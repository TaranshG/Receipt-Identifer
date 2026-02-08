/**
 * Vericeipt Backend Server
 * 
 * A hackathon-winning backend for AI-powered receipt verification with Solana certification
 * 
 * Features:
 * - Receipt analysis using Google Gemini AI
 * - Fraud detection and plausibility checks
 * - Blockchain certification on Solana
 * - Cryptographic verification of receipt integrity
 * 
 * Endpoints:
 * - POST /analyze - Analyze receipt with AI
 * - POST /certify - Certify receipt hash on blockchain
 * - POST /verify - Verify receipt against blockchain proof
 * - POST /analyze-and-certify - Combined workflow
 * - GET /health - System health check
 * 
 * Author: Vericeipt Team
 * Built for: Macathon 2026
 */

require('dotenv').config();
const express = require('express');
const cors = require('cors');
const helmet = require('helmet');
const morgan = require('morgan');
const rateLimit = require('express-rate-limit');

const VericeiptController = require('./controllers/vericeipt.controller');

// Initialize Express app
const app = express();
const PORT = process.env.PORT || 3000;

// =============================================================================
// MIDDLEWARE CONFIGURATION
// =============================================================================

// Security headers
app.use(helmet());

// CORS - Allow requests from Flutter app and web clients
const corsOptions = {
  origin: function (origin, callback) {
    // Allow requests with no origin (mobile apps, Postman, etc.)
    if (!origin) return callback(null, true);
    
    const allowedOrigins = process.env.ALLOWED_ORIGINS 
      ? process.env.ALLOWED_ORIGINS.split(',')
      : ['http://localhost:3000', 'http://localhost:8080'];
    
    if (allowedOrigins.indexOf(origin) !== -1 || allowedOrigins.includes('*')) {
      callback(null, true);
    } else {
      callback(null, true); // For hackathon, allow all origins
    }
  },
  credentials: true,
  methods: ['GET', 'POST', 'PUT', 'DELETE', 'OPTIONS'],
  allowedHeaders: ['Content-Type', 'Authorization']
};

app.use(cors(corsOptions));

// Request logging
app.use(morgan('dev'));

// Body parsing
app.use(express.json({ limit: '10mb' })); // Increase limit for base64 images
app.use(express.urlencoded({ extended: true, limit: '10mb' }));

// Rate limiting (protect against abuse)
const limiter = rateLimit({
  windowMs: parseInt(process.env.RATE_LIMIT_WINDOW_MS) || 15 * 60 * 1000, // 15 minutes
  max: parseInt(process.env.RATE_LIMIT_MAX_REQUESTS) || 100, // Limit each IP to 100 requests per window
  message: {
    success: false,
    error: 'Too many requests from this IP, please try again later.'
  },
  standardHeaders: true,
  legacyHeaders: false,
});

app.use('/analyze', limiter);
app.use('/certify', limiter);
app.use('/verify', limiter);

// =============================================================================
// INITIALIZE SERVICES
// =============================================================================

// Validate environment variables
const requiredEnvVars = ['GEMINI_API_KEY', 'SOLANA_RPC_URL'];
const missingEnvVars = requiredEnvVars.filter(varName => !process.env[varName]);

if (missingEnvVars.length > 0) {
  console.error('❌ Missing required environment variables:', missingEnvVars.join(', '));
  console.error('Please create a .env file with the required variables.');
  console.error('See .env.example for reference.');
  process.exit(1);
}

// Initialize controller with services
const controller = new VericeiptController(
  process.env.GEMINI_API_KEY,
  process.env.SOLANA_RPC_URL,
  process.env.SOLANA_PRIVATE_KEY
);

console.log('✅ Services initialized successfully');

// =============================================================================
// API ROUTES
// =============================================================================

/**
 * Welcome endpoint
 */
app.get('/', (req, res) => {
  res.json({
    name: 'Vericeipt API',
    version: '1.0.0',
    description: 'AI-powered receipt verification with Solana blockchain certification',
    endpoints: {
      analyze: {
        method: 'POST',
        path: '/analyze',
        description: 'Analyze a receipt using Gemini AI',
        accepts: ['imageBase64', 'manual data']
      },
      certify: {
        method: 'POST',
        path: '/certify',
        description: 'Certify a receipt hash on Solana blockchain',
        accepts: ['canonicalText', 'hash']
      },
      verify: {
        method: 'POST',
        path: '/verify',
        description: 'Verify receipt integrity against blockchain proof',
        accepts: ['canonicalText/hash', 'txSignature']
      },
      analyzeAndCertify: {
        method: 'POST',
        path: '/analyze-and-certify',
        description: 'Combined workflow: analyze then auto-certify if legitimate'
      },
      health: {
        method: 'GET',
        path: '/health',
        description: 'System health check'
      }
    },
    documentation: 'https://github.com/vericeipt/backend',
    hackathon: 'Macathon 2026',
    team: 'Vericeipt'
  });
});

/**
 * POST /analyze
 * Analyze receipt with Gemini AI
 */
app.post('/analyze', async (req, res) => {
  await controller.analyzeReceipt(req, res);
});

/**
 * POST /certify
 * Certify receipt hash on Solana blockchain
 */
app.post('/certify', async (req, res) => {
  await controller.certifyReceipt(req, res);
});

/**
 * POST /verify
 * Verify receipt against blockchain proof
 */
app.post('/verify', async (req, res) => {
  await controller.verifyReceipt(req, res);
});

/**
 * POST /analyze-and-certify
 * Combined workflow: analyze then certify
 */
app.post('/analyze-and-certify', async (req, res) => {
  await controller.analyzeAndCertify(req, res);
});

/**
 * GET /health
 * System health check
 */
app.get('/health', async (req, res) => {
  await controller.healthCheck(req, res);
});

// =============================================================================
// ERROR HANDLING
// =============================================================================

// 404 handler
app.use((req, res) => {
  res.status(404).json({
    success: false,
    error: 'Endpoint not found',
    path: req.path,
    method: req.method,
    availableEndpoints: ['/', '/analyze', '/certify', '/verify', '/analyze-and-certify', '/health']
  });
});

// Global error handler
app.use((err, req, res, next) => {
  console.error('❌ Unhandled error:', err);
  
  res.status(err.status || 500).json({
    success: false,
    error: err.message || 'Internal server error',
    ...(process.env.NODE_ENV === 'development' && { stack: err.stack })
  });
});

// =============================================================================
// START SERVER
// =============================================================================

app.listen(PORT, () => {
  console.log('');
  console.log('════════════════════════════════════════════════════════════════');
  console.log('🚀 Vericeipt Backend Server');
  console.log('════════════════════════════════════════════════════════════════');
  console.log(`📡 Server running on port ${PORT}`);
  console.log(`🌍 Environment: ${process.env.NODE_ENV || 'development'}`);
  console.log(`🔗 Local URL: http://localhost:${PORT}`);
  console.log('');
  console.log('📚 Available Endpoints:');
  console.log(`   POST   http://localhost:${PORT}/analyze`);
  console.log(`   POST   http://localhost:${PORT}/certify`);
  console.log(`   POST   http://localhost:${PORT}/verify`);
  console.log(`   POST   http://localhost:${PORT}/analyze-and-certify`);
  console.log(`   GET    http://localhost:${PORT}/health`);
  console.log('');
  console.log('✅ Services:');
  console.log('   🤖 Gemini AI: Configured');
  console.log(`   ⛓️  Solana: ${process.env.SOLANA_NETWORK || 'devnet'}`);
  console.log('');
  console.log('Press Ctrl+C to stop the server');
  console.log('════════════════════════════════════════════════════════════════');
  console.log('');
});

// Graceful shutdown
process.on('SIGTERM', () => {
  console.log('SIGTERM signal received: closing HTTP server');
  process.exit(0);
});

process.on('SIGINT', () => {
  console.log('\nSIGINT signal received: closing HTTP server');
  process.exit(0);
});

module.exports = app;
