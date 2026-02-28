const fs = require('fs');
const path = require('path');
const https = require('https');
const { URL } = require('url');

async function fetchJson(url, options = {}) {
  return new Promise((resolve, reject) => {
    const req = https.request(url, options, res => {
      let data = '';
      res.on('data', d => data += d);
      res.on('end', () => {
        try { const json = JSON.parse(data); resolve({ status: res.statusCode, body: json }); }
        catch (e) { resolve({ status: res.statusCode, body: data }); }
      });
    });
    req.on('error', reject);
    if (options.body) req.write(options.body);
    req.end();
  });
}

async function createOrGetRelease(token, owner, repo, tag, name) {
  const body = JSON.stringify({ tag_name: tag, name: name, body: `Release ${tag}` });
  const opts = {
    method: 'POST',
    headers: {
      'Authorization': `token ${token}`,
      'User-Agent': 'neooptimize-uploader',
      'Accept': 'application/vnd.github+json',
      'Content-Type': 'application/json',
      'Content-Length': Buffer.byteLength(body)
    }
  };
  const url = `https://api.github.com/repos/${owner}/${repo}/releases`;
  const res = await fetchJson(url, { ...opts, body });
  if (res.status === 201) return res.body;
  const getUrl = `https://api.github.com/repos/${owner}/${repo}/releases/tags/${tag}`;
  const getRes = await fetchJson(getUrl, { method: 'GET', headers: opts.headers });
  if (getRes.status === 200) return getRes.body;
  throw new Error(`Could not create or fetch release: ${JSON.stringify(res.body)}`);
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
      'Authorization': `token ${token}`,
      'User-Agent': 'neooptimize-uploader',
      'Content-Type': 'application/octet-stream',
      'Content-Length': stat.size
    }
  };

  return new Promise((resolve, reject) => {
    const req = https.request(options, res => {
      let data = '';
      res.on('data', c => data += c);
      res.on('end', () => {
        if (res.statusCode >= 200 && res.statusCode < 300) resolve({ status: res.statusCode, body: data });
        else reject(new Error(`Upload failed ${res.statusCode}: ${data}`));
      });
    });
    req.on('error', reject);
    const stream = fs.createReadStream(filePath);
    stream.on('error', reject);
    stream.pipe(req);
  });
}

async function findExe(distDir) {
  if (!fs.existsSync(distDir)) return null;
  const list = [];
  function walk(dir) {
    for (const f of fs.readdirSync(dir)) {
      const p = path.join(dir, f);
      const st = fs.statSync(p);
      if (st.isDirectory()) walk(p);
      else if (st.isFile() && p.toLowerCase().endsWith('.exe')) list.push(p);
    }
  }
  walk(distDir);
  return list[0] || null;
}

async function main() {
  const token = process.env.GITHUB_TOKEN || process.argv[2];
  if (!token) { console.error('Missing GITHUB_TOKEN (env or arg)'); process.exit(2); }
  const owner = 'NeoOptimize';
  const repo = 'NeoOptimize';
  const pkg = JSON.parse(fs.readFileSync('package.json','utf8'));
  const ver = pkg.version || '0.0.0';
  const tag = `v${ver}`;
  try {
    console.log('Creating/fetching release', tag);
    const rel = await createOrGetRelease(token, owner, repo, tag, tag);
    console.log('Release URL:', rel.html_url || rel.url);
    const exe = await findExe('dist');
    if (!exe) { console.error('No .exe found in dist/'); process.exit(3); }
    console.log('Found asset:', exe);
    if (!rel.upload_url) throw new Error('No upload_url on release response');
    await uploadAsset(token, rel.upload_url, exe);
    console.log('Upload success');
    process.exit(0);
  } catch (e) {
    console.error('Error:', e.message || e);
    process.exit(1);
  }
}

main();
