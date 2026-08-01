import { useEffect, useState } from "react";
import { createNotification } from "../../lib/notifications";
import { supabase } from "../../lib/supabase";
import { getCurrentHotel } from "../../lib/currentHotel";
import { getCurrentStaff } from "../../lib/currentStaff";
import { navigateToSection } from "../../lib/bookingCalendar";
import "./ServiceRequests.css";

export default function ServiceRequests() {
  const [requests, setRequests] = useState([]);
  const [staffList, setStaffList] = useState([]);
  const [currentHotel, setCurrentHotel] = useState(null);
  const [currentStaff, setCurrentStaff] = useState(null);
  const [loading, setLoading] = useState(true);
  const [updatingId, setUpdatingId] = useState(null);

  useEffect(() => {
    initPage();
  }, []);

  useEffect(() => {
    if (!currentHotel?.id) return undefined;

    const channel = supabase
      .channel(`service_requests_table_${currentHotel.id}`)
      .on(
        "postgres_changes",
        {
          event: "*",
          schema: "public",
          table: "service_requests",
          filter: `hotel_id=eq.${currentHotel.id}`,
        },
        () => {
          fetchRequests(currentHotel.id);
        }
      )
      .subscribe((status) => {
        console.log("Service requests realtime:", status);
      });

    return () => {
      supabase.removeChannel(channel);
    };
  }, [currentHotel?.id]);

  async function initPage() {
    setLoading(true);

    try {
      const [hotel, staff] = await Promise.all([
        getCurrentHotel(),
        getCurrentStaff(),
      ]);

      if (!hotel) {
        alert("No hotel assigned");
        return;
      }

      setCurrentHotel(hotel);
      setCurrentStaff(staff || null);

      await Promise.all([
        fetchRequests(hotel.id),
        fetchActiveStaff(hotel.id),
      ]);
    } catch (error) {
      console.error("Service requests initialization error:", error);
      alert(error.message || "Unable to load service requests");
    } finally {
      setLoading(false);
    }
  }

  async function fetchRequests(hotelId = currentHotel?.id) {
    if (!hotelId) return;

    const { data, error } = await supabase
      .from("service_requests")
      .select(`
        *,
        guests (
          full_name,
          phone
        ),
        rooms (
          room_number,
          room_type
        )
      `)
      .eq("hotel_id", hotelId)
      .order("created_at", { ascending: false });

    if (error) {
      console.error("Fetch service requests error:", error);
      alert(error.message);
      return;
    }

    setRequests(data || []);
  }

  async function fetchActiveStaff(hotelId) {
    if (!hotelId) return;

    const { data, error } = await supabase
      .from("staff")
      .select("id, full_name, role, status")
      .eq("hotel_id", hotelId)
      .eq("status", "active")
      .order("full_name", { ascending: true });

    if (error) {
      console.error("Fetch staff error:", error);
      return;
    }

    setStaffList(data || []);
  }

  async function assignStaff(request, staffId) {
    if (!currentHotel?.id || !request?.id) return;

    try {
      setUpdatingId(request.id);

      const { error } = await supabase
        .from("service_requests")
        .update({
          assigned_to: staffId || null,
        })
        .eq("id", request.id)
        .eq("hotel_id", currentHotel.id);

      if (error) throw error;

      await fetchRequests(currentHotel.id);
    } catch (error) {
      console.error("Assign staff error:", error);
      alert(error.message);
    } finally {
      setUpdatingId(null);
    }
  }

  async function updatePriority(request, priority) {
    if (!currentHotel?.id || !request?.id) return;

    try {
      setUpdatingId(request.id);

      const { error } = await supabase
        .from("service_requests")
        .update({ priority })
        .eq("id", request.id)
        .eq("hotel_id", currentHotel.id);

      if (error) throw error;

      await fetchRequests(currentHotel.id);
    } catch (error) {
      console.error("Update priority error:", error);
      alert(error.message);
    } finally {
      setUpdatingId(null);
    }
  }

  async function updateETA(request, minutes) {
    if (!currentHotel?.id || !request?.id) return;

    const estimatedMinutes = Number(minutes);

    try {
      setUpdatingId(request.id);

      if (!estimatedMinutes) {
        const { error } = await supabase
          .from("service_requests")
          .update({
            estimated_minutes: null,
            estimated_arrival_time: null,
          })
          .eq("id", request.id)
          .eq("hotel_id", currentHotel.id);

        if (error) throw error;

        await fetchRequests(currentHotel.id);
        return;
      }

      const estimatedArrivalTime = new Date(
        Date.now() + estimatedMinutes * 60 * 1000
      ).toISOString();

      const { error } = await supabase
        .from("service_requests")
        .update({
          estimated_minutes: estimatedMinutes,
          estimated_arrival_time: estimatedArrivalTime,
        })
        .eq("id", request.id)
        .eq("hotel_id", currentHotel.id);

      if (error) throw error;

      await createNotification({
        hotelId: currentHotel.id,
        roomId: request.room_id,
        guestId: request.guest_id,
        type: "service_eta",
        title: `${request.request_type} ETA`,
        message: `Hotel staff is expected in approximately ${estimatedMinutes} minutes.`,
      });

      await fetchRequests(currentHotel.id);
    } catch (error) {
      console.error("Update service ETA error:", error);
      alert(error.message);
    } finally {
      setUpdatingId(null);
    }
  }

  async function updateRequestStatus(request, status) {
    if (!currentHotel?.id || !request?.id) return;

    try {
      setUpdatingId(request.id);

      const now = new Date().toISOString();

      const payload = {
        status,
      };

      if (status === "accepted") {
        payload.accepted_at = now;

        if (!request.assigned_to && currentStaff?.id) {
          payload.assigned_to = currentStaff.id;
        }
      }

      if (status === "in_progress") {
        payload.started_at = now;
      }

      if (status === "completed") {
        payload.completed_at = now;
      }

      const { error } = await supabase
        .from("service_requests")
        .update(payload)
        .eq("id", request.id)
        .eq("hotel_id", currentHotel.id);

      if (error) throw error;

      const notifications = {
        accepted: {
          title: `${getRequestIcon(request.request_type)} Request Accepted`,
          message: `Hotel staff has accepted your ${request.request_type} request.`,
        },

        in_progress: {
          title: "👷 Staff On The Way",
          message: `Your ${request.request_type} request is now in progress.`,
        },

        completed: {
          title: "✅ Request Completed",
          message: `Your ${request.request_type} request has been completed.`,
        },

        cancelled: {
          title: "❌ Request Cancelled",
          message: `Your ${request.request_type} request has been cancelled.`,
        },
      };

      const notification = notifications[status];

      if (notification) {
        await createNotification({
          hotelId: currentHotel.id,
          roomId: request.room_id,
          guestId: request.guest_id,
          type: "service_status",
          title: notification.title,
          message: notification.message,
        });
      }

      await fetchRequests(currentHotel.id);
    } catch (error) {
      console.error("Update request error:", error);
      alert(error.message);
    } finally {
      setUpdatingId(null);
    }
  }

  async function openCheckoutSettlement(request) {
    if (!currentHotel?.id || !request?.id || !request?.room_id) return;

    try {
      setUpdatingId(request.id);

      const { data: activeSession, error: sessionError } = await supabase
        .from("guest_sessions")
        .select("id")
        .eq("hotel_id", currentHotel.id)
        .eq("room_id", request.room_id)
        .eq("guest_id", request.guest_id)
        .eq("status", "active")
        .order("created_at", { ascending: false })
        .limit(1)
        .maybeSingle();

      if (sessionError) throw sessionError;

      if (!activeSession?.id) {
        throw new Error(
          "No active guest stay was found for this checkout request. Refresh the request or verify the guest in the Guests module."
        );
      }

      if (request.status === "pending") {
        const acceptedAt = new Date().toISOString();
        const { error: requestError } = await supabase
          .from("service_requests")
          .update({
            status: "accepted",
            accepted_at: request.accepted_at || acceptedAt,
            assigned_to: request.assigned_to || currentStaff?.id || null,
          })
          .eq("id", request.id)
          .eq("hotel_id", currentHotel.id);

        if (requestError) throw requestError;

        await createNotification({
          hotelId: currentHotel.id,
          roomId: request.room_id,
          guestId: request.guest_id,
          type: "service_status",
          title: "🚪 Checkout Request Accepted",
          message:
            "The front desk has accepted your checkout request and is preparing the final settlement.",
        });
      }

      navigateToSection("guests", {
        guestSessionId: activeSession.id,
        checkoutRequestId: request.id,
      });
    } catch (error) {
      console.error("Open checkout settlement error:", error);
      alert(error.message || "Unable to open the checkout settlement.");
    } finally {
      setUpdatingId(null);
    }
  }

  const pendingRequests = requests.filter(
    (request) => request.status === "pending"
  );

  const acceptedRequests = requests.filter(
    (request) => request.status === "accepted"
  );

  const inProgressRequests = requests.filter(
    (request) => request.status === "in_progress"
  );

  const completedRequests = requests.filter(
    (request) => request.status === "completed"
  );

  const activeRequests = requests.filter(
    (request) =>
      !["completed", "cancelled"].includes(request.status)
  );

  if (loading) {
    return (
      <div className="service-page">
        <div className="service-loading">
          Loading service requests...
        </div>
      </div>
    );
  }

  return (
    <div className="service-page">
      <div className="service-header">
        <div>
          <p className="service-kicker">
            Live Hotel Operations
          </p>

          <h1>Service Requests</h1>

          <p>
            {currentHotel?.hotel_name || "Hotel"} · Manage guest
            requests in real time.
          </p>
        </div>

        <button
          type="button"
          className="service-refresh-btn"
          onClick={() => fetchRequests(currentHotel?.id)}
        >
          Refresh
        </button>
      </div>

      <div className="service-stats">
        <StatCard
          title="Pending"
          value={pendingRequests.length}
          icon="🟡"
        />

        <StatCard
          title="Accepted"
          value={acceptedRequests.length}
          icon="🟠"
        />

        <StatCard
          title="In Progress"
          value={inProgressRequests.length}
          icon="🔵"
        />

        <StatCard
          title="Completed"
          value={completedRequests.length}
          icon="🟢"
        />
      </div>

      <div className="service-table-card">
        {requests.length === 0 ? (
          <div className="service-empty">
            <div>🛎️</div>
            <h3>No service requests</h3>
            <p>
              Guest requests will appear here automatically.
            </p>
          </div>
        ) : (
          <table className="service-table">
            <thead>
              <tr>
                <th>Room</th>
                <th>Guest</th>
                <th>Request</th>
                <th>Priority</th>
                <th>Assigned Staff</th>
                <th>ETA</th>
                <th>Status</th>
                <th>Requested</th>
                <th>Action</th>
              </tr>
            </thead>

            <tbody>
              {requests.map((request) => {
                const isUpdating = updatingId === request.id;
                const isCompleted =
                  request.status === "completed";
                const isCheckout =
                  request.request_type === "Checkout Request";

                return (
                  <tr key={request.id}>
                    <td>
                      <strong>
                        Room {request.rooms?.room_number || "-"}
                      </strong>

                      <small>
                        {request.rooms?.room_type || ""}
                      </small>
                    </td>

                    <td>
                      <strong>
                        {request.guests?.full_name || "Guest"}
                      </strong>

                      <small>
                        {request.guests?.phone || ""}
                      </small>
                    </td>

                    <td>
                      <div className="service-request-name">
                        <span>
                          {getRequestIcon(request.request_type)}
                        </span>

                        <div>
                          <strong>
                            {request.request_type || "Request"}
                          </strong>

                          <small>
                            {request.request_details ||
                              "No additional details"}
                          </small>
                        </div>
                      </div>
                    </td>

                    <td>
                      <select
                        className={`priority-select ${
                          request.priority || "normal"
                        }`}
                        value={request.priority || "normal"}
                        disabled={isCompleted || isUpdating}
                        onChange={(event) =>
                          updatePriority(
                            request,
                            event.target.value
                          )
                        }
                      >
                        <option value="low">Low</option>
                        <option value="normal">Normal</option>
                        <option value="high">High</option>
                        <option value="urgent">Urgent</option>
                      </select>
                    </td>

                    <td>
                      <select
                        className="service-select"
                        value={request.assigned_to || ""}
                        disabled={isCompleted || isUpdating}
                        onChange={(event) =>
                          assignStaff(request, event.target.value)
                        }
                      >
                        <option value="">Unassigned</option>

                        {staffList.map((staff) => (
                          <option key={staff.id} value={staff.id}>
                            {staff.full_name} · {staff.role}
                          </option>
                        ))}
                      </select>
                    </td>

                    <td>
                      {isCompleted ? (
                        <span className="service-done-text">
                          Completed
                        </span>
                      ) : (
                        <>
                          <select
                            className="service-select eta-select"
                            value={request.estimated_minutes || ""}
                            disabled={isUpdating}
                            onChange={(event) =>
                              updateETA(
                                request,
                                event.target.value
                              )
                            }
                          >
                            <option value="">Set ETA</option>
                            <option value="10">10 min</option>
                            <option value="20">20 min</option>
                            <option value="30">30 min</option>
                            <option value="45">45 min</option>
                          </select>

                          {request.estimated_arrival_time && (
                            <small className="service-eta-time">
                              By{" "}
                              {new Date(
                                request.estimated_arrival_time
                              ).toLocaleTimeString("en-IN", {
                                hour: "2-digit",
                                minute: "2-digit",
                              })}
                            </small>
                          )}
                        </>
                      )}
                    </td>

                    <td>
                      <span
                        className={`service-status ${
                          request.status || "pending"
                        }`}
                      >
                        {formatStatus(request.status)}
                      </span>
                    </td>

                    <td>
                      {request.created_at
                        ? new Date(
                            request.created_at
                          ).toLocaleString("en-IN")
                        : "-"}
                    </td>

                    <td>
                      <div className="service-actions">
                        {request.status === "pending" &&
                          !isCheckout && (
                            <button
                              type="button"
                              disabled={isUpdating}
                              onClick={() =>
                                updateRequestStatus(
                                  request,
                                  "accepted"
                                )
                              }
                            >
                              Accept
                            </button>
                          )}

                        {request.status === "pending" &&
                          isCheckout && (
                            <button
                              type="button"
                              disabled={isUpdating}
                              onClick={() =>
                                openCheckoutSettlement(request)
                              }
                            >
                              Open Settlement
                            </button>
                          )}

                        {request.status === "accepted" && (
                          <button
                            type="button"
                            disabled={isUpdating}
                            onClick={() =>
                              updateRequestStatus(
                                request,
                                "in_progress"
                              )
                            }
                          >
                            Start Work
                          </button>
                        )}

                        {request.status === "in_progress" && (
                          <button
                            type="button"
                            disabled={isUpdating}
                            onClick={() =>
                              updateRequestStatus(
                                request,
                                "completed"
                              )
                            }
                          >
                            Complete
                          </button>
                        )}

                        {!isCompleted &&
                          request.status !== "cancelled" &&
                          !isCheckout && (
                            <button
                              type="button"
                              className="cancel-btn"
                              disabled={isUpdating}
                              onClick={() =>
                                updateRequestStatus(
                                  request,
                                  "cancelled"
                                )
                              }
                            >
                              Cancel
                            </button>
                          )}

                        {isCompleted && (
                          <span className="service-done-text">
                            Done
                          </span>
                        )}

                        {request.status === "cancelled" && (
                          <span className="service-cancelled-text">
                            Cancelled
                          </span>
                        )}

                        {isUpdating && (
                          <small className="service-updating">
                            Updating...
                          </small>
                        )}
                      </div>
                    </td>
                  </tr>
                );
              })}
            </tbody>
          </table>
        )}
      </div>

      <p className="service-footer-note">
        Active requests: {activeRequests.length}
      </p>
    </div>
  );
}

function StatCard({ title, value, icon }) {
  return (
    <div className="service-stat-card">
      <div className="service-stat-icon">{icon}</div>

      <div>
        <p>{title}</p>
        <h3>{value}</h3>
      </div>
    </div>
  );
}

function formatStatus(status) {
  const labels = {
    pending: "Pending",
    accepted: "Accepted",
    in_progress: "In Progress",
    completed: "Completed",
    cancelled: "Cancelled",
  };

  return labels[status] || "Pending";
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