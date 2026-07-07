import { supabase } from "./supabase";

export async function createNotification({
  hotelId,
  roomId = null,
  guestId = null,
  type = "general",
  title = "Notification",
  message = "",
}) {
  if (!hotelId) return null;

  const { data, error } = await supabase
    .from("notifications")
    .insert([
      {
        hotel_id: hotelId,
        room_id: roomId,
        guest_id: guestId,
        type,
        title,
        message,
        is_read: false,
      },
    ])
    .select()
    .single();

  if (error) {
    console.error("Create notification error:", error);
    return null;
  }

  return data;
}

export async function getNotifications(hotelId) {
  if (!hotelId) return [];

  const { data, error } = await supabase
    .from("notifications")
    .select("*")
    .eq("hotel_id", hotelId)
    .order("created_at", { ascending: false })
    .limit(30);

  if (error) {
    console.error("Get notifications error:", error);
    return [];
  }

  return data || [];
}

export async function markNotificationRead(notificationId) {
  if (!notificationId) return;

  const { error } = await supabase
    .from("notifications")
    .update({ is_read: true })
    .eq("id", notificationId);

  if (error) {
    console.error("Mark notification read error:", error);
  }
}

export async function markAllNotificationsRead(hotelId) {
  if (!hotelId) return;

  const { error } = await supabase
    .from("notifications")
    .update({ is_read: true })
    .eq("hotel_id", hotelId)
    .eq("is_read", false);

  if (error) {
    console.error("Mark all notifications read error:", error);
  }
}

export function getUnreadCount(notifications = []) {
  return notifications.filter((item) => !item.is_read).length;
}