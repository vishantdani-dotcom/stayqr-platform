import process from 'node:process'

const rawUrl = String(process.env.STAYQR_DEPLOY_URL || '').trim()

if (!rawUrl) {
  console.error('FAIL - STAYQR_DEPLOY_URL is required')
  process.exit(1)
}

let baseUrl

try {
  baseUrl = new URL(rawUrl)
} catch {
  console.error('FAIL - STAYQR_DEPLOY_URL must be a valid URL')
  process.exit(1)
}

if (baseUrl.protocol !== 'https:') {
  console.error('FAIL - deployment smoke requires HTTPS')
  process.exit(1)
}

baseUrl.pathname = '/'
baseUrl.search = ''
baseUrl.hash = ''

const requiredHeaders = [
  ['content-security-policy', /default-src 'self'/],
  ['referrer-policy', /strict-origin-when-cross-origin/],
  ['x-content-type-options', /nosniff/i],
  ['x-frame-options', /deny/i],
  ['permissions-policy', /camera=\(\)/],
  ['strict-transport-security', /max-age=31536000/],
]

async function get(url) {
  const response = await fetch(url, {
    redirect: 'follow',
    headers: {
      'user-agent': 'StayQR-Day18-Deploy-Smoke/1.0',
    },
  })

  if (!response.ok) {
    throw new Error(`${url} returned HTTP ${response.status}`)
  }

  return response
}

const rootResponse = await get(baseUrl)
const rootHtml = await rootResponse.text()

if (!/<div[^>]+id=["']root["']/i.test(rootHtml)) {
  throw new Error('root deployment response is not the StayQR SPA shell')
}

for (const [name, expectation] of requiredHeaders) {
  const value = rootResponse.headers.get(name) || ''

  if (!expectation.test(value)) {
    throw new Error(
      `required response header ${name} is missing or invalid`
    )
  }

  console.log(`PASS header - ${name}`)
}

const scriptSources = [...rootHtml.matchAll(
  /<script[^>]+src=["']([^"']+)["']/gi
)].map((match) => match[1])

const builtScriptSource = scriptSources.find((source) =>
  /(?:^|\/)assets\/[^/?#]+\.js(?:[?#].*)?$/i.test(source)
)

if (!builtScriptSource) {
  throw new Error(
    `built JavaScript asset was not found in index HTML; script sources: ${scriptSources.join(', ') || 'none'}`
  )
}

console.log(`PASS - built JavaScript asset discovered: ${builtScriptSource}`)

const assetUrl = new URL(builtScriptSource, baseUrl)
const assetResponse = await get(assetUrl)
const assetCache = assetResponse.headers.get('cache-control') || ''

if (!/max-age=31536000/i.test(assetCache) ||
    !/immutable/i.test(assetCache)) {
  throw new Error('built asset does not have immutable cache headers')
}

console.log('PASS - built JavaScript asset is reachable and immutable')

const deepUrl = new URL('/app', baseUrl)
const deepResponse = await get(deepUrl)
const deepHtml = await deepResponse.text()

if (!/<div[^>]+id=["']root["']/i.test(deepHtml)) {
  throw new Error('SPA deep-link rewrite did not return the app shell')
}

console.log('PASS - SPA deep-link rewrite')
console.log(`PASS - live deployment smoke: ${baseUrl.origin}`)
