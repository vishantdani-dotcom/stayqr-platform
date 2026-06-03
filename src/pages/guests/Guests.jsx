import { useEffect, useState } from "react";
import { supabase } from "../../lib/supabase";
import "./Guests.css";

export default function Guests() {
  const [guests, setGuests] = useState([]);
  const [loading, setLoading] = useState(true);

  const fetchGuests = async () => {
    setLoading(true);

    const { data, error } = await supabase
      .from("guests")
      .select("*")
      .order("created_at", { ascending: false });

    if (error) {
      console.error(error);
      setLoading(false);
      return;
    }

    setGuests(data || []);
    setLoading(false);
  };

  const handleCheckOut = async (guest) => {
    const confirmCheckout = window.confirm(
      `Check out ${guest.full_name}?`
    );

    if (!confirmCheckout) return;

    await supabase
      .from("rooms")
      .update({ status: "available" })
      .eq("room_number", guest.room_number);

    await supabase
      .from("guests")
      .delete()
      .eq("id", guest.id);

    alert("Guest checked out successfully");

    fetchGuests();
  };

  useEffect(() => {
    fetchGuests();
  }, []);

  return (
    <div className="rooms-page">
      <div className="rooms-header">
        <div>
          <h1>Guests</h1>
          <p>Manage checked-in guests and departures.</p>
        </div>
      </div>

      <div className="rooms-card">
        {loading ? (
          <p>Loading guests...</p>
        ) : guests.length === 0 ? (
          <p>No guests found.</p>
        ) : (
          <table className="rooms-table">
            <thead>
              <tr>
                <th>Name</th>
                <th>Room</th>
                <th>Phone</th>
                <th>Check-In Time</th>
                <th>Action</th>
              </tr>
            </thead>

            <tbody>
              {guests.map((guest) => (
                <tr key={guest.id}>
                  <td>{guest.full_name}</td>

                  <td>{guest.room_number}</td>

                  <td>{guest.phone || "-"}</td>

                  <td>
                    {guest.created_at
                      ? new Date(
                          guest.created_at
                        ).toLocaleString("en-IN")
                      : "-"}
                  </td>

                  <td>
                    <button
                      className="checkout-btn"
                      onClick={() =>
                        handleCheckOut(guest)
                      }
                    >
                      Check Out
                    </button>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        )}
      </div>
    </div>
  );
}