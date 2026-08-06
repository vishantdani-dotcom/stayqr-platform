import fs from 'node:fs'
import path from 'node:path'
import process from 'node:process'

const root = process.cwd()

const files = {
  package: 'package.json',
  gitignore: '.gitignore',
  netlify: 'netlify.toml',
  workflow: '.github/workflows/day18-production-validation.yml',
  environmentGuard: 'scripts/day18-environment-guard.mjs',
  liveSmoke: 'scripts/day18-live-deploy-smoke.mjs',
  fingerprint: 'scripts/day18-db-fingerprint.ps1',
  backup: 'scripts/day18-backup-create.ps1',
  restore: 'scripts/day18-restore-drill.ps1',
  environmentRunbook:
    'docs/operations/DAY18_ENVIRONMENT_SEPARATION.md',
  backupRunbook:
    'docs/operations/DAY18_BACKUP_RESTORE_DRILL.md',
  securityRunbook:
    'docs/operations/DAY18_SECURITY_HEADERS_RATE_LIMITING.md',
  cicdRunbook:
    'docs/operations/DAY18_CICD_DEPLOYMENT_VALIDATION.md',
}

function read(relativePath) {
  const fullPath = path.join(root, relativePath)

  if (!fs.existsSync(fullPath)) {
    console.error(`FAIL required - missing ${relativePath}`)
    process.exit(1)
  }

  return fs.readFileSync(fullPath, 'utf8')
}

const packageText = read(files.package)
const gitignore = read(files.gitignore)
const netlify = read(files.netlify)
const workflow = read(files.workflow)
const environmentGuard = read(files.environmentGuard)
const liveSmoke = read(files.liveSmoke)
const fingerprint = read(files.fingerprint)
const backup = read(files.backup)
const restore = read(files.restore)
const environmentRunbook = read(files.environmentRunbook)
const backupRunbook = read(files.backupRunbook)
const securityRunbook = read(files.securityRunbook)
const cicdRunbook = read(files.cicdRunbook)

let packageJson

try {
  packageJson = JSON.parse(packageText)
} catch {
  console.error('FAIL required - package JSON valid')
  process.exit(1)
}

const scripts = packageJson.scripts || {}

const required = [
  [
    'infrastructure source command',
    scripts['security:day18infra'] ===
      'node scripts/day18-infrastructure-source-check.mjs',
  ],
  [
    'environment guard command',
    scripts['env:day18'] ===
      'node scripts/day18-environment-guard.mjs',
  ],
  [
    'infrastructure validation chain',
    typeof scripts['validate:day18infra'] === 'string' &&
      scripts['validate:day18infra'].includes(
        'npm run validate:day18monitoring'
      ) &&
      scripts['validate:day18infra'].includes(
        'node scripts/day18-a072-source-check.mjs'
      ) &&
      scripts['validate:day18infra'].includes(
        'npm run security:day18infra'
      ) &&
      scripts['validate:day18infra'].includes(
        'npm run env:day18'
      ),
  ],
  [
    'local evidence ignored',
    gitignore.includes('.stayqr-evidence/'),
  ],
  [
    'Netlify build command',
    /\[build\][\s\S]*?command\s*=\s*"npm run build"/.test(netlify),
  ],
  [
    'Netlify dist publish',
    /\[build\][\s\S]*?publish\s*=\s*"dist"/.test(netlify),
  ],
  [
    'Netlify Node 22',
    /NODE_VERSION\s*=\s*"22"/.test(netlify),
  ],
  [
    'production environment label',
    /\[context\.production\.environment\][\s\S]*?VITE_APP_ENV\s*=\s*"production"/.test(
      netlify
    ),
  ],
  [
    'preview environment label',
    /\[context\.deploy-preview\.environment\][\s\S]*?VITE_APP_ENV\s*=\s*"staging"/.test(
      netlify
    ),
  ],
  [
    'branch environment label',
    /\[context\.branch-deploy\.environment\][\s\S]*?VITE_APP_ENV\s*=\s*"staging"/.test(
      netlify
    ),
  ],
  [
    'guest route rate limit',
    /from\s*=\s*"\/guest\/\*"[\s\S]*?\[redirects\.rate_limit\][\s\S]*?window_limit\s*=\s*120[\s\S]*?window_size\s*=\s*60[\s\S]*?aggregate_by\s*=\s*\["ip",\s*"domain"\]/.test(
      netlify
    ),
  ],
  [
    'site route rate limit',
    /from\s*=\s*"\/\*"[\s\S]*?\[redirects\.rate_limit\][\s\S]*?window_limit\s*=\s*600[\s\S]*?window_size\s*=\s*60[\s\S]*?aggregate_by\s*=\s*\["ip",\s*"domain"\]/.test(
      netlify
    ),
  ],
  [
    'SPA rewrite',
    /from\s*=\s*"\/\*"[\s\S]*?to\s*=\s*"\/index\.html"[\s\S]*?status\s*=\s*200/.test(
      netlify
    ),
  ],
  [
    'content security policy',
    netlify.includes('Content-Security-Policy') &&
      netlify.includes("default-src 'self'") &&
      netlify.includes("object-src 'none'") &&
      netlify.includes("frame-ancestors 'none'") &&
      netlify.includes(
        "connect-src 'self' https://*.supabase.co wss://*.supabase.co"
      ),
  ],
  [
    'HSTS header',
    /Strict-Transport-Security\s*=\s*"max-age=31536000"/.test(
      netlify
    ),
  ],
  [
    'MIME header',
    /X-Content-Type-Options\s*=\s*"nosniff"/.test(netlify),
  ],
  [
    'frame header',
    /X-Frame-Options\s*=\s*"DENY"/.test(netlify),
  ],
  [
    'referrer header',
    /Referrer-Policy\s*=\s*"strict-origin-when-cross-origin"/.test(
      netlify
    ),
  ],
  [
    'permissions header',
    netlify.includes(
      'Permissions-Policy = "camera=(), microphone=(), geolocation=(), payment=(), usb=()"'
    ),
  ],
  [
    'immutable asset cache',
    /for\s*=\s*"\/assets\/\*"[\s\S]*?Cache-Control\s*=\s*"public, max-age=31536000, immutable"/.test(
      netlify
    ),
  ],
  [
    'HTML revalidation cache',
    /for\s*=\s*"\/index\.html"[\s\S]*?Cache-Control\s*=\s*"public, max-age=0, must-revalidate"/.test(
      netlify
    ),
  ],
  [
    'workflow read-only permissions',
    /permissions:\s*\n\s+contents:\s+read/.test(workflow),
  ],
  [
    'workflow concurrency',
    workflow.includes('cancel-in-progress: true'),
  ],
  [
    'workflow checkout pinned major',
    workflow.includes('actions/checkout@v6'),
  ],
  [
    'workflow Node setup pinned major',
    workflow.includes('actions/setup-node@v7'),
  ],
  [
    'workflow Node 22',
    workflow.includes("node-version: '22'"),
  ],
  [
    'workflow exact install',
    workflow.includes('npm ci --no-audit --no-fund'),
  ],
  [
    'workflow complete validation',
    workflow.includes('npm run validate:day18infra'),
  ],
  [
    'workflow build artifact',
    workflow.includes('actions/upload-artifact@v4') &&
      workflow.includes('dist') &&
      workflow.includes('if-no-files-found: error'),
  ],
  [
    'workflow optional live smoke',
    workflow.includes('workflow_dispatch:') &&
      workflow.includes('deploy_url:') &&
      workflow.includes(
        'node scripts/day18-live-deploy-smoke.mjs'
      ),
  ],
  [
    'environment required variables',
    [
      'VITE_SUPABASE_URL',
      'VITE_SUPABASE_ANON_KEY',
      'VITE_APP_ENV',
      'VITE_APP_RELEASE',
    ].every((value) => environmentGuard.includes(value)),
  ],
  [
    'environment labels restricted',
    environmentGuard.includes(
      "['development', 'staging', 'production']"
    ),
  ],
  [
    'environment HTTPS enforcement',
    environmentGuard.includes(
      "Non-local Supabase URLs must use HTTPS"
    ),
  ],
  [
    'environment project separation',
    environmentGuard.includes(
      'Staging and production must not use the same Supabase project'
    ),
  ],
  [
    'browser privileged-variable rejection',
    environmentGuard.includes(
      'Forbidden browser-exposed environment variable name'
    ),
  ],
  [
    'live smoke HTTPS',
    liveSmoke.includes(
      "deployment smoke requires HTTPS"
    ),
  ],
  [
    'live smoke security headers',
    [
      'content-security-policy',
      'strict-transport-security',
      'x-content-type-options',
      'x-frame-options',
      'permissions-policy',
    ].every((value) => liveSmoke.includes(value)),
  ],
  [
    'live smoke immutable asset',
    liveSmoke.includes('max-age=31536000') &&
      liveSmoke.includes('immutable'),
  ],
  [
    'live smoke SPA deep link',
    liveSmoke.includes("new URL('/app', baseUrl)") &&
      liveSmoke.includes('SPA deep-link rewrite'),
  ],
  [
    'fingerprint uses exact public counts',
    fingerprint.includes(
      "select count(*) from public.`\"$quoted`\";"
    ) &&
      fingerprint.includes('public_table_row_counts'),
  ],
  [
    'fingerprint excludes row content',
    fingerprint.includes(
      'database fingerprint written without row content'
    ),
  ],
  [
    'backup uses official role dump',
    backup.includes('--role-only') &&
      backup.includes('roles.sql'),
  ],
  [
    'backup uses schema dump',
    backup.includes('schema.sql') &&
      backup.includes('Dumping schema'),
  ],
  [
    'backup uses COPY data dump',
    backup.includes('--use-copy') &&
      backup.includes('--data-only') &&
      backup.includes('data.sql'),
  ],
  [
    'backup excludes vector storage metadata',
    backup.includes('storage.buckets_vectors') &&
      backup.includes('storage.vector_indexes'),
  ],
  [
    'backup preserves migration history',
    backup.includes('--schema supabase_migrations') &&
      backup.includes('history_schema.sql') &&
      backup.includes('history_data.sql'),
  ],
  [
    'backup creates hashes and manifest',
    backup.includes('SHA256SUMS.txt') &&
      backup.includes('manifest.json'),
  ],
  [
    'restore requires disposable confirmation',
    restore.includes(
      'RESTORE_TO_DISPOSABLE_TARGET'
    ),
  ],
  [
    'restore blocks same source and target',
    restore.includes(
      'Source and restore target URLs must be different'
    ) &&
      restore.includes(
        'Source and restore target database hosts must be different'
      ),
  ],
  [
    'restore verifies backup hashes',
    restore.includes('Backup integrity check failed'),
  ],
  [
    'restore uses single transaction and stop-on-error',
    restore.includes('--single-transaction') &&
      restore.includes('ON_ERROR_STOP=1'),
  ],
  [
    'restore disables triggers for data',
    restore.includes(
      'SET session_replication_role = replica'
    ),
  ],
  [
    'restore compares table counts',
    restore.includes(
      'Row-count mismatch for public.$tableName'
    ),
  ],
  [
    'restore compares migration history',
    restore.includes(
      'Migration history does not match after restore'
    ),
  ],
  [
    'environment runbook names three environments',
    ['development', 'staging', 'production'].every((value) =>
      environmentRunbook.includes(value)
    ),
  ],
  [
    'backup runbook declares storage boundary',
    backupRunbook.includes(
      'not the actual object bytes'
    ) &&
      backupRunbook.includes(
        'must be completed separately'
      ),
  ],
  [
    'security runbook does not overclaim API protection',
    securityRunbook.includes(
      'They do not magically protect'
    ) &&
      securityRunbook.includes(
        'sent directly to Supabase'
      ),
  ],
  [
    'CI/CD runbook requires live evidence',
    cicdRunbook.includes(
      'Netlify post-processing log'
    ) &&
      cicdRunbook.includes(
        'A source-only pass is not the final Day 18 exit gate'
      ),
  ],
]

const blocked = [
  [
    'unsafe eval in CSP',
    /unsafe-eval/i.test(netlify),
  ],
  [
    'wildcard script source',
    /script-src[^;]*\*/i.test(netlify),
  ],
  [
    'wildcard connect source',
    /connect-src[^;]*\s\*(?:\s|;)/i.test(netlify),
  ],
  [
    'pull_request_target workflow',
    /\bpull_request_target\b/.test(workflow),
  ],
  [
    'write-all workflow permissions',
    /permissions:\s*write-all/i.test(workflow),
  ],
  [
    'continue-on-error bypass',
    /continue-on-error:\s*true/i.test(workflow),
  ],
  [
    'floating latest action or CLI',
    /uses:\s*[^\s]+@(?:master|main|latest)\b|@latest\b/i.test(
      workflow
    ),
  ],
  [
    'non-lockfile install',
    /\bnpm install\b/.test(workflow),
  ],
  [
    'hard-coded database password',
    /postgresql:\/\/[^:\s]+:[^@\s]+@/i.test(
      [
        workflow,
        netlify,
        environmentGuard,
        liveSmoke,
        fingerprint,
        backup,
        restore,
      ].join('\n')
    ),
  ],
  [
    'service-role key in executable config',
    /SUPABASE_SERVICE_ROLE_KEY|VITE_.*SERVICE_ROLE/i.test(
      [
        workflow,
        netlify,
        environmentGuard,
        liveSmoke,
        fingerprint,
        backup,
        restore,
      ].join('\n')
    ),
  ],
  [
    'raw database URL written to evidence',
    /Set-Content[\s\S]{0,300}(SOURCE_DB_URL|RESTORE_DB_URL)|ConvertTo-Json[\s\S]{0,300}(sourceDbUrl|targetDbUrl)/i.test(
      backup + '\n' + restore
    ),
  ],
  [
    'production restore bypass',
    /RESTORE_TO_PRODUCTION|ALLOW_PRODUCTION_RESTORE/i.test(
      restore
    ),
  ],
]

let failed = false

for (const [label, passed] of required) {
  if (passed) {
    console.log(`PASS required - ${label}`)
  } else {
    failed = true
    console.error(`FAIL required - ${label}`)
  }
}

for (const [label, present] of blocked) {
  if (!present) {
    console.log(`PASS blocked - ${label}`)
  } else {
    failed = true
    console.error(`FAIL blocked - ${label}`)
  }
}

if (failed) {
  process.exit(1)
}

console.log(
  `PASS - Day 18 infrastructure source gate ` +
    `(${required.length} required contracts; ` +
    `${blocked.length} unsafe patterns blocked)`
)
