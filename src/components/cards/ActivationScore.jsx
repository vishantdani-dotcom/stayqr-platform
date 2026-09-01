import { useCallback, useEffect, useState } from 'react'
import { loadCommercialReadyWorkspace } from '../../lib/commercialReady'
import './ActivationScore.css'

const SECTION_BY_KEY = {
  hotel_profile: 'hotel',
  rooms: 'rooms',
  staff: 'staff',
  guest_guide: 'guidebuilder',
  qr_guides: 'qr',
  billing: 'billing',
  operational_test: 'reservations',
  support: 'operationscenter',
}
export default function ActivationScore({ hotelId, onNavigate, refreshKey }) {
  const [activation, setActivation] = useState(null)
  const [error, setError] = useState('')

  const load = useCallback(async () => {
    if (!hotelId) return
    setError('')
    try {
      const workspace = await loadCommercialReadyWorkspace(hotelId)
      setActivation(workspace?.activation || null)
    } catch (loadError) {
      setError(loadError.message || 'Hotel activation score could not be loaded.')
    }
  }, [hotelId])

  useEffect(() => { load() }, [load, refreshKey])

  if (!hotelId) return null
  if (error) return <section className="activation-card activation-error"><strong>Activation score unavailable</strong><span>{error}</span></section>
  if (!activation) return <section className="activation-card">Calculating hotel activation score…</section>

  const score = Number(activation.score || 0)
  const items = Array.isArray(activation.checklist) ? activation.checklist : []

  return (
    <section className="activation-card" aria-label="Hotel activation score">
      <header className="activation-head">
        <div className="activation-ring" style={{ '--activation': `${Math.max(0, Math.min(score, 100)) * 3.6}deg` }}><span>{score}%</span></div>
        <div><p>HOTEL ACTIVATION SCORE</p><h2>{score === 100 ? 'Ready to sell & operate' : 'Complete your hotel launch'}</h2><span>{activation.completed_items || 0} of {activation.total_items || items.length} readiness checks complete.</span></div>
        <button type="button" onClick={load}>Refresh score</button>
      </header>
      <div className="activation-list">
        {items.map((item) => <button type="button" key={item.key} className={item.complete ? 'complete' : ''} onClick={() => onNavigate?.(SECTION_BY_KEY[item.key] || 'onboarding')}><span className="activation-check">{item.complete ? '✓' : '!'}</span><span><strong>{item.label}</strong><small>{item.complete ? item.complete_text : item.action}</small></span><b>{item.weight} pts</b></button>)}
      </div>
    </section>
  )
}
