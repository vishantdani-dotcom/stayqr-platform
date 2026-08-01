import { useCallback, useEffect, useState } from 'react'
import { getCurrentHotel } from '../../lib/currentHotel'
import {
  approveHousekeepingRoomReady,
  assignHousekeepingTask,
  cancelHousekeepingTask,
  completeHousekeepingCleaning,
  createHousekeepingTask,
  getHousekeepingMobileQueue,
  getHousekeepingWorkspace,
  inspectHousekeepingTask,
  loadActiveHotelStaff,
  startHousekeepingTask,
  updateHousekeepingChecklistItem,
} from '../../lib/day13Operations'
import '../day13/Day13Operations.css'

export default function Housekeeping({ hotel: hotelProp }) {
  const [hotel, setHotel] = useState(hotelProp || null)
  const [workspace, setWorkspace] = useState({
    tasks: [],
    workload: [],
    unassigned_open_tasks: 0,
    rooms_waiting_for_ready: 0,
  })
  const [mobileQueue, setMobileQueue] = useState([])
  const [staff, setStaff] = useState([])
  const [activeTab, setActiveTab] = useState('board')
  const [selectedStaffId, setSelectedStaffId] = useState('')
  const [loading, setLoading] = useState(true)
  const [busyTaskId, setBusyTaskId] = useState('')
  const [error, setError] = useState('')
  const [success, setSuccess] = useState('')
  const [createOpen, setCreateOpen] = useState(false)
  const [createForm, setCreateForm] = useState({
    roomId: '',
    taskType: 'room_cleaning',
    priority: 'normal',
    dueAt: '',
    notes: '',
  })

  const loadData = useCallback(async (showSpinner = true) => {
    if (showSpinner) setLoading(true)
    setError('')

    try {
      const activeHotel = hotel || (await getCurrentHotel())
      if (!activeHotel?.id) throw new Error('No active hotel is selected.')
      if (!hotel) setHotel(activeHotel)

      const [workspaceData, staffData] = await Promise.all([
        getHousekeepingWorkspace(activeHotel.id),
        loadActiveHotelStaff(activeHotel.id),
      ])

      setWorkspace(workspaceData || {})
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
      const data = await getHousekeepingMobileQueue(
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
    [
      'pending',
      'assigned',
      'in_progress',
      'cleaning_complete',
      'inspection_failed',
      'inspected',
    ].includes(task.status)
  )

  const stats = {
    open: openTasks.length,
    unassigned: workspace.unassigned_open_tasks || 0,
    inProgress: tasks.filter((task) => task.status === 'in_progress').length,
    inspection: tasks.filter((task) =>
      ['cleaning_complete', 'inspection_failed', 'inspected'].includes(task.status)
    ).length,
    ready: tasks.filter((task) => task.status === 'ready').length,
    roomsWaiting: workspace.rooms_waiting_for_ready || 0,
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

  const createTask = (event) => {
    event.preventDefault()
    runTaskAction('new', 'Housekeeping task created.', async () => {
      await createHousekeepingTask(hotel.id, createForm)
      setCreateOpen(false)
      setCreateForm({
        roomId: '',
        taskType: 'room_cleaning',
        priority: 'normal',
        dueAt: '',
        notes: '',
      })
    })
  }

  const assignTask = (task) => {
    const staffId = window.prompt(
      `Assign ${task.room?.room_number || task.room_number}. Paste staff ID:\n${staff
        .map((member) => `${member.full_name}: ${member.id}`)
        .join('\n')}`
    )
    if (!staffId) return

    runTaskAction(task.id, 'Task assigned.', () =>
      assignHousekeepingTask(
        hotel.id,
        task.id,
        staffId.trim(),
        task.priority || 'normal',
        task.due_at || null
      )
    )
  }

  const inspectTask = (task, result) => {
    const notes = window.prompt(
      result === 'passed' ? 'Inspection notes (optional):' : 'Why did inspection fail?'
    )
    if (result === 'failed' && !notes?.trim()) return

    runTaskAction(task.id, `Inspection ${result}.`, () =>
      inspectHousekeepingTask(hotel.id, task.id, result, notes || '')
    )
  }

  if (loading) {
    return <div className="day13-page">Loading housekeeping operations…</div>
  }

  return (
    <div className="day13-page">
      <div className="day13-header">
        <div>
          <div className="day13-kicker">Day 13 · Operational readiness</div>
          <h1>Housekeeping</h1>
          <p>
            Assignment, workload, required cleaning checklist, inspection, rework and
            explicit room-ready approval.
          </p>
        </div>
        <div className="day13-actions">
          <button className="day13-button" onClick={() => loadData()} type="button">
            Refresh
          </button>
          <button
            className="day13-button day13-button-primary"
            type="button"
            onClick={() => setCreateOpen(true)}
          >
            Create task
          </button>
        </div>
      </div>

      {error && <div className="day13-alert">{error}</div>}
      {success && <div className="day13-success">{success}</div>}

      <div className="day13-stats">
        <Stat label="Open tasks" value={stats.open} />
        <Stat label="Unassigned" value={stats.unassigned} />
        <Stat label="In progress" value={stats.inProgress} />
        <Stat label="Inspection queue" value={stats.inspection} />
        <Stat label="Ready" value={stats.ready} />
        <Stat label="Rooms waiting" value={stats.roomsWaiting} />
      </div>

      <div className="day13-tabs">
        {[
          ['board', 'Task board'],
          ['workload', 'Staff workload'],
          ['mobile', 'Mobile staff view'],
          ['history', 'Completed history'],
        ].map(([id, label]) => (
          <button
            key={id}
            className={`day13-tab ${activeTab === id ? 'day13-tab-active' : ''}`}
            type="button"
            onClick={() => setActiveTab(id)}
          >
            {label}
          </button>
        ))}
      </div>

      {activeTab === 'board' && (
        <div className="day13-grid">
          {openTasks.length === 0 ? (
            <div className="day13-panel day13-empty">No open housekeeping tasks.</div>
          ) : (
            openTasks.map((task) => (
              <HousekeepingCard
                key={task.id}
                task={task}
                busy={busyTaskId === task.id}
                onAssign={() => assignTask(task)}
                onStart={() =>
                  runTaskAction(task.id, 'Cleaning started.', () =>
                    startHousekeepingTask(hotel.id, task.id)
                  )
                }
                onItem={(item, status) =>
                  runTaskAction(task.id, 'Checklist updated.', () =>
                    updateHousekeepingChecklistItem(
                      hotel.id,
                      task.id,
                      item.id,
                      status,
                      ''
                    )
                  )
                }
                onComplete={() =>
                  runTaskAction(task.id, 'Cleaning marked complete.', () =>
                    completeHousekeepingCleaning(hotel.id, task.id, '')
                  )
                }
                onInspect={(result) => inspectTask(task, result)}
                onReady={() =>
                  runTaskAction(task.id, 'Room approved ready.', () =>
                    approveHousekeepingRoomReady(hotel.id, task.id, '')
                  )
                }
                onCancel={() => {
                  const reason = window.prompt('Cancellation reason:')
                  if (!reason?.trim()) return
                  runTaskAction(task.id, 'Task cancelled.', () =>
                    cancelHousekeepingTask(hotel.id, task.id, reason)
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
                <Stat label="Urgent" value={row.urgent_tasks || 0} />
                <Stat label="In progress" value={row.in_progress_tasks || 0} />
                <Stat label="Ready today" value={row.ready_today || 0} />
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
                <div className="day13-kicker">{task.priority} priority</div>
                <div className="day13-mobile-room">Room {task.room_number}</div>
                <span className={`day13-status day13-status-${task.status}`}>
                  {task.status}
                </span>
                <p className="day13-muted">{task.notes || task.task_type}</p>
                <div className="day13-small">
                  Checklist {task.completed_items || 0}/{task.total_items || 0}
                </div>
                <Progress
                  completed={task.completed_items || 0}
                  total={task.total_items || 0}
                />
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
                  <th>Room</th>
                  <th>Task</th>
                  <th>Status</th>
                  <th>Cleaning</th>
                  <th>Inspection</th>
                  <th>Ready</th>
                </tr>
              </thead>
              <tbody>
                {tasks
                  .filter((task) => ['ready', 'completed', 'cancelled'].includes(task.status))
                  .map((task) => (
                    <tr key={task.id}>
                      <td>{task.room?.room_number || task.room_number}</td>
                      <td>{task.task_type}</td>
                      <td>
                        <span className={`day13-status day13-status-${task.status}`}>
                          {task.status}
                        </span>
                      </td>
                      <td>{formatDate(task.cleaning_completed_at)}</td>
                      <td>{task.inspection_status || '—'}</td>
                      <td>{formatDate(task.room_ready_at)}</td>
                    </tr>
                  ))}
              </tbody>
            </table>
          </div>
        </div>
      )}

      {createOpen && (
        <div className="day13-overlay">
          <form className="day13-modal" onSubmit={createTask}>
            <div className="day13-modal-header">
              <h2>Create housekeeping task</h2>
              <button
                className="day13-button"
                type="button"
                onClick={() => setCreateOpen(false)}
              >
                ×
              </button>
            </div>
            <div className="day13-modal-body day13-form">
              <Field label="Room ID" full>
                <input
                  required
                  placeholder="Paste room UUID from Rooms workspace"
                  value={createForm.roomId}
                  onChange={(event) =>
                    setCreateForm((current) => ({ ...current, roomId: event.target.value }))
                  }
                />
              </Field>
              <Field label="Task type">
                <select
                  value={createForm.taskType}
                  onChange={(event) =>
                    setCreateForm((current) => ({
                      ...current,
                      taskType: event.target.value,
                    }))
                  }
                >
                  <option value="room_cleaning">Room cleaning</option>
                  <option value="stayover_cleaning">Stayover cleaning</option>
                  <option value="deep_cleaning">Deep cleaning</option>
                  <option value="turndown">Turndown</option>
                </select>
              </Field>
              <Field label="Priority">
                <select
                  value={createForm.priority}
                  onChange={(event) =>
                    setCreateForm((current) => ({
                      ...current,
                      priority: event.target.value,
                    }))
                  }
                >
                  <option value="low">Low</option>
                  <option value="normal">Normal</option>
                  <option value="high">High</option>
                  <option value="urgent">Urgent</option>
                </select>
              </Field>
              <Field label="Due at">
                <input
                  type="datetime-local"
                  value={createForm.dueAt}
                  onChange={(event) =>
                    setCreateForm((current) => ({ ...current, dueAt: event.target.value }))
                  }
                />
              </Field>
              <Field label="Notes" full>
                <textarea
                  value={createForm.notes}
                  onChange={(event) =>
                    setCreateForm((current) => ({ ...current, notes: event.target.value }))
                  }
                />
              </Field>
            </div>
            <div className="day13-modal-footer">
              <button
                className="day13-button"
                type="button"
                onClick={() => setCreateOpen(false)}
              >
                Cancel
              </button>
              <button className="day13-button day13-button-primary" disabled={busyTaskId === 'new'}>
                Create task
              </button>
            </div>
          </form>
        </div>
      )}
    </div>
  )
}

function HousekeepingCard({
  task,
  busy,
  onAssign,
  onStart,
  onItem,
  onComplete,
  onInspect,
  onReady,
  onCancel,
}) {
  const items = task.items || []
  const complete = items.filter((item) =>
    ['completed', 'not_applicable'].includes(item.item_status)
  ).length

  return (
    <div className="day13-card">
      <div className="day13-inline-actions" style={{ justifyContent: 'space-between' }}>
        <div>
          <div className="day13-kicker">{task.priority} priority</div>
          <h3>Room {task.room?.room_number || task.room_number}</h3>
          <div className="day13-muted">
            {task.task_type?.replaceAll('_', ' ')} · {task.assigned_to || 'Unassigned'}
          </div>
        </div>
        <span className={`day13-status day13-status-${task.status}`}>
          {task.status}
        </span>
      </div>

      <div className="day13-small" style={{ marginTop: 12 }}>
        Checklist {complete}/{items.length}
      </div>
      <Progress completed={complete} total={items.length} />

      <div className="day13-checklist">
        {items.map((item) => (
          <label className="day13-check" key={item.id}>
            <input
              type="checkbox"
              disabled={
                busy ||
                !['assigned', 'in_progress', 'inspection_failed'].includes(task.status)
              }
              checked={['completed', 'not_applicable'].includes(item.item_status)}
              onChange={(event) => onItem(item, event.target.checked ? 'completed' : 'pending')}
            />
            <span>{item.label}</span>
            <small className="day13-muted">{item.is_required ? 'Required' : 'Optional'}</small>
          </label>
        ))}
      </div>

      <div className="day13-inline-actions" style={{ marginTop: 14 }}>
        {['pending', 'assigned', 'inspection_failed'].includes(task.status) && (
          <button className="day13-button" type="button" disabled={busy} onClick={onAssign}>
            Assign
          </button>
        )}
        {['assigned', 'inspection_failed'].includes(task.status) && (
          <button
            className="day13-button day13-button-primary"
            type="button"
            disabled={busy}
            onClick={onStart}
          >
            Start
          </button>
        )}
        {task.status === 'in_progress' && (
          <button
            className="day13-button day13-button-primary"
            type="button"
            disabled={busy}
            onClick={onComplete}
          >
            Complete cleaning
          </button>
        )}
        {task.status === 'cleaning_complete' && (
          <>
            <button
              className="day13-button day13-button-success"
              type="button"
              disabled={busy}
              onClick={() => onInspect('passed')}
            >
              Pass inspection
            </button>
            <button
              className="day13-button day13-button-danger"
              type="button"
              disabled={busy}
              onClick={() => onInspect('failed')}
            >
              Fail inspection
            </button>
          </>
        )}
        {task.status === 'inspected' && (
          <button
            className="day13-button day13-button-success"
            type="button"
            disabled={busy}
            onClick={onReady}
          >
            Approve room ready
          </button>
        )}
        {!['ready', 'completed', 'cancelled'].includes(task.status) && (
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

function Field({ label, children, full = false }) {
  return (
    <div className={`day13-field ${full ? 'day13-field-full' : ''}`}>
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

function Progress({ completed, total }) {
  const width = total ? Math.min(100, Math.round((completed / total) * 100)) : 0
  return (
    <div className="day13-progress">
      <span style={{ width: `${width}%` }} />
    </div>
  )
}

function formatDate(value) {
  return value ? new Date(value).toLocaleString('en-IN') : '—'
}
