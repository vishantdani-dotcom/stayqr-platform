import { useEffect, useId, useRef, useState } from 'react'
import { createPortal } from 'react-dom'
import './ActionDialog.css'

// In-page replacement for native prompt/confirm. The HTML dialog supplies modal
// focus containment; cancellation never invokes the server action.
export default function ActionDialog({
  title, description, label, initialValue = '', options, required = true,
  confirmLabel = 'Confirm', danger = false, onConfirm, onClose,
}) {
  const dialogRef = useRef(null)
  const fieldRef = useRef(null)
  const submitting = useRef(false)
  const fieldId = useId()
  const [value, setValue] = useState(initialValue)
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState('')

  useEffect(() => {
    const dialog = dialogRef.current
    const previousFocus = document.activeElement
    dialog.showModal()
    fieldRef.current?.focus()
    return () => {
      dialog.close()
      if (previousFocus?.isConnected) previousFocus.focus()
    }
  }, [])

  const close = () => {
    if (!submitting.current) onClose()
  }

  async function submit(event) {
    event.preventDefault()
    if (submitting.current) return
    const normalized = value.trim()
    if (required && !normalized) {
      setError(`${label} is required.`)
      fieldRef.current?.focus()
      return
    }
    if (options && !options.some((option) => option.value === normalized)) {
      setError('Select an active staff member from this hotel.')
      return
    }
    submitting.current = true
    setBusy(true)
    setError('')
    try {
      await onConfirm(normalized)
      onClose()
    } catch (actionError) {
      setError(actionError.message || 'The action could not be completed. Please try again.')
    } finally {
      submitting.current = false
      setBusy(false)
    }
  }

  return createPortal(
    <dialog ref={dialogRef} className="stayqr-action-dialog" aria-labelledby={`${fieldId}-title`}
      aria-describedby={`${fieldId}-description`} onCancel={(event) => { event.preventDefault(); close() }}>
      <form onSubmit={submit} aria-busy={busy}>
        <header>
          <h2 id={`${fieldId}-title`}>{title}</h2>
          <button type="button" className="stayqr-action-close" aria-label="Close dialog" disabled={busy} onClick={close}>×</button>
        </header>
        <p id={`${fieldId}-description`}>{description}</p>
        <label htmlFor={fieldId}>{label}{required ? ' *' : ''}</label>
        {options ? (
          <select ref={fieldRef} id={fieldId} value={value} required={required} disabled={busy}
            onChange={(event) => { setValue(event.target.value); setError('') }}>
            <option value="">Select staff member</option>
            {options.map((option) => <option key={option.value} value={option.value}>{option.label}</option>)}
          </select>
        ) : (
          <textarea ref={fieldRef} id={fieldId} rows={3} value={value} required={required} disabled={busy} maxLength={2000}
            onChange={(event) => { setValue(event.target.value); setError('') }} />
        )}
        {options?.length === 0 && <p role="status">No active staff are available in this hotel. Add staff before assigning this task.</p>}
        {error && <p className="stayqr-action-error" role="alert">{error}</p>}
        <footer>
          <button type="button" disabled={busy} onClick={close}>Back</button>
          <button type="submit" className={danger ? 'danger' : 'primary'} disabled={busy || options?.length === 0}>
            {busy ? 'Saving…' : confirmLabel}
          </button>
        </footer>
      </form>
    </dialog>,
    document.body
  )
}
