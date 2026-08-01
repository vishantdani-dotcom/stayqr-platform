import { useEffect, useMemo, useState } from 'react'
import { supabase } from '../../lib/supabase'
import { getCurrentHotel } from '../../lib/currentHotel'
import {
  canManageStaff as roleCanManageStaff,
  formatRole,
  getCurrentStaff,
  normalizeRole,
} from '../../lib/currentStaff'
import './StaffManagement.css'

const emptyForm = {
  full_name: '',
  email: '',
  phone: '',
  role: 'reception',
}

const managedStatuses = ['active', 'invited', 'inactive', 'suspended']

export default function StaffManagement() {
  const [currentHotel, setCurrentHotel] = useState(null)
  const [currentStaff, setCurrentStaff] = useState(null)
  const [staff, setStaff] = useState([])
  const [roles, setRoles] = useState([])
  const [loading, setLoading] = useState(true)
  const [saving, setSaving] = useState(false)
  const [actionMessage, setActionMessage] = useState('')
  const [actionError, setActionError] = useState('')

  const [search, setSearch] = useState('')
  const [roleFilter, setRoleFilter] = useState('all')
  const [statusFilter, setStatusFilter] = useState('all')
  const [page, setPage] = useState(1)

  const [modalOpen, setModalOpen] = useState(false)
  const [editingStaff, setEditingStaff] = useState(null)
  const [form, setForm] = useState(emptyForm)

  const pageSize = 8

  useEffect(() => {
    initPage()
  }, [])

  async function initPage() {
    setLoading(true)
    setActionError('')

    const [hotel, loggedStaff] = await Promise.all([
      getCurrentHotel(),
      getCurrentStaff(),
    ])

    if (!hotel) {
      setActionError('No active hotel is assigned to this login.')
      setLoading(false)
      return
    }

    setCurrentHotel(hotel)
    setCurrentStaff(loggedStaff)

    await Promise.all([fetchRoles(), fetchStaff(hotel.id)])
    setLoading(false)
  }

  async function fetchRoles() {
    const { data, error } = await supabase
      .from('staff_roles')
      .select('id, role_name, description')
      .order('role_name', { ascending: true })

    if (error) {
      setActionError(`Roles could not be loaded: ${error.message}`)
      setRoles([])
      return
    }

    const allowed = new Set([
      'owner',
      'manager',
      'reception',
      'housekeeping',
      'restaurant',
      'accounts',
    ])
    const uniqueRoles = new Map()

    ;(data || []).forEach((role) => {
      const normalized = normalizeRole(role.role_name)
      if (allowed.has(normalized) && !uniqueRoles.has(normalized)) {
        uniqueRoles.set(normalized, { ...role, role_name: normalized })
      }
    })

    setRoles([...uniqueRoles.values()])
  }

  async function fetchStaff(hotelId) {
    const { data, error } = await supabase
      .from('staff')
      .select(
        'id, hotel_id, full_name, email, phone, role, status, auth_user_id, created_at, updated_at, invited_at, invitation_sent_at, accepted_at, disabled_at, identity_reconciliation_status, identity_reconciliation_note, identity_reconciled_at'
      )
      .eq('hotel_id', hotelId)
      .order('created_at', { ascending: false })

    if (error) {
      setActionError(`Staff could not be loaded: ${error.message}`)
      return
    }

    setStaff(data || [])
  }

  const currentRole = normalizeRole(currentStaff?.role)
  const canManageStaff = roleCanManageStaff(currentRole)

  const filteredStaff = useMemo(() => {
    return staff.filter((member) => {
      const query = search.trim().toLowerCase()
      const matchesSearch =
        !query ||
        member.full_name?.toLowerCase().includes(query) ||
        member.email?.toLowerCase().includes(query) ||
        member.phone?.toLowerCase().includes(query)

      const matchesRole =
        roleFilter === 'all' ||
        normalizeRole(member.role) === normalizeRole(roleFilter)

      const matchesStatus =
        statusFilter === 'all' || member.status === statusFilter

      return matchesSearch && matchesRole && matchesStatus
    })
  }, [staff, search, roleFilter, statusFilter])

  const totalPages = Math.max(1, Math.ceil(filteredStaff.length / pageSize))
  const paginatedStaff = filteredStaff.slice(
    (page - 1) * pageSize,
    page * pageSize
  )

  const stats = {
    total: staff.length,
    active: staff.filter((member) => member.status === 'active').length,
    invited: staff.filter((member) => member.status === 'invited').length,
    disabled: staff.filter((member) =>
      ['inactive', 'suspended'].includes(member.status)
    ).length,
  }

  function openAddModal() {
    if (!canManageStaff) {
      setActionError('Only an owner, manager or platform administrator can invite staff.')
      return
    }

    setEditingStaff(null)
    setForm(emptyForm)
    setActionError('')
    setActionMessage('')
    setModalOpen(true)
  }

  function openEditModal(member) {
    if (!canManageStaff) {
      setActionError('You do not have permission to update staff identities.')
      return
    }

    setEditingStaff(member)
    setForm({
      full_name: member.full_name || '',
      email: member.email || '',
      phone: member.phone || '',
      role: normalizeRole(member.role) || 'reception',
    })
    setActionError('')
    setActionMessage('')
    setModalOpen(true)
  }

  function closeModal() {
    if (saving) return
    setModalOpen(false)
    setEditingStaff(null)
    setForm(emptyForm)
  }

  function handleFormChange(event) {
    const { name, value } = event.target
    setForm((current) => ({ ...current, [name]: value }))
  }

  async function invokeStaffAction(body) {
    const { data, error } = await supabase.functions.invoke('manage-staff-user', {
      body,
    })

    if (error) {
      let message = error.message

      try {
        const errorBody = await error.context?.json()
        message = errorBody?.error || message
      } catch {
        // Keep the Supabase Functions error when no JSON response is available.
      }

      throw new Error(message)
    }

    if (data?.error) throw new Error(data.error)
    return data
  }

  async function saveStaff() {
    if (!canManageStaff || !currentHotel?.id) return

    const fullName = form.full_name.trim()
    const email = form.email.trim().toLowerCase()
    const role = normalizeRole(form.role)

    if (!fullName || !email || !role) {
      setActionError('Enter the staff name, email and role.')
      return
    }

    setSaving(true)
    setActionError('')
    setActionMessage('')

    try {
      const response = await invokeStaffAction({
        action: editingStaff ? 'update' : 'invite',
        hotelId: currentHotel.id,
        staffId: editingStaff?.id,
        fullName,
        email,
        phone: form.phone.trim(),
        role,
      })

      await fetchStaff(currentHotel.id)
      setActionMessage(response?.result || 'Staff identity saved successfully.')
      closeModal()
    } catch (error) {
      setActionError(error.message)
    } finally {
      setSaving(false)
    }
  }

  async function linkIdentity(member) {
    if (!canManageStaff || !currentHotel?.id || member.auth_user_id) return

    const confirmed = window.confirm(
      `Send a secure Supabase Auth invitation to ${member.email}?`
    )

    if (!confirmed) return

    setSaving(true)
    setActionError('')
    setActionMessage('')

    try {
      const response = await invokeStaffAction({
        action: 'link',
        hotelId: currentHotel.id,
        staffId: member.id,
      })

      await fetchStaff(currentHotel.id)
      setActionMessage(response?.result || 'Identity invitation sent.')
    } catch (error) {
      setActionError(error.message)
    } finally {
      setSaving(false)
    }
  }

  async function updateStatus(member, status) {
    if (!canManageStaff || !currentHotel?.id) return

    const actionLabel =
      status === 'active'
        ? 'activate'
        : status === 'suspended'
          ? 'suspend'
          : 'disable'
    const confirmed = window.confirm(
      `Are you sure you want to ${actionLabel} ${member.full_name}?`
    )

    if (!confirmed) return

    setSaving(true)
    setActionError('')
    setActionMessage('')

    try {
      const response = await invokeStaffAction({
        action: 'status',
        hotelId: currentHotel.id,
        staffId: member.id,
        status,
      })

      await fetchStaff(currentHotel.id)
      setActionMessage(response?.result || 'Staff access updated.')
    } catch (error) {
      setActionError(error.message)
    } finally {
      setSaving(false)
    }
  }

  function resetFilters() {
    setSearch('')
    setRoleFilter('all')
    setStatusFilter('all')
    setPage(1)
  }

  if (loading) {
    return (
      <div className="staff-page">
        <div className="staff-loading-card">
          <div className="staff-loader" />
          <p>Loading secure staff identities…</p>
        </div>
      </div>
    )
  }

  return (
    <div className="staff-page">
      <div className="staff-header">
        <div>
          <p className="staff-kicker">Authentication & Access Control</p>
          <h1>Staff Identities</h1>
          <p>
            {currentHotel?.hotel_name || 'Hotel'} · Invite verified users and
            control their hotel access.
          </p>
        </div>

        <div className="staff-header-actions">
          <button className="staff-secondary-btn" onClick={initPage} type="button">
            Refresh
          </button>
          <button
            className="staff-primary-btn"
            onClick={openAddModal}
            disabled={!canManageStaff || saving}
            type="button"
          >
            + Invite Staff
          </button>
        </div>
      </div>

      {actionMessage && <div className="staff-alert success">{actionMessage}</div>}
      {actionError && <div className="staff-alert error">{actionError}</div>}

      <div className="staff-stats-grid">
        <StatCard label="Total Identities" value={stats.total} icon="👥" />
        <StatCard label="Active" value={stats.active} icon="✅" />
        <StatCard label="Invitations" value={stats.invited} icon="✉️" />
        <StatCard label="Disabled" value={stats.disabled} icon="⛔" />
      </div>

      <div className="staff-control-card">
        <div className="staff-search-box">
          <span>🔍</span>
          <input
            placeholder="Search name, email or phone…"
            value={search}
            onChange={(event) => {
              setSearch(event.target.value)
              setPage(1)
            }}
          />
        </div>

        <select
          value={roleFilter}
          onChange={(event) => {
            setRoleFilter(event.target.value)
            setPage(1)
          }}
        >
          <option value="all">All roles</option>
          {roles.map((role) => (
            <option key={role.id} value={normalizeRole(role.role_name)}>
              {formatRole(role.role_name)}
            </option>
          ))}
        </select>

        <select
          value={statusFilter}
          onChange={(event) => {
            setStatusFilter(event.target.value)
            setPage(1)
          }}
        >
          <option value="all">All statuses</option>
          {managedStatuses.map((status) => (
            <option key={status} value={status}>
              {formatRole(status)}
            </option>
          ))}
        </select>

        <button onClick={resetFilters} type="button">
          Reset
        </button>
      </div>

      <div className="staff-table-card">
        <div className="staff-table-top">
          <div>
            <h2>Hotel staff</h2>
            <p>
              Showing {paginatedStaff.length} of {filteredStaff.length} identities
            </p>
          </div>
          <span className="staff-permission-pill">
            {canManageStaff ? 'Identity Manager' : 'View Only'}
          </span>
        </div>

        {filteredStaff.length === 0 ? (
          <div className="staff-empty">
            <div>👤</div>
            <h3>No staff identities found</h3>
            <p>Change the filters or invite a staff member.</p>
          </div>
        ) : (
          <div className="staff-table-wrap">
            <table className="staff-table">
              <thead>
                <tr>
                  <th>Staff</th>
                  <th>Role</th>
                  <th>Identity</th>
                  <th>Status</th>
                  <th>Accepted</th>
                  <th>Actions</th>
                </tr>
              </thead>
              <tbody>
                {paginatedStaff.map((member) => {
                  const isSelf = member.auth_user_id === currentStaff?.auth_user_id

                  return (
                    <tr key={member.id}>
                      <td>
                        <div className="staff-person">
                          <div className="staff-avatar">
                            {(member.full_name || member.email || '?').charAt(0).toUpperCase()}
                          </div>
                          <div>
                            <strong>{member.full_name}</strong>
                            <span>{member.email}</span>
                            {member.phone && <small>{member.phone}</small>}
                          </div>
                        </div>
                      </td>
                      <td>
                        <span className="staff-role-badge">
                          {formatRole(member.role)}
                        </span>
                      </td>
                      <td>
                        <span className={`staff-identity ${member.auth_user_id ? 'linked' : 'missing'}`}>
                          {member.auth_user_id
                            ? 'Supabase Auth linked'
                            : member.identity_reconciliation_status === 'archived_unlinked'
                              ? 'Archived legacy profile'
                              : 'Identity invitation required'}
                        </span>
                        {!member.auth_user_id && member.identity_reconciliation_note && (
                          <small className="staff-identity-note">
                            {member.identity_reconciliation_note}
                          </small>
                        )}
                      </td>
                      <td>
                        <span className={`staff-status ${member.status}`}>
                          {formatRole(member.status)}
                        </span>
                      </td>
                      <td>{formatDate(member.accepted_at || member.invited_at)}</td>
                      <td>
                        <div className="staff-actions">
                          <button
                            type="button"
                            onClick={() => openEditModal(member)}
                            disabled={!canManageStaff || saving}
                          >
                            Edit
                          </button>

                          {!member.auth_user_id ? (
                            <button
                              type="button"
                              className="staff-link-btn"
                              onClick={() => linkIdentity(member)}
                              disabled={!canManageStaff || saving}
                            >
                              Send identity invite
                            </button>
                          ) : (
                            <>
                              {member.status !== 'active' ? (
                                <button
                                  type="button"
                                  onClick={() => updateStatus(member, 'active')}
                                  disabled={!canManageStaff || saving}
                                >
                                  Activate
                                </button>
                              ) : (
                                <button
                                  type="button"
                                  onClick={() => updateStatus(member, 'inactive')}
                                  disabled={!canManageStaff || saving || isSelf}
                                >
                                  Disable
                                </button>
                              )}

                              {member.status !== 'suspended' && (
                                <button
                                  type="button"
                                  className="danger"
                                  onClick={() => updateStatus(member, 'suspended')}
                                  disabled={!canManageStaff || saving || isSelf}
                                >
                                  Suspend
                                </button>
                              )}
                            </>
                          )}
                        </div>
                      </td>
                    </tr>
                  )
                })}
              </tbody>
            </table>
          </div>
        )}

        {filteredStaff.length > pageSize && (
          <div className="staff-pagination">
            <button
              disabled={page === 1}
              onClick={() => setPage((current) => current - 1)}
              type="button"
            >
              Previous
            </button>
            <span>
              Page {page} of {totalPages}
            </span>
            <button
              disabled={page === totalPages}
              onClick={() => setPage((current) => current + 1)}
              type="button"
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
                  {editingStaff ? 'Update Identity' : 'Secure Invitation'}
                </p>
                <h2>{editingStaff ? 'Edit staff member' : 'Invite staff member'}</h2>
              </div>
              <button className="staff-close-btn" onClick={closeModal} type="button">
                ×
              </button>
            </div>

            <div className="staff-form-grid">
              <label>
                Full name
                <input
                  name="full_name"
                  value={form.full_name}
                  onChange={handleFormChange}
                  placeholder="Enter full name"
                />
              </label>

              <label>
                Verified email
                <input
                  name="email"
                  type="email"
                  value={form.email}
                  onChange={handleFormChange}
                  placeholder="staff@example.com"
                  disabled={Boolean(editingStaff?.auth_user_id)}
                />
              </label>

              <label>
                Phone
                <input
                  name="phone"
                  value={form.phone}
                  onChange={handleFormChange}
                  placeholder="Optional phone number"
                />
              </label>

              <label>
                Role
                <select name="role" value={form.role} onChange={handleFormChange}>
                  {roles.map((role) => (
                    <option key={role.id} value={normalizeRole(role.role_name)}>
                      {formatRole(role.role_name)}
                    </option>
                  ))}
                </select>
              </label>
            </div>

            <div className="staff-note">
              {editingStaff
                ? editingStaff.auth_user_id
                  ? 'Linked authentication email cannot be silently changed. Update the role or profile details here.'
                  : 'This preserved legacy profile has no login identity. Save profile details here, then use Send identity invite from the staff list.'
                : 'StayQR creates or links a real Supabase Auth identity and sends a secure password invitation.'}
            </div>

            <div className="staff-modal-actions">
              <button className="staff-secondary-btn" onClick={closeModal} type="button">
                Cancel
              </button>
              <button
                className="staff-primary-btn"
                onClick={saveStaff}
                disabled={saving}
                type="button"
              >
                {saving
                  ? 'Saving…'
                  : editingStaff
                    ? 'Save changes'
                    : 'Send invitation'}
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  )
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
  )
}

function formatDate(value) {
  if (!value) return '—'
  return new Date(value).toLocaleString('en-IN', {
    day: '2-digit',
    month: 'short',
    year: 'numeric',
  })
}
