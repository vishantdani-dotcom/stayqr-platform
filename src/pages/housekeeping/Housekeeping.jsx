import { useEffect, useState } from "react";
import { supabase } from "../../lib/supabase";
import { getCurrentHotel } from "../../lib/currentHotel";

export default function Housekeeping() {
  const [tasks, setTasks] = useState([]);
  const [loading, setLoading] = useState(true);
  const [currentHotel, setCurrentHotel] = useState(null);

  useEffect(() => {
    initPage();
  }, []);

  async function initPage() {
    const hotel = await getCurrentHotel();

    if (!hotel) {
      alert("No hotel assigned");
      return;
    }

    setCurrentHotel(hotel);
    fetchTasks(hotel.id);
  }

  async function fetchTasks(hotelId = currentHotel?.id) {
    if (!hotelId) return;

    setLoading(true);

    const { data, error } = await supabase
      .from("housekeeping_tasks")
      .select("*")
      .eq("hotel_id", hotelId)
      .order("created_at", { ascending: false });

    if (error) {
      alert(error.message);
      setLoading(false);
      return;
    }

    setTasks(data || []);
    setLoading(false);
  }

  async function markCompleted(task) {
    try {
      const { error: taskError } = await supabase
        .from("housekeeping_tasks")
        .update({ status: "completed" })
        .eq("id", task.id)
        .eq("hotel_id", currentHotel?.id);

      if (taskError) throw taskError;

      const { error: roomError } = await supabase
        .from("rooms")
        .update({ status: "available" })
        .eq("id", task.room_id)
        .eq("hotel_id", currentHotel?.id);

      if (roomError) throw roomError;

      alert("Room cleaned and marked available");

      fetchTasks(currentHotel?.id);
    } catch (err) {
      alert(err.message);
    }
  }

  const pending = tasks.filter((t) => t.status === "pending").length;
  const completed = tasks.filter((t) => t.status === "completed").length;

  if (loading) {
    return <div style={page}>Loading housekeeping tasks...</div>;
  }

  return (
    <div style={page}>
      <div style={header}>
        <div>
          <h1 style={title}>Housekeeping</h1>

          <p style={hotelName}>
            {currentHotel?.hotel_name || "Hotel"}
          </p>

          <p style={subtitle}>
            Manage cleaning tasks after guest checkout.
          </p>
        </div>

        <button
          style={refreshBtn}
          onClick={() => fetchTasks(currentHotel?.id)}
        >
          Refresh
        </button>
      </div>

      <div style={statsGrid}>
        <Card title="Pending Tasks" value={pending} />
        <Card title="Completed Tasks" value={completed} />
        <Card title="Total Tasks" value={tasks.length} />
      </div>

      <div style={tableCard}>
        {tasks.length === 0 ? (
          <p>No housekeeping tasks found.</p>
        ) : (
          <table style={table}>
            <thead>
              <tr>
                <th style={th}>Room</th>
                <th style={th}>Task</th>
                <th style={th}>Status</th>
                <th style={th}>Created</th>
                <th style={th}>Action</th>
              </tr>
            </thead>

            <tbody>
              {tasks.map((task) => (
                <tr key={task.id}>
                  <td style={td}>
                    Room {task.room_number || "-"}
                  </td>

                  <td style={td}>
                    {task.task_type || "room_cleaning"}
                  </td>

                  <td style={td}>
                    <span style={badge(task.status)}>
                      {task.status}
                    </span>
                  </td>

                  <td style={td}>
                    {task.created_at
                      ? new Date(task.created_at).toLocaleString("en-IN")
                      : "-"}
                  </td>

                  <td style={td}>
                    {task.status === "completed" ? (
                      <span
                        style={{
                          color: "#2ecc71",
                          fontWeight: 700,
                        }}
                      >
                        Done
                      </span>
                    ) : (
                      <button
                        style={btn}
                        onClick={() => markCompleted(task)}
                      >
                        Mark Complete
                      </button>
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
    <div style={statCard}>
      <div style={statTitle}>{title}</div>
      <div style={statValue}>{value}</div>
    </div>
  );
}

const page = {
  padding: "32px",
  color: "#fff",
};

const hotelName = {
  color: "#d4af37",
  marginBottom: "6px",
};

const header = {
  display: "flex",
  justifyContent: "space-between",
  alignItems: "center",
  marginBottom: "25px",
};

const title = {
  fontSize: "42px",
  marginBottom: "6px",
};

const subtitle = {
  color: "#aaa",
};

const refreshBtn = {
  background: "#d4af37",
  color: "#000",
  border: "none",
  borderRadius: "10px",
  padding: "12px 18px",
  fontWeight: 800,
  cursor: "pointer",
};

const statsGrid = {
  display: "grid",
  gridTemplateColumns: "repeat(auto-fit,minmax(200px,1fr))",
  gap: "18px",
  marginBottom: "25px",
};

const statCard = {
  background: "#0f0f0f",
  border: "1px solid #222",
  borderRadius: "16px",
  padding: "20px",
};

const statTitle = {
  color: "#d4af37",
  fontSize: "13px",
  marginBottom: "10px",
};

const statValue = {
  fontSize: "28px",
  fontWeight: "700",
};

const tableCard = {
  background: "#0f0f0f",
  border: "1px solid #222",
  borderRadius: "18px",
  overflowX: "auto",
  padding: "10px",
};

const table = {
  width: "100%",
  borderCollapse: "collapse",
  minWidth: "900px",
};

const th = {
  padding: "16px",
  textAlign: "left",
  color: "#d4af37",
  borderBottom: "1px solid #222",
};

const td = {
  padding: "16px",
  borderBottom: "1px solid #1f1f1f",
};

const btn = {
  background: "#d4af37",
  color: "#000",
  border: "none",
  padding: "9px 14px",
  borderRadius: "8px",
  fontWeight: 700,
  cursor: "pointer",
};

const badge = (status) => ({
  padding: "7px 12px",
  borderRadius: "999px",
  background:
    status === "completed"
      ? "rgba(46,204,113,.18)"
      : "rgba(255,170,0,.18)",
  color: status === "completed" ? "#2ecc71" : "#ffaa00",
  fontWeight: 700,
  textTransform: "capitalize",
});