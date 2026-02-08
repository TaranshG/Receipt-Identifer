/**
 * Solana Service
 * Handles blockchain interactions for receipt certification and verification
 *
 * CORE: Use Solana memo as a public notary for receipt integrity.
 */

const {
  Connection,
  Keypair,
  Transaction,
  TransactionInstruction,
  PublicKey,
  sendAndConfirmTransaction,
  LAMPORTS_PER_SOL,
} = require("@solana/web3.js");
const bs58 = require("bs58");

class SolanaService {
  constructor(rpcUrl, privateKeyBase58) {
    if (!rpcUrl) throw new Error("Solana RPC URL is required");

    this.connection = new Connection(rpcUrl, "confirmed");
    this.rpcUrl = rpcUrl;

    // cluster inference from RPC (devnet/testnet/mainnet-beta)
    this.cluster = this._inferClusterFromRpc(rpcUrl);

    if (privateKeyBase58) {
      try {
        const privateKeyBytes = bs58.decode(privateKeyBase58);
        this.wallet = Keypair.fromSecretKey(privateKeyBytes);
        console.log("✅ Solana wallet initialized:", this.wallet.publicKey.toString());
      } catch (error) {
        console.error("❌ Failed to initialize Solana wallet:", error.message);
        throw new Error("Invalid Solana private key format");
      }
    } else {
      console.warn("⚠️ No Solana private key provided - generating temporary keypair");
      this.wallet = Keypair.generate();
    }
  }

  _inferClusterFromRpc(rpcUrl) {
    const u = (rpcUrl || "").toLowerCase();
    if (u.includes("devnet")) return "devnet";
    if (u.includes("testnet")) return "testnet";
    // common mainnet identifiers
    if (u.includes("mainnet") || u.includes("mainnet-beta")) return "mainnet-beta";
    // if unknown (custom RPC), default to devnet for hackathon demos
    return "devnet";
  }

  _explorerTxUrl(signature) {
    const clusterParam = this.cluster === "mainnet-beta" ? "" : `?cluster=${this.cluster}`;
    return `https://explorer.solana.com/tx/${signature}${clusterParam}`;
  }

  /**
   * Get wallet balance in SOL
   */
  async getBalance() {
    try {
      const balance = await this.connection.getBalance(this.wallet.publicKey);
      return balance / LAMPORTS_PER_SOL;
    } catch (error) {
      console.error("Failed to get balance:", error);
      return 0;
    }
  }

  /**
   * Request airdrop on devnet/testnet (for testing)
   */
  async requestAirdrop(amount = 1) {
    if (this.cluster === "mainnet-beta") {
      throw new Error("Airdrop is not available on mainnet-beta");
    }

    try {
      console.log(`Requesting ${amount} SOL airdrop on ${this.cluster}...`);
      const signature = await this.connection.requestAirdrop(
        this.wallet.publicKey,
        amount * LAMPORTS_PER_SOL
      );

      await this.connection.confirmTransaction(signature);
      console.log(`✅ Airdrop successful: ${signature}`);
      return signature;
    } catch (error) {
      console.error("Airdrop failed:", error.message);
      throw new Error(`Airdrop failed: ${error.message}`);
    }
  }

  /**
   * CORE: Certify a receipt hash on Solana via Memo program
   *
   * memo format: VERICEIPT:v1:HASH:<hash>
   */
  async certifyHash(hash, metadata = {}) {
    try {
      if (!hash || !/^[a-f0-9]{64}$/i.test(hash)) {
        throw new Error("Invalid hash format - must be 64-character hex string");
      }

      // ensure we have enough SOL for fees (devnet-friendly)
      const balance = await this.getBalance();
      if (balance < 0.001 && this.cluster !== "mainnet-beta") {
        console.warn("⚠️ Low balance detected, attempting airdrop...");
        try {
          await this.requestAirdrop(1);
        } catch (airdropError) {
          console.error("Airdrop failed:", airdropError.message);
        }
      }

      const memoData = `VERICEIPT:v1:HASH:${hash}`;

      const memoInstruction = new TransactionInstruction({
        keys: [
          {
            pubkey: this.wallet.publicKey,
            isSigner: true,
            isWritable: true,
          },
        ],
        programId: new PublicKey("MemoSq4gqABAXKb96qnH8TysNcWxMyWCqXgDLGmfcHr"),
        data: Buffer.from(memoData, "utf8"),
      });

      const transaction = new Transaction().add(memoInstruction);

      const { blockhash } = await this.connection.getLatestBlockhash();
      transaction.recentBlockhash = blockhash;
      transaction.feePayer = this.wallet.publicKey;

      console.log("📤 Sending certification transaction to Solana...");
      const signature = await sendAndConfirmTransaction(
        this.connection,
        transaction,
        [this.wallet],
        { commitment: "confirmed", preflightCommitment: "confirmed" }
      );

      console.log("✅ Receipt certified on Solana:", signature);

      const txDetails = await this.connection.getTransaction(signature, {
        commitment: "confirmed",
        maxSupportedTransactionVersion: 0,
      });

      const timestamp = txDetails?.blockTime
        ? new Date(txDetails.blockTime * 1000).toISOString()
        : new Date().toISOString();

      return {
        success: true,
        txSignature: signature,
        chainHash: hash.toLowerCase(),
        timestamp,
        explorerUrl: this._explorerTxUrl(signature),
        walletAddress: this.wallet.publicKey.toString(),
        metadata,
      };
    } catch (error) {
      console.error("❌ Certification failed:", error);

      if (error.message && error.message.includes("insufficient funds")) {
        throw new Error(
          "Insufficient SOL balance for transaction. Please fund the wallet or use devnet/testnet airdrop."
        );
      }

      throw new Error(`Failed to certify receipt: ${error.message}`);
    }
  }

  /**
   * CORE: Verify a receipt hash against the memo stored on-chain
   */
  async verifyHash(txSignature, expectedHash) {
    try {
      if (!txSignature || txSignature.length < 64) {
        throw new Error("Invalid transaction signature");
      }
      if (!expectedHash || !/^[a-f0-9]{64}$/i.test(expectedHash)) {
        throw new Error("Invalid hash format - must be 64-character hex string");
      }

      console.log("🔍 Fetching transaction from Solana:", txSignature);

      const tx = await this.connection.getTransaction(txSignature, {
        commitment: "confirmed",
        maxSupportedTransactionVersion: 0,
      });

      if (!tx) {
        return {
          verified: false,
          message: "Transaction not found on blockchain",
          chainHash: null,
          localHash: expectedHash.toLowerCase(),
          error: "TRANSACTION_NOT_FOUND",
          explorerUrl: this._explorerTxUrl(txSignature),
        };
      }

      // Find memo instruction
      const memoIx = tx.transaction.message.instructions.find((ix) => {
        try {
          const programId = tx.transaction.message.accountKeys[ix.programIdIndex];
          return programId.toString() === "MemoSq4gqABAXKb96qnH8TysNcWxMyWCqXgDLGmfcHr";
        } catch {
          return false;
        }
      });

      const timestamp = tx.blockTime ? new Date(tx.blockTime * 1000).toISOString() : null;

      if (!memoIx) {
        return {
          verified: false,
          message: "No memo found in transaction",
          chainHash: null,
          localHash: expectedHash.toLowerCase(),
          error: "NO_MEMO_FOUND",
          timestamp,
          explorerUrl: this._explorerTxUrl(txSignature),
        };
      }

      // Decode memo
      const memoData = Buffer.from(memoIx.data, "base64").toString("utf8");
      console.log("📝 Memo data:", memoData);

      const match = memoData.match(/VERICEIPT:v1:HASH:([a-f0-9]{64})/i);
      if (!match) {
        return {
          verified: false,
          message: "Invalid memo format - not a Vericeipt transaction",
          chainHash: null,
          localHash: expectedHash.toLowerCase(),
          error: "INVALID_MEMO_FORMAT",
          timestamp,
          explorerUrl: this._explorerTxUrl(txSignature),
        };
      }

      const chainHash = match[1].toLowerCase();
      const localHash = expectedHash.toLowerCase();
      const verified = chainHash === localHash;

      return {
        verified,
        message: verified
          ? "✅ VERIFIED: Receipt matches the certified fingerprint."
          : "❌ VERIFICATION FAILED: Receipt has been altered or does not match the certified version.",
        chainHash,
        localHash,
        timestamp,
        explorerUrl: this._explorerTxUrl(txSignature),
        walletAddress: this.wallet.publicKey.toString(),
        difference: verified ? null : "Hashes do not match",
      };
    } catch (error) {
      console.error("❌ Verification error:", error);

      return {
        verified: false,
        message: `Verification failed: ${error.message}`,
        chainHash: null,
        localHash: expectedHash ? expectedHash.toLowerCase() : null,
        error: "VERIFICATION_ERROR",
        details: error.message,
        explorerUrl: txSignature ? this._explorerTxUrl(txSignature) : null,
      };
    }
  }

  async getTransactionDetails(signature) {
    try {
      const tx = await this.connection.getTransaction(signature, {
        commitment: "confirmed",
        maxSupportedTransactionVersion: 0,
      });

      if (!tx) return null;

      return {
        signature,
        blockTime: tx.blockTime,
        timestamp: tx.blockTime ? new Date(tx.blockTime * 1000).toISOString() : null,
        slot: tx.slot,
        success: tx.meta.err === null,
        fee: tx.meta.fee,
        explorerUrl: this._explorerTxUrl(signature),
      };
    } catch (error) {
      console.error("Failed to get transaction details:", error);
      return null;
    }
  }

  async healthCheck() {
    try {
      const version = await this.connection.getVersion();
      const balance = await this.getBalance();
      const slot = await this.connection.getSlot();

      return {
        connected: true,
        version: version["solana-core"],
        walletAddress: this.wallet.publicKey.toString(),
        balance: `${balance.toFixed(4)} SOL`,
        currentSlot: slot,
        network: this.connection.rpcEndpoint,
        cluster: this.cluster,
      };
    } catch (error) {
      return { connected: false, error: error.message };
    }
  }
}

module.exports = SolanaService;
