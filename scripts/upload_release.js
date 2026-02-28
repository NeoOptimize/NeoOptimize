const fs = require('fs');
const path = require('path');
const https = require('https');
const { URL } = require('url');

const OWNER = 'NeoOptimize';
const REPO = 'NeoOptimize';
const USER_AGENT = 'neooptimize-uploader';
const JSON_HEADERS = { Accept: 'application/vnd.github+json', 'X-GitHub-Api-Version': '2022-11-28' };

function requestJson(url, options = {}) {
  return new Promise((resolve, reject) => {
    const req = https.request(url, options, (res) => {
      let data = '';
      res.on('data', (d) => { data += d; });
      res.on('end', () => {
        try {
          resolve({ status: res.statusCode || 0, body: data ? JSON.parse(data) : null });
        } catch {
          resolve({ status: res.statusCode || 0, body: data });
        }
      });
    });
    req.on('error', reject);
    if (options.body) req.write(options.body);
    req.end();
  });
}

function authHeaders(token, extras = {}) {
  return {
    Authorization: `token ${token}`,
    'User-Agent': USER_AGENT,
    ...JSON_HEADERS,
    ...extras
  };
}

async function createOrGetRelease(token, tag, name) {
  const body = JSON.stringify({ tag_name: tag, name, body: `Release ${tag}` });
  const create = await requestJson(`https://api.github.com/repos/${OWNER}/${REPO}/releases`, {
    method: 'POST',
    headers: authHeaders(token, { 'Content-Type': 'application/json', 'Content-Length': Buffer.byteLength(body) }),
    body
  });
  if (create.status === 201) return create.body;
  const existing = await requestJson(`https://api.github.com/repos/${OWNER}/${REPO}/releases/tags/${tag}`, {
    method: 'GET',
    headers: authHeaders(token)
  });
  if (existing.status === 200) return existing.body;
  throw new Error(`Could not create/fetch release: ${JSON.stringify(create.body)}`);
}

async function listReleaseAssets(token, releaseId) {
  const r = await requestJson(`https://api.github.com/repos/${OWNER}/${REPO}/releases/${releaseId}/assets?per_page=100`, {
    method: 'GET',
    headers: authHeaders(token)
  });
  if (r.status !== 200 || !Array.isArray(r.body)) return [];
  return r.body;
}

async function deleteReleaseAsset(token, assetId) {
  const r = await requestJson(`https://api.github.com/repos/${OWNER}/${REPO}/releases/assets/${assetId}`, {
    method: 'DELETE',
    headers: authHeaders(token)
  });
  return r.status === 204;
}

async function uploadAsset(token, uploadUrlTemplate, filePath) {
  const uploadUrl = uploadUrlTemplate.replace('{?name,label}', '');
  const name = path.basename(filePath);
  const fullUrl = `${uploadUrl}?name=${encodeURIComponent(name)}`;
  const stat = fs.statSync(filePath);
  const u = new URL(fullUrl);
  const options = {
    method: 'POST',
    hostname: u.hostname,
    path: u.pathname + u.search,
    headers: {
      Authorization: `token ${token}`,
      'User-Agent': USER_AGENT,
      'Content-Type': 'application/octet-stream',
      'Content-Length': stat.size
    }
  };
  return new Promise((resolve, reject) => {
    const req = https.request(options, (res) => {
      let data = '';
      res.on('data', (c) => { data += c; });
      res.on('end', () => {
        if ((res.statusCode || 0) >= 200 && (res.statusCode || 0) < 300) resolve({ status: res.statusCode || 0, body: data });
        else reject(new Error(`Upload failed ${res.statusCode}: ${data}`));
      });
    });
    req.on('error', reject);
    const stream = fs.createReadStream(filePath);
    stream.on('error', reject);
    stream.pipe(req);
  });
}

function collectAssets(baseDir) {
  if (!fs.existsSync(baseDir)) return [];
  const out = [];
  const allow = new Set(['.exe', '.yml', '.blockmap']);
  const walk = (dir) => {
    for (const item of fs.readdirSync(dir)) {
      const p = path.join(dir, item);
      const st = fs.statSync(p);
      if (st.isDirectory()) walk(p);
      else if (st.isFile()) {
        const ext = path.extname(p).toLowerCase();
        if (allow.has(ext)) out.push(path.resolve(p));
      }
    }
  };
  walk(baseDir);
  return out.sort((a, b) => a.localeCompare(b));
}

async function main() {
  const token = process.env.GITHUB_TOKEN || process.argv[2];
  if (!token) {
    console.error('Missing GITHUB_TOKEN (env or arg)');
    process.exit(2);
  }
  const pkg = JSON.parse(fs.readFileSync('package.json', 'utf8'));
  const tag = `v${pkg.version || '0.0.0'}`;
  const outputDir = fs.existsSync('release') ? 'release' : 'dist';
  const assets = collectAssets(outputDir);
  if (!assets.length) {
    console.error(`No release assets found in ${outputDir}/`);
    process.exit(3);
  }

  try {
    console.log('Creating/fetching release', tag);
    const rel = await createOrGetRelease(token, tag, tag);
    console.log('Release URL:', rel.html_url || rel.url);
    if (!rel.upload_url || !rel.id) throw new Error('Invalid release response from GitHub');

    const existingAssets = await listReleaseAssets(token, rel.id);
    for (const file of assets) {
      const name = path.basename(file);
      const existing = existingAssets.find((a) => a && a.name === name);
      if (existing?.id) {
        console.log(`Replacing existing asset: ${name}`);
        await deleteReleaseAsset(token, existing.id);
      }
      console.log(`Uploading: ${name}`);
      await uploadAsset(token, rel.upload_url, file);
    }

    console.log(`Upload success (${assets.length} assets)`);
    process.exit(0);
  } catch (e) {
    console.error('Error:', e.message || e);
    process.exit(1);
  }
}

main();
