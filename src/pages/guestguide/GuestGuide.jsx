import { useCallback, useEffect, useState } from "react";
import {
  createGuestServiceRequest,
  getGuestAccessContext,
  getGuestServiceRequests,
  resolveGuestPortal,
} from "../../lib/guestPortal";
import "./GuestGuide.css";

const ACCESS_RECHECK_INTERVAL_MS = 15000;

export default function GuestGuide() {
  const [loading, setLoading] = useState(true);
  const [session, setSession] = useState(null);
  const [hotelInfo, setHotelInfo] = useState(null);
  const [requests, setRequests] = useState([]);
  const [requestLoading, setRequestLoading] = useState(false);
  const [nowMs, setNowMs] = useState(0);

  const clearGuestAccess = useCallback(() => {
    setSession(null);
    setHotelInfo(null);
    setRequests([]);
  }, []);

  const fetchActiveSession = useCallback(async ({ initial = false } = {}) => {
    if (initial) setLoading(true);

    try {
      const portal = await resolveGuestPortal("guest");

      if (!portal?.session) {
        throw new Error("This guest access link is invalid or expired.");
      }

      setSession(portal.session);
      setHotelInfo(portal.hotel_info || null);
      return true;
    } catch (error) {
      console.error("Guest portal access error:", error);
      clearGuestAccess();
      return false;
    } finally {
      if (initial) setLoading(false);
    }
  }, [clearGuestAccess]);

  const fetchMyRequests = useCallback(async () => {
    try {
      const data = await getGuestServiceRequests();
      setRequests(data);
    } catch (error) {
      console.error("Guest service requests error:", error);
      setRequests([]);
    }
  }, []);

  useEffect(() => {
    void fetchActiveSession({ initial: true });
  }, [fetchActiveSession]);

  const hasActiveSession = Boolean(session);

  useEffect(() => {
    if (!hasActiveSession) return undefined;

    const revalidateAccess = () => {
      void fetchActiveSession();
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
  }, [fetchActiveSession, hasActiveSession]);

  useEffect(() => {
    if (!hasActiveSession) return undefined;

    void fetchMyRequests();

    const requestInterval = window.setInterval(() => {
      void fetchMyRequests();
    }, 20000);

    return () => window.clearInterval(requestInterval);
  }, [fetchMyRequests, hasActiveSession]);

  useEffect(() => {
    const interval = setInterval(() => {
      setNowMs(new Date().getTime());
    }, 1000);

    return () => clearInterval(interval);
  }, []);

  async function createRequest(requestType) {
    if (!session || requestLoading) return;

    const duplicateRequest = requests.find(
      (request) =>
        request.request_type === requestType &&
        !["completed", "cancelled"].includes(request.status)
    );

    if (duplicateRequest) {
      alert(
        `Your ${requestType} request is already active. Please track it under My Requests.`
      );
      return;
    }

    try {
      setRequestLoading(true);

      const accessStillValid = await fetchActiveSession();
      if (!accessStillValid) {
        alert("Guest access has expired or been revoked.");
        return;
      }

      await createGuestServiceRequest(requestType);
      alert(`${requestType} request sent to hotel staff.`);
      await fetchMyRequests();
    } catch (error) {
      console.error("Create service request error:", error);
      await fetchActiveSession();
      alert(error.message || "Unable to create the service request.");
    } finally {
      setRequestLoading(false);
    }
  }

  async function openFoodMenu() {
    const accessStillValid = await fetchActiveSession();
    const { hotelSlug, accessToken } = getGuestAccessContext("guest");

    if (!accessStillValid || !hotelSlug || !accessToken) {
      alert("This guest access link is invalid or expired.");
      return;
    }

    window.location.href = `/food/${encodeURIComponent(hotelSlug)}/${encodeURIComponent(accessToken)}`;
  }

  function openGoogleReview() {
    const reviewUrl = hotelInfo?.google_review_url;

    if (!reviewUrl) {
      alert("Google review link is not configured yet.");
      return;
    }

    window.open(reviewUrl, "_blank", "noopener,noreferrer");
  }

  function callReception() {
    if (!hotelInfo?.reception_phone) {
      alert("Reception contact is not configured for this hotel.");
      return;
    }

    window.location.href = `tel:${hotelInfo.reception_phone}`;
  }

  function getRequestLabel(status) {
    const labels = {
      pending: "Request Received",
      accepted: "Accepted",
      in_progress: "Staff On The Way",
      completed: "Completed",
      cancelled: "Cancelled",
    };

    return labels[status] || "Request Received";
  }

  function getRequestIcon(requestType) {
    const icons = {
      Housekeeping: "🧹",
      Water: "💧",
      Towel: "🧺",
      "Fresh Towels": "🧺",
      "Checkout Request": "🚪",
      Toiletries: "🧴",
      "Extra Blanket": "🛏️",
      Maintenance: "🔧",
      Laundry: "👕",
    };

    return icons[requestType] || "🛎️";
  }

  function getRequestStepClass(status, step) {
    const statusOrder = {
      pending: 1,
      accepted: 2,
      in_progress: 3,
      completed: 4,
    };

    const currentStep = statusOrder[status] || 0;

    return currentStep >= step
      ? "service-track-step active"
      : "service-track-step";
  }

  function getServiceProgress(request) {
    if (request?.status === "cancelled") return 0;
    if (request?.status === "completed") return 100;

    const statusRanges = {
      pending: { min: 15, max: 29 },
      accepted: { min: 30, max: 59 },
      in_progress: { min: 60, max: 95 },
    };

    const range = statusRanges[request?.status] || {
      min: 0,
      max: 0,
    };

    if (
      !request?.estimated_minutes ||
      !request?.estimated_arrival_time
    ) {
      return range.min;
    }

    const arrivalTime = new Date(
      request.estimated_arrival_time
    ).getTime();

    const estimatedDuration =
      Number(request.estimated_minutes) * 60 * 1000;

    if (
      Number.isNaN(arrivalTime) ||
      estimatedDuration <= 0
    ) {
      return range.min;
    }

    const etaSetTime = arrivalTime - estimatedDuration;
    const elapsed = nowMs - etaSetTime;

    const elapsedRatio = Math.min(
      1,
      Math.max(0, elapsed / estimatedDuration)
    );

    const progress =
      range.min + (range.max - range.min) * elapsedRatio;

    return Math.round(progress);
  }

  function getRemainingTime(arrivalTime) {
    if (!arrivalTime) return null;

    const targetTime = new Date(arrivalTime).getTime();

    if (Number.isNaN(targetTime)) return null;

    const remaining = targetTime - nowMs;

    if (remaining <= 0) {
      return "Arriving shortly";
    }

    const minutes = Math.floor(remaining / 60000);
    const seconds = Math.floor(
      (remaining % 60000) / 1000
    );

    return `${minutes}:${String(seconds).padStart(
      2,
      "0"
    )} remaining`;
  }

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
          <h1>Guest Access Not Available</h1>

          <p>
            This signed StayQR link is invalid, expired or has been revoked.
            Please contact the hotel using the details provided at reception.
          </p>
        </section>
      </div>
    );
  }

  const guestName = session.guests?.full_name || "Guest";
  const roomNumber = session.rooms?.room_number || "-";
  const roomType =
    session.rooms?.room_type || "Luxury Room";
  const expiryTime =
    session.extended_until || session.checkout_time;
  const hotelName =
    hotelInfo?.hotel_name || "StayQR Hotel";

  return (
    <div className="guest-lux-page">
      <div className="guest-topbar">
        <div>
          <h3>{hotelName}</h3>
          <span>
            {hotelInfo?.address ||
              "Smart Hospitality Experience"}
          </span>
        </div>

        <button>Digital Guide</button>
      </div>

      <section className="guest-hero">
        <div className="guest-hero-overlay">
          <p className="section-kicker">
            WELCOME TO A SMART STAY EXPERIENCE
          </p>

          <h1>
            {hotelName.split(" ")[0]} <span>Stay</span>
          </h1>

          <p className="hero-sub">
            Digital Guest Guide · Powered by StayQR
          </p>

          <div className="guest-room-pill">
            Room {roomNumber} · {roomType}
          </div>

          <div className="guest-personal-card">
            <p>Welcome,</p>
            <h2>{guestName} 👋</h2>
            <span>
              Your personalized room guide is active.
            </span>

            {expiryTime && (
              <small
                style={{
                  display: "block",
                  marginTop: "10px",
                  color: "#d4af37",
                }}
              >
                Access valid until{" "}
                {new Date(expiryTime).toLocaleString(
                  "en-IN"
                )}
              </small>
            )}
          </div>
        </div>
      </section>

      <section className="guest-section">
        <p className="section-kicker">
          01 — QUICK ACCESS
        </p>

        <h2>Your Digital Concierge</h2>

        <p className="section-sub">
          Everything you need, at your fingertips.
        </p>

        <div className="concierge-grid">
          <button
            onClick={() =>
              createRequest("Housekeeping")
            }
            disabled={requestLoading}
          >
            <span>🧹</span>

            <div>
              <h4>Housekeeping</h4>
              <p>Request cleaning support →</p>
            </div>
          </button>

          <button
            onClick={() => createRequest("Water")}
            disabled={requestLoading}
          >
            <span>💧</span>

            <div>
              <h4>Water</h4>
              <p>Request drinking water →</p>
            </div>
          </button>

          <button
            onClick={() => createRequest("Towel")}
            disabled={requestLoading}
          >
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
              <p>Browse menu &amp; order food →</p>
            </div>
          </button>

          <button
            onClick={() =>
              createRequest("Checkout Request")
            }
            disabled={requestLoading}
          >
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
          <p className="section-kicker">
            02 — MY REQUESTS
          </p>

          <h2>Request Tracking</h2>

          <p className="section-sub">
            Track your hotel service requests in real time.
          </p>

          <div className="my-requests-box">
            {requests.map((request) => {
              const progress =
                getServiceProgress(request);

              const remainingTime =
                getRemainingTime(
                  request.estimated_arrival_time
                );

              return (
                <div
                  className={`my-request-card premium-service-request ${
                    request.status || "pending"
                  }`}
                  key={request.id}
                >
                  <div className="service-request-top">
                    <div className="service-request-heading">
                      <span className="service-request-icon">
                        {getRequestIcon(
                          request.request_type
                        )}
                      </span>

                      <div>
                        <h4>
                          {request.request_type ||
                            "Service Request"}
                        </h4>

                        <p>
                          {request.request_details ||
                            "Request sent to hotel staff."}
                        </p>
                      </div>
                    </div>

                    <span
                      className={`guest-request-status ${
                        request.status || "pending"
                      }`}
                    >
                      {getRequestLabel(request.status)}
                    </span>
                  </div>

                  {request.status === "cancelled" ? (
                    <div className="service-request-cancelled">
                      ❌ This request was cancelled.
                    </div>
                  ) : request.status === "completed" ? (
                    <div className="service-request-completed">
                      ✅ Request completed successfully.
                    </div>
                  ) : (
                    <div className="service-request-eta">
                      <div>
                        <span>Estimated Arrival</span>

                        <strong>
                          {request.estimated_minutes
                            ? `${request.estimated_minutes} minutes`
                            : "Staff confirming"}
                        </strong>
                      </div>

                      {remainingTime && (
                        <p>{remainingTime}</p>
                      )}

                      {request.estimated_arrival_time && (
                        <small>
                          Expected by{" "}
                          {new Date(
                            request.estimated_arrival_time
                          ).toLocaleTimeString("en-IN", {
                            hour: "2-digit",
                            minute: "2-digit",
                          })}
                        </small>
                      )}
                    </div>
                  )}

                  {request.status !== "cancelled" && (
                    <>
                      <div className="service-progress-section">
                        <div className="service-progress-header">
                          <span>Request Progress</span>
                          <strong>{progress}%</strong>
                        </div>

                        <div className="service-progress-bar">
                          <div
                            className="service-progress-fill"
                            style={{
                              width: `${progress}%`,
                            }}
                          />
                        </div>

                        <p>
                          {getRequestLabel(request.status)}
                        </p>
                      </div>

                      <div className="service-request-tracker">
                        <div
                          className={getRequestStepClass(
                            request.status,
                            1
                          )}
                        >
                          <span>✅</span>
                          <p>Request Received</p>
                        </div>

                        <div
                          className={getRequestStepClass(
                            request.status,
                            2
                          )}
                        >
                          <span>🛎️</span>
                          <p>Accepted</p>
                        </div>

                        <div
                          className={getRequestStepClass(
                            request.status,
                            3
                          )}
                        >
                          <span>👷</span>
                          <p>Staff On The Way</p>
                        </div>

                        <div
                          className={getRequestStepClass(
                            request.status,
                            4
                          )}
                        >
                          <span>✅</span>
                          <p>Completed</p>
                        </div>
                      </div>
                    </>
                  )}

                  <small className="service-request-created">
                    Requested{" "}
                    {request.created_at
                      ? new Date(
                          request.created_at
                        ).toLocaleString("en-IN")
                      : "-"}
                  </small>
                </div>
              );
            })}
          </div>
        </section>
      )}

      <section className="guest-section">
        <p className="section-kicker">
          03 — HOTEL INFORMATION
        </p>

        <h2>Stay Information</h2>

        <div className="info-card">
          <div>
            <span className="info-label">
              Check-In
            </span>

            <h3>
              {hotelInfo?.checkin_time || "Not configured"}
            </h3>
          </div>

          <div>
            <span className="info-label">
              Check-Out
            </span>

            <h3>
              {hotelInfo?.checkout_time || "Not configured"}
            </h3>
          </div>

          <div>
            <span className="info-label">
              Breakfast
            </span>

            <h3>
              {hotelInfo?.breakfast_time ||
                "Not configured"}
            </h3>
          </div>

          <div>
            <span className="info-label">
              Reception
            </span>

            <h3>
              {hotelInfo?.reception_phone || "Not configured"}
            </h3>
          </div>
        </div>
      </section>

      <section className="guest-section">
        <p className="section-kicker">
          04 — WI-FI ACCESS
        </p>

        <h2>Instant Connect</h2>

        <div className="info-card">
          <div>
            <span className="info-label">Network</span>

            <h3>
              {hotelInfo?.wifi_name ||
                "Not configured"}
            </h3>
          </div>

          <div>
            <span className="info-label">
              Password
            </span>

            <h3>
              {hotelInfo?.wifi_password ||
                "Not configured"}
            </h3>
          </div>
        </div>
      </section>

      <section className="guest-section">
        <p className="section-kicker">
          05 — EMERGENCY
        </p>

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
            onClick={() => {
              const emergencyPhone =
                hotelInfo?.emergency_phone || hotelInfo?.reception_phone;

              if (!emergencyPhone) {
                alert("Emergency contact is not configured for this hotel.");
                return;
              }

              window.location.href = `tel:${emergencyPhone}`;
            }}
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
        <p className="section-kicker">
          06 — HOTEL RULES
        </p>

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
        <p className="section-kicker">
          07 — AMENITIES
        </p>

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
        <p className="section-kicker">
          08 — REVIEW YOUR STAY
        </p>

        <h2>Share Your Experience</h2>

        <p className="section-sub">
          Your feedback helps the hotel improve and helps
          future guests make better decisions.
        </p>

        <div className="review-card">
          <div className="review-icon">⭐</div>

          <div>
            <h3>Enjoyed your stay?</h3>

            <p>
              You can leave an honest Google review for{" "}
              {hotelName}. This is completely optional.
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
                Please contact reception if you wish to
                share feedback.
              </small>
            )}
          </div>
        </div>
      </section>

      {hotelInfo?.reward_enabled !== false && (
        <section className="guest-section review-reward-section">
          <p className="section-kicker">
            09 — THANK YOU REWARD
          </p>

          <h2>
            {hotelInfo?.reward_title ||
              "Thank You Reward"}
          </h2>

          <p className="section-sub">
            {hotelInfo?.reward_description ||
              "Show this screen at reception to know if any offer is available."}
          </p>

          <div className="reward-card">
            <div className="reward-icon">🎁</div>

            <div>
              <h3>
                A small thank-you from the hotel
              </h3>

              <p>
                This reward is offered as a guest
                appreciation benefit. It is separate from
                Google reviews.
              </p>

              <button
                className="reward-btn"
                onClick={callReception}
              >
                Contact Reception
              </button>
            </div>
          </div>
        </section>
      )}

      <section className="guest-footer">
        <p>Powered by StayQR</p>
        <span>
          Luxury Smart Hospitality Experience
        </span>
      </section>
    </div>
  );
}