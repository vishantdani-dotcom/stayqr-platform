import { createNotification } from "../../lib/notifications";
import { useEffect, useState } from "react";
import { supabase } from "../../lib/supabase";
import "./GuestGuide.css";

export default function GuestGuide() {
  const [loading, setLoading] = useState(true);
  const [session, setSession] = useState(null);
  const [hotelInfo, setHotelInfo] = useState(null);
  const [requests, setRequests] = useState([]);
  const [requestLoading, setRequestLoading] = useState(false);

  useEffect(() => {
    fetchActiveSession();
  }, []);

  useEffect(() => {
    if (!session?.guest_id) return;

    fetchMyRequests(session.guest_id, session.hotel_id);
    fetchHotelInfo(session.hotel_id);

    const requestInterval = setInterval(() => {
      fetchMyRequests(session.guest_id, session.hotel_id);
    }, 3000);

    const sessionInterval = setInterval(() => {
      fetchActiveSession();
    }, 3000);

    return () => {
      clearInterval(requestInterval);
      clearInterval(sessionInterval);
    };
  }, [session?.guest_id]);

  const fetchActiveSession = async () => {
    const roomNumber = window.location.pathname.split("/").pop();

    const { data: roomData, error: roomError } = await supabase
      .from("rooms")
      .select("*")
      .eq("room_number", roomNumber)
      .maybeSingle();

    if (roomError || !roomData) {
      setSession(null);
      setLoading(false);
      return;
    }

    const { data, error } = await supabase
      .from("guest_sessions")
      .select(`
        *,
        guests (
          id,
          full_name,
          phone
        ),
        rooms (
          id,
          room_number,
          room_type
        )
      `)
      .eq("room_id", roomData.id)
      .eq("hotel_id", roomData.hotel_id)
      .eq("status", "active")
      .maybeSingle();

    if (error || !data) {
      setSession(null);
      setLoading(false);
      return;
    }

    const expiryTime = data.extended_until || data.checkout_time;

    if (expiryTime && new Date(expiryTime) < new Date()) {
      await supabase
        .from("guest_sessions")
        .update({
          status: "expired",
          expired_at: new Date().toISOString(),
        })
        .eq("id", data.id)
        .eq("hotel_id", data.hotel_id);

      setSession(null);
      setLoading(false);
      return;
    }

    setSession(data);
    setLoading(false);
  };

  const fetchHotelInfo = async (hotelId) => {
    const { data, error } = await supabase
      .from("hotel_info")
      .select("*")
      .eq("hotel_id", hotelId)
      .maybeSingle();

    if (error) {
      console.error("Hotel info error:", error);
      return;
    }

    setHotelInfo(data);
  };

  const fetchMyRequests = async (guestId, hotelId) => {
    const { data, error } = await supabase
      .from("service_requests")
      .select("*")
      .eq("hotel_id", hotelId)
      .eq("guest_id", guestId)
      .order("created_at", { ascending: false });

    if (error) return;

    setRequests(data || []);
  };

  const createRequest = async (requestType) => {
    if (!session) return;

    try {
      setRequestLoading(true);

      const { error } = await supabase.from("service_requests").insert([
  {
    hotel_id: session.hotel_id,
    room_id: session.room_id,
    guest_id: session.guest_id,
    request_type: requestType,
    request_details: `${requestType} requested from Room ${session.rooms?.room_number}`,
    status: "pending",
  },
]);

if (error) throw error;

await createNotification({
  hotelId: session.hotel_id,
  roomId: session.room_id,
  guestId: session.guest_id,
  type: "service_request",
  title: `${requestType} Request`,
  message: `Room ${session.rooms?.room_number} requested ${requestType}`,
});

      alert(`${requestType} request sent to hotel staff`);
      fetchMyRequests(session.guest_id, session.hotel_id);
    } catch (err) {
      alert(err.message);
    } finally {
      setRequestLoading(false);
    }
  };

  const openFoodMenu = () => {
    const roomNumber = session?.rooms?.room_number;
    if (!roomNumber) return alert("Room number not found");
    window.location.href = `/food/${roomNumber}`;
  };

  const openGoogleReview = () => {
    const reviewUrl = hotelInfo?.google_review_url;

    if (!reviewUrl) {
      alert("Google review link is not configured yet.");
      return;
    }

    window.open(reviewUrl, "_blank", "noopener,noreferrer");
  };

  const callReception = () => {
    window.location.href = `tel:${hotelInfo?.reception_phone || "+919503893141"}`;
  };

  const getRequestLabel = (status) => {
    if (status === "pending") return "Pending";
    if (status === "in_progress") return "In Progress";
    if (status === "completed") return "Completed";
    return status || "Pending";
  };

  if (loading) {
    return (
      <div className="guest-lux-page">
        <div className="guest-loading-card">
          <div className="guest-loading-mark">SQ</div>
          <p>Loading your digital room guide...</p>
        </div>
      </div>
    );
  }

  if (!session) {
    return (
      <div className="guest-lux-page">
        <section className="guest-inactive-card">
          <p className="section-kicker">STAYQR ACCESS</p>
          <h1>Room Guide Not Active</h1>
          <p>
            This QR is permanent, but no active guest session is currently
            available for this room. The stay may be expired or checked out.
            Please contact reception.
          </p>
          <button onClick={callReception}>Call Reception</button>
        </section>
      </div>
    );
  }

  const guestName = session.guests?.full_name || "Guest";
  const roomNumber = session.rooms?.room_number || "-";
  const roomType = session.rooms?.room_type || "Luxury Room";
  const expiryTime = session.extended_until || session.checkout_time;
  const hotelName = hotelInfo?.hotel_name || "StayQR Hotel";

  return (
    <div className="guest-lux-page">
      <div className="guest-topbar">
        <div>
          <h3>{hotelName}</h3>
          <span>{hotelInfo?.address || "Smart Hospitality Experience"}</span>
        </div>
        <button>Digital Guide</button>
      </div>

      <section className="guest-hero">
        <div className="guest-hero-overlay">
          <p className="section-kicker">WELCOME TO A SMART STAY EXPERIENCE</p>

          <h1>
            {hotelName.split(" ")[0]} <span>Stay</span>
          </h1>

          <p className="hero-sub">Digital Guest Guide · Powered by StayQR</p>

          <div className="guest-room-pill">
            Room {roomNumber} · {roomType}
          </div>

          <div className="guest-personal-card">
            <p>Welcome,</p>
            <h2>{guestName} 👋</h2>
            <span>Your personalized room guide is active.</span>

            {expiryTime && (
              <small style={{ display: "block", marginTop: "10px", color: "#d4af37" }}>
                Access valid until {new Date(expiryTime).toLocaleString("en-IN")}
              </small>
            )}
          </div>
        </div>
      </section>

      <section className="guest-section">
        <p className="section-kicker">01 — QUICK ACCESS</p>
        <h2>Your Digital Concierge</h2>
        <p className="section-sub">Everything you need, at your fingertips.</p>

        <div className="concierge-grid">
          <button onClick={() => createRequest("Housekeeping")} disabled={requestLoading}>
            <span>🧹</span>
            <div>
              <h4>Housekeeping</h4>
              <p>Request cleaning support →</p>
            </div>
          </button>

          <button onClick={() => createRequest("Water")} disabled={requestLoading}>
            <span>💧</span>
            <div>
              <h4>Water</h4>
              <p>Request drinking water →</p>
            </div>
          </button>

          <button onClick={() => createRequest("Towel")} disabled={requestLoading}>
            <span>🧺</span>
            <div>
              <h4>Fresh Towels</h4>
              <p>Request extra towels →</p>
            </div>
          </button>

          <button onClick={openFoodMenu}>
            <span>🍽️</span>
            <div>
              <h4>Food Menu</h4>
              <p>Browse menu & order food →</p>
            </div>
          </button>

          <button onClick={() => createRequest("Checkout Request")} disabled={requestLoading}>
            <span>🚪</span>
            <div>
              <h4>Checkout</h4>
              <p>Notify reception →</p>
            </div>
          </button>

          <button onClick={callReception}>
            <span>📞</span>
            <div>
              <h4>Reception</h4>
              <p>Call front desk →</p>
            </div>
          </button>
        </div>
      </section>

      {requests.length > 0 && (
        <section className="guest-section">
          <p className="section-kicker">02 — MY REQUESTS</p>
          <h2>Request Tracking</h2>
          <p className="section-sub">Track your hotel service requests.</p>

          <div className="my-requests-box">
            {requests.map((req) => (
              <div className="my-request-card" key={req.id}>
                <div>
                  <h4>{req.request_type}</h4>
                  <p>{req.request_details}</p>
                </div>

                <span className={`guest-request-status ${req.status}`}>
                  {getRequestLabel(req.status)}
                </span>
              </div>
            ))}
          </div>
        </section>
      )}

      <section className="guest-section">
        <p className="section-kicker">03 — HOTEL INFORMATION</p>
        <h2>Stay Information</h2>

        <div className="info-card">
          <div>
            <span className="info-label">Check-In</span>
            <h3>{hotelInfo?.checkin_time || "2:00 PM"}</h3>
          </div>

          <div>
            <span className="info-label">Check-Out</span>
            <h3>{hotelInfo?.checkout_time || "11:00 AM"}</h3>
          </div>

          <div>
            <span className="info-label">Breakfast</span>
            <h3>{hotelInfo?.breakfast_time || "8:00 AM - 10:30 AM"}</h3>
          </div>

          <div>
            <span className="info-label">Reception</span>
            <h3>{hotelInfo?.reception_phone || "+919503893141"}</h3>
          </div>
        </div>
      </section>

      <section className="guest-section">
        <p className="section-kicker">04 — WI-FI ACCESS</p>
        <h2>Instant Connect</h2>

        <div className="info-card">
          <div>
            <span className="info-label">Network</span>
            <h3>{hotelInfo?.wifi_name || "Hotel_Guest_WiFi"}</h3>
          </div>

          <div>
            <span className="info-label">Password</span>
            <h3>{hotelInfo?.wifi_password || "Ask Reception"}</h3>
          </div>
        </div>
      </section>

      <section className="guest-section">
        <p className="section-kicker">05 — EMERGENCY</p>
        <h2>Emergency Assistance</h2>

        <div className="concierge-grid">
          <button onClick={callReception}>
            <span>☎️</span>
            <div>
              <h4>Call Reception</h4>
              <p>Immediate hotel assistance →</p>
            </div>
          </button>

          <button
            onClick={() =>
              (window.location.href = `tel:${
                hotelInfo?.emergency_phone ||
                hotelInfo?.reception_phone ||
                "+919503893141"
              }`)
            }
          >
            <span>🚨</span>
            <div>
              <h4>Emergency Contact</h4>
              <p>Urgent support →</p>
            </div>
          </button>
        </div>
      </section>

      <section className="guest-section">
        <p className="section-kicker">06 — HOTEL RULES</p>
        <h2>Important Guidelines</h2>

        <div className="info-card">
          <div>
            <span className="info-label">About</span>
            <h3>
              {hotelInfo?.about ||
                `${hotelName} offers a smart hospitality experience powered by StayQR.`}
            </h3>
          </div>

          <div>
            <span className="info-label">Rules</span>
            <h3>
              {hotelInfo?.hotel_rules ||
                "Please maintain silence and contact reception for help."}
            </h3>
          </div>
        </div>
      </section>

      <section className="guest-section">
        <p className="section-kicker">07 — AMENITIES</p>
        <h2>Hotel Amenities</h2>

        <div className="concierge-grid">
          <button>
            <span>🍽️</span>
            <div>
              <h4>Restaurant</h4>
              <p>Multi-cuisine dining available</p>
            </div>
          </button>

          <button>
            <span>🚗</span>
            <div>
              <h4>Parking</h4>
              <p>Secure guest parking</p>
            </div>
          </button>

          <button>
            <span>📶</span>
            <div>
              <h4>High Speed WiFi</h4>
              <p>Available throughout hotel</p>
            </div>
          </button>

          <button>
            <span>🧺</span>
            <div>
              <h4>Laundry</h4>
              <p>Same day laundry service</p>
            </div>
          </button>

          <button>
            <span>🛎️</span>
            <div>
              <h4>Room Service</h4>
              <p>24×7 room service support</p>
            </div>
          </button>

          <button>
            <span>🏋️</span>
            <div>
              <h4>Gym</h4>
              <p>Fitness center access</p>
            </div>
          </button>
        </div>
      </section>

      <section className="guest-section review-reward-section">
        <p className="section-kicker">08 — REVIEW YOUR STAY</p>
        <h2>Share Your Experience</h2>
        <p className="section-sub">
          Your feedback helps the hotel improve and helps future guests make better decisions.
        </p>

        <div className="review-card">
          <div className="review-icon">⭐</div>

          <div>
            <h3>Enjoyed your stay?</h3>
            <p>
              You can leave an honest Google review for {hotelName}. This is completely optional.
            </p>

            <button
              className="review-btn"
              onClick={openGoogleReview}
              disabled={!hotelInfo?.google_review_url}
            >
              {hotelInfo?.google_review_url
                ? "Leave a Google Review"
                : "Google Review Link Not Configured"}
            </button>

            {!hotelInfo?.google_review_url && (
              <small className="review-help">
                Please contact reception if you wish to share feedback.
              </small>
            )}
          </div>
        </div>
      </section>

      {hotelInfo?.reward_enabled !== false && (
        <section className="guest-section review-reward-section">
          <p className="section-kicker">09 — THANK YOU REWARD</p>
          <h2>{hotelInfo?.reward_title || "Thank You Reward"}</h2>
          <p className="section-sub">
            {hotelInfo?.reward_description ||
              "Show this screen at reception to know if any offer is available."}
          </p>

          <div className="reward-card">
            <div className="reward-icon">🎁</div>

            <div>
              <h3>A small thank-you from the hotel</h3>
              <p>
                This reward is offered as a guest appreciation benefit. It is separate from Google reviews.
              </p>

              <button className="reward-btn" onClick={callReception}>
                Contact Reception
              </button>
            </div>
          </div>
        </section>
      )}

      <section className="guest-footer">
        <p>Powered by StayQR</p>
        <span>Luxury Smart Hospitality Experience</span>
      </section>
    </div>
  );
}