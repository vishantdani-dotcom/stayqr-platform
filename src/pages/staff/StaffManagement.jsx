import { useEffect, useMemo, useState } from 'react'
import { supabase } from '../../lib/supabase'
import { getCurrentHotel } from '../../lib/currentHotel'
import {
  canManageStaff as roleCanManageStaff,
  formatRole,
  getCurrentStaff,
  normalizeRole,
} from '../../lib/currentStaff'
import { loadTenantContext } from '../../lib/tenantContext'
import './StaffManagement.css'

const STAFF_AVATAR_BUCKET = 'staff-avatars'
const MAX_PROFILE_PHOTO_SIZE = 5 * 1024 * 1024
const allowedProfilePhotoTypes = new Set(['image/jpeg', 'image/png', 'image/webp'])

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
  const [profileForm, setProfileForm] = useState({ full_name: '', phone: '' })
  const [profilePhoto, setProfilePhoto] = useState(null)
  const [profilePreview, setProfilePreview] = useState('')
  const [profileSaving, setProfileSaving] = useState(false)
  const [phoneOtp, setPhoneOtp] = useState('')
  const [phoneVerificationSent, setPhoneVerificationSent] = useState(false)
  const [phoneVerifying, setPhoneVerifying] = useState(false)

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
    setProfileForm({
      full_name: loggedStaff?.full_name || '',
      phone: loggedStaff?.phone || '',
    })
    await loadAvatarPreview(loggedStaff?.avatar_path)

    await Promise.all([fetchRoles(), fetchStaff(hotel.id)])
    setLoading(false)
  }

  async function loadAvatarPreview(avatarPath) {
    if (!avatarPath) {
      setProfilePreview('')
      return
    }

    const { data, error } = await supabase.storage
      .from(STAFF_AVATAR_BUCKET)
      .createSignedUrl(avatarPath, 3600)

    setProfilePreview(error ? '' : data?.signedUrl || '')
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
        'id, hotel_id, full_name, email, phone, phone_verified_at, role, status, auth_user_id, avatar_path, created_at, updated_at, invited_at, invitation_sent_at, accepted_at, disabled_at, identity_reconciliation_status, identity_reconciliation_note, identity_reconciled_at'
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
  const displayedPhoneVerified = Boolean(
    currentStaff?.phone_verified_at &&
    String(currentStaff?.phone || '').trim() === profileForm.phone.trim()
  )

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

  function handleProfilePhoto(event) {
    const file = event.target.files?.[0]
    if (!file) return

    if (!allowedProfilePhotoTypes.has(file.type)) {
      setActionError('Profile photo must be a JPG, PNG or WebP image.')
      event.target.value = ''
      return
    }

    if (file.size > MAX_PROFILE_PHOTO_SIZE) {
      setActionError('Profile photo must be 5 MB or smaller.')
      event.target.value = ''
      return
    }

    if (profilePreview.startsWith('blob:')) URL.revokeObjectURL(profilePreview)
    setProfilePhoto(file)
    setProfilePreview(URL.createObjectURL(file))
    setActionError('')
  }

  async function saveOwnProfile() {
    const fullName = profileForm.full_name.trim()
    const phone = profileForm.phone.trim()

    if (!currentHotel?.id || !currentStaff?.auth_user_id) {
      setActionError('A linked staff login is required to update this profile.')
      return
    }

    if (!fullName) {
      setActionError('Enter your full name.')
      return
    }

    setProfileSaving(true)
    setActionError('')
    setActionMessage('')

    try {
      let avatarPath = currentStaff.avatar_path || null

      if (profilePhoto) {
        const extension = profilePhoto.name.split('.').pop()?.toLowerCase() || 'jpg'
        avatarPath = `${currentHotel.id}/${currentStaff.auth_user_id}/avatar-${Date.now()}.${extension}`
        const { error: uploadError } = await supabase.storage
          .from(STAFF_AVATAR_BUCKET)
          .upload(avatarPath, profilePhoto, {
            contentType: profilePhoto.type,
            upsert: true,
          })

        if (uploadError) throw uploadError
      }

      const { error: updateError } = await supabase.rpc('update_my_staff_profile', {
        p_hotel_id: currentHotel.id,
        p_full_name: fullName,
        p_phone: phone || null,
        p_avatar_path: avatarPath,
      })

      if (updateError) throw updateError

      const context = await loadTenantContext({ force: true })
      const refreshedStaff = context?.currentStaff || {
        ...currentStaff,
        full_name: fullName,
        phone,
        avatar_path: avatarPath,
      }
      setCurrentStaff(refreshedStaff)
      setProfileForm({
        full_name: refreshedStaff.full_name || fullName,
        phone: refreshedStaff.phone || phone,
      })
      setProfilePhoto(null)
      await Promise.all([loadAvatarPreview(avatarPath), fetchStaff(currentHotel.id)])
      setActionMessage('Your staff profile was updated.')
    } catch (error) {
      setActionError(error.message)
    } finally {
      setProfileSaving(false)
    }
  }

  async function beginPhoneVerification() {
    const phone = profileForm.phone.trim()
    if (!/^\+[1-9]\d{7,14}$/.test(phone)) {
      setActionError('Enter the phone in international format, for example +919503893141.')
      return
    }

    setPhoneVerifying(true)
    setActionError('')
    setActionMessage('')
    try {
      const { error } = await supabase.auth.updateUser({ phone })
      if (error) throw error
      setPhoneVerificationSent(true)
      setPhoneOtp('')
      setActionMessage(`Verification code sent to ${phone}.`)
    } catch (error) {
      const rawMessage = error?.message || ''
      setActionError(
        /sms provider|provider.*sms/i.test(rawMessage)
          ? 'Phone verification is ready, but this Supabase project has no SMS provider configured. Configure Auth > Phone/SMS provider, then retry.'
          : rawMessage || 'Unable to send the phone verification code.'
      )
    } finally {
      setPhoneVerifying(false)
    }
  }

  async function confirmPhoneVerification() {
    const phone = profileForm.phone.trim()
    if (!/^\d{6}$/.test(phoneOtp)) {
      setActionError('Enter the 6-digit verification code.')
      return
    }

    setPhoneVerifying(true)
    setActionError('')
    setActionMessage('')
    try {
      const { error: verifyError } = await supabase.auth.verifyOtp({
        phone,
        token: phoneOtp,
        type: 'phone_change',
      })
      if (verifyError) throw verifyError

      const { data, error: syncError } = await supabase.rpc('sync_my_verified_staff_phone', {
        p_hotel_id: currentHotel.id,
      })
      if (syncError) throw syncError

      const context = await loadTenantContext({ force: true })
      setCurrentStaff(context?.currentStaff || { ...currentStaff, phone: data?.phone || phone, phone_verified_at: data?.phone_verified_at || new Date().toISOString() })
      setProfileForm((current) => ({ ...current, phone: data?.phone || phone }))
      setPhoneVerificationSent(false)
      setPhoneOtp('')
      await fetchStaff(currentHotel.id)
      setActionMessage('Phone number verified successfully.')
    } catch (error) {
      setActionError(error?.message || 'Phone verification failed.')
    } finally {
      setPhoneVerifying(false)
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

      <section className="staff-self-profile" aria-labelledby="staff-self-profile-title">
        <div className="staff-self-profile-heading">
          <div className="staff-profile-photo">
            {profilePreview ? (
              <img src={profilePreview} alt="Your staff profile" />
            ) : (
              (profileForm.full_name || currentStaff?.email || '?').charAt(0).toUpperCase()
            )}
          </div>
          <div>
            <p className="staff-kicker">My profile</p>
            <h2 id="staff-self-profile-title">Personal contact details</h2>
            <span>Your photo and phone stay scoped to this hotel identity.</span>
          </div>
        </div>

        <div className="staff-self-profile-fields">
          <label>
            Full name
            <input
              value={profileForm.full_name}
              onChange={(event) =>
                setProfileForm((current) => ({ ...current, full_name: event.target.value }))
              }
            />
          </label>
          <label className="staff-phone-field">
            <span className="staff-phone-label">
              Phone number
              <b className={displayedPhoneVerified ? 'verified' : 'unverified'}>
                {displayedPhoneVerified ? 'Verified' : 'Unverified'}
              </b>
            </span>
            <input
              type="tel"
              value={profileForm.phone}
              onChange={(event) => {
                setProfileForm((current) => ({ ...current, phone: event.target.value }))
                setPhoneVerificationSent(false)
                setPhoneOtp('')
              }}
              placeholder="+919503893141"
            />
            <small>Use international format with country code.</small>
            {!displayedPhoneVerified && !phoneVerificationSent && (
              <button className="staff-secondary-btn compact" type="button" onClick={beginPhoneVerification} disabled={phoneVerifying}>
                {phoneVerifying ? 'Sending…' : 'Verify phone'}
              </button>
            )}
            {!displayedPhoneVerified && phoneVerificationSent && (
              <div className="staff-phone-otp">
                <input
                  inputMode="numeric"
                  maxLength={6}
                  value={phoneOtp}
                  onChange={(event) => setPhoneOtp(event.target.value.replace(/\D/g, '').slice(0, 6))}
                  placeholder="6-digit code"
                />
                <button className="staff-primary-btn compact" type="button" onClick={confirmPhoneVerification} disabled={phoneVerifying || phoneOtp.length !== 6}>
                  {phoneVerifying ? 'Checking…' : 'Confirm'}
                </button>
              </div>
            )}
          </label>
          <label>
            Profile photo
            <input
              type="file"
              accept="image/jpeg,image/png,image/webp"
              onChange={handleProfilePhoto}
            />
          </label>
          <button
            className="staff-primary-btn"
            type="button"
            onClick={saveOwnProfile}
            disabled={profileSaving || !currentStaff?.auth_user_id}
          >
            {profileSaving ? 'Saving…' : 'Save my profile'}
          </button>
        </div>
      </section>

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
                            {isSelf && profilePreview ? (
                              <img src={profilePreview} alt="" />
                            ) : (
                              (member.full_name || member.email || '?').charAt(0).toUpperCase()
                            )}
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
