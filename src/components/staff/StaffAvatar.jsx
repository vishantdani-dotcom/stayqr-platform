import { useEffect, useState } from 'react'
import { supabase } from '../../lib/supabase'

const STAFF_AVATAR_BUCKET = 'staff-avatars'

export default function StaffAvatar({ staff, name = '' }) {
  const [avatarUrl, setAvatarUrl] = useState('')

  useEffect(() => {
    let cancelled = false

    async function loadAvatar() {
      const avatarPath = staff?.avatar_path

      if (!avatarPath) {
        if (!cancelled) setAvatarUrl('')
        return
      }

      const { data, error } = await supabase.storage
        .from(STAFF_AVATAR_BUCKET)
        .createSignedUrl(avatarPath, 3600)

      if (!cancelled) {
        setAvatarUrl(error ? '' : data?.signedUrl || '')
      }
    }

    void loadAvatar()

    return () => {
      cancelled = true
    }
  }, [staff?.avatar_path])

  const label =
    String(
      name ||
      staff?.full_name ||
      staff?.email ||
      'User'
    ).trim() || 'User'

  const initial =
    label.charAt(0).toUpperCase() || 'U'

  return avatarUrl ? (
    <img
      className="stayqr-staff-avatar-image"
      src={avatarUrl}
      alt={`${label} profile`}
      draggable="false"
    />
  ) : (
    <span
      className="stayqr-staff-avatar-fallback"
      aria-hidden="true"
    >
      {initial}
    </span>
  )
}
