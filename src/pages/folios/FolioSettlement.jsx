import { useCallback, useEffect, useMemo, useRef, useState } from 'react'
import { supabase } from '../../lib/supabase'
import { normalizeRole } from '../../lib/currentStaff'
import {
  PAYMENT_METHODS,
  configureServiceRequestCharge,
  createSettlementRequestId,
  issueFolioCreditNote,
  loadFolioDetails,
  loadFolioWorkspace,
  postFolioCollection,
  postFolioSplitCollection,
  postServiceRequestCharge,
  processFolioRefund,
  requestFolioDiscount,
  requestFolioRefund,
  reviewFolioDiscount,
  voidFolioCreditNote,
} from '../../lib/folioSettlement'
import './FolioSettlement.css'

const EMPTY_WORKSPACE = {
  folios: [],
  exceptions: [],
  serviceTypes: [],
  serviceRequests: [],
  webhookEvents: [],
  serviceItems: [],
}

const EMPTY_SINGLE_COLLECTION = {
  amount: '',
  payment_method: 'cash',
  transaction_reference: '',
  provider: '',
  provider_payment_id: '',
}

const EMPTY_DISCOUNT = {
  discount_type: 'fixed',
  requested_value: '',
  reason: '',
}

const EMPTY_REFUND = {
  collection_id: '',
  amount: '',
  reason: '',
}

const EMPTY_CREDIT = {
  amount: '',
  reason: '',
}

const EMPTY_PROCESS_REFUND = {
  provider_refund_id: '',
  transaction_reference: '',
}

function newSplitLine(paymentMethod = 'cash') {
  return {
    id: createSettlementRequestId('split-line'),
    amount: '',
    payment_method: paymentMethod,
    transaction_reference: '',
    provider: '',
    provider_payment_id: '',
  }
}

export default function FolioSettlement({
  hotel,
  permissions = [],
  currentRole = '',
}) {
  const hotelId = hotel?.id || null
  const [workspace, setWorkspace] = useState(EMPTY_WORKSPACE)
  const [loading, setLoading] = useState(true)
  const [refreshing, setRefreshing] = useState(false)
  const [pageError, setPageError] = useState('')
  const [notice, setNotice] = useState('')
  const [activeView, setActiveView] = useState('folios')
  const [statusFilter, setStatusFilter] = useState('all')
  const [balanceFilter, setBalanceFilter] = useState('all')
  const [search, setSearch] = useState('')

  const [selectedFolioId, setSelectedFolioId] = useState(null)
  const [details, setDetails] = useState(null)
  const [detailsLoading, setDetailsLoading] = useState(false)
  const [detailTab, setDetailTab] = useState('ledger')
  const [actionMode, setActionMode] = useState('')
  const [actionBusy, setActionBusy] = useState(false)
  const [actionError, setActionError] = useState('')
  const [actionNotice, setActionNotice] = useState('')

  const [singleCollection, setSingleCollection] = useState(
    EMPTY_SINGLE_COLLECTION
  )
  const [singleRequestId, setSingleRequestId] = useState(() =>
    createSettlementRequestId('single-collection')
  )
  const [splitLines, setSplitLines] = useState(() => [
    newSplitLine('cash'),
    newSplitLine('upi'),
  ])
  const [splitRequestId, setSplitRequestId] = useState(() =>
    createSettlementRequestId('split-collection')
  )
  const [discountForm, setDiscountForm] = useState(EMPTY_DISCOUNT)
  const [discountRequestId, setDiscountRequestId] = useState(() =>
    createSettlementRequestId('discount')
  )
  const [refundForm, setRefundForm] = useState(EMPTY_REFUND)
  const [refundRequestId, setRefundRequestId] = useState(() =>
    createSettlementRequestId('refund')
  )
  const [creditForm, setCreditForm] = useState(EMPTY_CREDIT)
  const [creditRequestId, setCreditRequestId] = useState(() =>
    createSettlementRequestId('credit-note')
  )
  const [processRefundDrafts, setProcessRefundDrafts] = useState({})
  const [serviceDrafts, setServiceDrafts] = useState({})

  const refreshTimerRef = useRef(null)
  const workspaceRequestRef = useRef(0)
  const detailRequestRef = useRef(0)

  const normalizedRole = normalizeRole(currentRole)
  const canManage = useMemo(() => {
    if (['platform_admin', 'super_admin'].includes(normalizedRole)) return true
    if (
      permissions.some((permission) =>
        ['payments.manage', 'checkout.manage', 'invoices.manage'].includes(
          permission
        )
      )
    ) {
      return true
    }

    return [
      'owner',
      'manager',
      'accounts',
      'reception',
      'front_desk',
      'frontdesk',
    ].includes(normalizedRole)
  }, [normalizedRole, permissions])

  const selectedFolio = useMemo(
    () =>
      workspace.folios.find((folio) => folio.id === selectedFolioId) || null,
    [selectedFolioId, workspace.folios]
  )

  const totals = useMemo(
    () =>
      workspace.folios.reduce(
        (summary, folio) => {
          summary.charges += numberOf(folio.charges_amount)
          summary.discounts += numberOf(folio.discount_amount)
          summary.taxes += numberOf(folio.tax_amount)
          summary.collections += numberOf(folio.collection_amount)
          summary.refunds += numberOf(folio.refund_amount)
          summary.credits += numberOf(folio.credit_amount)
          summary.balance += numberOf(folio.balance_amount)
          if (folio.status === 'settled') summary.settled += 1
          else if (folio.status === 'open') summary.open += 1
          else summary.voided += 1
          return summary
        },
        {
          charges: 0,
          discounts: 0,
          taxes: 0,
          collections: 0,
          refunds: 0,
          credits: 0,
          balance: 0,
          settled: 0,
          open: 0,
          voided: 0,
        }
      ),
    [workspace.folios]
  )

  const filteredFolios = useMemo(() => {
    const needle = search.trim().toLowerCase()

    return workspace.folios.filter((folio) => {
      if (statusFilter !== 'all' && folio.status !== statusFilter) return false

      if (
        balanceFilter === 'positive' &&
        numberOf(folio.balance_amount) <= 0
      ) {
        return false
      }

      if (balanceFilter === 'zero' && numberOf(folio.balance_amount) !== 0) {
        return false
      }

      if (!needle) return true

      return [
        folio.folio_number,
        folio.guest?.full_name,
        folio.guest?.phone,
        folio.room?.room_number,
        folio.guestSession?.status,
      ]
        .filter(Boolean)
        .some((value) => String(value).toLowerCase().includes(needle))
    })
  }, [balanceFilter, search, statusFilter, workspace.folios])

  const loadWorkspace = useCallback(
    async ({ quiet = false } = {}) => {
      if (!hotelId) {
        setWorkspace(EMPTY_WORKSPACE)
        setLoading(false)
        return
      }

      const requestNumber = workspaceRequestRef.current + 1
      workspaceRequestRef.current = requestNumber

      if (quiet) setRefreshing(true)
      else setLoading(true)

      try {
        const nextWorkspace = await loadFolioWorkspace(hotelId)

        if (workspaceRequestRef.current !== requestNumber) return

        setWorkspace(nextWorkspace)
        setPageError('')
        setServiceDrafts((currentDrafts) =>
          buildServiceDrafts(nextWorkspace.serviceTypes, currentDrafts)
        )
      } catch (error) {
        if (workspaceRequestRef.current !== requestNumber) return
        console.error('Day 11 folio workspace error:', error)
        setPageError(error?.message || 'Unable to load folio workspace.')
      } finally {
        if (workspaceRequestRef.current === requestNumber) {
          setLoading(false)
          setRefreshing(false)
        }
      }
    },
    [hotelId]
  )

  const loadDetails = useCallback(
    async (folioId, { quiet = false } = {}) => {
      if (!hotelId || !folioId) return

      const requestNumber = detailRequestRef.current + 1
      detailRequestRef.current = requestNumber

      if (!quiet) setDetailsLoading(true)

      try {
        const nextDetails = await loadFolioDetails(hotelId, folioId)
        if (detailRequestRef.current !== requestNumber) return
        setDetails(nextDetails)
        setActionError('')
      } catch (error) {
        if (detailRequestRef.current !== requestNumber) return
        console.error('Day 11 folio detail error:', error)
        setActionError(error?.message || 'Unable to load folio detail.')
      } finally {
        if (detailRequestRef.current === requestNumber) {
          setDetailsLoading(false)
        }
      }
    },
    [hotelId]
  )

  useEffect(() => {
    setSelectedFolioId(null)
    setDetails(null)
    setNotice('')
    setPageError('')
    loadWorkspace()
  }, [hotelId, loadWorkspace])

  useEffect(() => {
    if (!hotelId) return undefined

    const scheduleRefresh = () => {
      window.clearTimeout(refreshTimerRef.current)
      refreshTimerRef.current = window.setTimeout(() => {
        loadWorkspace({ quiet: true })
        if (selectedFolioId) loadDetails(selectedFolioId, { quiet: true })
      }, 350)
    }

    const channel = supabase
      .channel(`day11_folio_workspace_${hotelId}`)
      .on(
        'postgres_changes',
        {
          event: '*',
          schema: 'public',
          table: 'folios',
          filter: `hotel_id=eq.${hotelId}`,
        },
        scheduleRefresh
      )
      .on(
        'postgres_changes',
        {
          event: '*',
          schema: 'public',
          table: 'folio_items',
          filter: `hotel_id=eq.${hotelId}`,
        },
        scheduleRefresh
      )
      .on(
        'postgres_changes',
        {
          event: '*',
          schema: 'public',
          table: 'folio_collections',
          filter: `hotel_id=eq.${hotelId}`,
        },
        scheduleRefresh
      )
      .on(
        'postgres_changes',
        {
          event: '*',
          schema: 'public',
          table: 'discount_approvals',
          filter: `hotel_id=eq.${hotelId}`,
        },
        scheduleRefresh
      )
      .on(
        'postgres_changes',
        {
          event: '*',
          schema: 'public',
          table: 'refunds',
          filter: `hotel_id=eq.${hotelId}`,
        },
        scheduleRefresh
      )
      .on(
        'postgres_changes',
        {
          event: '*',
          schema: 'public',
          table: 'credit_notes',
          filter: `hotel_id=eq.${hotelId}`,
        },
        scheduleRefresh
      )
      .on(
        'postgres_changes',
        {
          event: '*',
          schema: 'public',
          table: 'folio_adjustments',
          filter: `hotel_id=eq.${hotelId}`,
        },
        scheduleRefresh
      )
      .on(
        'postgres_changes',
        {
          event: '*',
          schema: 'public',
          table: 'payment_webhook_events',
          filter: `hotel_id=eq.${hotelId}`,
        },
        scheduleRefresh
      )
      .on(
        'postgres_changes',
        {
          event: '*',
          schema: 'public',
          table: 'folio_source_exceptions',
          filter: `hotel_id=eq.${hotelId}`,
        },
        scheduleRefresh
      )
      .on(
        'postgres_changes',
        {
          event: '*',
          schema: 'public',
          table: 'service_request_types',
          filter: `hotel_id=eq.${hotelId}`,
        },
        scheduleRefresh
      )
      .subscribe()

    return () => {
      window.clearTimeout(refreshTimerRef.current)
      supabase.removeChannel(channel)
    }
  }, [hotelId, loadDetails, loadWorkspace, selectedFolioId])

  useEffect(() => {
    if (!selectedFolioId) return
    loadDetails(selectedFolioId)
  }, [loadDetails, selectedFolioId])

  useEffect(() => {
    if (!selectedFolio) return
    setSingleCollection((current) => ({
      ...current,
      amount:
        current.amount ||
        (numberOf(selectedFolio.balance_amount) > 0
          ? String(numberOf(selectedFolio.balance_amount))
          : ''),
    }))
  }, [selectedFolio])

  function openFolio(folioId) {
    setSelectedFolioId(folioId)
    setDetailTab('ledger')
    setActionMode('')
    setActionError('')
    setActionNotice('')
  }

  function closeFolio() {
    setSelectedFolioId(null)
    setDetails(null)
    setActionMode('')
    setActionError('')
    setActionNotice('')
  }

  async function runAction(label, action, afterSuccess) {
    if (!canManage) {
      setActionError('Your current role has view-only folio access.')
      return
    }

    setActionBusy(true)
    setActionError('')
    setActionNotice('')

    try {
      const result = await action()
      setActionNotice(
        `${label}${result?.idempotent ? ' was already completed safely.' : ' completed.'}`
      )
      if (typeof afterSuccess === 'function') afterSuccess(result)
      await Promise.all([
        loadWorkspace({ quiet: true }),
        selectedFolioId
          ? loadDetails(selectedFolioId, { quiet: true })
          : Promise.resolve(),
      ])
    } catch (error) {
      console.error(`${label} failed:`, error)
      setActionError(error?.message || `${label} failed.`)
    } finally {
      setActionBusy(false)
    }
  }

  async function handleSingleCollection(event) {
    event.preventDefault()

    const amount = numberOf(singleCollection.amount)
    if (!selectedFolio || amount <= 0) {
      setActionError('Enter a positive collection amount.')
      return
    }

    if (amount > numberOf(selectedFolio.balance_amount)) {
      setActionError('Collection cannot exceed the current open balance.')
      return
    }

    await runAction(
      'Collection',
      () =>
        postFolioCollection(
          hotelId,
          selectedFolio.id,
          singleCollection,
          singleRequestId
        ),
      () => {
        setSingleCollection(EMPTY_SINGLE_COLLECTION)
        setSingleRequestId(createSettlementRequestId('single-collection'))
        setActionMode('')
      }
    )
  }

  async function handleSplitCollection(event) {
    event.preventDefault()

    if (!selectedFolio || splitLines.length < 2) {
      setActionError('Split collection requires at least two lines.')
      return
    }

    const total = splitLines.reduce(
      (sum, line) => sum + numberOf(line.amount),
      0
    )

    if (
      splitLines.some(
        (line) => numberOf(line.amount) <= 0 || !line.payment_method
      )
    ) {
      setActionError('Every split line requires a positive amount and method.')
      return
    }

    if (total > numberOf(selectedFolio.balance_amount)) {
      setActionError('Split total cannot exceed the open balance.')
      return
    }

    await runAction(
      'Split collection',
      () =>
        postFolioSplitCollection(
          hotelId,
          selectedFolio.id,
          splitLines,
          splitRequestId
        ),
      () => {
        setSplitLines([newSplitLine('cash'), newSplitLine('upi')])
        setSplitRequestId(createSettlementRequestId('split-collection'))
        setActionMode('')
      }
    )
  }

  async function handleDiscount(event) {
    event.preventDefault()

    if (
      !selectedFolio ||
      numberOf(discountForm.requested_value) <= 0 ||
      !discountForm.reason.trim()
    ) {
      setActionError('Enter the discount value and a clear reason.')
      return
    }

    await runAction(
      'Discount request',
      () =>
        requestFolioDiscount(
          hotelId,
          selectedFolio.id,
          discountForm,
          discountRequestId
        ),
      () => {
        setDiscountForm(EMPTY_DISCOUNT)
        setDiscountRequestId(createSettlementRequestId('discount'))
        setActionMode('')
        setDetailTab('discounts')
      }
    )
  }

  async function handleDiscountReview(approval, approve) {
    const notes = window.prompt(
      approve ? 'Approval notes (optional)' : 'Rejection notes (recommended)',
      ''
    )
    if (notes === null) return

    await runAction(
      approve ? 'Discount approval' : 'Discount rejection',
      () =>
        reviewFolioDiscount(
          hotelId,
          approval.id,
          approve,
          notes,
          createSettlementRequestId('discount-review')
        ),
      () => setDetailTab('discounts')
    )
  }

  async function handleRefund(event) {
    event.preventDefault()

    if (
      !selectedFolio ||
      !refundForm.collection_id ||
      numberOf(refundForm.amount) <= 0 ||
      !refundForm.reason.trim()
    ) {
      setActionError('Select a collection and enter refund amount and reason.')
      return
    }

    const sourceCollection = details?.collections.find(
      (collection) => collection.id === refundForm.collection_id
    )
    const refundable = getRefundableAmount(
      sourceCollection,
      details?.refunds || []
    )

    if (numberOf(refundForm.amount) > refundable) {
      setActionError(
        `Refund exceeds the available refundable amount ${formatMoney(refundable)}.`
      )
      return
    }

    await runAction(
      'Refund request',
      () =>
        requestFolioRefund(
          hotelId,
          selectedFolio.id,
          refundForm,
          refundRequestId
        ),
      () => {
        setRefundForm(EMPTY_REFUND)
        setRefundRequestId(createSettlementRequestId('refund'))
        setActionMode('')
        setDetailTab('refunds')
      }
    )
  }

  async function handleProcessRefund(refund) {
    const draft = processRefundDrafts[refund.id] || EMPTY_PROCESS_REFUND

    await runAction(
      'Refund processing',
      () =>
        processFolioRefund(
          hotelId,
          refund.id,
          draft,
          createSettlementRequestId('refund-process')
        ),
      () => {
        setProcessRefundDrafts((current) => {
          const next = { ...current }
          delete next[refund.id]
          return next
        })
        setDetailTab('refunds')
      }
    )
  }

  async function handleCredit(event) {
    event.preventDefault()

    if (
      !selectedFolio ||
      numberOf(creditForm.amount) <= 0 ||
      !creditForm.reason.trim()
    ) {
      setActionError('Enter a positive credit amount and reason.')
      return
    }

    if (numberOf(creditForm.amount) > numberOf(selectedFolio.balance_amount)) {
      setActionError('Credit note cannot exceed the current open balance.')
      return
    }

    await runAction(
      'Credit note',
      () =>
        issueFolioCreditNote(
          hotelId,
          selectedFolio.id,
          creditForm,
          creditRequestId
        ),
      () => {
        setCreditForm(EMPTY_CREDIT)
        setCreditRequestId(createSettlementRequestId('credit-note'))
        setActionMode('')
        setDetailTab('credits')
      }
    )
  }

  async function handleVoidCredit(creditNote) {
    const reason = window.prompt('Reason for voiding this credit note')
    if (!reason?.trim()) return

    await runAction(
      'Credit-note void',
      () =>
        voidFolioCreditNote(
          hotelId,
          creditNote.id,
          reason,
          createSettlementRequestId('credit-void')
        ),
      () => setDetailTab('credits')
    )
  }

  function updateSplitLine(lineId, field, value) {
    setSplitLines((current) =>
      current.map((line) =>
        line.id === lineId ? { ...line, [field]: value } : line
      )
    )
  }

  function addSplitLine() {
    setSplitLines((current) => [...current, newSplitLine('card')])
  }

  function removeSplitLine(lineId) {
    setSplitLines((current) =>
      current.length <= 2
        ? current
        : current.filter((line) => line.id !== lineId)
    )
  }

  function updateServiceDraft(typeId, field, value) {
    setServiceDrafts((current) => ({
      ...current,
      [typeId]: {
        ...current[typeId],
        [field]: value,
      },
    }))
  }

  async function saveServicePricing(serviceType) {
    const draft = serviceDrafts[serviceType.id]
    if (!draft) return

    if (
      draft.charge_enabled &&
      numberOf(draft.default_charge_amount) <= 0
    ) {
      setPageError('Enabled service pricing requires a positive amount.')
      return
    }

    setPageError('')
    setNotice('')

    try {
      await configureServiceRequestCharge(
        hotelId,
        serviceType.id,
        draft,
        createSettlementRequestId('service-pricing')
      )
      setNotice(`${serviceType.name} pricing saved.`)
      await loadWorkspace({ quiet: true })
    } catch (error) {
      console.error('Service pricing save failed:', error)
      setPageError(error?.message || 'Unable to save service pricing.')
    }
  }

  async function postServiceCharge(request) {
    setPageError('')
    setNotice('')

    try {
      const result = await postServiceRequestCharge(
        hotelId,
        request.id,
        createSettlementRequestId('service-post')
      )

      setNotice(
        `Service charge ${result?.idempotent ? 'already existed' : 'posted'} for ${
          request.guest?.full_name || 'guest'
        }.`
      )
      await loadWorkspace({ quiet: true })
    } catch (error) {
      console.error('Service charge post failed:', error)
      setPageError(error?.message || 'Unable to post service charge.')
    }
  }

  if (!hotelId) {
    return (
      <div className="folio-page">
        <EmptyState
          icon="🏨"
          title="Select a hotel"
          message="Choose an authorized property before opening the folio workspace."
        />
      </div>
    )
  }

  return (
    <div className="folio-page">
      <header className="folio-page-header">
        <div>
          <p className="folio-eyebrow">Day 11 · Authoritative finance</p>
          <h1>Folio & Settlement</h1>
          <p className="folio-page-subtitle">
            Unified room, food, service and manual charges with collections,
            discounts, refunds, credits and gateway reconciliation.
          </p>
        </div>

        <div className="folio-header-actions">
          <span className={`folio-access-badge ${canManage ? 'manage' : 'view'}`}>
            {canManage ? 'Settlement access' : 'View only'}
          </span>
          <button
            type="button"
            className="folio-button folio-button-secondary"
            onClick={() => loadWorkspace({ quiet: true })}
            disabled={refreshing}
          >
            {refreshing ? 'Refreshing…' : 'Refresh'}
          </button>
        </div>
      </header>

      {(pageError || notice) && (
        <div
          className={`folio-page-message ${pageError ? 'error' : 'success'}`}
          role={pageError ? 'alert' : 'status'}
        >
          <span>{pageError || notice}</span>
          <button
            type="button"
            onClick={() => {
              setPageError('')
              setNotice('')
            }}
          >
            ×
          </button>
        </div>
      )}

      <section className="folio-stat-grid">
        <StatCard label="Charges" value={formatMoney(totals.charges)} tone="gold" />
        <StatCard
          label="Collections"
          value={formatMoney(totals.collections)}
          tone="green"
        />
        <StatCard
          label="Open balance"
          value={formatMoney(totals.balance)}
          tone="orange"
        />
        <StatCard
          label="Discounts"
          value={formatMoney(totals.discounts)}
          tone="blue"
        />
        <StatCard label="Refunds" value={formatMoney(totals.refunds)} tone="red" />
        <StatCard label="Credits" value={formatMoney(totals.credits)} tone="violet" />
      </section>

      <section className="folio-status-strip">
        <div>
          <strong>{workspace.folios.length}</strong>
          <span>Total folios</span>
        </div>
        <div>
          <strong>{totals.open}</strong>
          <span>Open</span>
        </div>
        <div>
          <strong>{totals.settled}</strong>
          <span>Settled</span>
        </div>
        <div>
          <strong>{workspace.exceptions.filter((item) => item.status === 'open').length}</strong>
          <span>Source exceptions</span>
        </div>
        <div>
          <strong>
            {
              workspace.webhookEvents.filter(
                (event) => event.event_status === 'failed'
              ).length
            }
          </strong>
          <span>Failed gateway events</span>
        </div>
      </section>

      <nav className="folio-view-tabs" aria-label="Folio workspace sections">
        {[
          ['folios', 'Folios'],
          ['exceptions', 'Source Exceptions'],
          ['services', 'Service Pricing'],
          ['gateway', 'Gateway Events'],
        ].map(([id, label]) => (
          <button
            key={id}
            type="button"
            className={activeView === id ? 'active' : ''}
            onClick={() => setActiveView(id)}
          >
            {label}
          </button>
        ))}
      </nav>

      {loading ? (
        <LoadingState />
      ) : activeView === 'folios' ? (
        <FolioList
          folios={filteredFolios}
          search={search}
          onSearch={setSearch}
          statusFilter={statusFilter}
          onStatusFilter={setStatusFilter}
          balanceFilter={balanceFilter}
          onBalanceFilter={setBalanceFilter}
          onOpen={openFolio}
        />
      ) : activeView === 'exceptions' ? (
        <SourceExceptions exceptions={workspace.exceptions} />
      ) : activeView === 'services' ? (
        <ServicePricing
          serviceTypes={workspace.serviceTypes}
          serviceRequests={workspace.serviceRequests}
          drafts={serviceDrafts}
          canManage={canManage}
          onDraftChange={updateServiceDraft}
          onSave={saveServicePricing}
          onPost={postServiceCharge}
        />
      ) : (
        <GatewayEvents events={workspace.webhookEvents} folios={workspace.folios} />
      )}

      {selectedFolio && (
        <FolioDrawer
          folio={selectedFolio}
          details={details}
          loading={detailsLoading}
          activeTab={detailTab}
          onTab={setDetailTab}
          onClose={closeFolio}
          actionMode={actionMode}
          onActionMode={setActionMode}
          canManage={canManage}
          actionBusy={actionBusy}
          actionError={actionError}
          actionNotice={actionNotice}
          singleCollection={singleCollection}
          onSingleCollection={setSingleCollection}
          onSingleSubmit={handleSingleCollection}
          splitLines={splitLines}
          onSplitLine={updateSplitLine}
          onAddSplitLine={addSplitLine}
          onRemoveSplitLine={removeSplitLine}
          onSplitSubmit={handleSplitCollection}
          discountForm={discountForm}
          onDiscountForm={setDiscountForm}
          onDiscountSubmit={handleDiscount}
          onDiscountReview={handleDiscountReview}
          refundForm={refundForm}
          onRefundForm={setRefundForm}
          onRefundSubmit={handleRefund}
          processRefundDrafts={processRefundDrafts}
          onProcessRefundDraft={(refundId, field, value) =>
            setProcessRefundDrafts((current) => ({
              ...current,
              [refundId]: {
                ...(current[refundId] || EMPTY_PROCESS_REFUND),
                [field]: value,
              },
            }))
          }
          onProcessRefund={handleProcessRefund}
          creditForm={creditForm}
          onCreditForm={setCreditForm}
          onCreditSubmit={handleCredit}
          onVoidCredit={handleVoidCredit}
        />
      )}
    </div>
  )
}

function FolioList({
  folios,
  search,
  onSearch,
  statusFilter,
  onStatusFilter,
  balanceFilter,
  onBalanceFilter,
  onOpen,
}) {
  return (
    <section className="folio-panel">
      <div className="folio-toolbar">
        <label className="folio-search">
          <span>⌕</span>
          <input
            value={search}
            onChange={(event) => onSearch(event.target.value)}
            placeholder="Search folio, guest, phone or room"
          />
        </label>

        <select
          value={statusFilter}
          onChange={(event) => onStatusFilter(event.target.value)}
          aria-label="Folio status filter"
        >
          <option value="all">All statuses</option>
          <option value="open">Open</option>
          <option value="settled">Settled</option>
          <option value="voided">Voided</option>
        </select>

        <select
          value={balanceFilter}
          onChange={(event) => onBalanceFilter(event.target.value)}
          aria-label="Folio balance filter"
        >
          <option value="all">All balances</option>
          <option value="positive">Balance due</option>
          <option value="zero">Zero balance</option>
        </select>
      </div>

      {folios.length === 0 ? (
        <EmptyState
          icon="🧾"
          title="No matching folios"
          message="Adjust the search or filters to view the authoritative stay folios."
        />
      ) : (
        <div className="folio-table-wrap">
          <table className="folio-table">
            <thead>
              <tr>
                <th>Folio</th>
                <th>Guest & stay</th>
                <th>Room</th>
                <th>Charges</th>
                <th>Collections</th>
                <th>Adjustments</th>
                <th>Balance</th>
                <th>Status</th>
                <th aria-label="Actions" />
              </tr>
            </thead>
            <tbody>
              {folios.map((folio) => (
                <tr key={folio.id}>
                  <td>
                    <strong>{folio.folio_number}</strong>
                    <span>{formatDate(folio.opened_at)}</span>
                  </td>
                  <td>
                    <strong>{folio.guest?.full_name || 'Guest'}</strong>
                    <span>
                      {formatStayStatus(folio.guestSession?.status)} ·{' '}
                      {formatDate(folio.guestSession?.checkin_time, true)}
                    </span>
                  </td>
                  <td>
                    <strong>{folio.room?.room_number || 'Unassigned'}</strong>
                    <span>{folio.room?.room_type || '—'}</span>
                  </td>
                  <td>{formatMoney(folio.charges_amount)}</td>
                  <td>{formatMoney(folio.collection_amount)}</td>
                  <td>
                    <span className="folio-adjustment-mini">
                      −{formatCompactMoney(
                        numberOf(folio.discount_amount) +
                          numberOf(folio.credit_amount)
                      )}
                    </span>
                    <span className="folio-adjustment-mini refund">
                      +{formatCompactMoney(folio.refund_amount)}
                    </span>
                  </td>
                  <td>
                    <strong
                      className={
                        numberOf(folio.balance_amount) > 0
                          ? 'folio-balance-due'
                          : 'folio-balance-zero'
                      }
                    >
                      {formatMoney(folio.balance_amount)}
                    </strong>
                  </td>
                  <td>
                    <StatusPill value={folio.status} />
                  </td>
                  <td>
                    <button
                      type="button"
                      className="folio-row-button"
                      onClick={() => onOpen(folio.id)}
                    >
                      Open
                    </button>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
    </section>
  )
}

function FolioDrawer({
  folio,
  details,
  loading,
  activeTab,
  onTab,
  onClose,
  actionMode,
  onActionMode,
  canManage,
  actionBusy,
  actionError,
  actionNotice,
  singleCollection,
  onSingleCollection,
  onSingleSubmit,
  splitLines,
  onSplitLine,
  onAddSplitLine,
  onRemoveSplitLine,
  onSplitSubmit,
  discountForm,
  onDiscountForm,
  onDiscountSubmit,
  onDiscountReview,
  refundForm,
  onRefundForm,
  onRefundSubmit,
  processRefundDrafts,
  onProcessRefundDraft,
  onProcessRefund,
  creditForm,
  onCreditForm,
  onCreditSubmit,
  onVoidCredit,
}) {
  const sourceFolio = details?.folio || folio
  const postedCollections =
    details?.collections.filter((item) => item.status === 'posted') || []

  return (
    <div className="folio-drawer-backdrop" role="presentation">
      <aside
        className="folio-drawer"
        role="dialog"
        aria-modal="true"
        aria-label={`Folio ${folio.folio_number}`}
      >
        <header className="folio-drawer-header">
          <div>
            <p>{folio.folio_number}</p>
            <h2>{folio.guest?.full_name || 'Guest folio'}</h2>
            <span>
              Room {folio.room?.room_number || '—'} ·{' '}
              {formatStayStatus(folio.guestSession?.status)}
            </span>
          </div>

          <button
            type="button"
            className="folio-close-button"
            onClick={onClose}
            aria-label="Close folio"
          >
            ×
          </button>
        </header>

        <section className="folio-equation">
          <EquationValue label="Charges" value={sourceFolio.charges_amount} />
          <span>−</span>
          <EquationValue label="Discounts" value={sourceFolio.discount_amount} />
          <span>+</span>
          <EquationValue label="Taxes" value={sourceFolio.tax_amount} />
          <span>−</span>
          <EquationValue
            label="Collections"
            value={sourceFolio.collection_amount}
          />
          <span>+</span>
          <EquationValue label="Refunds" value={sourceFolio.refund_amount} />
          <span>−</span>
          <EquationValue label="Credits" value={sourceFolio.credit_amount} />
          <span>=</span>
          <EquationValue
            label="Balance"
            value={sourceFolio.balance_amount}
            emphasis
          />
        </section>

        <div className="folio-drawer-actions">
          {[
            ['collection', 'Collect'],
            ['split', 'Split payment'],
            ['discount', 'Discount'],
            ['refund', 'Refund'],
            ['credit', 'Credit note'],
          ].map(([id, label]) => (
            <button
              key={id}
              type="button"
              disabled={
                !canManage ||
                actionBusy ||
                sourceFolio.status === 'voided' ||
                (['collection', 'split', 'discount', 'credit'].includes(id) &&
                  numberOf(sourceFolio.balance_amount) <= 0) ||
                (id === 'refund' && postedCollections.length === 0)
              }
              className={actionMode === id ? 'active' : ''}
              onClick={() => onActionMode(actionMode === id ? '' : id)}
            >
              {label}
            </button>
          ))}
        </div>

        {actionMode && (
          <section className="folio-action-panel">
            <div className="folio-action-panel-header">
              <strong>{actionTitle(actionMode)}</strong>
              <button type="button" onClick={() => onActionMode('')}>
                ×
              </button>
            </div>

            {actionError && <div className="folio-action-message error">{actionError}</div>}
            {actionNotice && (
              <div className="folio-action-message success">{actionNotice}</div>
            )}

            {actionMode === 'collection' && (
              <SingleCollectionForm
                value={singleCollection}
                onChange={onSingleCollection}
                onSubmit={onSingleSubmit}
                busy={actionBusy}
                balance={sourceFolio.balance_amount}
              />
            )}

            {actionMode === 'split' && (
              <SplitCollectionForm
                lines={splitLines}
                onChange={onSplitLine}
                onAdd={onAddSplitLine}
                onRemove={onRemoveSplitLine}
                onSubmit={onSplitSubmit}
                busy={actionBusy}
                balance={sourceFolio.balance_amount}
              />
            )}

            {actionMode === 'discount' && (
              <DiscountForm
                value={discountForm}
                onChange={onDiscountForm}
                onSubmit={onDiscountSubmit}
                busy={actionBusy}
                balance={sourceFolio.balance_amount}
              />
            )}

            {actionMode === 'refund' && (
              <RefundForm
                value={refundForm}
                onChange={onRefundForm}
                onSubmit={onRefundSubmit}
                busy={actionBusy}
                collections={postedCollections}
                refunds={details?.refunds || []}
              />
            )}

            {actionMode === 'credit' && (
              <CreditForm
                value={creditForm}
                onChange={onCreditForm}
                onSubmit={onCreditSubmit}
                busy={actionBusy}
                balance={sourceFolio.balance_amount}
              />
            )}
          </section>
        )}

        <nav className="folio-detail-tabs">
          {[
            ['ledger', 'Ledger'],
            ['collections', 'Collections'],
            ['discounts', 'Discounts'],
            ['refunds', 'Refunds'],
            ['credits', 'Credits'],
            ['audit', 'Audit trail'],
          ].map(([id, label]) => (
            <button
              key={id}
              type="button"
              className={activeTab === id ? 'active' : ''}
              onClick={() => onTab(id)}
            >
              {label}
            </button>
          ))}
        </nav>

        <div className="folio-drawer-body">
          {loading || !details ? (
            <LoadingState compact />
          ) : activeTab === 'ledger' ? (
            <LedgerTab details={details} />
          ) : activeTab === 'collections' ? (
            <CollectionsTab collections={details.collections} />
          ) : activeTab === 'discounts' ? (
            <DiscountsTab
              discounts={details.discounts}
              canManage={canManage}
              busy={actionBusy}
              onReview={onDiscountReview}
            />
          ) : activeTab === 'refunds' ? (
            <RefundsTab
              refunds={details.refunds}
              canManage={canManage}
              busy={actionBusy}
              drafts={processRefundDrafts}
              onDraft={onProcessRefundDraft}
              onProcess={onProcessRefund}
            />
          ) : activeTab === 'credits' ? (
            <CreditsTab
              creditNotes={details.creditNotes}
              canManage={canManage}
              busy={actionBusy}
              onVoid={onVoidCredit}
            />
          ) : (
            <AuditTab
              events={details.events}
              webhookEvents={details.webhookEvents}
            />
          )}
        </div>
      </aside>
    </div>
  )
}

function SingleCollectionForm({ value, onChange, onSubmit, busy, balance }) {
  return (
    <form className="folio-form" onSubmit={onSubmit}>
      <div className="folio-form-grid">
        <Field label="Amount">
          <input
            type="number"
            min="0.01"
            step="0.01"
            max={numberOf(balance)}
            value={value.amount}
            onChange={(event) =>
              onChange({ ...value, amount: event.target.value })
            }
            required
          />
        </Field>
        <Field label="Method">
          <PaymentMethodSelect
            value={value.payment_method}
            onChange={(paymentMethod) =>
              onChange({ ...value, payment_method: paymentMethod })
            }
          />
        </Field>
        <Field label="Reference">
          <input
            value={value.transaction_reference}
            onChange={(event) =>
              onChange({
                ...value,
                transaction_reference: event.target.value,
              })
            }
            placeholder="Receipt / UTR / reference"
          />
        </Field>
        <Field label="Provider">
          <input
            value={value.provider}
            onChange={(event) =>
              onChange({ ...value, provider: event.target.value })
            }
            placeholder="Optional"
          />
        </Field>
        <Field label="Provider payment ID">
          <input
            value={value.provider_payment_id}
            onChange={(event) =>
              onChange({
                ...value,
                provider_payment_id: event.target.value,
              })
            }
            placeholder="Optional"
          />
        </Field>
      </div>
      <FormFooter
        hint={`Open balance ${formatMoney(balance)}`}
        busy={busy}
        label="Post collection"
      />
    </form>
  )
}

function SplitCollectionForm({
  lines,
  onChange,
  onAdd,
  onRemove,
  onSubmit,
  busy,
  balance,
}) {
  const total = lines.reduce((sum, line) => sum + numberOf(line.amount), 0)

  return (
    <form className="folio-form" onSubmit={onSubmit}>
      <div className="folio-split-lines">
        {lines.map((line, index) => (
          <div className="folio-split-line" key={line.id}>
            <span className="folio-split-index">{index + 1}</span>
            <input
              type="number"
              min="0.01"
              step="0.01"
              value={line.amount}
              onChange={(event) =>
                onChange(line.id, 'amount', event.target.value)
              }
              placeholder="Amount"
              required
            />
            <PaymentMethodSelect
              value={line.payment_method}
              onChange={(value) =>
                onChange(line.id, 'payment_method', value)
              }
            />
            <input
              value={line.transaction_reference}
              onChange={(event) =>
                onChange(
                  line.id,
                  'transaction_reference',
                  event.target.value
                )
              }
              placeholder="Reference"
            />
            <button
              type="button"
              className="folio-icon-button"
              onClick={() => onRemove(line.id)}
              disabled={lines.length <= 2}
              aria-label={`Remove split line ${index + 1}`}
            >
              −
            </button>
          </div>
        ))}
      </div>

      <button
        type="button"
        className="folio-add-line"
        onClick={onAdd}
        disabled={busy}
      >
        + Add payment method
      </button>

      <FormFooter
        hint={`Split total ${formatMoney(total)} · Open balance ${formatMoney(
          balance
        )}`}
        busy={busy}
        label="Post split collection"
      />
    </form>
  )
}

function DiscountForm({ value, onChange, onSubmit, busy, balance }) {
  return (
    <form className="folio-form" onSubmit={onSubmit}>
      <div className="folio-form-grid">
        <Field label="Discount type">
          <select
            value={value.discount_type}
            onChange={(event) =>
              onChange({ ...value, discount_type: event.target.value })
            }
          >
            <option value="fixed">Fixed amount</option>
            <option value="percentage">Percentage</option>
          </select>
        </Field>
        <Field
          label={
            value.discount_type === 'percentage' ? 'Percentage' : 'Amount'
          }
        >
          <input
            type="number"
            min="0.01"
            step="0.01"
            max={
              value.discount_type === 'percentage' ? 100 : numberOf(balance)
            }
            value={value.requested_value}
            onChange={(event) =>
              onChange({ ...value, requested_value: event.target.value })
            }
            required
          />
        </Field>
        <Field label="Reason" wide>
          <textarea
            value={value.reason}
            onChange={(event) =>
              onChange({ ...value, reason: event.target.value })
            }
            placeholder="Business reason for approval"
            required
          />
        </Field>
      </div>
      <FormFooter
        hint="Discount remains pending until reviewed."
        busy={busy}
        label="Request discount"
      />
    </form>
  )
}

function RefundForm({
  value,
  onChange,
  onSubmit,
  busy,
  collections,
  refunds,
}) {
  const sourceCollection = collections.find(
    (collection) => collection.id === value.collection_id
  )
  const refundable = getRefundableAmount(sourceCollection, refunds)

  return (
    <form className="folio-form" onSubmit={onSubmit}>
      <div className="folio-form-grid">
        <Field label="Source collection" wide>
          <select
            value={value.collection_id}
            onChange={(event) =>
              onChange({ ...value, collection_id: event.target.value })
            }
            required
          >
            <option value="">Select posted collection</option>
            {collections.map((collection) => {
              const available = getRefundableAmount(collection, refunds)
              return (
                <option
                  key={collection.id}
                  value={collection.id}
                  disabled={available <= 0}
                >
                  {formatDate(collection.collected_at)} ·{' '}
                  {formatPaymentMethod(collection.payment_method)} ·{' '}
                  {formatMoney(collection.amount)} · refundable{' '}
                  {formatMoney(available)}
                </option>
              )
            })}
          </select>
        </Field>
        <Field label="Refund amount">
          <input
            type="number"
            min="0.01"
            step="0.01"
            max={refundable || undefined}
            value={value.amount}
            onChange={(event) =>
              onChange({ ...value, amount: event.target.value })
            }
            required
          />
        </Field>
        <Field label="Reason" wide>
          <textarea
            value={value.reason}
            onChange={(event) =>
              onChange({ ...value, reason: event.target.value })
            }
            placeholder="Reason for refund"
            required
          />
        </Field>
      </div>
      <FormFooter
        hint={`Available refundable amount ${formatMoney(refundable)}`}
        busy={busy}
        label="Request refund"
      />
    </form>
  )
}

function CreditForm({ value, onChange, onSubmit, busy, balance }) {
  return (
    <form className="folio-form" onSubmit={onSubmit}>
      <div className="folio-form-grid">
        <Field label="Credit amount">
          <input
            type="number"
            min="0.01"
            step="0.01"
            max={numberOf(balance)}
            value={value.amount}
            onChange={(event) =>
              onChange({ ...value, amount: event.target.value })
            }
            required
          />
        </Field>
        <Field label="Reason" wide>
          <textarea
            value={value.reason}
            onChange={(event) =>
              onChange({ ...value, reason: event.target.value })
            }
            placeholder="Reason for credit note"
            required
          />
        </Field>
      </div>
      <FormFooter
        hint={`Credit cannot exceed open balance ${formatMoney(balance)}.`}
        busy={busy}
        label="Issue credit note"
      />
    </form>
  )
}

function LedgerTab({ details }) {
  const rows = [
    ...details.items.map((item) => ({
      id: item.id,
      at: item.service_at,
      type: item.item_kind === 'tax' ? 'Tax' : formatStatus(item.charge_category),
      description: item.description,
      amount: numberOf(item.amount),
      direction: 'charge',
      status: item.posting_status,
      source: item.source_table,
    })),
    ...details.adjustments.map((adjustment) => ({
      id: adjustment.id,
      at: adjustment.posted_at,
      type: formatStatus(adjustment.adjustment_type),
      description: adjustment.reason,
      amount: numberOf(adjustment.amount),
      direction:
        adjustment.adjustment_type === 'refund' ? 'refund' : 'reduction',
      status: adjustment.status,
      source: 'folio_adjustments',
    })),
  ].sort(
    (first, second) =>
      new Date(second.at).getTime() - new Date(first.at).getTime()
  )

  return (
    <DetailTable
      columns={['Date', 'Type', 'Description', 'Source', 'Amount', 'Status']}
      empty="No ledger entries."
    >
      {rows.map((row) => (
        <tr key={`${row.source}:${row.id}`}>
          <td>{formatDate(row.at)}</td>
          <td>{row.type}</td>
          <td>{row.description}</td>
          <td>{formatStatus(row.source)}</td>
          <td className={`folio-money-${row.direction}`}>
            {row.direction === 'charge' || row.direction === 'refund' ? '+' : '−'}
            {formatMoney(row.amount)}
          </td>
          <td>
            <StatusPill value={row.status} />
          </td>
        </tr>
      ))}
    </DetailTable>
  )
}

function CollectionsTab({ collections }) {
  return (
    <DetailTable
      columns={['Collected', 'Method', 'Amount', 'Reference', 'Provider', 'Status']}
      empty="No collection history."
    >
      {collections.map((collection) => (
        <tr key={collection.id}>
          <td>{formatDate(collection.collected_at)}</td>
          <td>{formatPaymentMethod(collection.payment_method)}</td>
          <td>{formatMoney(collection.amount)}</td>
          <td>{collection.transaction_reference || '—'}</td>
          <td>{collection.provider || formatStatus(collection.source_table) || '—'}</td>
          <td>
            <StatusPill value={collection.status} />
          </td>
        </tr>
      ))}
    </DetailTable>
  )
}

function DiscountsTab({ discounts, canManage, busy, onReview }) {
  return (
    <DetailTable
      columns={['Requested', 'Type', 'Requested amount', 'Reason', 'Status', 'Review']}
      empty="No discount requests."
    >
      {discounts.map((discount) => (
        <tr key={discount.id}>
          <td>{formatDate(discount.requested_at)}</td>
          <td>
            {formatStatus(discount.discount_type)} ·{' '}
            {discount.discount_type === 'percentage'
              ? `${numberOf(discount.requested_value)}%`
              : formatMoney(discount.requested_value)}
          </td>
          <td>{formatMoney(discount.requested_amount)}</td>
          <td>{discount.reason}</td>
          <td>
            <StatusPill value={discount.status} />
          </td>
          <td>
            {discount.status === 'pending' && canManage ? (
              <div className="folio-inline-actions">
                <button
                  type="button"
                  disabled={busy}
                  onClick={() => onReview(discount, true)}
                >
                  Approve
                </button>
                <button
                  type="button"
                  className="danger"
                  disabled={busy}
                  onClick={() => onReview(discount, false)}
                >
                  Reject
                </button>
              </div>
            ) : (
              discount.review_notes || '—'
            )}
          </td>
        </tr>
      ))}
    </DetailTable>
  )
}

function RefundsTab({
  refunds,
  canManage,
  busy,
  drafts,
  onDraft,
  onProcess,
}) {
  return (
    <div className="folio-refund-list">
      {refunds.length === 0 ? (
        <EmptyState
          icon="↩"
          title="No refunds"
          message="Requested and processed refunds will appear here."
          compact
        />
      ) : (
        refunds.map((refund) => {
          const draft = drafts[refund.id] || EMPTY_PROCESS_REFUND

          return (
            <article className="folio-refund-card" key={refund.id}>
              <div>
                <span>{formatDate(refund.requested_at)}</span>
                <h4>{formatMoney(refund.amount)}</h4>
                <p>{refund.reason}</p>
                <small>
                  Method {formatPaymentMethod(refund.payment_method)} · Source{' '}
                  {shortId(refund.folio_collection_id)}
                </small>
              </div>

              <div className="folio-refund-card-status">
                <StatusPill value={refund.status} />
                {refund.provider_refund_id && (
                  <small>{refund.provider_refund_id}</small>
                )}
              </div>

              {refund.status === 'pending' && canManage && (
                <div className="folio-refund-process">
                  <input
                    value={draft.provider_refund_id}
                    onChange={(event) =>
                      onDraft(
                        refund.id,
                        'provider_refund_id',
                        event.target.value
                      )
                    }
                    placeholder="Provider refund ID"
                  />
                  <input
                    value={draft.transaction_reference}
                    onChange={(event) =>
                      onDraft(
                        refund.id,
                        'transaction_reference',
                        event.target.value
                      )
                    }
                    placeholder="Transaction reference"
                  />
                  <button
                    type="button"
                    disabled={busy}
                    onClick={() => onProcess(refund)}
                  >
                    Mark processed
                  </button>
                </div>
              )}
            </article>
          )
        })
      )}
    </div>
  )
}

function CreditsTab({ creditNotes, canManage, busy, onVoid }) {
  return (
    <DetailTable
      columns={['Credit note', 'Issued', 'Amount', 'Reason', 'Status', 'Action']}
      empty="No credit notes."
    >
      {creditNotes.map((creditNote) => (
        <tr key={creditNote.id}>
          <td>{creditNote.credit_note_number}</td>
          <td>{formatDate(creditNote.issued_at)}</td>
          <td>{formatMoney(creditNote.amount)}</td>
          <td>{creditNote.reason}</td>
          <td>
            <StatusPill value={creditNote.status} />
          </td>
          <td>
            {creditNote.status === 'issued' && canManage ? (
              <button
                type="button"
                className="folio-table-action-danger"
                disabled={busy}
                onClick={() => onVoid(creditNote)}
              >
                Void
              </button>
            ) : (
              creditNote.void_reason || '—'
            )}
          </td>
        </tr>
      ))}
    </DetailTable>
  )
}

function AuditTab({ events, webhookEvents }) {
  return (
    <div className="folio-audit-stack">
      <section>
        <h3>Immutable folio events</h3>
        <DetailTable
          columns={['Date', 'Event', 'Entity', 'Actor', 'Metadata']}
          empty="No audit events."
        >
          {events.map((event) => (
            <tr key={event.id}>
              <td>{formatDate(event.created_at)}</td>
              <td>{formatStatus(event.event_type)}</td>
              <td>
                {formatStatus(event.entity_type)} · {shortId(event.entity_id)}
              </td>
              <td>{shortId(event.actor_id)}</td>
              <td>{jsonSummary(event.metadata)}</td>
            </tr>
          ))}
        </DetailTable>
      </section>

      <section>
        <h3>Linked gateway events</h3>
        <GatewayEventTable events={webhookEvents} compact />
      </section>
    </div>
  )
}

function SourceExceptions({ exceptions }) {
  const openCount = exceptions.filter((item) => item.status === 'open').length

  return (
    <section className="folio-panel">
      <div className="folio-section-heading">
        <div>
          <p className="folio-eyebrow">Strict no-guess ledger</p>
          <h2>Source exceptions</h2>
          <span>
            {openCount} open source rows remain intentionally unposted until
            they can be mapped safely.
          </span>
        </div>
      </div>

      <DetailTable
        columns={['Source', 'Reason', 'Guest', 'Candidates', 'Seen', 'Status']}
        empty="No source exceptions."
      >
        {exceptions.map((exception) => (
          <tr key={exception.id}>
            <td>
              <strong>{formatStatus(exception.source_table)}</strong>
              <span>{shortId(exception.source_id)}</span>
            </td>
            <td>{formatStatus(exception.exception_code)}</td>
            <td>{shortId(exception.guest_id)}</td>
            <td>{exception.candidate_count}</td>
            <td>{formatDate(exception.last_seen_at)}</td>
            <td>
              <StatusPill value={exception.status} />
            </td>
          </tr>
        ))}
      </DetailTable>
    </section>
  )
}

function ServicePricing({
  serviceTypes,
  serviceRequests,
  drafts,
  canManage,
  onDraftChange,
  onSave,
  onPost,
}) {
  const typeMap = Object.fromEntries(serviceTypes.map((type) => [type.id, type]))

  return (
    <div className="folio-service-layout">
      <section className="folio-panel">
        <div className="folio-section-heading">
          <div>
            <p className="folio-eyebrow">Hotel-configurable contract</p>
            <h2>Service pricing</h2>
            <span>
              Completion alone never creates a charge. Enable a positive price
              explicitly.
            </span>
          </div>
        </div>

        <div className="folio-service-type-grid">
          {serviceTypes.map((serviceType) => {
            const draft = drafts[serviceType.id] || {}

            return (
              <article className="folio-service-type-card" key={serviceType.id}>
                <div className="folio-service-type-title">
                  <div>
                    <strong>{serviceType.name}</strong>
                    <span>{serviceType.code}</span>
                  </div>
                  <label className="folio-switch">
                    <input
                      type="checkbox"
                      checked={Boolean(draft.charge_enabled)}
                      onChange={(event) =>
                        onDraftChange(
                          serviceType.id,
                          'charge_enabled',
                          event.target.checked
                        )
                      }
                      disabled={!canManage}
                    />
                    <span />
                  </label>
                </div>

                <div className="folio-form-grid">
                  <Field label="Default amount">
                    <input
                      type="number"
                      min="0.01"
                      step="0.01"
                      value={draft.default_charge_amount || ''}
                      onChange={(event) =>
                        onDraftChange(
                          serviceType.id,
                          'default_charge_amount',
                          event.target.value
                        )
                      }
                      disabled={!canManage || !draft.charge_enabled}
                    />
                  </Field>

                  <Field label="Posting">
                    <select
                      value={draft.charge_posting_policy || 'manual'}
                      onChange={(event) =>
                        onDraftChange(
                          serviceType.id,
                          'charge_posting_policy',
                          event.target.value
                        )
                      }
                      disabled={!canManage || !draft.charge_enabled}
                    >
                      <option value="manual">Manual</option>
                      <option value="on_completion">On completion</option>
                    </select>
                  </Field>

                  <Field label="Description" wide>
                    <input
                      value={draft.charge_description || ''}
                      onChange={(event) =>
                        onDraftChange(
                          serviceType.id,
                          'charge_description',
                          event.target.value
                        )
                      }
                      disabled={!canManage}
                      placeholder={serviceType.name}
                    />
                  </Field>
                </div>

                <div className="folio-service-type-footer">
                  <label>
                    <input
                      type="checkbox"
                      checked={Boolean(draft.charge_taxable)}
                      onChange={(event) =>
                        onDraftChange(
                          serviceType.id,
                          'charge_taxable',
                          event.target.checked
                        )
                      }
                      disabled={!canManage}
                    />
                    Taxable when Day 12 GST is enabled
                  </label>
                  <button
                    type="button"
                    className="folio-button"
                    onClick={() => onSave(serviceType)}
                    disabled={!canManage}
                  >
                    Save pricing
                  </button>
                </div>
              </article>
            )
          })}
        </div>
      </section>

      <section className="folio-panel">
        <div className="folio-section-heading">
          <div>
            <p className="folio-eyebrow">Completed request queue</p>
            <h2>Service charge posting</h2>
            <span>
              Manual posting is available only for completed, mapped and priced
              requests.
            </span>
          </div>
        </div>

        <DetailTable
          columns={['Created', 'Guest', 'Room', 'Service', 'Mapping', 'Charge']}
          empty="No service requests."
        >
          {serviceRequests.map((request) => {
            const serviceType = typeMap[request.request_type_id]
            const chargeEnabled = Boolean(serviceType?.charge_enabled)
            const amount = numberOf(serviceType?.default_charge_amount)
            const alreadyPosted = Boolean(request.postedItem)
            const hasException = Boolean(request.sourceException)
            const canPost =
              canManage &&
              request.status === 'completed' &&
              chargeEnabled &&
              amount > 0 &&
              !alreadyPosted &&
              !hasException

            return (
              <tr key={request.id}>
                <td>{formatDate(request.created_at)}</td>
                <td>{request.guest?.full_name || 'Guest'}</td>
                <td>{request.room?.room_number || '—'}</td>
                <td>
                  <strong>{serviceType?.name || request.request_type || 'Service'}</strong>
                  <span>{formatStatus(request.status)}</span>
                </td>
                <td>
                  {hasException ? (
                    <StatusPill value={request.sourceException.exception_code} />
                  ) : (
                    <StatusPill value="mapped" />
                  )}
                </td>
                <td>
                  {alreadyPosted ? (
                    <span className="folio-posted-charge">
                      Posted {formatMoney(request.postedItem.amount)}
                    </span>
                  ) : (
                    <button
                      type="button"
                      className="folio-row-button"
                      disabled={!canPost}
                      onClick={() => onPost(request)}
                      title={servicePostDisabledReason(
                        request,
                        serviceType,
                        canManage
                      )}
                    >
                      {chargeEnabled && amount > 0
                        ? `Post ${formatMoney(amount)}`
                        : 'Not priced'}
                    </button>
                  )}
                </td>
              </tr>
            )
          })}
        </DetailTable>
      </section>
    </div>
  )
}

function GatewayEvents({ events, folios }) {
  const folioMap = Object.fromEntries(
    folios.map((folio) => [folio.id, folio.folio_number])
  )

  return (
    <section className="folio-panel">
      <div className="folio-section-heading">
        <div>
          <p className="folio-eyebrow">Trusted-server reconciliation</p>
          <h2>Gateway events</h2>
          <span>
            Browser access is read-only. Signature verification and webhook
            processing remain server-owned.
          </span>
        </div>
      </div>

      <GatewayEventTable events={events} folioMap={folioMap} />
    </section>
  )
}

function GatewayEventTable({ events, folioMap = {}, compact = false }) {
  return (
    <DetailTable
      columns={[
        'Received',
        'Provider',
        'Event',
        'Signature',
        'Status',
        'Folio',
        'Attempts',
        'Error',
      ]}
      empty="No gateway events."
      compact={compact}
    >
      {events.map((event) => (
        <tr key={event.id}>
          <td>{formatDate(event.received_at)}</td>
          <td>{event.provider}</td>
          <td>{formatStatus(event.event_type)}</td>
          <td>
            <StatusPill value={event.signature_valid ? 'valid' : 'invalid'} />
          </td>
          <td>
            <StatusPill value={event.event_status} />
          </td>
          <td>{folioMap[event.folio_id] || shortId(event.folio_id)}</td>
          <td>{event.processing_attempts}</td>
          <td>{event.last_error || '—'}</td>
        </tr>
      ))}
    </DetailTable>
  )
}

function DetailTable({ columns, children, empty, compact = false }) {
  const rows = Array.isArray(children) ? children : children ? [children] : []

  if (rows.length === 0) {
    return (
      <EmptyState
        icon="—"
        title={empty}
        message="This authoritative ledger currently has no matching rows."
        compact
      />
    )
  }

  return (
    <div className={`folio-detail-table-wrap ${compact ? 'compact' : ''}`}>
      <table className="folio-detail-table">
        <thead>
          <tr>
            {columns.map((column) => (
              <th key={column}>{column}</th>
            ))}
          </tr>
        </thead>
        <tbody>{children}</tbody>
      </table>
    </div>
  )
}

function StatCard({ label, value, tone }) {
  return (
    <article className={`folio-stat-card ${tone}`}>
      <span>{label}</span>
      <strong>{value}</strong>
    </article>
  )
}

function EquationValue({ label, value, emphasis = false }) {
  return (
    <div className={emphasis ? 'emphasis' : ''}>
      <span>{label}</span>
      <strong>{formatCompactMoney(value)}</strong>
    </div>
  )
}

function StatusPill({ value }) {
  const normalized = String(value || 'unknown')
    .trim()
    .toLowerCase()

  return (
    <span className={`folio-status-pill ${statusTone(normalized)}`}>
      {formatStatus(normalized)}
    </span>
  )
}

function Field({ label, children, wide = false }) {
  return (
    <label className={`folio-field ${wide ? 'wide' : ''}`}>
      <span>{label}</span>
      {children}
    </label>
  )
}

function FormFooter({ hint, busy, label }) {
  return (
    <div className="folio-form-footer">
      <span>{hint}</span>
      <button type="submit" className="folio-button" disabled={busy}>
        {busy ? 'Processing…' : label}
      </button>
    </div>
  )
}

function PaymentMethodSelect({ value, onChange }) {
  return (
    <select
      value={value}
      onChange={(event) => onChange(event.target.value)}
    >
      {PAYMENT_METHODS.map((method) => (
        <option key={method.value} value={method.value}>
          {method.label}
        </option>
      ))}
    </select>
  )
}

function LoadingState({ compact = false }) {
  return (
    <div className={`folio-loading ${compact ? 'compact' : ''}`}>
      <span />
      <strong>Loading authoritative folio data…</strong>
    </div>
  )
}

function EmptyState({ icon, title, message, compact = false }) {
  return (
    <div className={`folio-empty-state ${compact ? 'compact' : ''}`}>
      <span>{icon}</span>
      <strong>{title}</strong>
      <p>{message}</p>
    </div>
  )
}

function buildServiceDrafts(serviceTypes, currentDrafts = {}) {
  return Object.fromEntries(
    serviceTypes.map((serviceType) => [
      serviceType.id,
      currentDrafts[serviceType.id] || {
        charge_enabled: Boolean(serviceType.charge_enabled),
        default_charge_amount:
          serviceType.default_charge_amount === null
            ? ''
            : String(serviceType.default_charge_amount),
        charge_posting_policy:
          serviceType.charge_posting_policy || 'manual',
        charge_taxable: Boolean(serviceType.charge_taxable),
        charge_description: serviceType.charge_description || '',
      },
    ])
  )
}

function getRefundableAmount(collection, refunds) {
  if (!collection || collection.status !== 'posted') return 0

  const reserved = refunds
    .filter(
      (refund) =>
        refund.folio_collection_id === collection.id &&
        ['pending', 'processed'].includes(refund.status)
    )
    .reduce((sum, refund) => sum + numberOf(refund.amount), 0)

  return Math.max(0, numberOf(collection.amount) - reserved)
}

function servicePostDisabledReason(request, serviceType, canManage) {
  if (!canManage) return 'View-only access'
  if (request.postedItem) return 'Charge already posted'
  if (request.sourceException) return 'Request is unmatched or ambiguous'
  if (request.status !== 'completed') return 'Request is not completed'
  if (!serviceType?.charge_enabled) return 'Service pricing is disabled'
  if (numberOf(serviceType?.default_charge_amount) <= 0) {
    return 'A positive service price is required'
  }
  return 'Post service charge'
}

function actionTitle(mode) {
  return {
    collection: 'Post collection',
    split: 'Split or multi-method collection',
    discount: 'Request discount approval',
    refund: 'Request partial or full refund',
    credit: 'Issue credit note',
  }[mode]
}

function numberOf(value) {
  const parsed = Number(value)
  return Number.isFinite(parsed) ? parsed : 0
}

function formatMoney(value) {
  return new Intl.NumberFormat('en-IN', {
    style: 'currency',
    currency: 'INR',
    maximumFractionDigits: 2,
  }).format(numberOf(value))
}

function formatCompactMoney(value) {
  return new Intl.NumberFormat('en-IN', {
    style: 'currency',
    currency: 'INR',
    notation: 'compact',
    maximumFractionDigits: 1,
  }).format(numberOf(value))
}

function formatDate(value, short = false) {
  if (!value) return '—'
  const date = new Date(value)
  if (Number.isNaN(date.getTime())) return '—'

  return date.toLocaleString('en-IN', {
    day: '2-digit',
    month: 'short',
    year: short ? undefined : 'numeric',
    hour: '2-digit',
    minute: '2-digit',
  })
}

function formatStatus(value) {
  if (!value) return '—'
  return String(value)
    .replace(/[._-]+/g, ' ')
    .replace(/\b\w/g, (character) => character.toUpperCase())
}

function formatStayStatus(value) {
  return formatStatus(value || 'stay')
}

function formatPaymentMethod(value) {
  return formatStatus(value || 'other')
}

function shortId(value) {
  if (!value) return '—'
  const text = String(value)
  return text.length > 12 ? `${text.slice(0, 8)}…` : text
}

function jsonSummary(value) {
  if (!value || typeof value !== 'object') return '—'
  const keys = Object.keys(value)
  if (keys.length === 0) return '—'
  return keys
    .slice(0, 4)
    .map((key) => `${formatStatus(key)}: ${String(value[key])}`)
    .join(' · ')
}

function statusTone(value) {
  if (
    ['settled', 'posted', 'processed', 'approved', 'valid', 'mapped'].includes(
      value
    )
  ) {
    return 'success'
  }

  if (
    ['open', 'pending', 'received', 'manual', 'requested'].includes(value)
  ) {
    return 'warning'
  }

  if (
    [
      'failed',
      'invalid',
      'rejected',
      'voided',
      'reversed',
      'source unmatched',
      'source_unmatched',
      'source ambiguous',
      'source_ambiguous',
    ].includes(value)
  ) {
    return 'danger'
  }

  return 'neutral'
}
