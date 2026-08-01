import { useEffect, useMemo, useState } from 'react'
import { supabase } from '../../lib/supabase'
import './InvoiceVerification.css'

export default function InvoiceVerification() {
  const token = useMemo(
    () => window.location.pathname.split('/').filter(Boolean).at(-1) || '',
    []
  )
  const [result, setResult] = useState(null)
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState('')

  useEffect(() => {
    let cancelled = false

    async function verify() {
      if (!token) {
        setError('The invoice verification token is missing.')
        setLoading(false)
        return
      }

      const { data, error: rpcError } = await supabase.rpc('verify_invoice', {
        verification_token_value: token,
      })

      if (cancelled) return

      if (rpcError) {
        setError(rpcError.message || 'Invoice verification failed.')
      } else {
        setResult(data)
      }

      setLoading(false)
    }

    verify()

    return () => {
      cancelled = true
    }
  }, [token])

  if (loading) {
    return (
      <main className="invoice-verify-page">
        <section className="invoice-verify-card">
          <div className="invoice-verify-spinner" />
          <h1>Verifying invoice…</h1>
          <p>StayQR is checking the immutable snapshot and SHA-256 hash.</p>
        </section>
      </main>
    )
  }

  const verified = Boolean(result?.verified)

  return (
    <main className="invoice-verify-page">
      <section className={`invoice-verify-card ${verified ? 'is-valid' : 'is-invalid'}`}>
        <div className="invoice-verify-brand">StayQR</div>
        <div className="invoice-verify-symbol">{verified ? '✓' : '!'}</div>
        <p className="invoice-verify-kicker">
          {verified ? 'AUTHENTIC INVOICE' : 'VERIFICATION FAILED'}
        </p>
        <h1>{verified ? result.invoice_number : 'Invoice not verified'}</h1>
        <p className="invoice-verify-copy">
          {verified
            ? 'The invoice snapshot matches its protected SHA-256 verification record.'
            : error || result?.reason || 'This token is invalid, revoked or unavailable.'}
        </p>

        {verified && (
          <>
            <div className="invoice-verify-grid">
              <VerificationField label="Hotel" value={result.hotel_name} />
              <VerificationField label="Invoice date" value={formatDate(result.invoice_date)} />
              <VerificationField label="Financial year" value={result.financial_year} />
              <VerificationField label="Status" value={formatLabel(result.invoice_status)} />
              <VerificationField label="Supply" value={formatLabel(result.tax_mode)} />
              <VerificationField
                label="Taxable amount"
                value={formatMoney(result.taxable_amount)}
              />
              <VerificationField label="CGST" value={formatMoney(result.cgst_amount)} />
              <VerificationField label="SGST" value={formatMoney(result.sgst_amount)} />
              <VerificationField label="IGST" value={formatMoney(result.igst_amount)} />
              <VerificationField label="Total tax" value={formatMoney(result.tax_amount)} />
              <VerificationField
                label="Invoice total"
                value={formatMoney(result.total_amount)}
                strong
              />
              <VerificationField
                label="Finalized"
                value={formatDateTime(result.finalized_at)}
              />
            </div>

            <div className="invoice-verify-hash">
              <span>Snapshot hash</span>
              <code>{result.snapshot_hash}</code>
            </div>
          </>
        )}

        <footer>Verified directly against StayQR’s immutable invoice ledger.</footer>
      </section>
    </main>
  )
}

function VerificationField({ label, value, strong = false }) {
  return (
    <div className={`invoice-verify-field ${strong ? 'is-strong' : ''}`}>
      <span>{label}</span>
      <strong>{value || '—'}</strong>
    </div>
  )
}

function formatMoney(value) {
  return `₹${Number(value || 0).toLocaleString('en-IN', {
    minimumFractionDigits: 2,
    maximumFractionDigits: 2,
  })}`
}

function formatDate(value) {
  if (!value) return '—'
  return new Date(`${value}T00:00:00`).toLocaleDateString('en-IN')
}

function formatDateTime(value) {
  if (!value) return '—'
  return new Date(value).toLocaleString('en-IN')
}

function formatLabel(value) {
  return String(value || '')
    .replaceAll('_', ' ')
    .replace(/\b\w/g, (letter) => letter.toUpperCase())
}
