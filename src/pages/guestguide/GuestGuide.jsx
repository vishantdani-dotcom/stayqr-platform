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

    fetchMyRequests(session.guest_id);
    fetchHotelInfo(session.hotel_id);

    const requestInterval = setInterval(() => {
      fetchMyRequests(session.guest_id);
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
      .single();

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
        .eq("id", data.id);

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

  const fetchMyRequests = async (guestId) => {
    const { data, error } = await supabase
      .from("service_requests")
      .select("*")
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

      alert(`${requestType} request sent to hotel staff`);
      fetchMyRequests(session.guest_id);
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
          <button onClick={() => (window.location.href = "tel:+919503893141")}>
            Call Reception
          </button>
        </section>
      </div>
    );
  }

  const guestName = session.guests?.full_name || "Guest";
  const roomNumber = session.rooms?.room_number || "-";
  const roomType = session.rooms?.room_type || "Luxury Room";
  const expiryTime = session.extended_until || session.checkout_time;

  return (
    <div className="guest-lux-page">
      <div className="guest-topbar">
        <div>
          <h3>{hotelInfo?.hotel_name || "VD Stay Inn"}</h3>
          <span>{hotelInfo?.address || "Nagpur, Maharashtra"}</span>
        </div>
        <button>Digital Guide</button>
      </div>

      <section className="guest-hero">
        <div className="guest-hero-overlay">
          <p className="section-kicker">WELCOME TO A WORLD OF REFINEMENT</p>

          <h1>
            VD <span>Stay</span>
          </h1>

          <p className="hero-sub">Digital Guest Guide · Your Luxury Companion</p>

          <div className="guest-room-pill">
            Room {roomNumber} · {roomType}
          </div>

          <div className="guest-personal-card">
            <p>Welcome,</p>
            <h2>{guestName} 👋</h2>
            <span>Your personalized room guide is active.</span>

            {expiryTime && (
              <small style={{ display: "block", marginTop: "10px", color: "#d4af37" }}>
                Access valid until{" "}
                {new Date(expiryTime).toLocaleString("en-IN")}
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

          <button onClick={() => (window.location.href = `tel:${hotelInfo?.reception_phone || "+919503893141"}`)}>
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
            <h3>{hotelInfo?.wifi_name || "VDStay_Guest"}</h3>
          </div>

          <div>
            <span className="info-label">Password</span>
            <h3>{hotelInfo?.wifi_password || "welcome123"}</h3>
          </div>
        </div>
      </section>

      <section className="guest-section">
        <p className="section-kicker">05 — EMERGENCY</p>
        <h2>Emergency Assistance</h2>

        <div className="concierge-grid">
          <button onClick={() => (window.location.href = `tel:${hotelInfo?.reception_phone || "+919503893141"}`)}>
            <span>☎️</span>
            <div>
              <h4>Call Reception</h4>
              <p>Immediate hotel assistance →</p>
            </div>
          </button>

          <button onClick={() => (window.location.href = `tel:${hotelInfo?.emergency_phone || "+919503893141"}`)}>
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
            <h3>{hotelInfo?.about || "VD Stay Inn offers a smart hospitality experience powered by StayQR."}</h3>
          </div>

          <div>
            <span className="info-label">Rules</span>
            <h3>{hotelInfo?.hotel_rules || "Please maintain silence and contact reception for help."}</h3>
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

      <section className="guest-footer">
        <p>Powered by StayQR</p>
        <span>Luxury Smart Hospitality Experience</span>
      </section>
    </div>
  );
}