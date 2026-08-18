const marketingUrl = (process.env.STAYQR_MARKETING_URL || 'https://stayqr.in').replace(/\/$/, '')
const appUrl = (process.env.STAYQR_APP_URL || 'https://app.stayqr.in').replace(/\/$/, '')
const failures = []
const passes = []

async function get(url) {
  const response = await fetch(url, {
    redirect: 'follow',
    signal: AbortSignal.timeout(30000),
    headers: { 'User-Agent': 'StayQR-PostLaunch-Batch1-Smoke/1.0' },
  })
  return { response, body: await response.text() }
}

function gate(name, passed, evidence) {
  const row = { name, passed: Boolean(passed), evidence }
  if (row.passed) passes.push(row)
  else failures.push(row)
}

try {
  const marketing = await get(marketingUrl)
  gate('marketing returns HTTP 200', marketing.response.status === 200, `HTTP ${marketing.response.status}`)
  gate('Hotel Login is published', marketing.body.includes(`${appUrl}/login`) && marketing.body.includes('Hotel Login'), `${appUrl}/login`)
  gate('monthly and yearly selectors are published', marketing.body.includes('data-billing="monthly"') && marketing.body.includes('data-billing="annual"'), 'monthly + annual')

  for (const plan of ['starter', 'growth', 'scale']) {
    gate(
      `${plan} paid acquisition is published`,
      marketing.body.includes(`${appUrl}/signup?plan=${plan}&amp;billing=monthly&amp;mode=paid`),
      `${plan}/paid`
    )
    gate(
      `${plan} trial acquisition is published`,
      marketing.body.includes(`${appUrl}/signup?plan=${plan}&amp;billing=monthly&amp;mode=trial`),
      `${plan}/trial`
    )
  }

  for (const route of ['/login', '/signup?plan=growth&billing=monthly&mode=paid', '/checkout']) {
    const page = await get(`${appUrl}${route}`)
    gate(`app route ${route.split('?')[0]} is served`, page.response.status === 200, `HTTP ${page.response.status}`)
  }
} catch (error) {
  failures.push({ name: 'live request execution', passed: false, evidence: error.message })
}

for (const [index, row] of [...passes, ...failures].entries()) {
  console.log(`${row.passed ? 'PASS' : 'FAIL'} ${String(index + 1).padStart(2, '0')} | ${row.name} | ${row.evidence}`)
}

if (failures.length) {
  console.error(`POSTLAUNCH_BATCH1_LIVE_SMOKE: FAIL (${passes.length}/${passes.length + failures.length})`)
  process.exitCode = 1
} else {
  console.log(`POSTLAUNCH_BATCH1_LIVE_SMOKE: PASS (${passes.length}/${passes.length})`)
}
