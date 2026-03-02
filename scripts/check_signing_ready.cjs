#!/usr/bin/env node
const fs = require('fs');

const link = process.env.CSC_LINK || process.env.WIN_CSC_LINK || '';
const password = process.env.CSC_KEY_PASSWORD || process.env.WIN_CSC_KEY_PASSWORD || '';

function fail(msg) {
  console.error(`[codesign] ${msg}`);
  process.exit(1);
}

if (!link) fail('CSC_LINK/WIN_CSC_LINK is missing');
if (!password) fail('CSC_KEY_PASSWORD/WIN_CSC_KEY_PASSWORD is missing');

if (/^https?:\/\//i.test(link)) {
  console.log('[codesign] certificate source URL configured');
  process.exit(0);
}

const normalized = String(link).replace(/^file:\/\//i, '');
if (!fs.existsSync(normalized)) fail(`certificate file not found: ${normalized}`);

console.log(`[codesign] certificate file found: ${normalized}`);
process.exit(0);
