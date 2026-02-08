// lib/services/receipt_service.dart

import 'dart:convert';
import '../../../models/receipt_analysis.dart';
import '../../../models/verify_result.dart';
import '../../../models/receipt_input.dart';

/// Central service interface for Gemini AI and Solana integration.
/// Person 1 (UI) calls these functions.
/// Person 2 (Gemini) implements analyzeReceipt with TEXT prompts (no image).
/// Person 3 (Solana) implements certifyReceipt and verifyReceipt.
class ReceiptService {
  /// Analyze receipt fields using Gemini AI (TEXT-BASED).
  /// Since Gemini free tier doesn't support images, we send structured text.
  /// 
  /// IMPLEMENTATION: Person 2 will replace this with actual Gemini API call.
  static Future<ReceiptAnalysis> analyzeReceipt(ReceiptInput input) async {
    // Simulate network delay for realism
    await Future.delayed(const Duration(seconds: 2));

    // TODO (Person 2): Replace with real Gemini TEXT call
    // Prompt structure:
    // "Analyze this receipt for fraud/inconsistencies:
    //  Merchant: ${input.merchant}
    //  Date: ${input.date}
    //  Subtotal: ${input.subtotal}
    //  Tax: ${input.tax}
    //  Total: ${input.total}
    //  
    //  Check if subtotal + tax = total.
    //  Return JSON with verdict, fraud_score, reasons."
    
    // For demo: simulate different verdicts based on input
    final subtotal = input.subtotal;
    final tax = input.tax;
    final total = input.total;
    final expectedTotal = subtotal + tax;
    final diff = (total - expectedTotal).abs();
    
    if (diff < 0.03) {
      // Math checks out
      return ReceiptAnalysis(
        merchant: input.merchant,
        date: input.date,
        currency: input.currency,
        subtotal: subtotal,
        tax: tax,
        total: total,
        verdict: 'LIKELY_REAL',
        fraudScore: 8,
        reasons: [
          'Subtotal + tax matches total (within rounding).',
          'All required fields present.',
          'No obvious tampering detected.',
        ],
        confidence: 0.89,
      );
    } else {
      // Math doesn't add up
      return ReceiptAnalysis(
        merchant: input.merchant,
        date: input.date,
        currency: input.currency,
        subtotal: subtotal,
        tax: tax,
        total: total,
        verdict: 'SUSPICIOUS',
        fraudScore: 91,
        reasons: [
          'Total does not equal subtotal + tax.',
          'Difference of \$${diff.toStringAsFixed(2)} detected.',
          'Recommend manual review.',
        ],
        confidence: 0.85,
      );
    }
  }

  /// Certify a receipt by anchoring its hash on Solana.
  /// Returns the transaction signature (proof ID).
  /// 
  /// IMPLEMENTATION: Person 3 will replace this with actual Solana transaction.
  static Future<String> certifyReceipt(ReceiptAnalysis analysis) async {
    // Simulate blockchain tx delay
    await Future.delayed(const Duration(seconds: 3));

    // TODO (Person 3): 
    // 1. Compute canonical hash from analysis
    // 2. Submit transaction to Solana
    // 3. Return real tx signature
    
    // For now: return demo signature
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    return 'SOLANA_TX_${timestamp}_${analysis.total.toStringAsFixed(2).replaceAll('.', '')}';
  }

  /// Verify a receipt against its on-chain proof.
  /// Recomputes the hash from new input and compares to the hash stored in txSignature.
  /// 
  /// IMPLEMENTATION: Person 2 + Person 3 will collaborate:
  /// - Person 2: extract/validate receipt fields from new input
  /// - Person 3: fetch on-chain hash and compare
  static Future<VerifyResult> verifyReceipt(
    ReceiptInput input,
    String txSignature,
  ) async {
    // Simulate verification process
    await Future.delayed(const Duration(seconds: 2));

    // TODO (Person 2 + 3):
    // 1. Compute canonical hash from input
    // 2. Fetch on-chain hash from txSignature (Solana)
    // 3. Compare hashes
    // 4. Return detailed result with mismatch explanation

    // For demo: parse total from tx signature and compare
    // In real implementation, you'd compare cryptographic hashes
    try {
      final parts = txSignature.split('_');
      if (parts.length >= 3) {
        final storedTotal = parts.last;
        final inputTotal = input.total.toStringAsFixed(2).replaceAll('.', '');
        
        if (storedTotal == inputTotal) {
          return VerifyResult(
            verified: true,
            message: 'VERIFIED: Receipt matches the certified fingerprint.',
            chainHash: 'hash_$storedTotal',
            localHash: 'hash_$inputTotal',
          );
        } else {
          return VerifyResult(
            verified: false,
            message: 'NOT VERIFIED: Total differs from certified version.',
            chainHash: 'hash_$storedTotal',
            localHash: 'hash_$inputTotal',
          );
        }
      }
    } catch (e) {
      // Fallback for invalid tx signatures
    }

    // Default demo result
    return VerifyResult(
      verified: true,
      message: 'VERIFIED: Receipt matches the certified fingerprint.',
      chainHash: 'abc123...demo',
      localHash: 'abc123...demo',
    );
  }
}
