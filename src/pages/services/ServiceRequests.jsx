import { useEffect, useState } from "react";
import { supabase } from "../../lib/supabase";
import { getCurrentHotel } from "../../lib/currentHotel";
import "./ServiceRequests.css";

export default function ServiceRequests() {
  const [requests, setRequests] = useState([]);
  const [loading, setLoading] = useState(true);
  const [currentHotel, setCurrentHotel] = useState(null);

  useEffect(() => {
    initPage();
  }, []);

  useEffect(() => {
    if (!currentHotel?.id) return;

    const interval = setInterval(() => {
      fetchRequests(currentHotel.id);
    }, 3000);

    return () => clearInterval(interval);
  }, [currentHotel?.id]);

  async function initPage() {
    const hotel = await getCurrentHotel();

    if (!hotel) {
      alert("No hotel assigned");
      setLoading(false);
      return;
    }

    setCurrentHotel(hotel);
    fetchRequests(hotel.id);
  }

  const fetchRequests = async (hotelId = currentHotel?.id) => {
    if (!hotelId) return;

    setLoading(true);

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
      setLoading(false);
      return;
    }

    setRequests(data || []);
    setLoading(false);
  };

  async function updateStatus(id, status) {
    const { error } = await supabase
      .from("service_requests")
      .update({ status })
      .eq("id", id)
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
        .update({ status: "completed" })
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

  const pendingCount = requests.filter((r) => r.status === "pending").length;
  const progressCount = requests.filter((r) => r.status === "in_progress").length;
  const completedCount = requests.filter((r) => r.status === "completed").length;
  const totalCount = requests.length;

  return (
    <div className="service-page">
      <div className="service-header">
        <div>
          <h1>Service Requests</h1>
          <p>
            {currentHotel?.hotel_name || "Hotel"} · Manage guest requests from QR digital guide.
          </p>
        </div>

        <button onClick={() => fetchRequests(currentHotel?.id)}>Refresh</button>
      </div>

      <div
        style={{
          display: "grid",
          gridTemplateColumns: "repeat(auto-fit,minmax(220px,1fr))",
          gap: "20px",
          marginBottom: "25px",
        }}
      >
        <Card title="Pending Requests" value={pendingCount} />
        <Card title="In Progress" value={progressCount} />
        <Card title="Completed" value={completedCount} />
        <Card title="Total Requests" value={totalCount} />
      </div>

      <div className="service-card">
        {loading ? (
          <p>Loading requests...</p>
        ) : requests.length === 0 ? (
          <p>No service requests found.</p>
        ) : (
          <table className="service-table">
            <thead>
              <tr>
                <th>Room</th>
                <th>Guest</th>
                <th>Request</th>
                <th>Details</th>
                <th>Status</th>
                <th>Time</th>
                <th>Actions</th>
              </tr>
            </thead>

            <tbody>
              {requests.map((req) => (
                <tr key={req.id}>
                  <td>Room {req.rooms?.room_number || "-"}</td>
                  <td>{req.guests?.full_name || "-"}</td>
                  <td>{req.request_type}</td>
                  <td>{req.request_details || "-"}</td>

                  <td>
                    <span className={`request-status ${req.status}`}>
                      {req.status}
                    </span>
                  </td>

                  <td>
                    {req.created_at
                      ? new Date(req.created_at).toLocaleString("en-IN")
                      : "-"}
                  </td>

                  <td>
                    {req.status === "pending" &&
                      req.request_type !== "Checkout Request" && (
                        <button
                          className="complete-btn"
                          onClick={() => updateStatus(req.id, "in_progress")}
                        >
                          Start
                        </button>
                      )}

                    {req.status === "pending" &&
                      req.request_type === "Checkout Request" && (
                        <button
                          className="complete-btn"
                          onClick={() => processCheckout(req)}
                        >
                          Approve Checkout
                        </button>
                      )}

                    {req.status === "in_progress" && (
                      <button
                        className="complete-btn"
                        onClick={() => updateStatus(req.id, "completed")}
                      >
                        Complete
                      </button>
                    )}

                    {req.status === "completed" && (
                      <span className="done-text">Done</span>
                    )}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        )}
      </div>
    </div>
  );
}

function Card({ title, value }) {
  return (
    <div
      style={{
        background: "#0f0f0f",
        border: "1px solid #222",
        borderRadius: "18px",
        padding: "24px",
        textAlign: "center",
      }}
    >
      <div
        style={{
          color: "#d4af37",
          fontSize: "13px",
          marginBottom: "10px",
        }}
      >
        {title}
      </div>

      <div
        style={{
          fontSize: "36px",
          fontWeight: "700",
          color: "#fff",
        }}
      >
        {value}
      </div>
    </div>
  );
}