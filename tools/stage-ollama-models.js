#!/usr/bin/env node
"use strict";

const fs = require("fs");
const path = require("path");

function parseArgs(argv) {
  const args = {};
  for (let i = 2; i < argv.length; i += 1) {
    const item = argv[i];
    if (!item.startsWith("--")) continue;
    const key = item.slice(2);
    const value = argv[i + 1] && !argv[i + 1].startsWith("--") ? argv[++i] : "1";
    args[key] = value;
  }
  return args;
}

function normalizeModel(raw) {
  const value = String(raw || "").trim();
  if (!value) return "";
  if (value === "neo-latest" || value === "neo") return "neo:latest";
  if (value === "neo-light") return "neo-light:latest";
  return value;
}

function ensureDir(dir) {
  fs.mkdirSync(dir, { recursive: true });
}

function copyFile(src, dest) {
  ensureDir(path.dirname(dest));
  fs.copyFileSync(src, dest);
}

function collectDigests(value, out) {
  if (Array.isArray(value)) {
    for (const item of value) collectDigests(item, out);
    return;
  }
  if (value && typeof value === "object") {
    for (const item of Object.values(value)) collectDigests(item, out);
    return;
  }
  if (typeof value !== "string") return;
  const matches = value.matchAll(/sha256:[a-f0-9]{64}/gi);
  for (const match of matches) out.add(match[0].toLowerCase());
}

function modelToManifestPath(source, model) {
  const [name, tag = "latest"] = model.split(":");
  if (!name || name.includes("/") || tag.includes("/") || tag.includes("\\")) {
    throw new Error(`Unsupported local model name for offline bundle: ${model}`);
  }
  return path.join(source, "manifests", "registry.ollama.ai", "library", name, tag);
}

function statSize(file) {
  return fs.statSync(file).size;
}

const args = parseArgs(process.argv);
const source = path.resolve(args.source || "/usr/share/ollama/.ollama/models");
const dest = path.resolve(args.dest || "installer/client/tools/ollama-models/models");
const requested = String(args.models || "neo-light:latest neo:latest")
  .split(/[,\s]+/)
  .map(normalizeModel)
  .filter(Boolean);

const allowed = new Set(["neo:latest", "neo-light:latest"]);
const models = [...new Set(requested)];
for (const model of models) {
  if (!allowed.has(model)) {
    throw new Error(`Refusing to stage unsupported model "${model}". Allowed: neo:latest, neo-light:latest`);
  }
}

if (!fs.existsSync(source)) {
  throw new Error(`Ollama model source does not exist: ${source}`);
}

fs.rmSync(dest, { recursive: true, force: true });
ensureDir(dest);

const copiedBlobs = new Set();
const staged = [];
let totalBytes = 0;

for (const model of models) {
  const manifestSrc = modelToManifestPath(source, model);
  if (!fs.existsSync(manifestSrc)) {
    throw new Error(`Missing Ollama manifest for ${model}: ${manifestSrc}`);
  }

  const relManifest = path.relative(source, manifestSrc);
  const manifestDest = path.join(dest, relManifest);
  copyFile(manifestSrc, manifestDest);
  totalBytes += statSize(manifestSrc);

  const manifest = JSON.parse(fs.readFileSync(manifestSrc, "utf8"));
  const digests = new Set();
  collectDigests(manifest, digests);

  const blobs = [];
  for (const digest of digests) {
    const blobName = digest.replace(":", "-");
    const blobSrc = path.join(source, "blobs", blobName);
    const blobDest = path.join(dest, "blobs", blobName);
    if (!fs.existsSync(blobSrc)) {
      throw new Error(`Missing Ollama blob for ${model}: ${blobSrc}`);
    }
    if (!copiedBlobs.has(blobName)) {
      copyFile(blobSrc, blobDest);
      copiedBlobs.add(blobName);
      totalBytes += statSize(blobSrc);
    }
    blobs.push(blobName);
  }

  staged.push({ model, manifest: relManifest, blobs });
}

const metadata = {
  schema_version: 1,
  generated_at: new Date().toISOString(),
  source,
  models: staged,
  total_bytes: totalBytes
};

fs.writeFileSync(
  path.join(path.dirname(dest), "bundle-manifest.json"),
  `${JSON.stringify(metadata, null, 2)}\n`,
  "utf8"
);

console.log(`[OK] Staged ${models.length} Ollama model(s), ${copiedBlobs.size} blob(s), ${totalBytes} bytes.`);
