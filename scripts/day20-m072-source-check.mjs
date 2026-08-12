import fs from 'node:fs';
import path from 'node:path';

const root = process.cwd();
const migration = path.join(
  root,
  'supabase',
  'migrations',
  '202608120072_day20_checkout_folio_no_synthetic_runtime_compat_FIX_REV1.sql'
);
const audit = path.join(
  root,
  'supabase',
  'audit',
  '202608120082_day20_checkout_folio_no_synthetic_runtime_compat_acceptance_REV1.sql'
);

const checks = [];
const add = (name, pass) => checks.push({ name, pass: Boolean(pass) });

add('migration_present', fs.existsSync(migration));
add('audit_present', fs.existsSync(audit));

const sql = fs.existsSync(migration) ? fs.readFileSync(migration, 'utf8') : '';
const auditSql = fs.existsSync(audit) ? fs.readFileSync(audit, 'utf8') : '';

add('requires_m068_marker', /DAY19_R3_CHECKOUT_FOLIO_RECONCILIATION_REV1/.test(sql));
add('installs_m069_marker', /DAY19_R3_CHECKOUT_FOLIO_NO_SYNTHETIC_PAYMENT_STATUS_REV1/.test(sql));
add('representation_tolerant_decl_removal',
  /replace\(v_def,\s*v_old_decl,\s*''\)/s.test(sql));
add('representation_tolerant_assign_removal',
  /replace\(v_def,\s*v_old_assign,\s*''\)/s.test(sql));
add('fails_if_synthetic_state_remains',
  /authoritative_paid_remaining remains after repair/i.test(sql));
add('postcommit_gate_present', /M072_POSTCOMMIT/.test(sql));
add('audit_has_6_checks', (auditSql.match(/union all/g) || []).length === 5);

for (const [i, c] of checks.entries()) {
  console.log(`${String(i + 1).padStart(2, '0')}. ${c.pass ? 'PASS' : 'FAIL'} - ${c.name}`);
}
const failed = checks.filter(c => !c.pass);
console.log(`\nRESULT: ${checks.length - failed.length}/${checks.length} PASS`);
if (failed.length) process.exitCode = 1;
