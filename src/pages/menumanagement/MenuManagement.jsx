import { useEffect, useState } from "react";
import { supabase } from "../../lib/supabase";
import { getCurrentHotel } from "../../lib/currentHotel";

export default function MenuManagement() {
  const [currentHotel, setCurrentHotel] = useState(null);
  const [items, setItems] = useState([]);
  const [loading, setLoading] = useState(true);

  const [itemName, setItemName] = useState("");
  const [category, setCategory] = useState("");
  const [price, setPrice] = useState("");
  const [description, setDescription] = useState("");
  const [editingItem, setEditingItem] = useState(null);

  useEffect(() => {
    initPage();
  }, []);

  async function initPage() {
    const hotel = await getCurrentHotel();

    if (!hotel) {
      alert("No hotel assigned");
      setLoading(false);
      return;
    }

    setCurrentHotel(hotel);
    fetchItems(hotel.id);
  }

  async function fetchItems(hotelId = currentHotel?.id) {
    if (!hotelId) return;

    setLoading(true);

    const { data, error } = await supabase
      .from("menu_items")
      .select("*")
      .eq("hotel_id", hotelId)
      .order("item_name", { ascending: true });

    if (error) {
      alert(error.message);
      setLoading(false);
      return;
    }

    setItems(data || []);
    setLoading(false);
  }

  function resetForm() {
    setItemName("");
    setCategory("");
    setPrice("");
    setDescription("");
    setEditingItem(null);
  }

  function startEdit(item) {
    setEditingItem(item);
    setItemName(item.item_name || "");
    setCategory(item.category || "");
    setPrice(item.price || "");
    setDescription(item.description || "");
  }

  async function saveItem() {
    if (!currentHotel?.id) {
      alert("No hotel assigned");
      return;
    }

    if (!itemName || !price) {
      alert("Please enter item name and price");
      return;
    }

    try {
      if (editingItem) {
        const { error } = await supabase
          .from("menu_items")
          .update({
            item_name: itemName,
            category,
            price: Number(price),
            description,
          })
          .eq("id", editingItem.id)
          .eq("hotel_id", currentHotel.id);

        if (error) throw error;

        alert("Menu item updated");
      } else {
        const { error } = await supabase.from("menu_items").insert([
          {
            hotel_id: currentHotel.id,
            item_name: itemName,
            category,
            price: Number(price),
            description,
            is_available: true,
          },
        ]);

        if (error) throw error;

        alert("Menu item added");
      }

      resetForm();
      fetchItems(currentHotel.id);
    } catch (err) {
      alert(err.message);
    }
  }

  async function toggleAvailability(item) {
    const { error } = await supabase
      .from("menu_items")
      .update({
        is_available: !item.is_available,
      })
      .eq("id", item.id)
      .eq("hotel_id", currentHotel?.id);

    if (error) {
      alert(error.message);
      return;
    }

    fetchItems(currentHotel?.id);
  }

  async function deleteItem(item) {
    const confirmDelete = window.confirm(
      `Delete ${item.item_name}?`
    );

    if (!confirmDelete) return;

    const { error } = await supabase
      .from("menu_items")
      .delete()
      .eq("id", item.id)
      .eq("hotel_id", currentHotel?.id);

    if (error) {
      alert(error.message);
      return;
    }

    fetchItems(currentHotel?.id);
  }

  if (loading) {
    return <div style={page}>Loading menu items...</div>;
  }

  return (
    <div style={page}>
      <div style={header}>
        <div>
          <h1 style={title}>Food Menu Management</h1>
          <p style={subtitle}>
            {currentHotel?.hotel_name || "Hotel"} · Add, edit and manage menu items.
          </p>
        </div>

        <button style={refreshBtn} onClick={() => fetchItems(currentHotel?.id)}>
          Refresh
        </button>
      </div>

      <div style={statsGrid}>
        <Card title="Total Items" value={items.length} />
        <Card
          title="Available"
          value={items.filter((i) => i.is_available !== false).length}
        />
        <Card
          title="Unavailable"
          value={items.filter((i) => i.is_available === false).length}
        />
      </div>

      <div style={formCard}>
        <h2 style={sectionTitle}>
          {editingItem ? "Edit Menu Item" : "Add Menu Item"}
        </h2>

        <input
          style={input}
          placeholder="Item Name"
          value={itemName}
          onChange={(e) => setItemName(e.target.value)}
        />

        <input
          style={input}
          placeholder="Category e.g. Breakfast, Beverages, Snacks"
          value={category}
          onChange={(e) => setCategory(e.target.value)}
        />

        <input
          style={input}
          type="number"
          placeholder="Price"
          value={price}
          onChange={(e) => setPrice(e.target.value)}
        />

        <textarea
          style={input}
          placeholder="Description"
          value={description}
          onChange={(e) => setDescription(e.target.value)}
        />

        <button style={primaryBtn} onClick={saveItem}>
          {editingItem ? "Update Item" : "Add Item"}
        </button>

        {editingItem && (
          <button style={secondaryBtn} onClick={resetForm}>
            Cancel Edit
          </button>
        )}
      </div>

      <div style={tableCard}>
        {items.length === 0 ? (
          <p>No menu items found.</p>
        ) : (
          <table style={table}>
            <thead>
              <tr>
                <th style={th}>Item</th>
                <th style={th}>Category</th>
                <th style={th}>Price</th>
                <th style={th}>Description</th>
                <th style={th}>Availability</th>
                <th style={th}>Actions</th>
              </tr>
            </thead>

            <tbody>
              {items.map((item) => (
                <tr key={item.id}>
                  <td style={td}>{item.item_name}</td>
                  <td style={td}>{item.category || "-"}</td>
                  <td style={td}>₹{item.price}</td>
                  <td style={td}>{item.description || "-"}</td>
                  <td style={td}>
                    <span style={badge(item.is_available)}>
                      {item.is_available === false ? "Unavailable" : "Available"}
                    </span>
                  </td>
                  <td style={td}>
                    <button style={smallBtn} onClick={() => startEdit(item)}>
                      Edit
                    </button>

                    <button
                      style={smallBtn}
                      onClick={() => toggleAvailability(item)}
                    >
                      {item.is_available === false ? "Make Available" : "Disable"}
                    </button>

                    <button style={deleteBtn} onClick={() => deleteItem(item)}>
                      Delete
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

function Card({ title, value }) {
  return (
    <div style={statCard}>
      <div style={statTitle}>{title}</div>
      <div style={statValue}>{value}</div>
    </div>
  );
}

const page = {
  padding: "32px",
  color: "#fff",
};

const header = {
  display: "flex",
  justifyContent: "space-between",
  alignItems: "center",
  gap: "20px",
  marginBottom: "25px",
};

const title = {
  fontSize: "42px",
  marginBottom: "6px",
};

const subtitle = {
  color: "#aaa",
};

const refreshBtn = {
  background: "#d4af37",
  color: "#000",
  border: "none",
  borderRadius: "10px",
  padding: "12px 18px",
  fontWeight: 800,
  cursor: "pointer",
};

const statsGrid = {
  display: "grid",
  gridTemplateColumns: "repeat(auto-fit,minmax(200px,1fr))",
  gap: "18px",
  marginBottom: "25px",
};

const statCard = {
  background: "#0f0f0f",
  border: "1px solid #222",
  borderRadius: "16px",
  padding: "20px",
};

const statTitle = {
  color: "#d4af37",
  fontSize: "13px",
  marginBottom: "10px",
};

const statValue = {
  fontSize: "28px",
  fontWeight: "700",
};

const formCard = {
  background: "#0f0f0f",
  border: "1px solid #222",
  borderRadius: "18px",
  padding: "24px",
  marginBottom: "25px",
};

const sectionTitle = {
  color: "#d4af37",
  marginBottom: "18px",
};

const input = {
  width: "100%",
  padding: "13px",
  marginBottom: "14px",
  borderRadius: "10px",
  border: "1px solid #333",
  background: "#111",
  color: "#fff",
};

const primaryBtn = {
  background: "#d4af37",
  color: "#000",
  border: "none",
  borderRadius: "10px",
  padding: "12px 18px",
  fontWeight: 800,
  cursor: "pointer",
  marginRight: "10px",
};

const secondaryBtn = {
  background: "#222",
  color: "#fff",
  border: "1px solid #444",
  borderRadius: "10px",
  padding: "12px 18px",
  cursor: "pointer",
};

const tableCard = {
  background: "#0f0f0f",
  border: "1px solid #222",
  borderRadius: "18px",
  padding: "20px",
  overflowX: "auto",
};

const table = {
  width: "100%",
  borderCollapse: "collapse",
  minWidth: "1000px",
};

const th = {
  color: "#d4af37",
  textAlign: "left",
  padding: "14px",
  borderBottom: "1px solid #222",
};

const td = {
  padding: "14px",
  borderBottom: "1px solid #1f1f1f",
};

const smallBtn = {
  background: "#d4af37",
  color: "#000",
  border: "none",
  borderRadius: "8px",
  padding: "8px 12px",
  marginRight: "8px",
  fontWeight: 700,
  cursor: "pointer",
};

const deleteBtn = {
  background: "#ff4d4d",
  color: "#fff",
  border: "none",
  borderRadius: "8px",
  padding: "8px 12px",
  fontWeight: 700,
  cursor: "pointer",
};

const badge = (available) => ({
  padding: "7px 12px",
  borderRadius: "999px",
  background:
    available === false
      ? "rgba(255,77,77,.18)"
      : "rgba(46,204,113,.18)",
  color: available === false ? "#ff4d4d" : "#2ecc71",
  fontWeight: 700,
});