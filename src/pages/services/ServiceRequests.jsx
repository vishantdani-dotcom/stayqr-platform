import { useCallback, useEffect, useMemo, useState } from 'react'
import { getCurrentHotel } from '../../lib/currentHotel'
import { getCurrentStaff } from '../../lib/currentStaff'
import {
  assignServiceRequest,
  escalateOverdueServiceRequests,
  getServiceOperationsAnalytics,
  loadDay15ServiceRequests,
  updateServiceRequestPriority,
  updateServiceRequestStatus,
} from '../../lib/day15Operations'
import { navigateToSection } from '../../lib/bookingCalendar'
import { supabase } from '../../lib/supabase'
import './ServiceRequests.css'

const ACTIVE_STATUSES = ['pending', 'accepted', 'in_progress', 'escalated']
const DEPARTMENTS = [
  'front_office',
  'housekeeping',
  'maintenance',
  'restaurant',
  'laundry',
  'transport',
  'guest_services',
  'accounts',
  'management',
]

export default function ServiceRequests() {
  const [hotel, setHotel] = useState(null)
  const [currentStaff, setCurrentStaff] = useState(null)
  const [requests, setRequests] = useState([])
  const [staff, setStaff] = useState([])
  const [types, setTypes] = useState([])
  const [analytics, setAnalytics] = useState({})
  const [department, setDepartment] = useState('all')
  const [status, setStatus] = useState('active')
  const [loading, setLoading] = useState(true)
  const [busyId, setBusyId] = useState('')
  const [toast, setToast] = useState('')
  const [nowMs, setNowMs] = useState(() => Date.now())
  const [catalogOpen, setCatalogOpen] = useState(false)

  const showToast = useCallback((message) => {
    setToast(String(message || ''))
    window.setTimeout(() => setToast(''), 3200)
  }, [])

  const loadSupportData = useCallback(async (hotelId) => {
    const [requestRows, staffResult, typeResult] = await Promise.all([
      loadDay15ServiceRequests(hotelId),
      supabase
        .from('staff')
        .select('id, full_name, role, status')
        .eq('hotel_id', hotelId)
        .eq('status', 'active')
        .order('full_name'),
      supabase
        .from('service_request_types')
        .select('*')
        .eq('hotel_id', hotelId)
        .order('sort_order'),
    ])
    if (staffResult.error) throw staffResult.error
    if (typeResult.error) throw typeResult.error
    setRequests(requestRows)
    setStaff(staffResult.data || [])
    setTypes(typeResult.data || [])
  }, [])

  const loadAnalytics = useCallback(async (hotelId) => {
    const from = new Date()
    from.setHours(0, 0, 0, 0)
    const to = new Date(from)
    to.setDate(to.getDate() + 1)
    const result = await getServiceOperationsAnalytics({
      hotelId,
      from: from.toISOString(),
      to: to.toISOString(),
    })
    setAnalytics(result || {})
  }, [])

  const initialize = useCallback(async () => {
    setLoading(true)
    try {
      const [selectedHotel, actor] = await Promise.all([
        getCurrentHotel(),
        getCurrentStaff(),
      ])
      if (!selectedHotel) throw new Error('No hotel is selected.')
      setHotel(selectedHotel)
      setCurrentStaff(actor || null)
      await escalateOverdueServiceRequests(selectedHotel.id).catch(() => null)
      await Promise.all([loadSupportData(selectedHotel.id), loadAnalytics(selectedHotel.id)])
    } catch (error) {
      console.error('Service operations initialization failed:', error)
      showToast(error.message || 'Unable to load service operations.')
    } finally {
      setLoading(false)
    }
  }, [loadAnalytics, loadSupportData, showToast])

  useEffect(() => {
    void initialize()
  }, [initialize])

  useEffect(() => {
    if (!hotel?.id) return undefined
    const channel = supabase
      .channel(`day15_service_requests_${hotel.id}`)
      .on('postgres_changes', {
        event: '*',
        schema: 'public',
        table: 'service_requests',
        filter: `hotel_id=eq.${hotel.id}`,
      }, () => void Promise.all([loadSupportData(hotel.id), loadAnalytics(hotel.id)]))
      .subscribe()
    const refreshTimer = window.setInterval(() => void loadSupportData(hotel.id), 15000)
    const escalationTimer = window.setInterval(() => {
      void escalateOverdueServiceRequests(hotel.id)
        .then(() => Promise.all([loadSupportData(hotel.id), loadAnalytics(hotel.id)]))
        .catch(() => null)
    }, 60000)
    const clockTimer = window.setInterval(() => setNowMs(Date.now()), 1000)
    return () => {
      window.clearInterval(refreshTimer)
      window.clearInterval(escalationTimer)
      window.clearInterval(clockTimer)
      supabase.removeChannel(channel)
    }
  }, [hotel?.id, loadAnalytics, loadSupportData])

  const filteredRequests = useMemo(() => requests.filter((request) => {
    const departmentMatch = department === 'all' || request.department === department
    const statusMatch = status === 'all'
      || (status === 'active' && ACTIVE_STATUSES.includes(request.status))
      || request.status === status
    return departmentMatch && statusMatch
  }), [department, requests, status])

  const overdueCount = useMemo(() => requests.filter((request) => isOverdue(request, nowMs)).length, [nowMs, requests])

  async function runRequestAction(requestId, action) {
    setBusyId(requestId)
    try {
      await action()
      await Promise.all([loadSupportData(hotel.id), loadAnalytics(hotel.id)])
    } catch (error) {
      showToast(error.message || 'Unable to update the service request.')
    } finally {
      setBusyId('')
    }
  }

  function assign(request, staffId) {
    return runRequestAction(request.id, async () => {
      await assignServiceRequest({ hotelId: hotel.id, requestId: request.id, staffId })
      showToast(staffId ? 'Request assigned.' : 'Request unassigned.')
    })
  }

  function updatePriority(request, priority) {
    return runRequestAction(request.id, async () => {
      await updateServiceRequestPriority({ hotelId: hotel.id, requestId: request.id, priority })
      showToast('Priority updated.')
    })
  }

  function changeStatus(request, nextStatus, eta = null, note = null) {
    return runRequestAction(request.id, async () => {
      await updateServiceRequestStatus({
        hotelId: hotel.id,
        requestId: request.id,
        status: nextStatus,
        estimatedMinutes: eta,
        note,
      })
      showToast(`Request moved to ${nextStatus.replaceAll('_', ' ')}.`)
    })
  }

  function changeEta(request, eta) {
    return changeStatus(request, request.status, eta)
  }

  async function cancelRequest(request) {
    const reason = window.prompt('Cancellation reason:', 'Unable to complete request')
    if (reason === null) return
    await changeStatus(request, 'cancelled', null, reason)
  }

  async function reconcileEscalations() {
    setBusyId('escalate')
    try {
      const result = await escalateOverdueServiceRequests(hotel.id)
      await Promise.all([loadSupportData(hotel.id), loadAnalytics(hotel.id)])
      showToast(`${result?.escalated_count || 0} overdue request(s) escalated.`)
    } catch (error) {
      showToast(error.message || 'Unable to escalate overdue requests.')
    } finally {
      setBusyId('')
    }
  }

  async function openCheckoutSettlement(request) {
    setBusyId(request.id)
    try {
      const { data: session, error } = await supabase
        .from('guest_sessions')
        .select('id')
        .eq('hotel_id', hotel.id)
        .eq('room_id', request.room_id)
        .eq('guest_id', request.guest_id)
        .eq('status', 'active')
        .order('created_at', { ascending: false })
        .limit(1)
        .maybeSingle()
      if (error) throw error
      if (!session?.id) throw new Error('No active stay was found for this checkout request.')
      if (request.status === 'pending') {
        await updateServiceRequestStatus({
          hotelId: hotel.id,
          requestId: request.id,
          status: 'accepted',
          estimatedMinutes: request.estimated_minutes || 10,
        })
      }
      navigateToSection('guests', {
        guestSessionId: session.id,
        checkoutRequestId: request.id,
      })
    } catch (error) {
      showToast(error.message || 'Unable to open checkout settlement.')
    } finally {
      setBusyId('')
    }
  }

  async function saveServiceType(type, patch) {
    setBusyId(type.id)
    try {
      const { error } = await supabase
        .from('service_request_types')
        .update(patch)
        .eq('hotel_id', hotel.id)
        .eq('id', type.id)
      if (error) throw error
      await loadSupportData(hotel.id)
      showToast(`${type.name} configuration saved.`)
    } catch (error) {
      showToast(error.message || 'Unable to save the service category. Hotel-management permission may be required.')
    } finally {
      setBusyId('')
    }
  }

  if (loading) return <div className="service-loading">Loading service operations…</div>

  return (
    <div className="service-day15-page">
      <header className="service-day15-header">
        <div><span>Day 15 · Guest Services</span><h1>Service Operations</h1><p>{hotel?.hotel_name} · Department routing, assignment, SLA, escalation and guest tracking.</p></div>
        <div><button onClick={() => setCatalogOpen((value) => !value)}>{catalogOpen ? 'Hide catalogue' : 'Service catalogue'}</button><button className="gold" disabled={busyId === 'escalate'} onClick={reconcileEscalations}>Escalate overdue ({overdueCount})</button></div>
      </header>

      <section className="service-metrics">
        <Metric label="Requests today" value={analytics.requests || 0} />
        <Metric label="Completed" value={analytics.completed || 0} />
        <Metric label="Overdue" value={analytics.overdue || overdueCount} tone="danger" />
        <Metric label="SLA met" value={`${Number(analytics.sla_met_rate || 0).toFixed(0)}%`} />
        <Metric label="Avg. accept" value={`${Math.round(Number(analytics.average_accept_minutes || 0))} min`} />
        <Metric label="Avg. complete" value={`${Math.round(Number(analytics.average_completion_minutes || 0))} min`} />
      </section>

      {catalogOpen && (
        <section className="service-catalogue-panel">
          <div className="service-section-title"><h2>Dynamic service catalogue</h2><span>Guest-visible types route to the selected department and inherit SLA deadlines.</span></div>
          <div className="service-type-grid">
            {types.map((type) => <ServiceTypeEditor key={type.id} type={type} busy={busyId === type.id} onSave={(patch) => saveServiceType(type, patch)} />)}
          </div>
        </section>
      )}

      <section className="service-filters">
        <select value={department} onChange={(event) => setDepartment(event.target.value)}><option value="all">All departments</option>{DEPARTMENTS.map((entry) => <option value={entry} key={entry}>{formatLabel(entry)}</option>)}</select>
        <select value={status} onChange={(event) => setStatus(event.target.value)}><option value="active">Active requests</option><option value="all">All statuses</option><option value="pending">Pending</option><option value="accepted">Accepted</option><option value="in_progress">In progress</option><option value="escalated">Escalated</option><option value="completed">Completed</option><option value="cancelled">Cancelled</option></select>
        <button onClick={() => Promise.all([loadSupportData(hotel.id), loadAnalytics(hotel.id)])}>Refresh</button>
      </section>

      <section className="service-request-grid">
        {filteredRequests.length === 0 ? <div className="service-empty">No requests match the selected queue.</div> : filteredRequests.map((request) => (
          <RequestCard
            key={request.id}
            request={request}
            staff={staff}
            actor={currentStaff}
            nowMs={nowMs}
            busy={busyId === request.id}
            onAssign={(staffId) => assign(request, staffId)}
            onPriority={(priority) => updatePriority(request, priority)}
            onEta={(eta) => changeEta(request, eta)}
            onStatus={(nextStatus) => changeStatus(request, nextStatus)}
            onCancel={() => cancelRequest(request)}
            onCheckout={() => openCheckoutSettlement(request)}
          />
        ))}
      </section>

      {Array.isArray(analytics.by_department) && analytics.by_department.length > 0 && (
        <section className="service-department-report">
          <div className="service-section-title"><h2>Department activity today</h2></div>
          {analytics.by_department.map((entry) => <div key={entry.department}><span>{formatLabel(entry.department)}</span><strong>{entry.requests} requests · {entry.completed} complete · {entry.overdue} overdue</strong></div>)}
        </section>
      )}

      {toast && <div className="service-toast">{toast}</div>}
    </div>
  )
}

function RequestCard({ request, staff, nowMs, busy, onAssign, onPriority, onEta, onStatus, onCancel, onCheckout }) {
  const nextStatus = request.status === 'pending' ? 'accepted' : request.status === 'accepted' || request.status === 'escalated' ? 'in_progress' : request.status === 'in_progress' ? 'completed' : null
  const assigned = staff.find((entry) => entry.id === request.assigned_staff_id)
  const checkout = /checkout/i.test(request.request_type || '')
  const overdue = isOverdue(request, nowMs)
  return (
    <article className={`service-request-card ${overdue ? 'overdue' : ''}`}>
      <div className="service-card-head"><div><span>{formatLabel(request.department)}</span><h3>{request.request_type}</h3></div><Status status={request.status} /></div>
      <div className="service-room-line"><strong>Room {request.rooms?.room_number || '—'}</strong><span>{request.guests?.full_name || 'Guest'}</span></div>
      <p>{request.request_details || 'Guest service request'}</p>
      <div className="service-sla"><span>{overdue ? 'SLA overdue' : 'SLA remaining'}</span><strong>{deadline(request.sla_due_at, nowMs)}</strong></div>
      <div className="service-controls">
        <label>Assign<select disabled={busy} value={request.assigned_staff_id || ''} onChange={(event) => onAssign(event.target.value)}><option value="">Unassigned</option>{staff.map((entry) => <option key={entry.id} value={entry.id}>{entry.full_name} · {entry.role}</option>)}</select></label>
        <label>Priority<select disabled={busy} value={request.priority || 'normal'} onChange={(event) => onPriority(event.target.value)}><option value="low">Low</option><option value="normal">Normal</option><option value="high">High</option><option value="urgent">Urgent</option></select></label>
        <label>ETA<select disabled={busy} value={request.estimated_minutes || ''} onChange={(event) => onEta(event.target.value)}><option value="">Not set</option><option value="5">5 min</option><option value="10">10 min</option><option value="15">15 min</option><option value="20">20 min</option><option value="30">30 min</option><option value="45">45 min</option></select></label>
      </div>
      <div className="service-card-meta"><span>Assigned: {assigned?.full_name || 'Nobody'}</span><span>Escalation: L{request.escalation_level || 0}</span></div>
      <div className="service-card-actions">
        {checkout && !['completed', 'cancelled'].includes(request.status) && <button className="gold" disabled={busy} onClick={onCheckout}>Open settlement</button>}
        {!checkout && nextStatus && <button className="gold" disabled={busy} onClick={() => onStatus(nextStatus)}>{busy ? 'Updating…' : `Mark ${formatLabel(nextStatus)}`}</button>}
        {['pending', 'accepted', 'in_progress', 'escalated'].includes(request.status) && <button className="danger" disabled={busy} onClick={onCancel}>Cancel</button>}
      </div>
    </article>
  )
}

function ServiceTypeEditor({ type, busy, onSave }) {
  const [form, setForm] = useState({
    department: type.department || 'guest_services',
    sla_minutes: type.sla_minutes || 30,
    escalation_minutes: type.escalation_minutes || 15,
    default_estimated_minutes: type.default_estimated_minutes || '',
    guest_visible: type.guest_visible !== false,
    is_active: type.is_active !== false,
  })
  return (
    <article className="service-type-card">
      <div><strong>{type.name}</strong><span>{type.code}</span></div>
      <select value={form.department} onChange={(event) => setForm((current) => ({ ...current, department: event.target.value }))}>{DEPARTMENTS.map((entry) => <option key={entry} value={entry}>{formatLabel(entry)}</option>)}</select>
      <div className="service-type-numbers"><label>SLA<input type="number" min="1" max="1440" value={form.sla_minutes} onChange={(event) => setForm((current) => ({ ...current, sla_minutes: Number(event.target.value) }))} /></label><label>Escalate after<input type="number" min="1" max="1440" value={form.escalation_minutes} onChange={(event) => setForm((current) => ({ ...current, escalation_minutes: Number(event.target.value) }))} /></label><label>Default ETA<input type="number" min="1" max="1440" value={form.default_estimated_minutes} onChange={(event) => setForm((current) => ({ ...current, default_estimated_minutes: event.target.value === '' ? null : Number(event.target.value) }))} /></label></div>
      <div className="service-type-toggles"><label><input type="checkbox" checked={form.guest_visible} onChange={(event) => setForm((current) => ({ ...current, guest_visible: event.target.checked }))} />Guest visible</label><label><input type="checkbox" checked={form.is_active} onChange={(event) => setForm((current) => ({ ...current, is_active: event.target.checked }))} />Active</label></div>
      <button disabled={busy} onClick={() => onSave(form)}>Save category</button>
    </article>
  )
}

function Metric({ label, value, tone = '' }) { return <div className={`service-metric ${tone}`}><span>{label}</span><strong>{value}</strong></div> }
function Status({ status }) { return <span className={`service-status ${status}`}>{formatLabel(status)}</span> }
function formatLabel(value) { return String(value || '').replaceAll('_', ' ').replace(/\b\w/g, (character) => character.toUpperCase()) }
function isOverdue(request, nowMs) { return ACTIVE_STATUSES.includes(request.status) && request.sla_due_at && new Date(request.sla_due_at).getTime() < nowMs }
function deadline(iso, nowMs) { if (!iso) return 'Not set'; const difference = new Date(iso).getTime() - nowMs; const absoluteMinutes = Math.ceil(Math.abs(difference) / 60000); return difference < 0 ? `${absoluteMinutes} min overdue` : `${absoluteMinutes} min` }
