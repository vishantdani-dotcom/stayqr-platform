import { useCallback, useEffect, useState } from "react";
import {
  getGuestFoodOrders,
  getGuestMenu,
  placeGuestFoodOrder,
  resolveGuestPortal,
} from "../../lib/guestPortal";
import "./FoodMenu.css";

const ACCESS_RECHECK_INTERVAL_MS = 15000;

export default function FoodMenu() {
  const [items, setItems] = useState([]);
  const [cart, setCart] = useState([]);
  const [myOrders, setMyOrders] = useState([]);
  const [activeSession, setActiveSession] = useState(null);
  const [loading, setLoading] = useState(true);
  const [ordering, setOrdering] = useState(false);
  const [nowMs, setNowMs] = useState(0);

  const clearFoodAccess = useCallback(() => {
    setActiveSession(null);
    setItems([]);
    setMyOrders([]);
    setCart([]);
  }, []);

  const validateFoodAccess = useCallback(async () => {
    try {
      const portal = await resolveGuestPortal("food");

      if (!portal?.session) {
        throw new Error("This guest access link is invalid or expired.");
      }

      setActiveSession(portal.session);
      return portal;
    } catch (error) {
      console.error("Food portal access error:", error);
      clearFoodAccess();
      return null;
    }
  }, [clearFoodAccess]);

  const fetchMenu = useCallback(async () => {
    try {
      const data = await getGuestMenu();
      setItems(data);
    } catch (error) {
      console.error("Menu fetch error:", error);
      setItems([]);
    }
  }, []);

  const fetchMyOrders = useCallback(async () => {
    try {
      const data = await getGuestFoodOrders();
      setMyOrders(data);
    } catch (error) {
      console.error("My orders error:", error);
      setMyOrders([]);
    }
  }, []);

  const initFoodPage = useCallback(async () => {
    setLoading(true);

    const portal = await validateFoodAccess();
    if (portal) {
      await Promise.all([fetchMenu(), fetchMyOrders()]);
    }

    setLoading(false);
  }, [fetchMenu, fetchMyOrders, validateFoodAccess]);

  useEffect(() => {
    void initFoodPage();
  }, [initFoodPage]);

  const hasActiveSession = Boolean(activeSession);

  useEffect(() => {
    if (!hasActiveSession) return undefined;

    const revalidateAccess = () => {
      void validateFoodAccess();
    };

    const handleVisibilityChange = () => {
      if (document.visibilityState === "visible") {
        revalidateAccess();
      }
    };

    window.addEventListener("focus", revalidateAccess);
    window.addEventListener("pageshow", revalidateAccess);
    document.addEventListener("visibilitychange", handleVisibilityChange);

    const accessInterval = window.setInterval(
      revalidateAccess,
      ACCESS_RECHECK_INTERVAL_MS
    );

    return () => {
      window.removeEventListener("focus", revalidateAccess);
      window.removeEventListener("pageshow", revalidateAccess);
      document.removeEventListener("visibilitychange", handleVisibilityChange);
      window.clearInterval(accessInterval);
    };
  }, [hasActiveSession, validateFoodAccess]);

  useEffect(() => {
    if (!hasActiveSession) return undefined;

    void fetchMyOrders();

    const orderInterval = window.setInterval(() => {
      void fetchMyOrders();
    }, 15000);

    return () => window.clearInterval(orderInterval);
  }, [fetchMyOrders, hasActiveSession]);
  useEffect(() => {
  const interval = setInterval(() => {
    setNowMs(new Date().getTime());
  }, 1000);

  return () => clearInterval(interval);
}, []);

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


  async function placeOrder() {
    if (cart.length === 0) {
      alert("Please add items to cart.");
      return;
    }

    if (!activeSession) {
      alert("This guest access link is invalid or expired.");
      return;
    }

    try {
      setOrdering(true);

      const portal = await validateFoodAccess();
      if (!portal) {
        alert("Guest access has expired or been revoked.");
        return;
      }

      await placeGuestFoodOrder(
        cart.map((item) => ({
          menu_item_id: item.id,
          quantity: Number(item.quantity || 0),
        }))
      );

      alert("Food order placed successfully.");
      setCart([]);
      await fetchMyOrders();
    } catch (error) {
      console.error("Food order error:", error);
      await validateFoodAccess();
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

  const elapsedTime = nowMs - etaSetTime;

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
    new Date(deliveryTime).getTime() - nowMs;

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
          <p>This signed StayQR link is invalid, expired or has been revoked. Please contact the hotel reception.</p>
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