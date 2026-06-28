import { supabase } from './supabase'

const DEFAULT_HOTEL_ID = '77d850d0-016d-4155-bc44-a6207d30e7b9'

export async function getCurrentHotel() {
  const {
    data: { user },
  } = await supabase.auth.getUser()

  if (user?.email) {
    const { data } = await supabase
      .from('hotel_users')
      .select(`
        *,
        hotels (
          id,
          hotel_name,
          location,
          status
        )
      `)
      .eq('email', user.email)
      .maybeSingle()

    if (data?.hotels) {
      return data.hotels
    }
  }

  const { data: fallbackHotel } = await supabase
    .from('hotels')
    .select('id, hotel_name, location, status')
    .eq('id', DEFAULT_HOTEL_ID)
    .maybeSingle()

  return fallbackHotel
}