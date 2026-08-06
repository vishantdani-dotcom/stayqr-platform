import process from 'node:process'

const required = [
  'VITE_SUPABASE_URL',
  'VITE_SUPABASE_ANON_KEY',
  'VITE_APP_ENV',
  'VITE_APP_RELEASE',
]

const placeholderPattern =
  /(YOUR_|PLACEHOLDER|CHANGEME|EXAMPLE|undefined|null)/i
const forbiddenBrowserKeyPattern =
  /^VITE_.*(SERVICE[_-]?ROLE|SECRET|PRIVATE|DATABASE[_-]?URL)/i

const errors = []

for (const name of required) {
  const value = String(process.env[name] || '').trim()

  if (!value) {
    errors.push(`${name} is required`)
    continue
  }

  if (placeholderPattern.test(value)) {
    errors.push(`${name} still contains a placeholder`)
  }
}

const appEnv = String(process.env.VITE_APP_ENV || '').trim().toLowerCase()
const release = String(process.env.VITE_APP_RELEASE || '').trim()

if (!['development', 'staging', 'production'].includes(appEnv)) {
  errors.push(
    'VITE_APP_ENV must be development, staging or production'
  )
}

let appUrl

try {
  appUrl = new URL(String(process.env.VITE_SUPABASE_URL || ''))
} catch {
  errors.push('VITE_SUPABASE_URL must be a valid URL')
}

if (appUrl) {
  const localDevelopment =
    appEnv === 'development' &&
    ['localhost', '127.0.0.1'].includes(appUrl.hostname)

  if (!localDevelopment && appUrl.protocol !== 'https:') {
    errors.push(
      'Non-local Supabase URLs must use HTTPS'
    )
  }

  if (
    !localDevelopment &&
    !appUrl.hostname.endsWith('.supabase.co')
  ) {
    errors.push(
      'Hosted Supabase URL must end with .supabase.co'
    )
  }
}

if (
  ['staging', 'production'].includes(appEnv) &&
  /^(local|dev|development|unknown|latest)$/i.test(release)
) {
  errors.push(
    'Staging and production require a traceable release identifier'
  )
}

for (const key of Object.keys(process.env)) {
  if (forbiddenBrowserKeyPattern.test(key)) {
    errors.push(
      `Forbidden browser-exposed environment variable name: ${key}`
    )
  }
}

const stagingUrl = String(
  process.env.STAYQR_STAGING_SUPABASE_URL || ''
).trim()
const productionUrl = String(
  process.env.STAYQR_PRODUCTION_SUPABASE_URL || ''
).trim()

if (stagingUrl && productionUrl) {
  try {
    const staging = new URL(stagingUrl)
    const production = new URL(productionUrl)

    if (staging.href === production.href) {
      errors.push(
        'Staging and production Supabase URLs must be different'
      )
    }

    if (staging.hostname === production.hostname) {
      errors.push(
        'Staging and production must not use the same Supabase project'
      )
    }
  } catch {
    errors.push(
      'STAYQR staging/production comparison URLs must be valid'
    )
  }
}

if (errors.length > 0) {
  for (const error of errors) {
    console.error(`FAIL - ${error}`)
  }

  process.exit(1)
}

const projectHost = appUrl?.hostname || 'unknown'

console.log(`PASS - environment: ${appEnv}`)
console.log(`PASS - release is traceable: ${release}`)
console.log(`PASS - Supabase host shape: ${projectHost}`)
console.log('PASS - no privileged key name is browser-exposed')
console.log('PASS - Day 18 environment separation guard')
