import { useEffect, useState } from 'react'
import { supabase } from '../../lib/supabase'
import { getCurrentHotel } from '../../lib/currentHotel'
import { getCurrentStaff } from '../../lib/currentStaff'
import { loadTenantContext } from '../../lib/tenantContext'
import './StaffManagement.css'

const STAFF_AVATAR_BUCKET = 'staff-avatars'
const MAX_PROFILE_PHOTO_SIZE = 5 * 1024 * 1024

const allowedProfilePhotoTypes = new Set([
  'image/jpeg',
  'image/png',
  'image/webp',
])

export default function MyProfile({ onProfileUpdated }) {
  const [currentHotel, setCurrentHotel] = useState(null)
  const [currentStaff, setCurrentStaff] = useState(null)

  const [profileForm, setProfileForm] = useState({
    full_name: '',
    phone: '',
  })

  const [profilePhoto, setProfilePhoto] = useState(null)
  const [profilePreview, setProfilePreview] = useState('')
  const [profileSaving, setProfileSaving] = useState(false)

  const [phoneOtp, setPhoneOtp] = useState('')
  const [phoneVerificationSent, setPhoneVerificationSent] = useState(false)
  const [phoneVerifying, setPhoneVerifying] = useState(false)

  const [loading, setLoading] = useState(true)
  const [actionMessage, setActionMessage] = useState('')
  const [actionError, setActionError] = useState('')

  useEffect(() => {
    initPage()
  }, [])

  async function initPage() {
    setLoading(true)
    setActionError('')
    setActionMessage('')

    try {
      const [hotel, staff] = await Promise.all([
        getCurrentHotel(),
        getCurrentStaff(),
      ])

      if (!hotel) {
        throw new Error('No active hotel is assigned to this login.')
      }

      if (!staff?.auth_user_id) {
        throw new Error(
          'A linked StayQR staff login is required to manage this profile.'
        )
      }

      setCurrentHotel(hotel)
      setCurrentStaff(staff)

      setProfileForm({
        full_name: staff.full_name || '',
        phone: staff.phone || '',
      })

      await loadAvatarPreview(staff.avatar_path)
    } catch (error) {
      setActionError(
        error?.message || 'StayQR could not load your profile.'
      )
    } finally {
      setLoading(false)
    }
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

  const displayedPhoneVerified = Boolean(
    currentStaff?.phone_verified_at &&
      String(currentStaff?.phone || '').trim() ===
        profileForm.phone.trim()
  )

  function handleProfilePhoto(event) {
    const file = event.target.files?.[0]

    if (!file) return

    if (!allowedProfilePhotoTypes.has(file.type)) {
      setActionError(
        'Profile photo must be a JPG, PNG or WebP image.'
      )
      event.target.value = ''
      return
    }

    if (file.size > MAX_PROFILE_PHOTO_SIZE) {
      setActionError('Profile photo must be 5 MB or smaller.')
      event.target.value = ''
      return
    }

    if (profilePreview.startsWith('blob:')) {
      URL.revokeObjectURL(profilePreview)
    }

    setProfilePhoto(file)
    setProfilePreview(URL.createObjectURL(file))
    setActionError('')
  }

  async function saveOwnProfile() {
    const fullName = profileForm.full_name.trim()
    const phone = profileForm.phone.trim()

    if (!currentHotel?.id || !currentStaff?.auth_user_id) {
      setActionError(
        'A linked staff login is required to update this profile.'
      )
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
        const extension =
          profilePhoto.name.split('.').pop()?.toLowerCase() || 'jpg'

        avatarPath =
          `${currentHotel.id}/` +
          `${currentStaff.auth_user_id}/` +
          `avatar-${Date.now()}.${extension}`

        const { error: uploadError } = await supabase.storage
          .from(STAFF_AVATAR_BUCKET)
          .upload(avatarPath, profilePhoto, {
            contentType: profilePhoto.type,
            upsert: true,
          })

        if (uploadError) throw uploadError
      }

      const { error: updateError } = await supabase.rpc(
        'update_my_staff_profile',
        {
          p_hotel_id: currentHotel.id,
          p_full_name: fullName,
          p_phone: phone || null,
          p_avatar_path: avatarPath,
        }
      )

      if (updateError) throw updateError

      const context = await loadTenantContext({ force: true })

      const refreshedStaff =
        context?.currentStaff || {
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

      await loadAvatarPreview(avatarPath)

      if (context) {
        onProfileUpdated?.(context)
      }

      setActionMessage('Your profile was updated successfully.')
    } catch (error) {
      setActionError(
        error?.message || 'StayQR could not update your profile.'
      )
    } finally {
      setProfileSaving(false)
    }
  }

  async function beginPhoneVerification() {
    const phone = profileForm.phone.trim()

    if (!/^\+[1-9]\d{7,14}$/.test(phone)) {
      setActionError(
        'Enter the phone in international format, for example +919503893141.'
      )
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
          ? 'Phone verification is ready, but this Supabase project has no SMS provider configured.'
          : rawMessage ||
              'Unable to send the phone verification code.'
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
      const { error: verifyError } =
        await supabase.auth.verifyOtp({
          phone,
          token: phoneOtp,
          type: 'phone_change',
        })

      if (verifyError) throw verifyError

      const { data, error: syncError } = await supabase.rpc(
        'sync_my_verified_staff_phone',
        {
          p_hotel_id: currentHotel.id,
        }
      )

      if (syncError) throw syncError

      const context = await loadTenantContext({ force: true })

      const refreshed =
        context?.currentStaff || {
          ...currentStaff,
          phone: data?.phone || phone,
          phone_verified_at:
            data?.phone_verified_at ||
            new Date().toISOString(),
        }

      setCurrentStaff(refreshed)

      setProfileForm((current) => ({
        ...current,
        phone: data?.phone || phone,
      }))

      setPhoneVerificationSent(false)
      setPhoneOtp('')

      if (context) {
        onProfileUpdated?.(context)
      }

      setActionMessage('Phone number verified successfully.')
    } catch (error) {
      setActionError(
        error?.message || 'Phone verification failed.'
      )
    } finally {
      setPhoneVerifying(false)
    }
  }

  if (loading) {
    return (
      <div className="staff-page">
        <div className="staff-loading-card">
          <div className="staff-loader" />
          <p>Loading your StayQR profile…</p>
        </div>
      </div>
    )
  }

  return (
    <div className="staff-page">
      <div className="staff-header">
        <div>
          <p className="staff-kicker">My Account</p>
          <h1>My Profile</h1>
          <p>
            {currentHotel?.hotel_name || 'Hotel'} ·
            Manage your own hotel identity.
          </p>
        </div>

        <div className="staff-header-actions">
          <button
            className="staff-secondary-btn"
            type="button"
            onClick={initPage}
          >
            Refresh
          </button>
        </div>
      </div>

      {actionMessage && (
        <div className="staff-alert success">
          {actionMessage}
        </div>
      )}

      {actionError && (
        <div className="staff-alert error">
          {actionError}
        </div>
      )}

      <section
        className="staff-self-profile"
        aria-labelledby="my-profile-title"
      >
        <div className="staff-self-profile-heading">
          <div className="staff-profile-photo">
            {profilePreview ? (
              <img
                src={profilePreview}
                alt="Your staff profile"
              />
            ) : (
              (
                profileForm.full_name ||
                currentStaff?.email ||
                '?'
              )
                .charAt(0)
                .toUpperCase()
            )}
          </div>

          <div>
            <p className="staff-kicker">My Profile</p>
            <h2 id="my-profile-title">
              Personal contact details
            </h2>

            <span>
              Your photo and phone stay scoped to this
              hotel identity.
            </span>
          </div>
        </div>

        <div className="staff-self-profile-fields">
          <label>
            Full name

            <input
              value={profileForm.full_name}
              onChange={(event) =>
                setProfileForm((current) => ({
                  ...current,
                  full_name: event.target.value,
                }))
              }
            />
          </label>

          <label className="staff-phone-field">
            <span className="staff-phone-label">
              Phone number

              <b hidden={!displayedPhoneVerified}
                className={
                  displayedPhoneVerified
                    ? 'verified'
                    : 'unverified'
                }
              >
                {displayedPhoneVerified
                  ? 'Verified'
                  : 'Unverified'}
              </b>
            </span>

            <input
              type="tel"
              value={profileForm.phone}
              onChange={(event) => {
                setProfileForm((current) => ({
                  ...current,
                  phone: event.target.value,
                }))

                setPhoneVerificationSent(false)
                setPhoneOtp('')
              }}
              placeholder="+919503893141"
            />

            <small>
              Use international format with country code.
            </small>

            {!displayedPhoneVerified &&
              !phoneVerificationSent && (
                <button hidden
                  className="staff-secondary-btn compact"
                  type="button"
                  onClick={beginPhoneVerification}
                  disabled={phoneVerifying}
                >
                  {phoneVerifying
                    ? 'Sending…'
                    : 'Verify phone'}
                </button>
              )}

            {!displayedPhoneVerified &&
              phoneVerificationSent && (
                <div className="staff-phone-otp">
                  <input
                    inputMode="numeric"
                    maxLength={6}
                    value={phoneOtp}
                    onChange={(event) =>
                      setPhoneOtp(
                        event.target.value
                          .replace(/\D/g, '')
                          .slice(0, 6)
                      )
                    }
                    placeholder="6-digit code"
                  />

                  <button
                    className="staff-primary-btn compact"
                    type="button"
                    onClick={confirmPhoneVerification}
                    disabled={
                      phoneVerifying ||
                      phoneOtp.length !== 6
                    }
                  >
                    {phoneVerifying
                      ? 'Checking…'
                      : 'Confirm'}
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
            disabled={
              profileSaving ||
              !currentStaff?.auth_user_id
            }
          >
            {profileSaving
              ? 'Saving…'
              : 'Save my profile'}
          </button>
        </div>
      </section>
    </div>
  )
}
