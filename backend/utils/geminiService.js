/**
 * Gemini AI Service
 * Handles receipt image analysis and fraud detection using Google's Gemini API
 */

const { GoogleGenerativeAI } = require('@google/generative-ai');
const { validateReceipt } = require('../utils/receiptUtils');

class GeminiService {
  constructor(apiKey) {
    if (!apiKey) {
      throw new Error('Gemini API key is required');
    }
    
    this.genAI = new GoogleGenerativeAI(apiKey);
    this.model = this.genAI.getGenerativeModel({ 
      model: 'gemini-1.5-flash',
      generationConfig: {
        temperature: 0.1, // Low temperature for more consistent outputs
        topP: 0.8,
        topK: 20,
        maxOutputTokens: 2048,
      }
    });
  }

  /**
   * The core prompt engineering for receipt analysis
   * This is CRITICAL for hackathon success - we want structured, reliable outputs
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
   * Analyzes a receipt from base64 image
   * 
   * @param {string} imageBase64 - Base64 encoded image
   * @returns {Promise<Object>} Analysis results
   */
  async analyzeImage(imageBase64) {
    try {
      // Remove data URI prefix if present
      const base64Data = imageBase64.replace(/^data:image\/\w+;base64,/, '');
      
      const imagePart = {
        inlineData: {
          data: base64Data,
          mimeType: 'image/jpeg' // Assume JPEG, could detect dynamically
        }
      };

      const prompt = this.getAnalysisPrompt();
      
      const result = await this.model.generateContent([prompt, imagePart]);
      const response = await result.response;
      const text = response.text();
      
      return this.parseGeminiResponse(text);
    } catch (error) {
      console.error('Gemini image analysis error:', error);
      throw new Error(`Failed to analyze receipt image: ${error.message}`);
    }
  }

  /**
   * Analyzes manually entered receipt data
   * This is faster and more reliable for text-based input
   * 
   * @param {Object} receiptData - Manual receipt data
   * @returns {Promise<Object>} Analysis results
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
      throw new Error(`Failed to analyze receipt data: ${error.message}`);
    }
  }

  /**
   * Parses Gemini's text response into structured JSON
   * Handles edge cases where Gemini adds extra text
   * 
   * @param {string} text - Raw Gemini response
   * @returns {Object} Parsed receipt data
   */
  parseGeminiResponse(text) {
    try {
      // Extract JSON from response (Gemini sometimes wraps it in markdown)
      let jsonText = text.trim();
      
      // Remove markdown code blocks if present
      jsonText = jsonText.replace(/```json\n?/g, '').replace(/```\n?/g, '');
      
      // Find JSON object boundaries
      const startIdx = jsonText.indexOf('{');
      const endIdx = jsonText.lastIndexOf('}');
      
      if (startIdx === -1 || endIdx === -1) {
        throw new Error('No JSON object found in response');
      }
      
      jsonText = jsonText.substring(startIdx, endIdx + 1);
      
      const parsed = JSON.parse(jsonText);
      
      // Validate required fields
      const required = ['merchant', 'total', 'verdict', 'fraud_score', 'reasons'];
      for (const field of required) {
        if (!(field in parsed)) {
          throw new Error(`Missing required field: ${field}`);
        }
      }
      
      // Ensure numeric fields are numbers
      parsed.subtotal = parseFloat(parsed.subtotal || 0);
      parsed.tax = parseFloat(parsed.tax || 0);
      parsed.total = parseFloat(parsed.total || 0);
      parsed.fraud_score = parseInt(parsed.fraud_score || 50);
      parsed.confidence = parseFloat(parsed.confidence || 0.5);
      
      // Normalize verdict
      const validVerdicts = ['LIKELY_REAL', 'SUSPICIOUS', 'LIKELY_FAKE', 'UNREADABLE'];
      if (!validVerdicts.includes(parsed.verdict)) {
        parsed.verdict = 'SUSPICIOUS';
      }
      
      // Ensure reasons is an array
      if (!Array.isArray(parsed.reasons)) {
        parsed.reasons = [parsed.reasons || 'No specific reasons provided'];
      }
      
      return parsed;
    } catch (error) {
      console.error('Failed to parse Gemini response:', text);
      throw new Error(`Invalid Gemini response format: ${error.message}`);
    }
  }

  /**
   * Enhanced analysis that combines Gemini AI with local validation
   * This improves accuracy and provides better fraud detection
   * 
   * @param {string|Object} input - Either base64 image or receipt data object
   * @returns {Promise<Object>} Enhanced analysis results
   */
  async analyzeReceipt(input) {
    let geminiResult;
    
    // Determine if input is image or manual data
    if (typeof input === 'string') {
      geminiResult = await this.analyzeImage(input);
    } else {
      geminiResult = await this.analyzeManualData(input);
    }
    
    // Run local validation checks
    const localValidation = validateReceipt(geminiResult);
    
    // Adjust fraud score based on local validation
    let adjustedFraudScore = geminiResult.fraud_score;
    const enhancedReasons = [...geminiResult.reasons];
    
    if (!localValidation.isValid) {
      adjustedFraudScore = Math.min(100, adjustedFraudScore + 30);
      enhancedReasons.push(...localValidation.issues.map(issue => `❌ ${issue}`));
    }
    
    if (localValidation.warnings.length > 0) {
      adjustedFraudScore = Math.min(100, adjustedFraudScore + 10);
      enhancedReasons.push(...localValidation.warnings.map(warn => `⚠️ ${warn}`));
    }
    
    // Update verdict based on adjusted score
    let verdict = geminiResult.verdict;
    if (adjustedFraudScore >= 70) {
      verdict = 'LIKELY_FAKE';
    } else if (adjustedFraudScore >= 40) {
      verdict = 'SUSPICIOUS';
    } else if (adjustedFraudScore < 25) {
      verdict = 'LIKELY_REAL';
    }
    
    return {
      ...geminiResult,
      fraud_score: adjustedFraudScore,
      verdict,
      reasons: enhancedReasons,
      validation: localValidation
    };
  }
}

module.exports = GeminiService;
