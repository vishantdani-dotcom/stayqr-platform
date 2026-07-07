import { useEffect, useMemo, useState } from "react";
import { createNotification } from "../../lib/notifications";
import {
  DndContext,
  PointerSensor,
  useDraggable,
  useDroppable,
  useSensor,
  useSensors,
} from "@dnd-kit/core";
import { CSS } from "@dnd-kit/utilities";
import { supabase } from "../../lib/supabase";
import { getCurrentHotel } from "../../lib/currentHotel";
import { getCurrentStaff } from "../../lib/currentStaff";
import "./ServiceRequests.css";

export default function ServiceRequests() {
  const [requests, setRequests] = useState([]);
  const [staffList, setStaffList] = useState([]);
  const [loading, setLoading] = useState(true);
  const [currentHotel, setCurrentHotel] = useState(null);
  const [currentStaff, setCurrentStaff] = useState(null);

  const sensors = useSensors(useSensor(PointerSensor, { activationConstraint: { distance: 8 } }));

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

    await Promise.all([fetchRequests(hotel.id), fetchActiveStaff(hotel.id)]);
    setLoading(false);
  }

  async function fetchActiveStaff(hotelId) {
    const { data, error } = await supabase
      .from("staff")
      .select("id, full_name, role, status")
      .eq("hotel_id", hotelId)
      .eq("status", "active")
      .order("full_name", { ascending: true });

    if (error) {
      alert(error.message);
      return;
    }

    setStaffList(data || []);
  }

  async function fetchRequests(hotelId = currentHotel?.id) {
    if (!hotelId) return;

    const { data, error } = await supabase
      .from("service_requests")
      .select(`
        *,
        guests (full_name, phone),
        rooms (room_number, room_type)
      `)
      .eq("hotel_id", hotelId)
      .order("created_at", { ascending: false });

    if (error) {
      alert(error.message);
      return;
    }

    setRequests(data || []);
  }

  function getStaffName(staffId) {
    const staff = staffList.find((s) => s.id === staffId);
    return staff?.full_name || "Unassigned";
  }

  async function assignStaff(request, staffId) {
    const { error } = await supabase
      .from("service_requests")
      .update({ assigned_to: staffId || null })
      .eq("id", request.id)
      .eq("hotel_id", currentHotel?.id);

    if (error) {
      alert(error.message);
      return;
    }

    fetchRequests(currentHotel?.id);
  }

  async function updatePriority(request, priority) {
    const { error } = await supabase
      .from("service_requests")
      .update({ priority })
      .eq("id", request.id)
      .eq("hotel_id", currentHotel?.id);

    if (error) {
      alert(error.message);
      return;
    }

    fetchRequests(currentHotel?.id);
  }

  async function updateRequest(request, status) {
    const payload = { status };

    if (status === "accepted") {
      payload.accepted_at = new Date().toISOString();
      if (!request.assigned_to && currentStaff?.id) payload.assigned_to = currentStaff.id;
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

await createNotification({
  hotelId: currentHotel.id,
  roomId: request.room_id,
  guestId: request.guest_id,
  type: "service_status",
  title: `Room ${request.rooms?.room_number}`,
  message: `${request.request_type} marked ${status}`,
});

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

      await createNotification({
  hotelId: currentHotel.id,
  roomId: request.room_id,
  guestId: request.guest_id,
  type: "checkout",
  title: `Room ${request.rooms?.room_number}`,
  message: "Guest checkout completed",
});

alert("Guest checked out successfully. Housekeeping task created.");

fetchRequests(currentHotel?.id);
    } catch (err) {
      alert(err.message);
    }
  }

  async function handleDragEnd(event) {
    const { active, over } = event;
    if (!over) return;

    const request = requests.find((r) => String(r.id) === String(active.id));
    const newStatus = over.id;

    if (!request || request.status === newStatus) return;

    if (request.request_type === "Checkout Request") {
      alert("Checkout requests must be approved using the checkout button.");
      return;
    }

    await updateRequest(request, newStatus);
  }

  const sortedRequests = useMemo(() => {
    const priorityRank = { urgent: 1, high: 2, normal: 3, low: 4 };

    return [...requests].sort((a, b) => {
      const rankA = priorityRank[a.priority || "normal"] || 3;
      const rankB = priorityRank[b.priority || "normal"] || 3;
      if (rankA !== rankB) return rankA - rankB;
      return new Date(b.created_at || 0) - new Date(a.created_at || 0);
    });
  }, [requests]);

  const columns = useMemo(
    () => [
      { key: "pending", title: "Pending", icon: "🟡", items: sortedRequests.filter((r) => r.status === "pending") },
      { key: "accepted", title: "Accepted", icon: "🟠", items: sortedRequests.filter((r) => r.status === "accepted") },
      { key: "in_progress", title: "In Progress", icon: "🔵", items: sortedRequests.filter((r) => r.status === "in_progress") },
      { key: "completed", title: "Completed", icon: "🟢", items: sortedRequests.filter((r) => r.status === "completed") },
    ],
    [sortedRequests]
  );

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
          <p>{currentHotel?.hotel_name || "Hotel"} · Drag requests across the live operations board.</p>
        </div>

        <button onClick={() => fetchRequests(currentHotel?.id)}>Refresh</button>
      </div>

      <div className="service-stats">
        <Card title="Pending" value={columns[0].items.length} icon="🟡" />
        <Card title="Accepted" value={columns[1].items.length} icon="🟠" />
        <Card title="In Progress" value={columns[2].items.length} icon="🔵" />
        <Card title="Completed" value={columns[3].items.length} icon="🟢" />
      </div>

      {requests.length === 0 ? (
        <div className="service-empty">
          <div>🛎️</div>
          <h3>No service requests yet</h3>
          <p>Guest requests will appear here instantly through Supabase Realtime.</p>
        </div>
      ) : (
        <DndContext sensors={sensors} onDragEnd={handleDragEnd}>
          <div className="kanban-board">
            {columns.map((column) => (
              <DroppableColumn key={column.key} column={column}>
                {column.items.length === 0 ? (
                  <div className="kanban-empty">Drop requests here</div>
                ) : (
                  column.items.map((req) => (
                    <DraggableRequestCard key={req.id} id={req.id}>
  {(dragProps) => (
    <RequestCard
      req={req}
      staffList={staffList}
      assignedName={getStaffName(req.assigned_to)}
      onAssign={assignStaff}
      onPriorityChange={updatePriority}
      onUpdate={updateRequest}
      onCheckout={processCheckout}
      {...dragProps}
    />
  )}
</DraggableRequestCard>
                  ))
                )}
              </DroppableColumn>
            ))}
          </div>
        </DndContext>
      )}
    </div>
  );
}

function DroppableColumn({ column, children }) {
  const { setNodeRef, isOver } = useDroppable({ id: column.key });

  return (
    <div ref={setNodeRef} className={`kanban-column ${isOver ? "drag-over" : ""}`}>
      <div className="kanban-column-header">
        <h2>
          <span>{column.icon}</span> {column.title}
        </h2>
        <span>{column.items.length}</span>
      </div>

      <div className="kanban-list">{children}</div>
    </div>
  );
}

function DraggableRequestCard({ id, children }) {
  const { attributes, listeners, setNodeRef, transform, isDragging } = useDraggable({
    id: String(id),
  });

  const style = {
    transform: CSS.Translate.toString(transform),
  };

  return (
    <div
      ref={setNodeRef}
      style={style}
      className={isDragging ? "dragging-card" : ""}
    >
      {children({ dragAttributes: attributes, dragListeners: listeners })}
    </div>
  );
}

function RequestCard({
  req,
  staffList,
  assignedName,
  onAssign,
  onPriorityChange,
  onUpdate,
  onCheckout,
  dragAttributes,
  dragListeners,
}) {
  const isCheckout = req.request_type === "Checkout Request";

  return (
    <div className={`request-card ${req.status}`}>
      <div className="request-drag-handle" {...dragAttributes} {...dragListeners}>
        ⋮⋮ Drag
      </div>

      <div className="request-card-top">
        <span className="room-pill">Room {req.rooms?.room_number || "-"}</span>
        <span className={`priority-pill ${req.priority || "normal"}`}>
          {req.priority || "normal"}
        </span>
      </div>

      <h3>{req.request_type}</h3>

      <p className="request-guest">👤 {req.guests?.full_name || "Guest"}</p>

      <p className="request-notes">📝 {req.request_details || "No additional details"}</p>

      <div className="request-priority-control">
        <label>🚦 Priority</label>
        <select
          value={req.priority || "normal"}
          onChange={(e) => onPriorityChange(req, e.target.value)}
          disabled={req.status === "completed"}
        >
          <option value="low">Low</option>
          <option value="normal">Normal</option>
          <option value="high">High</option>
          <option value="urgent">Urgent</option>
        </select>
      </div>

      <div className="request-assign">
        <label>👷 Assigned To</label>
        <select
          value={req.assigned_to || ""}
          onChange={(e) => onAssign(req, e.target.value)}
          disabled={req.status === "completed"}
        >
          <option value="">Unassigned</option>
          {staffList.map((staff) => (
            <option key={staff.id} value={staff.id}>
              {staff.full_name} · {staff.role}
            </option>
          ))}
        </select>
      </div>

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
        <span>👷 {assignedName}</span>
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

        {req.status === "completed" && <span className="done-text">Completed</span>}
      </div>
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