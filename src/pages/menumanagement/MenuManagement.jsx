import { useCallback, useEffect, useState } from 'react'
import { getCurrentHotel } from '../../lib/currentHotel'
import { addMenuItem } from '../../lib/onboarding'
import { supabase } from '../../lib/supabase'

export default function MenuManagement() {
  const [currentHotel, setCurrentHotel] = useState(null)
  const [items, setItems] = useState([])
  const [categories, setCategories] = useState([])
  const [loading, setLoading] = useState(true)
  const [saving, setSaving] = useState(false)
  const [error, setError] = useState('')
  const [editingItem, setEditingItem] = useState(null)
  const [itemForm, setItemForm] = useState({
    item_name: '',
    category_id: '',
    price: '',
    description: '',
  })
  const [categoryName, setCategoryName] = useState('')

  const loadData = useCallback(async (hotelId) => {
    const [itemResult, categoryResult] = await Promise.all([
      supabase
        .from('menu_items')
        .select('*')
        .eq('hotel_id', hotelId)
        .order('item_name', { ascending: true }),
      supabase
        .from('menu_categories')
        .select('*')
        .eq('hotel_id', hotelId)
        .order('sort_order', { ascending: true }),
    ])

    const firstError = itemResult.error || categoryResult.error
    if (firstError) throw firstError

    setItems(itemResult.data || [])
    setCategories(categoryResult.data || [])
    setItemForm((current) => ({
      ...current,
      category_id:
        current.category_id || categoryResult.data?.[0]?.id || '',
    }))
    setLoading(false)
  }, [])

  const initialize = useCallback(async () => {
    setLoading(true)
    setError('')

    try {
      const hotel = await getCurrentHotel()
      if (!hotel) throw new Error('No hotel is selected.')
      setCurrentHotel(hotel)
      await loadData(hotel.id)
    } catch (loadError) {
      setError(loadError?.message || 'Menu configuration could not be loaded.')
      setLoading(false)
    }
  }, [loadData])

  useEffect(() => {
    initialize()
  }, [initialize])

  function resetItemForm() {
    setEditingItem(null)
    setItemForm({
      item_name: '',
      category_id: categories[0]?.id || '',
      price: '',
      description: '',
    })
  }

  function startEdit(item) {
    setEditingItem(item)
    setItemForm({
      item_name: item.item_name || '',
      category_id: item.category_id || '',
      price: String(item.price ?? ''),
      description: item.description || '',
    })
  }

  async function saveItem(event) {
    event.preventDefault()
    const category = categories.find(
      (entry) => entry.id === itemForm.category_id
    )

    if (!itemForm.item_name.trim() || itemForm.price === '' || !category) {
      setError('Enter an item name, category and price.')
      return
    }

    setSaving(true)
    setError('')

    try {
      if (editingItem) {
        const { error: updateError } = await supabase
          .from('menu_items')
          .update({
            item_name: itemForm.item_name.trim(),
            category_id: category.id,
            category: category.name,
            price: Number(itemForm.price),
            description: itemForm.description.trim() || null,
          })
          .eq('id', editingItem.id)
          .eq('hotel_id', currentHotel.id)

        if (updateError) throw updateError
      } else {
        await addMenuItem(currentHotel.id, {
          ...itemForm,
          category_name: category.name,
        })
      }

      resetItemForm()
      await loadData(currentHotel.id)
    } catch (saveError) {
      setError(saveError?.message || 'Menu item could not be saved.')
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
      const { error: insertError } = await supabase
        .from('menu_categories')
        .insert({
          hotel_id: currentHotel.id,
          name,
          code: normalizeCode(name),
          sort_order: categories.length * 10 + 10,
          is_active: true,
        })

      if (insertError) throw insertError
      setCategoryName('')
      await loadData(currentHotel.id)
    } catch (categoryError) {
      setError(categoryError?.message || 'Menu category could not be added.')
    } finally {
      setSaving(false)
    }
  }

  async function toggleAvailability(item) {
    setSaving(true)
    setError('')

    try {
      const { error: updateError } = await supabase
        .from('menu_items')
        .update({ is_available: !item.is_available })
        .eq('id', item.id)
        .eq('hotel_id', currentHotel.id)

      if (updateError) throw updateError
      await loadData(currentHotel.id)
    } catch (updateError) {
      setError(updateError?.message || 'Availability could not be updated.')
    } finally {
      setSaving(false)
    }
  }

  async function deleteItem(item) {
    if (!window.confirm(`Delete ${item.item_name}?`)) return

    setSaving(true)
    setError('')

    try {
      const { error: deleteError } = await supabase
        .from('menu_items')
        .delete()
        .eq('id', item.id)
        .eq('hotel_id', currentHotel.id)

      if (deleteError) throw deleteError
      await loadData(currentHotel.id)
    } catch (deleteError) {
      setError(deleteError?.message || 'Menu item could not be deleted.')
    } finally {
      setSaving(false)
    }
  }

  if (loading) return <div style={page}>Loading menu configuration…</div>

  return (
    <div style={page}>
      <div style={header}>
        <div>
          <span style={kicker}>Guest dining</span>
          <h1 style={title}>Menu Management</h1>
          <p style={subtitle}>
            {currentHotel?.hotel_name} · Normalized categories and guest-visible items.
          </p>
        </div>
        <button style={refreshBtn} onClick={() => loadData(currentHotel?.id)}>
          Refresh
        </button>
      </div>

      {error && <div style={errorBox}>{error}</div>}

      <div style={statsGrid}>
        <Card title="Categories" value={categories.length} />
        <Card title="Total Items" value={items.length} />
        <Card title="Available" value={items.filter((item) => item.is_available !== false).length} />
        <Card title="Unavailable" value={items.filter((item) => item.is_available === false).length} />
      </div>

      <div style={twoColumnGrid}>
        <form style={formCard} onSubmit={addCategory}>
          <h2 style={sectionTitle}>Add category</h2>
          <input style={input} placeholder="Breakfast, Beverages, Meals…" value={categoryName} onChange={(event) => setCategoryName(event.target.value)} />
          <button style={secondaryBtn} disabled={saving}>Add category</button>
          <div style={categoryList}>
            {categories.map((category) => (
              <span key={category.id} style={categoryChip}>{category.name}<small>{category.code}</small></span>
            ))}
          </div>
        </form>

        <form style={formCard} onSubmit={saveItem}>
          <h2 style={sectionTitle}>{editingItem ? 'Edit menu item' : 'Add menu item'}</h2>
          <input style={input} placeholder="Item name" value={itemForm.item_name} onChange={(event) => setItemForm((current) => ({ ...current, item_name: event.target.value }))} />
          <select style={input} value={itemForm.category_id} onChange={(event) => setItemForm((current) => ({ ...current, category_id: event.target.value }))}>
            <option value="">Select category</option>
            {categories.map((category) => <option key={category.id} value={category.id}>{category.name}</option>)}
          </select>
          <input style={input} type="number" min="0" step="0.01" placeholder="Price" value={itemForm.price} onChange={(event) => setItemForm((current) => ({ ...current, price: event.target.value }))} />
          <textarea style={{ ...input, minHeight: 86 }} placeholder="Description" value={itemForm.description} onChange={(event) => setItemForm((current) => ({ ...current, description: event.target.value }))} />
          <div style={formActions}>
            <button style={primaryBtn} disabled={saving}>{editingItem ? 'Update item' : 'Add item'}</button>
            {editingItem && <button type="button" style={secondaryBtn} onClick={resetItemForm}>Cancel</button>}
          </div>
        </form>
      </div>

      <div style={tableCard}>
        {items.length === 0 ? (
          <p>No menu items found. Add at least one item to make onboarding menu readiness pass.</p>
        ) : (
          <table style={table}>
            <thead><tr><th style={th}>Item</th><th style={th}>Category</th><th style={th}>Price</th><th style={th}>Availability</th><th style={th}>Actions</th></tr></thead>
            <tbody>
              {items.map((item) => (
                <tr key={item.id}>
                  <td style={td}><strong>{item.item_name}</strong><div style={muted}>{item.description || '-'}</div></td>
                  <td style={td}>{item.category || '-'}</td>
                  <td style={td}>₹{Number(item.price || 0).toLocaleString('en-IN')}</td>
                  <td style={td}><span style={badge(item.is_available)}>{item.is_available === false ? 'Unavailable' : 'Available'}</span></td>
                  <td style={td}><div style={rowActions}><button style={smallBtn} onClick={() => startEdit(item)}>Edit</button><button style={smallBtn} disabled={saving} onClick={() => toggleAvailability(item)}>{item.is_available === false ? 'Enable' : 'Disable'}</button><button style={deleteBtn} disabled={saving} onClick={() => deleteItem(item)}>Delete</button></div></td>
                </tr>
              ))}
            </tbody>
          </table>
        )}
      </div>
    </div>
  )
}

function Card({ title, value }) {
  return <div style={statCard}><div style={statTitle}>{title}</div><div style={statValue}>{value}</div></div>
}

function normalizeCode(value) {
  return String(value || '').trim().toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-+|-+$/g, '').slice(0, 48)
}

const page = { padding: '32px', color: '#fff' }
const header = { display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start', gap: 20, marginBottom: 24 }
const kicker = { color: '#d4af37', fontSize: 12, fontWeight: 800, textTransform: 'uppercase', letterSpacing: '.14em' }
const title = { fontSize: 42, margin: '7px 0 6px' }
const subtitle = { color: '#aaa' }
const refreshBtn = { background: '#d4af37', color: '#000', border: 'none', borderRadius: 10, padding: '12px 18px', fontWeight: 800, cursor: 'pointer' }
const errorBox = { marginBottom: 18, padding: 13, borderRadius: 10, color: '#ffb4b4', background: 'rgba(255,72,72,.1)', border: '1px solid rgba(255,72,72,.25)' }
const statsGrid = { display: 'grid', gridTemplateColumns: 'repeat(auto-fit,minmax(180px,1fr))', gap: 16, marginBottom: 22 }
const statCard = { background: '#0f0f0f', border: '1px solid #222', borderRadius: 16, padding: 18 }
const statTitle = { color: '#d4af37', fontSize: 13, marginBottom: 9 }
const statValue = { fontSize: 26, fontWeight: 700 }
const twoColumnGrid = { display: 'grid', gridTemplateColumns: 'repeat(auto-fit,minmax(320px,1fr))', gap: 18, marginBottom: 22 }
const formCard = { background: '#0f0f0f', border: '1px solid #222', borderRadius: 18, padding: 22 }
const sectionTitle = { color: '#d4af37', marginBottom: 16 }
const input = { width: '100%', padding: 12, marginBottom: 12, borderRadius: 10, border: '1px solid #333', background: '#111', color: '#fff' }
const formActions = { display: 'flex', gap: 10 }
const primaryBtn = { background: '#d4af37', color: '#000', border: 'none', borderRadius: 10, padding: '11px 17px', fontWeight: 800, cursor: 'pointer' }
const secondaryBtn = { background: '#1a1a1a', color: '#fff', border: '1px solid #333', borderRadius: 10, padding: '11px 17px', fontWeight: 700, cursor: 'pointer' }
const categoryList = { display: 'flex', flexWrap: 'wrap', gap: 8, marginTop: 16 }
const categoryChip = { display: 'inline-flex', flexDirection: 'column', gap: 2, padding: '8px 10px', borderRadius: 10, background: '#171717', border: '1px solid #292929', color: '#fff' }
const tableCard = { background: '#0f0f0f', border: '1px solid #222', borderRadius: 18, padding: 20, overflowX: 'auto' }
const table = { width: '100%', borderCollapse: 'collapse', minWidth: 850 }
const th = { color: '#d4af37', textAlign: 'left', padding: 14, borderBottom: '1px solid #222' }
const td = { padding: 14, borderBottom: '1px solid #1f1f1f' }
const muted = { color: '#777', fontSize: 12, marginTop: 4 }
const rowActions = { display: 'flex', gap: 7, flexWrap: 'wrap' }
const smallBtn = { background: '#1b1b1b', color: '#fff', border: '1px solid #333', borderRadius: 8, padding: '7px 9px', cursor: 'pointer' }
const deleteBtn = { ...smallBtn, color: '#ff9f9f', borderColor: 'rgba(255,90,90,.3)' }
const badge = (available) => ({ padding: '6px 10px', borderRadius: 999, color: available === false ? '#ff9f9f' : '#65e6ad', background: available === false ? 'rgba(255,90,90,.1)' : 'rgba(61,220,151,.1)', fontWeight: 700 })
