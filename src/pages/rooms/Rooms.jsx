import { useEffect, useState } from 'react'
import { supabase } from '../../lib/supabase'
import RoomsTable from '../../components/table/RoomsTable'
import AddRoomModal from '../../components/modals/AddRoomModal'
import './Rooms.css'

export default function Rooms() {
  const [rooms, setRooms] = useState([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState(null)
  const [showAddRoomModal, setShowAddRoomModal] = useState(false)

  const fetchRooms = async () => {
    setLoading(true)
    setError(null)

    const { data, error } = await supabase
      .from('rooms')
      .select('*')
      .order('room_number', { ascending: true })

    if (error) {
      console.error('Rooms fetch error:', error)
      setError(error.message)
      setLoading(false)
      return
    }

    setRooms(data || [])
    setLoading(false)
  }

  useEffect(() => {
    fetchRooms()
  }, [])

  return (
    <div className="rooms-page">
      {showAddRoomModal && (
        <AddRoomModal
          onClose={() => setShowAddRoomModal(false)}
          onSuccess={fetchRooms}
        />
      )}

      <div className="rooms-header">
        <div>
          <h1>Rooms</h1>
          <p>Manage rooms, availability and live room status.</p>
        </div>

        <button
          className="rooms-add-btn"
          onClick={() => setShowAddRoomModal(true)}
        >
          + Add Room
        </button>
      </div>

      <RoomsTable
        rooms={rooms}
        loading={loading}
        error={error}
        onRefresh={fetchRooms}
      />
    </div>
  )
}