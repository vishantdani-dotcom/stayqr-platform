import { useEffect, useRef, useState } from 'react'
import { supabase } from '../../lib/supabase'
import './GlobalSearch.css'

const ENTITY_LABELS = {
  room: 'Room',
  guest: 'Guest',
  reservation: 'Reservation',
  service_request: 'Service request',
  invoice: 'Invoice',
}

export default function GlobalSearch({ open, hotelId, onClose, onNavigate }) {
  const [query, setQuery] = useState('')
  const [results, setResults] = useState([])
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState('')
  const inputRef = useRef(null)
  const requestRef = useRef(0)

  useEffect(() => {
    if (!open) return undefined
    setQuery('')
    setResults([])
    setError('')
    window.setTimeout(() => inputRef.current?.focus(), 0)

    const handleKeyDown = (event) => {
      if (event.key === 'Escape') onClose()
    }
    document.addEventListener('keydown', handleKeyDown)
    return () => document.removeEventListener('keydown', handleKeyDown)
  }, [hotelId, onClose, open])

  useEffect(() => {
    if (!open || !hotelId || query.trim().length < 2) {
      requestRef.current += 1
      setResults([])
      setLoading(false)
      setError('')
      return undefined
    }

    const requestId = requestRef.current + 1
    requestRef.current = requestId
    setLoading(true)
    setError('')

    const timer = window.setTimeout(async () => {
      const { data, error: searchError } = await supabase.rpc(
        'search_hotel_workspace',
        {
          target_hotel_id: hotelId,
          search_query: query.trim(),
          result_limit: 35,
        }
      )

      if (requestRef.current !== requestId) return
      if (searchError) {
        setResults([])
        setError(searchError.message || 'StayQR search is unavailable.')
      } else {
        setResults(data || [])
      }
      setLoading(false)
    }, 260)

    return () => window.clearTimeout(timer)
  }, [hotelId, open, query])

  if (!open) return null

  function selectResult(result) {
    const destination = result.entity_type === 'reservation'
      ? { reservationId: result.entity_id }
      : { entityType: result.entity_type, entityId: result.entity_id }

    onNavigate?.(result.section, {
      ...destination,
      source: 'global-search',
    })
    onClose()
  }

  return (
    <div
      className="global-search-backdrop"
      role="presentation"
      onMouseDown={(event) => {
        if (event.target === event.currentTarget) onClose()
      }}
    >
      <section className="global-search-dialog" role="dialog" aria-modal="true" aria-label="Search hotel workspace">
        <div className="global-search-input-wrap">
          <SearchGlyph />
          <input
            ref={inputRef}
            type="search"
            value={query}
            onChange={(event) => setQuery(event.target.value.slice(0, 80))}
            placeholder="Search rooms, guests, reservations, requests or invoices"
            aria-label="Search hotel workspace"
          />
          <kbd>Esc</kbd>
        </div>

        <div className="global-search-results" aria-live="polite">
          {!hotelId && <SearchMessage title="Select a hotel" text="Search is scoped to the active property." />}
          {hotelId && query.trim().length < 2 && <SearchMessage title="Search the active hotel" text="Enter at least two characters. Results respect your role and permissions." />}
          {loading && <SearchMessage loading title="Searching…" text="Checking authorised hotel records." />}
          {error && <SearchMessage tone="error" title="Search unavailable" text={error} />}
          {!loading && !error && query.trim().length >= 2 && results.length === 0 && <SearchMessage title="No matching records" text="Try a guest name, room number, reservation number or invoice number." />}
          {!loading && !error && results.map((result) => (
            <button
              key={`${result.entity_type}:${result.entity_id}`}
              type="button"
              className="global-search-result"
              onClick={() => selectResult(result)}
            >
              <span className="global-search-type">{ENTITY_LABELS[result.entity_type] || 'Record'}</span>
              <span className="global-search-copy">
                <strong>{result.title}</strong>
                <small>{result.subtitle || 'Open in StayQR'}</small>
              </span>
              <span className="global-search-open">Open →</span>
            </button>
          ))}
        </div>

        <footer><span>Active property only</span><span><kbd>Ctrl</kbd>/<kbd>⌘</kbd> <kbd>K</kbd> to open</span></footer>
      </section>
    </div>
  )
}

function SearchMessage({ title, text, tone = '', loading = false }) {
  return <div className={`global-search-message ${tone}`}>{loading ? <span className="global-search-spinner" /> : <SearchGlyph />}<strong>{title}</strong><p>{text}</p></div>
}

function SearchGlyph() {
  return <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round"><circle cx="11" cy="11" r="7" /><path d="m20 20-3.2-3.2" /></svg>
}
