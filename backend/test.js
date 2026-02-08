/**
 * Vericeipt Backend Test Script
 * 
 * This script tests all API endpoints to ensure everything works correctly
 * Run with: node src/test.js
 */

const axios = require('axios').default || require('axios');
const crypto = require('crypto');

const BASE_URL = process.env.BASE_URL || 'http://localhost:3000';

// Test data
const testReceipt = {
  merchant: 'Campus Mart',
  date: '2026-02-07 14:30',
  currency: 'CAD',
  subtotal: 12.49,
  tax: 1.62,
  total: 14.11
};

const fraudulentReceipt = {
  merchant: 'Suspicious Store',
  date: '2030-12-31 23:59', // Future date
  currency: 'CAD',
  subtotal: 100.00,
  tax: 5.00,
  total: 200.00 // Math doesn't add up
};

// Helper function to create canonical text
function createCanonicalText(receipt) {
  const formatNumber = (num) => parseFloat(num).toFixed(2);
  
  let canonical = '';
  canonical += `merchant=${receipt.merchant.trim()}\n`;
  canonical += `date=${receipt.date.trim()}\n`;
  canonical += `currency=${receipt.currency.toUpperCase()}\n`;
  canonical += `subtotal=${formatNumber(receipt.subtotal)}\n`;
  canonical += `tax=${formatNumber(receipt.tax)}\n`;
  canonical += `total=${formatNumber(receipt.total)}`;
  
  return canonical;
}

function computeHash(text) {
  return crypto.createHash('sha256').update(text, 'utf8').digest('hex');
}

// Color output helpers
const colors = {
  reset: '\x1b[0m',
  green: '\x1b[32m',
  red: '\x1b[31m',
  yellow: '\x1b[33m',
  blue: '\x1b[34m',
  cyan: '\x1b[36m'
};

function log(message, color = 'reset') {
  console.log(`${colors[color]}${message}${colors.reset}`);
}

// Test functions
async function testHealthCheck() {
  log('\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━', 'cyan');
  log('TEST 1: Health Check', 'cyan');
  log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━', 'cyan');
  
  try {
    const response = await axios.get(`${BASE_URL}/health`);
    log('✅ Health check passed', 'green');
    console.log('Response:', JSON.stringify(response.data, null, 2));
    return true;
  } catch (error) {
    log('❌ Health check failed', 'red');
    console.error('Error:', error.message);
    return false;
  }
}

async function testAnalyzeLegitReceipt() {
  log('\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━', 'cyan');
  log('TEST 2: Analyze Legitimate Receipt', 'cyan');
  log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━', 'cyan');
  
  try {
    const response = await axios.post(`${BASE_URL}/analyze`, testReceipt);
    
    if (response.data.success && response.data.verdict === 'LIKELY_REAL') {
      log('✅ Legitimate receipt analyzed correctly', 'green');
      log(`   Verdict: ${response.data.verdict}`, 'green');
      log(`   Fraud Score: ${response.data.fraud_score}`, 'green');
      log(`   Confidence: ${response.data.confidence}`, 'green');
      console.log('   Reasons:', response.data.reasons);
      return response.data;
    } else {
      log('⚠️  Unexpected verdict for legitimate receipt', 'yellow');
      console.log('Response:', JSON.stringify(response.data, null, 2));
      return response.data;
    }
  } catch (error) {
    log('❌ Analysis failed', 'red');
    console.error('Error:', error.response?.data || error.message);
    return null;
  }
}

async function testAnalyzeFraudulentReceipt() {
  log('\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━', 'cyan');
  log('TEST 3: Analyze Fraudulent Receipt', 'cyan');
  log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━', 'cyan');
  
  try {
    const response = await axios.post(`${BASE_URL}/analyze`, fraudulentReceipt);
    
    if (response.data.success && response.data.fraud_score > 50) {
      log('✅ Fraudulent receipt detected correctly', 'green');
      log(`   Verdict: ${response.data.verdict}`, 'green');
      log(`   Fraud Score: ${response.data.fraud_score}`, 'green');
      console.log('   Reasons:', response.data.reasons);
      return response.data;
    } else {
      log('⚠️  Fraudulent receipt not detected', 'yellow');
      console.log('Response:', JSON.stringify(response.data, null, 2));
      return response.data;
    }
  } catch (error) {
    log('❌ Analysis failed', 'red');
    console.error('Error:', error.response?.data || error.message);
    return null;
  }
}

async function testCertifyReceipt(analysisResult) {
  log('\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━', 'cyan');
  log('TEST 4: Certify Receipt on Solana', 'cyan');
  log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━', 'cyan');
  
  try {
    const canonicalText = analysisResult.canonicalText;
    
    const response = await axios.post(`${BASE_URL}/certify`, {
      canonicalText
    });
    
    if (response.data.success && response.data.txSignature) {
      log('✅ Receipt certified on blockchain', 'green');
      log(`   Transaction: ${response.data.txSignature}`, 'green');
      log(`   Hash: ${response.data.chainHash.substring(0, 32)}...`, 'green');
      console.log(`   Explorer: ${response.data.explorerUrl}`);
      return response.data;
    } else {
      log('⚠️  Certification incomplete', 'yellow');
      console.log('Response:', JSON.stringify(response.data, null, 2));
      return response.data;
    }
  } catch (error) {
    log('❌ Certification failed', 'red');
    console.error('Error:', error.response?.data || error.message);
    return null;
  }
}

async function testVerifyReceipt(certificationResult, analysisResult) {
  log('\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━', 'cyan');
  log('TEST 5: Verify Receipt (Should Pass)', 'cyan');
  log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━', 'cyan');
  
  try {
    const response = await axios.post(`${BASE_URL}/verify`, {
      canonicalText: analysisResult.canonicalText,
      txSignature: certificationResult.txSignature
    });
    
    if (response.data.verified) {
      log('✅ Verification passed - receipt is authentic', 'green');
      log(`   Message: ${response.data.message}`, 'green');
      return true;
    } else {
      log('⚠️  Verification failed unexpectedly', 'yellow');
      console.log('Response:', JSON.stringify(response.data, null, 2));
      return false;
    }
  } catch (error) {
    log('❌ Verification request failed', 'red');
    console.error('Error:', error.response?.data || error.message);
    return false;
  }
}

async function testVerifyAlteredReceipt(certificationResult) {
  log('\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━', 'cyan');
  log('TEST 6: Verify Altered Receipt (Should Fail)', 'cyan');
  log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━', 'cyan');
  
  try {
    // Create an altered version
    const alteredReceipt = { ...testReceipt, total: 999.99 };
    const alteredCanonical = createCanonicalText(alteredReceipt);
    
    const response = await axios.post(`${BASE_URL}/verify`, {
      canonicalText: alteredCanonical,
      txSignature: certificationResult.txSignature
    });
    
    if (!response.data.verified) {
      log('✅ Tamper detection works - altered receipt rejected', 'green');
      log(`   Message: ${response.data.message}`, 'green');
      return true;
    } else {
      log('⚠️  Altered receipt was not detected!', 'red');
      console.log('Response:', JSON.stringify(response.data, null, 2));
      return false;
    }
  } catch (error) {
    log('❌ Verification request failed', 'red');
    console.error('Error:', error.response?.data || error.message);
    return false;
  }
}

async function testAnalyzeAndCertify() {
  log('\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━', 'cyan');
  log('TEST 7: Combined Analyze & Certify', 'cyan');
  log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━', 'cyan');
  
  try {
    const response = await axios.post(`${BASE_URL}/analyze-and-certify`, {
      ...testReceipt,
      autoCertify: true
    });
    
    if (response.data.success && response.data.certification?.certified !== false) {
      log('✅ Combined workflow successful', 'green');
      log(`   Analysis Verdict: ${response.data.analysis.verdict}`, 'green');
      if (response.data.certification.txSignature) {
        log(`   Certified: Yes`, 'green');
        log(`   Transaction: ${response.data.certification.txSignature}`, 'green');
      }
      return response.data;
    } else {
      log('⚠️  Combined workflow incomplete', 'yellow');
      console.log('Response:', JSON.stringify(response.data, null, 2));
      return response.data;
    }
  } catch (error) {
    log('❌ Combined workflow failed', 'red');
    console.error('Error:', error.response?.data || error.message);
    return null;
  }
}

// Main test runner
async function runAllTests() {
  log('\n╔═══════════════════════════════════════════════════════════════╗', 'blue');
  log('║         VERICEIPT BACKEND - COMPREHENSIVE TEST SUITE         ║', 'blue');
  log('╚═══════════════════════════════════════════════════════════════╝', 'blue');
  log(`\n🎯 Target: ${BASE_URL}`, 'blue');
  log('⏱️  Starting tests...\n', 'blue');

  const results = {
    passed: 0,
    failed: 0,
    total: 7
  };

  // Test 1: Health Check
  const healthOk = await testHealthCheck();
  healthOk ? results.passed++ : results.failed++;

  if (!healthOk) {
    log('\n⚠️  Server is not healthy. Stopping tests.', 'red');
    process.exit(1);
  }

  // Test 2: Analyze legitimate receipt
  const legitimateAnalysis = await testAnalyzeLegitReceipt();
  legitimateAnalysis ? results.passed++ : results.failed++;

  // Test 3: Analyze fraudulent receipt
  const fraudulentAnalysis = await testAnalyzeFraudulentReceipt();
  fraudulentAnalysis ? results.passed++ : results.failed++;

  if (!legitimateAnalysis) {
    log('\n⚠️  Cannot proceed with certification tests without successful analysis.', 'yellow');
    process.exit(1);
  }

  // Test 4: Certify receipt
  const certification = await testCertifyReceipt(legitimateAnalysis);
  certification?.txSignature ? results.passed++ : results.failed++;

  if (!certification?.txSignature) {
    log('\n⚠️  Cannot proceed with verification tests without successful certification.', 'yellow');
    
    // Print summary and exit
    log('\n╔═══════════════════════════════════════════════════════════════╗', 'blue');
    log('║                        TEST SUMMARY                           ║', 'blue');
    log('╚═══════════════════════════════════════════════════════════════╝', 'blue');
    log(`\n✅ Passed: ${results.passed}/${results.total}`, results.passed === results.total ? 'green' : 'yellow');
    log(`❌ Failed: ${results.failed}/${results.total}\n`, results.failed > 0 ? 'red' : 'green');
    
    process.exit(results.failed > 0 ? 1 : 0);
  }

  // Test 5: Verify unaltered receipt
  const verificationOk = await testVerifyReceipt(certification, legitimateAnalysis);
  verificationOk ? results.passed++ : results.failed++;

  // Test 6: Verify altered receipt (should fail)
  const tamperDetectionOk = await testVerifyAlteredReceipt(certification);
  tamperDetectionOk ? results.passed++ : results.failed++;

  // Test 7: Combined workflow
  const combinedOk = await testAnalyzeAndCertify();
  combinedOk ? results.passed++ : results.failed++;

  // Print summary
  log('\n╔═══════════════════════════════════════════════════════════════╗', 'blue');
  log('║                        TEST SUMMARY                           ║', 'blue');
  log('╚═══════════════════════════════════════════════════════════════╝', 'blue');
  log(`\n✅ Passed: ${results.passed}/${results.total}`, results.passed === results.total ? 'green' : 'yellow');
  log(`❌ Failed: ${results.failed}/${results.total}\n`, results.failed > 0 ? 'red' : 'green');

  if (results.passed === results.total) {
    log('🎉 All tests passed! Backend is ready for the hackathon! 🚀\n', 'green');
  } else {
    log('⚠️  Some tests failed. Please review the errors above.\n', 'yellow');
  }

  process.exit(results.failed > 0 ? 1 : 0);
}

// Run tests
runAllTests().catch(error => {
  log('\n❌ Test suite crashed:', 'red');
  console.error(error);
  process.exit(1);
});
