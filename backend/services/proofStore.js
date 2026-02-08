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

function upsertProof({ hash, txSignature, canonicalText = null, analysisSummary = {} }) {
  const h = normHash(hash);
  const tx = normTx(txSignature);
  if (!h || !tx) throw new Error("hash and txSignature required");

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
    analysisSummary: Object.keys(analysisSummary || {}).length ? analysisSummary : existing?.analysisSummary || {},
    createdAt: existing?.createdAt || createdAt,
    lastSeenAt: createdAt,
    txSignature: tx,
    firstSeenTx,
    firstSeenAt,
    seenCount,
  };

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

function getAllProofs() {
  const db = readDb();
  const all = Object.values(db.byHash).sort((a, b) => {
    const ta = new Date(a.lastSeenAt || 0).getTime();
    const tb = new Date(b.lastSeenAt || 0).getTime();
    return tb - ta;
  });
  return all;
}

module.exports = {
  upsertProof,
  getByTx,
  getByHash,
  getProofBundleByTx,
  getAllProofs,
};