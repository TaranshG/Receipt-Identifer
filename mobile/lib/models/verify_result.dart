class VerifyResult {
  final bool verified;
  final String message;
  final String? chainHash;
  final String? localHash;

  const VerifyResult({
    required this.verified,
    required this.message,
    this.chainHash,
    this.localHash,
  });

  factory VerifyResult.demoVerified() {
    return const VerifyResult(
      verified: true,
      message: 'VERIFIED: Receipt matches the certified fingerprint.',
      chainHash: 'abc123xyz789',
      localHash: 'abc123xyz789',
    );
  }

  factory VerifyResult.demoTampered() {
    return const VerifyResult(
      verified: false,
      message: 'NOT VERIFIED: Receipt differs from the certified fingerprint.',
      chainHash: 'abc123xyz789',
      localHash: 'different789',
    );
  }
}
