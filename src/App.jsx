import { useEffect } from 'react'
import { supabase } from './lib/supabase'

function App() {

  useEffect(() => {
    getHotels()
  }, [])

  async function getHotels() {
    const { data, error } = await supabase
      .from('hotels')
      .select('*')

    console.log('Hotels:', data)

    if (error) {
      console.error(error)
    }
  }

  return (
    <div>
      <h1>StayQR Connected 🚀</h1>
      <p>Check browser console for hotel data.</p>
    </div>
  )
}

export default App