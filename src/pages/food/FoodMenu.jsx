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

  useEffect(() => {
    initFoodPage();
  }, []);

  useEffect(() => {
    if (!activeSession?.guest_id || !activeSession?.hotel_id) return;

    fetchMyOrders(activeSession.guest_id, activeSession.hotel_id);

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
          fetchMyOrders(activeSession.guest_id, activeSession.hotel_id);
        }
      )
      .subscribe();

    return () => {
      supabase.removeChannel(channel);
    };
  }, [activeSession?.guest_id, activeSession?.hotel_id]);

  const initFoodPage = async () => {
    setLoading(true);

    const roomNumber = window.location.pathname.split("/").pop();

    const { data: room, error: roomError } = await supabase
      .from("rooms")
      .select("*")
      .eq("room_number", roomNumber)
      .maybeSingle();

    if (roomError || !room) {
      setLoading(false);
      return;
    }

    await fetchMenu(room.hotel_id);

    const { data: session, error: sessionError } = await supabase
      .from("guest_sessions")
      .select("*")
      .eq("room_id", room.id)
      .eq("hotel_id", room.hotel_id)
      .eq("status", "active")
      .maybeSingle();

    if (sessionError || !session) {
      setLoading(false);
      return;
    }

    setActiveSession(session);
    await fetchMyOrders(session.guest_id, session.hotel_id);
    setLoading(false);
  };

  const fetchMenu = async (hotelId) => {
    let query = supabase
      .from("menu_items")
      .select("*")
      .eq("is_available", true)
      .order("item_name", { ascending: true });

    if (hotelId) {
      query = query.eq("hotel_id", hotelId);
    }

    const { data, error } = await query;

    if (error) {
      alert(error.message);
      return;
    }

    setItems(data || []);
  };

  const fetchMyOrders = async (guestId, hotelId) => {
    if (!guestId || !hotelId) return;

    const { data, error } = await supabase
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

    if (error) {
      console.error("My orders error:", error);
      return;
    }

    setMyOrders(data || []);
  };

  const addToCart = (item) => {
    setCart((prev) => {
      const existing = prev.find((cartItem) => cartItem.id === item.id);

      if (existing) {
        return prev.map((cartItem) =>
          cartItem.id === item.id
            ? { ...cartItem, quantity: cartItem.quantity + 1 }
            : cartItem
        );
      }

      return [...prev, { ...item, quantity: 1 }];
    });
  };

  const decreaseQty = (itemId) => {
    setCart((prev) =>
      prev
        .map((cartItem) =>
          cartItem.id === itemId
            ? { ...cartItem, quantity: cartItem.quantity - 1 }
            : cartItem
        )
        .filter((cartItem) => cartItem.quantity > 0)
    );
  };

  const increaseQty = (itemId) => {
    setCart((prev) =>
      prev.map((cartItem) =>
        cartItem.id === itemId
          ? { ...cartItem, quantity: cartItem.quantity + 1 }
          : cartItem
      )
    );
  };

  const cartTotal = cart.reduce(
    (total, item) => total + Number(item.price) * item.quantity,
    0
  );

  const placeOrder = async () => {
    if (cart.length === 0) {
      alert("Please add items to cart");
      return;
    }

    if (!activeSession) {
      alert("No active guest session found");
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
          },
        ])
        .select()
        .single();

      if (orderError) throw orderError;

      const orderItems = cart.map((item) => ({
        order_id: order.id,
        menu_item_id: item.id,
        quantity: item.quantity,
        price: item.price,
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
        message: `Room order placed · ₹${cartTotal} · ${cart.length} item(s)`,
      });

      alert("Food order placed successfully");
      setCart([]);
      fetchMyOrders(activeSession.guest_id, activeSession.hotel_id);
    } catch (err) {
      console.error("Food order error:", err);
      alert(err.message);
    } finally {
      setOrdering(false);
    }
  };

  const getStepClass = (status, step) => {
    const order = {
      pending: 1,
      preparing: 2,
      delivered: 3,
    };

    return order[status] >= step ? "track-step active" : "track-step";
  };

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
          <p>No active guest session found for this room.</p>
        </div>
      </div>
    );
  }

  return (
    <div className="food-page">
      <div className="food-header">
        <h1>🍽 Food Menu</h1>
        <p>Room Service</p>
      </div>

      {myOrders.length > 0 && (
        <div className="my-orders-box">
          <h2>My Orders</h2>

          {myOrders.map((order) => (
            <div className="my-order-card" key={order.id}>
              <div className="my-order-top">
                <strong>Order #{order.id.slice(0, 8)}</strong>
                <span>₹{order.total_amount}</span>
              </div>

              <div className="my-order-items">
                {order.food_order_items?.map((item, index) => (
                  <p key={index}>
                    {item.menu_items?.item_name || "Item"} x {item.quantity}
                  </p>
                ))}
              </div>

              <div className="order-tracker">
                <div className={getStepClass(order.order_status, 1)}>
                  <span>✅</span>
                  <p>Order Received</p>
                </div>

                <div className={getStepClass(order.order_status, 2)}>
                  <span>🍳</span>
                  <p>Preparing</p>
                </div>

                <div className={getStepClass(order.order_status, 3)}>
                  <span>🚪</span>
                  <p>Delivered</p>
                </div>
              </div>
            </div>
          ))}
        </div>
      )}

      {items.length === 0 ? (
        <p className="empty-menu">No menu items found.</p>
      ) : (
        <div className="food-grid">
          {items.map((item) => (
            <div key={item.id} className="food-card">
              <div className="food-category">{item.category || "Menu Item"}</div>

              <h3>{item.item_name}</h3>

              <p>{item.description || "Freshly prepared by hotel kitchen."}</p>

              <div className="food-footer">
                <span>₹{item.price}</span>
                <button onClick={() => addToCart(item)}>Add</button>
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
                <button onClick={() => decreaseQty(item.id)}>-</button>
                <span>{item.quantity}</span>
                <button onClick={() => increaseQty(item.id)}>+</button>
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
            {ordering ? "Placing Order..." : "Place Order"}
          </button>
        </div>
      )}
    </div>
  );
}