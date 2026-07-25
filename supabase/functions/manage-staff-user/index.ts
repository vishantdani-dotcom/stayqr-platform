import { createClient, type User } from 'npm:@supabase/supabase-js@2.106.2'

const allowedRoles = new Set([
  'owner',
  'manager',
  'reception',
  'housekeeping',
  'restaurant',
  'accounts',
])

const allowedStatuses = new Set(['active', 'inactive', 'suspended'])

type StaffAction = 'invite' | 'link' | 'update' | 'status' | 'archive'

type StaffRequest = {
  action?: StaffAction
  hotelId?: string
  staffId?: string
  fullName?: string
  email?: string
  phone?: string
  role?: string
  status?: string
}

type SupabaseClient = ReturnType<typeof createClient>

function normalizeEmail(value?: string) {
  return String(value || '').trim().toLowerCase()
}

function normalizeRole(value?: string) {
  return String(value || '')
    .trim()
    .toLowerCase()
    .replace(/\s+/g, '_')
}

function isUuid(value?: string) {
  return Boolean(
    value &&
      /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(
        value,
      ),
  )
}

function getAllowedOrigins() {
  const configured = [
    Deno.env.get('STAYQR_APP_URL'),
    Deno.env.get('STAYQR_APP_URLS'),
  ]
    .filter(Boolean)
    .flatMap((value) => String(value).split(','))
    .map((value) => value.trim().replace(/\/$/, ''))
    .filter(Boolean)

  return new Set(
    configured.map((value) => {
      try {
        return new URL(value).origin
      } catch {
        return value
      }
    }),
  )
}

function corsHeaders(request: Request) {
  const requestOrigin = request.headers.get('Origin') || ''
  const allowedOrigins = getAllowedOrigins()
  const fallbackOrigin = [...allowedOrigins][0] || requestOrigin || '*'
  const responseOrigin = allowedOrigins.has(requestOrigin)
    ? requestOrigin
    : fallbackOrigin

  return {
    'Access-Control-Allow-Origin': responseOrigin,
    'Access-Control-Allow-Headers':
      'authorization, x-client-info, apikey, content-type',
    'Access-Control-Allow-Methods': 'POST, OPTIONS',
    'Access-Control-Max-Age': '86400',
    Vary: 'Origin',
  }
}

function json(
  request: Request,
  status: number,
  body: Record<string, unknown>,
) {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      ...corsHeaders(request),
      'Content-Type': 'application/json',
      'Cache-Control': 'no-store',
    },
  })
}

async function findAuthUserByEmail(
  adminClient: SupabaseClient,
  email: string,
) {
  for (let page = 1; page <= 20; page += 1) {
    const { data, error } = await adminClient.auth.admin.listUsers({
      page,
      perPage: 500,
    })

    if (error) throw error

    const match = data.users.find(
      (candidate) => normalizeEmail(candidate.email) === email,
    )

    if (match) return match
    if (data.users.length < 500) return null
  }

  throw new Error('StayQR could not safely resolve the authentication user.')
}

async function getAuthUserById(
  adminClient: SupabaseClient,
  userId: string,
) {
  const { data, error } = await adminClient.auth.admin.getUserById(userId)
  if (error) throw error
  return data.user
}

function isCurrentlyBanned(user: User | null) {
  if (!user?.banned_until) return false
  return new Date(user.banned_until).getTime() > Date.now()
}

async function assertCallerCanManage(
  adminClient: SupabaseClient,
  callerId: string,
  hotelId: string,
) {
  const { data: platformAdmin, error: platformError } = await adminClient
    .from('platform_admins')
    .select('user_id')
    .eq('user_id', callerId)
    .eq('status', 'active')
    .maybeSingle()

  if (platformError) throw platformError
  if (platformAdmin) return { isPlatformAdmin: true, role: 'platform_admin' }

  const { data: staff, error } = await adminClient
    .from('staff')
    .select('id, role')
    .eq('hotel_id', hotelId)
    .eq('auth_user_id', callerId)
    .eq('status', 'active')
    .maybeSingle()

  if (error) throw error

  const role = normalizeRole(staff?.role)

  if (!staff || !['owner', 'manager'].includes(role)) {
    throw new Error('Only an active hotel owner or manager can manage staff.')
  }

  return { isPlatformAdmin: false, role }
}

async function assertOwnerContinuity(
  adminClient: SupabaseClient,
  hotelId: string,
  targetStaffId: string,
  nextRole: string,
  nextStatus: string,
) {
  const { data: target, error: targetError } = await adminClient
    .from('staff')
    .select('id, role, status')
    .eq('id', targetStaffId)
    .eq('hotel_id', hotelId)
    .single()

  if (targetError) throw targetError

  const removesActiveOwner =
    normalizeRole(target.role) === 'owner' &&
    target.status === 'active' &&
    (nextRole !== 'owner' || nextStatus !== 'active')

  if (!removesActiveOwner) return target

  const { count, error } = await adminClient
    .from('staff')
    .select('id', { count: 'exact', head: true })
    .eq('hotel_id', hotelId)
    .eq('status', 'active')
    .ilike('role', 'owner')
    .neq('id', targetStaffId)

  if (error) throw error
  if (!count) throw new Error('A hotel must retain at least one active owner.')

  return target
}

async function hasOtherActiveAccess(
  adminClient: SupabaseClient,
  authUserId: string,
  targetStaffId: string,
) {
  const [otherStaff, platformAdmin] = await Promise.all([
    adminClient
      .from('staff')
      .select('id', { count: 'exact', head: true })
      .eq('auth_user_id', authUserId)
      .eq('status', 'active')
      .neq('id', targetStaffId),
    adminClient
      .from('platform_admins')
      .select('user_id')
      .eq('user_id', authUserId)
      .eq('status', 'active')
      .maybeSingle(),
  ])

  if (otherStaff.error) throw otherStaff.error
  if (platformAdmin.error) throw platformAdmin.error

  return Boolean(otherStaff.count) || Boolean(platformAdmin.data)
}

async function recordIdentityEvent(
  adminClient: SupabaseClient,
  payload: {
    hotelId: string
    staffId?: string | null
    authUserId?: string | null
    eventType:
      | 'invited'
      | 'linked'
      | 'updated'
      | 'activated'
      | 'disabled'
      | 'suspended'
      | 'archived'
      | 'reconciled'
    previousStatus?: string | null
    newStatus?: string | null
    actorUserId: string
    details?: Record<string, unknown>
  },
) {
  const { error } = await adminClient.from('staff_identity_events').insert({
    hotel_id: payload.hotelId,
    staff_id: payload.staffId || null,
    auth_user_id: payload.authUserId || null,
    event_type: payload.eventType,
    previous_status: payload.previousStatus || null,
    new_status: payload.newStatus || null,
    actor_user_id: payload.actorUserId,
    details: payload.details || {},
  })

  if (error) throw error
}

async function upsertStaffIdentity(
  adminClient: SupabaseClient,
  payload: {
    hotelId: string
    authUserId: string
    fullName: string
    email: string
    phone: string
    role: string
    status: 'active' | 'invited'
    callerId: string
    invitationSent: boolean
    targetStaffId?: string | null
  },
) {
  let query = adminClient
    .from('staff')
    .select('id, auth_user_id, status')
    .eq('hotel_id', payload.hotelId)

  if (payload.targetStaffId) {
    query = query.eq('id', payload.targetStaffId)
  } else {
    query = query.ilike('email', payload.email)
  }

  const { data: existing, error: findError } = await query.maybeSingle()
  if (findError) throw findError

  if (
    existing?.auth_user_id &&
    existing.auth_user_id !== payload.authUserId
  ) {
    throw new Error(
      'This staff profile is already linked to a different authentication identity.',
    )
  }

  const now = new Date().toISOString()
  const values = {
    hotel_id: payload.hotelId,
    auth_user_id: payload.authUserId,
    full_name: payload.fullName,
    email: payload.email,
    phone: payload.phone || null,
    role: payload.role,
    status: payload.status,
    invited_at:
      payload.status === 'invited' ? existing?.status === 'invited' ? undefined : now : null,
    invitation_sent_at: payload.invitationSent ? now : undefined,
    accepted_at: payload.status === 'active' ? now : null,
    disabled_at: null,
    identity_reconciliation_status: 'linked',
    identity_reconciliation_note: payload.invitationSent
      ? 'Real Supabase Auth invitation created and linked.'
      : 'Existing Supabase Auth identity linked and verified.',
    identity_reconciled_at: now,
    updated_by: payload.callerId,
  }

  if (existing) {
    const cleanedValues = Object.fromEntries(
      Object.entries(values).filter(([, value]) => value !== undefined),
    )

    const { data, error } = await adminClient
      .from('staff')
      .update(cleanedValues)
      .eq('id', existing.id)
      .eq('hotel_id', payload.hotelId)
      .select('*')
      .single()

    if (error) throw error
    return { staff: data, previousStatus: existing.status }
  }

  const { data, error } = await adminClient
    .from('staff')
    .insert({
      ...values,
      invited_at: payload.status === 'invited' ? now : null,
      invitation_sent_at: payload.invitationSent ? now : null,
      created_by: payload.callerId,
    })
    .select('*')
    .single()

  if (error) throw error
  return { staff: data, previousStatus: null }
}

async function createOrLinkIdentity(
  adminClient: SupabaseClient,
  payload: {
    hotelId: string
    fullName: string
    email: string
    phone: string
    role: string
    callerId: string
    targetStaffId?: string | null
    appUrl: string
  },
) {
  let authUser = await findAuthUserByEmail(adminClient, payload.email)
  let invitationSent = false

  if (!authUser) {
    if (!payload.appUrl) {
      throw new Error('STAYQR_APP_URL is not configured for invitation redirects.')
    }

    const { data, error } = await adminClient.auth.admin.inviteUserByEmail(
      payload.email,
      {
        redirectTo: `${payload.appUrl}/auth/complete-invite`,
        data: {
          full_name: payload.fullName,
          stayqr_hotel_id: payload.hotelId,
          stayqr_role: payload.role,
        },
      },
    )

    if (error) throw error
    authUser = data.user
    invitationSent = true
  }

  if (!authUser) throw new Error('Supabase Auth did not return the staff user.')

  const identityStatus: 'active' | 'invited' = authUser.email_confirmed_at
    ? 'active'
    : 'invited'

  const wasBanned = isCurrentlyBanned(authUser)

  if (identityStatus === 'active' && wasBanned) {
    const { error } = await adminClient.auth.admin.updateUserById(authUser.id, {
      ban_duration: 'none',
    })
    if (error) throw error
  }

  try {
    const result = await upsertStaffIdentity(adminClient, {
      hotelId: payload.hotelId,
      authUserId: authUser.id,
      fullName: payload.fullName,
      email: payload.email,
      phone: payload.phone,
      role: payload.role,
      status: identityStatus,
      callerId: payload.callerId,
      invitationSent,
      targetStaffId: payload.targetStaffId,
    })

    await recordIdentityEvent(adminClient, {
      hotelId: payload.hotelId,
      staffId: result.staff.id,
      authUserId: authUser.id,
      eventType: invitationSent ? 'invited' : 'linked',
      previousStatus: result.previousStatus,
      newStatus: identityStatus,
      actorUserId: payload.callerId,
      details: {
        invitation_sent: invitationSent,
        verified_identity: Boolean(authUser.email_confirmed_at),
      },
    })

    return {
      authUser,
      staff: result.staff,
      identityStatus,
      invitationSent,
    }
  } catch (error) {
    if (invitationSent) {
      await adminClient.auth.admin.deleteUser(authUser.id).catch(() => undefined)
    } else if (wasBanned && identityStatus === 'active') {
      await adminClient.auth.admin
        .updateUserById(authUser.id, { ban_duration: '876000h' })
        .catch(() => undefined)
    }
    throw error
  }
}

Deno.serve(async (request) => {
  if (request.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders(request) })
  }

  if (request.method !== 'POST') {
    return json(request, 405, { error: 'Method not allowed.' })
  }

  try {
    const supabaseUrl = Deno.env.get('SUPABASE_URL')
    const anonKey = Deno.env.get('SUPABASE_ANON_KEY')
    const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')
    const appUrl = (Deno.env.get('STAYQR_APP_URL') || '').replace(/\/$/, '')

    if (!supabaseUrl || !anonKey || !serviceRoleKey) {
      throw new Error('The Edge Function authentication environment is incomplete.')
    }

    const authorization = request.headers.get('Authorization') || ''
    const token = authorization.replace(/^Bearer\s+/i, '').trim()

    if (!token) return json(request, 401, { error: 'Authentication is required.' })

    // Gateway JWT verification is disabled for ES256 compatibility. The caller
    // is still authenticated against the Supabase Auth server here before any
    // privileged service-role operation is performed.
    const authClient = createClient(supabaseUrl, anonKey, {
      auth: {
        autoRefreshToken: false,
        persistSession: false,
        detectSessionInUrl: false,
      },
    })

    const adminClient = createClient(supabaseUrl, serviceRoleKey, {
      auth: {
        autoRefreshToken: false,
        persistSession: false,
        detectSessionInUrl: false,
      },
    })

    const {
      data: { user: caller },
      error: callerError,
    } = await authClient.auth.getUser(token)

    if (callerError || !caller) {
      return json(request, 401, {
        error: 'Your StayQR session is invalid or expired.',
      })
    }

    const body = (await request.json()) as StaffRequest
    const action = body.action
    const hotelId = body.hotelId

    if (!action || !['invite', 'link', 'update', 'status', 'archive'].includes(action)) {
      return json(request, 400, { error: 'A valid staff action is required.' })
    }

    if (!isUuid(hotelId)) {
      return json(request, 400, { error: 'A valid hotel is required.' })
    }

    await assertCallerCanManage(adminClient, caller.id, hotelId as string)

    if (action === 'invite') {
      const fullName = String(body.fullName || '').trim()
      const email = normalizeEmail(body.email)
      const phone = String(body.phone || '').trim()
      const role = normalizeRole(body.role)

      if (!fullName || !email || !email.includes('@') || !allowedRoles.has(role)) {
        return json(request, 400, {
          error: 'Name, valid email and allowed role are required.',
        })
      }

      const result = await createOrLinkIdentity(adminClient, {
        hotelId: hotelId as string,
        fullName,
        email,
        phone,
        role,
        callerId: caller.id,
        appUrl,
      })

      return json(request, 200, {
        result: result.invitationSent
          ? 'Staff invitation sent.'
          : result.identityStatus === 'active'
            ? 'Existing verified identity linked to this hotel.'
            : 'Existing pending identity linked to this hotel.',
        staff: result.staff,
        invitationSent: result.invitationSent,
      })
    }

    if (!isUuid(body.staffId)) {
      return json(request, 400, { error: 'A valid staff member is required.' })
    }

    const { data: currentStaff, error: currentError } = await adminClient
      .from('staff')
      .select('*')
      .eq('id', body.staffId as string)
      .eq('hotel_id', hotelId as string)
      .single()

    if (currentError) throw currentError

    if (action === 'link') {
      if (currentStaff.auth_user_id) {
        return json(request, 400, {
          error: 'This staff profile already has a linked authentication identity.',
        })
      }

      const email = normalizeEmail(currentStaff.email)
      const role = normalizeRole(currentStaff.role)

      if (!email || !email.includes('@') || !allowedRoles.has(role)) {
        return json(request, 400, {
          error: 'The legacy staff profile needs a valid email and role before it can be linked.',
        })
      }

      const result = await createOrLinkIdentity(adminClient, {
        hotelId: hotelId as string,
        targetStaffId: currentStaff.id,
        fullName: currentStaff.full_name,
        email,
        phone: currentStaff.phone || '',
        role,
        callerId: caller.id,
        appUrl,
      })

      return json(request, 200, {
        result: result.invitationSent
          ? 'Identity invitation sent for the preserved staff profile.'
          : 'Existing Auth identity linked to the preserved staff profile.',
        staff: result.staff,
        invitationSent: result.invitationSent,
      })
    }

    if (action === 'archive') {
      if (currentStaff.auth_user_id) {
        return json(request, 400, {
          error: 'Linked identities must be disabled or suspended, not archived.',
        })
      }

      const now = new Date().toISOString()
      const { data, error } = await adminClient
        .from('staff')
        .update({
          status: 'inactive',
          disabled_at: currentStaff.disabled_at || now,
          identity_reconciliation_status: 'archived_unlinked',
          identity_reconciliation_note:
            'Legacy staff profile archived without login access.',
          identity_reconciled_at: now,
          updated_by: caller.id,
        })
        .eq('id', currentStaff.id)
        .eq('hotel_id', hotelId as string)
        .select('*')
        .single()

      if (error) throw error

      await recordIdentityEvent(adminClient, {
        hotelId: hotelId as string,
        staffId: currentStaff.id,
        eventType: 'archived',
        previousStatus: currentStaff.status,
        newStatus: 'inactive',
        actorUserId: caller.id,
      })

      return json(request, 200, {
        result: 'Unlinked legacy staff profile archived safely.',
        staff: data,
      })
    }

    if (action === 'update') {
      const fullName = String(body.fullName || '').trim()
      const phone = String(body.phone || '').trim()
      const role = normalizeRole(body.role)

      if (!fullName || !allowedRoles.has(role)) {
        return json(request, 400, {
          error: 'Name and an allowed role are required.',
        })
      }

      await assertOwnerContinuity(
        adminClient,
        hotelId as string,
        currentStaff.id,
        role,
        currentStaff.status,
      )

      const { data, error } = await adminClient
        .from('staff')
        .update({
          full_name: fullName,
          phone: phone || null,
          role,
          updated_by: caller.id,
        })
        .eq('id', currentStaff.id)
        .eq('hotel_id', hotelId as string)
        .select('*')
        .single()

      if (error) throw error

      await recordIdentityEvent(adminClient, {
        hotelId: hotelId as string,
        staffId: currentStaff.id,
        authUserId: currentStaff.auth_user_id,
        eventType: 'updated',
        previousStatus: currentStaff.status,
        newStatus: currentStaff.status,
        actorUserId: caller.id,
        details: { previous_role: currentStaff.role, new_role: role },
      })

      return json(request, 200, {
        result: 'Staff details updated.',
        staff: data,
      })
    }

    const status = String(body.status || '').trim().toLowerCase()

    if (!allowedStatuses.has(status)) {
      return json(request, 400, {
        error: 'Status must be active, inactive or suspended.',
      })
    }

    if (!currentStaff.auth_user_id) {
      return json(request, 400, {
        error: 'Send an identity invitation before activating this staff profile.',
      })
    }

    if (currentStaff.auth_user_id === caller.id && status !== 'active') {
      return json(request, 400, {
        error: 'You cannot disable your own active identity.',
      })
    }

    await assertOwnerContinuity(
      adminClient,
      hotelId as string,
      currentStaff.id,
      normalizeRole(currentStaff.role),
      status,
    )

    const authUser = await getAuthUserById(
      adminClient,
      currentStaff.auth_user_id,
    )
    const wasBanned = isCurrentlyBanned(authUser)
    const shouldBan =
      status !== 'active' &&
      !(await hasOtherActiveAccess(
        adminClient,
        currentStaff.auth_user_id,
        currentStaff.id,
      ))

    let authStateChanged = false

    if (status === 'active' && wasBanned) {
      const { error } = await adminClient.auth.admin.updateUserById(
        currentStaff.auth_user_id,
        { ban_duration: 'none' },
      )
      if (error) throw error
      authStateChanged = true
    } else if (shouldBan && !wasBanned) {
      const { error } = await adminClient.auth.admin.updateUserById(
        currentStaff.auth_user_id,
        { ban_duration: '876000h' },
      )
      if (error) throw error
      authStateChanged = true
    }

    try {
      const now = new Date().toISOString()
      const { data: updated, error: updateError } = await adminClient
        .from('staff')
        .update({
          status,
          disabled_at: status === 'active' ? null : now,
          accepted_at:
            status === 'active'
              ? currentStaff.accepted_at || now
              : currentStaff.accepted_at,
          updated_by: caller.id,
        })
        .eq('id', currentStaff.id)
        .eq('hotel_id', hotelId as string)
        .select('*')
        .single()

      if (updateError) throw updateError

      const eventType =
        status === 'active'
          ? 'activated'
          : status === 'suspended'
            ? 'suspended'
            : 'disabled'

      await recordIdentityEvent(adminClient, {
        hotelId: hotelId as string,
        staffId: currentStaff.id,
        authUserId: currentStaff.auth_user_id,
        eventType,
        previousStatus: currentStaff.status,
        newStatus: status,
        actorUserId: caller.id,
        details: {
          auth_ban_changed: authStateChanged,
          auth_ban_required: shouldBan,
          has_other_active_access: status !== 'active' && !shouldBan,
        },
      })

      return json(request, 200, {
        result:
          status === 'active'
            ? 'Staff access activated.'
            : status === 'suspended'
              ? 'Staff identity suspended immediately.'
              : 'Staff access disabled immediately.',
        staff: updated,
      })
    } catch (error) {
      if (authStateChanged) {
        if (status === 'active' && wasBanned) {
          await adminClient.auth.admin
            .updateUserById(currentStaff.auth_user_id, {
              ban_duration: '876000h',
            })
            .catch(() => undefined)
        } else if (shouldBan && !wasBanned) {
          await adminClient.auth.admin
            .updateUserById(currentStaff.auth_user_id, {
              ban_duration: 'none',
            })
            .catch(() => undefined)
        }
      }
      throw error
    }
  } catch (error) {
    console.error('manage-staff-user error', error)
    return json(request, 400, {
      error: error instanceof Error ? error.message : 'Staff action failed.',
    })
  }
})
