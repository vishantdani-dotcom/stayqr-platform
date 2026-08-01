import { access, readdir, readFile } from 'node:fs/promises'
import { dirname, extname, join, resolve } from 'node:path'

const root = resolve(process.cwd())
const sourceRoot = join(root, 'src')
const sourceExtensions = ['.js', '.jsx', '.css', '.png', '.svg']
const importPattern = /(?:import\s+(?:[^'";]+?\s+from\s+)?|import\s*\()\s*['"]([^'"]+)['"]/g

async function collect(directory) {
  const entries = await readdir(directory, { withFileTypes: true })
  const files = []

  for (const entry of entries) {
    const path = join(directory, entry.name)
    if (entry.isDirectory()) files.push(...(await collect(path)))
    else if (['.js', '.jsx'].includes(extname(entry.name))) files.push(path)
  }

  return files
}

async function exists(path) {
  try {
    await access(path)
    return true
  } catch {
    return false
  }
}

async function resolveImport(fromFile, specifier) {
  const base = resolve(dirname(fromFile), specifier)
  if (await exists(base)) return base

  for (const extension of sourceExtensions) {
    if (await exists(`${base}${extension}`)) return `${base}${extension}`
  }

  for (const extension of ['.js', '.jsx']) {
    const indexPath = join(base, `index${extension}`)
    if (await exists(indexPath)) return indexPath
  }

  return null
}

const failures = []
const files = await collect(sourceRoot)
let checked = 0

for (const file of files) {
  const contents = await readFile(file, 'utf8')
  for (const match of contents.matchAll(importPattern)) {
    const specifier = match[1]
    if (!specifier.startsWith('.')) continue
    checked += 1
    if (!(await resolveImport(file, specifier))) {
      failures.push(`${file}: unresolved import ${specifier}`)
    }
  }
}

if (failures.length > 0) {
  failures.forEach((failure) => console.error(`FAIL — ${failure}`))
  process.exitCode = 1
} else {
  console.log(`PASS — Resolved ${checked} relative frontend imports.`)
}
