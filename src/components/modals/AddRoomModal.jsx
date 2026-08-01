import { useState } from 'react'

export default function AddRoomModal({ onClose, onSubmit }) {
  const [values, setValues] = useState({
    room_number: '',
    floor_id: '',
    room_type_id: '',
    status: 'available',
  })

  const handleSubmit = async (event) => {
    event.preventDefault()
    await onSubmit?.(values)
  }

  return (
    <div className="modal-overlay">
      <form className="modal-card" onSubmit={handleSubmit}>
        <h2>Add room</h2>
        <input
          required
          placeholder="Room number"
          value={values.room_number}
          onChange={(event) =>
            setValues((current) => ({ ...current, room_number: event.target.value }))
          }
        />
        <input
          required
          placeholder="Floor UUID"
          value={values.floor_id}
          onChange={(event) =>
            setValues((current) => ({ ...current, floor_id: event.target.value }))
          }
        />
        <input
          required
          placeholder="Room type UUID"
          value={values.room_type_id}
          onChange={(event) =>
            setValues((current) => ({ ...current, room_type_id: event.target.value }))
          }
        />
        <button type="submit">Continue</button>
        <button type="button" onClick={onClose}>
          Cancel
        </button>
      </form>
    </div>
  )
}
