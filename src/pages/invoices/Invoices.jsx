import { useCallback, useEffect, useMemo, useRef, useState } from 'react'
import html2canvas from 'html2canvas'
import jsPDF from 'jspdf'
import LocalQrCode from '../../components/qr/LocalQrCode'
import { getCurrentHotel } from '../../lib/currentHotel'
import {
  DAY12_SUPPLY_MODES,
  DAY12_TAX_CATEGORIES,
  closeCashierShift,
  closeNightAudit,
  createDay12RequestId,
  generateAccountingCsv,
  getCashierShiftReport,
  getNightAuditSnapshot,
  issueFolioInvoice,
  loadDay12Workspace,
  loadInvoiceSnapshot,
  openCashierShift,
  previewDayClose,
  previewFolioInvoice,
  upsertTaxRate,
} from '../../lib/day12Finance'
import { supabase } from '../../lib/supabase'
import './Invoices.css'

const TABS = [
  { id: 'invoices', label: 'Invoices' },
  { id: 'receipts', label: 'Receipts' },
  { id: 'cashier', label: 'Cashier Shifts' },
  { id: 'night-audit', label: 'Night Audit' },
  { id: 'tax-rates', label: 'GST / Tax Setup' },
]

const EMPTY_WORKSPACE = {
  invoices: [],
  receipts: [],
  shifts: [],
  shiftEntries: [],
  audits: [],
  exceptions: [],
  exports: [],
  taxRates: [],
  folios: [],
}

export default function Invoices({ hotel, permissions = [], currentRole = '' }) {
  const [currentHotel, setCurrentHotel] = useState(hotel || null)
  const [workspace, setWorkspace] = useState(EMPTY_WORKSPACE)
  const [activeTab, setActiveTab] = useState('invoices')
  const [loading, setLoading] = useState(true)
  const [busy, setBusy] = useState('')
  const [error, setError] = useState('')
  const [notice, setNotice] = useState('')
  const [search, setSearch] = useState('')
  const [selectedInvoice, setSelectedInvoice] = useState(null)
  const [selectedReceipt, setSelectedReceipt] = useState(null)
  const [selectedShift, setSelectedShift] = useState(null)
  const [selectedAudit, setSelectedAudit] = useState(null)
  const [invoiceSnapshot, setInvoiceSnapshot] = useState(null)
  const [shiftReport, setShiftReport] = useState(null)
  const [auditSnapshot, setAuditSnapshot] = useState(null)
  const [invoicePanelOpen, setInvoicePanelOpen] = useState(false)
  const [invoicePreview, setInvoicePreview] = useState(null)
  const [dayClosePreview, setDayClosePreview] = useState(null)

  const invoicePrintRef = useRef(null)
  const receiptPrintRef = useRef(null)

  const today = new Date().toISOString().slice(0, 10)

  const [invoiceForm, setInvoiceForm] = useState({
    folio_id: '',
    supply_mode: 'intra_state',
    invoice_date: today,
  })
  const [openShiftForm, setOpenShiftForm] = useState({ opening_cash: '0' })
  const [closeShiftForm, setCloseShiftForm] = useState({
    declared_cash: '',
    notes: '',
  })
  const [nightAuditForm, setNightAuditForm] = useState({
    business_date: today,
    acknowledge: false,
    notes: '',
  })
  const [taxForm, setTaxForm] = useState({
    id: '',
    code: '',
    name: '',
    charge_category: 'room',
    hsn_sac_code: '',
    rate_percent: '',
    cess_percent: '0',
    valid_from: today,
    valid_to: '',
    is_active: true,
  })

  const canManage = useMemo(() => {
    const role = String(currentRole || '').toLowerCase()
    return (
      role === 'platform_admin' ||
      role === 'super_admin' ||
      role === 'owner' ||
      role === 'manager' ||
      permissions.includes('invoices.manage') ||
      permissions.includes('payments.manage') ||
      permissions.includes('checkout.manage')
    )
  }, [currentRole, permissions])

  const currentHotelId = currentHotel?.id || ''

  const loadWorkspace = useCallback(async (showSpinner = true) => {
    if (!currentHotelId) return
    if (showSpinner) setLoading(true)
    setError('')

    try {
      const nextWorkspace = await loadDay12Workspace(currentHotelId)
      setWorkspace(nextWorkspace)

      setSelectedInvoice((currentInvoice) => {
        if (!currentInvoice) return null

        return (
          nextWorkspace.invoices.find(
            (invoice) => invoice.id === currentInvoice.id
          ) || null
        )
      })

      setSelectedReceipt((currentReceipt) => {
        if (!currentReceipt) return null

        return (
          nextWorkspace.receipts.find(
            (receipt) => receipt.id === currentReceipt.id
          ) || null
        )
      })
    } catch (loadError) {
      console.error('Day 12 finance workspace error:', loadError)
      setError(loadError.message || 'Unable to load invoices and audit operations.')
    } finally {
      if (showSpinner) setLoading(false)
    }
  }, [currentHotelId])

  useEffect(() => {
    let cancelled = false

    async function resolveHotel() {
      const resolved = hotel || (await getCurrentHotel())
      if (cancelled) return

      if (!resolved?.id) {
        setError('No active hotel is available.')
        setLoading(false)
        return
      }

      setCurrentHotel(resolved)
    }

    resolveHotel()

    return () => {
      cancelled = true
    }
  }, [hotel])

  useEffect(() => {
    if (!currentHotelId) return
    loadWorkspace()
  }, [currentHotelId, loadWorkspace])

  useEffect(() => {
    if (!currentHotelId) return undefined

    const channel = supabase.channel(`day12_finance_${currentHotelId}`)
    const tables = [
      'invoices',
      'invoice_items',
      'receipts',
      'cashier_shifts',
      'cashier_shift_entries',
      'night_audits',
      'night_audit_exceptions',
      'accounting_exports',
      'tax_rates',
    ]

    tables.forEach((table) => {
      channel.on(
        'postgres_changes',
        {
          event: '*',
          schema: 'public',
          table,
          filter: `hotel_id=eq.${currentHotelId}`,
        },
        () => loadWorkspace(false)
      )
    })

    channel.subscribe()

    return () => {
      supabase.removeChannel(channel)
    }
  }, [currentHotelId, loadWorkspace])

  const metrics = useMemo(() => {
    const finalized = workspace.invoices.filter((invoice) => invoice.finalized_at)
    const receiptTotal = workspace.receipts
      .filter((receipt) => receipt.receipt_status === 'issued')
      .reduce((sum, receipt) => sum + Number(receipt.amount || 0), 0)
    const openShifts = workspace.shifts.filter((shift) => shift.status === 'open')

    return {
      invoices: workspace.invoices.length,
      finalized: finalized.length,
      receipts: workspace.receipts.length,
      receiptTotal,
      openShifts: openShifts.length,
      audits: workspace.audits.length,
    }
  }, [workspace])

  const filteredInvoices = useMemo(() => {
    const needle = search.trim().toLowerCase()
    if (!needle) return workspace.invoices

    return workspace.invoices.filter((invoice) =>
      [
        invoice.invoice_number,
        invoice.guest?.full_name,
        invoice.guest?.phone,
        invoice.room?.room_number,
        invoice.invoice_status,
        invoice.financial_year_label,
      ]
        .filter(Boolean)
        .some((value) => String(value).toLowerCase().includes(needle))
    )
  }, [search, workspace.invoices])

  const filteredReceipts = useMemo(() => {
    const needle = search.trim().toLowerCase()
    if (!needle) return workspace.receipts

    return workspace.receipts.filter((receipt) =>
      [
        receipt.receipt_number,
        receipt.guest?.full_name,
        receipt.room?.room_number,
        receipt.payment_method,
        receipt.transaction_reference,
      ]
        .filter(Boolean)
        .some((value) => String(value).toLowerCase().includes(needle))
    )
  }, [search, workspace.receipts])

  const eligibleFolios = useMemo(
    () =>
      workspace.folios.filter(
        (folio) =>
          Number(folio.charges_amount || 0) > 0 &&
          !workspace.invoices.some(
            (invoice) =>
              invoice.invoice_origin === 'authoritative' &&
              invoice.finalized_at &&
              invoice.folio_id === folio.id
          )
      ),
    [workspace.folios, workspace.invoices]
  )

  const openShift = workspace.shifts.find((shift) => shift.status === 'open') || null

  async function runAction(label, action, successMessage) {
    setBusy(label)
    setError('')
    setNotice('')

    try {
      const result = await action()
      if (successMessage) setNotice(successMessage)
      await loadWorkspace(false)
      return result
    } catch (actionError) {
      console.error(`${label} failed:`, actionError)
      setError(actionError.message || `${label} failed.`)
      return null
    } finally {
      setBusy('')
    }
  }

  async function handleInvoicePreview() {
    if (!invoiceForm.folio_id) {
      setError('Select an eligible folio first.')
      return
    }

    const result = await runAction(
      'invoice-preview',
      () =>
        previewFolioInvoice(
          currentHotel.id,
          invoiceForm.folio_id,
          invoiceForm.supply_mode,
          invoiceForm.invoice_date
        ),
      ''
    )

    if (result) setInvoicePreview(result)
  }

  async function handleInvoiceIssue() {
    if (!invoicePreview || !canManage) return

    const result = await runAction(
      'invoice-issue',
      () =>
        issueFolioInvoice(
          currentHotel.id,
          invoiceForm.folio_id,
          invoiceForm.supply_mode,
          invoiceForm.invoice_date,
          createDay12RequestId('invoice-issue')
        ),
      'Final invoice issued and immutably locked.'
    )

    if (result) {
      setInvoicePanelOpen(false)
      setInvoicePreview(null)
      setInvoiceForm({
        folio_id: '',
        supply_mode: 'intra_state',
        invoice_date: today,
      })
    }
  }

  async function handleOpenInvoice(invoice) {
    setSelectedInvoice(invoice)
    setInvoiceSnapshot(null)

    if (invoice.finalized_at) {
      const snapshot = await runAction(
        'invoice-snapshot',
        () => loadInvoiceSnapshot(currentHotel.id, invoice.id),
        ''
      )
      if (snapshot) setInvoiceSnapshot(snapshot)
    }
  }

  async function handleOpenShift() {
    const result = await runAction(
      'open-shift',
      () =>
        openCashierShift(
          currentHotel.id,
          openShiftForm.opening_cash,
          createDay12RequestId('cashier-open')
        ),
      'Cashier shift opened.'
    )

    if (result) setOpenShiftForm({ opening_cash: '0' })
  }

  async function handleLoadShiftReport(shift) {
    setSelectedShift(shift)
    const report = await runAction(
      'shift-report',
      () => getCashierShiftReport(currentHotel.id, shift.id),
      ''
    )
    if (report) {
      setShiftReport(report)
      setCloseShiftForm({
        declared_cash: String(report.expected_cash || 0),
        notes: '',
      })
    }
  }

  async function handleCloseShift() {
    if (!selectedShift) return

    const result = await runAction(
      'close-shift',
      () =>
        closeCashierShift(
          currentHotel.id,
          selectedShift.id,
          closeShiftForm.declared_cash,
          closeShiftForm.notes,
          createDay12RequestId('cashier-close')
        ),
      'Cashier shift closed and hashed.'
    )

    if (result) {
      setSelectedShift(null)
      setShiftReport(null)
    }
  }

  async function handleDayClosePreview() {
    const preview = await runAction(
      'day-close-preview',
      () => previewDayClose(currentHotel.id, nightAuditForm.business_date),
      ''
    )
    if (preview) setDayClosePreview(preview)
  }

  async function handleNightAuditClose() {
    if (!dayClosePreview || !canManage) return

    const result = await runAction(
      'night-audit-close',
      () =>
        closeNightAudit(
          currentHotel.id,
          nightAuditForm.business_date,
          nightAuditForm.acknowledge,
          nightAuditForm.notes,
          createDay12RequestId('night-audit')
        ),
      'Business date closed with immutable exception evidence.'
    )

    if (result) {
      setDayClosePreview(null)
      setNightAuditForm({
        business_date: today,
        acknowledge: false,
        notes: '',
      })
    }
  }

  async function handleManualCsvExport() {
    const result = await runAction(
      'accounting-export',
      () =>
        generateAccountingCsv(
          currentHotel.id,
          nightAuditForm.business_date,
          nightAuditForm.business_date,
          createDay12RequestId('accounting-csv')
        ),
      'Accounting CSV generated.'
    )

    const exportRecord = result?.export
    if (exportRecord) downloadCsvRecord(exportRecord)
  }

  async function handleOpenAudit(audit) {
    setSelectedAudit(audit)
    const snapshot = await runAction(
      'audit-snapshot',
      () => getNightAuditSnapshot(currentHotel.id, audit.id),
      ''
    )
    if (snapshot) setAuditSnapshot(snapshot)
  }

  async function handleSaveTaxRate(event) {
    event.preventDefault()
    if (!canManage) return

    const result = await runAction(
      'tax-rate',
      () => upsertTaxRate(currentHotel.id, taxForm),
      'GST/tax rate configuration saved.'
    )

    if (result) {
      setTaxForm({
        id: '',
        code: '',
        name: '',
        charge_category: 'room',
        hsn_sac_code: '',
        rate_percent: '',
        cess_percent: '0',
        valid_from: today,
        valid_to: '',
        is_active: true,
      })
    }
  }

  if (loading) {
    return (
      <div className="day12-loading">
        <span />
        Loading invoice, receipt, cashier and night-audit operations…
      </div>
    )
  }

  return (
    <div className="day12-page">
      <header className="day12-header">
        <div>
          <p className="day12-kicker">DAY 12 · IMMUTABLE FINANCE</p>
          <h1>Invoice, Cashier & Night Audit</h1>
          <p>
            GST invoice snapshots, immutable receipts, cashier controls, day-close
            exceptions and checksum-protected accounting exports.
          </p>
        </div>

        <div className="day12-header-actions">
          <span className={`day12-access ${canManage ? 'is-manage' : ''}`}>
            {canManage ? 'FINANCE MANAGEMENT' : 'READ-ONLY ACCESS'}
          </span>
          <button type="button" className="day12-btn secondary" onClick={() => loadWorkspace()}>
            Refresh
          </button>
        </div>
      </header>

      {(error || notice) && (
        <div className={`day12-banner ${error ? 'is-error' : 'is-success'}`}>
          <span>{error || notice}</span>
          <button type="button" onClick={() => (error ? setError('') : setNotice(''))}>
            ×
          </button>
        </div>
      )}

      <section className="day12-stats">
        <Metric label="Invoices" value={metrics.invoices} />
        <Metric label="Immutable finals" value={metrics.finalized} />
        <Metric label="Receipts" value={metrics.receipts} />
        <Metric label="Receipted value" value={formatMoney(metrics.receiptTotal)} />
        <Metric label="Open cashier shifts" value={metrics.openShifts} />
        <Metric label="Night audits" value={metrics.audits} />
      </section>

      <nav className="day12-tabs" aria-label="Day 12 finance modules">
        {TABS.map((tab) => (
          <button
            type="button"
            key={tab.id}
            className={activeTab === tab.id ? 'is-active' : ''}
            onClick={() => {
              setActiveTab(tab.id)
              setSearch('')
            }}
          >
            {tab.label}
          </button>
        ))}
      </nav>

      {activeTab === 'invoices' && (
        <InvoiceTab
          invoices={filteredInvoices}
          folios={workspace.folios}
          search={search}
          setSearch={setSearch}
          canManage={canManage}
          onOpenInvoice={handleOpenInvoice}
          onOpenIssue={() => {
            setInvoicePanelOpen(true)
            setInvoicePreview(null)
          }}
        />
      )}

      {activeTab === 'receipts' && (
        <ReceiptTab
          receipts={filteredReceipts}
          search={search}
          setSearch={setSearch}
          onOpenReceipt={setSelectedReceipt}
        />
      )}

      {activeTab === 'cashier' && (
        <CashierTab
          openShift={openShift}
          shifts={workspace.shifts}
          canManage={canManage}
          openForm={openShiftForm}
          setOpenForm={setOpenShiftForm}
          onOpenShift={handleOpenShift}
          onOpenReport={handleLoadShiftReport}
          busy={busy}
        />
      )}

      {activeTab === 'night-audit' && (
        <NightAuditTab
          form={nightAuditForm}
          setForm={setNightAuditForm}
          preview={dayClosePreview}
          audits={workspace.audits}
          exports={workspace.exports}
          canManage={canManage}
          onPreview={handleDayClosePreview}
          onClose={handleNightAuditClose}
          onExport={handleManualCsvExport}
          onOpenAudit={handleOpenAudit}
          busy={busy}
        />
      )}

      {activeTab === 'tax-rates' && (
        <TaxRateTab
          taxRates={workspace.taxRates}
          form={taxForm}
          setForm={setTaxForm}
          onSubmit={handleSaveTaxRate}
          canManage={canManage}
          busy={busy}
        />
      )}

      {invoicePanelOpen && (
        <InvoiceIssuePanel
          form={invoiceForm}
          setForm={setInvoiceForm}
          eligibleFolios={eligibleFolios}
          preview={invoicePreview}
          canManage={canManage}
          busy={busy}
          onPreview={handleInvoicePreview}
          onIssue={handleInvoiceIssue}
          onClose={() => {
            setInvoicePanelOpen(false)
            setInvoicePreview(null)
          }}
        />
      )}

      {selectedInvoice && (
        <InvoiceModal
          invoice={selectedInvoice}
          snapshot={invoiceSnapshot}
          hotel={currentHotel}
          printRef={invoicePrintRef}
          onClose={() => {
            setSelectedInvoice(null)
            setInvoiceSnapshot(null)
          }}
        />
      )}

      {selectedReceipt && (
        <ReceiptModal
          receipt={selectedReceipt}
          hotel={currentHotel}
          printRef={receiptPrintRef}
          onClose={() => setSelectedReceipt(null)}
        />
      )}

      {selectedShift && shiftReport && (
        <ShiftModal
          shift={selectedShift}
          report={shiftReport}
          canManage={canManage}
          closeForm={closeShiftForm}
          setCloseForm={setCloseShiftForm}
          onCloseShift={handleCloseShift}
          busy={busy}
          onClose={() => {
            setSelectedShift(null)
            setShiftReport(null)
          }}
        />
      )}

      {selectedAudit && auditSnapshot && (
        <AuditModal
          audit={selectedAudit}
          snapshot={auditSnapshot}
          onClose={() => {
            setSelectedAudit(null)
            setAuditSnapshot(null)
          }}
        />
      )}
    </div>
  )
}

function getLiveInvoiceSettlement(invoice, folios = []) {
  const folio = folios.find((item) => item.id === invoice.folio_id)

  const invoiceTotal = Number(invoice.total_amount || 0)

  // If an authoritative folio exists, its balance is the current
  // settlement truth. The immutable invoice snapshot remains untouched.
  if (folio) {
    const liveBalance = Math.max(Number(folio.balance_amount || 0), 0)

    const livePaid = Math.max(
      0,
      Math.min(invoiceTotal, invoiceTotal - liveBalance)
    )

    return {
      liveBalance,
      livePaid,
      settled:
        folio.status === 'settled' ||
        liveBalance <= 0.005,
    }
  }

  // Legacy/fallback invoices without a folio continue using
  // their stored invoice values.
  return {
    liveBalance: Math.max(Number(invoice.pending_amount || 0), 0),
    livePaid: Math.max(Number(invoice.paid_amount || 0), 0),
    settled: Number(invoice.pending_amount || 0) <= 0.005,
  }
}
function InvoiceTab({
  invoices,
  folios,
  search,
  setSearch,
  canManage,
  onOpenInvoice,
  onOpenIssue,
}) {
  return (
    <section className="day12-section">
      <div className="day12-section-head">
        <div>
          <p className="day12-section-kicker">IMMUTABLE DOCUMENTS</p>
          <h2>Invoice register</h2>
          <p>
            Legacy drafts remain identified; issued and paid documents are locked by
            snapshot and SHA-256 hash.
          </p>
        </div>
        <button type="button" className="day12-btn primary" onClick={onOpenIssue} disabled={!canManage}>
          Preview / issue invoice
        </button>
      </div>

      <SearchBox value={search} onChange={setSearch} placeholder="Search invoice, guest, phone or room" />

      <div className="day12-table-wrap">
        <table className="day12-table">
          <thead>
            <tr>
              <th>Invoice</th>
              <th>Guest & room</th>
              <th>Financial year</th>
              <th>Taxable</th>
              <th>GST</th>
              <th>Total</th>
              <th>Balance</th>
              <th>State</th>
              <th />
            </tr>
          </thead>
          <tbody>
            {invoices.map((invoice) => (
              <tr key={invoice.id}>
                <td>
                  <strong>{invoice.invoice_number}</strong>
                  <small>{invoice.invoice_origin || 'legacy'}</small>
                </td>
                <td>
                  <strong>{invoice.guest?.full_name || 'Guest unavailable'}</strong>
                  <small>Room {invoice.room?.room_number || '—'}</small>
                </td>
                <td>{invoice.financial_year_label || '—'}</td>
                <td>{formatMoney(invoice.taxable_amount || invoice.subtotal_amount)}</td>
                <td>{formatMoney(invoice.tax_amount)}</td>
                <td>{formatMoney(invoice.total_amount)}</td>
                <td>
  {formatMoney(
    getLiveInvoiceSettlement(invoice, folios).liveBalance
  )}
</td>
                <td>
                  <StatusBadge
                    value={invoice.finalized_at ? 'immutable' : invoice.invoice_status}
                  />
                </td>
                <td>
                  <button type="button" className="day12-link-btn" onClick={() => onOpenInvoice(invoice)}>
                    Open
                  </button>
                </td>
              </tr>
            ))}
            {invoices.length === 0 && <EmptyRow columns={9} text="No invoice matched the search." />}
          </tbody>
        </table>
      </div>
    </section>
  )
}

function ReceiptTab({ receipts, search, setSearch, onOpenReceipt }) {
  return (
    <section className="day12-section">
      <div className="day12-section-head">
        <div>
          <p className="day12-section-kicker">ONE PER COLLECTION</p>
          <h2>Receipt register</h2>
          <p>
            Every posted collection owns one source-linked immutable receipt with a
            financial-year number and SHA-256 snapshot.
          </p>
        </div>
        <span className="day12-readonly-pill">38 BACKFILLED RECEIPTS</span>
      </div>

      <SearchBox value={search} onChange={setSearch} placeholder="Search receipt, guest, room, method or reference" />

      <div className="day12-table-wrap">
        <table className="day12-table">
          <thead>
            <tr>
              <th>Receipt</th>
              <th>Guest & room</th>
              <th>Method</th>
              <th>Reference</th>
              <th>Amount</th>
              <th>Issued</th>
              <th>Status</th>
              <th />
            </tr>
          </thead>
          <tbody>
            {receipts.map((receipt) => (
              <tr key={receipt.id}>
                <td><strong>{receipt.receipt_number}</strong></td>
                <td>
                  <strong>{receipt.guest?.full_name || 'Guest unavailable'}</strong>
                  <small>Room {receipt.room?.room_number || '—'}</small>
                </td>
                <td>{formatLabel(receipt.payment_method)}</td>
                <td>{receipt.transaction_reference || '—'}</td>
                <td>{formatMoney(receipt.amount)}</td>
                <td>{formatDateTime(receipt.issued_at)}</td>
                <td><StatusBadge value={receipt.receipt_status} /></td>
                <td>
                  <button type="button" className="day12-link-btn" onClick={() => onOpenReceipt(receipt)}>
                    Open
                  </button>
                </td>
              </tr>
            ))}
            {receipts.length === 0 && <EmptyRow columns={8} text="No receipt matched the search." />}
          </tbody>
        </table>
      </div>
    </section>
  )
}

function CashierTab({
  openShift,
  shifts,
  canManage,
  openForm,
  setOpenForm,
  onOpenShift,
  onOpenReport,
  busy,
}) {
  return (
    <section className="day12-section">
      <div className="day12-section-head">
        <div>
          <p className="day12-section-kicker">CASH CONTROL</p>
          <h2>Cashier shifts</h2>
          <p>
            Expected cash equals opening cash plus cash inflows minus cash refund
            outflows. Every method remains visible in the shift report.
          </p>
        </div>
      </div>

      {openShift ? (
        <div className="day12-callout is-open">
          <div>
            <span>OPEN SHIFT</span>
            <strong>{openShift.shift_number}</strong>
            <p>
              Opened {formatDateTime(openShift.opened_at)} · Opening cash{' '}
              {formatMoney(openShift.opening_cash)}
            </p>
          </div>
          <button type="button" className="day12-btn primary" onClick={() => onOpenReport(openShift)}>
            View / close shift
          </button>
        </div>
      ) : (
        <div className="day12-form-card">
          <h3>Open cashier shift</h3>
          <div className="day12-form-grid two">
            <Field label="Opening cash">
              <input
                type="number"
                min="0"
                step="0.01"
                value={openForm.opening_cash}
                onChange={(event) => setOpenForm({ opening_cash: event.target.value })}
              />
            </Field>
            <div className="day12-form-action">
              <button
                type="button"
                className="day12-btn primary"
                disabled={!canManage || busy === 'open-shift'}
                onClick={onOpenShift}
              >
                {busy === 'open-shift' ? 'Opening…' : 'Open shift'}
              </button>
            </div>
          </div>
        </div>
      )}

      <h3 className="day12-subtitle">Shift history</h3>
      <div className="day12-card-grid">
        {shifts.map((shift) => (
          <button
            type="button"
            className="day12-record-card"
            key={shift.id}
            onClick={() => onOpenReport(shift)}
          >
            <div>
              <StatusBadge value={shift.status} />
              <h4>{shift.shift_number}</h4>
              <p>{formatDateTime(shift.opened_at)}</p>
            </div>
            <strong>{formatMoney(shift.expected_cash ?? shift.opening_cash)}</strong>
          </button>
        ))}
        {shifts.length === 0 && <EmptyCard text="No cashier shift has been created." />}
      </div>
    </section>
  )
}

function NightAuditTab({
  form,
  setForm,
  preview,
  audits,
  exports,
  canManage,
  onPreview,
  onClose,
  onExport,
  onOpenAudit,
  busy,
}) {
  const exceptions = preview?.exceptions || []

  return (
    <section className="day12-section">
      <div className="day12-section-head">
        <div>
          <p className="day12-section-kicker">DAY-CLOSE CONTROL</p>
          <h2>Night audit</h2>
          <p>
            Unresolved stays and payments are never hidden. Closing with blockers
            requires explicit acknowledgement and persists every exception.
          </p>
        </div>
      </div>

      <div className="day12-form-card">
        <div className="day12-form-grid three">
          <Field label="Business date">
            <input
              type="date"
              value={form.business_date}
              onChange={(event) =>
                setForm((current) => ({ ...current, business_date: event.target.value }))
              }
            />
          </Field>
          <div className="day12-form-action">
            <button type="button" className="day12-btn secondary" onClick={onPreview} disabled={busy === 'day-close-preview'}>
              {busy === 'day-close-preview' ? 'Checking…' : 'Preview day close'}
            </button>
          </div>
          <div className="day12-form-action">
            <button type="button" className="day12-btn secondary" onClick={onExport} disabled={!canManage || busy === 'accounting-export'}>
              Generate accounting CSV
            </button>
          </div>
        </div>

        {preview && (
          <div className="day12-preview">
            <div className="day12-preview-summary">
              <Metric label="Blockers" value={preview.blocker_count} />
              <Metric label="Warnings" value={preview.warning_count} />
              <Metric label="Exceptions" value={preview.exception_count} />
              <Metric
                label="Open balance"
                value={formatMoney(preview.financial_summary?.open_balance_amount)}
              />
            </div>

            <div className="day12-exception-list">
              {exceptions.map((exceptionRecord, index) => (
                <article
                  className={`day12-exception ${exceptionRecord.severity === 'blocker' ? 'is-blocker' : ''}`}
                  key={`${exceptionRecord.exception_type}-${exceptionRecord.entity_id || index}`}
                >
                  <div>
                    <StatusBadge value={exceptionRecord.severity} />
                    <strong>{formatLabel(exceptionRecord.exception_type)}</strong>
                    <p>{exceptionRecord.message}</p>
                  </div>
                  <span>{exceptionRecord.amount == null ? '—' : formatMoney(exceptionRecord.amount)}</span>
                </article>
              ))}
            </div>

            <Field label="Close notes">
              <textarea
                rows="3"
                value={form.notes}
                onChange={(event) =>
                  setForm((current) => ({ ...current, notes: event.target.value }))
                }
                placeholder="Reason and reconciliation notes"
              />
            </Field>

            <label className="day12-check">
              <input
                type="checkbox"
                checked={form.acknowledge}
                onChange={(event) =>
                  setForm((current) => ({
                    ...current,
                    acknowledge: event.target.checked,
                  }))
                }
              />
              <span>
                I acknowledge every unresolved blocker and warning shown in this
                immutable close package.
              </span>
            </label>

            <button
              type="button"
              className="day12-btn danger"
              disabled={!canManage || busy === 'night-audit-close'}
              onClick={onClose}
            >
              Close business date
            </button>
          </div>
        )}
      </div>

      <h3 className="day12-subtitle">Closed business dates</h3>
      <div className="day12-card-grid">
        {audits.map((audit) => (
          <button
            type="button"
            className="day12-record-card"
            key={audit.id}
            onClick={() => onOpenAudit(audit)}
          >
            <div>
              <StatusBadge value={audit.closed_with_exceptions ? 'closed with exceptions' : audit.status} />
              <h4>{audit.audit_number}</h4>
              <p>{formatDate(audit.business_date)}</p>
            </div>
            <strong>{audit.exception_count} exceptions</strong>
          </button>
        ))}
        {audits.length === 0 && <EmptyCard text="No business date is closed yet." />}
      </div>

      <h3 className="day12-subtitle">Accounting exports</h3>
      <div className="day12-export-list">
        {exports.map((exportRecord) => (
          <article key={exportRecord.id}>
            <div>
              <strong>{exportRecord.file_name}</strong>
              <small>
                {exportRecord.row_count} rows · {formatDateTime(exportRecord.generated_at)}
              </small>
            </div>
            <button type="button" className="day12-link-btn" onClick={() => downloadCsvRecord(exportRecord)}>
              Download CSV
            </button>
          </article>
        ))}
        {exports.length === 0 && <EmptyCard text="No accounting export has been generated." />}
      </div>
    </section>
  )
}

function TaxRateTab({ taxRates, form, setForm, onSubmit, canManage, busy }) {
  return (
    <section className="day12-section">
      <div className="day12-section-head">
        <div>
          <p className="day12-section-kicker">EXPLICIT CONFIGURATION</p>
          <h2>GST / tax rates</h2>
          <p>
            StayQR never guesses a tax rate. Configure exactly one active valid rate
            for every charge category used by a taxable invoice.
          </p>
        </div>
      </div>

      <div className="day12-tax-layout">
        <form className="day12-form-card" onSubmit={onSubmit}>
          <h3>{form.id ? 'Edit tax rate' : 'Configure tax rate'}</h3>
          <div className="day12-form-grid two">
            <Field label="Code">
              <input value={form.code} onChange={(event) => setForm((current) => ({ ...current, code: event.target.value }))} required />
            </Field>
            <Field label="Name">
              <input value={form.name} onChange={(event) => setForm((current) => ({ ...current, name: event.target.value }))} required />
            </Field>
            <Field label="Charge category">
              <select value={form.charge_category} onChange={(event) => setForm((current) => ({ ...current, charge_category: event.target.value }))}>
                {DAY12_TAX_CATEGORIES.map((category) => (
                  <option value={category.value} key={category.value}>{category.label}</option>
                ))}
              </select>
            </Field>
            <Field label="HSN / SAC">
              <input value={form.hsn_sac_code} onChange={(event) => setForm((current) => ({ ...current, hsn_sac_code: event.target.value }))} />
            </Field>
            <Field label="GST rate %">
              <input type="number" min="0" max="100" step="0.0001" value={form.rate_percent} onChange={(event) => setForm((current) => ({ ...current, rate_percent: event.target.value }))} required />
            </Field>
            <Field label="Cess %">
              <input type="number" min="0" max="100" step="0.0001" value={form.cess_percent} onChange={(event) => setForm((current) => ({ ...current, cess_percent: event.target.value }))} />
            </Field>
            <Field label="Valid from">
              <input type="date" value={form.valid_from} onChange={(event) => setForm((current) => ({ ...current, valid_from: event.target.value }))} required />
            </Field>
            <Field label="Valid to">
              <input type="date" value={form.valid_to} onChange={(event) => setForm((current) => ({ ...current, valid_to: event.target.value }))} />
            </Field>
          </div>
          <label className="day12-check">
            <input type="checkbox" checked={form.is_active} onChange={(event) => setForm((current) => ({ ...current, is_active: event.target.checked }))} />
            <span>Active for invoice preview and issuance</span>
          </label>
          <button type="submit" className="day12-btn primary" disabled={!canManage || busy === 'tax-rate'}>
            Save tax rate
          </button>
        </form>

        <div className="day12-rate-list">
          {taxRates.map((rate) => (
            <button
              type="button"
              key={rate.id}
              className="day12-rate-card"
              onClick={() =>
                setForm({
                  id: rate.id,
                  code: rate.code,
                  name: rate.name,
                  charge_category: rate.charge_category,
                  hsn_sac_code: rate.hsn_sac_code || '',
                  rate_percent: String(rate.rate_percent),
                  cess_percent: String(rate.cess_percent || 0),
                  valid_from: rate.valid_from,
                  valid_to: rate.valid_to || '',
                  is_active: rate.is_active,
                })
              }
            >
              <div>
                <StatusBadge value={rate.is_active ? 'active' : 'inactive'} />
                <h4>{rate.code} · {rate.name}</h4>
                <p>{formatLabel(rate.charge_category)} · HSN/SAC {rate.hsn_sac_code || '—'}</p>
              </div>
              <strong>{Number(rate.rate_percent)}%</strong>
            </button>
          ))}
          {taxRates.length === 0 && <EmptyCard text="No real tax rate is configured. This is intentional until the hotel confirms its GST setup." />}
        </div>
      </div>
    </section>
  )
}

function InvoiceIssuePanel({
  form,
  setForm,
  eligibleFolios,
  preview,
  canManage,
  busy,
  onPreview,
  onIssue,
  onClose,
}) {
  return (
    <Modal title="Preview / issue authoritative invoice" onClose={onClose} wide>
      <div className="day12-form-grid three">
        <Field label="Eligible folio">
          <select
            value={form.folio_id}
            onChange={(event) => setForm((current) => ({ ...current, folio_id: event.target.value }))}
          >
            <option value="">Select folio</option>
            {eligibleFolios.map((folio) => (
              <option value={folio.id} key={folio.id}>
                {folio.folio_number} · {folio.guest?.full_name || 'Guest'} · Room {folio.room?.room_number || '—'} · {formatMoney(folio.balance_amount)}
              </option>
            ))}
          </select>
        </Field>
        <Field label="Supply mode">
          <select value={form.supply_mode} onChange={(event) => setForm((current) => ({ ...current, supply_mode: event.target.value }))}>
            {DAY12_SUPPLY_MODES.map((mode) => (
              <option value={mode.value} key={mode.value}>{mode.label}</option>
            ))}
          </select>
        </Field>
        <Field label="Invoice date">
          <input type="date" value={form.invoice_date} onChange={(event) => setForm((current) => ({ ...current, invoice_date: event.target.value }))} />
        </Field>
      </div>

      <button type="button" className="day12-btn secondary" onClick={onPreview} disabled={busy === 'invoice-preview'}>
        Preview invoice
      </button>

      {preview && (
        <div className="day12-preview">
          <div className="day12-preview-summary">
            <Metric label="Gross charges" value={formatMoney(preview.gross_charges)} />
            <Metric label="Discount" value={formatMoney(preview.discount_amount)} />
            <Metric label="Taxable" value={formatMoney(preview.taxable_amount)} />
            <Metric label="CGST" value={formatMoney(preview.tax_breakup?.cgst_amount)} />
            <Metric label="SGST" value={formatMoney(preview.tax_breakup?.sgst_amount)} />
            <Metric label="IGST" value={formatMoney(preview.tax_breakup?.igst_amount)} />
            <Metric label="Invoice total" value={formatMoney(preview.invoice_total)} />
            <Metric label="Pending" value={formatMoney(preview.pending_amount)} />
          </div>

          <div className="day12-table-wrap">
            <table className="day12-table">
              <thead>
                <tr>
                  <th>Line</th>
                  <th>Description</th>
                  <th>Gross</th>
                  <th>Discount</th>
                  <th>Taxable</th>
                  <th>Rate</th>
                  <th>GST</th>
                  <th>Total</th>
                </tr>
              </thead>
              <tbody>
                {(preview.lines || []).map((line) => (
                  <tr key={line.folio_item_id}>
                    <td>{line.line_number}</td>
                    <td>
                      <strong>{line.description}</strong>
                      <small>{line.hsn_sac_code || 'No HSN/SAC'}</small>
                    </td>
                    <td>{formatMoney(line.gross_amount)}</td>
                    <td>{formatMoney(line.discount_amount)}</td>
                    <td>{formatMoney(line.taxable_amount)}</td>
                    <td>{Number(line.tax_rate_percent || 0)}%</td>
                    <td>{formatMoney(Number(line.cgst_amount || 0) + Number(line.sgst_amount || 0) + Number(line.igst_amount || 0) + Number(line.cess_amount || 0))}</td>
                    <td>{formatMoney(line.line_total)}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>

          <div className="day12-danger-note">
            Issuing allocates the next financial-year number and permanently locks
            the invoice and its line snapshots. Corrections must use a credit note.
          </div>

          <button type="button" className="day12-btn danger" onClick={onIssue} disabled={!canManage || busy === 'invoice-issue'}>
            Issue and lock final invoice
          </button>
        </div>
      )}
    </Modal>
  )
}

function InvoiceModal({ invoice, snapshot, hotel, printRef, onClose }) {
  const verificationUrl = invoice.verification_token
    ? `${window.location.origin}/invoice/verify/${invoice.verification_token}`
    : ''
  const guest = invoice.guest || {}
  const room = invoice.room || {}
  const shareText = [
    `Invoice ${invoice.invoice_number}`,
    `${hotel?.hotel_name || 'Hotel'}`,
    `Guest: ${guest.full_name || 'Guest'}`,
    `Room: ${room.room_number || '—'}`,
    `Total: ${formatMoney(invoice.total_amount)}`,
    `Balance: ${formatMoney(invoice.pending_amount)}`,
    verificationUrl ? `Verify: ${verificationUrl}` : '',
  ]
    .filter(Boolean)
    .join('\n')

  return (
    <Modal title={`Invoice ${invoice.invoice_number}`} onClose={onClose} wide>
      <DocumentActions
        targetRef={printRef}
        filename={`${sanitizeFilename(invoice.invoice_number || 'StayQR-Invoice')}.pdf`}
        whatsappPhone={guest.phone}
        email={guest.email}
        subject={`Invoice ${invoice.invoice_number} from ${hotel?.hotel_name || 'StayQR Hotel'}`}
        message={shareText}
      />

      <article className="day12-paper" ref={printRef}>
        <div className="day12-paper-top">
          <div>
            <span className="day12-paper-brand">StayQR</span>
            <h2>{hotel?.hotel_name || 'StayQR Hotel'}</h2>
            <p>{hotel?.address || hotel?.location || 'Hotel address'}</p>
            {invoice.seller_gstin && <p>GSTIN: {invoice.seller_gstin}</p>}
          </div>
          <div className="day12-paper-right">
            <h2>TAX INVOICE</h2>
            <strong>{invoice.invoice_number}</strong>
            <p>{formatDate(invoice.invoice_date || invoice.created_at)}</p>
            <StatusBadge value={invoice.finalized_at ? 'immutable' : invoice.invoice_status} />
          </div>
        </div>

        <div className="day12-paper-grid">
          <div>
            <span>Bill to</span>
            <strong>{guest.full_name || 'Guest'}</strong>
            <p>{guest.phone || '—'}</p>
            {invoice.buyer_gstin && <p>GSTIN: {invoice.buyer_gstin}</p>}
          </div>
          <div>
            <span>Stay</span>
            <strong>Room {room.room_number || '—'}</strong>
            <p>{invoice.stay_nights || 0} night(s)</p>
            <p>Place of supply: {invoice.place_of_supply || '—'} {invoice.place_of_supply_code ? `(${invoice.place_of_supply_code})` : ''}</p>
          </div>
        </div>

        <table className="day12-paper-table">
          <thead>
            <tr>
              <th>#</th>
              <th>Description</th>
              <th>HSN/SAC</th>
              <th>Taxable</th>
              <th>Rate</th>
              <th>GST</th>
              <th>Total</th>
            </tr>
          </thead>
          <tbody>
            {(invoice.invoice_items || []).map((item, index) => (
              <tr key={item.id}>
                <td>{item.line_number || index + 1}</td>
                <td>{item.description}</td>
                <td>{item.hsn_sac_code || '—'}</td>
                <td>{formatMoney(item.taxable_amount || item.amount)}</td>
                <td>{Number(item.tax_rate_percent || 0)}%</td>
                <td>{formatMoney(Number(item.cgst_amount || 0) + Number(item.sgst_amount || 0) + Number(item.igst_amount || 0) + Number(item.cess_amount || 0))}</td>
                <td>{formatMoney(item.amount)}</td>
              </tr>
            ))}
            {(invoice.invoice_items || []).length === 0 && (
              <tr>
                <td colSpan="7">No itemised lines are available for this legacy invoice.</td>
              </tr>
            )}
          </tbody>
        </table>

        <div className="day12-paper-summary">
          <SummaryRow label="Taxable amount" value={invoice.taxable_amount || invoice.subtotal_amount} />
          <SummaryRow label="CGST" value={invoice.cgst_amount} />
          <SummaryRow label="SGST" value={invoice.sgst_amount} />
          <SummaryRow label="IGST" value={invoice.igst_amount} />
          <SummaryRow label="Cess" value={invoice.cess_amount} />
          <SummaryRow label="Total tax" value={invoice.tax_amount} />
          <SummaryRow label="Invoice total" value={invoice.total_amount} strong />
          <SummaryRow label="Paid" value={invoice.paid_amount} />
          <SummaryRow label="Balance" value={invoice.pending_amount} strong />
        </div>

        {verificationUrl && (
          <div className="day12-verification-box">
            <LocalQrCode
              value={verificationUrl}
              label={`Verify invoice ${invoice.invoice_number}`}
              size={142}
            />
            <div>
              <span>PUBLIC QR VERIFICATION</span>
              <strong>Immutable snapshot verified by StayQR</strong>
              <p>{verificationUrl}</p>
              <code>{invoice.snapshot_hash}</code>
            </div>
          </div>
        )}

        <footer className="day12-paper-footer">
          <span>Final invoices cannot be silently changed.</span>
          <span>Powered by StayQR · stayqr.in</span>
        </footer>
      </article>

      {snapshot && (
        <details className="day12-technical">
          <summary>Immutable technical evidence</summary>
          <pre>{JSON.stringify(snapshot, null, 2)}</pre>
        </details>
      )}
    </Modal>
  )
}

function ReceiptModal({ receipt, hotel, printRef, onClose }) {
  const guest = receipt.guest || {}
  const room = receipt.room || {}
  const shareText = [
    `Receipt ${receipt.receipt_number}`,
    `${hotel?.hotel_name || 'Hotel'}`,
    `Guest: ${guest.full_name || 'Guest'}`,
    `Room: ${room.room_number || '—'}`,
    `Amount received: ${formatMoney(receipt.amount)}`,
    `Method: ${formatLabel(receipt.payment_method)}`,
    `Reference: ${receipt.transaction_reference || '—'}`,
  ].join('\n')

  return (
    <Modal title={`Receipt ${receipt.receipt_number}`} onClose={onClose}>
      <DocumentActions
        targetRef={printRef}
        filename={`${sanitizeFilename(receipt.receipt_number || 'StayQR-Receipt')}.pdf`}
        whatsappPhone={guest.phone}
        email={guest.email}
        subject={`Receipt ${receipt.receipt_number} from ${hotel?.hotel_name || 'StayQR Hotel'}`}
        message={shareText}
      />

      <article className="day12-paper receipt" ref={printRef}>
        <div className="day12-paper-top">
          <div>
            <span className="day12-paper-brand">StayQR</span>
            <h2>{hotel?.hotel_name || 'StayQR Hotel'}</h2>
            <p>{hotel?.address || hotel?.location || 'Hotel address'}</p>
          </div>
          <div className="day12-paper-right">
            <h2>PAYMENT RECEIPT</h2>
            <strong>{receipt.receipt_number}</strong>
            <p>{formatDateTime(receipt.issued_at)}</p>
            <StatusBadge value={receipt.receipt_status} />
          </div>
        </div>

        <div className="day12-receipt-amount">
          <span>Amount received</span>
          <strong>{formatMoney(receipt.amount)}</strong>
        </div>

        <div className="day12-paper-grid">
          <div>
            <span>Received from</span>
            <strong>{guest.full_name || 'Guest'}</strong>
            <p>Room {room.room_number || '—'}</p>
          </div>
          <div>
            <span>Payment details</span>
            <strong>{formatLabel(receipt.payment_method)}</strong>
            <p>{receipt.transaction_reference || 'No external reference'}</p>
          </div>
        </div>

        <div className="day12-receipt-hash">
          <span>SHA-256 receipt snapshot</span>
          <code>{receipt.snapshot_hash}</code>
        </div>

        <footer className="day12-paper-footer">
          <span>One immutable receipt per posted collection.</span>
          <span>Powered by StayQR · stayqr.in</span>
        </footer>
      </article>
    </Modal>
  )
}

function ShiftModal({
  shift,
  report,
  canManage,
  closeForm,
  setCloseForm,
  onCloseShift,
  busy,
  onClose,
}) {
  return (
    <Modal title={`Cashier shift ${shift.shift_number}`} onClose={onClose} wide>
      <div className="day12-preview-summary">
        <Metric label="Opening cash" value={formatMoney(shift.opening_cash)} />
        <Metric label="Entries" value={report.entry_count} />
        <Metric label="Inflows" value={formatMoney(report.inflow_amount)} />
        <Metric label="Outflows" value={formatMoney(report.outflow_amount)} />
        <Metric label="Cash net" value={formatMoney(report.cash_net)} />
        <Metric label="Expected cash" value={formatMoney(report.expected_cash)} />
        <Metric
          label="Cash variance"
          value={formatMoney(shift.cash_variance || 0)}
        />
      </div>

      <div className="day12-table-wrap">
        <table className="day12-table">
          <thead>
            <tr>
              <th>Time</th>
              <th>Type</th>
              <th>Method</th>
              <th>Direction</th>
              <th>Amount</th>
              <th>Net</th>
            </tr>
          </thead>
          <tbody>
            {(report.entries || []).map((entry) => (
              <tr key={entry.id}>
                <td>{formatDateTime(entry.occurred_at)}</td>
                <td>{formatLabel(entry.entry_type)}</td>
                <td>{formatLabel(entry.payment_method)}</td>
                <td><StatusBadge value={entry.direction} /></td>
                <td>{formatMoney(entry.amount)}</td>
                <td>{formatMoney(entry.net_effect)}</td>
              </tr>
            ))}
            {(report.entries || []).length === 0 && <EmptyRow columns={6} text="No financial entry belongs to this shift." />}
          </tbody>
        </table>
      </div>

      {shift.status === 'open' && (
        <div className="day12-form-card">
          <h3>Close shift</h3>
          <div className="day12-form-grid two">
            <Field label="Declared cash">
              <input type="number" min="0" step="0.01" value={closeForm.declared_cash} onChange={(event) => setCloseForm((current) => ({ ...current, declared_cash: event.target.value }))} />
            </Field>
            <Field label="Close notes">
              <input value={closeForm.notes} onChange={(event) => setCloseForm((current) => ({ ...current, notes: event.target.value }))} />
            </Field>
          </div>
          <button type="button" className="day12-btn danger" disabled={!canManage || busy === 'close-shift'} onClick={onCloseShift}>
            Close and hash shift
          </button>
        </div>
      )}
    </Modal>
  )
}

function AuditModal({ audit, snapshot, onClose }) {
  const exceptions = snapshot.exceptions || []
  const exports = snapshot.exports || []

  return (
    <Modal title={`Night audit ${audit.audit_number}`} onClose={onClose} wide>
      <div className="day12-preview-summary">
        <Metric label="Business date" value={formatDate(audit.business_date)} />
        <Metric label="Blockers" value={audit.blocker_count} />
        <Metric label="Warnings" value={audit.warning_count} />
        <Metric label="Open balance" value={formatMoney(audit.open_balance_amount)} />
        <Metric label="Hash valid" value={snapshot.hash_valid ? 'YES' : 'NO'} />
      </div>

      <div className="day12-exception-list">
        {exceptions.map((exceptionRecord) => (
          <article className={`day12-exception ${exceptionRecord.severity === 'blocker' ? 'is-blocker' : ''}`} key={exceptionRecord.id}>
            <div>
              <StatusBadge value={exceptionRecord.severity} />
              <strong>{formatLabel(exceptionRecord.exception_type)}</strong>
              <p>{exceptionRecord.message}</p>
            </div>
            <StatusBadge value={exceptionRecord.status} />
          </article>
        ))}
      </div>

      {exports.map((exportRecord) => (
        <article className="day12-export-card" key={exportRecord.id}>
          <div>
            <strong>{exportRecord.file_name}</strong>
            <small>{exportRecord.row_count} rows · SHA-256 {exportRecord.content_hash}</small>
          </div>
          <button type="button" className="day12-link-btn" onClick={() => downloadCsvRecord(exportRecord)}>
            Download CSV
          </button>
        </article>
      ))}

      <details className="day12-technical">
        <summary>Immutable audit snapshot</summary>
        <pre>{JSON.stringify(snapshot.snapshot, null, 2)}</pre>
      </details>
    </Modal>
  )
}

function DocumentActions({
  targetRef,
  filename,
  whatsappPhone,
  email,
  subject,
  message,
}) {
  return (
    <div className="day12-document-actions">
      <button type="button" className="day12-btn primary" onClick={() => downloadElementPdf(targetRef, filename)}>
        Download PDF
      </button>
      <button type="button" className="day12-btn secondary" onClick={() => printElement(targetRef)}>
        Print
      </button>
      <button type="button" className="day12-btn whatsapp" onClick={() => shareWhatsApp(whatsappPhone, message)}>
        WhatsApp
      </button>
      <button type="button" className="day12-btn secondary" onClick={() => shareEmail(email, subject, message)}>
        Email
      </button>
    </div>
  )
}

function SearchBox({ value, onChange, placeholder }) {
  return (
    <div className="day12-search">
      <span>⌕</span>
      <input value={value} onChange={(event) => onChange(event.target.value)} placeholder={placeholder} />
    </div>
  )
}

function Modal({ title, children, onClose, wide = false }) {
  return (
    <div className="day12-modal-backdrop" role="dialog" aria-modal="true">
      <div className={`day12-modal ${wide ? 'is-wide' : ''}`}>
        <header>
          <h2>{title}</h2>
          <button type="button" onClick={onClose} aria-label="Close">×</button>
        </header>
        <div className="day12-modal-body">{children}</div>
      </div>
    </div>
  )
}

function Field({ label, children }) {
  return (
    <label className="day12-field">
      <span>{label}</span>
      {children}
    </label>
  )
}

function Metric({ label, value }) {
  return (
    <article className="day12-metric">
      <span>{label}</span>
      <strong>{value}</strong>
    </article>
  )
}

function SummaryRow({ label, value, strong = false }) {
  return (
    <div className={`day12-summary-row ${strong ? 'is-strong' : ''}`}>
      <span>{label}</span>
      <strong>{formatMoney(value)}</strong>
    </div>
  )
}

function StatusBadge({ value }) {
  const normalized = String(value || 'unknown').toLowerCase().replaceAll('_', '-')
  return <span className={`day12-status status-${normalized}`}>{formatLabel(value)}</span>
}

function EmptyRow({ columns, text }) {
  return (
    <tr>
      <td className="day12-empty" colSpan={columns}>{text}</td>
    </tr>
  )
}

function EmptyCard({ text }) {
  return <div className="day12-empty-card">{text}</div>
}

async function downloadElementPdf(targetRef, filename) {
  if (!targetRef?.current) return

  try {
    const canvas = await html2canvas(targetRef.current, {
      scale: 2,
      backgroundColor: '#ffffff',
      useCORS: true,
    })
    const image = canvas.toDataURL('image/png')
    const pdf = new jsPDF('p', 'mm', 'a4')
    const pageWidth = pdf.internal.pageSize.getWidth()
    const pageHeight = pdf.internal.pageSize.getHeight()
    const imageHeight = (canvas.height * pageWidth) / canvas.width
    let heightLeft = imageHeight
    let position = 0

    pdf.addImage(image, 'PNG', 0, position, pageWidth, imageHeight)
    heightLeft -= pageHeight

    while (heightLeft > 0) {
      position = heightLeft - imageHeight
      pdf.addPage()
      pdf.addImage(image, 'PNG', 0, position, pageWidth, imageHeight)
      heightLeft -= pageHeight
    }

    pdf.save(filename)
  } catch (error) {
    console.error('Day 12 PDF generation error:', error)
    window.alert('Unable to generate this PDF.')
  }
}

function printElement(targetRef) {
  if (!targetRef?.current) return

  const popup = window.open('', '_blank', 'noopener,noreferrer,width=1100,height=800')
  if (!popup) {
    window.alert('Allow pop-ups to print this document.')
    return
  }

  popup.document.write(`
    <!doctype html>
    <html>
      <head>
        <title>StayQR document</title>
        <meta charset="utf-8" />
        <style>
          body { margin: 0; padding: 20px; font-family: Arial, sans-serif; background: #fff; }
          * { box-sizing: border-box; }
          table { width: 100%; border-collapse: collapse; }
          th, td { border-bottom: 1px solid #ddd; padding: 10px; text-align: left; }
          button { display: none !important; }
        </style>
      </head>
      <body>${targetRef.current.outerHTML}</body>
    </html>
  `)
  popup.document.close()
  popup.focus()
  popup.print()
  popup.close()
}

function shareWhatsApp(phoneValue, message) {
  let phone = String(phoneValue || '').replace(/\D/g, '')
  if (phone.length === 10) phone = `91${phone}`

  const url = phone
    ? `https://wa.me/${phone}?text=${encodeURIComponent(message)}`
    : `https://wa.me/?text=${encodeURIComponent(message)}`

  window.open(url, '_blank', 'noopener,noreferrer')
}

function shareEmail(email, subject, message) {
  const address = email || ''
  window.location.href = `mailto:${encodeURIComponent(address)}?subject=${encodeURIComponent(subject)}&body=${encodeURIComponent(message)}`
}

function downloadCsvRecord(exportRecord) {
  if (!exportRecord?.csv_content) return

  const blob = new Blob([exportRecord.csv_content], {
    type: 'text/csv;charset=utf-8',
  })
  const objectUrl = URL.createObjectURL(blob)
  const anchor = document.createElement('a')
  anchor.href = objectUrl
  anchor.download = exportRecord.file_name || 'stayqr-accounting.csv'
  document.body.appendChild(anchor)
  anchor.click()
  anchor.remove()
  URL.revokeObjectURL(objectUrl)
}

function sanitizeFilename(value) {
  return String(value || 'stayqr-document').replace(/[\\/:*?"<>|]+/g, '-')
}

function formatMoney(value) {
  return `₹${Number(value || 0).toLocaleString('en-IN', {
    minimumFractionDigits: 2,
    maximumFractionDigits: 2,
  })}`
}

function formatDate(value) {
  if (!value) return '—'
  const date = String(value).includes('T') ? new Date(value) : new Date(`${value}T00:00:00`)
  return date.toLocaleDateString('en-IN')
}

function formatDateTime(value) {
  if (!value) return '—'
  return new Date(value).toLocaleString('en-IN')
}

function formatLabel(value) {
  return String(value || 'unknown')
    .replaceAll('_', ' ')
    .replaceAll('-', ' ')
    .replace(/\b\w/g, (letter) => letter.toUpperCase())
}
