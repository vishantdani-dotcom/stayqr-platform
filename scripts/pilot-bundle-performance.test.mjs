import test from 'node:test'
import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import viteConfig from '../vite.config.js'

const groups = viteConfig.build.rollupOptions.output.codeSplitting.groups
const manualChunk = groups[1].name
const manifest = JSON.parse(readFileSync(new URL('../dist/.vite/manifest.json', import.meta.url), 'utf8'))

function staticClosure(key, visited = new Set()) {
  assert.ok(manifest[key], `Manifest entry exists: ${key}`)
  if (visited.has(key)) return visited
  visited.add(key)
  for (const dependency of manifest[key].imports || []) staticClosure(dependency, visited)
  return visited
}

test('the shared Vite preloader has a dedicated tiny runtime chunk', () => {
  assert.equal(groups[0].name, 'vendor-preload')
  assert.equal(groups[0].test('\0vite/preload-helper.js'), true)
  assert.equal(groups[0].test('/project/src/preload-helper.js'), false)
  assert.ok(groups[0].priority > (groups[1].priority || 0))
})

test('existing vendor groups and application chunking are preserved', () => {
  for (const [modulePath, group] of [
    ['react/index.js', 'vendor-react'],
    ['react-dom/client.js', 'vendor-react'],
    ['@supabase/supabase-js/dist/index.js', 'vendor-supabase'],
    ['jspdf/dist/jspdf.es.min.js', 'vendor-documents'],
    ['html2canvas/dist/html2canvas.js', 'vendor-documents'],
    ['dompurify/dist/purify.es.mjs', 'vendor-documents'],
    ['@dnd-kit/core/dist/index.js', 'vendor-dnd'],
    ['other/index.js', 'vendor'],
  ]) {
    assert.equal(manualChunk(`/project/node_modules/${modulePath}`), group)
    assert.equal(manualChunk(`C:\\project\\node_modules\\${modulePath.replaceAll('/', '\\')}`), group)
  }
  assert.equal(manualChunk('/project/src/App.jsx'), undefined)
})

test('all built app entries exclude document libraries from their static imports', () => {
  const entries = Object.entries(manifest).filter(([, entry]) => entry.isEntry)
  assert.ok(entries.length > 0, 'The built application must have an entry')
  for (const [key] of entries) {
    const files = [...staticClosure(key)].map((dependency) => manifest[dependency].file)
    assert.ok(files.some((file) => /vendor-preload-/.test(file)), 'Shared preload runtime remains reachable')
    assert.ok(!files.some((file) => /vendor-documents-/.test(file)), 'PDF code must not be a startup dependency')
  }
})

test('the lazy invoice route still includes its document library', () => {
  const invoice = manifest['src/pages/invoices/Invoices.jsx']
  assert.ok(invoice?.isDynamicEntry, 'Invoice route remains lazy')
  const files = [...staticClosure('src/pages/invoices/Invoices.jsx')].map((key) => manifest[key].file)
  assert.ok(files.some((file) => /vendor-documents-/.test(file)), 'PDF generation remains available on the invoice route')
  assert.ok(Object.values(manifest).filter((entry) => entry.isDynamicEntry).length >= 48)
})
