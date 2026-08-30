import { useCallback, useEffect, useMemo, useState } from 'react'
import {
  createLaundryOrder,
  createLostFoundItem,
  loadOperationsAutomation,
  postInventoryMovement,
  prepareKotPrint,
  runDueScheduledReports,
  transitionLostFoundItem,
  updateLaundryStatus,
  upsertInventoryItem,
  upsertKitchenPrinterProfile,
  upsertScheduledReportJob,
} from '../../lib/v11Operations'
import './OperationsAutomation.css'

const TABS = [
  ['laundry', 'Laundry'],
  ['lostfound', 'Lost & Found'],
  ['inventory', 'Inventory'],
  ['kot', 'KOT / Printers'],
  ['reports', 'Scheduled Reports'],
]

const REPORT_KEYS = [
  ['occupancy_daily', 'Occupancy Daily'],
  ['revenue_daily', 'Revenue Daily'],
  ['revenue_by_category', 'Revenue by Category'],
  ['reservations_by_source', 'Reservations by Source'],
  ['arrivals_departures', 'Arrivals & Departures'],
  ['payments_by_method', 'Payments by Method'],
  ['tax_gst_summary', 'Tax / GST Summary'],
  ['guest_food_service', 'Guest Food & Service'],
  ['service_sla', 'Service SLA'],
  ['housekeeping', 'Housekeeping'],
  ['staff_department', 'Staff / Department'],
]

export default function OperationsAutomation({ hotel }) {
  const [tab, setTab] = useState('laundry')
  const [workspace, setWorkspace] = useState(null)
  const [loading, setLoading] = useState(true)
  const [busy, setBusy] = useState('')
  const [toast, setToast] = useState('')
  const hotelId = hotel?.id || null

  const showToast = useCallback((message) => {
    setToast(String(message || ''))
    window.setTimeout(() => setToast(''), 3200)
  }, [])

  const refresh = useCallback(async () => {
    if (!hotelId) return
    setLoading(true)
    try {
      setWorkspace(await loadOperationsAutomation(hotelId))
    } catch (error) {
      showToast(error.message || 'Unable to load V1.1-B operations.')
    } finally {
      setLoading(false)
    }
  }, [hotelId, showToast])

  useEffect(() => { void refresh() }, [refresh])

  useEffect(() => {
    if (!hotelId) return undefined
    const timer = window.setInterval(() => {
      void runDueScheduledReports(hotelId, false).then((result) => {
        if (Number(result?.processed || 0) > 0) void refresh()
      }).catch(() => null)
    }, 60000)
    return () => window.clearInterval(timer)
  }, [hotelId, refresh])

  async function runAction(key, action, successMessage) {
    setBusy(key)
    try {
      await action()
      await refresh()
      showToast(successMessage)
    } catch (error) {
      showToast(error.message || 'Unable to complete the operation.')
    } finally {
      setBusy('')
    }
  }

  if (!hotelId) return <div className="v11b-page">Select a hotel to continue.</div>
  if (loading && !workspace) return <div className="v11b-page">Loading operations automation…</div>

  const data = workspace || {}
  const metrics = {
    laundry: (data.laundry_orders || []).filter((row) => !['delivered', 'cancelled'].includes(row.status)).length,
    lost: (data.lost_found_items || []).filter((row) => !['returned', 'disposed', 'donated'].includes(row.status)).length,
    lowStock: (data.inventory_items || []).filter((row) => row.is_active && Number(row.quantity_on_hand) <= Number(row.reorder_level)).length,
    printers: (data.printer_profiles || []).filter((row) => row.is_active).length,
    scheduled: (data.report_jobs || []).filter((row) => row.enabled).length,
  }

  return (
    <div className="v11b-page">
      {toast && <div className="v11b-toast">{toast}</div>}
      <header className="v11b-hero">
        <div>
          <span>V1.1-B · HOTEL OPERATIONS & AUTOMATION</span>
          <h1>Operations Automation</h1>
          <p>{hotel.hotel_name} · Laundry, lost & found, consumable inventory, KOT printing and scheduled reporting.</p>
        </div>
        <button onClick={refresh} disabled={loading}>{loading ? 'Refreshing…' : 'Refresh'}</button>
      </header>

      <section className="v11b-metrics">
        <Metric label="Laundry active" value={metrics.laundry} />
        <Metric label="Lost & found open" value={metrics.lost} />
        <Metric label="Low stock" value={metrics.lowStock} />
        <Metric label="KOT printers" value={metrics.printers} />
        <Metric label="Scheduled reports" value={metrics.scheduled} />
      </section>

      <nav className="v11b-tabs">
        {TABS.map(([id, label]) => <button key={id} className={tab === id ? 'active' : ''} onClick={() => setTab(id)}>{label}</button>)}
      </nav>

      {tab === 'laundry' && <LaundryTab hotel={hotel} data={data} busy={busy} runAction={runAction} />}
      {tab === 'lostfound' && <LostFoundTab hotel={hotel} data={data} busy={busy} runAction={runAction} />}
      {tab === 'inventory' && <InventoryTab hotel={hotel} data={data} busy={busy} runAction={runAction} />}
      {tab === 'kot' && <KotTab hotel={hotel} data={data} busy={busy} runAction={runAction} showToast={showToast} />}
      {tab === 'reports' && <ReportsTab hotel={hotel} data={data} busy={busy} runAction={runAction} />}
    </div>
  )
}

function LaundryTab({ hotel, data, busy, runAction }) {
  const [form, setForm] = useState({ guest_session_id: '', piece_count: 1, item_summary: '', priority: 'normal', promised_at: '' })
  const active = (data.laundry_orders || []).filter((row) => !['delivered', 'cancelled'].includes(row.status))

  function submit(event) {
    event.preventDefault()
    return runAction('laundry-create', () => createLaundryOrder(hotel.id, {
      ...form,
      promised_at: form.promised_at ? new Date(form.promised_at).toISOString() : null,
    }), 'Laundry order created.')
  }

  return (
    <section className="v11b-grid two">
      <form className="v11b-card" onSubmit={submit}>
        <h2>Create laundry order</h2>
        <label>Active stay<select value={form.guest_session_id} onChange={(e) => setForm({ ...form, guest_session_id: e.target.value })} required><option value="">Select active stay</option>{(data.active_stays || []).map((stay) => <option key={stay.id} value={stay.id}>Room {stay.room_number} · {stay.guest_name}</option>)}</select></label>
        <div className="v11b-form-grid"><label>Pieces<input type="number" min="1" max="500" value={form.piece_count} onChange={(e) => setForm({ ...form, piece_count: e.target.value })} required /></label><label>Priority<select value={form.priority} onChange={(e) => setForm({ ...form, priority: e.target.value })}><option value="normal">Normal</option><option value="express">Express</option></select></label></div>
        <label>Items<input value={form.item_summary} onChange={(e) => setForm({ ...form, item_summary: e.target.value })} placeholder="2 shirts, 1 trouser" required /></label>
        <label>Promised by<input type="datetime-local" value={form.promised_at} onChange={(e) => setForm({ ...form, promised_at: e.target.value })} /></label>
        <button className="primary" disabled={busy === 'laundry-create'}>{busy === 'laundry-create' ? 'Creating…' : 'Create laundry order'}</button>
      </form>
      <div className="v11b-card"><h2>Laundry board</h2>{active.length === 0 ? <Empty text="No active laundry orders." /> : active.map((row) => <LaundryRow key={row.id} row={row} busy={busy} runAction={runAction} hotelId={hotel.id} />)}</div>
    </section>
  )
}

function LaundryRow({ row, busy, runAction, hotelId }) {
  const next = { received: 'washing', washing: 'drying', drying: 'ironing', ironing: 'ready', ready: 'delivered' }[row.status]
  return <article className="v11b-row"><div><strong>{row.order_number}</strong><span>{row.piece_count} pcs · {row.item_summary}</span><small>{row.priority} · {row.status}</small></div>{next && <button disabled={busy === row.id} onClick={() => runAction(row.id, () => updateLaundryStatus(hotelId, row.id, next), `Laundry moved to ${next}.`)}>Move to {next}</button>}</article>
}

function LostFoundTab({ hotel, data, busy, runAction }) {
  const [form, setForm] = useState({ item_name: '', found_location: '', description: '', storage_location: '' })
  function submit(event) {
    event.preventDefault()
    return runAction('lost-create', () => createLostFoundItem(hotel.id, form), 'Lost-and-found item recorded.')
  }
  const open = (data.lost_found_items || []).filter((row) => !['returned', 'disposed', 'donated'].includes(row.status))
  return <section className="v11b-grid two"><form className="v11b-card" onSubmit={submit}><h2>Record found item</h2><label>Item<input value={form.item_name} onChange={(e) => setForm({ ...form, item_name: e.target.value })} required /></label><label>Found location<input value={form.found_location} onChange={(e) => setForm({ ...form, found_location: e.target.value })} required /></label><label>Storage location<input value={form.storage_location} onChange={(e) => setForm({ ...form, storage_location: e.target.value })} placeholder="Front desk locker A" /></label><label>Description<textarea value={form.description} onChange={(e) => setForm({ ...form, description: e.target.value })} /></label><button className="primary" disabled={busy === 'lost-create'}>Record item</button></form><div className="v11b-card"><h2>Custody register</h2>{open.length === 0 ? <Empty text="No open lost-and-found items." /> : open.map((row) => <article className="v11b-row" key={row.id}><div><strong>{row.item_number} · {row.item_name}</strong><span>{row.found_location} · {row.status}</span><small>{row.storage_location || 'Storage not set'}</small></div><div className="v11b-actions"><button disabled={busy === row.id} onClick={() => runAction(row.id, () => transitionLostFoundItem(hotel.id, row.id, 'matched', {}), 'Item marked matched.')}>Match</button><button disabled={busy === row.id} onClick={() => { const claimant = window.prompt('Claimant name:'); if (!claimant) return; void runAction(row.id, () => transitionLostFoundItem(hotel.id, row.id, 'returned', { claimant_name: claimant, note: 'Returned to claimant' }), 'Item returned and closed.') }}>Return</button></div></article>)}</div></section>
}

function InventoryTab({ hotel, data, busy, runAction }) {
  const [form, setForm] = useState({ sku: '', name: '', category: 'general', unit: 'unit', quantity_on_hand: 0, reorder_level: 0 })
  function submit(event) { event.preventDefault(); return runAction('inventory-create', () => upsertInventoryItem(hotel.id, form), 'Inventory item created.') }
  return <section className="v11b-grid two"><form className="v11b-card" onSubmit={submit}><h2>Add stock item</h2><div className="v11b-form-grid"><label>SKU<input value={form.sku} onChange={(e) => setForm({ ...form, sku: e.target.value })} required /></label><label>Name<input value={form.name} onChange={(e) => setForm({ ...form, name: e.target.value })} required /></label></div><div className="v11b-form-grid"><label>Category<select value={form.category} onChange={(e) => setForm({ ...form, category: e.target.value })}>{['general','housekeeping','laundry','restaurant','maintenance','front_office','guest_amenity'].map((v) => <option key={v} value={v}>{v.replaceAll('_',' ')}</option>)}</select></label><label>Unit<input value={form.unit} onChange={(e) => setForm({ ...form, unit: e.target.value })} /></label></div><div className="v11b-form-grid"><label>Opening stock<input type="number" min="0" step="0.001" value={form.quantity_on_hand} onChange={(e) => setForm({ ...form, quantity_on_hand: e.target.value })} /></label><label>Reorder at<input type="number" min="0" step="0.001" value={form.reorder_level} onChange={(e) => setForm({ ...form, reorder_level: e.target.value })} /></label></div><button className="primary" disabled={busy === 'inventory-create'}>Create stock item</button></form><div className="v11b-card"><h2>Stock ledger</h2>{(data.inventory_items || []).length === 0 ? <Empty text="No stock items yet." /> : (data.inventory_items || []).map((row) => <InventoryRow key={row.id} row={row} hotelId={hotel.id} busy={busy} runAction={runAction} />)}</div></section>
}

function InventoryRow({ row, hotelId, busy, runAction }) {
  const low = Number(row.quantity_on_hand) <= Number(row.reorder_level)
  function move(type) {
    const quantity = window.prompt(`${type.replaceAll('_',' ')} quantity:`,'1')
    if (!quantity) return
    const reason = window.prompt('Reason:','V1.1-B browser acceptance')
    if (!reason) return
    void runAction(row.id, () => postInventoryMovement(hotelId,row.id,type,quantity,reason), 'Stock movement posted.')
  }
  return <article className={`v11b-row ${low ? 'low' : ''}`}><div><strong>{row.name}</strong><span>{row.sku} · {row.quantity_on_hand} {row.unit}</span><small>Reorder ≤ {row.reorder_level} · {row.category}</small></div><div className="v11b-actions"><button disabled={busy === row.id} onClick={() => move('receive')}>Receive</button><button disabled={busy === row.id} onClick={() => move('consume')}>Consume</button></div></article>
}

function KotTab({ hotel, data, busy, runAction, showToast }) {
  const [form, setForm] = useState({ name: 'Kitchen Default', station: 'kitchen', paper_width_mm: 80, copies: 1, is_default: true, auto_print: false, is_active: true })
  const [profileId, setProfileId] = useState('')
  const activeProfiles = useMemo(() => (data.printer_profiles || []).filter((row) => row.is_active), [data.printer_profiles])
  useEffect(() => {
    if (!profileId && activeProfiles[0]?.id) setProfileId(activeProfiles[0].id)
    const current = activeProfiles.find((row) => row.id === (profileId || activeProfiles[0]?.id))
    if (current) setForm({ id: current.id, name: current.name, station: current.station, paper_width_mm: current.paper_width_mm, copies: current.copies, is_default: current.is_default, auto_print: current.auto_print, is_active: current.is_active })
  }, [activeProfiles, profileId])

  function save(event) { event.preventDefault(); return runAction('printer-save', () => upsertKitchenPrinterProfile(hotel.id, form), 'KOT printer profile saved.') }
  async function print(order) {
    try {
      const payload = await prepareKotPrint(hotel.id,order.id,profileId || null)
      const ticket = payload?.ticket || {}
      const profile = payload?.printer_profile || {}
      const popup = window.open('', '_blank', 'width=520,height=760')
      if (!popup) throw new Error('Allow pop-ups to print the kitchen ticket.')
      popup.document.write(renderKot(ticket, hotel.hotel_name, profile))
      popup.document.close(); popup.focus(); popup.print()
      showToast(`${ticket.ticket_number} prepared · ${profile.copies || 1} cop${Number(profile.copies || 1) === 1 ? 'y' : 'ies'}.`)
    } catch (error) { showToast(error.message || 'Unable to print KOT.') }
  }

  return <section className="v11b-grid two"><form className="v11b-card" onSubmit={save}><h2>Printer profile</h2><label>Name<input value={form.name} onChange={(e) => setForm({ ...form, name: e.target.value })} required /></label><div className="v11b-form-grid"><label>Station<select value={form.station} onChange={(e) => setForm({ ...form, station: e.target.value })}>{['kitchen','bar','bakery','room_service','other'].map((v) => <option key={v} value={v}>{v.replaceAll('_',' ')}</option>)}</select></label><label>Paper<select value={form.paper_width_mm} onChange={(e) => setForm({ ...form, paper_width_mm: Number(e.target.value) })}><option value="80">80 mm</option><option value="58">58 mm</option></select></label></div><label>Copies<input type="number" min="1" max="5" value={form.copies} onChange={(e) => setForm({ ...form, copies: Number(e.target.value) })} /></label><button className="primary" disabled={busy === 'printer-save'}>Save printer profile</button></form><div className="v11b-card"><h2>Recent food orders</h2><label>Print profile<select value={profileId} onChange={(e) => setProfileId(e.target.value)}>{activeProfiles.map((profile) => <option key={profile.id} value={profile.id}>{profile.name} · {profile.paper_width_mm}mm · {profile.copies} copy</option>)}</select></label>{(data.recent_food_orders || []).length === 0 ? <Empty text="No recent food orders." /> : (data.recent_food_orders || []).slice(0,15).map((order) => <article className="v11b-row" key={order.id}><div><strong>Room {order.room_number || '—'} · {order.guest_name || 'Guest'}</strong><span>{order.status} · {money(order.total_amount)}</span></div><button onClick={() => void print(order)}>Print KOT</button></article>)}</div></section>
}

function ReportsTab({ hotel, data, busy, runAction }) {
  const tomorrow = useMemo(() => { const d = new Date(); d.setDate(d.getDate()+1); d.setHours(8,0,0,0); return toLocalDateTime(d) }, [])
  const [form, setForm] = useState({ name: 'Daily Operations Snapshot', report_key: 'occupancy_daily', frequency: 'daily', lookback_days: 1, next_run_at: tomorrow, recipients: '' })
  function save(event) { event.preventDefault(); return runAction('report-save', () => upsertScheduledReportJob(hotel.id,{ ...form, next_run_at: new Date(form.next_run_at).toISOString(), recipients: form.recipients.split(',').map((v) => v.trim()).filter(Boolean) }), 'Scheduled report saved.') }
  return <section className="v11b-grid two"><form className="v11b-card" onSubmit={save}><h2>Schedule report</h2><label>Name<input value={form.name} onChange={(e) => setForm({ ...form, name: e.target.value })} required /></label><label>Report<select value={form.report_key} onChange={(e) => setForm({ ...form, report_key: e.target.value })}>{REPORT_KEYS.map(([key,label]) => <option value={key} key={key}>{label}</option>)}</select></label><div className="v11b-form-grid"><label>Frequency<select value={form.frequency} onChange={(e) => setForm({ ...form, frequency: e.target.value })}><option value="daily">Daily</option><option value="weekly">Weekly</option><option value="monthly">Monthly</option></select></label><label>Lookback days<input type="number" min="1" max="367" value={form.lookback_days} onChange={(e) => setForm({ ...form, lookback_days: Number(e.target.value) })} /></label></div><label>Next run<input type="datetime-local" value={form.next_run_at} onChange={(e) => setForm({ ...form, next_run_at: e.target.value })} required /></label><label>Recipients (optional, comma separated)<input value={form.recipients} onChange={(e) => setForm({ ...form, recipients: e.target.value })} /></label><button className="primary" disabled={busy === 'report-save'}>Save schedule</button><button type="button" disabled={busy === 'report-run'} onClick={() => runAction('report-run', () => runDueScheduledReports(hotel.id,true), 'Scheduled report run completed.')}>Run due / force now</button></form><div className="v11b-card"><h2>Schedules & runs</h2>{(data.report_jobs || []).map((job) => <article className="v11b-row" key={job.id}><div><strong>{job.name}</strong><span>{job.report_key} · {job.frequency}</span><small>Next: {formatDate(job.next_run_at)}</small></div></article>)}<h3>Recent generated snapshots</h3>{(data.report_runs || []).length === 0 ? <Empty text="No scheduled report runs yet." /> : (data.report_runs || []).slice(0,20).map((run) => <article className="v11b-row" key={run.id}><div><strong>{run.status} · {run.row_count} rows</strong><span>{run.date_from} → {run.date_to}</span><small>{formatDate(run.generated_at)}</small></div>{run.payload && <button onClick={() => downloadJson(`stayqr-scheduled-report-${run.id}.json`,run.payload)}>Download</button>}</article>)}</div></section>
}

function Metric({ label, value }) { return <article className="v11b-metric"><span>{label}</span><strong>{value}</strong></article> }
function Empty({ text }) { return <p className="v11b-empty">{text}</p> }
function money(value) { return new Intl.NumberFormat('en-IN',{style:'currency',currency:'INR',maximumFractionDigits:2}).format(Number(value || 0)) }
function formatDate(value) { return value ? new Date(value).toLocaleString() : '—' }
function toLocalDateTime(date) { const pad=(n)=>String(n).padStart(2,'0'); return `${date.getFullYear()}-${pad(date.getMonth()+1)}-${pad(date.getDate())}T${pad(date.getHours())}:${pad(date.getMinutes())}` }
function downloadJson(name,payload) { const blob=new Blob([JSON.stringify(payload,null,2)],{type:'application/json'}); const url=URL.createObjectURL(blob); const a=document.createElement('a'); a.href=url; a.download=name; a.click(); URL.revokeObjectURL(url) }
function renderKot(ticket,hotelName,profile) { const items=(ticket.items||[]).map((item)=>`<tr><td><strong>${escapeHtml(item.quantity)} × ${escapeHtml(item.item_name)}</strong>${(item.modifiers||[]).length?`<small>${item.modifiers.map(escapeHtml).join(', ')}</small>`:''}</td></tr>`).join(''); const copies=Math.max(1,Math.min(5,Number(profile.copies||1))); const ticketBody=Array.from({length:copies},(_,index)=>`<section class="ticket ${index<copies-1?'page-break':''}"><h1>${escapeHtml(hotelName)}</h1><h2>${escapeHtml(ticket.ticket_number)}</h2><p>${escapeHtml(profile.name||'Kitchen')} · ${escapeHtml(profile.station||'kitchen')} · Copy ${index+1}/${copies}</p><hr><div class="meta"><span>Room</span><strong>${escapeHtml(ticket.room?.room_number||'—')}</strong></div><div class="meta"><span>Guest</span><strong>${escapeHtml(ticket.guest?.full_name||'Guest')}</strong></div><hr><table>${items}</table><p class="footer">StayQR · Print ${escapeHtml(ticket.print_count)}</p></section>`).join(''); return `<!doctype html><html><head><title>${escapeHtml(ticket.ticket_number)}</title><style>body{font-family:Arial,sans-serif;width:${Number(profile.paper_width_mm||80)===58?'210':'300'}px;margin:20px auto;color:#000}h1,h2,p{margin:4px 0;text-align:center}hr{border:0;border-top:1px dashed #000;margin:14px 0}table{width:100%;border-collapse:collapse}td{padding:9px 0;border-bottom:1px dashed #aaa}small{display:block;margin:4px 0 0 18px}.meta{display:flex;justify-content:space-between;margin:8px 0}.footer{margin-top:18px;font-size:11px;text-align:center}.page-break{break-after:page;page-break-after:always}</style></head><body>${ticketBody}</body></html>` }
function escapeHtml(value) { return String(value ?? '').replace(/[&<>'"]/g,(c)=>({ '&':'&amp;','<':'&lt;','>':'&gt;',"'":'&#39;','"':'&quot;' })[c]) }
