import { useCallback, useEffect, useMemo, useRef, useState } from 'react'
import html2canvas from 'html2canvas'
import { jsPDF } from 'jspdf'
import { supabase } from '../../lib/supabase'
import { getCurrentHotel } from '../../lib/currentHotel'
import './Reports.css'

const REPORT_TABS = [
  { key: 'overview', label: 'Overview' },
  { key: 'revenue', label: 'Revenue' },
  { key: 'reservations', label: 'Reservations' },
  { key: 'operations', label: 'Operations' },
  { key: 'tax_staff', label: 'Tax & Staff' },
]

const EXPORT_REPORTS = [
  { key: 'occupancy_daily', label: 'Daily occupancy' },
  { key: 'revenue_daily', label: 'Daily revenue' },
  { key: 'revenue_by_category', label: 'Revenue by category' },
  { key: 'reservations_by_source', label: 'Reservations by source' },
  { key: 'arrivals_departures', label: 'Arrivals & departures' },
  { key: 'payments_by_method', label: 'Payments by method' },
  { key: 'tax_gst_summary', label: 'Tax / GST summary' },
  { key: 'guest_food_service', label: 'Guest, food & service' },
  { key: 'service_sla', label: 'Service SLA' },
  { key: 'housekeeping', label: 'Housekeeping' },
  { key: 'staff_department', label: 'Staff & department' },
]

const EMPTY_REPORT = {
  kpi: {},
  occupancy: [],
  revenueDaily: [],
  revenueCategory: [],
  sources: [],
  arrivals: {
    expected_arrivals: [],
    expected_departures: [],
    actual_arrivals: [],
    actual_departures: [],
  },
  payments: [],
  tax: {},
  guestFoodService: {},
  serviceSla: [],
  housekeeping: {
    summary: {},
    by_status: [],
  },
  staff: [],
}

const INR = new Intl.NumberFormat('en-IN', {
  style: 'currency',
  currency: 'INR',
  maximumFractionDigits: 2,
})

function formatDateInput(value) {
  const year = value.getFullYear()
  const month = String(value.getMonth() + 1).padStart(2, '0')
  const day = String(value.getDate()).padStart(2, '0')
  return `${year}-${month}-${day}`
}

function buildInitialRange() {
  const today = new Date()
  return {
    from: formatDateInput(new Date(today.getFullYear(), today.getMonth(), 1)),
    to: formatDateInput(today),
  }
}

function money(value) {
  return INR.format(Number(value || 0))
}

function number(value, digits = 0) {
  return Number(value || 0).toLocaleString('en-IN', {
    maximumFractionDigits: digits,
  })
}

function percent(value) {
  return `${number(value, 2)}%`
}

function safeArray(value) {
  return Array.isArray(value) ? value : []
}

async function callRpc(name, args) {
  const { data, error } = await supabase.rpc(name, args)
  if (error) throw new Error(`${name}: ${error.message}`)
  return data
}

function getPresetRange(preset) {
  const today = new Date()
  const to = formatDateInput(today)

  if (preset === 'today') {
    return { from: to, to }
  }

  if (preset === '7d') {
    const fromDate = new Date(today)
    fromDate.setDate(fromDate.getDate() - 6)
    return { from: formatDateInput(fromDate), to }
  }

  if (preset === '30d') {
    const fromDate = new Date(today)
    fromDate.setDate(fromDate.getDate() - 29)
    return { from: formatDateInput(fromDate), to }
  }

  return {
    from: formatDateInput(new Date(today.getFullYear(), today.getMonth(), 1)),
    to,
  }
}

function flattenObject(value, prefix = '', result = {}) {
  if (
    value === null
    || value === undefined
    || typeof value !== 'object'
    || value instanceof Date
  ) {
    result[prefix || 'value'] = value ?? ''
    return result
  }

  if (Array.isArray(value)) {
    result[prefix || 'value'] = JSON.stringify(value)
    return result
  }

  Object.entries(value).forEach(([key, nestedValue]) => {
    const nestedKey = prefix ? `${prefix}.${key}` : key
    if (
      nestedValue
      && typeof nestedValue === 'object'
      && !Array.isArray(nestedValue)
    ) {
      flattenObject(nestedValue, nestedKey, result)
    } else {
      result[nestedKey] = Array.isArray(nestedValue)
        ? JSON.stringify(nestedValue)
        : nestedValue ?? ''
    }
  })

  return result
}

function normalizeExportRows(reportKey, rows) {
  if (Array.isArray(rows)) return rows.map((row) => flattenObject(row))

  if (!rows || typeof rows !== 'object') {
    return [{ report_key: reportKey, value: rows ?? '' }]
  }

  if (reportKey === 'arrivals_departures') {
    return Object.entries(rows).flatMap(([section, items]) =>
      safeArray(items).map((item) => ({
        section,
        ...flattenObject(item),
      }))
    )
  }

  if (reportKey === 'housekeeping') {
    const summary = {
      section: 'summary',
      ...flattenObject(rows.summary || {}),
    }
    const statuses = safeArray(rows.by_status).map((item) => ({
      section: 'by_status',
      ...flattenObject(item),
    }))
    return [summary, ...statuses]
  }

  return [flattenObject(rows)]
}

function toCsv(rows) {
  if (!rows.length) return 'No data\n'

  const columns = Array.from(
    rows.reduce((keys, row) => {
      Object.keys(row).forEach((key) => keys.add(key))
      return keys
    }, new Set())
  )

  const escapeCell = (value) => {
    const text = value === null || value === undefined ? '' : String(value)
    return `"${text.replaceAll('"', '""')}"`
  }

  return [
    columns.map(escapeCell).join(','),
    ...rows.map((row) =>
      columns.map((column) => escapeCell(row[column])).join(',')
    ),
  ].join('\n')
}

function downloadText(filename, content, type) {
  const blob = new Blob([content], { type })
  const url = URL.createObjectURL(blob)
  const anchor = document.createElement('a')
  anchor.href = url
  anchor.download = filename
  document.body.appendChild(anchor)
  anchor.click()
  anchor.remove()
  URL.revokeObjectURL(url)
}

export default function Reports() {
  const [currentHotel, setCurrentHotel] = useState(null)
  const [range, setRange] = useState(buildInitialRange)
  const [preset, setPreset] = useState('mtd')
  const [activeTab, setActiveTab] = useState('overview')
  const [filterOptions, setFilterOptions] = useState({
    timezone: 'Asia/Kolkata',
    booking_sources: [],
    departments: [],
    payment_methods: [],
  })
  const [filters, setFilters] = useState({
    bookingSource: '',
    department: '',
    paymentMethod: '',
  })
  const [report, setReport] = useState(EMPTY_REPORT)
  const [loading, setLoading] = useState(true)
  const [exporting, setExporting] = useState('')
  const [error, setError] = useState('')
  const [toast, setToast] = useState('')
  const reportRef = useRef(null)

  const showToast = useCallback((message) => {
    setToast(message)
    window.setTimeout(() => setToast(''), 2800)
  }, [])

  const loadReports = useCallback(async (hotelId, nextRange) => {
    if (!hotelId) return

    setLoading(true)
    setError('')

    const dateArgs = {
      p_hotel_id: hotelId,
      p_date_from: nextRange.from,
      p_date_to: nextRange.to,
    }

    try {
      const [
        options,
        kpi,
        occupancy,
        revenueDaily,
        revenueCategory,
        sources,
        arrivals,
        payments,
        tax,
        guestFoodService,
        serviceSla,
        housekeeping,
        staff,
      ] = await Promise.all([
        callRpc('get_report_filter_options', {
          p_hotel_id: hotelId,
        }),
        callRpc('get_report_kpi_summary', dateArgs),
        callRpc('get_report_occupancy_daily', dateArgs),
        callRpc('get_report_revenue_daily', dateArgs),
        callRpc('get_report_revenue_by_category', dateArgs),
        callRpc('get_report_reservations_by_source', dateArgs),
        callRpc('get_report_arrivals_departures', dateArgs),
        callRpc('get_report_payments_by_method', dateArgs),
        callRpc('get_report_tax_gst_summary', dateArgs),
        callRpc('get_report_guest_food_service', dateArgs),
        callRpc('get_report_service_sla', dateArgs),
        callRpc('get_report_housekeeping', dateArgs),
        callRpc('get_report_staff_department', dateArgs),
      ])

      setFilterOptions({
        timezone: options?.timezone || 'Asia/Kolkata',
        booking_sources: safeArray(options?.booking_sources),
        departments: safeArray(options?.departments),
        payment_methods: safeArray(options?.payment_methods),
      })

      setReport({
        kpi: kpi || {},
        occupancy: safeArray(occupancy),
        revenueDaily: safeArray(revenueDaily),
        revenueCategory: safeArray(revenueCategory),
        sources: safeArray(sources),
        arrivals: arrivals || EMPTY_REPORT.arrivals,
        payments: safeArray(payments),
        tax: tax || {},
        guestFoodService: guestFoodService || {},
        serviceSla: safeArray(serviceSla),
        housekeeping: housekeeping || EMPTY_REPORT.housekeeping,
        staff: safeArray(staff),
      })

      showToast('Reports refreshed from the trusted reporting kernel.')
    } catch (loadError) {
      console.error(loadError)
      setError(loadError.message || 'Unable to load reports.')
    } finally {
      setLoading(false)
    }
  }, [showToast])

  const initialize = useCallback(async () => {
    setLoading(true)

    try {
      const hotel = await getCurrentHotel()
      if (!hotel) {
        throw new Error('No authorized hotel context is available.')
      }

      setCurrentHotel(hotel)
      const initialRange = buildInitialRange()
      setRange(initialRange)
      await loadReports(hotel.id, initialRange)
    } catch (initializeError) {
      console.error(initializeError)
      setError(initializeError.message || 'Unable to initialize reports.')
      setLoading(false)
    }
  }, [loadReports])

  useEffect(() => {
    initialize()
  }, [initialize])

  const filteredSources = useMemo(() => {
    if (!filters.bookingSource) return report.sources
    return report.sources.filter(
      (row) => row.booking_source === filters.bookingSource
    )
  }, [filters.bookingSource, report.sources])

  const filteredPayments = useMemo(() => {
    if (!filters.paymentMethod) return report.payments
    return report.payments.filter(
      (row) => row.payment_method === filters.paymentMethod
    )
  }, [filters.paymentMethod, report.payments])

  const filteredServiceSla = useMemo(() => {
    if (!filters.department) return report.serviceSla
    return report.serviceSla.filter(
      (row) => row.department === filters.department
    )
  }, [filters.department, report.serviceSla])

  const revenueTrend = useMemo(
    () => report.revenueDaily.map((row) => ({
      label: row.date,
      value: Number(row.gross_revenue || 0),
    })),
    [report.revenueDaily]
  )

  const occupancyTrend = useMemo(
    () => report.occupancy.map((row) => ({
      label: row.date,
      value: Number(row.occupancy_rate || 0),
    })),
    [report.occupancy]
  )

  function applyPreset(nextPreset) {
    const nextRange = getPresetRange(nextPreset)
    setPreset(nextPreset)
    setRange(nextRange)
    loadReports(currentHotel?.id, nextRange)
  }

  function updateDate(field, value) {
    setPreset('custom')
    setRange((current) => ({
      ...current,
      [field]: value,
    }))
  }

  async function exportCsv(reportKey) {
    if (!currentHotel?.id) return

    setExporting(`csv:${reportKey}`)
    setError('')

    try {
      const payload = await callRpc('get_report_export_rows', {
        p_hotel_id: currentHotel.id,
        p_date_from: range.from,
        p_date_to: range.to,
        p_report_key: reportKey,
        p_filters: {
          booking_source: filters.bookingSource || null,
          department: filters.department || null,
          payment_method: filters.paymentMethod || null,
        },
      })

      let rows = normalizeExportRows(reportKey, payload?.rows)

      if (reportKey === 'reservations_by_source' && filters.bookingSource) {
        rows = rows.filter(
          (row) => row.booking_source === filters.bookingSource
        )
      }

      if (reportKey === 'service_sla' && filters.department) {
        rows = rows.filter((row) => row.department === filters.department)
      }

      if (reportKey === 'payments_by_method' && filters.paymentMethod) {
        rows = rows.filter(
          (row) => row.payment_method === filters.paymentMethod
        )
      }

      const filename = [
        'StayQR',
        reportKey,
        range.from,
        range.to,
      ].join('_')

      downloadText(
        `${filename}.csv`,
        toCsv(rows),
        'text/csv;charset=utf-8'
      )
      showToast(`${EXPORT_REPORTS.find((item) => item.key === reportKey)?.label || 'Report'} CSV downloaded.`)
    } catch (exportError) {
      console.error(exportError)
      setError(exportError.message || 'Unable to export CSV.')
    } finally {
      setExporting('')
    }
  }

  async function exportPdf() {
    if (!reportRef.current) return

    setExporting('pdf')
    setError('')

    try {
      const canvas = await html2canvas(reportRef.current, {
        backgroundColor: '#080909',
        scale: 1.5,
        useCORS: true,
        logging: false,
      })

      const image = canvas.toDataURL('image/jpeg', 0.92)
      const pdf = new jsPDF({
        orientation: 'landscape',
        unit: 'mm',
        format: 'a4',
      })

      const pageWidth = pdf.internal.pageSize.getWidth()
      const pageHeight = pdf.internal.pageSize.getHeight()
      const imageWidth = pageWidth
      const imageHeight = (canvas.height * imageWidth) / canvas.width

      let remainingHeight = imageHeight
      let position = 0

      pdf.addImage(image, 'JPEG', 0, position, imageWidth, imageHeight)
      remainingHeight -= pageHeight

      while (remainingHeight > 0) {
        position = remainingHeight - imageHeight
        pdf.addPage()
        pdf.addImage(image, 'JPEG', 0, position, imageWidth, imageHeight)
        remainingHeight -= pageHeight
      }

      pdf.save(
        `StayQR_${activeTab}_${range.from}_${range.to}.pdf`
      )
      showToast('PDF downloaded for the current report view.')
    } catch (exportError) {
      console.error(exportError)
      setError(exportError.message || 'Unable to export PDF.')
    } finally {
      setExporting('')
    }
  }

  if (loading && !currentHotel) {
    return (
      <div className="reports-page reports-loading-page">
        <div className="reports-loader" />
        <strong>Loading trusted hotel reports…</strong>
      </div>
    )
  }

  return (
    <div className="reports-page">
      {toast && <div className="reports-toast">{toast}</div>}

      <div className="reports-shell" ref={reportRef}>
        <header className="reports-hero">
          <div>
            <span className="reports-eyebrow">DAY 16 · ANALYTICS & STANDARD REPORTS</span>
            <h1>Hotel Intelligence</h1>
            <p>
              {currentHotel?.hotel_name || 'StayQR Hotel'} · Source-reconciled
              metrics, operational trends and role-aware exports.
            </p>
          </div>

          <div className="reports-hero-meta">
            <span>Timezone</span>
            <strong>{filterOptions.timezone}</strong>
            <small>RPCs enforce hotel scope and reports.view.</small>
          </div>
        </header>

        <section className="reports-control-panel">
          <div className="reports-presets" aria-label="Report date presets">
            {[
              ['today', 'Today'],
              ['7d', '7 days'],
              ['30d', '30 days'],
              ['mtd', 'Month to date'],
            ].map(([key, label]) => (
              <button
                className={preset === key ? 'active' : ''}
                key={key}
                onClick={() => applyPreset(key)}
                type="button"
              >
                {label}
              </button>
            ))}
          </div>

          <div className="reports-date-fields">
            <label>
              From
              <input
                type="date"
                value={range.from}
                max={range.to}
                onChange={(event) => updateDate('from', event.target.value)}
              />
            </label>
            <label>
              To
              <input
                type="date"
                value={range.to}
                min={range.from}
                onChange={(event) => updateDate('to', event.target.value)}
              />
            </label>
          </div>

          <button
            className="reports-primary-button"
            disabled={loading || !range.from || !range.to}
            onClick={() => loadReports(currentHotel?.id, range)}
            type="button"
          >
            {loading ? 'Refreshing…' : 'Refresh reports'}
          </button>
        </section>

        <section className="reports-secondary-filters">
          <label>
            Booking source
            <select
              value={filters.bookingSource}
              onChange={(event) =>
                setFilters((current) => ({
                  ...current,
                  bookingSource: event.target.value,
                }))
              }
            >
              <option value="">All sources</option>
              {filterOptions.booking_sources.map((source) => (
                <option key={source} value={source}>{source}</option>
              ))}
            </select>
          </label>

          <label>
            Department
            <select
              value={filters.department}
              onChange={(event) =>
                setFilters((current) => ({
                  ...current,
                  department: event.target.value,
                }))
              }
            >
              <option value="">All departments</option>
              {filterOptions.departments.map((department) => (
                <option key={department} value={department}>
                  {department}
                </option>
              ))}
            </select>
          </label>

          <label>
            Payment method
            <select
              value={filters.paymentMethod}
              onChange={(event) =>
                setFilters((current) => ({
                  ...current,
                  paymentMethod: event.target.value,
                }))
              }
            >
              <option value="">All methods</option>
              {filterOptions.payment_methods.map((method) => (
                <option key={method} value={method}>{method}</option>
              ))}
            </select>
          </label>

          <button
            className="reports-clear-button"
            onClick={() =>
              setFilters({
                bookingSource: '',
                department: '',
                paymentMethod: '',
              })
            }
            type="button"
          >
            Clear drill-downs
          </button>
        </section>

        {error && (
          <div className="reports-error" role="alert">
            <strong>Report error</strong>
            <span>{error}</span>
          </div>
        )}

        <section className="reports-kpi-grid">
          <MetricCard
            label="Occupancy"
            value={percent(report.kpi.occupancy_rate)}
            note={`${number(report.kpi.occupied_room_nights)} occupied / ${number(report.kpi.available_room_nights)} available nights`}
            accent
          />
          <MetricCard
            label="ADR / ARR"
            value={money(report.kpi.adr)}
            note="Realized room revenue per occupied room-night"
          />
          <MetricCard
            label="RevPAR"
            value={money(report.kpi.revpar)}
            note="Room revenue per available room-night"
          />
          <MetricCard
            label="Gross revenue"
            value={money(report.kpi.gross_revenue)}
            note={`${money(report.kpi.collections)} collected`}
          />
          <MetricCard
            label="Reservations"
            value={number(report.kpi.reservation_count)}
            note={`${number(report.kpi.arrival_count)} arrivals · ${number(report.kpi.departure_count)} departures`}
          />
          <MetricCard
            label="Guest activity"
            value={number(report.guestFoodService.unique_guests)}
            note={`${number(report.kpi.food_order_count)} food orders · ${number(report.kpi.service_request_count)} service requests`}
          />
        </section>

        <nav className="reports-tabs" aria-label="Report sections">
          {REPORT_TABS.map((tab) => (
            <button
              className={activeTab === tab.key ? 'active' : ''}
              key={tab.key}
              onClick={() => setActiveTab(tab.key)}
              type="button"
            >
              {tab.label}
            </button>
          ))}
        </nav>

        <div className="reports-view">
          {activeTab === 'overview' && (
            <OverviewTab
              occupancyTrend={occupancyTrend}
              revenueTrend={revenueTrend}
              report={report}
            />
          )}

          {activeTab === 'revenue' && (
            <RevenueTab
              categoryRows={report.revenueCategory}
              dailyRows={report.revenueDaily}
              paymentRows={filteredPayments}
            />
          )}

          {activeTab === 'reservations' && (
            <ReservationsTab
              arrivals={report.arrivals}
              sourceRows={filteredSources}
            />
          )}

          {activeTab === 'operations' && (
            <OperationsTab
              guestFoodService={report.guestFoodService}
              housekeeping={report.housekeeping}
              serviceRows={filteredServiceSla}
            />
          )}

          {activeTab === 'tax_staff' && (
            <TaxStaffTab
              staffRows={report.staff}
              tax={report.tax}
            />
          )}
        </div>
      </div>

      <aside className="reports-export-dock">
        <div>
          <span>STANDARD EXPORTS</span>
          <h2>Download verified data</h2>
          <p>
            CSV datasets come from the same trusted RPCs and date window shown
            on screen.
          </p>
        </div>

        <div className="reports-export-list">
          {EXPORT_REPORTS.map((item) => (
            <button
              disabled={Boolean(exporting)}
              key={item.key}
              onClick={() => exportCsv(item.key)}
              type="button"
            >
              <span>{item.label}</span>
              <strong>
                {exporting === `csv:${item.key}` ? 'Preparing…' : 'CSV'}
              </strong>
            </button>
          ))}
        </div>

        <button
          className="reports-pdf-button"
          disabled={Boolean(exporting)}
          onClick={exportPdf}
          type="button"
        >
          {exporting === 'pdf' ? 'Creating PDF…' : 'Export current view as PDF'}
        </button>
      </aside>
    </div>
  )
}

function MetricCard({ accent = false, label, note, value }) {
  return (
    <article className={`reports-metric-card${accent ? ' accent' : ''}`}>
      <span>{label}</span>
      <strong>{value}</strong>
      <small>{note}</small>
    </article>
  )
}

function OverviewTab({ occupancyTrend, report, revenueTrend }) {
  return (
    <div className="reports-tab-stack">
      <div className="reports-two-column">
        <Panel
          eyebrow="ROOM PERFORMANCE"
          title="Occupancy trend"
          subtitle="Occupied room nights against authoritative available inventory."
        >
          <TrendChart
            data={occupancyTrend}
            formatter={(value) => `${number(value, 2)}%`}
            suffix="%"
          />
        </Panel>

        <Panel
          eyebrow="FINANCIAL PERFORMANCE"
          title="Gross revenue trend"
          subtitle="Posted folio charges and tax, kept separate from collections."
        >
          <TrendChart
            data={revenueTrend}
            formatter={money}
          />
        </Panel>
      </div>

      <Panel
        eyebrow="REVENUE MIX"
        title="Where revenue is coming from"
        subtitle="Authoritative posted folio categories for the selected period."
      >
        <BarList
          rows={[
            { label: 'Room', value: report.kpi.room_revenue },
            { label: 'Food', value: report.kpi.food_revenue },
            { label: 'Service', value: report.kpi.service_revenue },
            { label: 'Other', value: report.kpi.other_revenue },
            { label: 'Tax', value: report.kpi.tax_revenue },
          ]}
          valueFormatter={money}
        />
      </Panel>
    </div>
  )
}

function RevenueTab({ categoryRows, dailyRows, paymentRows }) {
  return (
    <div className="reports-tab-stack">
      <div className="reports-two-column">
        <Panel
          eyebrow="POSTED REVENUE"
          title="Revenue by category"
          subtitle="Room, food, service, manual and tax contribution."
        >
          <BarList
            rows={categoryRows.map((row) => ({
              label: row.category,
              value: row.amount,
            }))}
            valueFormatter={money}
          />
        </Panel>

        <Panel
          eyebrow="COLLECTIONS"
          title="Payments by method"
          subtitle="Posted collections with reversals kept visible."
        >
          <DataTable
            columns={[
              ['payment_method', 'Method'],
              ['posted_count', 'Posted'],
              ['posted_amount', 'Amount', money],
              ['reversed_count', 'Reversed'],
              ['reversed_amount', 'Reversed amount', money],
            ]}
            empty="No collections in this period."
            rows={paymentRows}
          />
        </Panel>
      </div>

      <Panel
        eyebrow="DAILY RECONCILIATION"
        title="Revenue versus collections"
        subtitle="Revenue and cash movement are deliberately shown separately."
      >
        <DataTable
          columns={[
            ['date', 'Date'],
            ['charge_revenue', 'Charges', money],
            ['tax_revenue', 'Tax', money],
            ['gross_revenue', 'Gross revenue', money],
            ['collections', 'Collections', money],
            ['reversed_or_voided_collections', 'Reversed / voided', money],
          ]}
          empty="No revenue activity in this period."
          rows={dailyRows}
        />
      </Panel>
    </div>
  )
}

function ReservationsTab({ arrivals, sourceRows }) {
  const movementRows = [
    ...safeArray(arrivals.expected_arrivals).map((row) => ({
      movement: 'Expected arrival',
      ...row,
    })),
    ...safeArray(arrivals.expected_departures).map((row) => ({
      movement: 'Expected departure',
      ...row,
    })),
    ...safeArray(arrivals.actual_arrivals).map((row) => ({
      movement: 'Actual arrival',
      date: row.checkin_time,
      ...row,
    })),
    ...safeArray(arrivals.actual_departures).map((row) => ({
      movement: 'Actual departure',
      date: row.checkout_time,
      ...row,
    })),
  ]

  return (
    <div className="reports-tab-stack">
      <Panel
        eyebrow="SOURCE PERFORMANCE"
        title="Reservations by booking source"
        subtitle="Booking volume, checked-in stays, cancellations and booked value."
      >
        <DataTable
          columns={[
            ['booking_source', 'Source'],
            ['reservation_count', 'Reservations'],
            ['checked_in_count', 'Checked in'],
            ['checked_out_count', 'Checked out'],
            ['cancelled_count', 'Cancelled'],
            ['no_show_count', 'No show'],
            ['booked_value', 'Booked value', money],
          ]}
          empty="No reservations in this period."
          rows={sourceRows}
        />
      </Panel>

      <Panel
        eyebrow="FRONT DESK MOVEMENTS"
        title="Arrivals and departures"
        subtitle="Expected reservation movements reconciled with actual stay activity."
      >
        <DataTable
          columns={[
            ['movement', 'Movement'],
            ['date', 'Date / time'],
            ['guest_name', 'Guest'],
            ['room_number', 'Room'],
            ['reservation_number', 'Reservation'],
            ['booking_source', 'Source'],
            ['status', 'Status'],
          ]}
          empty="No arrivals or departures in this period."
          rows={movementRows}
        />
      </Panel>
    </div>
  )
}

function OperationsTab({ guestFoodService, housekeeping, serviceRows }) {
  return (
    <div className="reports-tab-stack">
      <div className="reports-three-column">
        <SummaryBlock
          label="Guest stays"
          lines={[
            ['Total stays', guestFoodService.stay_count],
            ['Unique guests', guestFoodService.unique_guests],
            ['Repeat guests', guestFoodService.repeat_guests],
            ['Completed stays', guestFoodService.completed_stays],
          ]}
        />
        <SummaryBlock
          label="Food operations"
          lines={[
            ['Orders', guestFoodService.food_orders],
            ['Delivered', guestFoodService.delivered_food_orders],
            ['Cancelled', guestFoodService.cancelled_food_orders],
            ['Delivered revenue', money(guestFoodService.delivered_food_revenue)],
          ]}
        />
        <SummaryBlock
          label="Housekeeping"
          lines={[
            ['Tasks', housekeeping.summary?.total_tasks],
            ['Completed', housekeeping.summary?.completed_tasks],
            ['Overdue', housekeeping.summary?.overdue_tasks],
            ['Avg. turnaround', `${number(housekeeping.summary?.average_turnaround_minutes, 2)} min`],
          ]}
        />
      </div>

      <Panel
        eyebrow="SERVICE SLA"
        title="Department performance"
        subtitle="Acceptance, completion, overdue workload and SLA attainment."
      >
        <DataTable
          columns={[
            ['department', 'Department'],
            ['request_count', 'Requests'],
            ['completed_count', 'Completed'],
            ['currently_overdue_count', 'Overdue'],
            ['sla_met_rate', 'SLA met', percent],
            ['average_accept_minutes', 'Avg. accept', (value) => `${number(value, 2)} min`],
            ['average_complete_minutes', 'Avg. complete', (value) => `${number(value, 2)} min`],
          ]}
          empty="No service requests in this period."
          rows={serviceRows}
        />
      </Panel>

      <Panel
        eyebrow="HOUSEKEEPING STATUS"
        title="Task distribution"
        subtitle="Current outcome mix for tasks created in the selected date window."
      >
        <BarList
          rows={safeArray(housekeeping.by_status).map((row) => ({
            label: row.status,
            value: row.task_count,
          }))}
          valueFormatter={number}
        />
      </Panel>
    </div>
  )
}

function TaxStaffTab({ staffRows, tax }) {
  return (
    <div className="reports-tab-stack">
      <div className="reports-tax-grid">
        <MetricCard
          label="Taxable amount"
          value={money(tax.taxable_amount)}
          note={`${number(tax.invoice_count)} issued / paid invoices`}
        />
        <MetricCard
          label="CGST"
          value={money(tax.cgst_amount)}
          note="Central GST"
        />
        <MetricCard
          label="SGST"
          value={money(tax.sgst_amount)}
          note="State GST"
        />
        <MetricCard
          label="IGST"
          value={money(tax.igst_amount)}
          note="Integrated GST"
        />
        <MetricCard
          label="Total tax"
          value={money(tax.total_tax)}
          note={`${number(tax.invoice_line_count)} invoice lines`}
        />
        <MetricCard
          label="Invoice total"
          value={money(tax.invoice_total)}
          note="Issued and paid invoices"
        />
      </div>

      <Panel
        eyebrow="PEOPLE & PRODUCTIVITY"
        title="Staff and work-department report"
        subtitle="Role, assigned workload, completion and derived operational departments."
      >
        <DataTable
          columns={[
            ['full_name', 'Staff'],
            ['role', 'Role'],
            ['work_departments', 'Work departments', (value) =>
              safeArray(value).join(', ') || '—'
            ],
            ['assigned_count', 'Assigned'],
            ['completed_count', 'Completed'],
            ['completion_rate', 'Completion', percent],
            ['status', 'Status'],
          ]}
          empty="No staff records are available."
          rows={staffRows}
        />
      </Panel>
    </div>
  )
}

function Panel({ children, eyebrow, subtitle, title }) {
  return (
    <section className="reports-panel">
      <div className="reports-panel-heading">
        <span>{eyebrow}</span>
        <h2>{title}</h2>
        <p>{subtitle}</p>
      </div>
      {children}
    </section>
  )
}

function SummaryBlock({ label, lines }) {
  return (
    <article className="reports-summary-block">
      <span>{label}</span>
      <div>
        {lines.map(([name, value]) => (
          <p key={name}>
            <span>{name}</span>
            <strong>{value ?? 0}</strong>
          </p>
        ))}
      </div>
    </article>
  )
}

function TrendChart({ data, formatter, suffix = '' }) {
  if (!data.length) {
    return <EmptyState message="No trend data in this period." />
  }

  const values = data.map((item) => Number(item.value || 0))
  const maximum = Math.max(...values, 1)
  const minimum = Math.min(...values, 0)
  const range = Math.max(maximum - minimum, 1)

  const points = data.map((item, index) => {
    const x = data.length === 1 ? 50 : (index / (data.length - 1)) * 100
    const y = 90 - ((Number(item.value || 0) - minimum) / range) * 72
    return `${x},${y}`
  }).join(' ')

  const latest = data[data.length - 1]

  return (
    <div className="reports-trend-chart">
      <div className="reports-chart-value">
        <strong>{formatter(latest.value)}</strong>
        <span>Latest · {latest.label}</span>
      </div>
      <svg
        aria-label={`Trend chart. Latest value ${latest.value}${suffix}`}
        preserveAspectRatio="none"
        role="img"
        viewBox="0 0 100 100"
      >
        <defs>
          <linearGradient id="reportsArea" x1="0" x2="0" y1="0" y2="1">
            <stop offset="0%" stopColor="#e4bd42" stopOpacity="0.38" />
            <stop offset="100%" stopColor="#e4bd42" stopOpacity="0" />
          </linearGradient>
        </defs>
        <polyline
          className="reports-chart-area"
          points={`0,100 ${points} 100,100`}
        />
        <polyline className="reports-chart-line" points={points} />
      </svg>
      <div className="reports-chart-axis">
        <span>{data[0]?.label}</span>
        <span>{latest.label}</span>
      </div>
    </div>
  )
}

function BarList({ rows, valueFormatter }) {
  if (!rows.length) {
    return <EmptyState message="No data in this period." />
  }

  const maximum = Math.max(...rows.map((row) => Number(row.value || 0)), 1)

  return (
    <div className="reports-bar-list">
      {rows.map((row) => (
        <div className="reports-bar-row" key={row.label}>
          <div>
            <span>{row.label || 'Other'}</span>
            <strong>{valueFormatter(row.value)}</strong>
          </div>
          <div className="reports-bar-track">
            <i
              style={{
                width: `${Math.max(
                  (Number(row.value || 0) / maximum) * 100,
                  Number(row.value || 0) > 0 ? 3 : 0
                )}%`,
              }}
            />
          </div>
        </div>
      ))}
    </div>
  )
}

function DataTable({ columns, empty, rows }) {
  if (!rows.length) return <EmptyState message={empty} />

  return (
    <div className="reports-table-wrap">
      <table className="reports-table">
        <thead>
          <tr>
            {columns.map(([, label]) => <th key={label}>{label}</th>)}
          </tr>
        </thead>
        <tbody>
          {rows.map((row, rowIndex) => (
            <tr key={row.id || `${rowIndex}-${JSON.stringify(row).slice(0, 32)}`}>
              {columns.map(([key, label, formatter]) => (
                <td data-label={label} key={key}>
                  {formatter
                    ? formatter(row[key])
                    : displayCell(row[key])
                  }
                </td>
              ))}
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  )
}

function displayCell(value) {
  if (Array.isArray(value)) return value.join(', ') || '—'
  if (value === null || value === undefined || value === '') return '—'
  return String(value).replaceAll('_', ' ')
}

function EmptyState({ message }) {
  return (
    <div className="reports-empty-state">
      <span>◇</span>
      <strong>{message}</strong>
    </div>
  )
}
