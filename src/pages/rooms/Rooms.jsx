import { useEffect, useState } from 'react'
import { supabase } from '../../lib/supabase'
import { getCurrentHotel } from '../../lib/currentHotel'
import RoomsTable from '../../components/table/RoomsTable'
import AddRoomModal from '../../components/modals/AddRoomModal'
import './Rooms.css'

export default function Rooms() {
  const [rooms, setRooms] = useState([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState(null)
  const [showAddRoomModal, setShowAddRoomModal] = useState(false)
  const [currentHotel, setCurrentHotel] = useState(null)

  const fetchRooms = async () => {
    setLoading(true)
    setError(null)

    try {
      const hotel = await getCurrentHotel()

      if (!hotel) {
        throw new Error('No hotel assigned to current user')
      }

      setCurrentHotel(hotel)

      const { data, error } = await supabase
        .from('rooms')
        .select('*')
        .eq('hotel_id', hotel.id)
        .order('room_number', { ascending: true })

      if (error) throw error

      setRooms(data || [])
    } catch (err) {
      console.error('Rooms fetch error:', err)
      setError(err.message)
    }

    setLoading(false)
  }

  useEffect(() => {
    fetchRooms()
  }, [])

  return (
    <div className="rooms-page">
      {showAddRoomModal && (
        <AddRoomModal
          hotelId={currentHotel?.id}
          onClose={() => setShowAddRoomModal(false)}
          onSuccess={fetchRooms}
        />
      )}

      <div className="rooms-header">
        <div>
          <h1>Rooms</h1>
          <p>
            {currentHotel
              ? `${currentHotel.hotel_name} • Manage rooms, availability and live room status`
              : 'Manage rooms, availability and live room status'}
          </p>
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