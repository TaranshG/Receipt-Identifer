require("dotenv").config();
const express = require("express");
const cors = require("cors");
const helmet = require("helmet");
const morgan = require("morgan");
const rateLimit = require("express-rate-limit");

const VericeiptController = require("./controllers/vericeipt.controller");
const ProofStore = require("./services/proofStore");

const app = express();
const PORT = process.env.PORT || 3000;

app.use(helmet());
app.use(cors({ origin: true, credentials: true }));
app.use(morgan("dev"));
app.use(express.json({ limit: "10mb" }));
app.use(express.urlencoded({ extended: true, limit: "10mb" }));

const limiter = rateLimit({
  windowMs: 15 * 60 * 1000,
  max: 100,
  message: { success: false, error: "Too many requests" },
});
app.use("/analyze", limiter);
app.use("/certify", limiter);
app.use("/verify", limiter);
app.use("/proof", limiter);

const requiredEnvVars = ["GEMINI_API_KEY", "SOLANA_RPC_URL"];
const missingEnvVars = requiredEnvVars.filter((v) => !process.env[v]);
if (missingEnvVars.length > 0) {
  console.error("Missing env vars:", missingEnvVars.join(", "));
  process.exit(1);
}

const controller = new VericeiptController(
  process.env.GEMINI_API_KEY,
  process.env.SOLANA_RPC_URL,
  process.env.SOLANA_PRIVATE_KEY
);

console.log("✅ Services initialized");

app.get("/", (req, res) => {
  res.json({
    name: "Vericeipt API",
    version: "1.0.0",
    description: "AI receipt verification + Solana certification",
    endpoints: {
      analyze: { method: "POST", path: "/analyze" },
      certify: { method: "POST", path: "/certify" },
      verify: { method: "POST", path: "/verify" },
      proof: { method: "GET", path: "/proof/:txSignature" },
      proofs: { method: "GET", path: "/proofs" },
      health: { method: "GET", path: "/health" },
    },
  });
});

app.post("/analyze", async (req, res) => {
  await controller.analyzeReceipt(req, res);
});

app.post("/certify", async (req, res) => {
  await controller.certifyReceipt(req, res);
});

app.post("/verify", async (req, res) => {
  await controller.verifyReceipt(req, res);
});

app.get("/proof/:txSignature", async (req, res) => {
  try {
    const txSignature = String(req.params.txSignature || "").trim();
    if (!txSignature || txSignature.length < 20) {
      return res.status(400).json({ success: false, error: "Invalid txSignature" });
    }

    const bundle = ProofStore.getProofBundleByTx(txSignature);
    const cluster = process.env.SOLANA_NETWORK || "devnet";
    const explorerUrl = `https://explorer.solana.com/tx/${txSignature}?cluster=${cluster}`;

    if (!bundle) {
      return res.status(404).json({
        success: false,
        found: false,
        txSignature,
        explorerUrl,
        error: "No proof found",
      });
    }

    return res.json({ success: true, found: true, ...bundle, explorerUrl });
  } catch (error) {
    console.error("Proof lookup error:", error);
    return res.status(500).json({ success: false, error: error.message });
  }
});

app.get("/proofs", async (req, res) => {
  try {
    const all = ProofStore.getAllProofs();
    return res.json({ success: true, proofs: all });
  } catch (error) {
    console.error("Proofs list error:", error);
    return res.status(500).json({ success: false, error: error.message });
  }
});

app.get("/health", async (req, res) => {
  await controller.healthCheck(req, res);
});

app.use((req, res) => {
  res.status(404).json({
    success: false,
    error: "Endpoint not found",
    path: req.path,
    method: req.method,
  });
});

app.use((err, req, res, next) => {
  console.error("Unhandled error:", err);
  res.status(err.status || 500).json({
    success: false,
    error: err.message || "Internal server error",
  });
});

app.listen(PORT, () => {
  console.log("");
  console.log("═══════════════════════════════════════════════════════");
  console.log("🚀 Vericeipt Backend Server");
  console.log("═══════════════════════════════════════════════════════");
  console.log(`📡 Port: ${PORT}`);
  console.log(`🌍 Environment: ${process.env.NODE_ENV || "development"}`);
  console.log(`🔗 URL: http://localhost:${PORT}`);
  console.log("");
  console.log("📚 Endpoints:");
  console.log(`   POST   /analyze`);
  console.log(`   POST   /certify`);
  console.log(`   POST   /verify`);
  console.log(`   GET    /proof/:txSignature`);
  console.log(`   GET    /proofs`);
  console.log(`   GET    /health`);
  console.log("═══════════════════════════════════════════════════════");
  console.log("");
});

process.on("SIGTERM", () => process.exit(0));
process.on("SIGINT", () => process.exit(0));

module.exports = app;