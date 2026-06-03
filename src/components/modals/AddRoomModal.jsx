import { useState } from 'react'
import { supabase } from '../../lib/supabase'

export default function AddRoomModal({ onClose, onSuccess }) {
  const [roomNumber, setRoomNumber] = useState('')
  const [roomType, setRoomType] = useState('Standard Room')
  const [status, setStatus] = useState('available')
  const [saving, setSaving] = useState(false)

  const handleSubmit = async (e) => {
    e.preventDefault()

    if (!roomNumber) {
      alert('Enter room number')
      return
    }

    try {
      setSaving(true)

      const { error } = await supabase
        .from('rooms')
        .insert([
          {
            room_number: roomNumber,
            room_type: roomType,
            status,
          },
        ])

      if (error) throw error

      alert('Room added successfully')

      onSuccess?.()
      onClose?.()
    } catch (err) {
      console.error(err)
      alert(err.message)
    } finally {
      setSaving(false)
    }
  }

  return (
    <div className="modal-overlay">
      <div className="modal-card">
        <h2>Add New Room</h2>

        <form onSubmit={handleSubmit}>
          <input
            type="text"
            placeholder="Room Number"
            value={roomNumber}
            onChange={(e) => setRoomNumber(e.target.value)}
          />

          <select
            value={roomType}
            onChange={(e) => setRoomType(e.target.value)}
          >
            <option>Standard Room</option>
            <option>Deluxe Room</option>
            <option>Premium Room</option>
            <option>Suite</option>
          </select>

          <select
            value={status}
            onChange={(e) => setStatus(e.target.value)}
          >
            <option value="available">Available</option>
            <option value="occupied">Occupied</option>
            <option value="maintenance">Maintenance</option>
          </select>

          <button type="submit" disabled={saving}>
            {saving ? 'Saving...' : 'Save Room'}
          </button>

          <button
            type="button"
            onClick={onClose}
          >
            Cancel
          </button>
        </form>
      </div>
    </div>
  )
}