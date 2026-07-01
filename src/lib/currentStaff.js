import { supabase } from "./supabase";

export async function getCurrentStaff() {
  const {
    data: { user },
    error: userError,
  } = await supabase.auth.getUser();

  if (userError || !user) return null;

  const { data, error } = await supabase
    .from("staff")
    .select(`
      *,
      hotels (
        id,
        hotel_name,
        location,
        status
      )
    `)
    .eq("auth_user_id", user.id)
    .eq("status", "active")
    .maybeSingle();

  if (error) {
    console.error("Current staff error:", error);
    return null;
  }

  return data;
}

export function normalizeRole(role) {
  return String(role || "")
    .trim()
    .toLowerCase()
    .replace(/\s+/g, "_");
}

export function formatRole(role) {
  return String(role || "Staff")
    .replace(/_/g, " ")
    .replace(/\b\w/g, (char) => char.toUpperCase());
}

export const ROLE_ACCESS = {
  owner: [
    "dashboard",
    "rooms",
    "guests",
    "checkin",
    "menu",
    "staff",
    "qr",
    "payments",
    "services",
    "foodorders",
    "charges",
    "housekeeping",
    "amenities",
    "hotel",
    "reports",
    "invoices",
    "settings",
  ],

  manager: [
    "dashboard",
    "rooms",
    "guests",
    "checkin",
    "menu",
    "staff",
    "qr",
    "payments",
    "services",
    "foodorders",
    "charges",
    "housekeeping",
    "amenities",
    "hotel",
    "reports",
    "invoices",
    "settings",
  ],

  reception: [
    "dashboard",
    "rooms",
    "guests",
    "checkin",
    "payments",
    "services",
    "invoices",
  ],

  housekeeping: [
    "dashboard",
    "rooms",
    "housekeeping",
    "services",
  ],

  restaurant: [
    "dashboard",
    "menu",
    "foodorders",
  ],

  accounts: [
    "dashboard",
    "payments",
    "charges",
    "reports",
    "invoices",
  ],

  super_admin: [
    "dashboard",
    "superadmin",
    "rooms",
    "guests",
    "checkin",
    "menu",
    "staff",
    "qr",
    "payments",
    "services",
    "foodorders",
    "charges",
    "housekeeping",
    "amenities",
    "hotel",
    "reports",
    "invoices",
    "settings",
  ],
};

export function canAccessSection(role, section) {
  const normalizedRole = normalizeRole(role);
  const allowed = ROLE_ACCESS[normalizedRole] || [];
  return allowed.includes(section);
}

export function canManageStaff(role) {
  const normalizedRole = normalizeRole(role);
  return ["owner", "manager", "super_admin"].includes(normalizedRole);
}