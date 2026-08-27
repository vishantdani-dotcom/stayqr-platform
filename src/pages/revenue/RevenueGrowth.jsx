import { useCallback, useEffect, useMemo, useState } from 'react'
import {
  cancelStayMovePlan,
  createStayMovePlan,
  createV11RequestId,
  downloadAccountingExport,
  generateV11AccountingExport,
  loadRevenueGrowthWorkspace,
  postSplitShareCollection,
  replaceFolioSplitPlan,
  saveCorporateAccount,
  saveCorporateRate,
  savePublicBookingSettings,
  verifyStayMovePlan,
} from '../../lib/v11Revenue'
import './RevenueGrowth.css'

const EMPTY_WORKSPACE = {
  settings: {},
  corporate_accounts: [],
  corporate_rates: [],
  room_types: [],
  rate_plans: [],
  rooms: [],
  active_stays: [],
  move_plans: [],
  open_folios: [],
  split_shares: [],
  accounting_profiles: [],
  accounting_exports: [],
}

const PAYMENT_METHODS = [
  ['cash', 'Cash'],
  ['card', 'Card'],
  ['upi', 'UPI'],
  ['bank_transfer', 'Bank transfer'],
  ['payment_link', 'Payment link'],
  ['other', 'Other'],
]

function localDate(value = new Date()) {
  const copy = new Date(value)
  copy.setMinutes(copy.getMinutes() - copy.getTimezoneOffset())
  return copy.toISOString().slice(0, 10)
}

function formatMoney(value, currency = 'INR') {
  return new Intl.NumberFormat('en-IN', {
    style: 'currency',
    currency,
    maximumFractionDigits: 2,
  }).format(Number(value || 0))
}

function formatDate(value) {
  if (!value) return '—'
  const date = new Date(value)
  if (Number.isNaN(date.getTime())) return String(value)
  return date.toLocaleString('en-IN', {
    day: '2-digit',
    month: 'short',
    year: 'numeric',
    hour: value.includes?.('T') ? '2-digit' : undefined,
    minute: value.includes?.('T') ? '2-digit' : undefined,
  })
}

function accountingLabel(template) {
  return String(template || 'stayqr')
    .replaceAll('_', ' ')
    .replace(/\b\w/g, (letter) => letter.toUpperCase())
}

export default function RevenueGrowth({ hotel, onNavigate }) {
  const hotelId = hotel?.id || null
  const hotelSlug = hotel?.slug || ''
  const [workspace, setWorkspace] = useState(EMPTY_WORKSPACE)
  const [loading, setLoading] = useState(true)
  const [refreshing, setRefreshing] = useState(false)
  const [error, setError] = useState('')
  const [notice, setNotice] = useState('')
  const [tab, setTab] = useState('booking')
  const [busy, setBusy] = useState('')

  const [settings, setSettings] = useState({
    enabled: false,
    confirmation_mode: 'instant',
    minimum_stay: 1,
    maximum_stay: 30,
    maximum_advance_days: 365,
    deposit_percent: 0,
    booking_message: '',
  })
  const [accountForm, setAccountForm] = useState({
    name: '',
    code: '',
    booking_code: '',
    gstin: '',
    billing_email: '',
    billing_phone: '',
    billing_address: '',
    notes: '',
    status: 'active',
  })
  const [rateForm, setRateForm] = useState({
    corporate_account_id: '',
    room_type_id: '',
    rate_plan_id: '',
    negotiated_rate: '',
    extra_adult_rate: '',
    extra_child_rate: '',
    minimum_stay: 1,
    maximum_stay: '',
    valid_from: localDate(),
    valid_to: '',
    is_active: true,
  })
  const [moveForm, setMoveForm] = useState({
    guest_session_id: '',
    to_room_id: '',
    planned_date: localDate(),
    notes: '',
  })
  const [splitFolioId, setSplitFolioId] = useState('')
  const [splitDraft, setSplitDraft] = useState([
    { payer_label: 'Guest 1', allocated_amount: '' },
    { payer_label: 'Guest 2', allocated_amount: '' },
  ])
  const [sharePayments, setSharePayments] = useState({})
  const [accounting, setAccounting] = useState({
    profile_id: '',
    date_from: localDate(),
    date_to: localDate(),
  })

  const loadWorkspace = useCallback(
    async ({ quiet = false } = {}) => {
      if (!hotelId) {
        setWorkspace(EMPTY_WORKSPACE)
        setLoading(false)
        return
      }

      if (quiet) setRefreshing(true)
      else setLoading(true)

      try {
        const next = (await loadRevenueGrowthWorkspace(hotelId)) || EMPTY_WORKSPACE
        setWorkspace({ ...EMPTY_WORKSPACE, ...next })
        setSettings((current) => ({
          ...current,
          ...(next.settings || {}),
        }))
        setAccounting((current) => ({
          ...current,
          profile_id:
            current.profile_id ||
            next.accounting_profiles?.find((profile) => profile.is_default)?.id ||
            next.accounting_profiles?.[0]?.id ||
            '',
        }))
        setSplitFolioId((current) => current || next.open_folios?.[0]?.id || '')
        setError('')
      } catch (nextError) {
        console.error('v1.1 Revenue Growth workspace error:', nextError)
        setError(nextError?.message || 'Unable to load Revenue Growth workspace.')
      } finally {
        setLoading(false)
        setRefreshing(false)
      }
    },
    [hotelId]
  )

  useEffect(() => {
    loadWorkspace()
  }, [loadWorkspace])

  const publicBookingUrl = useMemo(() => {
    if (!hotelSlug || typeof window === 'undefined') return ''
    return `${window.location.origin}/book/${hotelSlug}`
  }, [hotelSlug])

  const selectedStay = useMemo(
    () => workspace.active_stays.find((stay) => stay.guest_session_id === moveForm.guest_session_id) || null,
    [moveForm.guest_session_id, workspace.active_stays]
  )

  const targetRooms = useMemo(
    () => workspace.rooms.filter((room) => room.id !== selectedStay?.room_id && !['maintenance', 'out_of_order'].includes(room.status)),
    [selectedStay?.room_id, workspace.rooms]
  )

  const compatiblePlans = useMemo(
    () => workspace.rate_plans.filter((plan) => plan.room_type_id === rateForm.room_type_id),
    [rateForm.room_type_id, workspace.rate_plans]
  )

  const selectedFolio = useMemo(
    () => workspace.open_folios.find((folio) => folio.id === splitFolioId) || null,
    [splitFolioId, workspace.open_folios]
  )

  const selectedShares = useMemo(
    () => workspace.split_shares.filter((share) => share.folio_id === splitFolioId),
    [splitFolioId, workspace.split_shares]
  )

  async function runAction(key, action, successMessage) {
    if (busy) return
    setBusy(key)
    setError('')
    setNotice('')
    try {
      const result = await action()
      setNotice(successMessage)
      await loadWorkspace({ quiet: true })
      return result
    } catch (nextError) {
      console.error(`${key} error:`, nextError)
      setError(nextError?.message || 'The action could not be completed.')
      return null
    } finally {
      setBusy('')
    }
  }

  async function copyText(text, message = 'Copied to clipboard.') {
    try {
      await navigator.clipboard.writeText(text)
      setNotice(message)
    } catch {
      setError('Copy failed. Select and copy the value manually.')
    }
  }

  function updateRateRoomType(value) {
    const firstPlan = workspace.rate_plans.find((plan) => plan.room_type_id === value)
    setRateForm((current) => ({
      ...current,
      room_type_id: value,
      rate_plan_id: firstPlan?.id || '',
    }))
  }

  function addSplitShare() {
    if (splitDraft.length >= 10) return
    setSplitDraft((current) => [
      ...current,
      { payer_label: `Guest ${current.length + 1}`, allocated_amount: '' },
    ])
  }

  function removeSplitShare(index) {
    if (splitDraft.length <= 2) return
    setSplitDraft((current) => current.filter((_, itemIndex) => itemIndex !== index))
  }

  function updateSplitShare(index, key, value) {
    setSplitDraft((current) =>
      current.map((item, itemIndex) =>
        itemIndex === index ? { ...item, [key]: value } : item
      )
    )
  }

  function autoSplitFolio() {
    if (!selectedFolio || splitDraft.length < 2) return
    const total = Number(selectedFolio.balance_amount || 0)
    const base = Math.floor((total * 100) / splitDraft.length) / 100
    const amounts = splitDraft.map((_, index) =>
      index === splitDraft.length - 1
        ? (total - base * (splitDraft.length - 1)).toFixed(2)
        : base.toFixed(2)
    )
    setSplitDraft((current) =>
      current.map((item, index) => ({ ...item, allocated_amount: amounts[index] }))
    )
  }

  async function handleSharePayment(share) {
    const draft = sharePayments[share.id] || {}
    const remaining = Number(share.allocated_amount || 0) - Number(share.paid_amount || 0)
    const amount = draft.amount || remaining.toFixed(2)
    const method = draft.payment_method || 'cash'

    const result = await runAction(
      `share-${share.id}`,
      () =>
        postSplitShareCollection({
          hotelId,
          shareId: share.id,
          amount,
          paymentMethod: method,
          transactionReference: draft.transaction_reference || '',
          requestId: createV11RequestId('payer-share'),
        }),
      `${share.payer_label} collection posted.`
    )

    if (result) {
      setSharePayments((current) => ({ ...current, [share.id]: {} }))
    }
  }

  async function handleAccountingExport() {
    const result = await runAction(
      'accounting-export',
      () =>
        generateV11AccountingExport({
          hotelId,
          profileId: accounting.profile_id,
          dateFrom: accounting.date_from,
          dateTo: accounting.date_to,
          requestId: createV11RequestId('accounting-export'),
        }),
      'Accounting export generated.'
    )

    if (result?.csv_content) {
      downloadAccountingExport(result)
    }
  }

  if (!hotelId) {
    return <div className="v11-empty-page">Select a hotel to use Revenue Growth.</div>
  }

  if (loading) {
    return <div className="v11-empty-page">Loading Revenue Growth…</div>
  }

  return (
    <div className="v11-revenue-page">
      <header className="v11-hero">
        <div>
          <p className="v11-eyebrow">V1.1 · Revenue, Reservation &amp; Finance Growth</p>
          <h1>Revenue Growth</h1>
          <p>
            Direct bookings, negotiated corporate rates, planned split stays,
            payer-level split bills and accounting exports — tenant-safe and
            built on StayQR&apos;s existing reservation and folio engines.
          </p>
        </div>
        <button
          type="button"
          className="v11-btn secondary"
          onClick={() => loadWorkspace({ quiet: true })}
          disabled={refreshing || Boolean(busy)}
        >
          {refreshing ? 'Refreshing…' : 'Refresh'}
        </button>
      </header>

      {error && <div className="v11-alert error">{error}</div>}
      {notice && <div className="v11-alert success">{notice}</div>}

      <section className="v11-metrics">
        <Metric label="Direct booking" value={settings.enabled ? 'LIVE' : 'OFF'} />
        <Metric label="Corporate accounts" value={workspace.corporate_accounts.length} />
        <Metric label="Planned room moves" value={workspace.move_plans.filter((plan) => plan.status === 'planned').length} />
        <Metric label="Open folios" value={workspace.open_folios.length} />
        <Metric label="Accounting profiles" value={workspace.accounting_profiles.length} />
      </section>

      <nav className="v11-tabs" aria-label="Revenue Growth modules">
        {[
          ['booking', 'Direct Booking'],
          ['corporate', 'Corporate Rates'],
          ['split-stay', 'Split Stay'],
          ['split-bill', 'Split Bill'],
          ['accounting', 'Accounting'],
        ].map(([id, label]) => (
          <button
            key={id}
            type="button"
            className={tab === id ? 'active' : ''}
            onClick={() => setTab(id)}
          >
            {label}
          </button>
        ))}
      </nav>

      {tab === 'booking' && (
        <section className="v11-grid two">
          <Card title="Hotel website booking" subtitle="Safe public booking page; disabled until you explicitly switch it on.">
            <div className="v11-form-grid two">
              <Field label="Direct booking">
                <select
                  value={settings.enabled ? 'on' : 'off'}
                  onChange={(event) => setSettings((current) => ({ ...current, enabled: event.target.value === 'on' }))}
                >
                  <option value="off">Disabled</option>
                  <option value="on">Enabled</option>
                </select>
              </Field>
              <Field label="Confirmation mode">
                <select
                  value={settings.confirmation_mode || 'instant'}
                  onChange={(event) => setSettings((current) => ({ ...current, confirmation_mode: event.target.value }))}
                >
                  <option value="instant">Instant confirmation</option>
                  <option value="request">Booking request / tentative</option>
                </select>
              </Field>
              <Field label="Minimum stay">
                <input type="number" min="1" max="365" value={settings.minimum_stay ?? 1} onChange={(event) => setSettings((current) => ({ ...current, minimum_stay: event.target.value }))} />
              </Field>
              <Field label="Maximum stay">
                <input type="number" min="1" max="365" value={settings.maximum_stay ?? 30} onChange={(event) => setSettings((current) => ({ ...current, maximum_stay: event.target.value }))} />
              </Field>
              <Field label="Advance booking window (days)">
                <input type="number" min="1" max="730" value={settings.maximum_advance_days ?? 365} onChange={(event) => setSettings((current) => ({ ...current, maximum_advance_days: event.target.value }))} />
              </Field>
              <Field label="Deposit required (%)">
                <input type="number" min="0" max="100" step="0.01" value={settings.deposit_percent ?? 0} onChange={(event) => setSettings((current) => ({ ...current, deposit_percent: event.target.value }))} />
              </Field>
              <Field label="Booking message" wide>
                <textarea rows="3" value={settings.booking_message || ''} onChange={(event) => setSettings((current) => ({ ...current, booking_message: event.target.value }))} placeholder="Optional message shown on the booking page" />
              </Field>
            </div>
            <div className="v11-actions">
              <button
                type="button"
                className="v11-btn primary"
                disabled={Boolean(busy)}
                onClick={() => runAction('booking-settings', () => savePublicBookingSettings(hotelId, settings), 'Direct booking settings saved.')}
              >
                {busy === 'booking-settings' ? 'Saving…' : 'Save booking settings'}
              </button>
            </div>
          </Card>

          <Card title="Website / embed link" subtitle="Use this URL on the hotel's official website, Instagram bio or booking CTA.">
            <div className="v11-link-box">
              <span>{publicBookingUrl || 'Hotel slug unavailable'}</span>
              <button type="button" onClick={() => copyText(publicBookingUrl, 'Booking link copied.')} disabled={!publicBookingUrl}>Copy</button>
            </div>
            {publicBookingUrl && (
              <a className="v11-open-link" href={publicBookingUrl} target="_blank" rel="noreferrer">
                Open public booking page ↗
              </a>
            )}
            <div className="v11-note">
              Public callers never receive room IDs or guest records. Availability,
              pricing and reservation creation are calculated server-side, and a
              request ID prevents accidental duplicate bookings.
            </div>
          </Card>
        </section>
      )}

      {tab === 'corporate' && (
        <section className="v11-stack">
          <div className="v11-grid two">
            <Card title="Corporate profile" subtitle="Create a negotiated B2B account with its own booking code.">
              <div className="v11-form-grid two">
                <Field label="Company name" wide><input value={accountForm.name} onChange={(event) => setAccountForm((current) => ({ ...current, name: event.target.value }))} /></Field>
                <Field label="Internal code"><input value={accountForm.code} onChange={(event) => setAccountForm((current) => ({ ...current, code: event.target.value.toUpperCase() }))} placeholder="ACME" /></Field>
                <Field label="Booking code"><input value={accountForm.booking_code} onChange={(event) => setAccountForm((current) => ({ ...current, booking_code: event.target.value.toUpperCase() }))} placeholder="ACME2026" /></Field>
                <Field label="GSTIN"><input value={accountForm.gstin} onChange={(event) => setAccountForm((current) => ({ ...current, gstin: event.target.value.toUpperCase() }))} /></Field>
                <Field label="Billing email"><input type="email" value={accountForm.billing_email} onChange={(event) => setAccountForm((current) => ({ ...current, billing_email: event.target.value }))} /></Field>
                <Field label="Billing phone"><input value={accountForm.billing_phone} onChange={(event) => setAccountForm((current) => ({ ...current, billing_phone: event.target.value }))} /></Field>
                <Field label="Billing address" wide><textarea rows="2" value={accountForm.billing_address} onChange={(event) => setAccountForm((current) => ({ ...current, billing_address: event.target.value }))} /></Field>
              </div>
              <div className="v11-actions">
                <button type="button" className="v11-btn primary" disabled={Boolean(busy)} onClick={async () => {
                  const saved = await runAction('corporate-account', () => saveCorporateAccount(hotelId, accountForm), 'Corporate account saved.')
                  if (saved) setAccountForm({ name: '', code: '', booking_code: '', gstin: '', billing_email: '', billing_phone: '', billing_address: '', notes: '', status: 'active' })
                }}>{busy === 'corporate-account' ? 'Saving…' : 'Create corporate account'}</button>
              </div>
            </Card>

            <Card title="Negotiated room rate" subtitle="Corporate prices override the selected base/seasonal rate for valid dates.">
              <div className="v11-form-grid two">
                <Field label="Corporate account" wide>
                  <select value={rateForm.corporate_account_id} onChange={(event) => setRateForm((current) => ({ ...current, corporate_account_id: event.target.value }))}>
                    <option value="">Select account</option>
                    {workspace.corporate_accounts.filter((account) => account.status === 'active').map((account) => <option key={account.id} value={account.id}>{account.name}</option>)}
                  </select>
                </Field>
                <Field label="Room type">
                  <select value={rateForm.room_type_id} onChange={(event) => updateRateRoomType(event.target.value)}>
                    <option value="">Select room type</option>
                    {workspace.room_types.map((roomType) => <option key={roomType.id} value={roomType.id}>{roomType.name}</option>)}
                  </select>
                </Field>
                <Field label="Base rate plan">
                  <select value={rateForm.rate_plan_id} onChange={(event) => setRateForm((current) => ({ ...current, rate_plan_id: event.target.value }))} disabled={!rateForm.room_type_id}>
                    <option value="">Select rate plan</option>
                    {compatiblePlans.map((plan) => <option key={plan.id} value={plan.id}>{plan.name}</option>)}
                  </select>
                </Field>
                <Field label="Negotiated nightly rate"><input type="number" min="0" step="0.01" value={rateForm.negotiated_rate} onChange={(event) => setRateForm((current) => ({ ...current, negotiated_rate: event.target.value }))} /></Field>
                <Field label="Extra adult rate"><input type="number" min="0" step="0.01" value={rateForm.extra_adult_rate} onChange={(event) => setRateForm((current) => ({ ...current, extra_adult_rate: event.target.value }))} placeholder="Use base plan" /></Field>
                <Field label="Valid from"><input type="date" value={rateForm.valid_from} onChange={(event) => setRateForm((current) => ({ ...current, valid_from: event.target.value }))} /></Field>
                <Field label="Valid to"><input type="date" value={rateForm.valid_to} onChange={(event) => setRateForm((current) => ({ ...current, valid_to: event.target.value }))} /></Field>
              </div>
              <div className="v11-actions">
                <button type="button" className="v11-btn primary" disabled={Boolean(busy)} onClick={async () => {
                  const saved = await runAction('corporate-rate', () => saveCorporateRate(hotelId, rateForm), 'Negotiated corporate rate saved.')
                  if (saved) setRateForm((current) => ({ ...current, negotiated_rate: '', extra_adult_rate: '', extra_child_rate: '', maximum_stay: '', valid_to: '' }))
                }}>{busy === 'corporate-rate' ? 'Saving…' : 'Save negotiated rate'}</button>
              </div>
            </Card>
          </div>

          <Card title="Corporate accounts & booking links" subtitle="Each active company gets a direct booking URL that automatically applies valid negotiated rates.">
            <div className="v11-table-wrap">
              <table className="v11-table">
                <thead><tr><th>Company</th><th>Code</th><th>Booking code</th><th>Rates</th><th>Link</th></tr></thead>
                <tbody>
                  {workspace.corporate_accounts.map((account) => {
                    const rates = workspace.corporate_rates.filter((rate) => rate.corporate_account_id === account.id && rate.is_active)
                    const link = `${publicBookingUrl}?corporate=${encodeURIComponent(account.booking_code)}`
                    return <tr key={account.id}><td><strong>{account.name}</strong><small>{account.status}</small></td><td>{account.code}</td><td>{account.booking_code}</td><td>{rates.length}</td><td><button type="button" className="v11-link-button" onClick={() => copyText(link, `${account.name} booking link copied.`)}>Copy corporate link</button></td></tr>
                  })}
                  {workspace.corporate_accounts.length === 0 && <tr><td colSpan="5" className="v11-table-empty">No corporate accounts yet.</td></tr>}
                </tbody>
              </table>
            </div>
          </Card>

          <Card title="Negotiated rate register">
            <div className="v11-table-wrap">
              <table className="v11-table">
                <thead><tr><th>Company</th><th>Room</th><th>Rate plan</th><th>Negotiated</th><th>Validity</th></tr></thead>
                <tbody>
                  {workspace.corporate_rates.map((rate) => <tr key={rate.id}><td>{rate.corporate_name}</td><td>{rate.room_type_name}</td><td>{rate.rate_plan_name}</td><td>{formatMoney(rate.negotiated_rate, rate.currency_code)}</td><td>{rate.valid_from} → {rate.valid_to || 'Open'}</td></tr>)}
                  {workspace.corporate_rates.length === 0 && <tr><td colSpan="5" className="v11-table-empty">No negotiated rates yet.</td></tr>}
                </tbody>
              </table>
            </div>
          </Card>
        </section>
      )}

      {tab === 'split-stay' && (
        <section className="v11-grid two">
          <Card title="Plan a room move" subtitle="Plan the second segment now; the existing atomic room-move workflow remains authoritative at execution time.">
            <div className="v11-form-grid">
              <Field label="Active stay">
                <select value={moveForm.guest_session_id} onChange={(event) => setMoveForm((current) => ({ ...current, guest_session_id: event.target.value, to_room_id: '' }))}>
                  <option value="">Select active stay</option>
                  {workspace.active_stays.map((stay) => <option key={stay.guest_session_id} value={stay.guest_session_id}>{stay.guest_name} · Room {stay.room_number}</option>)}
                </select>
              </Field>
              <Field label="Target room">
                <select value={moveForm.to_room_id} onChange={(event) => setMoveForm((current) => ({ ...current, to_room_id: event.target.value }))} disabled={!selectedStay}>
                  <option value="">Select target room</option>
                  {targetRooms.map((room) => <option key={room.id} value={room.id}>Room {room.room_number} · {room.status}</option>)}
                </select>
              </Field>
              <Field label="Planned move date"><input type="date" value={moveForm.planned_date} onChange={(event) => setMoveForm((current) => ({ ...current, planned_date: event.target.value }))} /></Field>
              <Field label="Notes"><input value={moveForm.notes} onChange={(event) => setMoveForm((current) => ({ ...current, notes: event.target.value }))} placeholder="Reason / guest preference" /></Field>
            </div>
            <div className="v11-actions">
              <button type="button" className="v11-btn primary" disabled={Boolean(busy) || !moveForm.guest_session_id || !moveForm.to_room_id} onClick={async () => {
                const saved = await runAction('move-plan', () => createStayMovePlan({ hotelId, guestSessionId: moveForm.guest_session_id, targetRoomId: moveForm.to_room_id, plannedDate: moveForm.planned_date, notes: moveForm.notes }), 'Split-stay room move planned.')
                if (saved) setMoveForm((current) => ({ ...current, to_room_id: '', notes: '' }))
              }}>{busy === 'move-plan' ? 'Planning…' : 'Plan room move'}</button>
              <button type="button" className="v11-btn secondary" onClick={() => onNavigate?.('operations')}>Open Arrivals &amp; Departures</button>
            </div>
            <div className="v11-note">A plan checks target-room commitments on the planned date but does not bypass StayQR&apos;s authoritative room-move transaction. After the real move is executed, verify the plan here.</div>
          </Card>

          <Card title="Split-stay plan register">
            <div className="v11-list">
              {workspace.move_plans.map((plan) => <article key={plan.id} className="v11-list-row"><div><strong>{plan.guest_name}</strong><span>Room {plan.from_room_number} → {plan.to_room_number} · {plan.planned_date}</span><small>{plan.notes || 'No note'} · {plan.status}</small></div>{plan.status === 'planned' && <div className="v11-row-actions"><button type="button" onClick={() => runAction(`verify-${plan.id}`, () => verifyStayMovePlan(hotelId, plan.id), 'Room move plan verified.')}>Verify after move</button><button type="button" className="danger" onClick={() => runAction(`cancel-${plan.id}`, () => cancelStayMovePlan(hotelId, plan.id), 'Room move plan cancelled.')}>Cancel</button></div>}</article>)}
              {workspace.move_plans.length === 0 && <div className="v11-empty">No split-stay move plans.</div>}
            </div>
          </Card>
        </section>
      )}

      {tab === 'split-bill' && (
        <section className="v11-grid two">
          <Card title="Create payer split" subtitle="Divide the current folio balance by person/company while keeping one authoritative StayQR folio.">
            <div className="v11-form-grid">
              <Field label="Open folio">
                <select value={splitFolioId} onChange={(event) => setSplitFolioId(event.target.value)}>
                  <option value="">Select folio</option>
                  {workspace.open_folios.map((folio) => <option key={folio.id} value={folio.id}>{folio.folio_number} · {folio.guest_name} · {formatMoney(folio.balance_amount, folio.currency_code)}</option>)}
                </select>
              </Field>
            </div>
            {selectedFolio && <div className="v11-balance-callout"><span>Current balance</span><strong>{formatMoney(selectedFolio.balance_amount, selectedFolio.currency_code)}</strong></div>}
            <div className="v11-split-editor">
              {splitDraft.map((share, index) => <div className="v11-split-line" key={`${index}-${share.payer_label}`}><input value={share.payer_label} onChange={(event) => updateSplitShare(index, 'payer_label', event.target.value)} placeholder="Payer label" /><input type="number" min="0.01" step="0.01" value={share.allocated_amount} onChange={(event) => updateSplitShare(index, 'allocated_amount', event.target.value)} placeholder="Amount" /><button type="button" onClick={() => removeSplitShare(index)} disabled={splitDraft.length <= 2}>×</button></div>)}
            </div>
            <div className="v11-actions"><button type="button" className="v11-btn secondary" onClick={addSplitShare} disabled={splitDraft.length >= 10}>Add payer</button><button type="button" className="v11-btn secondary" onClick={autoSplitFolio} disabled={!selectedFolio}>Equal split</button><button type="button" className="v11-btn primary" disabled={Boolean(busy) || !splitFolioId} onClick={() => runAction('split-plan', () => replaceFolioSplitPlan(hotelId, splitFolioId, splitDraft.map((share) => ({ ...share, allocated_amount: Number(share.allocated_amount) }))), 'Split-bill payer plan saved.')}>{busy === 'split-plan' ? 'Saving…' : 'Save payer split'}</button></div>
          </Card>

          <Card title="Payer collections" subtitle="Collections post to the same authoritative folio and are tagged to the payer share for reconciliation.">
            <div className="v11-list">
              {selectedShares.map((share) => {
                const remaining = Number(share.allocated_amount) - Number(share.paid_amount)
                const draft = sharePayments[share.id] || {}
                return <article key={share.id} className="v11-payer"><div className="v11-payer-head"><div><strong>{share.payer_label}</strong><span>{formatMoney(share.paid_amount)} paid of {formatMoney(share.allocated_amount)}</span></div><span className={`v11-status ${share.status}`}>{share.status}</span></div>{share.status !== 'settled' && <div className="v11-payment-row"><input type="number" min="0.01" max={remaining} step="0.01" value={draft.amount ?? remaining.toFixed(2)} onChange={(event) => setSharePayments((current) => ({ ...current, [share.id]: { ...current[share.id], amount: event.target.value } }))} /><select value={draft.payment_method || 'cash'} onChange={(event) => setSharePayments((current) => ({ ...current, [share.id]: { ...current[share.id], payment_method: event.target.value } }))}>{PAYMENT_METHODS.map(([value, label]) => <option key={value} value={value}>{label}</option>)}</select><input value={draft.transaction_reference || ''} onChange={(event) => setSharePayments((current) => ({ ...current, [share.id]: { ...current[share.id], transaction_reference: event.target.value } }))} placeholder="Reference (optional)" /><button type="button" onClick={() => handleSharePayment(share)} disabled={Boolean(busy)}>Post</button></div>}</article>
              })}
              {!splitFolioId && <div className="v11-empty">Select an open folio.</div>}
              {splitFolioId && selectedShares.length === 0 && <div className="v11-empty">No payer split exists for this folio yet.</div>}
            </div>
          </Card>
        </section>
      )}

      {tab === 'accounting' && (
        <section className="v11-grid two">
          <Card title="Accounting export" subtitle="Generate connector-ready CSVs from immutable StayQR invoices and collections.">
            <div className="v11-form-grid">
              <Field label="Template">
                <select value={accounting.profile_id} onChange={(event) => setAccounting((current) => ({ ...current, profile_id: event.target.value }))}>
                  <option value="">Select export profile</option>
                  {workspace.accounting_profiles.map((profile) => <option key={profile.id} value={profile.id}>{profile.profile_name} · {accountingLabel(profile.template)}</option>)}
                </select>
              </Field>
              <div className="v11-form-grid two nested"><Field label="Date from"><input type="date" value={accounting.date_from} onChange={(event) => setAccounting((current) => ({ ...current, date_from: event.target.value }))} /></Field><Field label="Date to"><input type="date" value={accounting.date_to} onChange={(event) => setAccounting((current) => ({ ...current, date_to: event.target.value }))} /></Field></div>
            </div>
            <div className="v11-actions"><button type="button" className="v11-btn primary" disabled={Boolean(busy) || !accounting.profile_id} onClick={handleAccountingExport}>{busy === 'accounting-export' ? 'Generating…' : 'Generate & download CSV'}</button><button type="button" className="v11-btn secondary" onClick={() => onNavigate?.('invoices')}>Open Invoices &amp; Audit</button></div>
            <div className="v11-note">StayQR Standard preserves the existing Day 12 accounting export. Tally, Zoho Books and QuickBooks profiles generate dedicated column layouts without changing invoice or folio data.</div>
          </Card>

          <Card title="Recent accounting exports">
            <div className="v11-list">
              {workspace.accounting_exports.slice(0, 15).map((exportRecord) => <article key={exportRecord.id} className="v11-list-row"><div><strong>{exportRecord.file_name}</strong><span>{exportRecord.date_from} → {exportRecord.date_to} · {exportRecord.row_count} row(s)</span><small>{formatDate(exportRecord.generated_at)} · {exportRecord.metadata?.v11_template ? accountingLabel(exportRecord.metadata.v11_template) : 'StayQR standard'}</small></div><button type="button" onClick={() => downloadAccountingExport(exportRecord)}>Download</button></article>)}
              {workspace.accounting_exports.length === 0 && <div className="v11-empty">No accounting exports yet.</div>}
            </div>
          </Card>
        </section>
      )}
    </div>
  )
}

function Card({ title, subtitle, children }) {
  return <article className="v11-card"><header><h2>{title}</h2>{subtitle && <p>{subtitle}</p>}</header>{children}</article>
}

function Metric({ label, value }) {
  return <div className="v11-metric"><span>{label}</span><strong>{value}</strong></div>
}

function Field({ label, wide = false, children }) {
  return <label className={`v11-field${wide ? ' wide' : ''}`}><span>{label}</span>{children}</label>
}
