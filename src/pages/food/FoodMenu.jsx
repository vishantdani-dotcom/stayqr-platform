import { useEffect, useState } from "react";
import { supabase } from "../../lib/supabase";
import { createNotification } from "../../lib/notifications";
import "./FoodMenu.css";

export default function FoodMenu() {
  const [items, setItems] = useState([]);
  const [cart, setCart] = useState([]);
  const [myOrders, setMyOrders] = useState([]);
  const [activeSession, setActiveSession] = useState(null);
  const [loading, setLoading] = useState(true);
  const [ordering, setOrdering] = useState(false);
  const [, forceTick] = useState(0);

  useEffect(() => {
    initFoodPage();
  }, []);

  useEffect(() => {
    if (!activeSession?.guest_id || !activeSession?.hotel_id) {
      return undefined;
    }

    fetchMyOrders(
      activeSession.guest_id,
      activeSession.hotel_id,
      activeSession.room_id
    );

    const channel = supabase
      .channel(`guest_food_orders_${activeSession.guest_id}`)
      .on(
        "postgres_changes",
        {
          event: "*",
          schema: "public",
          table: "food_orders",
          filter: `guest_id=eq.${activeSession.guest_id}`,
        },
        () => {
          fetchMyOrders(
            activeSession.guest_id,
            activeSession.hotel_id,
            activeSession.room_id
          );
        }
      )
      .subscribe((status) => {
        console.log("Guest food realtime status:", status);
      });

    return () => {
      supabase.removeChannel(channel);
    };
  }, [
    activeSession?.guest_id,
    activeSession?.hotel_id,
    activeSession?.room_id,
  ]);
  useEffect(() => {
  const interval = setInterval(() => {
    forceTick((v) => v + 1);
  }, 1000);

  return () => clearInterval(interval);
}, []);

  async function initFoodPage() {
    setLoading(true);

    try {
      const roomNumber = decodeURIComponent(
        window.location.pathname.split("/").filter(Boolean).pop() || ""
      );

      if (!roomNumber) {
        throw new Error("Room number is missing from the food menu URL.");
      }

      const { data: room, error: roomError } = await supabase
        .from("rooms")
        .select("*")
        .eq("room_number", roomNumber)
        .maybeSingle();

      if (roomError) throw roomError;

      if (!room) {
        throw new Error("Room not found.");
      }

      await fetchMenu(room.hotel_id);

      const { data: session, error: sessionError } = await supabase
        .from("guest_sessions")
        .select("*")
        .eq("room_id", room.id)
        .eq("hotel_id", room.hotel_id)
        .eq("status", "active")
        .maybeSingle();

      if (sessionError) throw sessionError;

      if (!session) {
        setActiveSession(null);
        return;
      }

      setActiveSession(session);

      await fetchMyOrders(
        session.guest_id,
        session.hotel_id,
        session.room_id
      );
    } catch (error) {
      console.error("Food page initialization error:", error);
      setActiveSession(null);
    } finally {
      setLoading(false);
    }
  }

  async function fetchMenu(hotelId) {
    if (!hotelId) return;

    const { data, error } = await supabase
      .from("menu_items")
      .select("*")
      .eq("hotel_id", hotelId)
      .eq("is_available", true)
      .order("item_name", { ascending: true });

    if (error) {
      console.error("Menu fetch error:", error);
      alert(error.message);
      return;
    }

    setItems(data || []);
  }

  async function fetchMyOrders(guestId, hotelId, roomId) {
    if (!guestId || !hotelId) return;

    let query = supabase
      .from("food_orders")
      .select(`
        *,
        food_order_items (
          quantity,
          price,
          menu_items (
            item_name
          )
        )
      `)
      .eq("hotel_id", hotelId)
      .eq("guest_id", guestId)
      .order("created_at", { ascending: false });

    if (roomId) {
      query = query.eq("room_id", roomId);
    }

    const { data, error } = await query;

    if (error) {
      console.error("My orders error:", error);
      return;
    }

    setMyOrders(data || []);
  }

  function addToCart(item) {
    setCart((previousCart) => {
      const existingItem = previousCart.find(
        (cartItem) => cartItem.id === item.id
      );

      if (existingItem) {
        return previousCart.map((cartItem) =>
          cartItem.id === item.id
            ? {
                ...cartItem,
                quantity: cartItem.quantity + 1,
              }
            : cartItem
        );
      }

      return [
        ...previousCart,
        {
          ...item,
          quantity: 1,
        },
      ];
    });
  }

  function decreaseQty(itemId) {
    setCart((previousCart) =>
      previousCart
        .map((cartItem) =>
          cartItem.id === itemId
            ? {
                ...cartItem,
                quantity: cartItem.quantity - 1,
              }
            : cartItem
        )
        .filter((cartItem) => cartItem.quantity > 0)
    );
  }

  function increaseQty(itemId) {
    setCart((previousCart) =>
      previousCart.map((cartItem) =>
        cartItem.id === itemId
          ? {
              ...cartItem,
              quantity: cartItem.quantity + 1,
            }
          : cartItem
      )
    );
  }

  const cartTotal = cart.reduce(
    (total, item) =>
      total + Number(item.price || 0) * Number(item.quantity || 0),
    0
  );

  const totalCartQuantity = cart.reduce(
    (total, item) => total + Number(item.quantity || 0),
    0
  );

  async function placeOrder() {
    if (cart.length === 0) {
      alert("Please add items to cart.");
      return;
    }

    if (!activeSession) {
      alert("No active guest session found.");
      return;
    }

    try {
      setOrdering(true);

      const { data: order, error: orderError } = await supabase
        .from("food_orders")
        .insert([
          {
            hotel_id: activeSession.hotel_id,
            room_id: activeSession.room_id,
            guest_id: activeSession.guest_id,
            total_amount: cartTotal,
            payment_status: "pending",
            order_status: "pending",
            estimated_minutes: null,
            estimated_delivery_time: null,
          },
        ])
        .select()
        .single();

      if (orderError) throw orderError;

      const orderItems = cart.map((item) => ({
        order_id: order.id,
        menu_item_id: item.id,
        quantity: Number(item.quantity || 0),
        price: Number(item.price || 0),
      }));

      const { error: itemsError } = await supabase
        .from("food_order_items")
        .insert(orderItems);

      if (itemsError) throw itemsError;

      await createNotification({
        hotelId: activeSession.hotel_id,
        roomId: activeSession.room_id,
        guestId: activeSession.guest_id,
        type: "food_order",
        title: "New Food Order",
        message: `Room order placed · ₹${cartTotal} · ${totalCartQuantity} item(s)`,
      });

      alert("Food order placed successfully.");

      setCart([]);

      await fetchMyOrders(
        activeSession.guest_id,
        activeSession.hotel_id,
        activeSession.room_id
      );
    } catch (error) {
      console.error("Food order error:", error);
      alert(error.message || "Unable to place food order.");
    } finally {
      setOrdering(false);
    }
  }

  function getStepClass(status, step) {
    const statusOrder = {
      pending: 1,
      accepted: 2,
      preparing: 3,
      out_for_delivery: 4,
      delivered: 5,
    };

    const currentStep = statusOrder[status] || 0;

    return currentStep >= step
      ? "track-step active"
      : "track-step";
  }

  function formatOrderStatus(status) {
    const labels = {
      pending: "Order Placed",
      accepted: "Accepted by Kitchen",
      preparing: "Preparing",
      out_for_delivery: "On the Way",
      delivered: "Delivered",
    };

    return labels[status] || "Order Placed";
  }

  function getAnimatedProgressPercent(order) {
  const statusRanges = {
    pending: { min: 20, max: 39 },
    accepted: { min: 40, max: 64 },
    preparing: { min: 65, max: 89 },
    out_for_delivery: { min: 90, max: 99 },
    delivered: { min: 100, max: 100 },
  };

  const range = statusRanges[order?.order_status] || {
    min: 0,
    max: 0,
  };

  if (order?.order_status === "delivered") {
    return 100;
  }

  if (
    !order?.estimated_minutes ||
    !order?.estimated_delivery_time
  ) {
    return range.min;
  }

  const deliveryTime = new Date(
    order.estimated_delivery_time
  ).getTime();

  const estimatedDuration =
    Number(order.estimated_minutes) * 60 * 1000;

  const etaSetTime = deliveryTime - estimatedDuration;

  if (
    Number.isNaN(deliveryTime) ||
    estimatedDuration <= 0
  ) {
    return range.min;
  }

  const elapsedTime = Date.now() - etaSetTime;

  const elapsedRatio = Math.min(
    1,
    Math.max(0, elapsedTime / estimatedDuration)
  );

  const animatedProgress =
    range.min + (range.max - range.min) * elapsedRatio;

  return Math.round(animatedProgress);
}

  function getRemainingTime(deliveryTime) {
  if (!deliveryTime) return null;

  const remaining =
    new Date(deliveryTime).getTime() - Date.now();

  if (remaining <= 0) {
    return "Arriving shortly";
  }

  const minutes = Math.floor(remaining / 60000);
  const seconds = Math.floor((remaining % 60000) / 1000);

  return `${minutes}:${String(seconds).padStart(2, "0")} remaining`;
}

  if (loading) {
    return (
      <div className="food-page">
        <h2>Loading Menu...</h2>
      </div>
    );
  }

  if (!activeSession) {
    return (
      <div className="food-page">
        <div className="my-orders-box">
          <h2>Food Menu Not Active</h2>
          <p>No active guest session was found for this room.</p>
        </div>
      </div>
    );
  }

  return (
    <div className="food-page">
      <div className="food-header">
        <h1>🍽 Food Menu</h1>
        <p>Fresh room service delivered to your door.</p>
      </div>

      {myOrders.length > 0 && (
        <div className="my-orders-box">
          <h2>My Orders</h2>

          {myOrders.map((order) => {
            const progressPercent =
  getAnimatedProgressPercent(order);

            return (
              <div className="my-order-card" key={order.id}>
                <div className="my-order-top">
                  <div>
                    <strong>
                      Order #{String(order.id).slice(0, 8)}
                    </strong>

                    <p className="guest-order-current-status">
                      {formatOrderStatus(order.order_status)}
                    </p>
                  </div>

                  <span>₹{Number(order.total_amount || 0)}</span>
                </div>

                <div className="my-order-items">
                  {order.food_order_items?.length > 0 ? (
                    order.food_order_items.map((item, index) => (
                      <p key={`${order.id}-${index}`}>
                        {item.menu_items?.item_name || "Item"} x{" "}
                        {item.quantity}
                      </p>
                    ))
                  ) : (
                    <p>Order items are loading...</p>
                  )}
                </div>

                {order.order_status !== "delivered" &&
                  order.estimated_minutes &&
                  order.estimated_delivery_time && (
                    <div className="guest-order-eta">
                      <div>
                        <span>Estimated Delivery</span>

                        <strong>
                          {order.estimated_minutes} minutes
                        </strong>
                      </div>

                      <p>
  {getRemainingTime(order.estimated_delivery_time)}
</p>

<small>
  ETA:
  {" "}
  {new Date(
    order.estimated_delivery_time
  ).toLocaleTimeString("en-IN", {
    hour: "2-digit",
    minute: "2-digit",
  })}
</small>
                    </div>
                  )}

                {order.order_status !== "delivered" &&
                  !order.estimated_delivery_time && (
                    <div className="guest-order-eta guest-order-eta-waiting">
                      <div>
                        <span>Estimated Delivery</span>
                        <strong>Kitchen confirming</strong>
                      </div>

                      <p>
                        Your delivery time will appear once the kitchen
                        confirms the ETA.
                      </p>
                    </div>
                  )}

                {order.order_status === "delivered" && (
                  <div className="guest-order-delivered">
                    ✅ Delivered — Enjoy your meal!
                  </div>
                )}

                <div className="order-progress-section">
                  <div className="order-progress-header">
                    <span>Order Progress</span>
                    <strong>{progressPercent}%</strong>
                  </div>

                  <div className="order-progress">
                    <div
                      className="order-progress-fill"
                      style={{
                        width: `${progressPercent}%`,
                      }}
                    />
                  </div>

                  <p className="order-progress-status">
                    {formatOrderStatus(order.order_status)}
                  </p>
                </div>

                <div className="order-tracker">
                  <div
                    className={getStepClass(
                      order.order_status,
                      1
                    )}
                  >
                    <span>✅</span>
                    <p>Order Placed</p>
                  </div>

                  <div
                    className={getStepClass(
                      order.order_status,
                      2
                    )}
                  >
                    <span>👨‍🍳</span>
                    <p>Accepted</p>
                  </div>

                  <div
                    className={getStepClass(
                      order.order_status,
                      3
                    )}
                  >
                    <span>🔥</span>
                    <p>Preparing</p>
                  </div>

                  <div
                    className={getStepClass(
                      order.order_status,
                      4
                    )}
                  >
                    <span>🚶</span>
                    <p>On the Way</p>
                  </div>

                  <div
                    className={getStepClass(
                      order.order_status,
                      5
                    )}
                  >
                    <span>✅</span>
                    <p>Delivered</p>
                  </div>
                </div>
              </div>
            );
          })}
        </div>
      )}

      {items.length === 0 ? (
        <p className="empty-menu">
          No menu items are available.
        </p>
      ) : (
        <div className="food-grid">
          {items.map((item) => (
            <div key={item.id} className="food-card">
              <div className="food-category">
                {item.category || "Menu Item"}
              </div>

              <h3>{item.item_name}</h3>

              <p>
                {item.description ||
                  "Freshly prepared by the hotel kitchen."}
              </p>

              <div className="food-footer">
                <span>₹{item.price}</span>

                <button
                  type="button"
                  onClick={() => addToCart(item)}
                >
                  Add
                </button>
              </div>
            </div>
          ))}
        </div>
      )}

      {cart.length > 0 && (
        <div className="cart-box">
          <h2>Your Cart</h2>

          {cart.map((item) => (
            <div className="cart-row" key={item.id}>
              <div>
                <strong>{item.item_name}</strong>
                <p>₹{item.price} each</p>
              </div>

              <div className="cart-actions">
                <button
                  type="button"
                  onClick={() => decreaseQty(item.id)}
                >
                  −
                </button>

                <span>{item.quantity}</span>

                <button
                  type="button"
                  onClick={() => increaseQty(item.id)}
                >
                  +
                </button>
              </div>
            </div>
          ))}

          <div className="cart-total">
            <span>Total</span>
            <strong>₹{cartTotal}</strong>
          </div>

          <button
            className="place-order-btn"
            onClick={placeOrder}
            disabled={ordering}
          >
            {ordering
              ? "Placing Order..."
              : `Place Order · ₹${cartTotal}`}
          </button>
        </div>
      )}
    </div>
  );
}