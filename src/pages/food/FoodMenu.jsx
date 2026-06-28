import { useEffect, useState } from "react";
import { supabase } from "../../lib/supabase";
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
  if (!activeSession?.guest_id) return;

  fetchMyOrders(activeSession.guest_id);

  const interval = setInterval(() => {
    fetchMyOrders(activeSession.guest_id);
  }, 3000);

  return () => clearInterval(interval);
}, [activeSession]);

  const initFoodPage = async () => {
    setLoading(true);

    await fetchMenu();

    const roomNumber = window.location.pathname.split("/").pop();

    const { data: room } = await supabase
      .from("rooms")
      .select("*")
      .eq("room_number", roomNumber)
      .single();

    if (!room) {
      setLoading(false);
      return;
    }

    const { data: session } = await supabase
      .from("guest_sessions")
      .select("*")
      .eq("room_id", room.id)
      .eq("status", "active")
      .single();

    if (session) {
      setActiveSession(session);
      await fetchMyOrders(session.guest_id);
    }

    setLoading(false);
  };

  const fetchMenu = async () => {
    const { data, error } = await supabase
      .from("menu_items")
      .select("*")
      .order("item_name", { ascending: true });

    if (error) {
      alert(error.message);
      return;
    }

    setItems(data || []);
  };

  const fetchMyOrders = async (guestId) => {
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

      alert("Food order placed successfully");

      setCart([]);
      fetchMyOrders(activeSession.guest_id);
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

  return (
    <div className="food-page">
      <div className="food-header">
        <h1>🍽 Food Menu</h1>
        <p>VD Stay Inn Room Service</p>
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
              <div className="food-category">Menu Item</div>

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