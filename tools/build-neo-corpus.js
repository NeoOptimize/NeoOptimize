'use strict'

const crypto = require('crypto')
const fs = require('fs')
const os = require('os')
const path = require('path')
const { spawnSync } = require('child_process')

const DEFAULT_SOURCES = (process.env.NEO_CORPUS_SOURCES || '')
  .split(path.delimiter)
  .map((item) => item.trim())
  .filter(Boolean)

const DEFAULT_OUTPUTS = [
  'client/knowledge/neo-ai-corpus.jsonl'
]

const DEFAULT_MANIFESTS = [
  'client/knowledge/neo-ai-corpus.manifest.json'
]

function sha256 (value) {
  return crypto.createHash('sha256').update(value).digest('hex')
}

function parseArgs (argv) {
  const args = { sources: [], outputs: [], manifests: [] }
  for (let i = 0; i < argv.length; i += 1) {
    const item = argv[i]
    if (item === '--source') args.sources.push(argv[++i])
    else if (item === '--out') args.outputs.push(argv[++i])
    else if (item === '--manifest') args.manifests.push(argv[++i])
    else if (item === '--help') args.help = true
  }
  if (!args.sources.length) args.sources = DEFAULT_SOURCES
  if (!args.outputs.length) args.outputs = DEFAULT_OUTPUTS
  if (!args.manifests.length) args.manifests = DEFAULT_MANIFESTS
  return args
}

function usage () {
  return `Usage: node tools/build-neo-corpus.js --source FILE [--source FILE] [--out FILE] [--manifest FILE]\n\nBuilds Neo AI local corpus JSONL from TXT/PDF sources. PDF extraction requires pdftotext.\n\nDefault sources can also be supplied through NEO_CORPUS_SOURCES using the platform path delimiter.`
}

function readPdfText (file) {
  const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), 'neo-corpus-'))
  const out = path.join(tmpDir, 'extracted.txt')
  const result = spawnSync('pdftotext', ['-layout', file, out], { encoding: 'utf8' })
  if (result.status !== 0) {
    throw new Error(`pdftotext failed for ${file}: ${result.stderr || result.stdout || result.error?.message || 'unknown error'}`)
  }
  return fs.readFileSync(out, 'utf8')
}

function readSource (file) {
  const ext = path.extname(file).toLowerCase()
  const bytes = fs.readFileSync(file)
  const rawText = ext === '.pdf' ? readPdfText(file) : bytes.toString('utf8')
  return {
    file,
    name: path.basename(file),
    ext,
    bytes: bytes.length,
    sha256: sha256(bytes),
    text: normalizeText(rawText)
  }
}

function normalizeText (text) {
  return String(text || '')
    .replace(/\r\n/g, '\n')
    .replace(/\f/g, '\n')
    .replace(/[ \t]+\n/g, '\n')
    .replace(/\n{4,}/g, '\n\n\n')
    .trim()
}

function headingForLine (line, fallback) {
  const text = line.trim()
  const md = text.match(/^(#{1,6})\s+(.{3,160})$/)
  if (md) return md[2].trim()
  const numbered = text.match(/^(\d+(?:\.\d+)*)\s+([A-Z][A-Za-z0-9 /&().:-]{8,160})$/)
  if (numbered) return text
  return fallback
}

function classifySection (text) {
  const lower = text.toLowerCase()
  const categories = []
  const checks = [
    ['powershell', /\b(get-|set-|new-|remove-|invoke-|restart-|clear-|enable-|disable-)[a-z]/i],
    ['cmd', /\b(sfc|dism|netsh|wmic|chkdsk|ipconfig|sc\.exe|powercfg|bcdedit)\b/i],
    ['registry', /\b(hklm|hkcu|registry|reg add|reg query|group policy|gpo)\b/i],
    ['network', /\b(dns|tcp|ipsec|firewall|netadapter|netsh|network|wifi|wi-fi|adapter)\b/i],
    ['security', /\b(defender|firewall|asr|bitlocker|uac|audit|security|threat|malware)\b/i],
    ['storage', /\b(disk|storage|volume|partition|chkdsk|ntfs|smb|cache)\b/i],
    ['wmi-cim', /\b(wmi|cim|get-ciminstance|win32_)\b/i],
    ['optimization', /\b(optimize|performance|cleanup|startup|service|maintenance)\b/i]
  ]
  for (const [name, re] of checks) {
    if (re.test(lower)) categories.push(name)
  }
  return categories.length ? categories : ['general']
}

function extractKeywords (text) {
  const keywords = new Set()
  const patterns = [
    /\b(?:Get|Set|New|Remove|Invoke|Restart|Clear|Enable|Disable|Add|Stop|Start)-[A-Za-z0-9]+\b/g,
    /\b(?:sfc|dism|netsh|wmic|chkdsk|ipconfig|powercfg|bcdedit|reg(?:\.exe)?)\b/gi,
    /\bHKLM\\[A-Za-z0-9_\\ -]+/g,
    /\bWin32_[A-Za-z0-9_]+\b/g
  ]
  for (const re of patterns) {
    for (const match of text.matchAll(re)) {
      keywords.add(match[0].slice(0, 120))
      if (keywords.size >= 24) return [...keywords]
    }
  }
  return [...keywords]
}

function splitIntoBlocks (source) {
  const lines = source.text.split('\n')
  const blocks = []
  let heading = 'Overview'
  let current = []

  function pushBlock () {
    const text = current.join('\n').trim()
    if (text.length >= 80) blocks.push({ heading, text })
    current = []
  }

  for (const line of lines) {
    const nextHeading = headingForLine(line, null)
    if (nextHeading && current.join('\n').length > 400) {
      pushBlock()
      heading = nextHeading
    } else if (nextHeading) {
      heading = nextHeading
    }
    current.push(line)
  }
  pushBlock()
  return blocks
}

function chunkBlock (block, source, options = {}) {
  const maxChars = options.maxChars || 1600
  const overlap = options.overlap || 180
  const chunks = []
  const text = block.text.replace(/\n{3,}/g, '\n\n').trim()
  let start = 0
  while (start < text.length) {
    let end = Math.min(text.length, start + maxChars)
    if (end < text.length) {
      const boundary = Math.max(
        text.lastIndexOf('\n\n', end),
        text.lastIndexOf('\n', end),
        text.lastIndexOf('. ', end)
      )
      if (boundary > start + 500) end = boundary + 1
    }
    const chunkText = text.slice(start, end).trim()
    if (chunkText.length >= 120) {
      chunks.push({
        source_name: source.name,
        source_path: source.file,
        source_ext: source.ext,
        section: block.heading,
        categories: classifySection(`${block.heading}\n${chunkText}`),
        keywords: extractKeywords(chunkText),
        text: chunkText
      })
    }
    if (end >= text.length) break
    start = Math.max(0, end - overlap)
  }
  return chunks
}

function buildCorpus (sources) {
  const records = []
  const seen = new Set()
  for (const source of sources) {
    for (const block of splitIntoBlocks(source)) {
      for (const chunk of chunkBlock(block, source)) {
        const normalized = chunk.text.replace(/\s+/g, ' ').toLowerCase()
        const contentHash = sha256(normalized)
        if (seen.has(contentHash)) continue
        seen.add(contentHash)
        records.push({
          id: `neo-corpus-${String(records.length + 1).padStart(5, '0')}`,
          schema_version: '1.0',
          corpus: 'neo-ai-windows-admin',
          content_sha256: contentHash,
          ...chunk
        })
      }
    }
  }
  return records
}

function writeJsonl (file, records) {
  fs.mkdirSync(path.dirname(file), { recursive: true })
  fs.writeFileSync(file, records.map(record => JSON.stringify(record)).join('\n') + '\n')
}

function writeManifest (file, manifest) {
  fs.mkdirSync(path.dirname(file), { recursive: true })
  fs.writeFileSync(file, JSON.stringify(manifest, null, 2) + '\n')
}

function main () {
  const args = parseArgs(process.argv.slice(2))
  if (args.help) {
    console.log(usage())
    return
  }
  if (!args.sources.length) {
    console.error('No corpus sources supplied.')
    console.error(usage())
    process.exit(2)
  }

  const sources = args.sources.map(file => readSource(path.resolve(file)))
  const records = buildCorpus(sources)
  const categories = {}
  for (const record of records) {
    for (const category of record.categories) categories[category] = (categories[category] || 0) + 1
  }

  const jsonl = records.map(record => JSON.stringify(record)).join('\n') + '\n'
  const manifest = {
    schema_version: '1.0',
    corpus: 'neo-ai-windows-admin',
    generated_at: new Date().toISOString(),
    record_count: records.length,
    corpus_sha256: sha256(jsonl),
    chunking: { max_chars: 1600, overlap_chars: 180 },
    categories,
    sources: sources.map(source => ({
      name: source.name,
      path: source.file,
      ext: source.ext,
      bytes: source.bytes,
      sha256: source.sha256,
      extracted_chars: source.text.length
    }))
  }

  for (const out of args.outputs) writeJsonl(path.resolve(out), records)
  for (const manifestFile of args.manifests) writeManifest(path.resolve(manifestFile), manifest)
  console.log(JSON.stringify({
    ok: true,
    records: records.length,
    corpus_sha256: manifest.corpus_sha256,
    outputs: args.outputs,
    manifests: args.manifests
  }, null, 2))
}

if (require.main === module) main()
