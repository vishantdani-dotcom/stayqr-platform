import { useState } from 'react'
import { createRoot } from 'react-dom/client'
import ActionDialog from '../../src/components/modals/ActionDialog'

// Local-only browser fixture: imports the real component, with no authentication,
// network calls, hotel data, or production entry-point import.
export default function DialogFixture() {
  const [mode, setMode] = useState('required')
  const [open, setOpen] = useState(false)
  const [fail, setFail] = useState(false)
  const [attempts, setAttempts] = useState(0)
  const [saves, setSaves] = useState([])
  const options = mode === 'staff' ? [{ value: 'staff-a', label: 'Test Cleaner A' }, { value: 'staff-b', label: 'Test Cleaner B' }] : mode === 'empty' ? [] : undefined
  return <main style={{ fontFamily: 'sans-serif', padding: 24 }}>
    <h1>Pilot action dialog regression fixture</h1>
    <p>Local component test only. No server or payment calls.</p>
    <label>Test mode <select value={mode} onChange={(event) => setMode(event.target.value)}>
      <option value="required">Required reason</option><option value="optional">Optional notes</option>
      <option value="staff">Staff selector</option><option value="empty">No active staff</option>
    </select></label>
    <label><input type="checkbox" checked={fail} onChange={(event) => setFail(event.target.checked)} />Simulate server failure</label>
    <button onClick={() => setOpen(true)}>Open dialog</button>
    <p role="status">Attempts: {attempts}; Successful saves: {saves.length}</p>
    <pre aria-label="Saved values">{JSON.stringify(saves)}</pre>
    {open && <ActionDialog title="Test hotel action" description="Only this local fixture is affected."
      label={options ? 'Staff member' : mode === 'optional' ? 'Inspection notes (optional)' : 'Cancellation reason'}
      required={mode !== 'optional'} options={options} confirmLabel="Save test action"
      onClose={() => setOpen(false)} onConfirm={async (value) => {
        setAttempts((count) => count + 1)
        await new Promise((resolve) => setTimeout(resolve, 1500))
        if (fail) throw new Error('Simulated server rejection. Your input is retained.')
        setSaves((previous) => [...previous, value])
      }} />}
  </main>
}

createRoot(document.getElementById('root')).render(<DialogFixture />)
