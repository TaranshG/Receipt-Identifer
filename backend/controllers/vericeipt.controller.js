// backend/controllers/vericeipt.controller.js

const GeminiService = require("../services/geminiService");
const SolanaService = require("../services/solanaService");
const ProofStore = require("../services/proofStore");

const { createCanonicalText, computeHash } = require("../utils/receiptUtils");

class VericeiptController {
  constructor(geminiApiKey, solanaRpcUrl, solanaPrivateKey) {
    this.geminiService = new GeminiService(geminiApiKey);
    this.solanaService = new SolanaService(solanaRpcUrl, solanaPrivateKey);
  }

  /**
   * Canonicalize text to eliminate "false mismatches"
   * - merchant lower
   * - currency upper
   * - numeric fields forced to 2dp where possible
   */
  _normalizeCanonicalText(text) {
    if (!text || typeof text !== "string") return text;

    const map = {};
    for (const line of text.split("\n")) {
      const idx = line.indexOf("=");
      if (idx <= 0) continue;
      const k = line.substring(0, idx).trim();
      const v = line.substring(idx + 1).trim();
      map[k] = v;
    }

    const norm = (k, v) => {
      if (v == null) return "";
      if (k === "merchant") return String(v).trim().toLowerCase();
      if (k === "currency") return String(v).trim().toUpperCase();
      if (["subtotal", "tax", "total"].includes(k)) {
        const n = Number(String(v).trim());
        if (Number.isFinite(n)) return n.toFixed(2);
        return String(v).trim();
      }
      return String(v).trim();
    };

    const orderedKeys = ["merchant", "date", "currency", "subtotal", "tax", "total"];
    const out = [];
    for (const k of orderedKeys) {
      if (map[k] !== undefined) out.push(`${k}=${norm(k, map[k])}`);
    }

    // Preserve any extra fields deterministically (rare, but safe)
    const extras = Object.keys(map)
      .filter((k) => !orderedKeys.includes(k))
      .sort();
    for (const k of extras) out.push(`${k}=${norm(k, map[k])}`);

    return out.join("\n");
  }

  // POST /analyze
  async analyzeReceipt(req, res) {
    try {
      const { imageBase64, merchant, date, currency, subtotal, tax, total } = req.body;

      if (!imageBase64 && !merchant) {
        return res.status(400).json({
          success: false,
          error: "Either imageBase64 or manual receipt data is required",
        });
      }

      let analysis;
      if (imageBase64) {
        analysis = await this.geminiService.analyzeReceipt(imageBase64);
      } else {
        const manualData = { merchant, date, currency, subtotal, tax, total };
        analysis = await this.geminiService.analyzeReceipt(manualData);
      }

      // create canonical, normalize it, hash it
      const canonicalRaw = createCanonicalText(analysis);
      const canonicalText = this._normalizeCanonicalText(canonicalRaw);
      const hash = computeHash(canonicalText);

      return res.json({
        success: true,
        ...analysis,
        canonicalText,
        hash,
        timestamp: new Date().toISOString(),
      });
    } catch (error) {
      console.error("❌ Analysis error:", error);
      return res.status(500).json({
        success: false,
        error: error.message,
      });
    }
  }

  // POST /certify
  async certifyReceipt(req, res) {
    try {
      let { canonicalText, hash, analysisSummary } = req.body;

      if (!canonicalText && !hash) {
        return res.status(400).json({
          success: false,
          error: "Either canonicalText or hash is required",
        });
      }

      // Normalize canonicalText before hashing/storing
      if (canonicalText) canonicalText = this._normalizeCanonicalText(canonicalText);

      if (canonicalText && !hash) hash = computeHash(canonicalText);

      if (!/^[a-f0-9]{64}$/i.test(hash)) {
        return res.status(400).json({
          success: false,
          error: "Invalid hash format - must be 64-character hex string",
        });
      }

      // 1) certify on Solana
      const chain = await this.solanaService.certifyHash(hash, {
        source: "vericeipt-api",
        certified_at: new Date().toISOString(),
      });

      // 2) store canonical text off-chain for forensics + duplicate detection
      const storeResult = ProofStore.upsertProof({
        hash,
        txSignature: chain.txSignature,
        canonicalText: canonicalText || null,
        analysisSummary: analysisSummary || {},
      });

      return res.json({
        success: true,
        txSignature: chain.txSignature,
        chainHash: chain.chainHash,
        timestamp: chain.timestamp,
        explorerUrl: chain.explorerUrl,
        walletAddress: chain.walletAddress,

        // WOW fields
        duplicate: storeResult.duplicate,
        firstSeenTx: storeResult.firstSeenTx,
        firstSeenAt: storeResult.firstSeenAt,
        seenCount: storeResult.seenCount,

        message: storeResult.duplicate
          ? "⚠️ Certified, but this receipt hash was seen before (possible duplicate claim)"
          : "✅ Receipt certified successfully on Solana",
      });
    } catch (error) {
      console.error("❌ Certification error:", error);
      return res.status(500).json({
        success: false,
        error: error.message,
      });
    }
  }

  // POST /verify
  async verifyReceipt(req, res) {
    try {
      let { canonicalText, hash, txSignature } = req.body;

      if (!txSignature) {
        return res.status(400).json({
          success: false,
          error: "txSignature is required",
        });
      }

      if (!canonicalText && !hash) {
        return res.status(400).json({
          success: false,
          error: "Either canonicalText or hash is required",
        });
      }

      // Normalize canonicalText BEFORE hashing so user formatting doesn't break verification
      if (canonicalText) canonicalText = this._normalizeCanonicalText(canonicalText);

      if (canonicalText && !hash) hash = computeHash(canonicalText);

      const chainResult = await this.solanaService.verifyHash(txSignature, hash);

      // Look up what was originally certified (for forensic diff)
      const storedByTx = ProofStore.getByTx(txSignature);
      let chainCanonicalText = storedByTx?.canonicalText || null;

      // If missing, try by chain hash
      if (!chainCanonicalText && chainResult.chainHash) {
        const storedByHash = ProofStore.getByHash(chainResult.chainHash);
        chainCanonicalText = storedByHash?.canonicalText || null;
      }

      // Normalize the stored canonical too (just in case early versions stored raw)
      if (chainCanonicalText) chainCanonicalText = this._normalizeCanonicalText(chainCanonicalText);

      // Ensure explorerUrl exists even if verifyHash returns an error path
      const explorerUrl =
        chainResult.explorerUrl ||
        (this.solanaService._explorerTxUrl ? this.solanaService._explorerTxUrl(txSignature) : null);

      return res.json({
        success: true,
        ...chainResult,
        explorerUrl,

        // WOW fields for UI forensic replay
        chainCanonicalText,
        localCanonicalText: canonicalText || null,
      });
    } catch (error) {
      console.error("❌ Verification error:", error);
      return res.status(500).json({
        success: false,
        verified: false,
        error: error.message,
      });
    }
  }

  // GET /health
  async healthCheck(req, res) {
    try {
      const solanaHealth = await this.solanaService.healthCheck();
      const geminiHealth = {
        connected: !!this.geminiService.model,
        model: "gemini-1.5-flash",
      };

      return res.json({
        success: true,
        healthy: solanaHealth.connected && geminiHealth.connected,
        timestamp: new Date().toISOString(),
        services: { gemini: geminiHealth, solana: solanaHealth },
      });
    } catch (error) {
      return res.status(503).json({
        success: false,
        healthy: false,
        error: error.message,
      });
    }
  }

  // POST /analyze-and-certify (not used for demo)
  async analyzeAndCertify(req, res) {
    return res.status(501).json({
      success: false,
      error: "Not used for the hackathon demo. Use /analyze then /certify.",
    });
  }
}

module.exports = VericeiptController;
