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

  async getBalance() {
    try {
      const balance = await this.connection.getBalance(this.wallet.publicKey);
      return balance / LAMPORTS_PER_SOL;
    } catch (error) {
      console.error('Failed to get balance:', error);
      return 0;
    }
  }

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

  async certifyHash(hash, metadata = {}) {
    try {
      if (!hash || !/^[a-f0-9]{64}$/i.test(hash)) {
        throw new Error('Invalid hash format - must be 64-character hex string');
      }

      const balance = await this.getBalance();
      if (balance < 0.001) {
        console.warn('⚠️ Low balance detected, attempting airdrop...');
        try {
          await this.requestAirdrop(1);
        } catch (airdropError) {
          console.error('Airdrop failed:', airdropError.message);
        }
      }

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

      const transaction = new Transaction().add(memoInstruction);
      
      const { blockhash } = await this.connection.getLatestBlockhash();
      transaction.recentBlockhash = blockhash;
      transaction.feePayer = this.wallet.publicKey;

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

      const txDetails = await this.connection.getTransaction(signature, {
        commitment: 'confirmed'
      });

      const cluster = process.env.SOLANA_NETWORK || 'devnet';

      return {
        success: true,
        txSignature: signature,
        chainHash: hash,
        timestamp: txDetails?.blockTime ? new Date(txDetails.blockTime * 1000).toISOString() : new Date().toISOString(),
        explorerUrl: `https://explorer.solana.com/tx/${signature}?cluster=${cluster}`,
        walletAddress: this.wallet.publicKey.toString(),
        metadata
      };
    } catch (error) {
      console.error('❌ Certification failed:', error);
      
      if (error.message.includes('insufficient funds')) {
        throw new Error('Insufficient SOL balance for transaction. Please fund the wallet or use devnet airdrop.');
      }
      
      throw new Error(`Failed to certify receipt: ${error.message}`);
    }
  }

  _explorerTxUrl(txSignature) {
    const cluster = process.env.SOLANA_NETWORK || 'devnet';
    return `https://explorer.solana.com/tx/${txSignature}?cluster=${cluster}`;
  }

  async verifyHash(txSignature, expectedHash) {
    try {
      if (!txSignature || txSignature.length < 64) {
        throw new Error('Invalid transaction signature');
      }

      if (!expectedHash || !/^[a-f0-9]{64}$/i.test(expectedHash)) {
        throw new Error('Invalid hash format - must be 64-character hex string');
      }

      console.log('🔍 Fetching transaction from Solana:', txSignature);

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

      // CRITICAL FIX: Robust memo extraction
      const MEMO_PROGRAM_ID = 'MemoSq4gqABAXKb96qnH8TysNcWxMyWCqXgDLGmfcHr';
      
      let memoData = null;

      // Try compiled instructions first (newer format)
      if (tx.transaction.message.compiledInstructions) {
        for (const ix of tx.transaction.message.compiledInstructions) {
          try {
            const programId = tx.transaction.message.staticAccountKeys[ix.programIdIndex];
            if (programId && programId.toString() === MEMO_PROGRAM_ID) {
              // Data is base58 encoded in compiledInstructions
              const decoded = bs58.decode(ix.data);
              memoData = decoded.toString('utf8');
              console.log('🔍 Memo found (compiled):', memoData);
              break;
            }
          } catch (e) {
            console.log('Failed to decode compiled instruction:', e.message);
          }
        }
      }

      // Fallback to legacy instructions format
      if (!memoData && tx.transaction.message.instructions) {
        for (const ix of tx.transaction.message.instructions) {
          try {
            const programId = tx.transaction.message.accountKeys[ix.programIdIndex];
            if (programId && programId.toString() === MEMO_PROGRAM_ID) {
              // Try multiple decoding strategies
              let decoded = null;
              
              // Strategy 1: base58 decode
              try {
                decoded = bs58.decode(ix.data);
                memoData = decoded.toString('utf8');
              } catch (e1) {
                // Strategy 2: direct buffer if already bytes
                try {
                  decoded = Buffer.from(ix.data);
                  memoData = decoded.toString('utf8');
                } catch (e2) {
                  // Strategy 3: base64 decode (some RPC formats)
                  try {
                    decoded = Buffer.from(ix.data, 'base64');
                    memoData = decoded.toString('utf8');
                  } catch (e3) {
                    console.log('All decode strategies failed');
                  }
                }
              }
              
              if (memoData) {
                console.log('🔍 Memo found (legacy):', memoData);
                break;
              }
            }
          } catch (e) {
            console.log('Failed to decode legacy instruction:', e.message);
          }
        }
      }

      if (!memoData) {
        return {
          verified: false,
          message: 'No memo found in transaction',
          chainHash: null,
          localHash: expectedHash,
          error: 'NO_MEMO_FOUND'
        };
      }

      // Extract hash from memo (format: "VERICEIPT:v1:HASH:<hash>")
      const hashMatch = memoData.match(/VERICEIPT:v1:HASH:([a-f0-9]{64})/i);
      
      if (!hashMatch) {
        return {
          verified: false,
          message: 'Invalid memo format - not a Vericeipt transaction',
          chainHash: null,
          localHash: expectedHash,
          error: 'INVALID_MEMO_FORMAT',
          memoFound: memoData
        };
      }

      const chainHash = hashMatch[1].toLowerCase();
      const localHash = expectedHash.toLowerCase();

      const verified = chainHash === localHash;

      const timestamp = tx.blockTime 
        ? new Date(tx.blockTime * 1000).toISOString() 
        : null;

      const explorerUrl = this._explorerTxUrl(txSignature);

      if (verified) {
        return {
          verified: true,
          message: '✅ VERIFIED: Receipt matches the certified fingerprint.',
          chainHash,
          localHash,
          timestamp,
          explorerUrl,
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
          explorerUrl
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
        explorerUrl: this._explorerTxUrl(signature)
      };
    } catch (error) {
      console.error('Failed to get transaction details:', error);
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