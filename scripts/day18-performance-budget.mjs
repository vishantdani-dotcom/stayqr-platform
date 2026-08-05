import fs from 'node:fs'
import path from 'node:path'
import { gzipSync } from 'node:zlib'

const root = process.cwd()
const dist = path.join(root, 'dist')
const manifestCandidates = [
  path.join(dist, '.vite', 'manifest.json'),
  path.join(dist, 'manifest.json'),
]

const manifestPath = manifestCandidates.find((candidate) => fs.existsSync(candidate))
if (!manifestPath) {
  throw new Error('Day 18 performance gate requires a Vite manifest. Run npm run build first.')
}

const manifest = JSON.parse(fs.readFileSync(manifestPath, 'utf8'))
const entries = Object.entries(manifest)
const fileToManifestKey = new Map(
  entries
    .filter(([, value]) => typeof value?.file === 'string')
    .map(([key, value]) => [value.file, key])
)

function positiveNumberFromEnv(name, fallback) {
  const value = Number(process.env[name] || fallback)
  if (!Number.isFinite(value) || value <= 0) {
    throw new Error(`${name} must be a positive number.`)
  }
  return value
}

const budgets = {
  MAX_INITIAL_JS_GZIP_KB: positiveNumberFromEnv('STAYQR_MAX_INITIAL_JS_GZIP_KB', 355),
  MAX_SINGLE_JS_GZIP_KB: positiveNumberFromEnv('STAYQR_MAX_SINGLE_JS_GZIP_KB', 450),
  MAX_TOTAL_JS_GZIP_KB: positiveNumberFromEnv('STAYQR_MAX_TOTAL_JS_GZIP_KB', 1800),
  MAX_SINGLE_CSS_GZIP_KB: positiveNumberFromEnv('STAYQR_MAX_SINGLE_CSS_GZIP_KB', 100),
  MIN_DYNAMIC_ENTRIES: positiveNumberFromEnv('STAYQR_MIN_DYNAMIC_ENTRIES', 20),
}

function collectFiles(directory) {
  if (!fs.existsSync(directory)) return []

  return fs.readdirSync(directory, { withFileTypes: true }).flatMap((entry) => {
    const absolutePath = path.join(directory, entry.name)
    return entry.isDirectory() ? collectFiles(absolutePath) : [absolutePath]
  })
}

function measureFile(absolutePath) {
  const bytes = fs.readFileSync(absolutePath)
  return {
    file: path.relative(dist, absolutePath).replaceAll('\\', '/'),
    gzipBytes: gzipSync(bytes, { level: 9 }).length,
    rawBytes: bytes.length,
  }
}

function toKb(bytes) {
  return Number((bytes / 1024).toFixed(1))
}

function collectStaticImports(manifestKey, visited = new Set()) {
  if (!manifestKey || visited.has(manifestKey)) return visited
  visited.add(manifestKey)

  const item = manifest[manifestKey]
  for (const importedKey of item?.imports || []) {
    collectStaticImports(importedKey, visited)
  }

  return visited
}

const assetFiles = collectFiles(path.join(dist, 'assets'))
const jsFiles = assetFiles.filter((file) => file.endsWith('.js')).map(measureFile)
const cssFiles = assetFiles.filter((file) => file.endsWith('.css')).map(measureFile)
const dynamicEntries = entries.filter(([, value]) => value?.isDynamicEntry)
const applicationEntries = entries.filter(([, value]) => value?.isEntry)

if (applicationEntries.length === 0) {
  throw new Error('Vite manifest does not contain an application entry.')
}

const measuredByFile = new Map(jsFiles.map((item) => [item.file, item]))
const initialFiles = new Set()

for (const [entryKey, entry] of applicationEntries) {
  const closure = collectStaticImports(entryKey)
  closure.add(entryKey)

  for (const manifestKey of closure) {
    const file = manifest[manifestKey]?.file
    if (file?.endsWith('.js')) initialFiles.add(file)
  }

  if (entry.file?.endsWith('.js')) initialFiles.add(entry.file)
}

const initialJsGzipBytes = [...initialFiles].reduce(
  (total, file) => total + (measuredByFile.get(file)?.gzipBytes || 0),
  0
)
const totalJsGzipBytes = jsFiles.reduce((total, item) => total + item.gzipBytes, 0)
const largestJs = jsFiles.toSorted((a, b) => b.gzipBytes - a.gzipBytes)[0]
const largestCss = cssFiles.toSorted((a, b) => b.gzipBytes - a.gzipBytes)[0]

const checks = [
  {
    label: 'initial JavaScript gzip',
    actual: toKb(initialJsGzipBytes),
    limit: budgets.MAX_INITIAL_JS_GZIP_KB,
    unit: 'KiB',
    pass: toKb(initialJsGzipBytes) <= budgets.MAX_INITIAL_JS_GZIP_KB,
  },
  {
    label: 'largest JavaScript chunk gzip',
    actual: toKb(largestJs?.gzipBytes || 0),
    limit: budgets.MAX_SINGLE_JS_GZIP_KB,
    unit: 'KiB',
    pass: toKb(largestJs?.gzipBytes || 0) <= budgets.MAX_SINGLE_JS_GZIP_KB,
  },
  {
    label: 'total JavaScript gzip',
    actual: toKb(totalJsGzipBytes),
    limit: budgets.MAX_TOTAL_JS_GZIP_KB,
    unit: 'KiB',
    pass: toKb(totalJsGzipBytes) <= budgets.MAX_TOTAL_JS_GZIP_KB,
  },
  {
    label: 'largest CSS chunk gzip',
    actual: toKb(largestCss?.gzipBytes || 0),
    limit: budgets.MAX_SINGLE_CSS_GZIP_KB,
    unit: 'KiB',
    pass: toKb(largestCss?.gzipBytes || 0) <= budgets.MAX_SINGLE_CSS_GZIP_KB,
  },
  {
    label: 'dynamic route entries',
    actual: dynamicEntries.length,
    limit: budgets.MIN_DYNAMIC_ENTRIES,
    unit: 'minimum',
    pass: dynamicEntries.length >= budgets.MIN_DYNAMIC_ENTRIES,
  },
]

console.log('StayQR Day 18 production performance budget')
console.log(`Manifest: ${path.relative(root, manifestPath).replaceAll('\\', '/')}`)
console.log(`JavaScript chunks: ${jsFiles.length}`)
console.log(`Dynamic entries: ${dynamicEntries.length}`)
console.log(`Initial files: ${[...initialFiles].join(', ')}`)
console.log(`Largest JavaScript: ${largestJs?.file || 'none'}`)
console.log(`Largest CSS: ${largestCss?.file || 'none'}`)

for (const check of checks) {
  const comparison = check.unit === 'minimum' ? '>=' : '<='
  console.log(
    `${check.pass ? 'PASS' : 'FAIL'} required - ${check.label}: ${check.actual} ${check.unit} ${comparison} ${check.limit} ${check.unit}`
  )
}

const orphanManifestFiles = entries
  .map(([, value]) => value?.file)
  .filter((file) => typeof file === 'string' && !fileToManifestKey.has(file))

if (orphanManifestFiles.length > 0) {
  throw new Error(`Manifest file mapping failed for: ${orphanManifestFiles.join(', ')}`)
}

const failures = checks.filter((check) => !check.pass)
if (failures.length > 0) {
  throw new Error(
    `Day 18 performance budget failed: ${failures.map((item) => item.label).join(', ')}`
  )
}

console.log(
  `PASS - Day 18 production performance budget (${dynamicEntries.length} dynamic entries; ${toKb(initialJsGzipBytes)} KiB initial JS gzip; ${toKb(totalJsGzipBytes)} KiB total JS gzip)`
)
