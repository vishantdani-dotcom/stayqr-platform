import fs from 'node:fs';
import path from 'node:path';

const root = process.cwd();
const migrationPath = path.join(
  root,
  'supabase',
  'migrations',
  '202608120071_day20_operational_error_retention_provenance_recovery_REV1.sql'
);
const auditPath = path.join(
  root,
  'supabase',
  'audit',
  '202608120081_day20_operational_error_retention_provenance_acceptance_REV1.sql'
);
const ownershipPath = path.join(
  root,
  'docs',
  'operations',
  'DAY20_PRODUCTION_OPERATIONAL_OWNERSHIP.md'
);

const checks = [];

function check(name, passed, details = '') {
  checks.push({ name, passed: Boolean(passed), details });
}

check('migration_present', fs.existsSync(migrationPath), migrationPath);
check('audit_present', fs.existsSync(auditPath), auditPath);
check('ownership_present', fs.existsSync(ownershipPath), ownershipPath);

const sql = fs.existsSync(migrationPath)
  ? fs.readFileSync(migrationPath, 'utf8')
  : '';
const audit = fs.existsSync(auditPath)
  ? fs.readFileSync(auditPath, 'utf8')
  : '';
const ownership = fs.existsSync(ownershipPath)
  ? fs.readFileSync(ownershipPath, 'utf8')
  : '';

check(
  'security_definer_present',
  /security\s+definer/i.test(sql)
);
check(
  'search_path_locked',
  /set\s+search_path\s+to\s+'pg_catalog'\s*,\s*'public'\s*,\s*'private'/i.test(sql)
);
check(
  'retention_90_days',
  /interval\s+'90 days'/i.test(sql)
);
check(
  'terminal_statuses_only',
  /status\s+in\s*\(\s*'resolved'\s*,\s*'ignored'\s*\)/i.test(sql)
);
check(
  'cron_schedule_exact',
  /'17 2 \* \* \*'/i.test(sql)
);
check(
  'cron_command_exact',
  /select private\.cleanup_operational_error_events_retention\(\);/i.test(sql)
);
check(
  'browser_execute_revoked',
  /revoke\s+all\s+on\s+function\s+private\.cleanup_operational_error_events_retention\(\)[\s\S]*from\s+public\s*,\s*anon\s*,\s*authenticated\s*,\s*service_role\s*;/i.test(sql)
);
check(
  'audit_has_12_checks',
  (audit.match(/union all/g) || []).length === 11
);
check(
  'operational_owner_recorded',
  /Primary production owner:\s*\*\*Vishant Dani\*\*/i.test(ownership)
);

for (const [index, item] of checks.entries()) {
  console.log(
    `${String(index + 1).padStart(2, '0')}. ${item.passed ? 'PASS' : 'FAIL'} - ${item.name}` +
    (item.details ? ` - ${item.details}` : '')
  );
}

const failed = checks.filter((item) => !item.passed);
console.log(`\nRESULT: ${checks.length - failed.length}/${checks.length} PASS`);

if (failed.length) {
  process.exitCode = 1;
}
