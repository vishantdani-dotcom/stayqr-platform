import fs from 'node:fs'

const path = 'src/pages/staff/MyProfile.jsx'

if (!fs.existsSync(path)) {
  console.error(`FAIL required_file_exists :: ${path}`)
  process.exit(1)
}

const source = fs.readFileSync(path, 'utf8')

const checks = [
  ['login_email_label_present', source.includes('Login email')],
  ['login_email_uses_current_staff_email', source.includes("value={currentStaff?.email || ''}")],
  ['login_email_read_only', source.includes('readOnly') && source.includes('aria-readonly="true"')],
  ['login_email_username_autocomplete', source.includes('autoComplete="username"')],
  ['login_email_helper_present', source.includes('Used to sign in to StayQR. This email is read-only here.')],
  ['no_literal_backslash_n_artifact', !source.includes('\\n          <label className="staff-phone-field">')],
  ['profile_email_not_added_to_editable_form_state',
    !/setProfileForm\([\s\S]{0,500}email\s*:/.test(source)],
  ['profile_save_rpc_email_unchanged',
    source.includes("'update_my_staff_profile'") &&
    !/p_email\s*:/.test(source)],
  ['no_auth_email_update_added',
    !/supabase\.auth\.updateUser\s*\(\s*\{\s*email\s*:/.test(source)],
  ['full_name_preserved', source.includes('Full name')],
  ['phone_field_preserved', source.includes('Phone number')],
  ['profile_photo_preserved', source.includes('Profile photo')],
  ['background_push_preserved', source.includes('<BackgroundPushCard')],
]

let failed = 0
for (const [name, pass] of checks) {
  console.log(`${pass ? 'PASS' : 'FAIL'} ${name}`)
  if (!pass) failed += 1
}

console.log(`\nProfile login email FIX1 validation: ${checks.length - failed}/${checks.length} passed.`)
if (failed) process.exit(1)
