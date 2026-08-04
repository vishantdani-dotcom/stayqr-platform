import { useCallback, useEffect, useMemo, useRef, useState } from 'react'
import { getCurrentHotel } from '../../lib/currentHotel'
import { supabase } from '../../lib/supabase'
import {
  GUEST_GUIDE_LOCALES,
  getGuestGuideBuilder,
  getGuestGuideMediaUrl,
  normalizeGuestGuideBuilderPayload,
  publishGuestGuide,
  saveGuestGuideMedia,
  saveGuestGuideSettings,
  uploadGuestGuideMediaFile,
} from '../../lib/guestGuideBuilder'
import { getTranslationSeed } from '../../lib/diningI18n'
import './MenuManagement.css'

const EMPTY_ITEM = {
  item_name: '',
  category_id: '',
  price: '',
  description: '',
  image_url: '',
  tax_rate: '0',
  tax_inclusive: false,
  preparation_minutes: '20',
  is_available: true,
}

const EMPTY_OFFER = {
  enabled: true,
  badge: 'Limited Offer',
  title: 'Make Your Stay More Rewarding',
  description: 'Ask reception about today’s guest benefit.',
  button_label: 'View Offer',
  action_type: 'section',
  action_value: 'food-menu',
  image_media_id: '',
}

export default function MenuManagement() {
  const [hotel, setHotel] = useState(null)
  const [categories, setCategories] = useState([])
  const [items, setItems] = useState([])
  const [groups, setGroups] = useState([])
  const [modifiers, setModifiers] = useState([])
  const [builder, setBuilder] = useState(() => normalizeGuestGuideBuilderPayload({}))
  const [selectedItemId, setSelectedItemId] = useState('')
  const [editingItemId, setEditingItemId] = useState('')
  const [itemForm, setItemForm] = useState(EMPTY_ITEM)
  const [categoryName, setCategoryName] = useState('')
  const [offerLocale, setOfferLocale] = useState('en')
  const [offerForm, setOfferForm] = useState(EMPTY_OFFER)
  const [offerFile, setOfferFile] = useState(null)
  const [translationLocale, setTranslationLocale] = useState('hi')
  const [translationDraft, setTranslationDraft] = useState({
    categories: {},
    items: {},
    groups: {},
    modifiers: {},
  })
  const [loading, setLoading] = useState(true)
  const [saving, setSaving] = useState(false)
  const [uploadingImage, setUploadingImage] = useState(false)
  const [uploadingOffer, setUploadingOffer] = useState(false)
  const [toast, setToast] = useState('')
  const [error, setError] = useState('')
  const modifierGroupLockRef = useRef(false)
  const modifierLockRef = useRef(false)
  const toastTimerRef = useRef(null)

  const showToast = useCallback((message) => {
    setToast(String(message || ''))
    window.clearTimeout(toastTimerRef.current)
    toastTimerRef.current = window.setTimeout(() => setToast(''), 3600)
  }, [])

  useEffect(
    () => () => window.clearTimeout(toastTimerRef.current),
    []
  )

  const syncOffer = useCallback((nextBuilder, locale = offerLocale) => {
    const settings = nextBuilder?.settings || {}
    const offer = settings?.branding?.offer || {}
    const translated = offer?.translations?.[locale] || {}
    setOfferForm({
      enabled: offer.enabled !== false,
      badge: translated.badge || offer.badge || EMPTY_OFFER.badge,
      title: translated.title || offer.title || EMPTY_OFFER.title,
      description: translated.description || offer.description || EMPTY_OFFER.description,
      button_label: translated.button_label || offer.button_label || EMPTY_OFFER.button_label,
      action_type: offer.action_type || EMPTY_OFFER.action_type,
      action_value: offer.action_value || EMPTY_OFFER.action_value,
      image_media_id: offer.image_media_id || '',
    })
  }, [offerLocale])

  const loadData = useCallback(async (hotelId) => {
    const [categoryResult, itemResult, groupResult, modifierResult, builderResult] = await Promise.all([
      supabase.from('menu_categories').select('*').eq('hotel_id', hotelId).order('sort_order'),
      supabase.from('menu_items').select('*').eq('hotel_id', hotelId).order('sort_order').order('item_name'),
      supabase.from('menu_item_modifier_groups').select('*').eq('hotel_id', hotelId).order('sort_order'),
      supabase.from('menu_item_modifiers').select('*').eq('hotel_id', hotelId).order('sort_order'),
      getGuestGuideBuilder(hotelId),
    ])
    const firstError = categoryResult.error || itemResult.error || groupResult.error || modifierResult.error
    if (firstError) throw firstError

    const nextCategories = categoryResult.data || []
    const nextItems = itemResult.data || []
    const nextGroups = groupResult.data || []
    const nextModifiers = modifierResult.data || []
    const nextBuilder = normalizeGuestGuideBuilderPayload(builderResult)

    setCategories(nextCategories)
    setItems(nextItems)
    setGroups(nextGroups)
    setModifiers(nextModifiers)
    setBuilder(nextBuilder)
    syncOffer(nextBuilder)
    setTranslationDraft(buildTranslationDraft(
      translationLocale,
      nextCategories,
      nextItems,
      nextGroups,
      nextModifiers
    ))
    setItemForm((current) => ({
      ...current,
      category_id: current.category_id || nextCategories[0]?.id || '',
    }))
    setSelectedItemId((current) => current || nextItems[0]?.id || '')
  }, [syncOffer, translationLocale])

  const initialize = useCallback(async () => {
    setLoading(true)
    setError('')
    try {
      const selectedHotel = await getCurrentHotel()
      if (!selectedHotel) throw new Error('No hotel is selected.')
      setHotel(selectedHotel)
      await loadData(selectedHotel.id)
    } catch (loadError) {
      setError(loadError.message || 'Unable to load menu management.')
    } finally {
      setLoading(false)
    }
  }, [loadData])

  useEffect(() => {
    void initialize()
  }, [initialize])

  useEffect(() => {
    setTranslationDraft(buildTranslationDraft(
      translationLocale,
      categories,
      items,
      groups,
      modifiers
    ))
  }, [categories, groups, items, modifiers, translationLocale])

  useEffect(() => {
    syncOffer(builder, offerLocale)
  }, [builder, offerLocale, syncOffer])

  const selectedItem = items.find((item) => item.id === selectedItemId) || null
  const selectedGroups = useMemo(
    () => groups.filter((group) => group.menu_item_id === selectedItemId),
    [groups, selectedItemId]
  )
  const activeItems = items.filter((item) => !item.archived_at)
  const offerMedia = useMemo(() => {
    const idMatch = builder.media.find((media) => media.id === offerForm.image_media_id)
    return idMatch
      || builder.media.find((media) => media.media_key === 'dining_offer_banner' && media.is_active !== false)
      || builder.media.find((media) => media.media_key === 'offer_banner' && media.is_active !== false)
      || null
  }, [builder.media, offerForm.image_media_id])
  const offerImageUrl = offerMedia?.object_path
    ? getGuestGuideMediaUrl(offerMedia.object_path)
    : ''

  function resetItemForm() {
    setEditingItemId('')
    setItemForm({ ...EMPTY_ITEM, category_id: categories[0]?.id || '' })
  }

  function editItem(item) {
    setEditingItemId(item.id)
    setItemForm({
      item_name: item.item_name || '',
      category_id: item.category_id || '',
      price: String(item.price ?? ''),
      description: item.description || '',
      image_url: item.image_url || '',
      tax_rate: String(item.tax_rate ?? 0),
      tax_inclusive: Boolean(item.tax_inclusive),
      preparation_minutes: String(item.preparation_minutes ?? 20),
      is_available: item.is_available !== false,
    })
    document.getElementById('menu-item-editor')?.scrollIntoView({ behavior: 'smooth', block: 'start' })
  }

  async function saveItem(event) {
    event.preventDefault()
    const category = categories.find((entry) => entry.id === itemForm.category_id)
    if (!itemForm.item_name.trim() || !category || itemForm.price === '') {
      setError('Enter the item name, category and price.')
      return
    }
    setSaving(true)
    setError('')
    try {
      const payload = {
        hotel_id: hotel.id,
        item_name: itemForm.item_name.trim(),
        category_id: category.id,
        category: category.name,
        price: Number(itemForm.price),
        description: itemForm.description.trim() || null,
        image_url: itemForm.image_url.trim() || null,
        tax_rate: Number(itemForm.tax_rate || 0),
        tax_inclusive: itemForm.tax_inclusive,
        preparation_minutes: Number(itemForm.preparation_minutes || 20),
        is_available: itemForm.is_available,
      }
      if (editingItemId) {
        const { error: updateError } = await supabase
          .from('menu_items')
          .update(payload)
          .eq('hotel_id', hotel.id)
          .eq('id', editingItemId)
        if (updateError) throw updateError
      } else {
        const { error: insertError } = await supabase.from('menu_items').insert(payload)
        if (insertError) throw insertError
      }
      await loadData(hotel.id)
      resetItemForm()
      showToast(editingItemId ? 'Menu item updated.' : 'Menu item added.')
    } catch (saveError) {
      setError(saveError.message || 'Menu item could not be saved.')
    } finally {
      setSaving(false)
    }
  }

  async function uploadItemPhoto(event) {
    const file = event.target.files?.[0]
    event.target.value = ''
    if (!file || !hotel?.id || uploadingImage) return
    setUploadingImage(true)
    setError('')
    try {
      const uploaded = await uploadGuestGuideMediaFile({
        hotelId: hotel.id,
        file,
        scopeType: 'hotel',
        category: 'food',
      })
      setItemForm((current) => ({ ...current, image_url: uploaded.publicUrl }))
      showToast('Menu photo uploaded. Save the item to publish it.')
    } catch (uploadError) {
      setError(uploadError.message || 'Menu photo could not be uploaded.')
    } finally {
      setUploadingImage(false)
    }
  }

  async function saveOffer({ publish = false } = {}) {
    if (!hotel?.id || saving) return
    setSaving(true)
    setError('')
    try {
      const currentSettings = builder.settings || {}
      const currentBranding = currentSettings.branding || {}
      const currentOffer = currentBranding.offer || {}
      const translation = {
        badge: offerForm.badge.trim(),
        title: offerForm.title.trim(),
        description: offerForm.description.trim(),
        button_label: offerForm.button_label.trim(),
      }
      const nextOffer = {
        ...currentOffer,
        enabled: offerForm.enabled,
        action_type: offerForm.action_type,
        action_value: offerForm.action_value.trim(),
        image_media_id: offerForm.image_media_id || offerMedia?.id || '',
        translations: {
          ...(currentOffer.translations || {}),
          [offerLocale]: translation,
        },
      }
      if (offerLocale === 'en') Object.assign(nextOffer, translation)

      await saveGuestGuideSettings(hotel.id, {
        ...currentSettings,
        branding: {
          ...currentBranding,
          offer: nextOffer,
        },
      })
      if (publish) {
        await publishGuestGuide(hotel.id, 'Premium dining offer updated from Menu Management')
      }
      await loadData(hotel.id)
      showToast(publish ? 'Dining offer saved and published.' : 'Dining offer saved to draft.')
    } catch (saveError) {
      setError(saveError.message || 'Dining offer could not be saved.')
    } finally {
      setSaving(false)
    }
  }

  async function uploadOfferBanner() {
    if (!offerFile || !hotel?.id || uploadingOffer) return
    setUploadingOffer(true)
    setError('')
    try {
      const uploaded = await uploadGuestGuideMediaFile({
        hotelId: hotel.id,
        file: offerFile,
        scopeType: 'hotel',
        category: 'custom',
      })
      const saved = await saveGuestGuideMedia(hotel.id, {
        section_id: null,
        item_id: null,
        scope_type: 'hotel',
        room_type_id: null,
        room_id: null,
        media_key: 'dining_offer_banner',
        category: 'custom',
        object_path: uploaded.objectPath,
        mime_type: uploaded.mimeType,
        title: 'Dining offer banner',
        caption: offerForm.title || 'Dining offer',
        alt_text: `${hotel.hotel_name || hotel.name || 'Hotel'} dining offer`,
        locale: null,
        sort_order: 15,
        is_active: true,
        metadata: { surface: 'premium_dining' },
      })
      const mediaId = saved?.id || saved?.media?.id || ''
      setOfferForm((current) => ({ ...current, image_media_id: mediaId }))
      setOfferFile(null)
      const nextBuilder = normalizeGuestGuideBuilderPayload(await getGuestGuideBuilder(hotel.id))
      setBuilder(nextBuilder)
      const resolved = nextBuilder.media.find((media) => media.media_key === 'dining_offer_banner' && media.is_active !== false)
      if (resolved?.id) {
        setOfferForm((current) => ({ ...current, image_media_id: resolved.id }))
      }
      showToast('Offer banner uploaded. Save or publish the offer now.')
    } catch (uploadError) {
      setError(uploadError.message || 'Offer banner could not be uploaded.')
    } finally {
      setUploadingOffer(false)
    }
  }

  async function saveTranslations() {
    if (!hotel?.id || saving) return
    setSaving(true)
    setError('')
    try {
      const payload = {
        categories: categories.map((category) => ({
          id: category.id,
          name: translationDraft.categories[category.id]?.name || '',
        })),
        items: activeItems.map((item) => ({
          id: item.id,
          item_name: translationDraft.items[item.id]?.item_name || '',
          description: translationDraft.items[item.id]?.description || '',
        })),
        groups: groups.map((group) => ({
          id: group.id,
          name: translationDraft.groups[group.id]?.name || '',
        })),
        modifiers: modifiers.map((modifier) => ({
          id: modifier.id,
          name: translationDraft.modifiers[modifier.id]?.name || '',
        })),
      }
      const { error: translationError } = await supabase.rpc('save_menu_locale_translations', {
        p_hotel_id: hotel.id,
        p_locale: translationLocale,
        p_payload: payload,
      })
      if (translationError) throw translationError
      await loadData(hotel.id)
      showToast(`${localeLabel(translationLocale)} menu translations saved.`)
    } catch (translationError) {
      setError(translationError.message || 'Menu translations could not be saved.')
    } finally {
      setSaving(false)
    }
  }

  async function addCategory(event) {
    event.preventDefault()
    const name = categoryName.trim()
    if (!name) return
    setSaving(true)
    setError('')
    try {
      const { error: insertError } = await supabase.from('menu_categories').insert({
        hotel_id: hotel.id,
        name,
        code: normalizeCode(name),
        is_active: true,
        sort_order: categories.length * 10 + 10,
      })
      if (insertError) throw insertError
      setCategoryName('')
      await loadData(hotel.id)
      showToast('Category added.')
    } catch (categoryError) {
      setError(categoryError.message || 'Category could not be added.')
    } finally {
      setSaving(false)
    }
  }

  async function updateCategory(category, patch) {
    setSaving(true)
    setError('')
    try {
      const { error: updateError } = await supabase
        .from('menu_categories')
        .update(patch)
        .eq('hotel_id', hotel.id)
        .eq('id', category.id)
      if (updateError) throw updateError
      await loadData(hotel.id)
      showToast(`${category.name} service settings saved.`)
    } catch (updateError) {
      setError(updateError.message || 'Category could not be updated.')
    } finally {
      setSaving(false)
    }
  }

  async function toggleItem(item) {
    setSaving(true)
    setError('')
    try {
      const { error: updateError } = await supabase
        .from('menu_items')
        .update({ is_available: !item.is_available })
        .eq('hotel_id', hotel.id)
        .eq('id', item.id)
      if (updateError) throw updateError
      await loadData(hotel.id)
      showToast(`${item.item_name} is now ${item.is_available ? 'unavailable' : 'available'}.`)
    } catch (updateError) {
      setError(updateError.message || 'Availability could not be changed.')
    } finally {
      setSaving(false)
    }
  }

  async function archiveItem(item) {
    if (!window.confirm(`Archive ${item.item_name}? Existing order snapshots remain unchanged.`)) return
    setSaving(true)
    setError('')
    try {
      const { error: updateError } = await supabase
        .from('menu_items')
        .update({ archived_at: new Date().toISOString(), is_available: false })
        .eq('hotel_id', hotel.id)
        .eq('id', item.id)
      if (updateError) throw updateError
      await loadData(hotel.id)
      showToast('Menu item archived.')
    } catch (archiveError) {
      setError(archiveError.message || 'Menu item could not be archived.')
    } finally {
      setSaving(false)
    }
  }

  async function addModifierGroup(event) {
    event.preventDefault()
    if (!selectedItemId || modifierGroupLockRef.current) return
    const formElement = event.currentTarget
    const form = new FormData(formElement)
    const name = String(form.get('name') || '').trim()
    if (!name) return
    const normalizedName = name.toLocaleLowerCase()
    const existingGroup = selectedGroups.find(
      (group) => String(group.name || '').trim().toLocaleLowerCase() === normalizedName
    )
    if (existingGroup) {
      setError('')
      formElement.reset()
      showToast(`${existingGroup.name} already exists and is ready below.`)
      return
    }
    modifierGroupLockRef.current = true
    setSaving(true)
    setError('')
    try {
      const min = Number(form.get('min') || 0)
      const max = Number(form.get('max') || 1)
      const { error: insertError } = await supabase.from('menu_item_modifier_groups').insert({
        hotel_id: hotel.id,
        menu_item_id: selectedItemId,
        name,
        min_selections: min,
        max_selections: max,
        is_required: min > 0,
        is_active: true,
        sort_order: selectedGroups.length * 10 + 10,
      })
      if (insertError && insertError.code !== '23505') throw insertError
      formElement.reset()
      await loadData(hotel.id)
      showToast(insertError ? 'This modifier group already exists and has been loaded.' : 'Modifier group added.')
    } catch (groupError) {
      setError(groupError.message || 'Modifier group could not be added.')
    } finally {
      modifierGroupLockRef.current = false
      setSaving(false)
    }
  }

  async function addModifier(event, group) {
    event.preventDefault()
    if (modifierLockRef.current) return
    const formElement = event.currentTarget
    const form = new FormData(formElement)
    const name = String(form.get('name') || '').trim()
    if (!name) return
    const existingModifier = modifiers.find(
      (modifier) => modifier.modifier_group_id === group.id
        && String(modifier.name || '').trim().toLocaleLowerCase() === name.toLocaleLowerCase()
    )
    if (existingModifier) {
      formElement.reset()
      setError('')
      showToast(`${existingModifier.name} already exists in ${group.name}.`)
      return
    }
    modifierLockRef.current = true
    setSaving(true)
    setError('')
    try {
      const { error: insertError } = await supabase.from('menu_item_modifiers').insert({
        hotel_id: hotel.id,
        modifier_group_id: group.id,
        name,
        price_delta: Number(form.get('price_delta') || 0),
        is_available: true,
        sort_order: modifiers.filter((entry) => entry.modifier_group_id === group.id).length * 10 + 10,
      })
      if (insertError && insertError.code !== '23505') throw insertError
      formElement.reset()
      await loadData(hotel.id)
      showToast(insertError ? 'This add-on already exists and has been loaded.' : 'Add-on added.')
    } catch (modifierError) {
      setError(modifierError.message || 'Add-on could not be added.')
    } finally {
      modifierLockRef.current = false
      setSaving(false)
    }
  }

  async function toggleModifier(modifier) {
    setSaving(true)
    setError('')
    try {
      const { error: updateError } = await supabase
        .from('menu_item_modifiers')
        .update({ is_available: !modifier.is_available })
        .eq('hotel_id', hotel.id)
        .eq('id', modifier.id)
      if (updateError) throw updateError
      await loadData(hotel.id)
      showToast('Add-on availability updated.')
    } catch (updateError) {
      setError(updateError.message || 'Add-on availability could not be updated.')
    } finally {
      setSaving(false)
    }
  }

  if (loading) return <div className="menu15-loading">Loading menu configuration…</div>

  return (
    <div className="menu15-page">
      <header className="menu15-header">
        <div>
          <span>Premium Dining · Language & Offer Studio</span>
          <h1>Menu Management</h1>
          <p>{hotel?.hotel_name || hotel?.name} · Food photos, full-language menu, offer banner, service windows, tax and modifiers.</p>
        </div>
        <button onClick={() => loadData(hotel.id)}>Refresh</button>
      </header>

      {error && <div className="menu15-error">{error}<button onClick={() => setError('')}>×</button></div>}

      <section className="menu15-experience-grid">
        <article className="menu15-panel menu15-offer-studio">
          <div className="menu15-section-title">
            <div><span>Guest dining promotion</span><h2>Dining Offer & Banner</h2></div>
            <label className="menu15-inline-check"><input type="checkbox" checked={offerForm.enabled} onChange={(event) => setOfferForm((current) => ({ ...current, enabled: event.target.checked }))} />Show offer</label>
          </div>
          <div className="menu15-offer-preview" style={offerImageUrl ? { backgroundImage: `linear-gradient(90deg, rgba(5,5,5,.92), rgba(5,5,5,.5)), url(${offerImageUrl})` } : undefined}>
            <span>{offerForm.badge}</span>
            <h3>{offerForm.title}</h3>
            <p>{offerForm.description}</p>
            <button type="button">{offerForm.button_label || 'View Offer'} →</button>
          </div>
          <div className="menu15-form-grid offer-fields">
            <label>Offer language<select value={offerLocale} onChange={(event) => setOfferLocale(event.target.value)}>{GUEST_GUIDE_LOCALES.map((entry) => <option key={entry.code} value={entry.code}>{entry.nativeName}</option>)}</select></label>
            <label>Badge<input value={offerForm.badge} onChange={(event) => setOfferForm((current) => ({ ...current, badge: event.target.value }))} /></label>
            <label>Title<input value={offerForm.title} onChange={(event) => setOfferForm((current) => ({ ...current, title: event.target.value }))} /></label>
            <label>Button label<input value={offerForm.button_label} onChange={(event) => setOfferForm((current) => ({ ...current, button_label: event.target.value }))} /></label>
            <label className="wide">Description<textarea value={offerForm.description} onChange={(event) => setOfferForm((current) => ({ ...current, description: event.target.value }))} /></label>
            <label>Button action<select value={offerForm.action_type} onChange={(event) => setOfferForm((current) => ({ ...current, action_type: event.target.value }))}><option value="section">Scroll to menu</option><option value="url">Open website/offer URL</option><option value="call">Call reception</option><option value="whatsapp">Open WhatsApp</option><option value="guest_guide">Back to guest guide</option><option value="orders">View my orders</option></select></label>
            <label>Action value<input value={offerForm.action_value} onChange={(event) => setOfferForm((current) => ({ ...current, action_value: event.target.value }))} placeholder="URL, number or section" /></label>
          </div>
          <div className="menu15-banner-upload">
            <div><strong>Upload offer banner</strong><p>Use a wide JPG, PNG or WebP. Recommended 1600 × 450 px, under 8 MB.</p></div>
            <input type="file" accept="image/jpeg,image/png,image/webp" onChange={(event) => setOfferFile(event.target.files?.[0] || null)} />
            <button type="button" disabled={!offerFile || uploadingOffer} onClick={() => void uploadOfferBanner()}>{uploadingOffer ? 'Uploading…' : 'Upload banner'}</button>
          </div>
          <div className="menu15-action-row"><button type="button" onClick={() => void saveOffer()} disabled={saving}>Save draft</button><button type="button" className="menu15-primary compact" onClick={() => void saveOffer({ publish: true })} disabled={saving}>Save & publish</button></div>
        </article>

        <article className="menu15-panel menu15-language-studio">
          <div className="menu15-section-title"><div><span>12 launch languages · Urdu excluded</span><h2>Menu Language Studio</h2></div><select value={translationLocale} onChange={(event) => setTranslationLocale(event.target.value)}>{GUEST_GUIDE_LOCALES.filter((entry) => entry.code !== 'en').map((entry) => <option key={entry.code} value={entry.code}>{entry.nativeName}</option>)}</select></div>
          <p className="menu15-help">Translate category names, food names, descriptions and add-ons. The signed guest menu changes completely with the selected guest-guide language.</p>
          <div className="menu15-translation-scroll">
            <TranslationGroup title="Categories">{categories.map((category) => <label key={category.id}><span>{category.name}</span><input value={translationDraft.categories[category.id]?.name || ''} onChange={(event) => updateTranslation(setTranslationDraft, 'categories', category.id, 'name', event.target.value)} /></label>)}</TranslationGroup>
            <TranslationGroup title="Menu items">{activeItems.map((item) => <div className="menu15-translation-item" key={item.id}><strong>{item.item_name}</strong><input value={translationDraft.items[item.id]?.item_name || ''} onChange={(event) => updateTranslation(setTranslationDraft, 'items', item.id, 'item_name', event.target.value)} /><textarea value={translationDraft.items[item.id]?.description || ''} onChange={(event) => updateTranslation(setTranslationDraft, 'items', item.id, 'description', event.target.value)} /></div>)}</TranslationGroup>
            {groups.length > 0 && <TranslationGroup title="Modifier groups">{groups.map((group) => <label key={group.id}><span>{group.name}</span><input value={translationDraft.groups[group.id]?.name || ''} onChange={(event) => updateTranslation(setTranslationDraft, 'groups', group.id, 'name', event.target.value)} /></label>)}</TranslationGroup>}
            {modifiers.length > 0 && <TranslationGroup title="Add-ons">{modifiers.map((modifier) => <label key={modifier.id}><span>{modifier.name}</span><input value={translationDraft.modifiers[modifier.id]?.name || ''} onChange={(event) => updateTranslation(setTranslationDraft, 'modifiers', modifier.id, 'name', event.target.value)} /></label>)}</TranslationGroup>}
          </div>
          <button type="button" className="menu15-primary" disabled={saving} onClick={() => void saveTranslations()}>Save {localeLabel(translationLocale)} translations</button>
        </article>
      </section>

      <section className="menu15-metrics"><Metric label="Categories" value={categories.length} /><Metric label="Active items" value={activeItems.filter((item) => item.is_available).length} /><Metric label="Unavailable" value={activeItems.filter((item) => !item.is_available).length} /><Metric label="Modifier groups" value={groups.length} /></section>

      <section className="menu15-top-grid" id="menu-item-editor">
        <form className="menu15-panel" onSubmit={saveItem}>
          <div className="menu15-section-title"><h2>{editingItemId ? 'Edit menu item' : 'Add menu item'}</h2>{editingItemId && <button type="button" onClick={resetItemForm}>Cancel edit</button>}</div>
          <div className="menu15-form-grid"><label>Item name<input value={itemForm.item_name} onChange={(event) => setItemForm((current) => ({ ...current, item_name: event.target.value }))} /></label><label>Category<select value={itemForm.category_id} onChange={(event) => setItemForm((current) => ({ ...current, category_id: event.target.value }))}><option value="">Select</option>{categories.map((category) => <option key={category.id} value={category.id}>{category.name}</option>)}</select></label><label>Base price<input type="number" min="0" step="0.01" value={itemForm.price} onChange={(event) => setItemForm((current) => ({ ...current, price: event.target.value }))} /></label><label>Tax rate %<input type="number" min="0" max="100" step="0.01" value={itemForm.tax_rate} onChange={(event) => setItemForm((current) => ({ ...current, tax_rate: event.target.value }))} /></label><label>Preparation minutes<input type="number" min="0" max="1440" value={itemForm.preparation_minutes} onChange={(event) => setItemForm((current) => ({ ...current, preparation_minutes: event.target.value }))} /></label><label>Image URL<input value={itemForm.image_url} onChange={(event) => setItemForm((current) => ({ ...current, image_url: event.target.value }))} /></label></div>
          <div className="menu15-photo-uploader"><div className="menu15-photo-preview">{itemForm.image_url ? <img src={itemForm.image_url} alt="Menu item preview" /> : <span>Food photo preview</span>}</div><div><strong>Upload a professional food photo</strong><p>JPG, PNG or WebP up to 8 MB. The guest menu uses this image automatically.</p><label className="menu15-upload-button">{uploadingImage ? 'Uploading…' : 'Choose photo'}<input type="file" accept="image/jpeg,image/png,image/webp" disabled={uploadingImage} onChange={uploadItemPhoto} /></label></div></div>
          <label>Description<textarea value={itemForm.description} onChange={(event) => setItemForm((current) => ({ ...current, description: event.target.value }))} /></label>
          <div className="menu15-checks"><label><input type="checkbox" checked={itemForm.tax_inclusive} onChange={(event) => setItemForm((current) => ({ ...current, tax_inclusive: event.target.checked }))} />Tax included in displayed price</label><label><input type="checkbox" checked={itemForm.is_available} onChange={(event) => setItemForm((current) => ({ ...current, is_available: event.target.checked }))} />Available to guests</label></div>
          <button className="menu15-primary" disabled={saving}>{editingItemId ? 'Save item' : 'Add item'}</button>
        </form>

        <div className="menu15-panel"><div className="menu15-section-title"><h2>Category service windows</h2></div><form className="menu15-add-category" onSubmit={addCategory}><input placeholder="New category" value={categoryName} onChange={(event) => setCategoryName(event.target.value)} /><button disabled={saving}>Add</button></form><div className="menu15-category-list">{categories.map((category) => <CategoryEditor key={category.id} category={category} saving={saving} onSave={(patch) => updateCategory(category, patch)} />)}</div></div>
      </section>

      <section className="menu15-panel menu15-table-panel"><div className="menu15-section-title"><h2>Guest-visible menu</h2><span>Select an item to configure add-ons.</span></div><div className="menu15-item-grid">{activeItems.map((item) => <article key={item.id} className={selectedItemId === item.id ? 'selected' : ''} onClick={() => setSelectedItemId(item.id)}>{item.image_url && <img className="menu15-item-thumb" src={item.image_url} alt="" loading="lazy" decoding="async" />}<div><span>{item.category}</span><h3>{item.item_name}</h3><p>{item.description || 'No description'}</p></div><strong>{money(item.price)}</strong><div className="menu15-item-meta"><span>{item.tax_rate}% tax {item.tax_inclusive ? 'included' : 'extra'}</span><span>{item.preparation_minutes} min</span><span>{item.is_available ? 'Available' : 'Unavailable'}</span></div><div className="menu15-item-actions"><button onClick={(event) => { event.stopPropagation(); editItem(item) }}>Edit</button><button onClick={(event) => { event.stopPropagation(); void toggleItem(item) }}>{item.is_available ? 'Disable' : 'Enable'}</button><button className="danger" onClick={(event) => { event.stopPropagation(); void archiveItem(item) }}>Archive</button></div></article>)}</div></section>

      <section className="menu15-panel"><div className="menu15-section-title"><div><h2>Modifiers & add-ons</h2><span>{selectedItem ? `Configuring ${selectedItem.item_name}` : 'Select a menu item above.'}</span></div></div>{selectedItem ? <><form className="menu15-group-form" onSubmit={addModifierGroup}><input name="name" placeholder="Group name, e.g. Choose spice level" /><input name="min" type="number" min="0" defaultValue="0" title="Minimum selections" /><input name="max" type="number" min="1" defaultValue="1" title="Maximum selections" /><button disabled={saving}>Add group</button></form><div className="menu15-modifier-grid">{selectedGroups.map((group) => <div key={group.id} className="menu15-modifier-group"><div><strong>{group.name}</strong><span>Choose {group.min_selections}-{group.max_selections}</span></div><form onSubmit={(event) => addModifier(event, group)}><input name="name" placeholder="Option name" /><input name="price_delta" type="number" min="0" step="0.01" placeholder="Add price" /><button disabled={saving}>Add</button></form>{modifiers.filter((modifier) => modifier.modifier_group_id === group.id).map((modifier) => <div className="menu15-modifier-row" key={modifier.id}><span>{modifier.name}</span><strong>{modifier.price_delta > 0 ? `+${money(modifier.price_delta)}` : 'Included'}</strong><button onClick={() => void toggleModifier(modifier)}>{modifier.is_available ? 'Disable' : 'Enable'}</button></div>)}</div>)}</div></> : <p className="menu15-muted">Select a menu item to add required or optional choices.</p>}</section>

      {toast && <div className="menu15-toast" role="status">{toast}</div>}
    </div>
  )
}

function TranslationGroup({ title, children }) {
  return <section className="menu15-translation-group"><h3>{title}</h3>{children}</section>
}

function CategoryEditor({ category, saving, onSave }) {
  const [form, setForm] = useState({
    service_start_time: category.service_start_time || '',
    service_end_time: category.service_end_time || '',
    is_active: category.is_active !== false,
  })
  return <div className="menu15-category-row"><div><strong>{category.name}</strong><span>{category.code}</span></div><input type="time" value={form.service_start_time} onChange={(event) => setForm((current) => ({ ...current, service_start_time: event.target.value }))} /><input type="time" value={form.service_end_time} onChange={(event) => setForm((current) => ({ ...current, service_end_time: event.target.value }))} /><label><input type="checkbox" checked={form.is_active} onChange={(event) => setForm((current) => ({ ...current, is_active: event.target.checked }))} />Active</label><button disabled={saving} onClick={() => onSave({ service_start_time: form.service_start_time || null, service_end_time: form.service_end_time || null, is_active: form.is_active })}>Save</button></div>
}

function Metric({ label, value }) {
  return <div className="menu15-metric"><span>{label}</span><strong>{value}</strong></div>
}

function buildTranslationDraft(locale, categories, items, groups, modifiers) {
  return {
    categories: Object.fromEntries(categories.map((entry) => [entry.id, getTranslationSeed(entry, locale, 'category')])),
    items: Object.fromEntries(items.filter((entry) => !entry.archived_at).map((entry) => [entry.id, getTranslationSeed(entry, locale, 'item')])),
    groups: Object.fromEntries(groups.map((entry) => [entry.id, getTranslationSeed(entry, locale, 'group')])),
    modifiers: Object.fromEntries(modifiers.map((entry) => [entry.id, getTranslationSeed(entry, locale, 'modifier')])),
  }
}

function updateTranslation(setter, collection, id, field, value) {
  setter((current) => ({
    ...current,
    [collection]: {
      ...current[collection],
      [id]: {
        ...(current[collection]?.[id] || {}),
        [field]: value,
      },
    },
  }))
}

function localeLabel(code) {
  const locale = GUEST_GUIDE_LOCALES.find((entry) => entry.code === code)
  return locale?.nativeName || code
}

function normalizeCode(value) {
  return String(value || '').trim().toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-+|-+$/g, '').slice(0, 48)
}

function money(value) {
  return new Intl.NumberFormat('en-IN', {
    style: 'currency',
    currency: 'INR',
    maximumFractionDigits: 2,
  }).format(Number(value || 0))
}
