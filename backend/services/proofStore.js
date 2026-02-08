// backend/services/proofStore.js
/**
 * ProofStore (hackathon-grade, demo-safe)
 *
 * Solana stores ONLY a hash in a memo (tamper-evident anchor).
 * This store keeps the original canonical text + metadata for:
 *  - Forensic diff (show exactly what changed)
 *  - Duplicate/reuse detection (same receipt claimed twice)
 *
 * Storage: small JSON file on disk (no DB setup needed).
 */

const fs = require("fs");
const path = require("path");

const DATA_DIR = path.join(__dirname, "..", "data");
const DB_PATH = path.join(DATA_DIR, "proofs.json");

function ensureDb() {
  if (!fs.existsSync(DATA_DIR)) fs.mkdirSync(DATA_DIR, { recursive: true });
  if (!fs.existsSync(DB_PATH)) {
    fs.writeFileSync(DB_PATH, JSON.stringify({ byHash: {}, byTx: {} }, null, 2));
  }
}

function readDb() {
  ensureDb();
  try {
    const raw = fs.readFileSync(DB_PATH, "utf8");
    const parsed = JSON.parse(raw);
    if (!parsed.byHash) parsed.byHash = {};
    if (!parsed.byTx) parsed.byTx = {};
    return parsed;
  } catch {
    return { byHash: {}, byTx: {} };
  }
}

function writeDb(db) {
  ensureDb();
  fs.writeFileSync(DB_PATH, JSON.stringify(db, null, 2));
}

function nowIso() {
  return new Date().toISOString();
}

function normHash(hash) {
  return String(hash || "").trim().toLowerCase();
}

function normTx(tx) {
  return String(tx || "").trim();
}

/**
 * Upsert proof record.
 * @returns { duplicate:boolean, firstSeenTx:string|null, firstSeenAt:string|null, seenCount:number }
 */
function upsertProof({ hash, txSignature, canonicalText = null, analysisSummary = {} }) {
  const h = normHash(hash);
  const tx = normTx(txSignature);

  if (!h || !tx) throw new Error("hash and txSignature are required");

  const db = readDb();
  const existing = db.byHash[h] || null;

  const duplicate = !!existing;
  const createdAt = nowIso();

  const firstSeenTx = existing?.firstSeenTx || tx;
  const firstSeenAt = existing?.firstSeenAt || createdAt;
  const seenCount = (existing?.seenCount || 0) + 1;

  db.byHash[h] = {
    hash: h,
    canonicalText: canonicalText || existing?.canonicalText || null,
    analysisSummary:
      Object.keys(analysisSummary || {}).length
        ? analysisSummary
        : existing?.analysisSummary || {},
    createdAt: existing?.createdAt || createdAt,
    lastSeenAt: createdAt,

    // Most recent tx
    txSignature: tx,

    // Duplicate tracking
    firstSeenTx,
    firstSeenAt,
    seenCount,
  };

  // Only write byTx if not present (avoid overwriting older data accidentally)
  if (!db.byTx[tx]) {
    db.byTx[tx] = {
      txSignature: tx,
      hash: h,
      canonicalText: canonicalText || null,
      createdAt,
    };
  }

  writeDb(db);

  return { duplicate, firstSeenTx, firstSeenAt, seenCount };
}

function getByTx(txSignature) {
  const tx = normTx(txSignature);
  const db = readDb();
  return db.byTx[tx] || null;
}

function getByHash(hash) {
  const h = normHash(hash);
  const db = readDb();
  return db.byHash[h] || null;
}

/**
 * Nice for a GET /proof/:tx endpoint
 * Returns merged view of proof data (tx -> hash -> analytics).
 */
function getProofBundleByTx(txSignature) {
  const txRow = getByTx(txSignature);
  if (!txRow) return null;

  const hashRow = getByHash(txRow.hash);
  return {
    txSignature: txRow.txSignature,
    hash: txRow.hash,
    canonicalText: txRow.canonicalText || hashRow?.canonicalText || null,
    createdAt: txRow.createdAt || null,
    duplicate: (hashRow?.seenCount || 0) > 1,
    firstSeenTx: hashRow?.firstSeenTx || txRow.txSignature,
    firstSeenAt: hashRow?.firstSeenAt || txRow.createdAt || null,
    seenCount: hashRow?.seenCount || 1,
    lastSeenAt: hashRow?.lastSeenAt || null,
    analysisSummary: hashRow?.analysisSummary || {},
  };
}

module.exports = {
  upsertProof,
  getByTx,
  getByHash,
  getProofBundleByTx,
};
