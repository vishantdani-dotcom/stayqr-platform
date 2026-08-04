import { memo, useCallback, useEffect, useMemo, useRef, useState } from 'react'
import {
  cancelGuestFoodOrder,
  getGuestAccessContext,
  getGuestFoodOrders,
  getGuestMenu,
  getGuestNotifications,
  placeGuestFoodOrder,
  resolveGuestPortal,
  resolvePremiumGuestGuide,
} from '../../lib/guestPortal'
import { createRequestId } from '../../lib/day15Operations'
import {
  GUEST_GUIDE_LOCALES,
  getGuestGuideMediaUrl,
} from '../../lib/guestGuideBuilder'
import {
  getDiningCopy,
  getLocalizedNotification,
  localizeMenuItem,
  localizeOrderItem,
  localizeStatus,
} from '../../lib/diningI18n'
import {
  persistGuestLocale,
  readPreferredGuestLocale,
  replaceGuestLocaleInUrl,
  withGuestLocale,
} from '../../lib/guestLocale'
import './FoodMenu.css'

const ACCESS_RECHECK_INTERVAL_MS = 30000
const ORDER_RECHECK_INTERVAL_MS = 12000
const CLOCK_RECHECK_INTERVAL_MS = 30000
const STATUS_FLOW = [
  'pending',
  'accepted',
  'preparing',
  'ready',
  'out_for_delivery',
  'delivered',
]

const CATEGORY_ICONS = {
  all: 'grid',
  featured: 'star',
  breakfast: 'sun',
  beverages: 'cup',
  beverage: 'cup',
  dinner: 'utensils',
  lunch: 'bowl',
  meal: 'plate',
  meals: 'plate',
  thali: 'plate',
  thalis: 'plate',
  sides: 'bowl',
  dessert: 'sparkles',
  desserts: 'sparkles',
}

const MenuItemCard = memo(function MenuItemCard({
  item,
  featured,
  heroImageUrl,
  copy,
  onAdd,
  priority = false,
}) {
  return (
    <article className="food-item-card">
      <div className="food-item-image">
        <MenuItemImage item={item} fallbackImage={heroImageUrl} priority={priority} />
        <div className="food-card-badges">
          {featured && <span className="featured"><FoodIcon name="star" /> {copy.featured}</span>}
          {(item.modifier_groups || []).length > 0 && <span>{copy.customisable}</span>}
        </div>
      </div>
      <div className="food-item-copy">
        <div className="food-item-top">
          <div>
            <span className="food-item-category">{item.category || copy.hotelMenu}</span>
            <h3>{item.item_name}</h3>
          </div>
          <strong>{money(item.price, item.currency_code)}</strong>
        </div>
        <p>{item.description || copy.preparedFresh}</p>
        <div className="food-item-meta">
          <span><FoodIcon name="clock" /> {item.preparation_minutes || 20} {copy.min}</span>
          {Number(item.tax_rate || 0) > 0 && (
            <span>
              {item.tax_rate}% {copy.tax} {item.tax_inclusive ? copy.included : copy.extra}
            </span>
          )}
        </div>
        <button type="button" onClick={() => onAdd(item)}>
          <span>{(item.modifier_groups || []).length ? copy.customiseAdd : copy.addToCart}</span>
          <b>+</b>
        </button>
      </div>
    </article>
  )
})

export default function FoodMenu() {
  const [portal, setPortal] = useState(null)
  const [brandPortal, setBrandPortal] = useState(null)
  const [items, setItems] = useState([])
  const [orders, setOrders] = useState([])
  const [notifications, setNotifications] = useState([])
  const [cart, setCart] = useState([])
  const [selectedItem, setSelectedItem] = useState(null)
  const [selectedModifiers, setSelectedModifiers] = useState({})
  const [loading, setLoading] = useState(true)
  const [submitting, setSubmitting] = useState(false)
  const [busyId, setBusyId] = useState('')
  const [toast, setToast] = useState('')
  const [activeCategory, setActiveCategory] = useState('all')
  const [nowMs, setNowMs] = useState(() => Date.now())
  const [locale, setLocale] = useState('en')
  const [defaultLocale, setDefaultLocale] = useState('en')
  const [enabledLocales, setEnabledLocales] = useState(['en'])
  const toastTimerRef = useRef(null)

  const copy = useMemo(() => getDiningCopy(locale), [locale])

  const showToast = useCallback((message) => {
    setToast(String(message || ''))
    window.clearTimeout(toastTimerRef.current)
    toastTimerRef.current = window.setTimeout(() => setToast(''), 3200)
  }, [])

  useEffect(
    () => () => window.clearTimeout(toastTimerRef.current),
    []
  )

  const validateAccess = useCallback(async () => {
    try {
      const nextPortal = await resolveGuestPortal('food')
      if (!nextPortal?.session) throw new Error('Guest access is unavailable.')
      setPortal(nextPortal)
      return nextPortal
    } catch (error) {
      console.error('Food access validation failed:', error)
      setPortal(null)
      setBrandPortal(null)
      setItems([])
      setOrders([])
      setCart([])
      return null
    }
  }, [])

  const loadBranding = useCallback(async () => {
    try {
      const nextBrandPortal = await resolvePremiumGuestGuide('food')
      setBrandPortal(nextBrandPortal || null)
      const settings = nextBrandPortal?.premium_guide?.settings || {}
      const nextEnabled = Array.isArray(settings.enabled_locales)
        && settings.enabled_locales.length > 0
        ? settings.enabled_locales
        : ['en']
      const nextDefault = nextEnabled.includes(settings.default_locale)
        ? settings.default_locale
        : nextEnabled[0] || 'en'
      const hotelSlug = nextBrandPortal?.hotel?.slug || getGuestAccessContext('food').hotelSlug
      const preferred = readPreferredGuestLocale({
        hotelSlug,
        enabledLocales: nextEnabled,
        defaultLocale: nextDefault,
      })
      setEnabledLocales(nextEnabled)
      setDefaultLocale(nextDefault)
      setLocale(preferred)
      persistGuestLocale(hotelSlug, preferred)
      replaceGuestLocaleInUrl(preferred)
      return nextBrandPortal
    } catch (error) {
      console.warn('Premium dining branding unavailable:', error)
      setBrandPortal(null)
      return null
    }
  }, [])

  const loadMenuData = useCallback(async () => {
    const menuResult = await getGuestMenu()
    setItems(menuResult)
  }, [])

  const loadOrderData = useCallback(async () => {
    const [orderResult, notificationResult] = await Promise.all([
      getGuestFoodOrders(),
      getGuestNotifications().catch(() => []),
    ])
    setOrders(orderResult)
    setNotifications(
      notificationResult.filter((entry) => entry.source_type === 'food_order')
    )
  }, [])

  const initialize = useCallback(async () => {
    setLoading(true)
    const validPortal = await validateAccess()
    if (validPortal) {
      try {
        await Promise.all([loadMenuData(), loadOrderData(), loadBranding()])
      } catch (error) {
        console.error('Food page load failed:', error)
        showToast(error.message || getDiningCopy('en').menuLoadFailed)
      }
    }
    setLoading(false)
  }, [loadBranding, loadMenuData, loadOrderData, showToast, validateAccess])

  useEffect(() => {
    void initialize()
  }, [initialize])

  useEffect(() => {
    if (!portal?.session) return undefined

    const refreshAccessAndOrders = () => {
      if (document.visibilityState !== 'visible') return
      void validateAccess().then((valid) => valid && loadOrderData())
    }
    const refreshOrders = () => {
      if (document.visibilityState === 'visible') void loadOrderData()
    }

    const accessTimer = window.setInterval(
      refreshAccessAndOrders,
      ACCESS_RECHECK_INTERVAL_MS
    )
    const orderTimer = window.setInterval(
      refreshOrders,
      ORDER_RECHECK_INTERVAL_MS
    )
    const clockTimer = window.setInterval(
      () => setNowMs(Date.now()),
      CLOCK_RECHECK_INTERVAL_MS
    )

    window.addEventListener('focus', refreshAccessAndOrders)
    document.addEventListener('visibilitychange', refreshAccessAndOrders)

    return () => {
      window.clearInterval(accessTimer)
      window.clearInterval(orderTimer)
      window.clearInterval(clockTimer)
      window.removeEventListener('focus', refreshAccessAndOrders)
      document.removeEventListener('visibilitychange', refreshAccessAndOrders)
    }
  }, [loadOrderData, portal?.session, validateAccess])

  const localizedItems = useMemo(
    () => items.map((item) => localizeMenuItem(item, locale, defaultLocale)),
    [defaultLocale, items, locale]
  )

  const localizedOrders = useMemo(
    () => orders.map((order) => ({
      ...order,
      food_order_items: (order.food_order_items || []).map(
        (item) => localizeOrderItem(item, locale, defaultLocale)
      ),
    })),
    [defaultLocale, locale, orders]
  )

  const localizedNotifications = useMemo(
    () => notifications.map((notification) => getLocalizedNotification(notification, copy)),
    [copy, notifications]
  )

  useEffect(() => {
    if (cart.length === 0) return
    const itemMap = new Map(localizedItems.map((item) => [item.id, item]))
    setCart((current) => current.map((line) => {
      const nextItem = itemMap.get(line.item.id)
      if (!nextItem) return line
      const modifierMap = new Map(
        (nextItem.modifier_groups || [])
          .flatMap((group) => group.modifiers || [])
          .map((modifier) => [modifier.id, modifier])
      )
      return {
        ...line,
        item: nextItem,
        modifiers: line.modifiers.map(
          (modifier) => modifierMap.get(modifier.id) || modifier
        ),
      }
    }))
    // Only locale/menu identity changes should relocalise existing cart lines.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [localizedItems])

  const groupedItems = useMemo(() => {
    const groups = new Map()
    localizedItems.forEach((item) => {
      const category = item.category || copy.hotelMenu
      if (!groups.has(category)) groups.set(category, [])
      groups.get(category).push(item)
    })
    return Array.from(groups.entries())
  }, [copy.hotelMenu, localizedItems])

  const categories = useMemo(
    () => groupedItems.map(([category]) => category),
    [groupedItems]
  )

  const featuredItems = useMemo(() => {
    const photoItems = localizedItems.filter((item) => Boolean(item.image_url))
    const source = photoItems.length >= 4 ? photoItems : localizedItems
    return source.slice(0, Math.min(4, source.length))
  }, [localizedItems])

  const featuredIds = useMemo(
    () => new Set(featuredItems.map((item) => item.id)),
    [featuredItems]
  )

  const visibleItems = useMemo(() => {
    if (activeCategory === 'featured') return featuredItems
    if (activeCategory === 'all') return localizedItems
    return localizedItems.filter((item) => item.category === activeCategory)
  }, [activeCategory, featuredItems, localizedItems])

  useEffect(() => {
    if (activeCategory === 'all' || activeCategory === 'featured') return
    if (!categories.includes(activeCategory)) setActiveCategory('all')
  }, [activeCategory, categories])

  const totals = useMemo(() => cart.reduce(
    (sum, line) => {
      const financials = calculateLineFinancials(line)
      return {
        subtotal: sum.subtotal + financials.subtotal,
        modifiers: sum.modifiers + financials.modifiers,
        tax: sum.tax + financials.tax,
        total: sum.total + financials.total,
        quantity: sum.quantity + Number(line.quantity || 0),
      }
    },
    { subtotal: 0, modifiers: 0, tax: 0, total: 0, quantity: 0 }
  ), [cart])

  const premiumGuide = brandPortal?.premium_guide || {}
  const guideSettings = premiumGuide.settings || {}
  const guideMedia = useMemo(
    () => (Array.isArray(premiumGuide.media) ? premiumGuide.media : [])
      .filter((media) => media?.is_active !== false)
      .filter((media) => !media.locale || media.locale === locale || media.locale === defaultLocale),
    [defaultLocale, locale, premiumGuide.media]
  )

  const logoMedia = guideMedia.find((media) => media.category === 'logo')
    || guideMedia.find((media) => media.category === 'profile')
    || null
  const heroMedia = guideMedia.find((media) => media.category === 'hero')
    || guideMedia.find((media) => media.category === 'property')
    || guideMedia.find((media) => media.category === 'room')
    || null
  const offerMedia = guideMedia.find((media) => media.media_key === 'dining_offer_banner')
    || guideMedia.find((media) => media.media_key === 'offer_banner')
    || guideMedia.find((media) => media.category === 'custom' && /offer/i.test(media.media_key || ''))
    || null
  const storyMedia = guideMedia.find((media) => media.media_key === 'dining_kitchen_story')
    || guideMedia.find((media) => media.category === 'dining')
    || null

  const hotel = portal?.hotel || brandPortal?.hotel || {}
  const room = portal?.session?.rooms || portal?.session?.room || {}
  const hotelName = hotel.hotel_name || copy.hotelMenu
  const hotelSlug = hotel.slug || getGuestAccessContext('food').hotelSlug
  const hotelLogoUrl = logoMedia ? getGuestGuideMediaUrl(logoMedia.object_path) : ''
  const firstItemImage = localizedItems.find((item) => item.image_url)?.image_url || ''
  const heroImageUrl = heroMedia ? getGuestGuideMediaUrl(heroMedia.object_path) : firstItemImage
  const offerImageUrl = offerMedia ? getGuestGuideMediaUrl(offerMedia.object_path) : ''
  const storyImageUrl = storyMedia
    ? getGuestGuideMediaUrl(storyMedia.object_path)
    : offerImageUrl || heroImageUrl
  const averagePrep = localizedItems.length > 0
    ? Math.max(1, Math.round(
      localizedItems.reduce(
        (sum, item) => sum + Number(item.preparation_minutes || 20),
        0
      ) / localizedItems.length
    ))
    : 20

  const diningBranding = guideSettings?.branding?.dining || {}
  const offerConfig = guideSettings?.branding?.offer || {}
  const explicitOfferTranslation = offerConfig?.translations?.[locale] || null
  const defaultOfferTranslation = offerConfig?.translations?.[defaultLocale]
    || offerConfig?.translations?.en
    || {}
  const offerTranslation = explicitOfferTranslation
    || (locale === defaultLocale ? defaultOfferTranslation : {})
  const offerEnabled = offerConfig.enabled !== false
  const offerBadge = offerTranslation.badge
    || (locale === defaultLocale ? offerConfig.badge : copy.offerBadgeDefault)
    || copy.offerBadgeDefault
  const offerTitle = offerTranslation.title
    || (locale === defaultLocale ? offerConfig.title : copy.offerTitleDefault)
    || copy.offerTitleDefault
  const offerDescription = offerTranslation.description
    || (locale === defaultLocale ? offerConfig.description : copy.offerDescriptionDefault)
    || copy.offerDescriptionDefault
  const offerButton = offerTranslation.button_label
    || (locale === defaultLocale ? offerConfig.button_label : copy.offerCtaDefault)
    || copy.offerCtaDefault
  const videoUrl = safeExternalUrl(
    diningBranding.video_url || guideSettings?.branding?.video_url || ''
  )

  const handleLocaleChange = useCallback((nextLocale) => {
    if (!enabledLocales.includes(nextLocale)) return
    setLocale(nextLocale)
    persistGuestLocale(hotelSlug, nextLocale)
    replaceGuestLocaleInUrl(nextLocale)
  }, [enabledLocales, hotelSlug])

  function openConfigurator(item) {
    const defaults = {}
    ;(item.modifier_groups || []).forEach((group) => {
      defaults[group.id] = []
    })
    setSelectedModifiers(defaults)
    setSelectedItem(item)
  }

  function toggleModifier(group, modifier) {
    setSelectedModifiers((current) => {
      const existing = current[group.id] || []
      const selected = existing.includes(modifier.id)
      if (selected) {
        return {
          ...current,
          [group.id]: existing.filter((id) => id !== modifier.id),
        }
      }
      if (group.max_selections === 1) {
        return { ...current, [group.id]: [modifier.id] }
      }
      if (existing.length >= Number(group.max_selections || 1)) return current
      return { ...current, [group.id]: [...existing, modifier.id] }
    })
  }

  function addLineToCart(item, modifiers = []) {
    const modifierKey = modifiers.map((modifier) => modifier.id).sort().join(',')
    const lineKey = `${item.id}:${modifierKey}`
    setCart((current) => {
      const existing = current.find((line) => line.key === lineKey)
      if (existing) {
        return current.map((line) => (
          line.key === lineKey
            ? { ...line, quantity: line.quantity + 1 }
            : line
        ))
      }
      return [...current, { key: lineKey, item, modifiers, quantity: 1 }]
    })
    showToast(`${item.item_name} ${copy.addedToCart}`)
  }

  const handleAddItem = useCallback((item) => {
    if ((item.modifier_groups || []).length > 0) {
      openConfigurator(item)
      return
    }
    addLineToCart(item)
    // copy/showToast are current because this callback is recreated on locale change.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [copy.addedToCart])

  function addConfiguredItem() {
    if (!selectedItem) return
    const groups = selectedItem.modifier_groups || []
    for (const group of groups) {
      const count = (selectedModifiers[group.id] || []).length
      if (
        count < Number(group.min_selections || 0)
        || count > Number(group.max_selections || 1)
      ) {
        showToast(copy.interpolate('chooseOptions', {
          group: group.name,
          range: `${group.min_selections}-${group.max_selections}`,
        }))
        return
      }
    }

    const allModifiers = groups.flatMap((group) => (
      (group.modifiers || []).filter((modifier) => (
        (selectedModifiers[group.id] || []).includes(modifier.id)
      ))
    ))
    addLineToCart(selectedItem, allModifiers)
    setSelectedItem(null)
  }

  function changeQuantity(key, amount) {
    setCart((current) => current
      .map((line) => (
        line.key === key
          ? { ...line, quantity: Math.max(0, line.quantity + amount) }
          : line
      ))
      .filter((line) => line.quantity > 0))
  }

  function removeLine(key) {
    setCart((current) => current.filter((line) => line.key !== key))
  }

  async function submitOrder() {
    if (submitting || cart.length === 0) return
    setSubmitting(true)
    try {
      const valid = await validateAccess()
      if (!valid) throw new Error(copy.accessUnavailableBody)
      const payload = {
        request_id: createRequestId('food'),
        items: cart.map((line) => ({
          menu_item_id: line.item.id,
          quantity: line.quantity,
          modifier_ids: line.modifiers.map((modifier) => modifier.id),
        })),
      }
      const result = await placeGuestFoodOrder(payload)
      setCart([])
      await loadOrderData()
      showToast(result?.idempotent ? copy.orderAlreadyReceived : copy.orderSent)
      scrollToOrders()
    } catch (error) {
      console.error('Food order failed:', error)
      showToast(error.message || copy.menuLoadFailed)
    } finally {
      setSubmitting(false)
    }
  }

  async function cancelOrder(order) {
    if (!order?.can_cancel || busyId) return
    if (!window.confirm(copy.cancelConfirm)) return
    setBusyId(order.id)
    try {
      const valid = await validateAccess()
      if (!valid) throw new Error(copy.accessUnavailableBody)
      await cancelGuestFoodOrder(order.id)
      await loadOrderData()
      showToast(copy.orderCancelled)
    } catch (error) {
      showToast(error.message || copy.unableCancel)
    } finally {
      setBusyId('')
    }
  }

  function returnToGuide() {
    const { hotelSlug: accessSlug, accessToken } = getGuestAccessContext('food')
    if (accessSlug && accessToken) {
      const target = `/guest/${encodeURIComponent(accessSlug)}/${encodeURIComponent(accessToken)}`
      window.location.href = withGuestLocale(target, locale)
    }
  }

  function scrollToMenu() {
    document.getElementById('food-menu')?.scrollIntoView({
      behavior: 'smooth',
      block: 'start',
    })
  }

  function scrollToOrders() {
    document.getElementById('food-orders')?.scrollIntoView({
      behavior: 'smooth',
      block: 'start',
    })
  }

  function handleOfferAction() {
    const actionType = String(offerConfig.action_type || 'section')
    const actionValue = String(offerConfig.action_value || '')
    if (actionType === 'url') {
      const target = safeExternalUrl(actionValue)
      if (target) window.open(target, '_blank', 'noopener,noreferrer')
      else scrollToMenu()
      return
    }
    if (actionType === 'call') {
      const phone = actionValue.replace(/[^0-9+]/g, '')
      if (phone) window.location.href = `tel:${phone}`
      else scrollToMenu()
      return
    }
    if (actionType === 'whatsapp') {
      const phone = actionValue.replace(/[^0-9]/g, '')
      if (phone) window.open(`https://wa.me/${phone}`, '_blank', 'noopener,noreferrer')
      else scrollToMenu()
      return
    }
    if (actionType === 'guest_guide') {
      returnToGuide()
      return
    }
    if (actionType === 'orders') {
      scrollToOrders()
      return
    }
    scrollToMenu()
  }

  if (loading) {
    return <div className="food-guest-state">{copy.loading}</div>
  }

  if (!portal?.session) {
    return (
      <div className="food-guest-state">
        <strong>{copy.accessUnavailable}</strong>
        <span>{copy.accessUnavailableBody}</span>
      </div>
    )
  }

  const selectedModifierList = selectedItem
    ? (selectedItem.modifier_groups || []).flatMap((group) => (
      (group.modifiers || []).filter((modifier) => (
        (selectedModifiers[group.id] || []).includes(modifier.id)
      ))
    ))
    : []
  const selectedFinancials = selectedItem
    ? calculateLineFinancials({
      item: selectedItem,
      modifiers: selectedModifierList,
      quantity: 1,
    })
    : null

  return (
    <div className="food-guest-page" lang={locale}>
      <div className="food-app-shell">
        <aside className="food-side-nav">
          <button
            type="button"
            className="food-brand"
            onClick={returnToGuide}
            aria-label={copy.backToGuestGuide}
          >
            <img src="/assets/stayqr-official-logo.png" alt="StayQR" />
          </button>

          <nav aria-label={copy.dining}>
            <button type="button" className="active" onClick={scrollToMenu}>
              <FoodIcon name="utensils" /> <span>{copy.dining}</span>
            </button>
            <button type="button" onClick={returnToGuide}>
              <FoodIcon name="guide" /> <span>{copy.guestGuide}</span>
            </button>
            <button type="button" onClick={returnToGuide}>
              <FoodIcon name="bell" /> <span>{copy.inRoomServices}</span>
            </button>
            <button type="button" onClick={scrollToOrders}>
              <FoodIcon name="receipt" /> <span>{copy.myOrders}</span>
            </button>
          </nav>

          <div className="food-side-trust">
            <strong>{copy.secureHotelDining}</strong>
            <p>{copy.interpolate('roomLinked', { room: room.room_number || '—' })}</p>
          </div>

          <div className="food-powered-by">
            <span>{copy.poweredSecurelyBy}</span>
            <img src="/assets/stayqr-official-logo.png" alt="StayQR" />
          </div>
        </aside>

        <div className="food-main-column">
          <header className="food-topbar">
            <button type="button" className="food-back" onClick={returnToGuide}>
              ← {copy.backToGuestGuide}
            </button>
            <div className="food-top-actions">
              {enabledLocales.length > 1 && (
                <label className="food-language-picker">
                  <span>{copy.language}</span>
                  <select
                    value={locale}
                    onChange={(event) => handleLocaleChange(event.target.value)}
                    aria-label={copy.language}
                  >
                    {enabledLocales.map((code) => {
                      const definition = GUEST_GUIDE_LOCALES.find((entry) => entry.code === code)
                      return (
                        <option key={code} value={code}>
                          {definition?.nativeName || code.toUpperCase()}
                        </option>
                      )
                    })}
                  </select>
                </label>
              )}
              <div className="food-stay-pills">
                <span><FoodIcon name="room" /> {copy.room} {room.room_number || '—'}</span>
                <span className="active"><i /> {copy.stayActive}</span>
              </div>
            </div>
          </header>

          <section
            className="food-hero-card"
            style={heroImageUrl
              ? { '--food-hero-image': `url(${heroImageUrl})` }
              : undefined}
          >
            <div className="food-hero-overlay" />
            <div className="food-hotel-logo">
              {hotelLogoUrl
                ? <img src={hotelLogoUrl} alt={`${hotelName} logo`} decoding="async" />
                : <span>{getInitials(hotelName)}</span>}
            </div>
            <div className="food-hero-content">
              <span className="food-kicker">{copy.stayqrDining}</span>
              <h1>{hotelName}</h1>
              <p>{copy.diningDelivered}</p>
              <div className="food-hero-chips">
                <span><FoodIcon name="clock" /> {copy.approx} {averagePrep}-{averagePrep + 10} {copy.min}</span>
                <span><FoodIcon name="shield" /> {copy.secureOrdering}</span>
                <span><FoodIcon name="chef" /> {copy.liveKitchenTracking}</span>
              </div>
            </div>
            <div className="food-hero-art"><FoodIcon name="cloche" size={58} /></div>
          </section>

          {offerEnabled && (
            <section
              className={`food-offer-band${offerImageUrl ? ' has-image' : ''}`}
              style={offerImageUrl
                ? { '--food-offer-image': `url(${offerImageUrl})` }
                : undefined}
            >
              <div className="food-offer-shade" />
              <div className="food-offer-icon"><FoodIcon name="gift" size={30} /></div>
              <div className="food-offer-copy">
                <span>{offerBadge}</span>
                <h2>{offerTitle}</h2>
                <p>{offerDescription}</p>
              </div>
              <button type="button" className="food-offer-cta" onClick={handleOfferAction}>
                {offerButton} <span>→</span>
              </button>
            </section>
          )}

          <div className="food-content-grid">
            <main className="food-menu-panel" id="food-menu">
              <div className="food-category-strip" role="tablist" aria-label={copy.dining}>
                <CategoryButton
                  label={copy.all}
                  icon="grid"
                  active={activeCategory === 'all'}
                  onClick={() => setActiveCategory('all')}
                />
                {featuredItems.length > 0 && (
                  <CategoryButton
                    label={copy.featured}
                    icon="star"
                    active={activeCategory === 'featured'}
                    onClick={() => setActiveCategory('featured')}
                  />
                )}
                {categories.map((category) => (
                  <CategoryButton
                    key={category}
                    label={category}
                    icon={getCategoryIcon(category)}
                    active={activeCategory === category}
                    onClick={() => setActiveCategory(category)}
                  />
                ))}
              </div>

              <div className="food-section-heading premium">
                <div>
                  <span>{activeCategory === 'featured' ? copy.curatedForStay : copy.inRoomDiningMenu}</span>
                  <h2>{getSectionTitle(activeCategory, copy)}</h2>
                </div>
                <strong>{visibleItems.length} {copy.available}</strong>
              </div>

              {visibleItems.length === 0 ? (
                <div className="food-menu-empty">
                  <FoodIcon name="cloche" size={38} />
                  <h3>{copy.noItemsTitle}</h3>
                  <p>{copy.noItemsBody}</p>
                </div>
              ) : (
                <div className="food-item-grid">
                  {visibleItems.map((item, index) => (
                    <MenuItemCard
                      key={item.id}
                      item={item}
                      featured={featuredIds.has(item.id)}
                      heroImageUrl={heroImageUrl}
                      copy={copy}
                      onAdd={handleAddItem}
                      priority={index < 3}
                    />
                  ))}
                </div>
              )}

              <section className="food-kitchen-story">
                <div
                  className="food-story-visual"
                  style={storyImageUrl
                    ? { backgroundImage: `linear-gradient(135deg, rgba(0,0,0,.3), rgba(0,0,0,.72)), url(${storyImageUrl})` }
                    : undefined}
                >
                  <span className="food-story-play"><FoodIcon name="play" size={24} /></span>
                </div>
                <div className="food-story-copy">
                  <span className="food-kicker">{copy.behindEveryOrder}</span>
                  <h3>{copy.kitchenCares}</h3>
                  <p>{copy.kitchenStoryBody}</p>
                  {videoUrl && (
                    <button
                      type="button"
                      onClick={() => window.open(videoUrl, '_blank', 'noopener,noreferrer')}
                    >
                      {copy.watchKitchenStory}
                    </button>
                  )}
                </div>
                <div className="food-trust-points">
                  <TrustPoint
                    icon="chef"
                    title={copy.freshlyPrepared}
                    text={copy.madeToOrder}
                  />
                  <TrustPoint
                    icon="shield"
                    title={copy.hygienicSecure}
                    text={copy.activeRoomSecure}
                  />
                  <TrustPoint
                    icon="clock"
                    title={copy.liveTracking}
                    text={copy.liveTrackingBody}
                  />
                </div>
              </section>
            </main>

            <aside className="food-cart-panel">
              <div className="food-cart-heading">
                <div>
                  <FoodIcon name="cart" />
                  <div><span>{copy.yourActiveOrder}</span><h2>{copy.yourCart}</h2></div>
                </div>
                <strong>{totals.quantity}</strong>
              </div>

              {cart.length === 0 ? (
                <div className="food-empty-cart">
                  <span><FoodIcon name="cloche" size={40} /></span>
                  <h3>{copy.cartEmpty}</h3>
                  <p>{copy.cartEmptyBody}</p>
                </div>
              ) : (
                <div className="food-cart-lines">
                  {cart.map((line) => {
                    const lineFinancials = calculateLineFinancials(line)
                    return (
                      <div key={line.key} className="food-cart-line">
                        <div className="food-cart-thumb">
                          <MenuItemImage item={line.item} fallbackImage={heroImageUrl} />
                        </div>
                        <div className="food-cart-line-copy">
                          <button
                            type="button"
                            className="food-remove-line"
                            onClick={() => removeLine(line.key)}
                            aria-label={`Remove ${line.item.item_name}`}
                          >
                            ×
                          </button>
                          <strong>{line.item.item_name}</strong>
                          {line.modifiers.length > 0 && (
                            <small>{line.modifiers.map((modifier) => modifier.name).join(', ')}</small>
                          )}
                          <div>
                            <div className="food-quantity">
                              <button type="button" onClick={() => changeQuantity(line.key, -1)}>−</button>
                              <span>{line.quantity}</span>
                              <button type="button" onClick={() => changeQuantity(line.key, 1)}>+</button>
                            </div>
                            <b>{money(lineFinancials.total, line.item.currency_code)}</b>
                          </div>
                        </div>
                      </div>
                    )
                  })}

                  <div className="food-totals">
                    <h3>{copy.total}</h3>
                    <div><span>{copy.itemSubtotal}</span><strong>{money(totals.subtotal)}</strong></div>
                    {totals.modifiers > 0 && (
                      <div><span>{copy.addOns}</span><strong>{money(totals.modifiers)}</strong></div>
                    )}
                    {totals.tax > 0 && (
                      <div><span>{copy.taxes}</span><strong>{money(totals.tax)}</strong></div>
                    )}
                    <div className="grand"><span>{copy.total}</span><strong>{money(totals.total)}</strong></div>
                  </div>

                  <div className="food-secure-note">
                    <FoodIcon name="shield" />
                    <span>{copy.interpolate('secureOrderFromRoom', { room: room.room_number || '—' })}</span>
                  </div>
                  <button className="food-submit" disabled={submitting} onClick={submitOrder}>
                    {submitting ? copy.sendingOrder : copy.placeSecureOrder} <span>→</span>
                  </button>
                  <button className="food-continue" type="button" onClick={scrollToMenu}>
                    {copy.continueShopping}
                  </button>
                </div>
              )}
            </aside>
          </div>

          <section className="food-order-history" id="food-orders">
            <div className="food-section-heading premium">
              <div><span>{copy.liveKitchenTracking}</span><h2>{copy.yourOrders}</h2></div>
              <strong>
                {localizedOrders.length} {localizedOrders.length === 1 ? copy.orderSingular : copy.orderPlural}
              </strong>
            </div>
            {localizedOrders.length === 0 ? (
              <div className="food-orders-empty">
                <FoodIcon name="receipt" size={36} />
                <p>{copy.noOrders}</p>
              </div>
            ) : (
              <div className="food-order-list">
                {localizedOrders.map((order) => (
                  <article key={order.id} className="food-order-card">
                    <div className="food-order-card-head">
                      <div>
                        <span>{copy.orderSingular} {String(order.id).slice(0, 8).toUpperCase()}</span>
                        <strong>{money(order.total_amount, order.currency_code)}</strong>
                      </div>
                      <StatusBadge status={order.order_status} copy={copy} />
                    </div>
                    <OrderProgress order={order} copy={copy} />
                    <div className="food-order-items">
                      {(order.food_order_items || []).map((item) => (
                        <div key={item.id || `${item.item_name}-${item.quantity}`}>
                          <span>{item.quantity} × {item.item_name}</span>
                          <small>{(item.modifiers || []).map((modifier) => modifier.name).join(', ')}</small>
                        </div>
                      ))}
                    </div>
                    {order.estimated_delivery_time
                      && !['delivered', 'cancelled'].includes(order.order_status) && (
                      <div className="food-eta">
                        <FoodIcon name="clock" /> {copy.estimatedDelivery}: {remaining(order.estimated_delivery_time, nowMs, copy)}
                      </div>
                    )}
                    {order.can_cancel && (
                      <button
                        className="food-cancel"
                        disabled={busyId === order.id}
                        onClick={() => cancelOrder(order)}
                      >
                        {copy.cancelOrder}
                      </button>
                    )}
                  </article>
                ))}
              </div>
            )}
          </section>

          {localizedNotifications.length > 0 && (
            <section className="food-notifications">
              <div className="food-section-heading premium">
                <div><span>{copy.kitchenMessages}</span><h2>{copy.latestUpdates}</h2></div>
              </div>
              <div className="food-notification-grid">
                {localizedNotifications.slice(0, 4).map((notification) => (
                  <article key={notification.id}>
                    <FoodIcon name="bell" />
                    <div><strong>{notification.title}</strong><span>{notification.message}</span></div>
                  </article>
                ))}
              </div>
            </section>
          )}

          <footer className="food-footer">
            <div>
              <img src="/assets/stayqr-official-logo.png" alt="StayQR" />
              <span>{copy.secureGuestExperience}</span>
            </div>
            <span>{hotelName} · {copy.room} {room.room_number || '—'}</span>
          </footer>
        </div>
      </div>

      {selectedItem && (
        <div className="food-modal-backdrop" onMouseDown={() => setSelectedItem(null)}>
          <div className="food-modal" onMouseDown={(event) => event.stopPropagation()}>
            <button className="food-modal-close" onClick={() => setSelectedItem(null)}>×</button>
            <div className="food-modal-hero">
              <MenuItemImage item={selectedItem} fallbackImage={heroImageUrl} priority />
              <div>
                <span className="food-kicker">{copy.customiseOrder}</span>
                <h2>{selectedItem.item_name}</h2>
                <p>{selectedItem.description || copy.preparedFresh}</p>
              </div>
            </div>
            {(selectedItem.modifier_groups || []).map((group) => (
              <fieldset key={group.id}>
                <legend>
                  {group.name}
                  <small>
                    {group.is_required ? copy.required : copy.optional} · {copy.choose} {group.min_selections}-{group.max_selections} {Number(group.max_selections) === 1 ? copy.optionSingular : copy.optionPlural}
                  </small>
                </legend>
                {(group.modifiers || []).map((modifier) => {
                  const checked = (selectedModifiers[group.id] || []).includes(modifier.id)
                  return (
                    <label key={modifier.id} className={checked ? 'selected' : ''}>
                      <input
                        type={group.max_selections === 1 ? 'radio' : 'checkbox'}
                        name={group.id}
                        checked={checked}
                        onChange={() => toggleModifier(group, modifier)}
                      />
                      <span>{modifier.name}</span>
                      <strong>
                        {Number(modifier.price_delta || 0) > 0
                          ? `+${money(modifier.price_delta)}`
                          : copy.includedPrice}
                      </strong>
                    </label>
                  )
                })}
              </fieldset>
            ))}
            <button className="food-submit" onClick={addConfiguredItem}>
              {copy.addToCart}
              <span>{selectedFinancials ? money(selectedFinancials.total, selectedItem.currency_code) : ''}</span>
            </button>
          </div>
        </div>
      )}

      {totals.quantity > 0 && (
        <button
          className="food-mobile-cart"
          type="button"
          onClick={() => document.querySelector('.food-cart-panel')?.scrollIntoView({ behavior: 'smooth' })}
        >
          <span>{totals.quantity} {totals.quantity === 1 ? copy.orderSingular : copy.orderPlural}</span>
          <strong>{money(totals.total)} · {copy.yourCart}</strong>
        </button>
      )}

      {toast && <div className="food-toast" role="status">{toast}</div>}
    </div>
  )
}

function CategoryButton({ label, icon, active, onClick }) {
  return (
    <button type="button" className={active ? 'active' : ''} onClick={onClick}>
      <FoodIcon name={icon} /><span>{label}</span>
    </button>
  )
}

function TrustPoint({ icon, title, text }) {
  return (
    <div>
      <span><FoodIcon name={icon} /></span>
      <div><strong>{title}</strong><p>{text}</p></div>
    </div>
  )
}

function MenuItemImage({ item, fallbackImage = '', priority = false }) {
  const [failed, setFailed] = useState(false)
  const source = !failed ? (item?.image_url || fallbackImage) : ''
  if (source) {
    return (
      <img
        src={source}
        alt={item?.item_name || 'Hotel menu item'}
        loading={priority ? 'eager' : 'lazy'}
        fetchPriority={priority ? 'high' : 'auto'}
        decoding="async"
        onError={() => setFailed(true)}
      />
    )
  }
  return (
    <span className="food-image-fallback">
      <FoodIcon name={getCategoryIcon(item?.category)} size={42} />
    </span>
  )
}

function StatusBadge({ status, copy }) {
  return (
    <span className={`food-status food-status-${status}`}>
      {localizeStatus(status, copy)}
    </span>
  )
}

function OrderProgress({ order, copy }) {
  if (order.order_status === 'cancelled') {
    return <div className="food-order-cancelled">{copy.thisOrderCancelled}</div>
  }
  const index = STATUS_FLOW.indexOf(order.order_status)
  return (
    <div className="food-progress">
      {STATUS_FLOW.map((status, statusIndex) => (
        <div key={status} className={statusIndex <= index ? 'complete' : ''}>
          <span /> <small>{localizeStatus(status, copy)}</small>
        </div>
      ))}
    </div>
  )
}

function FoodIcon({ name = 'sparkles', size = 18 }) {
  const props = {
    width: size,
    height: size,
    viewBox: '0 0 24 24',
    fill: 'none',
    stroke: 'currentColor',
    strokeWidth: 1.8,
    strokeLinecap: 'round',
    strokeLinejoin: 'round',
    'aria-hidden': true,
  }
  const paths = {
    grid: <><rect x="3" y="3" width="7" height="7" rx="2" /><rect x="14" y="3" width="7" height="7" rx="2" /><rect x="3" y="14" width="7" height="7" rx="2" /><rect x="14" y="14" width="7" height="7" rx="2" /></>,
    star: <path d="m12 3 2.8 5.7 6.2.9-4.5 4.4 1.1 6.2-5.6-2.9-5.6 2.9 1.1-6.2L3 9.6l6.2-.9L12 3z" />,
    sun: <><circle cx="12" cy="12" r="4" /><path d="M12 2v2M12 20v2M4.93 4.93l1.42 1.42M17.66 17.66l1.41 1.41M2 12h2M20 12h2M4.93 19.07l1.42-1.42M17.66 6.34l1.41-1.41" /></>,
    cup: <><path d="M5 8h11v6a5 5 0 0 1-5 5h-1a5 5 0 0 1-5-5V8z" /><path d="M16 10h2a3 3 0 0 1 0 6h-2M7 3v2M11 3v2M15 3v2" /></>,
    utensils: <><path d="M7 3v7M4 3v4a3 3 0 0 0 6 0V3M7 10v11M16 3v18M16 3c3 2 4 5 4 8h-4" /></>,
    bowl: <><path d="M4 11h16a8 8 0 0 1-16 0z" /><path d="M8 4c0 2 2 2 2 4M13 3c0 2 2 2 2 4" /></>,
    plate: <><circle cx="12" cy="12" r="9" /><circle cx="12" cy="12" r="5" /></>,
    sparkles: <><path d="m12 3 1.2 3.2L16.5 7.5l-3.3 1.3L12 12l-1.2-3.2-3.3-1.3 3.3-1.3L12 3zM18.5 13l.8 2.2 2.2.8-2.2.8-.8 2.2-.8-2.2-2.2-.8 2.2-.8.8-2.2z" /></>,
    guide: <><path d="M4 5a3 3 0 0 1 3-3h13v17H7a3 3 0 0 0-3 3V5z" /><path d="M7 2v17" /></>,
    bell: <><path d="M18 8a6 6 0 0 0-12 0c0 7-3 7-3 9h18c0-2-3-2-3-9" /><path d="M10 21h4" /></>,
    receipt: <><path d="M6 3h12v18l-3-2-3 2-3-2-3 2V3z" /><path d="M9 8h6M9 12h6" /></>,
    room: <><rect x="4" y="4" width="16" height="16" rx="2" /><path d="M8 8h3v3H8zM14 8h2M14 12h2M8 15h8" /></>,
    clock: <><circle cx="12" cy="12" r="9" /><path d="M12 7v5l3 2" /></>,
    shield: <><path d="M12 3 20 6v6c0 5-3.4 8-8 9-4.6-1-8-4-8-9V6l8-3z" /><path d="m9 12 2 2 4-4" /></>,
    chef: <><path d="M7 10a4 4 0 0 1 1-7 4 4 0 0 1 4 1 4 4 0 0 1 5 6v3H7v-3z" /><path d="M7 17h10M8 13v7M16 13v7" /></>,
    cloche: <><path d="M4 15h16M6 15a6 6 0 0 1 12 0M12 7V5M3 19h18" /></>,
    gift: <><rect x="3" y="9" width="18" height="12" rx="2" /><path d="M12 9v12M3 13h18M12 9H8a2.5 2.5 0 1 1 2.5-2.5L12 9zm0 0h4a2.5 2.5 0 1 0-2.5-2.5L12 9z" /></>,
    cart: <><circle cx="9" cy="20" r="1" /><circle cx="18" cy="20" r="1" /><path d="M3 4h2l2.5 11h10l2-8H6" /></>,
    play: <><circle cx="12" cy="12" r="9" /><path d="m10 8 6 4-6 4V8z" /></>,
  }
  return <svg {...props}>{paths[name] || paths.sparkles}</svg>
}

function calculateLineFinancials(line) {
  const quantity = Number(line?.quantity || 0)
  const base = Number(line?.item?.price || 0) * quantity
  const modifiers = (line?.modifiers || []).reduce(
    (sum, modifier) => sum + Number(modifier.price_delta || 0) * quantity,
    0
  )
  const rate = Number(line?.item?.tax_rate || 0)
  const inclusive = Boolean(line?.item?.tax_inclusive)
  const grossBeforeTax = base + modifiers
  const tax = inclusive
    ? rate > 0 ? grossBeforeTax - grossBeforeTax / (1 + rate / 100) : 0
    : grossBeforeTax * rate / 100
  return {
    subtotal: inclusive && rate > 0 ? base / (1 + rate / 100) : base,
    modifiers: inclusive && rate > 0 ? modifiers / (1 + rate / 100) : modifiers,
    tax,
    total: inclusive ? grossBeforeTax : grossBeforeTax + tax,
  }
}

function getCategoryIcon(category) {
  const key = String(category || '').trim().toLowerCase()
  return CATEGORY_ICONS[key] || 'plate'
}

function getSectionTitle(activeCategory, copy) {
  if (activeCategory === 'featured') return copy.featuredForYou
  if (activeCategory === 'all') return copy.exploreMenu
  return activeCategory
}

function getInitials(value) {
  const words = String(value || '').trim().split(/\s+/).filter(Boolean)
  return words.slice(0, 2).map((word) => word.charAt(0).toUpperCase()).join('') || 'H'
}

function safeExternalUrl(value) {
  try {
    const url = new URL(String(value || '').trim())
    return ['http:', 'https:'].includes(url.protocol) ? url.toString() : ''
  } catch {
    return ''
  }
}

function money(value, currency = 'INR') {
  return new Intl.NumberFormat('en-IN', {
    style: 'currency',
    currency: currency || 'INR',
    maximumFractionDigits: 2,
  }).format(Number(value || 0))
}

function remaining(iso, nowMs, copy) {
  const difference = new Date(iso).getTime() - nowMs
  if (difference <= 0) return copy.dueNow
  const minutes = Math.ceil(difference / 60000)
  return `${minutes} ${minutes === 1 ? copy.minuteSingular : copy.minutePlural}`
}
