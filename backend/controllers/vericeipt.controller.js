/**
 * API Controllers
 * Handles all HTTP endpoints for Vericeipt backend
 */

const GeminiService = require('../services/geminiService');
const SolanaService = require('../services/solanaService');

// ✅ FIX: import the helpers you actually use
const {
  createCanonicalText,
  computeHash,
} = require('../utils/receiptUtils');

class VericeiptController {
  constructor(geminiApiKey, solanaRpcUrl, solanaPrivateKey) {
    this.geminiService = new GeminiService(geminiApiKey);
    this.solanaService = new SolanaService(solanaRpcUrl, solanaPrivateKey);
  }

  /**
   * ENDPOINT 1: POST /analyze
   */
  async analyzeReceipt(req, res) {
    try {
      const { imageBase64, merchant, date, currency, subtotal, tax, total } =
        req.body;

      // Validate input
      if (!imageBase64 && !merchant) {
        return res.status(400).json({
          success: false,
          error:
            'Either imageBase64 or manual receipt data (merchant, date, etc.) is required',
        });
      }

      console.log('📸 Analyzing receipt...');

      let analysis;

      // Route to appropriate analysis method
      if (imageBase64) {
        analysis = await this.geminiService.analyzeReceipt(imageBase64);
      } else {
        const manualData = { merchant, date, currency, subtotal, tax, total };
        analysis = await this.geminiService.analyzeReceipt(manualData);
      }

      // Generate canonical text and hash for convenience
      const canonicalText = createCanonicalText(analysis);
      const hash = computeHash(canonicalText);

      console.log('✅ Analysis complete');
      console.log(`   Verdict: ${analysis.verdict}`);
      console.log(`   Fraud Score: ${analysis.fraud_score}`);
      console.log(`   Hash: ${hash.substring(0, 16)}...`);

      return res.json({
        success: true,
        ...analysis,
        canonicalText,
        hash,
        timestamp: new Date().toISOString(),
      });
    } catch (error) {
      console.error('❌ Analysis error:', error);
      return res.status(500).json({
        success: false,
        error: error.message,
        details:
          'Failed to analyze receipt. Please check the image quality or manual data.',
      });
    }
  }

  /**
   * ENDPOINT 2: POST /certify
   */
  async certifyReceipt(req, res) {
    try {
      let { canonicalText, hash } = req.body;

      if (!canonicalText && !hash) {
        return res.status(400).json({
          success: false,
          error: 'Either canonicalText or hash is required',
        });
      }

      if (canonicalText && !hash) {
        hash = computeHash(canonicalText);
      }

      if (!/^[a-f0-9]{64}$/i.test(hash)) {
        return res.status(400).json({
          success: false,
          error: 'Invalid hash format - must be 64-character hex string',
        });
      }

      console.log('🔐 Certifying receipt on Solana...');
      console.log(`   Hash: ${hash.substring(0, 16)}...`);

      const result = await this.solanaService.certifyHash(hash, {
        source: 'vericeipt-api',
        certified_at: new Date().toISOString(),
      });

      console.log('✅ Certification successful');
      console.log(`   Transaction: ${result.txSignature}`);

      return res.json({
        success: true,
        txSignature: result.txSignature,
        chainHash: result.chainHash,
        timestamp: result.timestamp,
        explorerUrl: result.explorerUrl,
        walletAddress: result.walletAddress,
        message: '✅ Receipt certified successfully on Solana blockchain',
        proofId: result.txSignature,
      });
    } catch (error) {
      console.error('❌ Certification error:', error);
      return res.status(500).json({
        success: false,
        error: error.message,
        details:
          'Failed to certify receipt on blockchain. Please check your Solana configuration.',
      });
    }
  }

  /**
   * ENDPOINT 3: POST /verify
   */
  async verifyReceipt(req, res) {
    try {
      let { canonicalText, hash, txSignature } = req.body;

      if (!txSignature) {
        return res.status(400).json({
          success: false,
          error: 'txSignature (transaction signature) is required',
        });
      }

      if (!canonicalText && !hash) {
        return res.status(400).json({
          success: false,
          error: 'Either canonicalText or hash is required',
        });
      }

      if (canonicalText && !hash) {
        hash = computeHash(canonicalText);
      }

      console.log('🔍 Verifying receipt...');
      console.log(`   Transaction: ${txSignature}`);
      console.log(`   Local Hash: ${hash.substring(0, 16)}...`);

      const result = await this.solanaService.verifyHash(txSignature, hash);

      console.log(result.verified ? '✅ Verification PASSED' : '❌ Verification FAILED');

      return res.json({
        success: true,
        ...result,
      });
    } catch (error) {
      console.error('❌ Verification error:', error);
      return res.status(500).json({
        success: false,
        verified: false,
        error: error.message,
        details:
          'Failed to verify receipt. Please check the transaction signature.',
      });
    }
  }

  /**
   * BONUS ENDPOINT: GET /health
   */
  async healthCheck(req, res) {
    try {
      console.log('🏥 Running health check...');

      const solanaHealth = await this.solanaService.healthCheck();

      const geminiHealth = {
        connected: !!this.geminiService.model,
        model: 'gemini-1.5-flash',
      };

      const overallHealth = solanaHealth.connected && geminiHealth.connected;

      return res.json({
        success: true,
        healthy: overallHealth,
        timestamp: new Date().toISOString(),
        services: {
          gemini: geminiHealth,
          solana: solanaHealth,
        },
        version: '1.0.0',
        message: overallHealth ? '✅ All systems operational' : '⚠️ Some systems are down',
      });
    } catch (error) {
      console.error('❌ Health check error:', error);
      return res.status(503).json({
        success: false,
        healthy: false,
        error: error.message,
      });
    }
  }

  /**
   * BONUS ENDPOINT: POST /analyze-and-certify
   */
  async analyzeAndCertify(req, res) {
    try {
      const { imageBase64, merchant, date, currency, subtotal, tax, total, autoCertify } =
        req.body;

      console.log('📸 Step 1: Analyzing receipt...');

      let analysis;
      if (imageBase64) {
        analysis = await this.geminiService.analyzeReceipt(imageBase64);
      } else {
        const manualData = { merchant, date, currency, subtotal, tax, total };
        analysis = await this.geminiService.analyzeReceipt(manualData);
      }

      const canonicalText = createCanonicalText(analysis);
      const hash = computeHash(canonicalText);

      console.log(`   Verdict: ${analysis.verdict}, Fraud Score: ${analysis.fraud_score}`);

      let certification = null;

      if (autoCertify !== false && analysis.verdict === 'LIKELY_REAL' && analysis.fraud_score < 30) {
        console.log('🔐 Step 2: Auto-certifying receipt...');

        try {
          certification = await this.solanaService.certifyHash(hash, {
            source: 'vericeipt-auto-certify',
            analysis: {
              verdict: analysis.verdict,
              fraud_score: analysis.fraud_score,
            },
          });
          console.log('✅ Auto-certification successful');
        } catch (certError) {
          console.error('❌ Auto-certification failed:', certError.message);
        }
      } else {
        console.log('⏭️ Skipping auto-certification (fraud_score too high or not LIKELY_REAL)');
      }

      return res.json({
        success: true,
        analysis: {
          ...analysis,
          canonicalText,
          hash,
        },
        certification: certification || {
          certified: false,
          reason:
            analysis.fraud_score >= 30
              ? 'Fraud score too high for auto-certification'
              : 'Verdict is not LIKELY_REAL',
        },
        timestamp: new Date().toISOString(),
      });
    } catch (error) {
      console.error('❌ Analyze-and-certify error:', error);
      return res.status(500).json({
        success: false,
        error: error.message,
      });
    }
  }
}

module.exports = VericeiptController;
