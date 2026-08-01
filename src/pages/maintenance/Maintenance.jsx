import { useCallback, useEffect, useState } from 'react'
import { getCurrentHotel } from '../../lib/currentHotel'
import {
  assignMaintenanceTask,
  cancelMaintenanceTask,
  getMaintenanceMobileQueue,
  getMaintenanceWorkspace,
  getRoomInventoryWorkspace,
  holdMaintenanceTask,
  loadActiveHotelStaff,
  reportMaintenanceTask,
  resolveMaintenanceTask,
  startMaintenanceTask,
  verifyMaintenanceTask,
} from '../../lib/day13Operations'
import '../day13/Day13Operations.css'

const EMPTY_FORM = {
  roomId: '',
  title: '',
  description: '',
  category: 'other',
  severity: 'medium',
  inventoryImpact: 'none',
  expectedReturnDate: '',
  dueAt: '',
  requiresCleaning: true,
}

export default function Maintenance({ hotel: hotelProp }) {
  const [hotel, setHotel] = useState(hotelProp || null)
  const [workspace, setWorkspace] = useState({
    tasks: [],
    workload: [],
    unassigned_open_tasks: 0,
    offline_rooms: 0,
    active_room_blocks: 0,
  })
  const [rooms, setRooms] = useState([])
  const [staff, setStaff] = useState([])
  const [mobileQueue, setMobileQueue] = useState([])
  const [selectedStaffId, setSelectedStaffId] = useState('')
  const [activeTab, setActiveTab] = useState('board')
  const [reportOpen, setReportOpen] = useState(false)
  const [reportForm, setReportForm] = useState(EMPTY_FORM)
  const [loading, setLoading] = useState(true)
  const [busyTaskId, setBusyTaskId] = useState('')
  const [error, setError] = useState('')
  const [success, setSuccess] = useState('')

  const loadData = useCallback(async (showSpinner = true) => {
    if (showSpinner) setLoading(true)
    setError('')

    try {
      const activeHotel = hotel || (await getCurrentHotel())
      if (!activeHotel?.id) throw new Error('No active hotel is selected.')
      if (!hotel) setHotel(activeHotel)

      const [maintenanceData, roomData, staffData] = await Promise.all([
        getMaintenanceWorkspace(activeHotel.id),
        getRoomInventoryWorkspace(activeHotel.id),
        loadActiveHotelStaff(activeHotel.id),
      ])

      setWorkspace(maintenanceData || {})
      setRooms((roomData?.rooms || []).filter((room) => room.is_active))
      setStaff(staffData)
    } catch (loadError) {
      setError(loadError.message)
    } finally {
      if (showSpinner) setLoading(false)
    }
  }, [hotel])

  const hotelId = hotel?.id || null

  const loadMobile = useCallback(async () => {
    if (!hotelId) return

    try {
      const data = await getMaintenanceMobileQueue(
        hotelId,
        selectedStaffId || null
      )
      setMobileQueue(data || [])
    } catch (loadError) {
      setError(loadError.message)
    }
  }, [hotelId, selectedStaffId])

  useEffect(() => {
    loadData()
  }, [loadData])

  useEffect(() => {
    if (activeTab === 'mobile') loadMobile()
  }, [activeTab, loadMobile])

  const tasks = workspace.tasks || []
  const openTasks = tasks.filter((task) =>
    ['reported', 'assigned', 'in_progress', 'on_hold', 'resolved'].includes(
      task.status
    )
  )

  const stats = {
    open: openTasks.length,
    unassigned: workspace.unassigned_open_tasks || 0,
    offline: workspace.offline_rooms || 0,
    blocks: workspace.active_room_blocks || 0,
    critical: openTasks.filter((task) => task.severity === 'critical').length,
    verified: tasks.filter((task) => task.status === 'verified').length,
  }

  const runTaskAction = async (taskId, message, action) => {
    setBusyTaskId(taskId)
    setError('')
    setSuccess('')

    try {
      await action()
      setSuccess(message)
      await loadData(false)
      if (activeTab === 'mobile') await loadMobile()
    } catch (actionError) {
      setError(actionError.message)
    } finally {
      setBusyTaskId('')
    }
  }

  const submitReport = (event) => {
    event.preventDefault()

    if (
      reportForm.inventoryImpact !== 'none' &&
      !reportForm.expectedReturnDate
    ) {
      setError('Offline maintenance requires an expected return date.')
      return
    }

    runTaskAction('new', 'Maintenance task reported.', async () => {
      await reportMaintenanceTask(hotel.id, reportForm)
      setReportOpen(false)
      setReportForm(EMPTY_FORM)
    })
  }

  const assignTask = (task) => {
    const staffId = window.prompt(
      `Assign ${task.task_number}. Paste staff ID:\n${staff
        .map((member) => `${member.full_name}: ${member.id}`)
        .join('\n')}`
    )
    if (!staffId) return

    runTaskAction(task.id, 'Maintenance task assigned.', () =>
      assignMaintenanceTask(hotel.id, task.id, staffId.trim(), task.due_at || null)
    )
  }

  if (loading) {
    return <div className="day13-page">Loading maintenance operations…</div>
  }

  return (
    <div className="day13-page">
      <div className="day13-header">
        <div>
          <div className="day13-kicker">Day 13 · Inventory protection</div>
          <h1>Maintenance</h1>
          <p>
            Track defects with explicit inventory impact, authoritative room blocks,
            verification evidence and housekeeping handoff.
          </p>
        </div>
        <div className="day13-actions">
          <button className="day13-button" type="button" onClick={() => loadData()}>
            Refresh
          </button>
          <button
            className="day13-button day13-button-primary"
            type="button"
            onClick={() => setReportOpen(true)}
          >
            Report issue
          </button>
        </div>
      </div>

      {error && <div className="day13-alert">{error}</div>}
      {success && <div className="day13-success">{success}</div>}

      <div className="day13-stats">
        <Stat label="Open tasks" value={stats.open} />
        <Stat label="Unassigned" value={stats.unassigned} />
        <Stat label="Offline rooms" value={stats.offline} />
        <Stat label="Active blocks" value={stats.blocks} />
        <Stat label="Critical" value={stats.critical} />
        <Stat label="Verified" value={stats.verified} />
      </div>

      <div className="day13-tabs">
        {[
          ['board', 'Maintenance board'],
          ['workload', 'Staff workload'],
          ['mobile', 'Mobile staff view'],
          ['history', 'Verified history'],
        ].map(([id, label]) => (
          <button
            key={id}
            type="button"
            className={`day13-tab ${activeTab === id ? 'day13-tab-active' : ''}`}
            onClick={() => setActiveTab(id)}
          >
            {label}
          </button>
        ))}
      </div>

      {activeTab === 'board' && (
        <div className="day13-grid">
          {openTasks.length === 0 ? (
            <div className="day13-panel day13-empty">No open maintenance tasks.</div>
          ) : (
            openTasks.map((task) => (
              <MaintenanceCard
                key={task.id}
                task={task}
                busy={busyTaskId === task.id}
                onAssign={() => assignTask(task)}
                onStart={() =>
                  runTaskAction(task.id, 'Maintenance work started.', () =>
                    startMaintenanceTask(hotel.id, task.id)
                  )
                }
                onHold={() => {
                  const reason = window.prompt('Hold reason:')
                  if (!reason?.trim()) return
                  runTaskAction(task.id, 'Maintenance task put on hold.', () =>
                    holdMaintenanceTask(hotel.id, task.id, reason)
                  )
                }}
                onResolve={() => {
                  const notes = window.prompt('Resolution notes:')
                  if (!notes?.trim()) return
                  const requiresCleaning = window.confirm(
                    'Does this room require housekeeping cleaning before returning to inventory?'
                  )
                  runTaskAction(task.id, 'Maintenance task resolved.', () =>
                    resolveMaintenanceTask(
                      hotel.id,
                      task.id,
                      notes,
                      requiresCleaning
                    )
                  )
                }}
                onVerify={() => {
                  const notes = window.prompt('Verification notes (optional):') || ''
                  runTaskAction(task.id, 'Maintenance verified.', () =>
                    verifyMaintenanceTask(hotel.id, task.id, notes)
                  )
                }}
                onCancel={() => {
                  const reason = window.prompt('Cancellation reason:')
                  if (!reason?.trim()) return
                  runTaskAction(task.id, 'Maintenance task cancelled.', () =>
                    cancelMaintenanceTask(hotel.id, task.id, reason)
                  )
                }}
              />
            ))
          )}
        </div>
      )}

      {activeTab === 'workload' && (
        <div className="day13-grid">
          {(workspace.workload || []).map((row) => (
            <div className="day13-card" key={row.staff_id}>
              <h3>{row.staff_name}</h3>
              <div className="day13-muted">{row.role || 'Staff'}</div>
              <div className="day13-stats" style={{ marginTop: 14, marginBottom: 0 }}>
                <Stat label="Open" value={row.open_tasks || 0} />
                <Stat label="Critical" value={row.critical_tasks || 0} />
                <Stat label="In progress" value={row.in_progress_tasks || 0} />
              </div>
            </div>
          ))}
        </div>
      )}

      {activeTab === 'mobile' && (
        <>
          <div className="day13-panel" style={{ marginBottom: 14 }}>
            <div className="day13-panel-body day13-inline-actions">
              <select
                value={selectedStaffId}
                onChange={(event) => setSelectedStaffId(event.target.value)}
              >
                <option value="">All staff and unassigned</option>
                {staff.map((member) => (
                  <option key={member.id} value={member.id}>
                    {member.full_name}
                  </option>
                ))}
              </select>
              <button className="day13-button" type="button" onClick={loadMobile}>
                Load mobile queue
              </button>
            </div>
          </div>
          <div className="day13-mobile-grid">
            {mobileQueue.map((task) => (
              <div className="day13-mobile-card" key={task.task_id}>
                <div className="day13-kicker">{task.severity} severity</div>
                <div className="day13-mobile-room">Room {task.room_number}</div>
                <h3>{task.title}</h3>
                <span className={`day13-status day13-status-${task.status}`}>
                  {task.status}
                </span>
                <p className="day13-muted">
                  {task.category} · {task.inventory_impact.replaceAll('_', ' ')}
                </p>
                <div className="day13-small">
                  Return: {task.expected_return_date || 'Not offline'}
                </div>
              </div>
            ))}
          </div>
        </>
      )}

      {activeTab === 'history' && (
        <div className="day13-panel">
          <div className="day13-table-wrap">
            <table className="day13-table">
              <thead>
                <tr>
                  <th>Task</th>
                  <th>Room</th>
                  <th>Issue</th>
                  <th>Impact</th>
                  <th>Status</th>
                  <th>Verification</th>
                </tr>
              </thead>
              <tbody>
                {tasks
                  .filter((task) => ['verified', 'cancelled'].includes(task.status))
                  .map((task) => (
                    <tr key={task.id}>
                      <td>{task.task_number}</td>
                      <td>{task.room?.room_number || '—'}</td>
                      <td>
                        {task.title}
                        <div className="day13-muted day13-small">{task.category}</div>
                      </td>
                      <td>{task.inventory_impact.replaceAll('_', ' ')}</td>
                      <td>
                        <span className={`day13-status day13-status-${task.status}`}>
                          {task.status}
                        </span>
                      </td>
                      <td>{formatDate(task.verified_at || task.cancelled_at)}</td>
                    </tr>
                  ))}
              </tbody>
            </table>
          </div>
        </div>
      )}

      {reportOpen && (
        <div className="day13-overlay">
          <form className="day13-modal" onSubmit={submitReport}>
            <div className="day13-modal-header">
              <h2>Report maintenance issue</h2>
              <button
                type="button"
                className="day13-button"
                onClick={() => setReportOpen(false)}
              >
                ×
              </button>
            </div>
            <div className="day13-modal-body day13-form">
              <Field label="Room">
                <select
                  required
                  value={reportForm.roomId}
                  onChange={(event) =>
                    setReportForm((current) => ({ ...current, roomId: event.target.value }))
                  }
                >
                  <option value="">Select room</option>
                  {rooms.map((room) => (
                    <option key={room.id} value={room.id}>
                      {room.room_number} · {room.status}
                    </option>
                  ))}
                </select>
              </Field>
              <Field label="Title" wide>
                <input
                  required
                  value={reportForm.title}
                  onChange={(event) =>
                    setReportForm((current) => ({ ...current, title: event.target.value }))
                  }
                />
              </Field>
              <Field label="Category">
                <select
                  value={reportForm.category}
                  onChange={(event) =>
                    setReportForm((current) => ({
                      ...current,
                      category: event.target.value,
                    }))
                  }
                >
                  {[
                    'electrical',
                    'plumbing',
                    'hvac',
                    'appliance',
                    'furniture',
                    'structural',
                    'safety',
                    'pest_control',
                    'internet',
                    'other',
                  ].map((value) => (
                    <option key={value} value={value}>
                      {value.replaceAll('_', ' ')}
                    </option>
                  ))}
                </select>
              </Field>
              <Field label="Severity">
                <select
                  value={reportForm.severity}
                  onChange={(event) =>
                    setReportForm((current) => ({
                      ...current,
                      severity: event.target.value,
                    }))
                  }
                >
                  <option value="low">Low</option>
                  <option value="medium">Medium</option>
                  <option value="high">High</option>
                  <option value="critical">Critical</option>
                </select>
              </Field>
              <Field label="Inventory impact">
                <select
                  value={reportForm.inventoryImpact}
                  onChange={(event) =>
                    setReportForm((current) => ({
                      ...current,
                      inventoryImpact: event.target.value,
                    }))
                  }
                >
                  <option value="none">Track only</option>
                  <option value="maintenance">Maintenance</option>
                  <option value="out_of_order">Out of order</option>
                </select>
              </Field>
              <Field label="Expected return">
                <input
                  type="date"
                  required={reportForm.inventoryImpact !== 'none'}
                  value={reportForm.expectedReturnDate}
                  onChange={(event) =>
                    setReportForm((current) => ({
                      ...current,
                      expectedReturnDate: event.target.value,
                    }))
                  }
                />
              </Field>
              <Field label="Due at">
                <input
                  type="datetime-local"
                  value={reportForm.dueAt}
                  onChange={(event) =>
                    setReportForm((current) => ({ ...current, dueAt: event.target.value }))
                  }
                />
              </Field>
              <Field label="Description" full>
                <textarea
                  value={reportForm.description}
                  onChange={(event) =>
                    setReportForm((current) => ({
                      ...current,
                      description: event.target.value,
                    }))
                  }
                />
              </Field>
              <div className="day13-field day13-field-full">
                <label className="day13-inline-actions">
                  <input
                    type="checkbox"
                    checked={reportForm.requiresCleaning}
                    onChange={(event) =>
                      setReportForm((current) => ({
                        ...current,
                        requiresCleaning: event.target.checked,
                      }))
                    }
                  />
                  Require housekeeping cleaning after verification
                </label>
              </div>
            </div>
            <div className="day13-modal-footer">
              <button
                className="day13-button"
                type="button"
                onClick={() => setReportOpen(false)}
              >
                Cancel
              </button>
              <button className="day13-button day13-button-primary" disabled={busyTaskId === 'new'}>
                Report issue
              </button>
            </div>
          </form>
        </div>
      )}
    </div>
  )
}

function MaintenanceCard({
  task,
  busy,
  onAssign,
  onStart,
  onHold,
  onResolve,
  onVerify,
  onCancel,
}) {
  return (
    <div className="day13-card">
      <div className="day13-inline-actions" style={{ justifyContent: 'space-between' }}>
        <div>
          <div className="day13-kicker">{task.task_number}</div>
          <h3>
            Room {task.room?.room_number || '—'} · {task.title}
          </h3>
          <div className="day13-muted">
            {task.category.replaceAll('_', ' ')} · {task.assigned_staff_id ? 'Assigned' : 'Unassigned'}
          </div>
        </div>
        <span className={`day13-status day13-status-${task.status}`}>
          {task.status}
        </span>
      </div>

      <p>{task.description || 'No additional description.'}</p>

      <div className="day13-grid">
        <div className="day13-small">
          <strong>Severity</strong>
          <div>{task.severity}</div>
        </div>
        <div className="day13-small">
          <strong>Inventory</strong>
          <div>{task.inventory_impact.replaceAll('_', ' ')}</div>
        </div>
        <div className="day13-small">
          <strong>Expected return</strong>
          <div>{task.expected_return_date || 'Not offline'}</div>
        </div>
      </div>

      <div className="day13-inline-actions" style={{ marginTop: 15 }}>
        {['reported', 'assigned', 'on_hold'].includes(task.status) && (
          <button className="day13-button" type="button" disabled={busy} onClick={onAssign}>
            Assign
          </button>
        )}
        {['assigned', 'on_hold'].includes(task.status) && (
          <button
            className="day13-button day13-button-primary"
            type="button"
            disabled={busy}
            onClick={onStart}
          >
            {task.status === 'on_hold' ? 'Resume' : 'Start'}
          </button>
        )}
        {task.status === 'in_progress' && (
          <>
            <button className="day13-button" type="button" disabled={busy} onClick={onHold}>
              Hold
            </button>
            <button
              className="day13-button day13-button-primary"
              type="button"
              disabled={busy}
              onClick={onResolve}
            >
              Resolve
            </button>
          </>
        )}
        {task.status === 'resolved' && (
          <button
            className="day13-button day13-button-success"
            type="button"
            disabled={busy}
            onClick={onVerify}
          >
            Verify & release
          </button>
        )}
        {!['resolved', 'verified', 'cancelled'].includes(task.status) && (
          <button
            className="day13-button day13-button-danger"
            type="button"
            disabled={busy}
            onClick={onCancel}
          >
            Cancel
          </button>
        )}
      </div>
    </div>
  )
}

function Field({ label, children, wide = false, full = false }) {
  return (
    <div
      className={`day13-field ${wide ? 'day13-field-wide' : ''} ${
        full ? 'day13-field-full' : ''
      }`}
    >
      <label>{label}</label>
      {children}
    </div>
  )
}

function Stat({ label, value }) {
  return (
    <div className="day13-stat">
      <span>{label}</span>
      <strong>{value}</strong>
    </div>
  )
}

function formatDate(value) {
  return value ? new Date(value).toLocaleString('en-IN') : '—'
}
