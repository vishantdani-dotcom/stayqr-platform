import crypto from 'node:crypto'
import fs from 'node:fs'
import path from 'node:path'
import process from 'node:process'

const root = process.cwd()
const activeDirectory = path.join(root, 'supabase', 'migrations')
const archiveDirectory = path.join(
  root,
  'docs',
  'database',
  'legacy-migrations',
  'pre-day18-canonical-baseline'
)
const baselineName =
  '202608060060_day18_canonical_schema_baseline_REV1.sql'
const hardeningName =
  '202608060061_day18_default_privilege_hardening_REV1.sql'
const sourceSchemaHash =
  '553a964549977d07915044852b718d4caa2251cf9c6a8267e712457dc1f7044e'

function fail(message) {
  console.error(`FAIL required - ${message}`)
  process.exit(1)
}

function pass(message) {
  console.log(`PASS required - ${message}`)
}

function blocked(message) {
  console.log(`PASS blocked - ${message}`)
}

function read(relativePath) {
  const fullPath = path.join(root, relativePath)
  if (!fs.existsSync(fullPath)) fail(`missing ${relativePath}`)
  return fs.readFileSync(fullPath, 'utf8')
}

if (!fs.existsSync(activeDirectory)) fail('missing supabase/migrations')
if (!fs.existsSync(archiveDirectory)) fail('missing legacy migration archive')

const activeFiles = fs
  .readdirSync(activeDirectory)
  .filter((name) => name.endsWith('.sql'))
  .sort()

const approvedForwardMigrations = [
  '202608080062_day19_existing_object_acl_repair_REV1.sql',
  '202608080063_day19_guest_access_signing_key_seed_repair_REV1.sql',
  '202608080064_day19_days15_18_acl_compatibility_repair_REV1.sql',
  '202608090065_day19_days15_18_acl_canonicalization_REV1.sql',
  '202608090066_day19_business_day_settings_invariant_REV1.sql',
  '202608090067_day19_gate19c_anonymous_surface_storage_restoration_REV1.sql',
  '202608090069_day19_hotel_onboarding_cross_tenant_rls_hardening_REV1.sql',
  '202608101020_day19_housekeeping_template_onboarding_repair.sql',
  '202608101021_day19_checkout_settlement_folio_repair.sql',
  '202608110067_day19_guest_guide_future_hotel_bootstrap_repair_REV1.sql',
  '202608110068_day19_checkout_folio_collection_reconciliation_REV1.sql',
  '202608110069_day19_checkout_folio_no_synthetic_payment_status_REV1.sql',
]
const expectedActive = [
  baselineName,
  hardeningName,
  ...approvedForwardMigrations,
]
if (JSON.stringify(activeFiles) !== JSON.stringify(expectedActive)) {
  fail(`active migration set differs: ${activeFiles.join(', ')}`)
}

pass('canonical Day 18 foundation plus approved Day 19 forward migration chain')

// DAY19F_HOUSEKEEPING_TEMPLATE_REPAIR_SOURCE_CONTRACT_REV2
const day19fHousekeepingRepair =
  read('supabase/migrations/202608101020_day19_housekeeping_template_onboarding_repair.sql')

const day19fHousekeepingRepairContracts = [
  ['Day 19F housekeeping repair is transactional', /\bbegin\s*;/i],
  ['Day 19F housekeeping repair backfills hotels', /ensure_default_housekeeping_template\(hotel_row\.id\)/i],
  ['Day 19F housekeeping repair installs future-hotel trigger', /hotels_day19_default_housekeeping_template/i],
  ['Day 19F housekeeping repair preserves existing active template', /if\s+existing_template_id\s+is\s+not\s+null\s+then/i],
  ['Day 19F housekeeping repair includes eight-item baseline', /'final-condition'[\s\S]*?'sort_order'\s*,\s*80/i],
  ['Day 19F housekeeping repair blocks browser helper execution', /revoke\s+all\s+on\s+function[\s\S]*?ensure_default_housekeeping_template\(uuid\)[\s\S]*?from\s+public\s*,\s*anon\s*,\s*authenticated\s*;/i],
  ['Day 19F housekeeping repair verifies missing-template coverage', /one or more hotels still lack an active room-cleaning template/i],
  ['Day 19F housekeeping repair commits after verification', /\bcommit\s*;/i],
]

for (const [label, pattern] of day19fHousekeepingRepairContracts) {
  if (!pattern.test(day19fHousekeepingRepair)) fail(label)
  pass(`required - ${label}`)
}


const versions = activeFiles.map((name) => name.slice(0, 14))
if (new Set(versions).size !== versions.length) {
  fail('duplicate active migration versions')
}
pass('unique active migration versions')

const baseline = read(`supabase/migrations/${baselineName}`)
const hardening = read(`supabase/migrations/${hardeningName}`)
// ============================================================================
// DAY 19 MIGRATION 062 - EXISTING-OBJECT ACL REPAIR SOURCE CONTRACT
// ============================================================================

const aclRepairName = approvedForwardMigrations[0]
const aclRepair = read(`supabase/migrations/${aclRepairName}`)

if (!aclRepair.trim()) {
  fail('Day 19 ACL repair migration is empty')
}

const aclRepairContracts = [
  [
    'Day 19 ACL repair is transactional',
    /\bbegin\s*;/i,
  ],
  [
    'Day 19 ACL repair protects hotel_guest_content',
    /revoke\s+all\s+on\s+table\s+public\.hotel_guest_content\s+from\s+public\s*,\s*anon\s*,\s*authenticated\s*;/i,
  ],
  [
    'Day 19 ACL repair protects guest_feedback',
    /revoke\s+all\s+on\s+table\s+public\.guest_feedback\s+from\s+public\s*,\s*anon\s*,\s*authenticated\s*;/i,
  ],
  [
    'Day 19 ACL repair protects guest_review_rewards',
    /revoke\s+all\s+on\s+table\s+public\.guest_review_rewards\s+from\s+public\s*,\s*anon\s*,\s*authenticated\s*;/i,
  ],
  [
    'Day 19 ACL repair blocks anonymous amenity writes',
    /revoke\s+all\s+on\s+table\s+public\.amenities\s+from\s+public\s*,\s*anon\s*;/i,
  ],
  [
    'Day 19 ACL repair blocks anonymous token-table access',
    /revoke\s+all\s+on\s+table\s+public\.guest_access_tokens\s+from\s+public\s*,\s*anon\s*;/i,
  ],
  [
    'Day 19 ACL repair blocks anonymous content-read RPC',
    /revoke\s+all\s+on\s+function\s+public\.get_hotel_guest_content\s*\(\s*uuid\s*,\s*text\s*\)\s+from\s+public\s*,\s*anon\s*;/i,
  ],
  [
    'Day 19 ACL repair blocks anonymous content-write RPC',
    /revoke\s+all\s+on\s+function\s+public\.upsert_hotel_guest_content\s*\(\s*uuid\s*,\s*text\s*,\s*jsonb\s*\)\s+from\s+public\s*,\s*anon\s*;/i,
  ],
  [
    'Day 19 ACL repair restores authenticated content read',
    /grant\s+select\s+on\s+table\s+public\.hotel_guest_content\s+to\s+authenticated\s*;/i,
  ],
  [
    'Day 19 ACL repair contains verification block',
    /Migration 062 verification failed:/i,
  ],
  [
    'Day 19 ACL repair commits only after verification',
    /\bcommit\s*;/i,
  ],
]

for (const [label, pattern] of aclRepairContracts) {
  if (!pattern.test(aclRepair)) {
    fail(label)
  }
}

pass(
  `Day 19 existing-object ACL repair source contract (${aclRepairContracts.length} required controls)`
)

// ============================================================================
// DAY 19 MIGRATION 063 - GUEST SIGNING-KEY SEED REPAIR SOURCE CONTRACT
// ============================================================================

const signingKeyRepairName = approvedForwardMigrations[1]
const signingKeyRepair = read(`supabase/migrations/${signingKeyRepairName}`)

if (!signingKeyRepair.trim()) {
  fail('Day 19 signing-key repair migration is empty')
}

const signingKeyRepairContracts = [
  [
    'Day 19 signing-key repair is transactional',
    /\bbegin\s*;/i,
  ],
  [
    'Day 19 signing-key repair uses an advisory transaction lock',
    /pg_advisory_xact_lock\s*\(/i,
  ],
  [
    'Day 19 signing-key repair preserves the one-active unique index',
    /create\s+unique\s+index\s+if\s+not\s+exists\s+uq_guest_access_one_active_signing_key[\s\S]*?where\s+status\s*=\s*'active'\s*;/i,
  ],
  [
    'Day 19 signing-key repair generates a 32-byte secret',
    /extensions\.gen_random_bytes\s*\(\s*32\s*\)/i,
  ],
  [
    'Day 19 signing-key repair is idempotent',
    /where\s+not\s+exists\s*\([\s\S]*?from\s+private\.guest_access_signing_keys[\s\S]*?where\s+status\s*=\s*'active'[\s\S]*?\)\s*;/i,
  ],
  [
    'Day 19 signing-key repair keeps browser roles off signing material',
    /revoke\s+all\s+on\s+private\.guest_access_signing_keys\s+from\s+public\s*,\s*anon\s*,\s*authenticated\s*;/i,
  ],
  [
    'Day 19 signing-key repair verifies exactly one active key',
    /v_active_count\s*<>\s*1/i,
  ],
  [
    'Day 19 signing-key repair verifies 32-byte active key material',
    /octet_length\s*\(\s*k\.secret\s*\)\s*<>\s*32/i,
  ],
  [
    'Day 19 signing-key repair rejects ambiguous multi-active state',
    /v_active_count\s*>\s*1/i,
  ],
  [
    'Day 19 signing-key repair does not expose the signing secret',
    /Never return the secret itself\./i,
  ],
  [
    'Day 19 signing-key repair commits only after verification',
    /\bcommit\s*;/i,
  ],
]

for (const [label, pattern] of signingKeyRepairContracts) {
  if (!pattern.test(signingKeyRepair)) {
    fail(label)
  }
}

pass(
  `Day 19 guest signing-key seed repair source contract (${signingKeyRepairContracts.length} required controls)`
)

// ============================================================================
// DAY 19 MIGRATION 064 - DAYS 15-18 ACL COMPATIBILITY SOURCE CONTRACT
// ============================================================================

const days15to18AclRepairName = approvedForwardMigrations[2]
const days15to18AclRepair = read(
  `supabase/migrations/${days15to18AclRepairName}`
)

if (!days15to18AclRepair.trim()) {
  fail('Day 19 Days 15-18 ACL compatibility repair migration is empty')
}

const days15to18AclRepairContracts = [
  [
    'Day 19 Days 15-18 ACL repair is transactional',
    /\bbegin\s*;/i,
  ],
  [
    'Day 19 Days 15-18 ACL repair uses an advisory transaction lock',
    /pg_advisory_xact_lock\s*\(/i,
  ],
  [
    'Day 15 operational table writes are RPC-only',
    /revoke\s+insert\s*,\s*update\s*,\s*delete\s*,\s*truncate\s*,\s*references\s*,\s*trigger[\s\S]*?public\.food_orders[\s\S]*?public\.service_escalations[\s\S]*?from\s+public\s*,\s*anon\s*,\s*authenticated\s*;/i,
  ],
  [
    'Day 15 staff RPC anonymous execution is closed',
    /revoke\s+all\s+on\s+function\s+public\.update_food_order_status\s*\([\s\S]*?\)\s+from\s+public\s*,\s*anon\s*;/i,
  ],
  [
    'Day 16 report RPC anonymous execution is closed',
    /revoke\s+all\s+on\s+function\s+public\.get_report_filter_options\s*\(\s*uuid\s*\)\s+from\s+public\s*,\s*anon\s*;/i,
  ],
  [
    'Day 17 data-plane tables are reset to authenticated read-only',
    /revoke\s+all\s+on\s+table[\s\S]*?public\.notification_event_catalog[\s\S]*?public\.business_day_settings[\s\S]*?from\s+public\s*,\s*anon\s*,\s*authenticated\s*;[\s\S]*?grant\s+select\s+on\s+table[\s\S]*?to\s+authenticated\s*;/i,
  ],
  [
    'Day 17 public RPCs are authenticated-only',
    /revoke\s+all\s+on\s+function[\s\S]*?public\.get_notification_inbox[\s\S]*?public\.upsert_manual_whatsapp_template[\s\S]*?from\s+public\s*,\s*anon\s*,\s*authenticated\s*;[\s\S]*?grant\s+execute\s+on\s+function[\s\S]*?to\s+authenticated\s*;/i,
  ],
  [
    'Day 18 trusted pagination denies anonymous execution',
    /revoke\s+all\s+on\s+function\s+public\.get_reservations_page[\s\S]*?from\s+public\s*,\s*anon\s*;/i,
  ],
  [
    'Day 18 monitoring table remains RPC-only',
    /revoke\s+all\s+on\s+table\s+public\.operational_error_events\s+from\s+public\s*,\s*anon\s*,\s*authenticated\s*;/i,
  ],
  [
    'Day 18 monitoring RPCs deny anonymous execution',
    /revoke\s+all\s+on\s+function\s+public\.report_operational_error\s*\(\s*uuid\s*,\s*jsonb\s*\)\s+from\s+public\s*,\s*anon\s*;/i,
  ],
  [
    'Day 19 Days 15-18 ACL repair contains verification',
    /Migration 064 verification failed:/i,
  ],
  [
    'Day 19 Days 15-18 ACL repair is business-data DML free',
    !/\b(?:insert\s+into|update|delete\s+from)\s+public\./i.test(
      days15to18AclRepair
    ),
  ],
  [
    'Day 19 Days 15-18 ACL repair commits after verification',
    /\bcommit\s*;/i,
  ],
]

for (const [label, contract] of days15to18AclRepairContracts) {
  const ok =
    contract instanceof RegExp
      ? contract.test(days15to18AclRepair)
      : contract

  if (!ok) {
    fail(label)
  }
}

pass(
  `Day 19 Days 15-18 ACL compatibility repair source contract (${days15to18AclRepairContracts.length} required controls)`
)
// ============================================================================
// DAY 19 MIGRATION 065 - DAYS 15-18 ACL CANONICALIZATION SOURCE CONTRACT
// ============================================================================

const days15to18AclCanonicalizationName = approvedForwardMigrations[3]
const days15to18AclCanonicalization = read(
  `supabase/migrations/${days15to18AclCanonicalizationName}`
)

if (!days15to18AclCanonicalization.trim()) {
  fail('Day 19 Days 15-18 ACL canonicalization migration is empty')
}

const days15to18AclCanonicalizationContracts = [
  [
    'Day 19 ACL canonicalization is transactional',
    /\bbegin\s*;/i,
  ],
  [
    'Day 19 ACL canonicalization uses an advisory transaction lock',
    /pg_advisory_xact_lock\s*\(/i,
  ],
  [
    'Day 19 ACL canonicalization re-hardens table defaults',
    /alter\s+default\s+privileges\s+for\s+role\s+postgres\s+in\s+schema\s+public[\s\S]*?revoke\s+all\s+on\s+tables\s+from\s+anon\s*,\s*authenticated\s*;/i,
  ],
  [
    'Day 19 ACL canonicalization re-hardens function defaults',
    /alter\s+default\s+privileges\s+for\s+role\s+postgres\s+in\s+schema\s+public[\s\S]*?revoke\s+all\s+on\s+functions\s+from\s+anon\s*,\s*authenticated\s*;/i,
  ],
  [
    'Day 15 operational tables receive a full browser ACL reset',
    /revoke\s+all\s+privileges\s+on\s+table[\s\S]*?public\.food_orders[\s\S]*?public\.service_escalations[\s\S]*?from\s+public\s*,\s*anon\s*,\s*authenticated\s*;/i,
  ],
  [
    'Day 15 authenticated operational access is read-only',
    /grant\s+select\s+on\s+table[\s\S]*?public\.food_orders[\s\S]*?public\.service_escalations[\s\S]*?to\s+authenticated\s*;/i,
  ],
  [
    'Day 15 staff RPCs receive a full browser ACL reset',
    /revoke\s+all\s+privileges\s+on\s+function[\s\S]*?public\.update_food_order_status[\s\S]*?public\.save_menu_locale_translations[\s\S]*?from\s+public\s*,\s*anon\s*,\s*authenticated\s*;/i,
  ],
  [
    'Day 16 report RPCs receive a full browser ACL reset',
    /revoke\s+all\s+privileges\s+on\s+function[\s\S]*?public\.get_report_filter_options[\s\S]*?public\.get_report_export_rows[\s\S]*?from\s+public\s*,\s*anon\s*,\s*authenticated\s*;/i,
  ],
  [
    'Day 17 tables receive a full browser ACL reset',
    /revoke\s+all\s+privileges\s+on\s+table[\s\S]*?public\.notification_event_catalog[\s\S]*?public\.business_day_settings[\s\S]*?from\s+public\s*,\s*anon\s*,\s*authenticated\s*;/i,
  ],
  [
    'Day 18 monitoring table remains API closed',
    /revoke\s+all\s+privileges\s+on\s+table\s+public\.operational_error_events\s+from\s+public\s*,\s*anon\s*,\s*authenticated\s*;/i,
  ],
  [
    'Day 19 ACL canonicalization verifies default ACL recurrence',
    /unsafe\s+anon\/authenticated\s+default\s+ACL/i,
  ],
  [
    'Day 19 ACL canonicalization has a pre-commit failure gate',
    /Migration\s+065\s+verification\s+failed:/i,
  ],
  [
    'Day 19 ACL canonicalization contains post-COMMIT verification',
    /M065_POSTCOMMIT/i,
  ],
  [
    'Day 19 ACL canonicalization is business-data DML free',
    !/\b(?:insert\s+into|update|delete\s+from)\s+public\./i.test(
      days15to18AclCanonicalization
    ),
  ],
]

for (const [label, contract] of days15to18AclCanonicalizationContracts) {
  const ok =
    contract instanceof RegExp
      ? contract.test(days15to18AclCanonicalization)
      : contract

  if (!ok) {
    fail(label)
  }
}

pass(
  `Day 19 Days 15-18 ACL canonicalization source contract (${days15to18AclCanonicalizationContracts.length} required controls)`
)

// ============================================================================
// DAY 19 MIGRATION 066 - BUSINESS-DAY SETTINGS INVARIANT SOURCE CONTRACT
// ============================================================================

const businessDayInvariantName = approvedForwardMigrations[4]
const businessDayInvariant = read(
  `supabase/migrations/${businessDayInvariantName}`
)

if (!businessDayInvariant.trim()) {
  fail('Day 19 business-day settings invariant migration is empty')
}

const businessDayInvariantContracts = [
  [
    'Day 19 business-day invariant is transactional',
    /\bbegin\s*;/i,
  ],
  [
    'Day 19 business-day invariant uses an advisory transaction lock',
    /pg_advisory_xact_lock\s*\(/i,
  ],
  [
    'Day 19 business-day invariant creates a future-hotel trigger helper',
    /create\s+or\s+replace\s+function\s+private\.day19_ensure_business_day_settings_for_hotel\s*\(\s*\)/i,
  ],
  [
    'Day 19 business-day invariant creates an AFTER INSERT hotel trigger',
    /create\s+trigger\s+day19_ensure_business_day_settings_after_hotel_insert[\s\S]*?after\s+insert\s+on\s+public\.hotels/i,
  ],
  [
    'Day 19 business-day invariant backfills missing hotel settings only',
    /insert\s+into\s+public\.business_day_settings[\s\S]*?from\s+public\.hotels[\s\S]*?where\s+not\s+exists/i,
  ],
  [
    'Day 19 business-day trigger helper is API-closed',
    /revoke\s+all\s+on\s+function\s+private\.day19_ensure_business_day_settings_for_hotel\s*\(\s*\)[\s\S]*?from\s+public\s*,\s*anon\s*,\s*authenticated\s*;/i,
  ],
  [
    'Day 19 business-day invariant verifies zero missing hotels',
    /Migration\s+066\s+verification\s+failed:\s*%\s+hotel\(s\)\s+still\s+lack\s+business-day\s+settings/i,
  ],
  [
    'Day 19 business-day invariant contains post-COMMIT evidence',
    /M066_POSTCOMMIT/i,
  ],
]

for (const [label, pattern] of businessDayInvariantContracts) {
  if (!pattern.test(businessDayInvariant)) {
    fail(label)
  }
}

pass(
  `Day 19 business-day settings invariant source contract (${businessDayInvariantContracts.length} required controls)`
)

// ============================================================================
// DAY 19 MIGRATION 067 - GATE 19C ANON SURFACE + STORAGE SOURCE CONTRACT
// ============================================================================

const gate19cSecurityName = approvedForwardMigrations[5]
const gate19cSecurity = read(
  `supabase/migrations/${gate19cSecurityName}`
)

if (!gate19cSecurity.trim()) {
  fail('Day 19 Gate 19C security migration is empty')
}

const gate19cSecurityContracts = [
  [
    'Gate 19C security migration is transactional',
    /\bbegin\s*;/i,
  ],
  [
    'Gate 19C closes anonymous direct public tables globally',
    /revoke\s+all\s+privileges\s+on\s+all\s+tables\s+in\s+schema\s+public\s+from\s+public\s*,\s*anon\s*;/i,
  ],
  [
    'Gate 19C closes PUBLIC and anon function execute globally',
    /revoke\s+execute\s+on\s+all\s+functions\s+in\s+schema\s+public\s+from\s+public\s*,\s*anon\s*;/i,
  ],
  [
    'Gate 19C hardens future PUBLIC function defaults',
    /alter\s+default\s+privileges[\s\S]*?revoke\s+execute\s+on\s+functions\s+from\s+public\s*;/i,
  ],
  [
    'Gate 19C restores exact signed guest surface',
    /grant\s+execute\s+on\s+function[\s\S]*?cancel_guest_food_order[\s\S]*?verify_invoice[\s\S]*?to\s+anon\s*;/i,
  ],
  [
    'Gate 19C restores private hotel-assets bucket',
    /'hotel-assets'[\s\S]*?false[\s\S]*?10485760/i,
  ],
  [
    'Gate 19C restores private guest-documents bucket',
    /'guest-documents'[\s\S]*?false[\s\S]*?15728640/i,
  ],
  [
    'Gate 19C preserves public guest-guide-media delivery',
    /'guest-guide-media'[\s\S]*?true[\s\S]*?8388608/i,
  ],
  [
    'Gate 19C uses latest guest-document permission matrix',
    /stayqr_guest_documents_select[\s\S]*?user_has_any_permission[\s\S]*?checkout\.manage/i,
  ],
  [
    'Gate 19C restores guest-guide-media tenant write policies',
    /stayqr_guest_guide_media_insert[\s\S]*?stayqr_guest_guide_media_delete/i,
  ],
  [
    'Gate 19C verifies anonymous table closure',
    /anon retains effective DML/i,
  ],
  [
    'Gate 19C contains post-COMMIT verification',
    /M067_POSTCOMMIT/i,
  ],
]

for (const [label, pattern] of gate19cSecurityContracts) {
  if (!pattern.test(gate19cSecurity)) {
    fail(label)
  }
}

pass(
  `Day 19 Gate 19C anonymous surface + Storage source contract (${gate19cSecurityContracts.length} required controls)`
)

// ============================================================================
// DAY 19 MIGRATION 069 - HOTEL ONBOARDING CROSS-TENANT RLS HARDENING
// ============================================================================

const gate19cOnboardingRlsName = approvedForwardMigrations[6]
const gate19cOnboardingRls = read(
  `supabase/migrations/${gate19cOnboardingRlsName}`
)

if (!gate19cOnboardingRls.trim()) {
  fail('Day 19 Gate 19C hotel_onboarding RLS migration is empty')
}

const gate19cOnboardingRlsContracts = [
  [
    'Gate 19C hotel_onboarding RLS migration is transactional',
    /\bbegin\s*;/i,
  ],
  [
    'Gate 19C hotel_onboarding RLS replaces INSERT policy',
    /drop\s+policy\s+if\s+exists\s+stayqr_hotel_onboarding_insert[\s\S]*?create\s+policy\s+stayqr_hotel_onboarding_insert/i,
  ],
  [
    'Gate 19C hotel_onboarding INSERT is same-hotel hotel.manage scoped',
    /create\s+policy\s+stayqr_hotel_onboarding_insert[\s\S]*?user_has_permission\s*\(\s*hotel_id\s*,\s*'hotel\.manage'\s*\)/i,
  ],
  [
    'Gate 19C hotel_onboarding RLS replaces UPDATE policy',
    /drop\s+policy\s+if\s+exists\s+stayqr_hotel_onboarding_update[\s\S]*?create\s+policy\s+stayqr_hotel_onboarding_update/i,
  ],
  [
    'Gate 19C hotel_onboarding UPDATE is same-hotel hotel.manage scoped',
    /create\s+policy\s+stayqr_hotel_onboarding_update[\s\S]*?using\s*\([\s\S]*?user_has_permission\s*\(\s*hotel_id\s*,\s*'hotel\.manage'\s*\)[\s\S]*?with\s+check\s*\([\s\S]*?user_has_permission\s*\(\s*hotel_id\s*,\s*'hotel\.manage'\s*\)/i,
  ],
  [
    'Gate 19C hotel_onboarding RLS verifies INSERT owner bypass is absent',
    /owner_user_id remains in direct INSERT authorization/i,
  ],
  [
    'Gate 19C hotel_onboarding RLS verifies UPDATE owner bypass is absent',
    /owner_user_id remains in direct UPDATE authorization/i,
  ],
  [
    'Gate 19C hotel_onboarding RLS preserves bootstrap RPC boundary',
    /public\.bootstrap_hotel_onboarding\s*\(\s*jsonb\s*\)/i,
  ],
  [
    'Gate 19C hotel_onboarding RLS preserves resumable-step RPC boundary',
    /public\.save_hotel_onboarding_step\s*\(\s*uuid\s*,\s*text\s*,\s*jsonb\s*\)/i,
  ],
  [
    'Gate 19C hotel_onboarding RLS contains post-COMMIT evidence',
    /M069_POSTCOMMIT/i,
  ],
]

for (const [label, pattern] of gate19cOnboardingRlsContracts) {
  if (!pattern.test(gate19cOnboardingRls)) {
    fail(label)
  }
}

pass(
  `Day 19 Gate 19C hotel_onboarding RLS source contract (${gate19cOnboardingRlsContracts.length} required controls)`
)

const canonicalRunbook = read(
  'docs/operations/DAY18_CANONICAL_DATABASE_BASELINE.md'
)
const archiveReadme = read(
  'docs/database/legacy-migrations/pre-day18-canonical-baseline/README.md'
)
const operationsPage = read(
  'src/pages/operationscenter/OperationsCenter.jsx'
)

if (!baseline.includes(`Source schema SHA-256: ${sourceSchemaHash}`)) {
  fail('baseline source-schema provenance hash')
}
pass('baseline source-schema provenance hash')

for (const [label, text] of [
  ['canonical baseline runbook', canonicalRunbook],
  ['legacy migration archive README', archiveReadme],
]) {
  if (!text.includes(baselineName) || !text.includes(hardeningName)) {
    fail(`${label} does not name the active migrations`)
  }

  if (
    text.includes('$' + 'baselineName') ||
    text.includes('$' + 'hardeningName')
  ) {
    fail(`${label} contains unresolved template placeholders`)
  }

  if (/[ --]/.test(text)) {
    fail(`${label} contains control characters`)
  }

  if (/(?:\u00c3.|\u00c2.|\u00e2\u20ac|\u00e2\u20ac\u00a6)/.test(text)) {
    fail(`${label} contains mojibake`)
  }
}
pass('canonical baseline documentation integrity')

if (/(?:\u00c3.|\u00c2.|\u00e2\u20ac|\u00e2\u20ac\u00a6)/.test(operationsPage)) {
  fail('Operations Center contains mojibake')
}
pass('Operations Center diagnostic copy encoding')

if (
  !baseline.includes('StayQR canonical baseline refused: target is not empty') ||
  !baseline.includes("WHERE schemaname = 'public'")
) {
  fail('empty-target production safety guard')
}
pass('empty-target production safety guard')

for (const contract of [
  'CREATE TABLE IF NOT EXISTS "public"."analytics_events"',
  'CREATE TABLE IF NOT EXISTS "public"."operational_error_events"',
  'CREATE OR REPLACE FUNCTION "public"."get_operational_diagnostics"',
  'CREATE OR REPLACE FUNCTION "public"."get_day18_query_health"',
  'idx_d18_reservations_cursor',
  'idx_d18_activity_logs_cursor',
]) {
  if (!baseline.includes(contract)) fail(`baseline contract ${contract}`)
}
pass('Day 1-18 schema and Day 18 diagnostics contracts present')

if (/^\s*COPY\s+(?:"public"\.|public\.)/im.test(baseline)) {
  fail('production public-row COPY found in canonical baseline')
}
blocked('production public-row COPY absent')

if (baseline.includes('rbyirbovbkguzvwijyaj')) {
  fail('production project reference embedded in baseline')
}
blocked('production project reference absent from baseline')

for (const objectType of ['TABLES', 'SEQUENCES', 'FUNCTIONS']) {
  const pattern = new RegExp(
    `ALTER DEFAULT PRIVILEGES[\\s\\S]*?REVOKE ALL ON ${objectType} FROM anon, authenticated;`,
    'i'
  )
  if (!pattern.test(hardening)) {
    fail(`default ${objectType.toLowerCase()} privileges hardened`)
  }
}
pass('future table, sequence and function defaults hardened')

if (!hardening.includes('v_unsafe_default_acl_count')) {
  fail('default ACL runtime assertion')
}
pass('default ACL runtime assertion')

const archivedFiles = fs
  .readdirSync(archiveDirectory)
  .filter((name) => name.endsWith('.sql'))
  .sort()

if (archivedFiles.length < 50) {
  fail(`legacy archive unexpectedly small (${archivedFiles.length})`)
}
pass(`legacy migration archive preserved (${archivedFiles.length} SQL files)`)

for (const requiredName of [
  '202607200001_tenant_foundation_and_guarded_repairs.sql',
  '202608050056_day17_notification_activity_support_settings_foundation_REV2_JSON_SYNTAX_FIX.sql',
  '202608050057_day17_rls_helper_trusted_config_rpc_hotfix_REV1.sql',
  '202608050058_day18_indexes_query_plans_trusted_pagination_REV1.sql',
  '202608050059_day18_monitoring_structured_logs_operational_diagnostics_REV1.sql',
]) {
  if (!archivedFiles.includes(requiredName)) {
    fail(`legacy archive missing ${requiredName}`)
  }
}
pass('critical Day 1, Day 17 and Day 18 source migrations preserved')

const manifestPath = path.join(archiveDirectory, 'SHA256SUMS.txt')
if (!fs.existsSync(manifestPath)) fail('legacy SHA256 manifest missing')
const manifestLines = fs
  .readFileSync(manifestPath, 'utf8')
  .split(/\r?\n/)
  .filter(Boolean)
const manifest = new Map(
  manifestLines.map((line) => {
    const match = line.match(/^([0-9a-f]{64})\s{2}(.+)$/i)
    if (!match) fail(`invalid legacy manifest line: ${line}`)
    return [match[2], match[1].toLowerCase()]
  })
)

function sha256(bytes) {
  return crypto.createHash('sha256').update(bytes).digest('hex')
}

for (const name of archivedFiles) {
  const bytes = fs.readFileSync(path.join(archiveDirectory, name))
  const expected = manifest.get(name)
  const rawHash = sha256(bytes)

  if (expected === rawHash) continue

  const text = bytes.toString('utf8')
  const lfHash = sha256(
    Buffer.from(text.replace(/\r\n/g, '\n'), 'utf8')
  )
  const crlfHash = sha256(
    Buffer.from(text.replace(/\r?\n/g, '\r\n'), 'utf8')
  )

  if (expected !== lfHash && expected !== crlfHash) {
    fail(`legacy hash mismatch ${name}`)
  }
}

pass('legacy migration archive hashes verified')

console.log(
  `PASS - Day 18 canonical baseline source gate ` +
    `(${activeFiles.length} active migrations; ${archivedFiles.length} archived migrations; ` +
    `empty-target guard; default privileges hardened)`
)


// DAY19F_CHECKOUT_SETTLEMENT_FOLIO_REPAIR_SOURCE_CONTRACT_REV1
const day19fCheckoutSettlementFolioRepair =
  read('supabase/migrations/202608101021_day19_checkout_settlement_folio_repair.sql')

const day19fCheckoutSettlementFolioRepairContracts = [
  ['Day 19F checkout-settlement folio repair is transactional', /\bbegin\s*;/i],
  ['Day 19F checkout-settlement payment trigger is guarded', /payment_type[\s\S]*?checkout_settlement/i],
  ['Day 19F checkout-settlement remains collection-backed', /day11_sync_payment_collection\(new\.id\)/i],
  ['Day 19F checkout-settlement prevents duplicate folio charge', /must not be a folio charge/i],
  ['Day 19F checkout-settlement repair verifies residue', /posted settlement-as-charge residue/i],
  ['Day 19F checkout-settlement repair commits', /\bcommit\s*;/i],
]

for (const [label, pattern] of day19fCheckoutSettlementFolioRepairContracts) {
  if (!pattern.test(day19fCheckoutSettlementFolioRepair)) fail(label)
  pass(`required - ${label}`)
}


// DAY19_R3_CHECKOUT_FOLIO_SOURCE_CONTRACT_REV1
const day19R3CheckoutFolioSource =
  read('supabase/migrations/202608110068_day19_checkout_folio_collection_reconciliation_REV1.sql')
const day19R3GuestsSource =
  read('src/pages/guests/Guests.jsx')

const day19R3CheckoutFolioContracts = [
  ['Day19 R3 checkout uses authoritative folio collections in DB', /from public\.folios f/i.test(day19R3CheckoutFolioSource)],
  ['Day19 R3 checkout merges proven folio paid amount', /previously_paid := greatest\(previously_paid, folio_paid_amount\)/i.test(day19R3CheckoutFolioSource)],
  ['Day19 R3 checkout UI reads folio collection amount', /from\(["']folios["']\)[\s\S]{0,220}collection_amount/i.test(day19R3GuestsSource)],
  ['Day19 R3 checkout UI retains legacy compatibility', /legacyCheckoutPaidAmount[\s\S]{0,220}legacyPaidAmount/i.test(day19R3GuestsSource)],
]

for (const [label, ok] of day19R3CheckoutFolioContracts) {
  if (!ok) fail(label)
  pass(`required - ${label}`)
}

// DAY19_R3_CHECKOUT_FOLIO_NO_SYNTHETIC_SOURCE_CONTRACT_REV1
const day19R3NoSyntheticCheckout =
  read('supabase/migrations/202608110069_day19_checkout_folio_no_synthetic_payment_status_REV1.sql')

if (!/DAY19_R3_CHECKOUT_FOLIO_NO_SYNTHETIC_PAYMENT_STATUS_REV1/i.test(day19R3NoSyntheticCheckout)) {
  fail('Day19 R3 checkout no-synthetic-payment-status repair source contract')
}
if (!/v_def := replace\(v_def, v_old_loop, v_new_loop\)/i.test(day19R3NoSyntheticCheckout)) {
  fail('Day19 R3 checkout repair must replace the synthetic payment-status block')
}
if (!/DAY19_R3_CHECKOUT_FOLIO_NO_SYNTHETIC_PAYMENT_STATUS_REV1/i.test(day19R3NoSyntheticCheckout)) {
  fail('Day19 R3 checkout repair corrective runtime marker must be present')
}
pass('required - Day19 R3 checkout no-synthetic-payment-status repair source contract')