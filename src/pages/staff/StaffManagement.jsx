import { useEffect, useState } from "react";
import { supabase } from "../../lib/supabase";
import { getCurrentHotel } from "../../lib/currentHotel";

export default function StaffManagement() {
  const [currentHotel, setCurrentHotel] = useState(null);
  const [staff, setStaff] = useState([]);
  const [roles, setRoles] = useState([]);
  const [loading, setLoading] = useState(true);

  const [fullName, setFullName] = useState("");
  const [email, setEmail] = useState("");
  const [phone, setPhone] = useState("");
  const [role, setRole] = useState("");

  useEffect(() => {
    initPage();
  }, []);

  async function initPage() {
    setLoading(true);

    const hotel = await getCurrentHotel();

    if (!hotel) {
      alert("No hotel assigned");
      setLoading(false);
      return;
    }

    setCurrentHotel(hotel);

    await fetchRoles();
    await fetchStaff(hotel.id);

    setLoading(false);
  }

  async function fetchRoles() {
    const { data, error } = await supabase
      .from("staff_roles")
      .select("id, role_name, description")
      .order("role_name", { ascending: true });

    if (error) {
      console.error("Roles fetch error:", error);
      alert("Roles fetch error: " + error.message);
      setRoles([]);
      return;
    }

    setRoles(data || []);
  }

  async function fetchStaff(hotelId) {
    if (!hotelId) return;

    const { data, error } = await supabase
      .from("staff")
      .select("*")
      .eq("hotel_id", hotelId)
      .order("created_at", { ascending: false });

    if (error) {
      console.error("Staff fetch error:", error);
      alert("Staff fetch error: " + error.message);
      return;
    }

    setStaff(data || []);
  }

  async function addStaff() {
    if (!currentHotel?.id) {
      alert("No hotel assigned");
      return;
    }

    if (!fullName || !email || !role) {
      alert("Please enter name, email and role");
      return;
    }

    const { error } = await supabase.from("staff").insert([
      {
        hotel_id: currentHotel.id,
        full_name: fullName,
        email,
        phone,
        role,
        status: "active",
      },
    ]);

    if (error) {
      alert(error.message);
      return;
    }

    alert("Staff added successfully");

    setFullName("");
    setEmail("");
    setPhone("");
    setRole("");

    fetchStaff(currentHotel.id);
  }

  async function updateStatus(member, status) {
    const { error } = await supabase
      .from("staff")
      .update({ status })
      .eq("id", member.id)
      .eq("hotel_id", currentHotel?.id);

    if (error) {
      alert(error.message);
      return;
    }

    fetchStaff(currentHotel?.id);
  }

  async function deleteStaff(member) {
    const confirmDelete = window.confirm(`Delete ${member.full_name}?`);
    if (!confirmDelete) return;

    const { error } = await supabase
      .from("staff")
      .delete()
      .eq("id", member.id)
      .eq("hotel_id", currentHotel?.id);

    if (error) {
      alert(error.message);
      return;
    }

    fetchStaff(currentHotel?.id);
  }

  if (loading) {
    return <div style={page}>Loading staff...</div>;
  }

  return (
    <div style={page}>
      <div style={header}>
        <div>
          <h1 style={title}>Staff Management</h1>
          <p style={subtitle}>
            {currentHotel?.hotel_name || "Hotel"} · Manage hotel staff and roles.
          </p>
        </div>

        <button style={refreshBtn} onClick={initPage}>
          Refresh
        </button>
      </div>

      <div style={statsGrid}>
        <Card title="Total Staff" value={staff.length} />
        <Card
          title="Active Staff"
          value={staff.filter((s) => s.status === "active").length}
        />
        <Card
          title="Disabled Staff"
          value={staff.filter((s) => s.status !== "active").length}
        />
        <Card title="Roles Loaded" value={roles.length} />
      </div>

      <div style={formCard}>
        <h2 style={sectionTitle}>Add Staff Member</h2>

        <input
          style={input}
          placeholder="Full Name"
          value={fullName}
          onChange={(e) => setFullName(e.target.value)}
        />

        <input
          style={input}
          placeholder="Email"
          value={email}
          onChange={(e) => setEmail(e.target.value)}
        />

        <input
          style={input}
          placeholder="Phone"
          value={phone}
          onChange={(e) => setPhone(e.target.value)}
        />

        <select
          style={input}
          value={role}
          onChange={(e) => setRole(e.target.value)}
        >
          <option value="">Select Role</option>

          {roles.map((r) => (
            <option key={r.id} value={r.role_name}>
              {r.role_name}
            </option>
          ))}
        </select>

        <button style={primaryBtn} onClick={addStaff}>
          Add Staff
        </button>
      </div>

      <div style={tableCard}>
        {staff.length === 0 ? (
          <p>No staff found.</p>
        ) : (
          <table style={table}>
            <thead>
              <tr>
                <th style={th}>Name</th>
                <th style={th}>Email</th>
                <th style={th}>Phone</th>
                <th style={th}>Role</th>
                <th style={th}>Status</th>
                <th style={th}>Created</th>
                <th style={th}>Actions</th>
              </tr>
            </thead>

            <tbody>
              {staff.map((member) => (
                <tr key={member.id}>
                  <td style={td}>{member.full_name}</td>
                  <td style={td}>{member.email}</td>
                  <td style={td}>{member.phone || "-"}</td>
                  <td style={td}>{member.role}</td>
                  <td style={td}>
                    <span style={badge(member.status)}>
                      {member.status || "active"}
                    </span>
                  </td>
                  <td style={td}>
                    {member.created_at
                      ? new Date(member.created_at).toLocaleString("en-IN")
                      : "-"}
                  </td>
                  <td style={td}>
                    {member.status === "active" ? (
                      <button
                        style={smallBtn}
                        onClick={() => updateStatus(member, "disabled")}
                      >
                        Disable
                      </button>
                    ) : (
                      <button
                        style={smallBtn}
                        onClick={() => updateStatus(member, "active")}
                      >
                        Enable
                      </button>
                    )}

                    <button style={deleteBtn} onClick={() => deleteStaff(member)}>
                      Delete
                    </button>
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

const page = { padding: "32px", color: "#fff" };

const header = {
  display: "flex",
  justifyContent: "space-between",
  alignItems: "center",
  gap: "20px",
  marginBottom: "25px",
};

const title = { fontSize: "42px", marginBottom: "6px" };
const subtitle = { color: "#aaa" };

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

const statTitle = { color: "#d4af37", fontSize: "13px", marginBottom: "10px" };
const statValue = { fontSize: "28px", fontWeight: "700" };

const formCard = {
  background: "#0f0f0f",
  border: "1px solid #222",
  borderRadius: "18px",
  padding: "24px",
  marginBottom: "25px",
};

const sectionTitle = { color: "#d4af37", marginBottom: "18px" };

const input = {
  width: "100%",
  padding: "13px",
  marginBottom: "14px",
  borderRadius: "10px",
  border: "1px solid #333",
  background: "#111",
  color: "#fff",
};

const primaryBtn = {
  background: "#d4af37",
  color: "#000",
  border: "none",
  borderRadius: "10px",
  padding: "12px 18px",
  fontWeight: 800,
  cursor: "pointer",
};

const tableCard = {
  background: "#0f0f0f",
  border: "1px solid #222",
  borderRadius: "18px",
  padding: "20px",
  overflowX: "auto",
};

const table = { width: "100%", borderCollapse: "collapse", minWidth: "1000px" };

const th = {
  color: "#d4af37",
  textAlign: "left",
  padding: "14px",
  borderBottom: "1px solid #222",
};

const td = {
  padding: "14px",
  borderBottom: "1px solid #1f1f1f",
};

const smallBtn = {
  background: "#d4af37",
  color: "#000",
  border: "none",
  borderRadius: "8px",
  padding: "8px 12px",
  marginRight: "8px",
  fontWeight: 700,
  cursor: "pointer",
};

const deleteBtn = {
  background: "#ff4d4d",
  color: "#fff",
  border: "none",
  borderRadius: "8px",
  padding: "8px 12px",
  fontWeight: 700,
  cursor: "pointer",
};

const badge = (status) => ({
  padding: "7px 12px",
  borderRadius: "999px",
  background:
    status === "active"
      ? "rgba(46,204,113,.18)"
      : "rgba(255,77,77,.18)",
  color: status === "active" ? "#2ecc71" : "#ff4d4d",
  fontWeight: 700,
  textTransform: "capitalize",
});