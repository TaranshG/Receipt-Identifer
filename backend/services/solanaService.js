/**
 * Solana Service
 * Handles blockchain interactions for receipt certification and verification
 * 
 * This is the CORE innovation - we use Solana as a public notary for receipt integrity
 */

const {
  Connection,
  Keypair,
  Transaction,
  TransactionInstruction,
  PublicKey,
  SystemProgram,
  sendAndConfirmTransaction,
  LAMPORTS_PER_SOL
} = require('@solana/web3.js');
const bs58 = require('bs58').default;

class SolanaService {
  constructor(rpcUrl, privateKeyBase58) {
    if (!rpcUrl) {
      throw new Error('Solana RPC URL is required');
    }
    
    this.connection = new Connection(rpcUrl, 'confirmed');
    
    // Initialize wallet from private key
    if (privateKeyBase58) {
      try {
        const privateKeyBytes = bs58.decode(privateKeyBase58);
        this.wallet = Keypair.fromSecretKey(privateKeyBytes);
        console.log('✅ Solana wallet initialized:', this.wallet.publicKey.toString());
      } catch (error) {
        console.error('❌ Failed to initialize Solana wallet:', error.message);
        throw new Error('Invalid Solana private key format');
      }
    } else {
      console.warn('⚠️ No Solana private key provided - generating temporary keypair');
      this.wallet = Keypair.generate();
    }
  }

  /**
   * Get wallet balance in SOL
   * Useful for monitoring and preventing failed transactions
   */
  async getBalance() {
    try {
      const balance = await this.connection.getBalance(this.wallet.publicKey);
      return balance / LAMPORTS_PER_SOL;
    } catch (error) {
      console.error('Failed to get balance:', error);
      return 0;
    }
  }

  /**
   * Request airdrop on devnet (for testing)
   * This is useful during hackathon demos
   */
  async requestAirdrop(amount = 1) {
    try {
      console.log(`Requesting ${amount} SOL airdrop...`);
      const signature = await this.connection.requestAirdrop(
        this.wallet.publicKey,
        amount * LAMPORTS_PER_SOL
      );
      
      await this.connection.confirmTransaction(signature);
      console.log(`✅ Airdrop successful: ${signature}`);
      return signature;
    } catch (error) {
      console.error('Airdrop failed:', error.message);
      throw new Error(`Airdrop failed: ${error.message}`);
    }
  }

  /**
   * CORE FUNCTION: Certify a receipt hash on Solana blockchain
   * 
   * How it works:
   * 1. Takes a hash (SHA-256 hex string)
   * 2. Creates a Memo transaction with the hash as the memo
   * 3. Sends transaction to Solana blockchain
   * 4. Returns the transaction signature (proof ID)
   * 
   * This creates an immutable, timestamped record that can be verified later
   * 
   * @param {string} hash - SHA-256 hash in hex format
   * @param {Object} metadata - Optional metadata (not stored on-chain)
   * @returns {Promise<Object>} Transaction result with signature
   */
  async certifyHash(hash, metadata = {}) {
    try {
      // Validate hash format
      if (!hash || !/^[a-f0-9]{64}$/i.test(hash)) {
        throw new Error('Invalid hash format - must be 64-character hex string');
      }

      // Check balance before attempting transaction
      const balance = await this.getBalance();
      if (balance < 0.001) {
        console.warn('⚠️ Low balance detected, attempting airdrop...');
        try {
          await this.requestAirdrop(1);
        } catch (airdropError) {
          console.error('Airdrop failed:', airdropError.message);
        }
      }

      // Create memo instruction with hash
      // Format: "VERICEIPT:v1:HASH:<hash>"
      const memoData = `VERICEIPT:v1:HASH:${hash}`;
      
      const memoInstruction = new TransactionInstruction({
        keys: [{
          pubkey: this.wallet.publicKey,
          isSigner: true,
          isWritable: true
        }],
        programId: new PublicKey('MemoSq4gqABAXKb96qnH8TysNcWxMyWCqXgDLGmfcHr'),
        data: Buffer.from(memoData, 'utf8')
      });

      // Create transaction
      const transaction = new Transaction().add(memoInstruction);
      
      // Get recent blockhash
      const { blockhash } = await this.connection.getLatestBlockhash();
      transaction.recentBlockhash = blockhash;
      transaction.feePayer = this.wallet.publicKey;

      // Sign and send transaction
      console.log('📤 Sending certification transaction to Solana...');
      const signature = await sendAndConfirmTransaction(
        this.connection,
        transaction,
        [this.wallet],
        {
          commitment: 'confirmed',
          preflightCommitment: 'confirmed'
        }
      );

      console.log('✅ Receipt certified on Solana:', signature);

      // Get transaction details
      const txDetails = await this.connection.getTransaction(signature, {
        commitment: 'confirmed'
      });

      return {
        success: true,
        txSignature: signature,
        chainHash: hash,
        timestamp: txDetails?.blockTime ? new Date(txDetails.blockTime * 1000).toISOString() : new Date().toISOString(),
        explorerUrl: `https://explorer.solana.com/tx/${signature}?cluster=devnet`,
        walletAddress: this.wallet.publicKey.toString(),
        metadata
      };
    } catch (error) {
      console.error('❌ Certification failed:', error);
      
      // Provide helpful error messages
      if (error.message.includes('insufficient funds')) {
        throw new Error('Insufficient SOL balance for transaction. Please fund the wallet or use devnet airdrop.');
      }
      
      throw new Error(`Failed to certify receipt: ${error.message}`);
    }
  }

  /**
   * CORE FUNCTION: Verify a receipt hash against on-chain record
   * 
   * How it works:
   * 1. Takes a transaction signature (proof ID)
   * 2. Fetches the transaction from Solana
   * 3. Extracts the memo data (which contains the certified hash)
   * 4. Compares it with the provided hash
   * 5. Returns verification result
   * 
   * @param {string} txSignature - Transaction signature to verify
   * @param {string} expectedHash - Hash to compare against
   * @returns {Promise<Object>} Verification result
   */
  async verifyHash(txSignature, expectedHash) {
    try {
      // Validate inputs
      if (!txSignature || txSignature.length < 64) {
        throw new Error('Invalid transaction signature');
      }

      if (!expectedHash || !/^[a-f0-9]{64}$/i.test(expectedHash)) {
        throw new Error('Invalid hash format - must be 64-character hex string');
      }

      console.log('🔍 Fetching transaction from Solana:', txSignature);

      // Fetch transaction
      const tx = await this.connection.getTransaction(txSignature, {
        commitment: 'confirmed',
        maxSupportedTransactionVersion: 0
      });

      if (!tx) {
        return {
          verified: false,
          message: 'Transaction not found on blockchain',
          chainHash: null,
          localHash: expectedHash,
          error: 'TRANSACTION_NOT_FOUND'
        };
      }

      // Extract memo from transaction
      const memoInstruction = tx.transaction.message.instructions.find(
        ix => {
          try {
            const programId = tx.transaction.message.accountKeys[ix.programIdIndex];
            return programId.toString() === 'MemoSq4gqABAXKb96qnH8TysNcWxMyWCqXgDLGmfcHr';
          } catch {
            return false;
          }
        }
      );

      if (!memoInstruction) {
        return {
          verified: false,
          message: 'No memo found in transaction',
          chainHash: null,
          localHash: expectedHash,
          error: 'NO_MEMO_FOUND'
        };
      }

      // Decode memo data
      const memoData = Buffer.from(memoInstruction.data, 'base64').toString('utf8');
      console.log('📝 Memo data:', memoData);

      // Extract hash from memo (format: "VERICEIPT:v1:HASH:<hash>")
      const hashMatch = memoData.match(/VERICEIPT:v1:HASH:([a-f0-9]{64})/i);
      
      if (!hashMatch) {
        return {
          verified: false,
          message: 'Invalid memo format - not a Vericeipt transaction',
          chainHash: null,
          localHash: expectedHash,
          error: 'INVALID_MEMO_FORMAT'
        };
      }

      const chainHash = hashMatch[1].toLowerCase();
      const localHash = expectedHash.toLowerCase();

      // Compare hashes
      const verified = chainHash === localHash;

      // Get timestamp
      const timestamp = tx.blockTime 
        ? new Date(tx.blockTime * 1000).toISOString() 
        : null;

      if (verified) {
        return {
          verified: true,
          message: '✅ VERIFIED: Receipt matches the certified fingerprint.',
          chainHash,
          localHash,
          timestamp,
          explorerUrl: `https://explorer.solana.com/tx/${txSignature}?cluster=devnet`,
          walletAddress: this.wallet.publicKey.toString()
        };
      } else {
        return {
          verified: false,
          message: '❌ VERIFICATION FAILED: Receipt has been altered or does not match the certified version.',
          chainHash,
          localHash,
          timestamp,
          difference: 'Hashes do not match',
          explorerUrl: `https://explorer.solana.com/tx/${txSignature}?cluster=devnet`
        };
      }
    } catch (error) {
      console.error('❌ Verification error:', error);
      
      return {
        verified: false,
        message: `Verification failed: ${error.message}`,
        chainHash: null,
        localHash: expectedHash,
        error: 'VERIFICATION_ERROR',
        details: error.message
      };
    }
  }

  /**
   * Get transaction details
   * Useful for debugging and displaying transaction info
   */
  async getTransactionDetails(signature) {
    try {
      const tx = await this.connection.getTransaction(signature, {
        commitment: 'confirmed',
        maxSupportedTransactionVersion: 0
      });

      if (!tx) {
        return null;
      }

      return {
        signature,
        blockTime: tx.blockTime,
        timestamp: tx.blockTime ? new Date(tx.blockTime * 1000).toISOString() : null,
        slot: tx.slot,
        success: tx.meta.err === null,
        fee: tx.meta.fee,
        explorerUrl: `https://explorer.solana.com/tx/${signature}?cluster=devnet`
      };
    } catch (error) {
      console.error('Failed to get transaction details:', error);
      return null;
    }
  }

  /**
   * Health check - verify Solana connection is working
   */
  async healthCheck() {
    try {
      const version = await this.connection.getVersion();
      const balance = await this.getBalance();
      const slot = await this.connection.getSlot();

      return {
        connected: true,
        version: version['solana-core'],
        walletAddress: this.wallet.publicKey.toString(),
        balance: `${balance.toFixed(4)} SOL`,
        currentSlot: slot,
        network: this.connection.rpcEndpoint
      };
    } catch (error) {
      return {
        connected: false,
        error: error.message
      };
    }
  }
}

module.exports = SolanaService;
