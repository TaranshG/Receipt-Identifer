/**
 * Utility functions for receipt processing
 * Handles hashing, canonicalization, and validation
 */

const crypto = require('crypto');

/**
 * Creates a canonical text representation of receipt data
 * This ensures consistent hashing regardless of JSON key ordering
 * 
 * @param {Object} receiptData - Receipt data object
 * @returns {string} Canonical text representation
 */
function createCanonicalText(receiptData) {
  const {
    merchant = '',
    date = '',
    currency = 'CAD',
    subtotal = 0,
    tax = 0,
    total = 0,
    items = []
  } = receiptData;

  // Format numbers to 2 decimal places for consistency
  const formatNumber = (num) => {
    if (typeof num === 'string') {
      num = parseFloat(num);
    }
    return isNaN(num) ? '0.00' : num.toFixed(2);
  };

  // Build canonical text with strict ordering
  let canonical = '';
  canonical += `merchant=${merchant.trim()}\n`;
  canonical += `date=${date.trim()}\n`;
  canonical += `currency=${currency.toUpperCase()}\n`;
  canonical += `subtotal=${formatNumber(subtotal)}\n`;
  canonical += `tax=${formatNumber(tax)}\n`;
  canonical += `total=${formatNumber(total)}`;

  // Optional: include line items if present
  if (items && items.length > 0) {
    canonical += '\nitems=';
    const sortedItems = items
      .map(item => `${item.name}:${formatNumber(item.price)}:${item.quantity || 1}`)
      .sort()
      .join('|');
    canonical += sortedItems;
  }

  return canonical;
}

/**
 * Computes SHA-256 hash of canonical text
 * 
 * @param {string} canonicalText - Canonical receipt text
 * @returns {string} Hexadecimal hash string
 */
function computeHash(canonicalText) {
  return crypto
    .createHash('sha256')
    .update(canonicalText, 'utf8')
    .digest('hex');
}

/**
 * Validates arithmetic consistency of receipt
 * 
 * @param {number} subtotal 
 * @param {number} tax 
 * @param {number} total 
 * @returns {Object} { isValid: boolean, difference: number }
 */
function validateArithmetic(subtotal, tax, total) {
  const expectedTotal = parseFloat(subtotal) + parseFloat(tax);
  const actualTotal = parseFloat(total);
  const difference = Math.abs(expectedTotal - actualTotal);
  
  // Allow 0.02 tolerance for rounding
  const isValid = difference <= 0.02;
  
  return {
    isValid,
    difference: parseFloat(difference.toFixed(2)),
    expected: parseFloat(expectedTotal.toFixed(2)),
    actual: actualTotal
  };
}

/**
 * Validates date format and plausibility
 * 
 * @param {string} dateStr 
 * @returns {Object} { isValid: boolean, reason: string }
 */
function validateDate(dateStr) {
  if (!dateStr || dateStr.trim().length === 0) {
    return { isValid: false, reason: 'Date is missing' };
  }

  // Try to parse the date
  const date = new Date(dateStr);
  
  if (isNaN(date.getTime())) {
    return { isValid: false, reason: 'Date format is invalid' };
  }

  // Check if date is in the future
  const now = new Date();
  if (date > now) {
    return { isValid: false, reason: 'Date is in the future' };
  }

  // Check if date is unreasonably old (10 years)
  const tenYearsAgo = new Date();
  tenYearsAgo.setFullYear(now.getFullYear() - 10);
  
  if (date < tenYearsAgo) {
    return { isValid: false, reason: 'Date is too old (>10 years)' };
  }

  return { isValid: true, reason: 'Date is plausible' };
}

/**
 * Validates merchant name
 * 
 * @param {string} merchant 
 * @returns {Object} { isValid: boolean, reason: string }
 */
function validateMerchant(merchant) {
  if (!merchant || merchant.trim().length === 0) {
    return { isValid: false, reason: 'Merchant name is missing' };
  }

  if (merchant.trim().length < 2) {
    return { isValid: false, reason: 'Merchant name is too short' };
  }

  // Check for suspicious patterns (all caps, repeated characters)
  const hasOnlyRepeated = /^(.)\1+$/.test(merchant.trim());
  if (hasOnlyRepeated) {
    return { isValid: false, reason: 'Merchant name appears suspicious' };
  }

  return { isValid: true, reason: 'Merchant name is valid' };
}

/**
 * Validates currency code
 * 
 * @param {string} currency 
 * @returns {Object} { isValid: boolean, reason: string }
 */
function validateCurrency(currency) {
  const validCurrencies = ['CAD', 'USD', 'EUR', 'GBP', 'JPY', 'AUD'];
  
  if (!currency || currency.trim().length === 0) {
    return { isValid: true, reason: 'Currency defaults to CAD' }; // Default
  }

  if (!validCurrencies.includes(currency.toUpperCase())) {
    return { isValid: false, reason: `Currency ${currency} not recognized` };
  }

  return { isValid: true, reason: 'Currency is valid' };
}

/**
 * Comprehensive receipt validation
 * Returns validation results with reasons
 * 
 * @param {Object} receiptData 
 * @returns {Object} Validation results
 */
function validateReceipt(receiptData) {
  const results = {
    isValid: true,
    issues: [],
    warnings: []
  };

  // Validate merchant
  const merchantCheck = validateMerchant(receiptData.merchant);
  if (!merchantCheck.isValid) {
    results.isValid = false;
    results.issues.push(merchantCheck.reason);
  }

  // Validate date
  const dateCheck = validateDate(receiptData.date);
  if (!dateCheck.isValid) {
    results.warnings.push(dateCheck.reason);
  }

  // Validate currency
  const currencyCheck = validateCurrency(receiptData.currency);
  if (!currencyCheck.isValid) {
    results.warnings.push(currencyCheck.reason);
  }

  // Validate arithmetic
  const arithmeticCheck = validateArithmetic(
    receiptData.subtotal,
    receiptData.tax,
    receiptData.total
  );
  
  if (!arithmeticCheck.isValid) {
    results.isValid = false;
    results.issues.push(
      `Math error: ${arithmeticCheck.expected} expected but got ${arithmeticCheck.actual}`
    );
  }

  // Check for negative values
  if (receiptData.subtotal < 0 || receiptData.tax < 0 || receiptData.total < 0) {
    results.isValid = false;
    results.issues.push('Negative values detected');
  }

  // Check for unreasonably large values (>$10,000)
  if (receiptData.total > 10000) {
    results.warnings.push('Total exceeds $10,000 - please verify');
  }

  return results;
}

/**
 * Formats a number as currency
 * 
 * @param {number} amount 
 * @param {string} currency 
 * @returns {string}
 */
function formatCurrency(amount, currency = 'CAD') {
  const formatter = new Intl.NumberFormat('en-CA', {
    style: 'currency',
    currency: currency,
    minimumFractionDigits: 2,
    maximumFractionDigits: 2
  });
  
  return formatter.format(amount);
}

module.exports = {
  createCanonicalText,
  computeHash,
  validateArithmetic,
  validateDate,
  validateMerchant,
  validateCurrency,
  validateReceipt,
  formatCurrency
};
