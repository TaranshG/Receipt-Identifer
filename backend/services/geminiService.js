/**
 * Gemini AI Service
 * Handles receipt image analysis and fraud detection using Google's Gemini API
 */

const { GoogleGenerativeAI } = require('@google/generative-ai');
const { validateReceipt } = require('../utils/receiptUtils');

// --- Date helpers: safe "future date" detection (avoid timezone / parsing bugs) ---
function _parseReceiptDateToLocal(dateStr) {
  if (!dateStr) return null;

  // Accept "YYYY-MM-DD" or "YYYY-MM-DD HH:mm" or "YYYY-MM-DDTHH:mm"
  const m = String(dateStr).trim().match(/^(\d{4})-(\d{2})-(\d{2})(?:[ T](\d{2}):(\d{2}))?/);
  if (!m) return null;

  const y = Number(m[1]);
  const mo = Number(m[2]);
  const d = Number(m[3]);
  const hh = m[4] ? Number(m[4]) : 0;
  const mm = m[5] ? Number(m[5]) : 0;

  // Local time to avoid UTC shifting issues
  return new Date(y, mo - 1, d, hh, mm, 0, 0);
}

function isFutureReceiptDate(dateStr) {
  const receiptDate = _parseReceiptDateToLocal(dateStr);
  if (!receiptDate) return false;

  const now = new Date();
  const today = new Date(now.getFullYear(), now.getMonth(), now.getDate());

  // Allow tomorrow (timezone/processing edge cases)
  const tomorrow = new Date(today);
  tomorrow.setDate(today.getDate() + 1);

  return receiptDate > tomorrow;
}

function removeFutureDateReasons(reasons) {
  const rx = /(future|in the future)/i;
  return (reasons || []).filter((r) => !rx.test(String(r)));
}

class GeminiService {
  constructor(apiKey) {
    if (!apiKey) {
      throw new Error('Gemini API key is required');
    }

    this.genAI = new GoogleGenerativeAI(apiKey);

    // Use a supported model.
    this.model = this.genAI.getGenerativeModel({
      model: 'gemini-2.5-flash',
      generationConfig: {
        temperature: 0.1,
        topP: 0.8,
        topK: 20,
        maxOutputTokens: 2048,
      },
    });
  }

  /**
   * The core prompt engineering for receipt analysis
   */
  getAnalysisPrompt() {
    return `You are an expert receipt verification AI. Analyze this receipt image OR manual data and extract structured information.

Your job is to:
1. Extract key fields: merchant name, date/time, currency, subtotal, tax, total
2. Check arithmetic consistency (subtotal + tax should equal total)
3. Detect fraud indicators and assign a fraud_score (0-100, where 0=perfectly legit, 100=definitely fake)
4. Provide specific reasons for your verdict

CRITICAL REQUIREMENTS:
- Output ONLY valid JSON, no extra text
- Use these exact field names: merchant, date, currency, subtotal, tax, total, verdict, fraud_score, reasons, confidence
- verdict must be one of: "LIKELY_REAL", "SUSPICIOUS", "LIKELY_FAKE", "UNREADABLE"
- fraud_score is 0-100 (integer)
- reasons is an array of short strings
- confidence is 0.0-1.0 (float)

FRAUD INDICATORS (increase fraud_score):
- Arithmetic doesn't match (subtotal + tax ≠ total)
- Missing required fields (merchant, total)
- Suspicious formatting (weird fonts, inconsistent spacing)
- Date in the future or unreasonably old
- Unrealistic tax rates (<0% or >20%)
- Repeated decimal patterns (12.34, 12.34, 12.34)
- Generic merchant names like "Store" or "Shop"
- Rounded numbers for everything (10.00, 20.00, 30.00)

QUALITY INDICATORS (decrease fraud_score):
- All math checks out perfectly
- Merchant name is specific
- Date is recent and plausible
- Tax rate is reasonable (5-15% for most regions)
- Line items are detailed
- Receipt has unique identifiers (receipt #, transaction ID)

OUTPUT FORMAT (JSON only):
{
  "merchant": "Campus Mart",
  "date": "2026-02-07 14:12",
  "currency": "CAD",
  "subtotal": 12.49,
  "tax": 1.62,
  "total": 14.11,
  "verdict": "LIKELY_REAL",
  "fraud_score": 12,
  "reasons": [
    "Math is correct: 12.49 + 1.62 = 14.11",
    "Merchant name is specific",
    "Date is plausible and recent"
  ],
  "confidence": 0.87
}

Now analyze the receipt:`;
  }

  /**
   * Helper: remove markdown fences and trim
   */
  _stripFences(text) {
    if (!text) return '';
    return String(text)
      .replace(/```json\s*/gi, '')
      .replace(/```\s*/g, '')
      .trim();
  }

  /**
   * Helper: extract first balanced JSON object from text.
   * Robust against extra text before/after JSON.
   * Handles braces inside strings.
   */
  _extractFirstJsonObject(text) {
    const s = String(text || '');
    const start = s.indexOf('{');
    if (start === -1) return null;

    let depth = 0;
    let inString = false;
    let escape = false;

    for (let i = start; i < s.length; i++) {
      const ch = s[i];

      if (inString) {
        if (escape) {
          escape = false;
          continue;
        }
        if (ch === '\\') {
          escape = true;
          continue;
        }
        if (ch === '"') {
          inString = false;
          continue;
        }
        continue;
      } else {
        if (ch === '"') {
          inString = true;
          continue;
        }
        if (ch === '{') depth++;
        if (ch === '}') depth--;

        if (depth === 0) {
          // balanced object end
          return s.slice(start, i + 1);
        }
      }
    }

    // Not balanced (likely truncated)
    return s.slice(start); // return from first { to end as "candidate"
  }

  /**
   * Helper: attempt to repair truncated JSON by appending missing braces.
   * This won't fix *all* truncations, but it fixes the common “missing closing }” case.
   */
  _tryRepairAndParse(candidate) {
    if (!candidate) return null;

    let c = candidate.trim();

    // quick cleanup: remove trailing markdown fences just in case
    c = this._stripFences(c);

    // Try normal parse first
    try {
      return JSON.parse(c);
    } catch (_) {}

    // Try appending a few closing braces if JSON looks cut off
    // (common when model output truncates near the end)
    for (let i = 0; i < 6; i++) {
      c += '}';
      try {
        return JSON.parse(c);
      } catch (_) {}
    }

    return null;
  }

  /**
   * Creates a safe fallback result so the API never hard-crashes.
   */
  _fallbackUnreadable(rawText, reason) {
    const snippet = String(rawText || '').slice(0, 600);
    return {
      merchant: '',
      date: '',
      currency: 'CAD',
      subtotal: 0,
      tax: 0,
      total: 0,
      verdict: 'UNREADABLE',
      fraud_score: 95,
      reasons: [
        'Could not reliably parse AI output.',
        reason || 'AI output was malformed or truncated.',
        'Try a clearer photo or manual entry.',
      ],
      confidence: 0.2,
      // keep debug info for logs / optional UI (safe snippet only)
      _rawSnippet: snippet,
    };
  }

  /**
   * Analyzes a receipt from base64 image
   */
  async analyzeImage(imageBase64) {
    try {
      const base64Data = imageBase64.replace(/^data:image\/\w+;base64,/, '');

      const imagePart = {
        inlineData: {
          data: base64Data,
          mimeType: 'image/jpeg',
        },
      };

      const prompt = this.getAnalysisPrompt();

      const result = await this.model.generateContent([prompt, imagePart]);
      const response = await result.response;
      const text = response.text();

      return this.parseGeminiResponse(text);
    } catch (error) {
      console.error('Gemini image analysis error:', error);
      // Return safe payload instead of throwing (demo-safe)
      return this._fallbackUnreadable(null, `Gemini image analyze failed: ${error.message}`);
    }
  }

  /**
   * Analyzes manually entered receipt data
   */
  async analyzeManualData(receiptData) {
    try {
      const dataPrompt = `${this.getAnalysisPrompt()}

MANUAL DATA PROVIDED:
Merchant: ${receiptData.merchant || 'Not provided'}
Date: ${receiptData.date || 'Not provided'}
Currency: ${receiptData.currency || 'CAD'}
Subtotal: ${receiptData.subtotal || 0}
Tax: ${receiptData.tax || 0}
Total: ${receiptData.total || 0}

Analyze this data and provide your structured JSON response.`;

      const result = await this.model.generateContent(dataPrompt);
      const response = await result.response;
      const text = response.text();

      return this.parseGeminiResponse(text);
    } catch (error) {
      console.error('Gemini manual data analysis error:', error);
      return this._fallbackUnreadable(null, `Gemini manual analyze failed: ${error.message}`);
    }
  }

  /**
   * Parses Gemini's text response into structured JSON
   * Now tolerant to:
   * - markdown fences
   * - extra text
   * - truncated JSON (missing closing braces)
   * - occasional weird formatting
   *
   * IMPORTANT: does NOT throw. Returns UNREADABLE payload on failure.
   */
  parseGeminiResponse(text) {
    const raw = String(text || '');
    try {
      const cleaned = this._stripFences(raw);

      // Extract first JSON object (or candidate if truncated)
      const candidate = this._extractFirstJsonObject(cleaned);
      if (!candidate) {
        console.error('Failed to parse Gemini response (no JSON candidate):', raw);
        return this._fallbackUnreadable(raw, 'No JSON object found in model output.');
      }

      // Parse or repair
      const parsed = this._tryRepairAndParse(candidate);
      if (!parsed || typeof parsed !== 'object') {
        console.error('Failed to parse Gemini response (invalid JSON):', raw);
        return this._fallbackUnreadable(raw, 'Model returned invalid or truncated JSON.');
      }

      // Fill defaults / normalize
      const out = { ...parsed };

      out.merchant = String(out.merchant || '').trim();
      out.date = String(out.date || '').trim();
      out.currency = String(out.currency || 'CAD').trim().toUpperCase();

      out.subtotal = Number.parseFloat(out.subtotal ?? 0) || 0;
      out.tax = Number.parseFloat(out.tax ?? 0) || 0;
      out.total = Number.parseFloat(out.total ?? 0) || 0;

      out.fraud_score = Number.parseInt(out.fraud_score ?? 50, 10);
      if (!Number.isFinite(out.fraud_score)) out.fraud_score = 50;
      out.fraud_score = Math.max(0, Math.min(100, out.fraud_score));

      out.confidence = Number.parseFloat(out.confidence ?? 0.5);
      if (!Number.isFinite(out.confidence)) out.confidence = 0.5;
      out.confidence = Math.max(0, Math.min(1, out.confidence));

      const validVerdicts = ['LIKELY_REAL', 'SUSPICIOUS', 'LIKELY_FAKE', 'UNREADABLE'];
      out.verdict = String(out.verdict || 'SUSPICIOUS').trim().toUpperCase();
      if (!validVerdicts.includes(out.verdict)) out.verdict = 'SUSPICIOUS';

      if (!Array.isArray(out.reasons)) {
        out.reasons = out.reasons ? [String(out.reasons)] : [];
      }
      out.reasons = out.reasons.map((r) => String(r)).filter(Boolean);
      if (out.reasons.length === 0) out.reasons = ['No specific reasons provided.'];

      // If missing critical fields, degrade to UNREADABLE instead of throwing
      if (!out.total || !out.verdict || !Number.isFinite(out.fraud_score)) {
        return this._fallbackUnreadable(raw, 'Missing critical fields in model output.');
      }

      return out;
    } catch (error) {
      console.error('Failed to parse Gemini response (exception):', raw);
      return this._fallbackUnreadable(raw, `Parser exception: ${error.message}`);
    }
  }

  /**
   * Enhanced analysis that combines Gemini AI with local validation
   */
  async analyzeReceipt(input) {
    let geminiResult;

    if (typeof input === 'string') {
      geminiResult = await this.analyzeImage(input);
    } else {
      geminiResult = await this.analyzeManualData(input);
    }

    // --- FIX: If Gemini claims "future date" but local check says it's NOT future,
    // remove that reason and reduce fraud_score to prevent false HIGH RISK.
    const geminiSaidFuture =
      Array.isArray(geminiResult.reasons) &&
      geminiResult.reasons.some((r) => /(future|in the future)/i.test(String(r)));

    const actuallyFuture = isFutureReceiptDate(geminiResult.date);

    if (geminiSaidFuture && !actuallyFuture) {
      geminiResult.reasons = removeFutureDateReasons(geminiResult.reasons);

      // Reduce fraud score (Gemini likely inflated it due to the incorrect future-date signal)
      geminiResult.fraud_score = Math.max(0, (geminiResult.fraud_score || 0) - 35);

      // Add a transparent note so UI explains the correction
      geminiResult.reasons.push('✅ Date checked locally: not in the future (Gemini corrected).');
    }

    // If UNREADABLE, don't run strict validators that assume fields exist
    if (geminiResult.verdict === 'UNREADABLE') {
      return {
        ...geminiResult,
        validation: {
          isValid: false,
          issues: ['UNREADABLE: could not confidently extract receipt fields.'],
          warnings: [],
        },
      };
    }

    const localValidation = validateReceipt(geminiResult);

    let adjustedFraudScore = geminiResult.fraud_score;
    const enhancedReasons = [...(geminiResult.reasons || [])];

    if (!localValidation.isValid) {
      adjustedFraudScore = Math.min(100, adjustedFraudScore + 30);
      enhancedReasons.push(...localValidation.issues.map((issue) => `❌ ${issue}`));
    }

    if (localValidation.warnings.length > 0) {
      adjustedFraudScore = Math.min(100, adjustedFraudScore + 10);
      enhancedReasons.push(...localValidation.warnings.map((warn) => `⚠️ ${warn}`));
    }

    // If local validation is clean (no issues/warnings), clamp score so legit receipts don't become high-risk
    if (localValidation.isValid && localValidation.warnings.length === 0) {
      adjustedFraudScore = Math.min(adjustedFraudScore, 25);
    }

    let verdict = geminiResult.verdict;
    if (adjustedFraudScore >= 70) {
      verdict = 'LIKELY_FAKE';
    } else if (adjustedFraudScore >= 40) {
      verdict = 'SUSPICIOUS';
    } else if (adjustedFraudScore <= 25) {
      verdict = 'LIKELY_REAL';
    }

    return {
      ...geminiResult,
      fraud_score: adjustedFraudScore,
      verdict,
      reasons: enhancedReasons,
      validation: localValidation,
    };
  }
}

module.exports = GeminiService;
