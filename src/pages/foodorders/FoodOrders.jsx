import { useEffect, useRef, useState } from "react";
import { supabase } from "../../lib/supabase";
import { getCurrentHotel } from "../../lib/currentHotel";
import { createNotification } from "../../lib/notifications";

export default function FoodOrders() {
  const [orders, setOrders] = useState([]);
  const [loading, setLoading] = useState(true);
  const [currentHotel, setCurrentHotel] = useState(null);
  const [newOrderAlert, setNewOrderAlert] = useState(null);
  const [updatingOrderId, setUpdatingOrderId] = useState(null);

  const knownOrderIds = useRef(new Set());
  const firstLoadDone = useRef(false);
  const alertTimeoutRef = useRef(null);

  useEffect(() => {
    initPage();

    return () => {
      if (alertTimeoutRef.current) {
        clearTimeout(alertTimeoutRef.current);
      }
    };
  }, []);

  useEffect(() => {
    if (!currentHotel?.id) return undefined;

    loadOrders(currentHotel.id);

    const channel = supabase
      .channel(`food_orders_${currentHotel.id}`)
      .on(
        "postgres_changes",
        {
          event: "*",
          schema: "public",
          table: "food_orders",
          filter: `hotel_id=eq.${currentHotel.id}`,
        },
        (payload) => {
          if (payload.eventType === "INSERT") {
            handleNewOrder(payload.new);
          }

          loadOrders(currentHotel.id);
        }
      )
      .subscribe((status) => {
        console.log("Food orders realtime status:", status);
      });

    return () => {
      supabase.removeChannel(channel);
    };
  }, [currentHotel?.id]);

  async function initPage() {
    const hotel = await getCurrentHotel();

    if (!hotel) {
      alert("No hotel assigned");
      setLoading(false);
      return;
    }

    setCurrentHotel(hotel);
    await loadOrders(hotel.id);
    setLoading(false);
  }

  function handleNewOrder(order) {
    if (!order?.id) return;
    if (knownOrderIds.current.has(order.id)) return;

    knownOrderIds.current.add(order.id);

    if (!firstLoadDone.current) return;

    setNewOrderAlert(order);
    playKitchenSound();

    if (alertTimeoutRef.current) {
      clearTimeout(alertTimeoutRef.current);
    }

    alertTimeoutRef.current = setTimeout(() => {
      setNewOrderAlert(null);
    }, 6000);
  }

  function playKitchenSound() {
    try {
      const AudioContextClass =
        window.AudioContext || window.webkitAudioContext;

      if (!AudioContextClass) return;

      const audioContext = new AudioContextClass();
      const oscillator = audioContext.createOscillator();
      const gainNode = audioContext.createGain();

      oscillator.connect(gainNode);
      gainNode.connect(audioContext.destination);

      oscillator.frequency.value = 880;
      oscillator.type = "sine";

      gainNode.gain.setValueAtTime(0.001, audioContext.currentTime);

      gainNode.gain.exponentialRampToValueAtTime(
        0.25,
        audioContext.currentTime + 0.02
      );

      gainNode.gain.exponentialRampToValueAtTime(
        0.001,
        audioContext.currentTime + 0.35
      );

      oscillator.start(audioContext.currentTime);
      oscillator.stop(audioContext.currentTime + 0.35);
    } catch (error) {
      console.warn("Kitchen sound unavailable:", error);
    }
  }

  async function loadOrders(hotelId = currentHotel?.id) {
    if (!hotelId) return;

    const { data, error } = await supabase
      .from("food_orders")
      .select(`
        *,
        rooms (
          room_number
        ),
        guests (
          full_name
        ),
        food_order_items (
          quantity,
          price,
          menu_items (
            item_name,
            category
          )
        )
      `)
      .eq("hotel_id", hotelId)
      .order("created_at", { ascending: false });

    if (error) {
      console.error("Load food orders error:", error);
      alert(error.message);
      return;
    }

    const nextOrders = data || [];

    nextOrders.forEach((order) => {
      if (order?.id) {
        knownOrderIds.current.add(order.id);
      }
    });

    firstLoadDone.current = true;
    setOrders(nextOrders);
  }

  async function updateStatus(order, status) {
    if (!currentHotel?.id || !order?.id) return;

    try {
      setUpdatingOrderId(order.id);

      const payload = {
        order_status: status,
      };

      if (status === "delivered") {
        payload.delivered_at = new Date().toISOString();
      }

      const { error } = await supabase
        .from("food_orders")
        .update(payload)
        .eq("id", order.id)
        .eq("hotel_id", currentHotel.id);

      if (error) throw error;

      const notificationMessages = {
        accepted: {
          title: "🍽 Order Accepted",
          message: "The kitchen has accepted your order.",
        },

        preparing: {
          title: "👨‍🍳 Preparing Your Meal",
          message: "Our chefs have started preparing your order.",
        },

        out_for_delivery: {
          title: "🚶 Order On The Way",
          message: "Your order is on the way to your room.",
        },

        delivered: {
          title: "✅ Order Delivered",
          message: "Your order has been delivered. Enjoy your meal!",
        },
      };

      const notification = notificationMessages[status];

      if (notification) {
        await createNotification({
          hotelId: currentHotel.id,
          roomId: order.room_id,
          guestId: order.guest_id,
          type: "food_status",
          title: notification.title,
          message: notification.message,
        });
      }

      await loadOrders(currentHotel.id);
    } catch (error) {
      console.error("Update food status error:", error);
      alert(error.message);
    } finally {
      setUpdatingOrderId(null);
    }
  }

  async function updateETA(order, minutes) {
    if (!currentHotel?.id || !order?.id) return;

    const estimatedMinutes = Number(minutes);

    try {
      setUpdatingOrderId(order.id);

      if (!estimatedMinutes) {
        const { error } = await supabase
          .from("food_orders")
          .update({
            estimated_minutes: null,
            estimated_delivery_time: null,
          })
          .eq("id", order.id)
          .eq("hotel_id", currentHotel.id);

        if (error) throw error;

        await loadOrders(currentHotel.id);
        return;
      }

      const estimatedDeliveryTime = new Date(
        Date.now() + estimatedMinutes * 60 * 1000
      ).toISOString();

      const { error } = await supabase
        .from("food_orders")
        .update({
          estimated_minutes: estimatedMinutes,
          estimated_delivery_time: estimatedDeliveryTime,
        })
        .eq("id", order.id)
        .eq("hotel_id", currentHotel.id);

      if (error) throw error;

      await createNotification({
        hotelId: currentHotel.id,
        roomId: order.room_id,
        guestId: order.guest_id,
        type: "food_eta",
        title: "⏱ Food Delivery ETA",
        message: `Your order is expected in approximately ${estimatedMinutes} minutes.`,
      });

      await loadOrders(currentHotel.id);
    } catch (error) {
      console.error("Update food ETA error:", error);
      alert(error.message);
    } finally {
      setUpdatingOrderId(null);
    }
  }

  const today = new Date().toDateString();

  const todayOrders = orders.filter(
    (order) => new Date(order.created_at).toDateString() === today
  );

  const todayRevenue = todayOrders.reduce(
    (sum, order) => sum + Number(order.total_amount || 0),
    0
  );

  const pendingOrders = orders.filter(
    (order) => order.order_status === "pending"
  );

  const acceptedOrders = orders.filter(
    (order) => order.order_status === "accepted"
  );

  const preparingOrders = orders.filter(
    (order) => order.order_status === "preparing"
  );

  const outForDeliveryOrders = orders.filter(
    (order) => order.order_status === "out_for_delivery"
  );

  const deliveredOrders = orders.filter(
    (order) => order.order_status === "delivered"
  );

  const deliveredRevenue = deliveredOrders.reduce(
    (sum, order) => sum + Number(order.total_amount || 0),
    0
  );

  const pendingRevenue = pendingOrders.reduce(
    (sum, order) => sum + Number(order.total_amount || 0),
    0
  );

  const totalRevenue = orders.reduce(
    (sum, order) => sum + Number(order.total_amount || 0),
    0
  );

  const averageOrderValue =
    orders.length > 0 ? Math.round(totalRevenue / orders.length) : 0;

  const deliveryRate =
    orders.length > 0
      ? Math.round((deliveredOrders.length / orders.length) * 100)
      : 0;

  const topSellingItems = Object.values(
    orders.reduce((accumulator, order) => {
      order.food_order_items?.forEach((item) => {
        const name = item.menu_items?.item_name || "Unknown";

        if (!accumulator[name]) {
          accumulator[name] = {
            name,
            quantity: 0,
            revenue: 0,
          };
        }

        accumulator[name].quantity += Number(item.quantity || 0);

        accumulator[name].revenue +=
          Number(item.quantity || 0) * Number(item.price || 0);
      });

      return accumulator;
    }, {})
  )
    .sort((first, second) => second.quantity - first.quantity)
    .slice(0, 5);

  const categoryRevenue = Object.values(
    orders.reduce((accumulator, order) => {
      order.food_order_items?.forEach((item) => {
        const category = item.menu_items?.category || "Uncategorized";

        if (!accumulator[category]) {
          accumulator[category] = {
            category,
            revenue: 0,
          };
        }

        accumulator[category].revenue +=
          Number(item.quantity || 0) * Number(item.price || 0);
      });

      return accumulator;
    }, {})
  ).sort((first, second) => second.revenue - first.revenue);

  const last7Days = [...Array(7)].map((_, index) => {
    const day = new Date();

    day.setHours(0, 0, 0, 0);
    day.setDate(day.getDate() - (6 - index));

    const nextDay = new Date(day);
    nextDay.setDate(nextDay.getDate() + 1);

    const count = orders.filter((order) => {
      const orderDate = new Date(order.created_at);

      return orderDate >= day && orderDate < nextDay;
    }).length;

    return {
      key: day.toISOString().slice(0, 10),
      label: day.toLocaleDateString("en-IN", {
        weekday: "short",
      }),
      count,
    };
  });

  if (loading) {
    return <div style={page}>Loading Food Orders...</div>;
  }

  return (
    <div style={page}>
      {newOrderAlert && (
        <div style={newOrderBanner}>
          <div style={bannerIcon}>🔔</div>

          <div>
            <strong>New Food Order</strong>

            <p style={bannerText}>
              Room order received · ₹{newOrderAlert.total_amount || 0}
            </p>
          </div>
        </div>
      )}

      <div style={header}>
        <div>
          <p style={kicker}>Kitchen Operations</p>
          <h1 style={title}>Food Orders</h1>

          <p style={subtitle}>
            {currentHotel?.hotel_name || "Hotel"} · Live kitchen order
            dashboard.
          </p>
        </div>

        <button
          style={refreshBtn}
          onClick={() => loadOrders(currentHotel?.id)}
        >
          Refresh
        </button>
      </div>

      <div style={statsGrid}>
        <Stat title="Today's Orders" value={todayOrders.length} />
        <Stat title="Today's Revenue" value={`₹${todayRevenue}`} />
        <Stat title="Pending" value={pendingOrders.length} />
        <Stat title="Accepted" value={acceptedOrders.length} />
        <Stat title="Preparing" value={preparingOrders.length} />
        <Stat title="On the Way" value={outForDeliveryOrders.length} />
        <Stat title="Delivered" value={deliveredOrders.length} />
        <Stat title="Delivered Revenue" value={`₹${deliveredRevenue}`} />
        <Stat title="Pending Revenue" value={`₹${pendingRevenue}`} />
        <Stat title="Avg Order Value" value={`₹${averageOrderValue}`} />
        <Stat title="Delivery Rate" value={`${deliveryRate}%`} />
      </div>

      <div style={analyticsCardWide}>
        <h2 style={analyticsTitle}>🏆 Top Selling Items</h2>

        {topSellingItems.length === 0 ? (
          <p style={analyticsEmpty}>No sales yet.</p>
        ) : (
          topSellingItems.map((item, index) => (
            <div
              key={item.name}
              style={{
                ...analyticsRow,
                borderBottom:
                  index === topSellingItems.length - 1
                    ? "none"
                    : "1px solid #222",
              }}
            >
              <strong>{item.name}</strong>

              <span style={analyticsValue}>
                {item.quantity} sold · ₹{item.revenue}
              </span>
            </div>
          ))
        )}
      </div>

      <div style={analyticsGrid}>
        <div style={analyticsCard}>
          <h2 style={analyticsTitle}>📊 Sales by Category</h2>

          {categoryRevenue.length === 0 ? (
            <p style={analyticsEmpty}>No category sales yet.</p>
          ) : (
            categoryRevenue.map((item, index) => (
              <div
                key={item.category}
                style={{
                  ...analyticsRow,
                  borderBottom:
                    index === categoryRevenue.length - 1
                      ? "none"
                      : "1px solid #222",
                }}
              >
                <span>{item.category}</span>
                <strong>₹{item.revenue}</strong>
              </div>
            ))
          )}
        </div>

        <div style={analyticsCard}>
          <h2 style={analyticsTitle}>📈 7-Day Order Trend</h2>

          {last7Days.map((day) => {
            const highestCount = Math.max(
              ...last7Days.map((item) => item.count),
              1
            );

            const widthPercentage = (day.count / highestCount) * 100;

            return (
              <div key={day.key} style={trendRow}>
                <span style={trendLabel}>{day.label}</span>

                <div style={trendBarWrap}>
                  <div
                    style={{
                      ...trendBar,
                      width: `${widthPercentage}%`,
                    }}
                  />
                </div>

                <strong style={trendCount}>{day.count}</strong>
              </div>
            );
          })}
        </div>
      </div>

      {orders.length === 0 ? (
        <div style={emptyCard}>
          <h3>No food orders yet</h3>
          <p>Guest food orders will appear here instantly.</p>
        </div>
      ) : (
        <div style={card}>
          <table style={table}>
            <thead>
              <tr>
                <th style={th}>Room</th>
                <th style={th}>Guest</th>
                <th style={th}>Items</th>
                <th style={th}>Amount</th>
                <th style={th}>Status</th>
                <th style={th}>Payment</th>
                <th style={th}>Time</th>
                <th style={th}>ETA</th>
                <th style={th}>Action</th>
              </tr>
            </thead>

            <tbody>
              {orders.map((order) => {
                const isNew = isRecentPendingOrder(order);
                const isUpdating = updatingOrderId === order.id;

                return (
                  <tr key={order.id} style={isNew ? newOrderRow : undefined}>
                    <td style={td}>
                      Room {order.rooms?.room_number || "-"}

                      {isNew && <span style={newBadge}>NEW</span>}
                    </td>

                    <td style={td}>{order.guests?.full_name || "-"}</td>

                    <td style={td}>
                      {order.food_order_items?.length > 0
                        ? order.food_order_items.map((item, index) => (
                            <div key={`${order.id}-${index}`}>
                              {item.menu_items?.item_name || "Unknown Item"} x{" "}
                              {item.quantity}
                            </div>
                          ))
                        : "No items"}
                    </td>

                    <td style={td}>₹{order.total_amount || 0}</td>

                    <td style={td}>
                      <span style={badge(order.order_status)}>
                        {formatStatus(order.order_status)}
                      </span>
                    </td>

                    <td style={td}>
                      <span style={paymentBadge(order.payment_status)}>
                        {formatStatus(order.payment_status || "pending")}
                      </span>
                    </td>

                    <td style={td}>
                      {order.created_at
                        ? new Date(order.created_at).toLocaleString("en-IN")
                        : "-"}
                    </td>

                    <td style={td}>
                      {order.order_status === "delivered" ? (
                        <span style={deliveredText}>Delivered</span>
                      ) : (
                        <>
                          <select
                            value={order.estimated_minutes || ""}
                            onChange={(event) =>
                              updateETA(order, event.target.value)
                            }
                            style={etaSelect}
                            disabled={isUpdating}
                          >
                            <option value="">Set ETA</option>
                            <option value="10">10 min</option>
                            <option value="20">20 min</option>
                            <option value="30">30 min</option>
                            <option value="45">45 min</option>
                          </select>

                          {order.estimated_delivery_time && (
                            <div style={etaTime}>
                              By{" "}
                              {new Date(
                                order.estimated_delivery_time
                              ).toLocaleTimeString("en-IN", {
                                hour: "2-digit",
                                minute: "2-digit",
                              })}
                            </div>
                          )}

                          {isUpdating && (
                            <div style={updatingText}>Updating...</div>
                          )}
                        </>
                      )}
                    </td>

                    <td style={td}>
                      {order.order_status === "pending" && (
                        <button
                          style={btn}
                          disabled={isUpdating}
                          onClick={() => updateStatus(order, "accepted")}
                        >
                          Accept Order
                        </button>
                      )}

                      {order.order_status === "accepted" && (
                        <button
                          style={btn}
                          disabled={isUpdating}
                          onClick={() => updateStatus(order, "preparing")}
                        >
                          Start Preparing
                        </button>
                      )}

                      {order.order_status === "preparing" && (
                        <button
                          style={btn}
                          disabled={isUpdating}
                          onClick={() =>
                            updateStatus(order, "out_for_delivery")
                          }
                        >
                          Out for Delivery
                        </button>
                      )}

                      {order.order_status === "out_for_delivery" && (
                        <button
                          style={btn}
                          disabled={isUpdating}
                          onClick={() => updateStatus(order, "delivered")}
                        >
                          Mark Delivered
                        </button>
                      )}

                      {order.order_status === "delivered" && (
                        <span style={deliveredText}>Delivered</span>
                      )}
                    </td>
                  </tr>
                );
              })}
            </tbody>
          </table>
        </div>
      )}
    </div>
  );
}

function Stat({ title, value }) {
  return (
    <div style={statCard}>
      <span style={statLabel}>{title}</span>
      <strong style={statValue}>{value}</strong>
    </div>
  );
}

function isRecentPendingOrder(order) {
  if (order.order_status !== "pending") return false;
  if (!order.created_at) return false;

  const createdAt = new Date(order.created_at).getTime();

  if (Number.isNaN(createdAt)) return false;

  return Date.now() - createdAt < 10 * 60 * 1000;
}

function formatStatus(status) {
  return String(status || "")
    .replaceAll("_", " ")
    .replace(/\b\w/g, (letter) => letter.toUpperCase());
}

const page = {
  padding: "32px",
  color: "#fff",
};

const header = {
  display: "flex",
  justifyContent: "space-between",
  alignItems: "center",
  gap: "20px",
  marginBottom: "25px",
};

const kicker = {
  color: "#d4af37",
  fontSize: "12px",
  fontWeight: 900,
  letterSpacing: "2px",
  textTransform: "uppercase",
  marginBottom: "8px",
};

const title = {
  fontSize: "42px",
  marginBottom: "8px",
};

const subtitle = {
  color: "#aaa",
};

const refreshBtn = {
  background: "#d4af37",
  color: "#000",
  border: "none",
  borderRadius: "10px",
  padding: "12px 18px",
  fontWeight: 800,
  cursor: "pointer",
};

const statsGrid = {
  display: "grid",
  gridTemplateColumns: "repeat(auto-fit, minmax(160px, 1fr))",
  gap: "18px",
  marginBottom: "28px",
};

const statCard = {
  background: "#0f0f0f",
  border: "1px solid #222",
  borderRadius: "16px",
  padding: "20px",
};

const statLabel = {
  display: "block",
  color: "#d4af37",
  fontSize: "13px",
  marginBottom: "10px",
};

const statValue = {
  fontSize: "28px",
};

const analyticsGrid = {
  display: "grid",
  gridTemplateColumns: "repeat(auto-fit, minmax(280px, 1fr))",
  gap: "20px",
  marginBottom: "25px",
};

const analyticsCard = {
  background: "#0f0f0f",
  border: "1px solid #222",
  borderRadius: "18px",
  padding: "24px",
};

const analyticsCardWide = {
  ...analyticsCard,
  marginBottom: "25px",
};

const analyticsTitle = {
  color: "#d4af37",
  marginBottom: "18px",
  fontSize: "22px",
};

const analyticsEmpty = {
  color: "#888",
};

const analyticsRow = {
  display: "flex",
  justifyContent: "space-between",
  gap: "15px",
  padding: "12px 0",
};

const analyticsValue = {
  color: "#d4af37",
  fontWeight: 700,
};

const trendRow = {
  display: "flex",
  alignItems: "center",
  gap: "12px",
  padding: "10px 0",
};

const trendLabel = {
  width: "45px",
};

const trendCount = {
  width: "25px",
  textAlign: "right",
};

const trendBarWrap = {
  flex: 1,
  height: "10px",
  background: "#1a1a1a",
  borderRadius: "999px",
  overflow: "hidden",
};

const trendBar = {
  height: "100%",
  background: "#d4af37",
  borderRadius: "999px",
};

const emptyCard = {
  background: "#0f0f0f",
  border: "1px solid #222",
  borderRadius: "18px",
  padding: "28px",
  color: "#aaa",
};

const card = {
  background: "#0f0f0f",
  border: "1px solid #222",
  borderRadius: "18px",
  overflowX: "auto",
};

const table = {
  width: "100%",
  borderCollapse: "collapse",
  minWidth: "1350px",
};

const th = {
  padding: "18px",
  color: "#d4af37",
  textAlign: "left",
  borderBottom: "1px solid #222",
  whiteSpace: "nowrap",
};

const td = {
  padding: "18px",
  borderBottom: "1px solid #1f1f1f",
  verticalAlign: "top",
  position: "relative",
};

const btn = {
  background: "#d4af37",
  color: "#000",
  border: "none",
  padding: "9px 14px",
  borderRadius: "8px",
  marginRight: "8px",
  marginBottom: "6px",
  fontWeight: 700,
  cursor: "pointer",
};

const etaSelect = {
  width: "115px",
  background: "#080808",
  color: "#fff",
  border: "1px solid #333",
  borderRadius: "8px",
  padding: "8px 10px",
  outline: "none",
  cursor: "pointer",
};

const etaTime = {
  color: "#d4af37",
  fontSize: "12px",
  fontWeight: 700,
  marginTop: "7px",
};

const updatingText = {
  color: "#888",
  fontSize: "11px",
  marginTop: "6px",
};

const deliveredText = {
  color: "#2ecc71",
  fontWeight: 700,
};

const newOrderBanner = {
  position: "fixed",
  top: "90px",
  right: "28px",
  zIndex: 999,
  background: "#0f0f0f",
  border: "1px solid #d4af37",
  borderRadius: "16px",
  padding: "16px 18px",
  display: "flex",
  gap: "14px",
  alignItems: "center",
  boxShadow: "0 18px 50px rgba(0,0,0,.45)",
};

const bannerIcon = {
  width: "42px",
  height: "42px",
  borderRadius: "12px",
  background: "rgba(212,175,55,.16)",
  display: "flex",
  alignItems: "center",
  justifyContent: "center",
  fontSize: "22px",
};

const bannerText = {
  margin: "4px 0 0",
  color: "#aaa",
};

const newBadge = {
  display: "inline-block",
  marginLeft: "8px",
  background: "#d4af37",
  color: "#000",
  padding: "3px 7px",
  borderRadius: "999px",
  fontSize: "10px",
  fontWeight: 900,
};

const newOrderRow = {
  background: "rgba(212,175,55,.06)",
};

const badge = (status) => ({
  display: "inline-block",
  padding: "7px 12px",
  borderRadius: "999px",
  background:
    status === "delivered"
      ? "rgba(46,204,113,.18)"
      : status === "out_for_delivery"
      ? "rgba(155,89,182,.18)"
      : status === "preparing"
      ? "rgba(52,152,219,.18)"
      : status === "accepted"
      ? "rgba(212,175,55,.18)"
      : "rgba(255,170,0,.18)",
  color:
    status === "delivered"
      ? "#2ecc71"
      : status === "out_for_delivery"
      ? "#bb86fc"
      : status === "preparing"
      ? "#3498db"
      : status === "accepted"
      ? "#d4af37"
      : "#ffaa00",
  fontWeight: 700,
  textTransform: "capitalize",
  whiteSpace: "nowrap",
});

const paymentBadge = (status) => ({
  display: "inline-block",
  padding: "6px 10px",
  borderRadius: "999px",
  background:
    status === "paid"
      ? "rgba(46,204,113,.18)"
      : "rgba(255,170,0,.18)",
  color: status === "paid" ? "#2ecc71" : "#ffaa00",
  fontWeight: 700,
  fontSize: "12px",
  whiteSpace: "nowrap",
});