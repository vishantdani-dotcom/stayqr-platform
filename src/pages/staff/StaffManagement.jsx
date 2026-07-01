import { useEffect, useMemo, useState } from "react";
import { supabase } from "../../lib/supabase";
import { getCurrentHotel } from "../../lib/currentHotel";
import { getCurrentStaff, normalizeRole } from "../../lib/currentStaff";
import "./StaffManagement.css";

const emptyForm = {
  full_name: "",
  email: "",
  phone: "",
  role: "",
  status: "active",
};

export default function StaffManagement() {
  const [currentHotel, setCurrentHotel] = useState(null);
  const [currentStaff, setCurrentStaff] = useState(null);
  const [staff, setStaff] = useState([]);
  const [roles, setRoles] = useState([]);
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);

  const [search, setSearch] = useState("");
  const [roleFilter, setRoleFilter] = useState("all");
  const [statusFilter, setStatusFilter] = useState("all");
  const [page, setPage] = useState(1);

  const [modalOpen, setModalOpen] = useState(false);
  const [editingStaff, setEditingStaff] = useState(null);
  const [form, setForm] = useState(emptyForm);

  const pageSize = 8;

  useEffect(() => {
    initPage();
  }, []);

  async function initPage() {
    setLoading(true);

    const [hotel, loggedStaff] = await Promise.all([
      getCurrentHotel(),
      getCurrentStaff(),
    ]);

    if (!hotel) {
      alert("No hotel assigned");
      setLoading(false);
      return;
    }

    setCurrentHotel(hotel);
    setCurrentStaff(loggedStaff);

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
      alert("Roles fetch error: " + error.message);
      setRoles([]);
      return;
    }

    setRoles(data || []);
  }

  async function fetchStaff(hotelId) {
    const { data, error } = await supabase
      .from("staff")
      .select("*")
      .eq("hotel_id", hotelId)
      .order("created_at", { ascending: false });

    if (error) {
      alert("Staff fetch error: " + error.message);
      return;
    }

    setStaff(data || []);
  }

  const currentRole = normalizeRole(currentStaff?.role || "manager");

  const canManageStaff = ["owner", "manager", "super_admin"].includes(
    currentRole
  );

  const filteredStaff = useMemo(() => {
    return staff.filter((member) => {
      const query = search.trim().toLowerCase();

      const matchesSearch =
        !query ||
        member.full_name?.toLowerCase().includes(query) ||
        member.email?.toLowerCase().includes(query) ||
        member.phone?.toLowerCase().includes(query);

      const matchesRole =
        roleFilter === "all" ||
        normalizeRole(member.role) === normalizeRole(roleFilter);

      const matchesStatus =
        statusFilter === "all" || member.status === statusFilter;

      return matchesSearch && matchesRole && matchesStatus;
    });
  }, [staff, search, roleFilter, statusFilter]);

  const totalPages = Math.max(1, Math.ceil(filteredStaff.length / pageSize));

  const paginatedStaff = filteredStaff.slice(
    (page - 1) * pageSize,
    page * pageSize
  );

  const stats = {
    total: staff.length,
    active: staff.filter((s) => s.status === "active").length,
    disabled: staff.filter((s) => s.status === "disabled").length,
    archived: staff.filter((s) => s.status === "archived").length,
  };

  function openAddModal() {
    if (!canManageStaff) {
      alert("Only Manager or Owner can add staff.");
      return;
    }

    setEditingStaff(null);
    setForm(emptyForm);
    setModalOpen(true);
  }

  function openEditModal(member) {
    if (!canManageStaff) {
      alert("Only Manager or Owner can edit staff.");
      return;
    }

    setEditingStaff(member);
    setForm({
      full_name: member.full_name || "",
      email: member.email || "",
      phone: member.phone || "",
      role: member.role || "",
      status: member.status || "active",
    });
    setModalOpen(true);
  }

  function closeModal() {
    setModalOpen(false);
    setEditingStaff(null);
    setForm(emptyForm);
  }

  function handleFormChange(e) {
    const { name, value } = e.target;
    setForm((prev) => ({ ...prev, [name]: value }));
  }

  async function saveStaff() {
    if (!canManageStaff) {
      alert("You do not have permission to manage staff.");
      return;
    }

    if (!currentHotel?.id) {
      alert("No hotel assigned");
      return;
    }

    if (!form.full_name.trim() || !form.email.trim() || !form.role) {
      alert("Please enter name, email and role.");
      return;
    }

    setSaving(true);

    const payload = {
      hotel_id: currentHotel.id,
      full_name: form.full_name.trim(),
      email: form.email.trim().toLowerCase(),
      phone: form.phone.trim(),
      role: form.role,
      status: form.status || "active",
    };

    let error;

    if (editingStaff?.id) {
      const result = await supabase
        .from("staff")
        .update(payload)
        .eq("id", editingStaff.id)
        .eq("hotel_id", currentHotel.id);

      error = result.error;
    } else {
      const result = await supabase.from("staff").insert([payload]);
      error = result.error;
    }

    setSaving(false);

    if (error) {
      alert(error.message);
      return;
    }

    await fetchStaff(currentHotel.id);
    closeModal();

    alert(editingStaff ? "Staff updated successfully" : "Staff added successfully");
  }

  async function updateStatus(member, status) {
    if (!canManageStaff) {
      alert("Only Manager or Owner can change staff status.");
      return;
    }

    const label =
      status === "archived"
        ? "archive"
        : status === "disabled"
        ? "disable"
        : "activate";

    const confirmAction = window.confirm(
      `Are you sure you want to ${label} ${member.full_name}?`
    );

    if (!confirmAction) return;

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

  function resetFilters() {
    setSearch("");
    setRoleFilter("all");
    setStatusFilter("all");
    setPage(1);
  }

  if (loading) {
    return (
      <div className="staff-page">
        <div className="staff-loading-card">
          <div className="staff-loader" />
          <p>Loading staff management...</p>
        </div>
      </div>
    );
  }

  return (
    <div className="staff-page">
      <div className="staff-header">
        <div>
          <p className="staff-kicker">Team & Access Control</p>
          <h1>Staff Management</h1>
          <p>
            {currentHotel?.hotel_name || "Hotel"} · Manage staff, roles and access.
          </p>
        </div>

        <div className="staff-header-actions">
          <button className="staff-secondary-btn" onClick={initPage}>
            Refresh
          </button>

          <button
            className="staff-primary-btn"
            onClick={openAddModal}
            disabled={!canManageStaff}
            title={!canManageStaff ? "Only Manager or Owner can add staff" : ""}
          >
            + Add Staff
          </button>
        </div>
      </div>

      <div className="staff-stats-grid">
        <StatCard label="Total Staff" value={stats.total} icon="👥" />
        <StatCard label="Active Staff" value={stats.active} icon="✅" />
        <StatCard label="Disabled" value={stats.disabled} icon="⛔" />
        <StatCard label="Archived" value={stats.archived} icon="🗄️" />
      </div>

      <div className="staff-control-card">
        <div className="staff-search-box">
          <span>🔍</span>
          <input
            placeholder="Search by name, email or phone..."
            value={search}
            onChange={(e) => {
              setSearch(e.target.value);
              setPage(1);
            }}
          />
        </div>

        <select
          value={roleFilter}
          onChange={(e) => {
            setRoleFilter(e.target.value);
            setPage(1);
          }}
        >
          <option value="all">All Roles</option>
          {roles.map((r) => (
            <option key={r.id} value={r.role_name}>
              {r.role_name}
            </option>
          ))}
        </select>

        <select
          value={statusFilter}
          onChange={(e) => {
            setStatusFilter(e.target.value);
            setPage(1);
          }}
        >
          <option value="all">All Status</option>
          <option value="active">Active</option>
          <option value="disabled">Disabled</option>
          <option value="archived">Archived</option>
        </select>

        <button onClick={resetFilters}>Reset</button>
      </div>

      <div className="staff-table-card">
        <div className="staff-table-top">
          <div>
            <h2>Hotel Staff</h2>
            <p>
              Showing {paginatedStaff.length} of {filteredStaff.length} staff
            </p>
          </div>

          <span className="staff-permission-pill">
            {canManageStaff ? "Manager Access" : "View Only"}
          </span>
        </div>

        {filteredStaff.length === 0 ? (
          <div className="staff-empty">
            <div>👤</div>
            <h3>No staff found</h3>
            <p>Try changing filters or add a new staff member.</p>
          </div>
        ) : (
          <div className="staff-table-wrap">
            <table className="staff-table">
              <thead>
                <tr>
                  <th>Name</th>
                  <th>Email</th>
                  <th>Phone</th>
                  <th>Role</th>
                  <th>Status</th>
                  <th>Created</th>
                  <th>Actions</th>
                </tr>
              </thead>

              <tbody>
                {paginatedStaff.map((member) => (
                  <tr key={member.id}>
                    <td>
                      <div className="staff-person">
                        <div className="staff-avatar">
                          {(member.full_name || "S").charAt(0).toUpperCase()}
                        </div>
                        <div>
                          <strong>{member.full_name}</strong>
                          {member.auth_user_id && <span>Auth linked</span>}
                        </div>
                      </div>
                    </td>

                    <td>{member.email || "-"}</td>
                    <td>{member.phone || "-"}</td>

                    <td>
                      <span className="staff-role-badge">
                        {member.role || "-"}
                      </span>
                    </td>

                    <td>
                      <span className={`staff-status ${member.status || "active"}`}>
                        {member.status || "active"}
                      </span>
                    </td>

                    <td>
                      {member.created_at
                        ? new Date(member.created_at).toLocaleDateString("en-IN")
                        : "-"}
                    </td>

                    <td>
                      <div className="staff-actions">
                        <button
                          onClick={() => openEditModal(member)}
                          disabled={!canManageStaff}
                        >
                          Edit
                        </button>

                        {member.status === "active" ? (
                          <button
                            onClick={() => updateStatus(member, "disabled")}
                            disabled={!canManageStaff}
                          >
                            Disable
                          </button>
                        ) : (
                          <button
                            onClick={() => updateStatus(member, "active")}
                            disabled={!canManageStaff}
                          >
                            Enable
                          </button>
                        )}

                        <button
                          className="danger"
                          onClick={() => updateStatus(member, "archived")}
                          disabled={!canManageStaff}
                        >
                          Archive
                        </button>
                      </div>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}

        {filteredStaff.length > pageSize && (
          <div className="staff-pagination">
            <button disabled={page === 1} onClick={() => setPage(page - 1)}>
              Previous
            </button>

            <span>
              Page {page} of {totalPages}
            </span>

            <button
              disabled={page === totalPages}
              onClick={() => setPage(page + 1)}
            >
              Next
            </button>
          </div>
        )}
      </div>

      {modalOpen && (
        <div className="staff-modal-backdrop">
          <div className="staff-modal">
            <div className="staff-modal-header">
              <div>
                <p className="staff-kicker">
                  {editingStaff ? "Edit Staff" : "New Staff"}
                </p>
                <h2>{editingStaff ? "Update Staff Member" : "Add Staff Member"}</h2>
              </div>

              <button className="staff-close-btn" onClick={closeModal}>
                ×
              </button>
            </div>

            <div className="staff-form-grid">
              <label>
                Full Name
                <input
                  name="full_name"
                  value={form.full_name}
                  onChange={handleFormChange}
                  placeholder="Enter full name"
                />
              </label>

              <label>
                Email
                <input
                  name="email"
                  value={form.email}
                  onChange={handleFormChange}
                  placeholder="Enter email"
                  type="email"
                />
              </label>

              <label>
                Phone
                <input
                  name="phone"
                  value={form.phone}
                  onChange={handleFormChange}
                  placeholder="Enter phone number"
                />
              </label>

              <label>
                Role
                <select name="role" value={form.role} onChange={handleFormChange}>
                  <option value="">Select Role</option>
                  {roles.map((r) => (
                    <option key={r.id} value={r.role_name}>
                      {r.role_name}
                    </option>
                  ))}
                </select>
              </label>

              <label>
                Status
                <select
                  name="status"
                  value={form.status}
                  onChange={handleFormChange}
                >
                  <option value="active">Active</option>
                  <option value="disabled">Disabled</option>
                  <option value="archived">Archived</option>
                </select>
              </label>
            </div>

            {!editingStaff && (
              <div className="staff-note">
                Invite email / password setup will be added in the next phase.
                For now, this creates the staff record.
              </div>
            )}

            <div className="staff-modal-actions">
              <button className="staff-secondary-btn" onClick={closeModal}>
                Cancel
              </button>

              <button
                className="staff-primary-btn"
                onClick={saveStaff}
                disabled={saving}
              >
                {saving ? "Saving..." : editingStaff ? "Save Changes" : "Add Staff"}
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}

function StatCard({ label, value, icon }) {
  return (
    <div className="staff-stat-card">
      <div className="staff-stat-icon">{icon}</div>
      <div>
        <p>{label}</p>
        <h3>{value}</h3>
      </div>
    </div>
  );
}