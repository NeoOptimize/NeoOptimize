'use strict'

const crypto = require('crypto')
const fs = require('fs')
const path = require('path')

const ROOT = path.resolve(__dirname, '..')
const DEFAULT_CLIENT = path.join(ROOT, 'client')
const DEFAULT_STAGED = path.join(ROOT, 'installer/client')
const REPORT_DIR = path.join(ROOT, 'reports/prebuild')
const REPORT_PATH = path.join(REPORT_DIR, 'neooptimize-prebuild-check.json')

function sha256File (file) {
  return crypto.createHash('sha256').update(fs.readFileSync(file)).digest('hex')
}

function exists (file) {
  return fs.existsSync(file)
}

function read (file) {
  return fs.readFileSync(file, 'utf8')
}

function rel (file) {
  return path.relative(ROOT, file).replace(/\\/g, '/')
}

function parseArgs (argv) {
  const args = { staged: null, client: DEFAULT_CLIENT, writeReport: true }
  for (let i = 0; i < argv.length; i += 1) {
    const item = argv[i]
    if (item === '--staged') args.staged = path.resolve(argv[++i] || DEFAULT_STAGED)
    else if (item === '--client') args.client = path.resolve(argv[++i] || DEFAULT_CLIENT)
    else if (item === '--no-report') args.writeReport = false
    else if (item === '--help') args.help = true
  }
  return args
}

function usage () {
  return [
    'Usage: node tools/verify-public-bundle.js [--client client-dir] [--staged installer/client]',
    '',
    'Validates public NeoOptimize bundle readiness before rebuilding the installer.'
  ].join('\n')
}

function addFailure (failures, message, detail = {}) {
  failures.push({ message, detail })
}

function addWarning (warnings, message, detail = {}) {
  warnings.push({ message, detail })
}

function listFiles (root) {
  const out = []
  function walk (dir) {
    if (!exists(dir)) return
    for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
      const full = path.join(dir, entry.name)
      if (entry.isDirectory()) walk(full)
      else out.push(full)
    }
  }
  walk(root)
  return out
}

function parseValidateSetActions (content) {
  const match = content.match(/\[ValidateSet\(([\s\S]*?)\)\]\s*\[string\]\$Action/)
  if (!match) return []
  return [...match[1].matchAll(/"([^"]+)"/g)].map(item => item[1])
}

function parseUiActions (content) {
  const actions = new Set()
  for (const match of content.matchAll(/@\{[^\r\n]*Action\s*=\s*"([^"]+)"/g)) actions.add(match[1])
  for (const match of content.matchAll(/Start-NeoAction\s+"([^"]+)"/g)) actions.add(match[1])
  return [...actions]
}

function parseModuleActionMap (content) {
  const map = {}
  const fn = content.match(/function\s+Resolve-NeoModuleAction\s*\{([\s\S]*?)function\s+Resolve-NeoMaintenanceAction/)
  if (!fn) return map
  for (const match of fn[1].matchAll(/"([^"]+\.ps1)"\s*=\s*"([^"]+)"/g)) {
    map[match[2]] = match[1]
  }
  return map
}

function validateRuntimeTree (root, label, failures, warnings) {
  const required = [
    'NeoOptimize.ps1',
    'NeoOptimize.UI.ps1',
    'NeoOptimize.AIAgent.ps1',
    'NeoOptimize.UpdateManager.ps1',
    'NeoOptimize.Tray.ps1',
    'NeoOptimize.Launcher.ps1',
    'VERSION.txt',
    'assets/NeoOptimize.ico',
    'assets/NeoOptimize.png',
    'config/NeoOptimize.ModelAgent.json',
    'config/NeoOptimize.Bundle.json',
    'config/NeoOptimize.RMM.json',
    'lib/Common.ps1',
    'lib/NeoCapabilityCatalog.ps1',
    'models/NeoCore.Policy.json',
    'knowledge/neo-ai-corpus.jsonl',
    'knowledge/neo-ai-corpus.manifest.json',
    'modules/01_Cleaner.ps1',
    'modules/02_Performance.ps1',
    'modules/03_Privacy.ps1',
    'modules/04_Network.ps1',
    'modules/05_Security.ps1',
    'modules/06_Services.ps1',
    'modules/07_Updates.ps1',
    'modules/08_Power.ps1',
    'modules/09_Apps.ps1',
    'modules/19_StartupOptimizer.ps1',
    'modules/20_ComponentCleanup.ps1',
    'modules/21_EventLogMaintenance.ps1',
    'modules/22_WindowsFeatureOptimizer.ps1',
    'modules/23_NetworkRepairToolkit.ps1',
    'modules/24_DeviceSnapshot.ps1',
    'modules/25_BenchmarkReport.ps1',
    'modules/26_PrivacyReview.ps1',
    'modules/27_NetworkDiagnostics.ps1',
    'modules/28_ContainerHyperVTuning.ps1',
    'modules/29_ZeroTrustSecurity.ps1',
    'modules/30_GameModeUltra.ps1',
    'modules/31_AINPUCaching.ps1',
    'modules/32_StorageTiering.ps1',
    'modules/33_RemoteAccessReadiness.ps1',
    'modules/34_UpdateRepair.ps1',
    'modules/35_PowerPlanTuning.ps1',
    'modules/36_SecurityAudit.ps1',
    'tools/Invoke-NeoOptimizeSelfTest.ps1'
  ]

  for (const item of required) {
    if (!exists(path.join(root, item))) addFailure(failures, `${label}: missing required file`, { file: item })
  }

  const corpusPath = path.join(root, 'knowledge/neo-ai-corpus.jsonl')
  const manifestPath = path.join(root, 'knowledge/neo-ai-corpus.manifest.json')
  if (exists(corpusPath) && exists(manifestPath)) {
    try {
      const manifest = JSON.parse(read(manifestPath))
      const actual = sha256File(corpusPath)
      if (manifest.corpus_sha256 !== actual) {
        addFailure(failures, `${label}: corpus SHA-256 mismatch`, {
          expected: manifest.corpus_sha256,
          actual
        })
      }
      if (Number(manifest.record_count || 0) < 100) {
        addFailure(failures, `${label}: corpus record count too low`, { record_count: manifest.record_count })
      }
    } catch (err) {
      addFailure(failures, `${label}: invalid corpus manifest`, { error: err.message })
    }
  }

  const enginePath = path.join(root, 'NeoOptimize.ps1')
  const uiPath = path.join(root, 'NeoOptimize.UI.ps1')
  if (exists(enginePath) && exists(uiPath)) {
    const engine = read(enginePath)
    const ui = read(uiPath)
    const validActions = new Set(parseValidateSetActions(engine).map(item => item.toLowerCase()))
    const specialUiActions = new Set(['aimodelsettings'])
    for (const action of parseUiActions(ui)) {
      if (!validActions.has(action.toLowerCase()) && !specialUiActions.has(action.toLowerCase())) {
        addFailure(failures, `${label}: UI action is not routed by NeoOptimize.ps1`, { action })
      }
    }

    const moduleMap = parseModuleActionMap(engine)
    for (const [action, moduleFile] of Object.entries(moduleMap)) {
      if (!exists(path.join(root, 'modules', moduleFile))) {
        addFailure(failures, `${label}: mapped module file missing`, { action, moduleFile })
      }
    }
  }

  const permissionsPath = path.join(root, 'modules/00_Permissions.ps1')
  if (exists(permissionsPath)) {
    const permissions = read(permissionsPath)
    const unsafePermissionPatterns = [
      [/ConsentPromptBehaviorAdmin["'\s`)-]+-Value\s+0/i, 'must not suppress administrator UAC prompts'],
      [/ConsentPromptBehaviorUser["'\s`)-]+-Value\s+0/i, 'must not suppress user UAC prompts'],
      [/PromptOnSecureDesktop["'\s`)-]+-Value\s+0/i, 'must not disable secure desktop prompts'],
      [/fDenyTSConnections["'\s`)-]+-Value\s+0/i, 'must not enable RDP by default'],
      [/Enable-PSRemoting\s+-Force/i, 'must not enable PowerShell remoting by default'],
      [/TrustedHosts\s+-Value\s+["']\*["']/i, 'must not configure TrustedHosts wildcard'],
      [/Set-Service\s+RemoteRegistry\s+-StartupType\s+Automatic/i, 'must not enable RemoteRegistry by default'],
      [/AutoShareWks["'\s`)-]+-Value\s+1/i, 'must not enable administrative shares by default']
    ]
    for (const [pattern, reason] of unsafePermissionPatterns) {
      if (pattern.test(permissions)) {
        addFailure(failures, `${label}: unsafe permissions module`, { reason })
      }
    }
  }

  const privacyPath = path.join(root, 'modules/03_Privacy.ps1')
  if (exists(privacyPath)) {
    const privacy = read(privacyPath)
    const unsafePrivacyPatterns = [
      [/Set-Reg\s+\$privPath\s+["']LetAppsAccess(?:Camera|Microphone|Location)["']\s+2/i, 'must not lock Camera/Microphone/Location through organization AppPrivacy policy'],
      [/Set-Reg\s+\$locPath\s+["']Disable(?:Location|LocationScripting|Sensors)["']\s+1/i, 'must not disable Location/Sensors through organization policy']
    ]
    for (const [pattern, reason] of unsafePrivacyPatterns) {
      if (pattern.test(privacy)) {
        addFailure(failures, `${label}: unsafe privacy module`, { reason })
      }
    }
  }

  const forbidden = [
    /(^|[/\\])server([/\\]|$)/i,
    /(^|[/\\])dashboard([/\\]|$)/i,
    /(^|[/\\])\.git([/\\]|$)/i,
    /(^|[/\\])node_modules([/\\]|$)/i,
    /(^|[/\\])SPICE-Guest-Tools\.exe$/i,
    /(^|[/\\]).*\.pfx$/i,
    /(^|[/\\]).*service.*role.*key/i,
    /(^|[/\\])\.env$/i
  ]
  for (const file of listFiles(root)) {
    const relative = path.relative(root, file).replace(/\\/g, '/')
    if (forbidden.some(pattern => pattern.test(relative))) {
      addFailure(failures, `${label}: forbidden public bundle artifact`, { file: relative })
    }
  }

  if (!exists(path.join(root, 'bin/NeoOptimize.Agent.exe')) && label.includes('staged')) {
    addWarning(warnings, `${label}: public lightweight build has no bundled endpoint sync agent`, {
      expected: 'OK for public builds'
    })
  }
}

function validateInstallerScripts (failures) {
  const buildScript = path.join(ROOT, 'installer/client/build.sh')
  const nsi = path.join(ROOT, 'installer/client/installer.nsi')
  if (exists(buildScript)) {
    const content = read(buildScript)
    if (!content.includes('client/knowledge') || !content.includes('installer/client/knowledge')) {
      addFailure(failures, 'installer build does not stage client/knowledge corpus')
    }
    if (!content.includes('verify-public-bundle.js')) {
      addFailure(failures, 'installer build does not run public bundle verifier')
    }
    if (!content.includes('prepare_rust_ui') || !content.includes('client-nextgen')) {
      addFailure(failures, 'installer build does not prefer the Rust/Tauri UI source')
    }
  }
  if (exists(nsi)) {
    const content = read(nsi)
    if (!/SetOutPath\s+"\$INSTDIR\\program\\knowledge"/i.test(content) || !/File\s+\/r\s+"knowledge\\\*\.\*"/i.test(content)) {
      addFailure(failures, 'NSIS installer does not install program\\knowledge corpus')
    }
    if (!/RMDir\s+\/r\s+"\$INSTDIR\\program\\knowledge"/i.test(content)) {
      addFailure(failures, 'NSIS installer does not clean old program\\knowledge directory before copy')
    }
  }
}

function validateRustUiSource (failures) {
  const rustRoot = path.join(ROOT, 'client-nextgen')
  const required = [
    'package.json',
    'index.html',
    'vite.config.js',
    'src/main.jsx',
    'src/App.jsx',
    'src/styles.css',
    'src-tauri/Cargo.toml',
    'src-tauri/build.rs',
    'src-tauri/tauri.conf.json',
    'src-tauri/src/main.rs'
  ]

  for (const item of required) {
    if (!exists(path.join(rustRoot, item))) addFailure(failures, 'Rust/Tauri UI source missing required file', { file: `client-nextgen/${item}` })
  }

  const packagePath = path.join(rustRoot, 'package.json')
  if (exists(packagePath)) {
    try {
      const pkg = JSON.parse(read(packagePath))
      if (!pkg.scripts || !pkg.scripts.build || !pkg.scripts['tauri:build']) {
        addFailure(failures, 'Rust/Tauri UI package scripts incomplete')
      }
      if (!pkg.dependencies || !pkg.dependencies['@tauri-apps/api'] || !pkg.dependencies.react) {
        addFailure(failures, 'Rust/Tauri UI package dependencies incomplete')
      }
    } catch (err) {
      addFailure(failures, 'Rust/Tauri UI package.json is invalid', { error: err.message })
    }
  }

  const cargoPath = path.join(rustRoot, 'src-tauri/Cargo.toml')
  if (exists(cargoPath)) {
    const cargo = read(cargoPath)
    if (!cargo.includes('tauri') || !cargo.includes('sysinfo') || !cargo.includes('serde')) {
      addFailure(failures, 'Rust/Tauri UI Cargo.toml missing required runtime dependencies')
    }
  }

  const mainPath = path.join(rustRoot, 'src-tauri/src/main.rs')
  if (exists(mainPath)) {
    const main = read(mainPath)
    for (const token of ['get_system_snapshot', 'run_action', 'ask_neo', 'open_voice_command', 'launch_legacy_console_if_requested']) {
      if (!main.includes(token)) addFailure(failures, 'Rust/Tauri backend missing required command bridge', { token })
    }
  }
}

function main () {
  const args = parseArgs(process.argv.slice(2))
  if (args.help) {
    console.log(usage())
    return
  }

  const failures = []
  const warnings = []
  validateRuntimeTree(args.client, 'client', failures, warnings)
  if (args.staged) validateRuntimeTree(args.staged, 'staged installer/client', failures, warnings)
  validateInstallerScripts(failures)
  validateRustUiSource(failures)

  const report = {
    ok: failures.length === 0,
    checked_at: new Date().toISOString(),
    client: rel(args.client),
    staged: args.staged ? rel(args.staged) : null,
    failures,
    warnings
  }

  if (args.writeReport) {
    fs.mkdirSync(REPORT_DIR, { recursive: true })
    fs.writeFileSync(REPORT_PATH, JSON.stringify(report, null, 2) + '\n')
  }

  if (warnings.length) {
    for (const warning of warnings) console.warn(`[WARN] ${warning.message}`)
  }
  if (failures.length) {
    for (const failure of failures) console.error(`[FAIL] ${failure.message}`, failure.detail)
    console.error(`Public bundle verification failed. Report: ${rel(REPORT_PATH)}`)
    process.exit(1)
  }

  console.log(`Public bundle verification passed. Report: ${rel(REPORT_PATH)}`)
}

if (require.main === module) main()
