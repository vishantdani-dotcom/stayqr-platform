import fs from 'node:fs'

const checkin = fs.readFileSync('src/pages/checkin/CheckIn.jsx', 'utf8')
const css = fs.readFileSync('src/pages/checkin/CheckIn.css', 'utf8')
const migration = fs.readFileSync('supabase/migrations/202609190122_negotiated_room_rate_REV1.sql', 'utf8')

const checks = [
  ['visible_standard_rate_label', /Standard room rate/.test(checkin)],
  ['visible_agreed_rate_label', /Agreed room rate \*/.test(checkin)],
  ['standard_rate_comes_from_selected_room_type', /selectedRoom\?\.room_type\?\.base_rate/.test(checkin)],
  ['agreed_rate_uses_existing_room_charge_state', /value=\{roomCharge\}/.test(checkin)],
  ['override_reason_state_present', /rateOverrideReason/.test(checkin)],
  ['override_reason_required_client_side', /hasRateOverride && !rateOverrideReason\.trim\(\)/.test(checkin)],
  ['override_reason_sent_to_rpc', /rate_override_reason: hasRateOverride \? rateOverrideReason\.trim\(\) : ""/.test(checkin)],
  ['standard_rate_sent_as_stale_screen_guard', /standard_room_rate: standardRoomRate/.test(checkin)],
  ['old_hidden_room_charge_control_removed', !/<span>Room charge<\/span><input/.test(checkin)],
  ['hotel_master_rate_not_mutated_in_frontend', !/from\(["']room_types["']\)[\s\S]{0,250}\.update\(/.test(checkin)],
  ['rate_ui_has_mobile_rule', /@media\(max-width:640px\)[\s\S]*simple-stay-rate-grid\{grid-template-columns:1fr\}/.test(css)],
  ['rate_ui_matches_stayqr_theme', /simple-stay-rate-card/.test(css) && /#e8b62f|#f1c84e/.test(css)],
  ['migration_replaces_only_rpc_contract', /create or replace function public\.check_in_walk_in_guest/.test(migration) && !/create table|alter table/i.test(migration)],
  ['server_uses_authoritative_room_type_base_rate', /standard_room_rate_value :=[\s\S]*room_type_row\.base_rate/.test(migration)],
  ['server_detects_stale_client_standard_rate', /The room standard rate changed after this screen loaded/.test(migration)],
  ['server_requires_override_reason', /A rate adjustment reason is required/.test(migration)],
  ['server_preserves_agreed_amount_as_room_charge_payment', /insert into public\.payments[\s\S]*room_charge_value,[\s\S]*'room_charge'/.test(migration)],
  ['stay_history_audits_standard_and_agreed_rates', /insert into public\.stay_room_history[\s\S]*'standard_room_rate', standard_room_rate_value[\s\S]*'agreed_room_rate', room_charge_value/.test(migration)],
  ['audit_records_discount_and_surcharge', /'discount_amount', rate_discount_amount_value/.test(migration) && /'surcharge_amount', rate_surcharge_amount_value/.test(migration)],
  ['audit_records_reason_and_actor', /'reason', rate_override_reason_value/.test(migration) && /'approved_by', auth\.uid\(\)/.test(migration)],
  ['result_returns_rate_contract', /'rate_override_applied', rate_overridden_value/.test(migration) && /'rate_adjustment_percent', rate_adjustment_percent_value/.test(migration)],
  ['companion_mapping_preserved', /'client_id', nullif\(trim\(companion_payload ->> 'client_id'\), ''\)/.test(migration)],
  ['idempotency_contract_preserved', /walkin_checkin_events[\s\S]*idempotency_key = request_id_value/.test(migration)],
  ['no_master_room_rate_update_in_migration', !/update public\.room_types/i.test(migration)],
]

let failed = 0
for (const [name, pass] of checks) {
  console.log(`${pass ? 'PASS' : 'FAIL'} ${name}`)
  if (!pass) failed += 1
}
console.log(`\nNegotiated room rate validation: ${checks.length - failed}/${checks.length} passed.`)
if (failed) process.exit(1)
