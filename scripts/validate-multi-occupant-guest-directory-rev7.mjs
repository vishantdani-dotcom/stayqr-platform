import fs from "node:fs";
import path from "node:path";

const root = process.cwd();
const read = (relative) => fs.readFileSync(path.join(root, relative), "utf8");

const guestDirectory = read("src/pages/guests/GuestDirectory.jsx");
const migration112 = read("supabase/migrations/202609050112_multi_occupant_checkin_result_contract_REV1.sql");
const migration113 = read("supabase/migrations/202609050113_multi_occupant_guest_directory_summary_REV1.sql");

const checks = [];
const expect = (name, condition) => checks.push({ name, pass: Boolean(condition) });

expect("REV6 companion persistence remains present", migration112.includes("insert into public.guest_companions"));
expect("REV6 companion result mapping remains present", migration112.includes("'companions', companion_results"));
expect("REV7 replaces Guest 360 RPC", migration113.includes("create or replace function public.get_guest_360_directory"));
expect("REV7 uses a unified stay membership CTE", migration113.includes("with stay_memberships as"));
expect("Primary guest sessions are included", /from public\.guest_sessions gs[\s\S]*?where gs\.hotel_id = target_hotel_id/.test(migration113));
expect("Companion memberships are included", migration113.includes("from public.guest_companions gc"));
expect("Companion membership joins are hotel scoped", migration113.includes("gs.hotel_id = gc.hotel_id") && migration113.includes("gs.id = gc.guest_session_id"));
expect("Stay memberships use UNION dedupe", /stay_memberships as \([\s\S]*?\n\s*union\n[\s\S]*?guest_companions/.test(migration113));
expect("Total stays derive from unified memberships", /from stay_memberships sm[\s\S]*?group by sm\.guest_id/.test(migration113));
expect("Active stay derives from unified memberships", /active_stay as \([\s\S]*?from stay_memberships sm[\s\S]*?sm\.status = 'active'/.test(migration113));
expect("Guest 360 anon execution remains denied", migration113.includes("revoke all on function public.get_guest_360_directory(uuid) from public, anon"));
expect("Guest 360 authenticated execution remains granted", migration113.includes("grant execute on function public.get_guest_360_directory(uuid) to authenticated, service_role"));
expect("Communication audience is companion aware", migration113.includes("with active_memberships as") && migration113.includes("active_room_by_guest"));
expect("Communication audience anon execution remains denied", migration113.includes("revoke all on function public.get_guest_communication_audience(uuid) from public, anon"));
expect("Frontend consumes RPC active session", guestDirectory.includes("summary.active_session_id"));
expect("Frontend consumes RPC active room", guestDirectory.includes("summary.active_room_number"));
expect("Frontend marks synthetic companion active stay", guestDirectory.includes('stay_role: primaryActiveStay?.id === summary.active_session_id ? "primary" : "companion"'));
expect("Frontend total stays still prefers Guest 360 summary", guestDirectory.includes("summary.total_stays ?? primaryGuestSessions.length"));
expect("Frontend last stay uses Guest 360 summary", guestDirectory.includes("const lastStayAt = summary.last_stay_at"));
expect("Directory renders companion last stay from summary", guestDirectory.includes("formatDate(row.lastStayAt)"));
expect("In-house metric still derives from activeStay", guestDirectory.includes("directoryRows.filter((row) => row.activeStay).length"));
expect("Room filter still derives from activeStay", guestDirectory.includes("row.activeStay?.rooms?.room_number"));
expect("Existing companion-aware profile loader remains", guestDirectory.includes("companionSessionIds") && guestDirectory.includes('stay_role: "companion"'));

const failed = checks.filter((item) => !item.pass);
for (const item of checks) console.log(`${item.pass ? "PASS" : "FAIL"} ${item.name}`);
console.log(JSON.stringify({ checks: checks.length, passed: checks.length - failed.length, failed: failed.length }));
if (failed.length) process.exit(1);
