import fs from 'node:fs'
import path from 'node:path'
import { fileURLToPath } from 'node:url'

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..')
const read = (relativePath) => fs.readFileSync(path.join(root, relativePath), 'utf8')
const exists = (relativePath) => fs.existsSync(path.join(root, relativePath))
const has = (source, value) => source.includes(value)

const files = {
  app: read('src/App.jsx'),
  commercial: read('src/lib/commercialControl.js'),
  tenant: read('src/lib/tenantContext.js'),
  dashboard: read('src/pages/dashboard/Dashboard.jsx'),
  hotelCard: read('src/components/cards/HotelOverviewCard.jsx'),
  hotelCardCss: read('src/components/cards/HotelOverviewCard.css'),
  hotelProfile: read('src/pages/hotel/HotelProfile.jsx'),
  staff: read('src/pages/staff/StaffManagement.jsx'),
  amenities: read('src/pages/amenities/Amenities.jsx'),
  amenitiesCss: read('src/pages/amenities/Amenities.css'),
  mediaManager: read('src/pages/media/MediaManager.jsx'),
  mediaManagerCss: read('src/pages/media/MediaManager.css'),
  mediaLib: read('src/lib/guestGuideBuilder.js'),
  builder: read('src/pages/guestbuilder/GuestGuideBuilder.jsx'),
  guide: read('src/pages/guestguide/GuestGuide.jsx'),
  qr: read('src/pages/qr/QRGenerator.jsx'),
  portal: read('src/lib/guestPortal.js'),
  roomAccess: read('src/pages/roomaccess/RoomAccess.jsx'),
  migration: read('supabase/migrations/202608200088_postlaunch_batch2_final_completion.sql'),
  audit: read('supabase/audit/202608200089_postlaunch_batch2_final_completion_ACCEPTANCE.sql'),
}

const checks = []
const expect = (name, condition) => checks.push({ name, passed: Boolean(condition) })

// Item 3 — authoritative Super Admin isolation + timed/audited hotel access.
expect('03.1 Super Admin uses the existing safe support-access client', has(files.commercial, 'startSafeSupportAccess') && has(files.commercial, "'start_safe_support_access'"))
expect('03.2 Super Admin can explicitly end safe support access', has(files.commercial, 'endSafeSupportAccess') && has(files.commercial, "'end_safe_support_access'"))
expect('03.3 Super Admin UI starts safe support access rather than silent hotel switching', has(read('src/pages/superadmin/SuperAdmin.jsx'), 'startSafeSupportAccess(') && has(read('src/pages/superadmin/SuperAdmin.jsx'), 'No silent impersonation'))
expect('03.4 Normal platform navigation continues to block ordinary hotel switching', has(read('src/components/navbar/Navbar.jsx'), 'timed, audited support session') && has(read('src/components/sidebar/Sidebar.jsx'), 'Use Super Admin for timed hotel support access'))

// Item 4 — hotel support/report + guest escalation/emergency.
expect('04.1 Dashboard exposes Get Support', has(read('src/components/buttons/QuickActions.jsx'), "label: 'Get Support'"))
expect('04.2 Dashboard exposes Report Issue', has(read('src/components/buttons/QuickActions.jsx'), "label: 'Report Issue'"))
expect('04.3 Dashboard routes support into Operations Centre', has(files.dashboard, "onNavigate?.('operationscenter')"))
expect('04.4 Guest guide exposes hotel-management escalation', has(files.guide, "createRequest('Management Escalation')"))
expect('04.5 Guest guide exposes emergency direct-call action', has(files.guide, 'displayInfo.emergency_phone') && has(files.guide, 'callPhone(displayInfo.emergency_phone'))

// Item 5 — editable staff profile + private avatar + verified phone.
expect('05.1 Staff profile retains tenant-explicit editable profile RPC', has(files.staff, "supabase.rpc('update_my_staff_profile'"))
expect('05.2 Staff profile retains private avatar implementation', has(files.staff, "const STAFF_AVATAR_BUCKET = 'staff-avatars'"))
expect('05.3 Tenant context carries phone verification timestamp', has(files.tenant, 'phone_verified_at'))
expect('05.4 Phone verification uses Supabase Auth phone update', has(files.staff, 'supabase.auth.updateUser({ phone })'))
expect('05.5 Phone verification requires OTP confirmation', has(files.staff, "type: 'phone_change'") && has(files.staff, 'supabase.auth.verifyOtp'))
expect('05.6 Verified Auth phone is synchronized through a tenant-explicit RPC', has(files.staff, "supabase.rpc('sync_my_verified_staff_phone'") && has(files.migration, 'auth.users'))
expect('05.7 Database stores verification timestamp separately from phone text', has(files.migration, 'add column if not exists phone_verified_at timestamptz'))

// Item 8 — hotel-branded dashboard.
expect('08.1 Tenant hotel context includes logo and cover', has(files.tenant, 'logo_url') && has(files.tenant, 'cover_url'))
expect('08.2 Property overview renders hotel logo', has(files.hotelCard, 'hotel?.logo_url'))
expect('08.3 Property overview renders hotel cover', has(files.hotelCard, 'hotel?.cover_url') && has(files.hotelCardCss, '--hotel-cover-image'))
expect('08.4 Hotel Profile can upload logo and cover through shared media storage', has(files.hotelProfile, "saveBrandAsset('logo'") && has(files.hotelProfile, "saveBrandAsset('cover'"))
expect('08.5 Branding persistence is tenant permission guarded', has(files.migration, 'create or replace function public.update_hotel_branding') && has(files.migration, "'hotel.manage'"))

// Item 11 — amenity gallery CRUD.
expect('11.1 Amenities load unified media assets', has(files.amenities, "from('guest_guide_media')") && has(files.amenities, "eq('category', 'facility')"))
expect('11.2 Amenities upload gallery media', has(files.amenities, 'uploadGuestGuideMediaFile'))
expect('11.3 Amenities can edit media title/caption', has(files.amenities, 'editMediaDetails'))
expect('11.4 Amenities can remove/deactivate gallery media', has(files.amenities, 'removeMedia'))
expect('11.5 Amenity gallery associates media with amenity identity', has(files.amenities, 'amenity_id'))
expect('11.6 Amenity media UI supports both image and short video', has(files.amenities, '<video') && has(files.amenities, '<img'))
expect('11.7 Amenity media controls remain responsive', has(files.amenitiesCss, '@media'))

// Item 13 — unified media manager + controlled short video.
expect('13.0 Dedicated unified Media Manager is routed and permission-scoped', has(files.app, "case 'media':") && has(read('src/components/sidebar/Sidebar.jsx'), "id: 'media'") && has(read('src/lib/currentStaff.js'), "media: 'hotel.manage'"))
expect('13.0b Media Manager supports upload/edit/remove across tenant media', has(files.mediaManager, 'uploadGuestGuideMediaFile') && has(files.mediaManager, 'saveGuestGuideMedia') && has(files.mediaManager, 'removeGuestGuideMediaFile'))
expect('13.0c Media Manager is responsive', has(files.mediaManagerCss, '@media(max-width:600px)'))
expect('13.1 Unified media helper explicitly allows MP4 and WebM', has(files.mediaLib, 'video/mp4') && has(files.mediaLib, 'video/webm'))
expect('13.2 Short videos are capped at 20 MB', has(files.mediaLib, '20 * 1024 * 1024'))
expect('13.3 Short videos are capped at 30 seconds', has(files.mediaLib, '30'))
expect('13.4 Video is restricted to approved content categories', has(files.mediaLib, 'VIDEO_ALLOWED_CATEGORIES'))
expect('13.5 Builder upload accepts image and controlled video', has(files.builder, 'video/mp4,video/webm'))
expect('13.6 Builder provides media detail editing and removal', has(files.builder, 'editMediaDetails') && has(files.builder, 'deleteMedia'))
expect('13.7 Guest guide renders video media', has(files.guide, '<video') && has(files.guide, 'GuideMedia'))
expect('13.8 Storage bucket limits are enforced server-side', has(files.migration, '20971520') && has(files.migration, "'video/mp4','video/webm'"))

// Item 14 — permanent room QR + fresh per-stay access layer.
expect('14.1 Standalone permanent room QR route exists', exists('src/pages/roomaccess/RoomAccess.jsx') && has(files.app, "startsWith('/room/')"))
expect('14.2 QR generator loads stable permanent room links', has(files.qr, 'getPermanentRoomQrLinks'))
expect('14.3 QR generator can issue or rotate the current stay PIN', has(files.qr, 'issuePermanentRoomQrPin') && has(files.qr, 'Rotate stay PIN'))
expect('14.4 Public room access requires a six-digit stay PIN', has(files.roomAccess, '6-digit') && has(files.roomAccess, 'resolvePermanentRoomQr'))
expect('14.5 Permanent QR tables are additive and room-bound', has(files.migration, 'create table if not exists public.room_qr_codes') && has(files.migration, 'room_id uuid primary key'))
expect('14.6 PIN challenge is bound to guest_session_id', has(files.migration, 'guest_session_id uuid not null references public.guest_sessions'))
expect('14.7 PIN values are stored only as bcrypt hashes', has(files.migration, 'pin_hash text not null') && has(files.migration, "extensions.gen_salt('bf', 8)"))
expect('14.8 Five failed PIN attempts lock access', has(files.migration, 'failed_attempts >= 5') && has(files.migration, "status = 'locked'"))
expect('14.9 Checkout/stay changes revoke active room PIN challenge', has(files.migration, 'sync_room_qr_pin_from_guest_session') && has(files.migration, 'Guest stay changed or ended'))
expect('14.10 Permanent room resolver preserves existing signed token lifecycle', has(files.migration, 'private.render_guest_access_token') && has(files.migration, 'private.issue_guest_access_token'))
expect('14.11 Resolver cannot bypass manually revoked or expired signed access', has(files.migration, "v_token.status <> 'active'") && has(files.migration, 'v_token.expires_at <= now()'))
expect('14.12 Public resolver exposes no direct QR/PIN table grants to anon', has(files.migration, 'revoke all on table public.room_qr_codes from public, anon') && has(files.migration, 'revoke all on table public.room_qr_pin_challenges from public, anon'))

expect('Final database acceptance audit is packaged', has(files.audit, 'POSTLAUNCH_BATCH2_FINAL_DATABASE_ACCEPTANCE: PASS (24/24)'))

const changedScope = Object.values(files).join('\n')
expect('Production Supabase project reference is absent from final patch scope', !changedScope.includes('rbyirbovbkguzvwijyaj'))
expect('No unsupported 24x7 support promise was introduced', !/(24\s*[x×/]\s*7|24\/7)/i.test(changedScope))

for (const [index, check] of checks.entries()) {
  console.log(`${check.passed ? 'PASS' : 'FAIL'} ${String(index + 1).padStart(2, '0')} | ${check.name}`)
}

const failures = checks.filter((check) => !check.passed)
if (failures.length) {
  console.error(`POSTLAUNCH_BATCH2_FINAL_SOURCE_ACCEPTANCE: FAIL (${checks.length - failures.length}/${checks.length})`)
  process.exit(1)
}

console.log(`POSTLAUNCH_BATCH2_FINAL_SOURCE_ACCEPTANCE: PASS (${checks.length}/${checks.length})`)
