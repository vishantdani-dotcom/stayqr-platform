import { useEffect, useMemo, useState } from "react";
import { supabase } from "../../lib/supabase";
import { getCurrentHotel } from "../../lib/currentHotel";
import { getCurrentStaff } from "../../lib/currentStaff";
import "./ServiceRequests.css";

export default function ServiceRequests() {
  const [requests, setRequests] = useState([]);
  const [loading, setLoading] = useState(true);
  const [currentHotel, setCurrentHotel] = useState(null);
  const [currentStaff, setCurrentStaff] = useState(null);

  useEffect(() => {
    initPage();
  }, []);

  useEffect(() => {
    if (!currentHotel?.id) return;

    fetchRequests(currentHotel.id);

    const channel = supabase
      .channel(`service_requests_${currentHotel.id}`)
      .on(
        "postgres_changes",
        {
          event: "*",
          schema: "public",
          table: "service_requests",
          filter: `hotel_id=eq.${currentHotel.id}`,
        },
        () => fetchRequests(currentHotel.id)
      )
      .subscribe();

    return () => supabase.removeChannel(channel);
  }, [currentHotel?.id]);

  async function initPage() {
    const hotel = await getCurrentHotel();
    const staff = await getCurrentStaff();

    if (!hotel) {
      alert("No hotel assigned");
      setLoading(false);
      return;
    }

    setCurrentHotel(hotel);
    setCurrentStaff(staff);
    await fetchRequests(hotel.id);
    setLoading(false);
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
      console.error(error);
      alert(error.message);
      return;
    }

    setRequests(data || []);
  }

  async function updateRequest(request, status) {
    const payload = { status };

    if (status === "accepted") {
      payload.accepted_at = new Date().toISOString();
      if (currentStaff?.id) payload.assigned_to = currentStaff.id;
    }

    if (status === "completed") {
      payload.completed_at = new Date().toISOString();
    }

    const { error } = await supabase
      .from("service_requests")
      .update(payload)
      .eq("id", request.id)
      .eq("hotel_id", currentHotel?.id);

    if (error) {
      alert(error.message);
      return;
    }

    fetchRequests(currentHotel?.id);
  }

  async function processCheckout(request) {
    try {
      const { error: roomError } = await supabase
        .from("rooms")
        .update({ status: "cleaning" })
        .eq("id", request.room_id)
        .eq("hotel_id", currentHotel?.id);

      if (roomError) throw roomError;

      const { error: sessionError } = await supabase
        .from("guest_sessions")
        .update({
          status: "completed",
          expired_at: new Date().toISOString(),
        })
        .eq("room_id", request.room_id)
        .eq("hotel_id", currentHotel?.id)
        .eq("status", "active");

      if (sessionError) throw sessionError;

      const { error: requestError } = await supabase
        .from("service_requests")
        .update({
          status: "completed",
          completed_at: new Date().toISOString(),
        })
        .eq("id", request.id)
        .eq("hotel_id", currentHotel?.id);

      if (requestError) throw requestError;

      const { error: housekeepingError } = await supabase
        .from("housekeeping_tasks")
        .insert([
          {
            hotel_id: currentHotel?.id,
            room_id: request.room_id,
            room_number: request.rooms?.room_number,
            task_type: "room_cleaning",
            status: "pending",
          },
        ]);

      if (housekeepingError) throw housekeepingError;

      alert("Guest checked out successfully. Housekeeping task created.");
      fetchRequests(currentHotel?.id);
    } catch (err) {
      console.error(err);
      alert(err.message);
    }
  }

  const columns = useMemo(
    () => [
      {
        key: "pending",
        title: "Pending",
        icon: "🟡",
        items: requests.filter((r) => r.status === "pending"),
      },
      {
        key: "accepted",
        title: "Accepted",
        icon: "🟠",
        items: requests.filter((r) => r.status === "accepted"),
      },
      {
        key: "in_progress",
        title: "In Progress",
        icon: "🔵",
        items: requests.filter((r) => r.status === "in_progress"),
      },
      {
        key: "completed",
        title: "Completed",
        icon: "🟢",
        items: requests.filter((r) => r.status === "completed"),
      },
    ],
    [requests]
  );

  const pendingCount = requests.filter((r) => r.status === "pending").length;
  const acceptedCount = requests.filter((r) => r.status === "accepted").length;
  const progressCount = requests.filter((r) => r.status === "in_progress").length;
  const completedCount = requests.filter((r) => r.status === "completed").length;

  if (loading) {
    return (
      <div className="service-page">
        <div className="service-loading">Loading service requests...</div>
      </div>
    );
  }

  return (
    <div className="service-page">
      <div className="service-header">
        <div>
          <p className="service-kicker">Live Operations</p>
          <h1>Service Requests</h1>
          <p>
            {currentHotel?.hotel_name || "Hotel"} · Realtime guest service operations board.
          </p>
        </div>

        <button onClick={() => fetchRequests(currentHotel?.id)}>Refresh</button>
      </div>

      <div className="service-stats">
        <Card title="Pending" value={pendingCount} icon="🟡" />
        <Card title="Accepted" value={acceptedCount} icon="🟠" />
        <Card title="In Progress" value={progressCount} icon="🔵" />
        <Card title="Completed" value={completedCount} icon="🟢" />
      </div>

      {requests.length === 0 ? (
        <div className="service-empty">
          <div>🛎️</div>
          <h3>No service requests yet</h3>
          <p>Guest requests will appear here instantly through Supabase Realtime.</p>
        </div>
      ) : (
        <div className="kanban-board">
          {columns.map((column) => (
            <div key={column.key} className="kanban-column">
              <div className="kanban-column-header">
                <h2>
                  <span>{column.icon}</span> {column.title}
                </h2>
                <span>{column.items.length}</span>
              </div>

              <div className="kanban-list">
                {column.items.length === 0 ? (
                  <div className="kanban-empty">No requests</div>
                ) : (
                  column.items.map((req) => (
                    <RequestCard
                      key={req.id}
                      req={req}
                      currentStaff={currentStaff}
                      onUpdate={updateRequest}
                      onCheckout={processCheckout}
                    />
                  ))
                )}
              </div>
            </div>
          ))}
        </div>
      )}
    </div>
  );
}

function RequestCard({ req, currentStaff, onUpdate, onCheckout }) {
  const isCheckout = req.request_type === "Checkout Request";

  return (
    <div className={`request-card ${req.status}`}>
      <div className="request-card-top">
        <span className="room-pill">Room {req.rooms?.room_number || "-"}</span>
        <span className={`priority-pill ${req.priority || "normal"}`}>
          {req.priority || "normal"}
        </span>
      </div>

      <h3>{req.request_type}</h3>

      <p className="request-guest">👤 {req.guests?.full_name || "Guest"}</p>

      <p className="request-notes">
        📝 {req.request_details || "No additional details"}
      </p>

      <div className="request-meta">
        <span>
          ⏰{" "}
          {req.created_at
            ? new Date(req.created_at).toLocaleTimeString("en-IN", {
                hour: "2-digit",
                minute: "2-digit",
              })
            : "-"}
        </span>

        <span>👷 {req.assigned_to ? "Assigned" : "Unassigned"}</span>
      </div>

      <div className="request-actions">
        {req.status === "pending" && !isCheckout && (
          <button onClick={() => onUpdate(req, "accepted")}>Accept</button>
        )}

        {req.status === "pending" && isCheckout && (
          <button onClick={() => onCheckout(req)}>Approve Checkout</button>
        )}

        {req.status === "accepted" && (
          <button onClick={() => onUpdate(req, "in_progress")}>Start</button>
        )}

        {req.status === "in_progress" && (
          <button onClick={() => onUpdate(req, "completed")}>Complete</button>
        )}

        {req.status === "completed" && (
          <span className="done-text">Completed</span>
        )}
      </div>

      {currentStaff?.full_name && req.status !== "pending" && (
        <div className="handled-by">Handled by {currentStaff.full_name}</div>
      )}
    </div>
  );
}

function Card({ title, value, icon }) {
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