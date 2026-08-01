import { useCallback, useEffect, useMemo, useState } from 'react'
import { supabase } from '../../lib/supabase'
import {
  addAmenity,
  addMenuItem,
  addRequestType,
  bootstrapHotel,
  clearOnboardingDraft,
  configureHotelInventory,
  fetchActiveSubscriptionPlans,
  fetchHotelSetupSnapshot,
  getHotelOnboardingReadiness,
  getOrCreateOnboardingRequestId,
  importHotelRooms,
  loadOnboardingDraft,
  parseRoomsCsv,
  refreshHotelOnboardingReadiness,
  resetOnboardingRequestId,
  saveHotelOnboardingStep,
  saveOnboardingDraft,
  seedHotelConfigurationDefaults,
  updateAmenity,
  updateHotelBasics,
  updateRequestType,
} from '../../lib/onboarding'
import './HotelOnboarding.css'

const STEPS = [
  { id: 'hotel', label: 'Hotel & Policies' },
  { id: 'inventory', label: 'Types, Floors & Rates' },
  { id: 'rooms', label: 'Rooms Import' },
  { id: 'operations', label: 'Guest Operations' },
  { id: 'review', label: 'Readiness' },
]

const DEFAULT_BASIC_FORM = {
  hotel_name: '',
  owner_name: '',
  contact_email: '',
  phone: '',
  address: '',
  city: '',
  state: '',
  location: '',
  website: '',
  tax_registration_number: '',
  timezone: 'Asia/Kolkata',
  currency_code: 'INR',
  default_tax_percent: '0',
  prices_include_tax: false,
  checkin_time: '14:00',
  checkout_time: '11:00',
  cancellation_policy: '',
  house_rules: '',
  terms_and_conditions: '',
  invoice_notes: '',
  plan_id: '',
  trial_days: '14',
}

const DEFAULT_INVENTORY = {
  floors: [
    {
      name: 'Ground Floor',
      code: 'DEFAULT',
      floor_number: '0',
      sort_order: '0',
      is_active: true,
    },
  ],
  roomTypes: [
    {
      name: 'Standard Room',
      code: 'STD',
      description: '',
      base_occupancy: '1',
      max_adults: '2',
      max_children: '1',
      max_occupancy: '3',
      base_rate: '2500',
      extra_adult_rate: '500',
      extra_child_rate: '250',
      sort_order: '10',
      is_active: true,
    },
  ],
  ratePlans: [
    {
      name: 'Standard Best Available Rate',
      code: 'STD-BAR',
      room_type_code: 'STD',
      meal_plan: 'room_only',
      base_rate: '2500',
      extra_adult_rate: '500',
      extra_child_rate: '250',
      minimum_stay: '1',
      maximum_stay: '',
      cancellation_policy: '',
      is_refundable: true,
      priority: '10',
      is_active: true,
    },
  ],
}

const DEFAULT_CSV = `room_number,room_type_code,floor_code,status
101,STD,DEFAULT,available
102,STD,DEFAULT,available`

export default function HotelOnboarding({
  session,
  tenantContext,
  onHotelReady,
  standalone = false,
}) {
  const user = session?.user || tenantContext?.user || null
  const selectedHotel = tenantContext?.selectedHotel || null
  const [mode, setMode] = useState(selectedHotel ? 'existing' : 'new')
  const [targetHotelId, setTargetHotelId] = useState(
    selectedHotel?.id || null
  )
  const [activeStep, setActiveStep] = useState(0)
  const [plans, setPlans] = useState([])
  const [snapshot, setSnapshot] = useState(null)
  const [readiness, setReadiness] = useState(null)
  const [basicForm, setBasicForm] = useState(() => {
    const draft = user?.id ? loadOnboardingDraft(user.id) : null
    return {
      ...DEFAULT_BASIC_FORM,
      ...(draft?.basicForm || {}),
      owner_name:
        draft?.basicForm?.owner_name ||
        user?.user_metadata?.full_name ||
        '',
      contact_email:
        draft?.basicForm?.contact_email || user?.email || '',
    }
  })
  const [inventory, setInventory] = useState(DEFAULT_INVENTORY)
  const [csvText, setCsvText] = useState(DEFAULT_CSV)
  const [menuForm, setMenuForm] = useState({
    item_name: '',
    category_id: '',
    price: '',
    description: '',
  })
  const [amenityForm, setAmenityForm] = useState({
    name: '',
    code: '',
    category: 'general',
    description: '',
    icon: '',
  })
  const [requestForm, setRequestForm] = useState({
    name: '',
    code: '',
    description: '',
    default_priority: 'normal',
    default_estimated_minutes: '15',
  })
  const [loading, setLoading] = useState(true)
  const [busy, setBusy] = useState('')
  const [error, setError] = useState('')
  const [success, setSuccess] = useState('')
  const [hydratedHotelId, setHydratedHotelId] = useState(null)

  const isPlatformAdmin = Boolean(tenantContext?.isPlatformAdmin)
  const hotelId =
    mode === 'new'
      ? targetHotelId
      : targetHotelId || selectedHotel?.id || null

  const loadSnapshot = useCallback(async (id = hotelId) => {
    if (!id) {
      setSnapshot(null)
      setReadiness(null)
      return null
    }

    const [nextSnapshot, nextReadiness] = await Promise.all([
      fetchHotelSetupSnapshot(id),
      getHotelOnboardingReadiness(id),
    ])

    setSnapshot(nextSnapshot)
    setReadiness(nextReadiness)
    return nextSnapshot
  }, [hotelId])

  useEffect(() => {
    let cancelled = false

    async function initialize() {
      setLoading(true)
      setError('')

      try {
        const planRows = await fetchActiveSubscriptionPlans()
        if (cancelled) return

        setPlans(planRows)
        setBasicForm((current) => ({
          ...current,
          plan_id: current.plan_id || planRows[0]?.id || '',
        }))

        if (hotelId) {
          await loadSnapshot(hotelId)
        }
      } catch (loadError) {
        if (!cancelled) {
          setError(loadError?.message || 'StayQR could not load onboarding.')
        }
      } finally {
        if (!cancelled) setLoading(false)
      }
    }

    initialize()

    return () => {
      cancelled = true
    }
  }, [hotelId, loadSnapshot])

  useEffect(() => {
    if (!snapshot?.hotel || hydratedHotelId === snapshot.hotel.id) return

    const hotel = snapshot.hotel
    const settings = snapshot.settings || {}
    const onboarding = snapshot.onboarding || {}

    setBasicForm((current) => ({
      ...current,
      hotel_name: hotel.hotel_name || '',
      owner_name: hotel.owner_name || current.owner_name || '',
      contact_email: hotel.email || current.contact_email || '',
      phone: hotel.phone || '',
      address: hotel.address || '',
      city: hotel.city || '',
      state: hotel.state || '',
      location: hotel.location || '',
      website: hotel.website || '',
      tax_registration_number:
        settings.tax_registration_number || hotel.gst_number || '',
      timezone: hotel.timezone || 'Asia/Kolkata',
      currency_code: hotel.currency_code || 'INR',
      default_tax_percent: String(settings.default_tax_percent ?? 0),
      prices_include_tax: Boolean(settings.prices_include_tax),
      checkin_time: normalizeTime(settings.checkin_time, '14:00'),
      checkout_time: normalizeTime(settings.checkout_time, '11:00'),
      cancellation_policy: settings.cancellation_policy || '',
      house_rules: settings.house_rules || '',
      terms_and_conditions: settings.terms_and_conditions || '',
      invoice_notes: settings.invoice_notes || '',
      plan_id: snapshot.subscription?.plan_id || current.plan_id || '',
    }))

    setInventory({
      floors:
        snapshot.floors.length > 0
          ? snapshot.floors.map((floor) => ({
              name: floor.name || '',
              code: floor.code || '',
              floor_number:
                floor.floor_number === null || floor.floor_number === undefined
                  ? ''
                  : String(floor.floor_number),
              sort_order: String(floor.sort_order ?? 0),
              is_active: floor.is_active !== false,
            }))
          : DEFAULT_INVENTORY.floors,
      roomTypes:
        snapshot.roomTypes.length > 0
          ? snapshot.roomTypes.map((roomType) => ({
              name: roomType.name || '',
              code: roomType.code || '',
              description: roomType.description || '',
              base_occupancy: String(roomType.base_occupancy ?? 1),
              max_adults: String(roomType.max_adults ?? 2),
              max_children: String(roomType.max_children ?? 1),
              max_occupancy: String(roomType.max_occupancy ?? 3),
              base_rate: String(roomType.base_rate ?? 0),
              extra_adult_rate: String(roomType.extra_adult_rate ?? 0),
              extra_child_rate: String(roomType.extra_child_rate ?? 0),
              sort_order: String(roomType.sort_order ?? 0),
              is_active: roomType.is_active !== false,
            }))
          : DEFAULT_INVENTORY.roomTypes,
      ratePlans:
        snapshot.ratePlans.length > 0
          ? snapshot.ratePlans.map((rate) => ({
              name: rate.name || '',
              code: rate.code || '',
              room_type_code:
                snapshot.roomTypes.find(
                  (roomType) => roomType.id === rate.room_type_id
                )?.code || '',
              meal_plan: rate.meal_plan || 'room_only',
              base_rate: String(rate.base_rate ?? 0),
              extra_adult_rate: String(rate.extra_adult_rate ?? 0),
              extra_child_rate: String(rate.extra_child_rate ?? 0),
              minimum_stay: String(rate.minimum_stay ?? 1),
              maximum_stay:
                rate.maximum_stay === null || rate.maximum_stay === undefined
                  ? ''
                  : String(rate.maximum_stay),
              cancellation_policy: rate.cancellation_policy || '',
              is_refundable: rate.is_refundable !== false,
              priority: String(rate.priority ?? 100),
              is_active: rate.is_active !== false,
            }))
          : DEFAULT_INVENTORY.ratePlans,
    })

    setActiveStep(stepIndexFromOnboarding(onboarding.current_step))
    setHydratedHotelId(snapshot.hotel.id)
  }, [hydratedHotelId, snapshot])

  useEffect(() => {
    if (!user?.id || mode !== 'new' || hotelId) return
    saveOnboardingDraft(user.id, { basicForm })
  }, [basicForm, hotelId, mode, user?.id])

  const checklist = useMemo(
    () => readiness?.checklist || {},
    [readiness]
  )
  const completionCount = useMemo(
    () => Object.values(checklist).filter(Boolean).length,
    [checklist]
  )
  const totalChecks = Object.keys(checklist).length

  async function runAction(actionName, action) {
    setBusy(actionName)
    setError('')
    setSuccess('')

    try {
      const result = await action()
      return result
    } catch (actionError) {
      console.error(`${actionName} failed:`, actionError)
      setError(actionError?.message || 'The StayQR action could not be completed.')
      return null
    } finally {
      setBusy('')
    }
  }

  async function handleHotelSubmit(event) {
    event.preventDefault()

    if (!basicForm.hotel_name.trim() || !basicForm.owner_name.trim()) {
      setError('Hotel name and owner name are required.')
      return
    }

    if (!basicForm.contact_email.trim()) {
      setError('Contact email is required.')
      return
    }

    if (mode === 'new' && !basicForm.plan_id) {
      setError('Select an active StayQR plan.')
      return
    }

    if (mode === 'new') {
      const result = await runAction('Creating hotel', async () => {
        const requestId = getOrCreateOnboardingRequestId(user?.id)
        return bootstrapHotel({
          request_id: requestId,
          hotel_name: basicForm.hotel_name,
          owner_name: basicForm.owner_name,
          contact_email: basicForm.contact_email,
          phone: basicForm.phone,
          address: basicForm.address,
          city: basicForm.city,
          state: basicForm.state,
          location: basicForm.location,
          website: basicForm.website,
          tax_registration_number: basicForm.tax_registration_number,
          timezone: basicForm.timezone,
          currency_code: basicForm.currency_code,
          default_tax_percent: basicForm.default_tax_percent,
          prices_include_tax: basicForm.prices_include_tax,
          checkin_time: basicForm.checkin_time,
          checkout_time: basicForm.checkout_time,
          cancellation_policy: basicForm.cancellation_policy,
          house_rules: basicForm.house_rules,
          terms_and_conditions: basicForm.terms_and_conditions,
          invoice_notes: basicForm.invoice_notes,
          plan_id: basicForm.plan_id,
          trial_days: basicForm.trial_days,
        })
      })

      if (!result?.hotel_id) return

      setTargetHotelId(result.hotel_id)
      setSuccess(
        result.idempotent
          ? 'The existing onboarding request was resumed.'
          : 'Hotel tenant, owner, settings and trial were created atomically.'
      )
      setActiveStep(1)

      if (onHotelReady) {
        await onHotelReady(result.hotel_id)
      }
      return
    }

    const result = await runAction('Saving hotel settings', async () => {
      await updateHotelBasics(hotelId, basicForm)
      await saveHotelOnboardingStep(hotelId, 'hotel_details', {
        complete: true,
        hotel_name: basicForm.hotel_name,
      })
      await saveHotelOnboardingStep(hotelId, 'policies', {
        complete: true,
        default_tax_percent: Number(basicForm.default_tax_percent || 0),
      })
      return loadSnapshot(hotelId)
    })

    if (result) {
      setSuccess('Hotel details, tax settings and policies were saved.')
      setActiveStep(1)
    }
  }

  async function handleInventorySubmit(event) {
    event.preventDefault()

    if (!hotelId) return

    const result = await runAction('Configuring inventory', async () => {
      const response = await configureHotelInventory(hotelId, {
        floors: inventory.floors.map(serializeFloor),
        room_types: inventory.roomTypes.map(serializeRoomType),
        rate_plans: inventory.ratePlans.map((rate) =>
          serializeRatePlan(rate, basicForm.currency_code)
        ),
      })

      await saveHotelOnboardingStep(hotelId, 'room_types', {
        complete: true,
        configured_at: new Date().toISOString(),
      })

      await loadSnapshot(hotelId)
      return response
    })

    if (result) {
      setSuccess('Floors, room types and rates were configured safely.')
      setActiveStep(2)
    }
  }

  async function handleRoomImport(event) {
    event.preventDefault()

    if (!hotelId) return

    const result = await runAction('Importing rooms', async () => {
      const rooms = parseRoomsCsv(csvText)
      const response = await importHotelRooms(hotelId, { rooms })

      await saveHotelOnboardingStep(hotelId, 'floors_rooms', {
        complete: true,
        imported_rows: rooms.length,
      })

      await loadSnapshot(hotelId)
      return response
    })

    if (result) {
      setSuccess(
        `Room import complete: ${result.inserted || 0} inserted, ${result.updated || 0} updated and ${result.unchanged || 0} unchanged.`
      )
      setActiveStep(3)
    }
  }

  async function handleSeedDefaults() {
    if (!hotelId) return

    const result = await runAction('Restoring defaults', async () => {
      const response = await seedHotelConfigurationDefaults(hotelId)
      await loadSnapshot(hotelId)
      return response
    })

    if (result) {
      setSuccess('Amenity, request and menu-category defaults are ready.')
    }
  }

  async function handleAddMenuItem(event) {
    event.preventDefault()

    const category = snapshot?.menuCategories.find(
      (item) => item.id === menuForm.category_id
    )

    if (!category || !menuForm.item_name.trim() || menuForm.price === '') {
      setError('Select a category and enter the menu item name and price.')
      return
    }

    const result = await runAction('Adding menu item', async () => {
      await addMenuItem(hotelId, {
        ...menuForm,
        category_name: category.name,
      })
      await loadSnapshot(hotelId)
      return true
    })

    if (result) {
      setMenuForm({
        item_name: '',
        category_id: category.id,
        price: '',
        description: '',
      })
      setSuccess('Starter menu item added.')
    }
  }

  async function handleAddAmenity(event) {
    event.preventDefault()
    if (!amenityForm.name.trim()) {
      setError('Amenity name is required.')
      return
    }

    const result = await runAction('Adding amenity', async () => {
      await addAmenity(hotelId, amenityForm)
      await loadSnapshot(hotelId)
      return true
    })

    if (result) {
      setAmenityForm({
        name: '',
        code: '',
        category: 'general',
        description: '',
        icon: '',
      })
      setSuccess('Amenity added.')
    }
  }

  async function handleAddRequestType(event) {
    event.preventDefault()
    if (!requestForm.name.trim()) {
      setError('Request category name is required.')
      return
    }

    const result = await runAction('Adding request category', async () => {
      await addRequestType(hotelId, requestForm)
      await loadSnapshot(hotelId)
      return true
    })

    if (result) {
      setRequestForm({
        name: '',
        code: '',
        description: '',
        default_priority: 'normal',
        default_estimated_minutes: '15',
      })
      setSuccess('Request category added.')
    }
  }

  async function handleToggleAmenity(amenity) {
    const result = await runAction('Updating amenity', async () => {
      await updateAmenity(hotelId, amenity.id, {
        is_active: !amenity.is_active,
      })
      await loadSnapshot(hotelId)
      return true
    })

    if (result) setSuccess('Amenity status updated.')
  }

  async function handleToggleRequestType(requestType) {
    const result = await runAction('Updating request category', async () => {
      await updateRequestType(hotelId, requestType.id, {
        is_active: !requestType.is_active,
      })
      await loadSnapshot(hotelId)
      return true
    })

    if (result) setSuccess('Request category status updated.')
  }

  async function handleCompleteOperations() {
    const activeAmenities = snapshot?.amenities.filter(
      (item) => item.is_active
    ).length
    const activeRequestTypes = snapshot?.requestTypes.filter(
      (item) => item.is_active
    ).length
    const menuItems = snapshot?.menuItems.length || 0

    if (!activeAmenities || !activeRequestTypes || !menuItems) {
      setError(
        'Keep at least one active amenity, one active request category and one menu item.'
      )
      return
    }

    const result = await runAction('Completing guest operations', async () => {
      await saveHotelOnboardingStep(hotelId, 'amenities', {
        complete: true,
        active_count: activeAmenities,
      })
      await saveHotelOnboardingStep(hotelId, 'request_categories', {
        complete: true,
        active_count: activeRequestTypes,
      })
      await saveHotelOnboardingStep(hotelId, 'menu', {
        complete: true,
        item_count: menuItems,
      })
      await saveHotelOnboardingStep(hotelId, 'invoice', {
        complete: true,
      })
      await saveHotelOnboardingStep(hotelId, 'subscription', {
        complete: true,
      })
      const nextReadiness = await refreshHotelOnboardingReadiness(hotelId)
      await loadSnapshot(hotelId)
      return nextReadiness
    })

    if (result) {
      setReadiness(result)
      setSuccess('Guest operations and commercial defaults are complete.')
      setActiveStep(4)
    }
  }

  async function handleRefreshReadiness() {
    if (!hotelId) return

    const result = await runAction('Refreshing readiness', async () => {
      const nextReadiness = await refreshHotelOnboardingReadiness(hotelId)
      await loadSnapshot(hotelId)
      return nextReadiness
    })

    if (result) {
      setReadiness(result)
      setSuccess('Operational readiness has been refreshed.')
    }
  }

  async function handleFinishOnboarding() {
    if (!readiness?.ready) {
      setError('Complete every missing readiness item before finishing.')
      return
    }

    const result = await runAction('Completing onboarding', async () => {
      const response = await saveHotelOnboardingStep(hotelId, 'review', {
        complete: true,
        completed_from: 'day8_frontend_wizard',
      })
      await loadSnapshot(hotelId)
      return response
    })

    if (result) {
      clearOnboardingDraft(user?.id)
      resetOnboardingRequestId(user?.id)
      setSuccess(
        'Hotel onboarding is complete. The property is operational and QR-ready.'
      )
    }
  }

  function switchToNewHotel() {
    setMode('new')
    setTargetHotelId(null)
    setSnapshot(null)
    setReadiness(null)
    setHydratedHotelId(null)
    setActiveStep(0)
    setError('')
    setSuccess('')
    setInventory(DEFAULT_INVENTORY)
    setCsvText(DEFAULT_CSV)
    resetOnboardingRequestId(user?.id)
    setBasicForm({
      ...DEFAULT_BASIC_FORM,
      owner_name: user?.user_metadata?.full_name || '',
      contact_email: user?.email || '',
      plan_id: plans[0]?.id || '',
    })
  }

  function switchToSelectedHotel() {
    if (!selectedHotel?.id) return
    setMode('existing')
    setTargetHotelId(selectedHotel.id)
    setHydratedHotelId(null)
    setActiveStep(0)
    setError('')
    setSuccess('')
  }

  async function handleSignOut() {
    setBusy('Signing out')
    setError('')

    const { error: signOutError } = await supabase.auth.signOut()

    if (signOutError) {
      setError(signOutError.message)
      setBusy('')
      return
    }

    window.location.replace('/')
  }

  if (loading) {
    return (
      <div className={`onboarding-shell ${standalone ? 'standalone' : ''}`}>
        <div className="onboarding-loading-card">
          <span className="onboarding-spinner" />
          <div>
            <strong>Loading hotel onboarding</strong>
            <span>Checking plans, tenant access and saved progress…</span>
          </div>
        </div>
      </div>
    )
  }

  return (
    <div className={`onboarding-shell ${standalone ? 'standalone' : ''}`}>
      <header className="onboarding-hero">
        <div>
          <span className="onboarding-kicker">StayQR v1.0 · Day 8</span>
          <h1>Hotel Onboarding & Configuration</h1>
          <p>
            Move a property from account creation to an operational,
            tenant-isolated and QR-ready hotel without manual database edits.
          </p>
        </div>

        <div className="onboarding-mode-actions">
          {standalone && (
            <button
              type="button"
              className="ghost-button"
              onClick={handleSignOut}
              disabled={Boolean(busy)}
            >
              Sign out
            </button>
          )}
          {selectedHotel && mode === 'new' && (
            <button type="button" className="ghost-button" onClick={switchToSelectedHotel}>
              Continue {selectedHotel.hotel_name}
            </button>
          )}
          {isPlatformAdmin && mode === 'existing' && (
            <button type="button" className="ghost-button" onClick={switchToNewHotel}>
              Create another hotel
            </button>
          )}
        </div>
      </header>

      {hotelId && (
        <section className="onboarding-context-card">
          <div>
            <span>Active setup</span>
            <strong>{snapshot?.hotel?.hotel_name || selectedHotel?.hotel_name}</strong>
          </div>
          <div>
            <span>Hotel slug</span>
            <strong>{snapshot?.hotel?.slug || selectedHotel?.slug || 'Pending'}</strong>
          </div>
          <div>
            <span>Progress</span>
            <strong>{completionCount}/{totalChecks || 13} readiness checks</strong>
          </div>
          <div>
            <span>Status</span>
            <strong className={readiness?.ready ? 'ready-text' : 'warning-text'}>
              {readiness?.ready ? 'Operational' : 'Setup in progress'}
            </strong>
          </div>
        </section>
      )}

      <nav className="onboarding-steps" aria-label="Onboarding steps">
        {STEPS.map((step, index) => {
          const disabled = !hotelId && index > 0
          return (
            <button
              key={step.id}
              type="button"
              disabled={disabled}
              className={`${activeStep === index ? 'active' : ''} ${
                index < activeStep ? 'complete' : ''
              }`}
              onClick={() => !disabled && setActiveStep(index)}
            >
              <span>{index + 1}</span>
              <strong>{step.label}</strong>
            </button>
          )
        })}
      </nav>

      {error && <div className="onboarding-alert error">{error}</div>}
      {success && <div className="onboarding-alert success">{success}</div>}

      <main className="onboarding-panel">
        {activeStep === 0 && (
          <HotelStep
            mode={mode}
            form={basicForm}
            setForm={setBasicForm}
            plans={plans}
            busy={busy}
            onSubmit={handleHotelSubmit}
          />
        )}

        {activeStep === 1 && (
          <InventoryStep
            inventory={inventory}
            setInventory={setInventory}
            currency={basicForm.currency_code}
            busy={busy}
            onSubmit={handleInventorySubmit}
          />
        )}

        {activeStep === 2 && (
          <RoomsStep
            csvText={csvText}
            setCsvText={setCsvText}
            snapshot={snapshot}
            busy={busy}
            onSubmit={handleRoomImport}
          />
        )}

        {activeStep === 3 && (
          <OperationsStep
            snapshot={snapshot}
            menuForm={menuForm}
            setMenuForm={setMenuForm}
            amenityForm={amenityForm}
            setAmenityForm={setAmenityForm}
            requestForm={requestForm}
            setRequestForm={setRequestForm}
            busy={busy}
            onSeedDefaults={handleSeedDefaults}
            onAddMenuItem={handleAddMenuItem}
            onAddAmenity={handleAddAmenity}
            onAddRequestType={handleAddRequestType}
            onToggleAmenity={handleToggleAmenity}
            onToggleRequestType={handleToggleRequestType}
            onComplete={handleCompleteOperations}
          />
        )}

        {activeStep === 4 && (
          <ReadinessStep
            readiness={readiness}
            snapshot={snapshot}
            busy={busy}
            onRefresh={handleRefreshReadiness}
            onFinish={handleFinishOnboarding}
          />
        )}
      </main>
    </div>
  )
}

function HotelStep({ mode, form, setForm, plans, busy, onSubmit }) {
  const setField = (field, value) => {
    setForm((current) => ({ ...current, [field]: value }))
  }

  return (
    <form className="onboarding-form" onSubmit={onSubmit}>
      <SectionHeader
        eyebrow={mode === 'new' ? 'Atomic registration' : 'Hotel configuration'}
        title={mode === 'new' ? 'Create the hotel tenant' : 'Hotel details and policies'}
        description="Timezone, currency, tax and property policies are saved as hotel-owned configuration."
      />

      <div className="form-grid three-columns">
        <Field label="Hotel name" required>
          <input value={form.hotel_name} onChange={(event) => setField('hotel_name', event.target.value)} />
        </Field>
        <Field label="Owner name" required>
          <input value={form.owner_name} onChange={(event) => setField('owner_name', event.target.value)} />
        </Field>
        <Field label="Contact email" required>
          <input type="email" value={form.contact_email} onChange={(event) => setField('contact_email', event.target.value)} />
        </Field>
        <Field label="Phone">
          <input value={form.phone} onChange={(event) => setField('phone', event.target.value)} />
        </Field>
        <Field label="City">
          <input value={form.city} onChange={(event) => setField('city', event.target.value)} />
        </Field>
        <Field label="State">
          <input value={form.state} onChange={(event) => setField('state', event.target.value)} />
        </Field>
        <Field label="Address" wide>
          <input value={form.address} onChange={(event) => setField('address', event.target.value)} />
        </Field>
        <Field label="Website">
          <input value={form.website} onChange={(event) => setField('website', event.target.value)} placeholder="https://" />
        </Field>
        <Field label="Timezone">
          <select value={form.timezone} onChange={(event) => setField('timezone', event.target.value)}>
            <option value="Asia/Kolkata">Asia/Kolkata</option>
            <option value="Asia/Dubai">Asia/Dubai</option>
            <option value="Europe/London">Europe/London</option>
            <option value="America/New_York">America/New_York</option>
          </select>
        </Field>
        <Field label="Currency">
          <select value={form.currency_code} onChange={(event) => setField('currency_code', event.target.value)}>
            <option value="INR">INR</option>
            <option value="USD">USD</option>
            <option value="AED">AED</option>
            <option value="GBP">GBP</option>
            <option value="EUR">EUR</option>
          </select>
        </Field>
        <Field label="Tax registration number">
          <input value={form.tax_registration_number} onChange={(event) => setField('tax_registration_number', event.target.value)} />
        </Field>
        <Field label="Default tax %">
          <input type="number" min="0" max="100" step="0.001" value={form.default_tax_percent} onChange={(event) => setField('default_tax_percent', event.target.value)} />
        </Field>
        <Field label="Check-in time">
          <input type="time" value={form.checkin_time} onChange={(event) => setField('checkin_time', event.target.value)} />
        </Field>
        <Field label="Checkout time">
          <input type="time" value={form.checkout_time} onChange={(event) => setField('checkout_time', event.target.value)} />
        </Field>
        <Field label="Prices include tax">
          <select value={String(form.prices_include_tax)} onChange={(event) => setField('prices_include_tax', event.target.value === 'true')}>
            <option value="false">No</option>
            <option value="true">Yes</option>
          </select>
        </Field>
        {mode === 'new' && (
          <>
            <Field label="StayQR plan" required>
              <select value={form.plan_id} onChange={(event) => setField('plan_id', event.target.value)}>
                <option value="">Select plan</option>
                {plans.map((plan) => (
                  <option key={plan.id} value={plan.id}>
                    {plan.plan_name} · ₹{Number(plan.price_monthly || 0).toLocaleString('en-IN')}/month · {plan.max_rooms} rooms
                  </option>
                ))}
              </select>
            </Field>
            <Field label="Trial days">
              <input type="number" min="1" max="30" value={form.trial_days} onChange={(event) => setField('trial_days', event.target.value)} />
            </Field>
          </>
        )}
      </div>

      <div className="form-grid two-columns policy-grid">
        <Field label="Cancellation policy">
          <textarea value={form.cancellation_policy} onChange={(event) => setField('cancellation_policy', event.target.value)} />
        </Field>
        <Field label="House rules">
          <textarea value={form.house_rules} onChange={(event) => setField('house_rules', event.target.value)} />
        </Field>
        <Field label="Terms and conditions">
          <textarea value={form.terms_and_conditions} onChange={(event) => setField('terms_and_conditions', event.target.value)} />
        </Field>
        <Field label="Invoice notes">
          <textarea value={form.invoice_notes} onChange={(event) => setField('invoice_notes', event.target.value)} />
        </Field>
      </div>

      <div className="panel-actions">
        <button className="primary-button" disabled={Boolean(busy)}>
          {busy || (mode === 'new' ? 'Create hotel & start trial' : 'Save and continue')}
        </button>
      </div>
    </form>
  )
}

function InventoryStep({ inventory, setInventory, currency, busy, onSubmit }) {
  const updateList = (key, index, field, value) => {
    setInventory((current) => ({
      ...current,
      [key]: current[key].map((item, itemIndex) =>
        itemIndex === index ? { ...item, [field]: value } : item
      ),
    }))
  }

  const removeListItem = (key, index) => {
    setInventory((current) => ({
      ...current,
      [key]: current[key].filter((_, itemIndex) => itemIndex !== index),
    }))
  }

  const addFloor = () => {
    setInventory((current) => ({
      ...current,
      floors: [
        ...current.floors,
        {
          name: '',
          code: '',
          floor_number: '',
          sort_order: String(current.floors.length * 10),
          is_active: true,
        },
      ],
    }))
  }

  const addRoomType = () => {
    setInventory((current) => ({
      ...current,
      roomTypes: [
        ...current.roomTypes,
        {
          ...DEFAULT_INVENTORY.roomTypes[0],
          name: '',
          code: '',
          sort_order: String(current.roomTypes.length * 10 + 10),
        },
      ],
    }))
  }

  const addRatePlan = () => {
    setInventory((current) => ({
      ...current,
      ratePlans: [
        ...current.ratePlans,
        {
          ...DEFAULT_INVENTORY.ratePlans[0],
          name: '',
          code: '',
          room_type_code: current.roomTypes[0]?.code || '',
          priority: String(current.ratePlans.length * 10 + 10),
        },
      ],
    }))
  }

  return (
    <form className="onboarding-form" onSubmit={onSubmit}>
      <SectionHeader
        eyebrow="Inventory foundation"
        title="Configure floors, room types and rates"
        description="The entire inventory payload is validated and applied by one hotel-scoped server transaction."
      />

      <ConfigSection title="Floors" actionLabel="Add floor" onAction={addFloor}>
        {inventory.floors.map((floor, index) => (
          <div className="config-row floor-row" key={`${floor.code}-${index}`}>
            <input placeholder="Floor name" value={floor.name} onChange={(event) => updateList('floors', index, 'name', event.target.value)} required />
            <input placeholder="Code" value={floor.code} onChange={(event) => updateList('floors', index, 'code', event.target.value.toUpperCase())} required />
            <input placeholder="Floor no." type="number" value={floor.floor_number} onChange={(event) => updateList('floors', index, 'floor_number', event.target.value)} />
            <button type="button" className="danger-link" disabled={inventory.floors.length === 1} onClick={() => removeListItem('floors', index)}>Remove</button>
          </div>
        ))}
      </ConfigSection>

      <ConfigSection title="Room types" actionLabel="Add room type" onAction={addRoomType}>
        {inventory.roomTypes.map((roomType, index) => (
          <div className="config-card" key={`${roomType.code}-${index}`}>
            <div className="config-card-header">
              <strong>Room type {index + 1}</strong>
              <button type="button" className="danger-link" disabled={inventory.roomTypes.length === 1} onClick={() => removeListItem('roomTypes', index)}>Remove</button>
            </div>
            <div className="form-grid four-columns compact-grid">
              <Field label="Name"><input value={roomType.name} onChange={(event) => updateList('roomTypes', index, 'name', event.target.value)} required /></Field>
              <Field label="Code"><input value={roomType.code} onChange={(event) => updateList('roomTypes', index, 'code', event.target.value.toUpperCase())} required /></Field>
              <Field label={`Base rate (${currency})`}><input type="number" min="0" value={roomType.base_rate} onChange={(event) => updateList('roomTypes', index, 'base_rate', event.target.value)} /></Field>
              <Field label="Max occupancy"><input type="number" min="1" value={roomType.max_occupancy} onChange={(event) => updateList('roomTypes', index, 'max_occupancy', event.target.value)} /></Field>
              <Field label="Max adults"><input type="number" min="1" value={roomType.max_adults} onChange={(event) => updateList('roomTypes', index, 'max_adults', event.target.value)} /></Field>
              <Field label="Max children"><input type="number" min="0" value={roomType.max_children} onChange={(event) => updateList('roomTypes', index, 'max_children', event.target.value)} /></Field>
              <Field label="Extra adult"><input type="number" min="0" value={roomType.extra_adult_rate} onChange={(event) => updateList('roomTypes', index, 'extra_adult_rate', event.target.value)} /></Field>
              <Field label="Extra child"><input type="number" min="0" value={roomType.extra_child_rate} onChange={(event) => updateList('roomTypes', index, 'extra_child_rate', event.target.value)} /></Field>
            </div>
          </div>
        ))}
      </ConfigSection>

      <ConfigSection title="Rate plans" actionLabel="Add rate plan" onAction={addRatePlan}>
        {inventory.ratePlans.map((rate, index) => (
          <div className="config-card" key={`${rate.code}-${index}`}>
            <div className="config-card-header">
              <strong>Rate plan {index + 1}</strong>
              <button type="button" className="danger-link" disabled={inventory.ratePlans.length === 1} onClick={() => removeListItem('ratePlans', index)}>Remove</button>
            </div>
            <div className="form-grid four-columns compact-grid">
              <Field label="Name"><input value={rate.name} onChange={(event) => updateList('ratePlans', index, 'name', event.target.value)} required /></Field>
              <Field label="Code"><input value={rate.code} onChange={(event) => updateList('ratePlans', index, 'code', event.target.value.toUpperCase())} required /></Field>
              <Field label="Room type"><select value={rate.room_type_code} onChange={(event) => updateList('ratePlans', index, 'room_type_code', event.target.value)} required><option value="">Select</option>{inventory.roomTypes.map((roomType) => <option key={roomType.code} value={roomType.code}>{roomType.name || roomType.code}</option>)}</select></Field>
              <Field label={`Rate (${currency})`}><input type="number" min="0" value={rate.base_rate} onChange={(event) => updateList('ratePlans', index, 'base_rate', event.target.value)} /></Field>
              <Field label="Meal plan"><select value={rate.meal_plan} onChange={(event) => updateList('ratePlans', index, 'meal_plan', event.target.value)}><option value="room_only">Room only</option><option value="breakfast">Breakfast</option><option value="half_board">Half board</option><option value="full_board">Full board</option></select></Field>
              <Field label="Minimum stay"><input type="number" min="1" value={rate.minimum_stay} onChange={(event) => updateList('ratePlans', index, 'minimum_stay', event.target.value)} /></Field>
              <Field label="Refundable"><select value={String(rate.is_refundable)} onChange={(event) => updateList('ratePlans', index, 'is_refundable', event.target.value === 'true')}><option value="true">Yes</option><option value="false">No</option></select></Field>
              <Field label="Priority"><input type="number" value={rate.priority} onChange={(event) => updateList('ratePlans', index, 'priority', event.target.value)} /></Field>
            </div>
          </div>
        ))}
      </ConfigSection>

      <div className="panel-actions">
        <button className="primary-button" disabled={Boolean(busy)}>{busy || 'Save inventory & continue'}</button>
      </div>
    </form>
  )
}

function RoomsStep({ csvText, setCsvText, snapshot, busy, onSubmit }) {
  return (
    <form className="onboarding-form" onSubmit={onSubmit}>
      <SectionHeader
        eyebrow="Bulk room setup"
        title="Import rooms without manual database work"
        description="Use the exact CSV columns shown below. Existing available rooms are safely updated; occupied rooms cannot be reconfigured."
      />

      <div className="csv-layout">
        <div>
          <label className="field-label">Room CSV</label>
          <textarea className="csv-editor" value={csvText} onChange={(event) => setCsvText(event.target.value)} spellCheck="false" />
          <p className="field-help">Required: room_number, room_type_code, floor_code. Status defaults to available.</p>
        </div>
        <div className="csv-reference">
          <h3>Available codes</h3>
          <div className="reference-block"><span>Room types</span>{snapshot?.roomTypes.map((item) => <code key={item.id}>{item.code}</code>)}</div>
          <div className="reference-block"><span>Floors</span>{snapshot?.floors.map((item) => <code key={item.id}>{item.code}</code>)}</div>
          <div className="reference-block"><span>Existing rooms</span><strong>{snapshot?.rooms.length || 0}</strong></div>
        </div>
      </div>

      {snapshot?.rooms.length > 0 && (
        <div className="mini-table-wrap">
          <table className="mini-table">
            <thead><tr><th>Room</th><th>Type</th><th>Status</th></tr></thead>
            <tbody>{snapshot.rooms.slice(0, 12).map((room) => <tr key={room.id}><td>{room.room_number}</td><td>{room.room_type}</td><td>{room.status}</td></tr>)}</tbody>
          </table>
        </div>
      )}

      <div className="panel-actions">
        <button className="primary-button" disabled={Boolean(busy)}>{busy || 'Import rooms & continue'}</button>
      </div>
    </form>
  )
}

function OperationsStep({
  snapshot,
  menuForm,
  setMenuForm,
  amenityForm,
  setAmenityForm,
  requestForm,
  setRequestForm,
  busy,
  onSeedDefaults,
  onAddMenuItem,
  onAddAmenity,
  onAddRequestType,
  onToggleAmenity,
  onToggleRequestType,
  onComplete,
}) {
  return (
    <div className="onboarding-form">
      <SectionHeader
        eyebrow="Guest operations"
        title="Amenities, service requests and menu"
        description="Defaults are hotel-owned and fully editable. Add at least one real menu item to make the guest food menu operational."
      />

      <div className="operations-summary">
        <Stat label="Active amenities" value={snapshot?.amenities.filter((item) => item.is_active).length || 0} />
        <Stat label="Active request types" value={snapshot?.requestTypes.filter((item) => item.is_active).length || 0} />
        <Stat label="Menu categories" value={snapshot?.menuCategories.length || 0} />
        <Stat label="Menu items" value={snapshot?.menuItems.length || 0} />
      </div>

      <button type="button" className="ghost-button inline-action" onClick={onSeedDefaults} disabled={Boolean(busy)}>Restore missing defaults</button>

      <div className="operations-grid">
        <section className="operations-card">
          <h3>Amenities</h3>
          <div className="chip-list">
            {snapshot?.amenities.map((amenity) => (
              <button key={amenity.id} type="button" className={`toggle-chip ${amenity.is_active ? 'active' : ''}`} onClick={() => onToggleAmenity(amenity)}>{amenity.name}<span>{amenity.is_active ? 'On' : 'Off'}</span></button>
            ))}
          </div>
          <form className="small-form" onSubmit={onAddAmenity}>
            <input placeholder="New amenity" value={amenityForm.name} onChange={(event) => setAmenityForm((current) => ({ ...current, name: event.target.value }))} />
            <input placeholder="Category" value={amenityForm.category} onChange={(event) => setAmenityForm((current) => ({ ...current, category: event.target.value }))} />
            <button className="secondary-button" disabled={Boolean(busy)}>Add amenity</button>
          </form>
        </section>

        <section className="operations-card">
          <h3>Request categories</h3>
          <div className="chip-list">
            {snapshot?.requestTypes.map((requestType) => (
              <button key={requestType.id} type="button" className={`toggle-chip ${requestType.is_active ? 'active' : ''}`} onClick={() => onToggleRequestType(requestType)}>{requestType.name}<span>{requestType.is_active ? 'On' : 'Off'}</span></button>
            ))}
          </div>
          <form className="small-form" onSubmit={onAddRequestType}>
            <input placeholder="New request category" value={requestForm.name} onChange={(event) => setRequestForm((current) => ({ ...current, name: event.target.value }))} />
            <select value={requestForm.default_priority} onChange={(event) => setRequestForm((current) => ({ ...current, default_priority: event.target.value }))}><option value="normal">Normal</option><option value="high">High</option><option value="urgent">Urgent</option></select>
            <button className="secondary-button" disabled={Boolean(busy)}>Add category</button>
          </form>
        </section>
      </div>

      <section className="operations-card menu-setup-card">
        <div className="config-card-header"><h3>Starter menu</h3><span>{snapshot?.menuItems.length || 0} items</span></div>
        <form className="menu-item-form" onSubmit={onAddMenuItem}>
          <input placeholder="Item name" value={menuForm.item_name} onChange={(event) => setMenuForm((current) => ({ ...current, item_name: event.target.value }))} />
          <select value={menuForm.category_id} onChange={(event) => setMenuForm((current) => ({ ...current, category_id: event.target.value }))}><option value="">Select category</option>{snapshot?.menuCategories.map((category) => <option key={category.id} value={category.id}>{category.name}</option>)}</select>
          <input type="number" min="0" step="0.01" placeholder="Price" value={menuForm.price} onChange={(event) => setMenuForm((current) => ({ ...current, price: event.target.value }))} />
          <input placeholder="Description" value={menuForm.description} onChange={(event) => setMenuForm((current) => ({ ...current, description: event.target.value }))} />
          <button className="secondary-button" disabled={Boolean(busy)}>Add menu item</button>
        </form>
        {snapshot?.menuItems.length > 0 && <div className="menu-preview">{snapshot.menuItems.slice(0, 8).map((item) => <div key={item.id}><strong>{item.item_name}</strong><span>{item.category} · ₹{Number(item.price || 0).toLocaleString('en-IN')}</span></div>)}</div>}
      </section>

      <div className="panel-actions">
        <button type="button" className="primary-button" disabled={Boolean(busy)} onClick={onComplete}>{busy || 'Complete guest operations'}</button>
      </div>
    </div>
  )
}

function ReadinessStep({ readiness, snapshot, busy, onRefresh, onFinish }) {
  const checklist = readiness?.checklist || {}
  const entries = Object.entries(checklist)

  return (
    <div className="onboarding-form">
      <SectionHeader
        eyebrow="Exit gate"
        title="Operational readiness"
        description="StayQR calculates this checklist from authoritative hotel data. The wizard cannot mark an incomplete property as operational."
      />

      <div className={`readiness-banner ${readiness?.ready ? 'ready' : ''}`}>
        <div><span>{readiness?.ready ? '✓' : '!'}</span><div><strong>{readiness?.ready ? 'Hotel is operational' : 'Setup is not complete yet'}</strong><p>{readiness?.ready ? 'The property has passed every Day 8 readiness check.' : 'Complete the missing items shown below.'}</p></div></div>
        <button type="button" className="ghost-button" onClick={onRefresh} disabled={Boolean(busy)}>Refresh</button>
      </div>

      <div className="readiness-grid">
        {entries.map(([key, value]) => (
          <div key={key} className={`readiness-item ${value ? 'passed' : 'missing'}`}><span>{value ? '✓' : '×'}</span><strong>{formatChecklistLabel(key)}</strong></div>
        ))}
      </div>

      {readiness?.missing?.length > 0 && <div className="missing-list"><strong>Still required</strong><div>{readiness.missing.map((item) => <span key={item}>{formatChecklistLabel(item)}</span>)}</div></div>}

      <div className="final-summary-grid">
        <Stat label="Rooms" value={snapshot?.rooms.length || 0} />
        <Stat label="Room types" value={snapshot?.roomTypes.length || 0} />
        <Stat label="Menu items" value={snapshot?.menuItems.length || 0} />
        <Stat label="Subscription" value={snapshot?.subscription?.status || 'Missing'} />
      </div>

      <div className="panel-actions">
        <button type="button" className="primary-button" disabled={Boolean(busy) || !readiness?.ready} onClick={onFinish}>{busy || 'Complete onboarding'}</button>
      </div>
    </div>
  )
}

function SectionHeader({ eyebrow, title, description }) {
  return <div className="section-header"><span>{eyebrow}</span><h2>{title}</h2><p>{description}</p></div>
}

function Field({ label, children, required = false, wide = false }) {
  return <label className={`onboarding-field ${wide ? 'wide' : ''}`}><span>{label}{required && <em>*</em>}</span>{children}</label>
}

function ConfigSection({ title, actionLabel, onAction, children }) {
  return <section className="config-section"><div className="config-section-header"><h3>{title}</h3><button type="button" className="secondary-button" onClick={onAction}>{actionLabel}</button></div><div className="config-section-content">{children}</div></section>
}

function Stat({ label, value }) {
  return <div className="setup-stat"><span>{label}</span><strong>{value}</strong></div>
}

function normalizeTime(value, fallback) {
  if (!value) return fallback
  return String(value).slice(0, 5)
}

function stepIndexFromOnboarding(step) {
  if (['account', 'hotel_details', 'policies'].includes(step)) return 0
  if (step === 'room_types') return 1
  if (step === 'floors_rooms') return 2
  if (['amenities', 'request_categories', 'menu', 'invoice', 'subscription'].includes(step)) return 3
  if (['review', 'complete'].includes(step)) return 4
  return 0
}

function serializeFloor(floor) {
  return {
    name: floor.name.trim(),
    code: floor.code.trim().toUpperCase(),
    floor_number: floor.floor_number,
    sort_order: floor.sort_order,
    is_active: floor.is_active,
  }
}

function serializeRoomType(roomType) {
  return {
    name: roomType.name.trim(),
    code: roomType.code.trim().toUpperCase(),
    description: roomType.description.trim(),
    base_occupancy: roomType.base_occupancy,
    max_adults: roomType.max_adults,
    max_children: roomType.max_children,
    max_occupancy: roomType.max_occupancy,
    base_rate: roomType.base_rate,
    extra_adult_rate: roomType.extra_adult_rate,
    extra_child_rate: roomType.extra_child_rate,
    sort_order: roomType.sort_order,
    is_active: roomType.is_active,
  }
}

function serializeRatePlan(rate, currency) {
  return {
    name: rate.name.trim(),
    code: rate.code.trim().toUpperCase(),
    room_type_code: rate.room_type_code.trim().toUpperCase(),
    meal_plan: rate.meal_plan,
    currency_code: currency,
    base_rate: rate.base_rate,
    extra_adult_rate: rate.extra_adult_rate,
    extra_child_rate: rate.extra_child_rate,
    minimum_stay: rate.minimum_stay,
    maximum_stay: rate.maximum_stay,
    cancellation_policy: rate.cancellation_policy,
    is_refundable: rate.is_refundable,
    priority: rate.priority,
    is_active: rate.is_active,
  }
}

function formatChecklistLabel(value) {
  return String(value || '')
    .replace(/_/g, ' ')
    .replace(/\b\w/g, (character) => character.toUpperCase())
}
