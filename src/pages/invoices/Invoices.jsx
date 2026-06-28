import { useEffect, useRef, useState } from "react";
import { supabase } from "../../lib/supabase";
import { getCurrentHotel } from "../../lib/currentHotel";
import html2canvas from "html2canvas";
import jsPDF from "jspdf";

export default function Invoices() {
  const [invoices, setInvoices] = useState([]);
  const [loading, setLoading] = useState(true);
  const [selectedInvoice, setSelectedInvoice] = useState(null);
  const [currentHotel, setCurrentHotel] = useState(null);
  const invoiceRef = useRef(null);

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
    fetchInvoices(hotel.id);
  }

  async function fetchInvoices(hotelId = currentHotel?.id) {
    if (!hotelId) return;

    setLoading(true);

    const { data, error } = await supabase
      .from("invoices")
      .select(`
        *,
        guests (
          full_name,
          phone
        ),
        rooms (
          room_number,
          room_type
        )
      `)
      .eq("hotel_id", hotelId)
      .order("created_at", { ascending: false });

    if (error) {
      alert(error.message);
      setLoading(false);
      return;
    }

    setInvoices(data || []);
    setLoading(false);
  }

  function openInvoice(invoice) {
    setSelectedInvoice(invoice);
  }

  async function downloadPDF() {
    if (!invoiceRef.current || !selectedInvoice) return;

    const canvas = await html2canvas(invoiceRef.current, {
      scale: 2,
      backgroundColor: "#ffffff",
      useCORS: true,
    });

    const imgData = canvas.toDataURL("image/png");
    const pdf = new jsPDF("p", "mm", "a4");

    const pageWidth = pdf.internal.pageSize.getWidth();
    const pageHeight = pdf.internal.pageSize.getHeight();

    const imgWidth = pageWidth;
    const imgHeight = (canvas.height * imgWidth) / canvas.width;

    let heightLeft = imgHeight;
    let position = 0;

    pdf.addImage(imgData, "PNG", 0, position, imgWidth, imgHeight);
    heightLeft -= pageHeight;

    while (heightLeft > 0) {
      position = heightLeft - imgHeight;
      pdf.addPage();
      pdf.addImage(imgData, "PNG", 0, position, imgWidth, imgHeight);
      heightLeft -= pageHeight;
    }

    pdf.save(`${selectedInvoice.invoice_number || "StayQR-Invoice"}.pdf`);
  }

  function printInvoice() {
    window.print();
  }

  if (loading) {
    return <div style={page}>Loading invoices...</div>;
  }

  return (
    <div style={page}>
      <div style={header}>
        <div>
          <h1 style={title}>Invoices</h1>
          <p style={hotelName}>{currentHotel?.hotel_name || "Hotel"}</p>
          <p style={subtitle}>View, print and download professional invoices.</p>
        </div>

        <button style={refreshBtn} onClick={() => fetchInvoices(currentHotel?.id)}>
          Refresh
        </button>
      </div>

      <div style={statsGrid}>
        <Card title="Total Invoices" value={invoices.length} />
        <Card
          title="Paid Invoices"
          value={invoices.filter((i) => i.payment_status === "paid").length}
        />
        <Card
          title="Pending Invoices"
          value={invoices.filter((i) => i.payment_status !== "paid").length}
        />
        <Card
          title="Invoice Revenue"
          value={`₹${invoices.reduce(
            (sum, i) => sum + Number(i.total_amount || 0),
            0
          )}`}
        />
      </div>

      <div style={tableCard}>
        {invoices.length === 0 ? (
          <p>No invoices found.</p>
        ) : (
          <table style={table}>
            <thead>
              <tr>
                <th style={th}>Invoice</th>
                <th style={th}>Guest</th>
                <th style={th}>Room</th>
                <th style={th}>Room Amount</th>
                <th style={th}>Food</th>
                <th style={th}>Manual</th>
                <th style={th}>Total</th>
                <th style={th}>Status</th>
                <th style={th}>Date</th>
                <th style={th}>Action</th>
              </tr>
            </thead>

            <tbody>
              {invoices.map((invoice) => (
                <tr key={invoice.id}>
                  <td style={td}>{invoice.invoice_number}</td>
                  <td style={td}>{invoice.guests?.full_name || "-"}</td>
                  <td style={td}>Room {invoice.rooms?.room_number || "-"}</td>
                  <td style={td}>₹{invoice.room_amount || 0}</td>
                  <td style={td}>₹{invoice.food_amount || 0}</td>
                  <td style={td}>₹{invoice.manual_amount || 0}</td>
                  <td style={td}>₹{invoice.total_amount || 0}</td>
                  <td style={td}>
                    <span style={badge(invoice.payment_status)}>
                      {invoice.payment_status || "pending"}
                    </span>
                  </td>
                  <td style={td}>
                    {invoice.created_at
                      ? new Date(invoice.created_at).toLocaleString("en-IN")
                      : "-"}
                  </td>
                  <td style={td}>
                    <button style={smallBtn} onClick={() => openInvoice(invoice)}>
                      View PDF
                    </button>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        )}
      </div>

      {selectedInvoice && (
        <div style={modalOverlay}>
          <div style={modal}>
            <div style={modalActions}>
              <button style={smallBtn} onClick={downloadPDF}>
                Download PDF
              </button>

              <button style={smallBtn} onClick={printInvoice}>
                Print
              </button>

              <button style={closeBtn} onClick={() => setSelectedInvoice(null)}>
                Close
              </button>
            </div>

            <div ref={invoiceRef} style={invoicePaper}>
              <div style={invoiceTop}>
                <div>
                  <div style={brandBadge}>StayQR</div>
                  <h1 style={invoiceHotel}>
                    {currentHotel?.hotel_name || "StayQR Hotel"}
                  </h1>
                  <p style={invoiceMuted}>
                    {currentHotel?.location || "Hotel Address"}
                  </p>
                </div>

                <div style={{ textAlign: "right" }}>
                  <h2 style={invoiceTitle}>INVOICE</h2>
                  <p style={invoiceMuted}>
                    Invoice No: <strong>{selectedInvoice.invoice_number}</strong>
                  </p>
                  <p style={invoiceMuted}>
                    Date:{" "}
                    <strong>
                      {selectedInvoice.created_at
                        ? new Date(selectedInvoice.created_at).toLocaleDateString("en-IN")
                        : "-"}
                    </strong>
                  </p>
                </div>
              </div>

              <hr style={invoiceLine} />

              <div style={invoiceGrid}>
                <div>
                  <h3 style={invoiceSectionTitle}>Bill To</h3>
                  <p style={invoiceText}>
                    <strong>{selectedInvoice.guests?.full_name || "-"}</strong>
                  </p>
                  <p style={invoiceMuted}>
                    Phone: {selectedInvoice.guests?.phone || "-"}
                  </p>
                </div>

                <div>
                  <h3 style={invoiceSectionTitle}>Stay Details</h3>
                  <p style={invoiceText}>
                    Room {selectedInvoice.rooms?.room_number || "-"}
                  </p>
                  <p style={invoiceMuted}>
                    {selectedInvoice.rooms?.room_type || "Hotel Room"}
                  </p>
                  <p style={invoiceMuted}>
                    Payment Status:{" "}
                    <strong>{selectedInvoice.payment_status || "pending"}</strong>
                  </p>
                </div>
              </div>

              <table style={invoiceTable}>
                <thead>
                  <tr>
                    <th style={invoiceTh}>Description</th>
                    <th style={invoiceThRight}>Amount</th>
                  </tr>
                </thead>

                <tbody>
                  <InvoiceRow label="Room Charges" value={selectedInvoice.room_amount} />
                  <InvoiceRow label="Food Charges" value={selectedInvoice.food_amount} />
                  <InvoiceRow label="Manual Charges" value={selectedInvoice.manual_amount} />
                  <InvoiceRow label="Service Charges" value={selectedInvoice.service_amount} />
                </tbody>
              </table>

              <div style={invoiceTotalBox}>
                <span>Total Amount</span>
                <strong>₹{selectedInvoice.total_amount || 0}</strong>
              </div>

              <div style={invoiceNote}>
                <p>
                  This invoice confirms the charges recorded for the guest stay.
                  Please contact reception for any billing clarification.
                </p>
              </div>

              <div style={invoiceFooter}>
                <p>Thank you for staying with us.</p>
                <p>Powered by StayQR · Smart Hospitality Experience</p>
              </div>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}

function InvoiceRow({ label, value }) {
  return (
    <tr>
      <td style={invoiceTd}>{label}</td>
      <td style={invoiceTdRight}>₹{value || 0}</td>
    </tr>
  );
}

function Card({ title, value }) {
  return (
    <div style={statCard}>
      <span style={statLabel}>{title}</span>
      <strong style={statValue}>{value}</strong>
    </div>
  );
}

const page = { padding: "32px", color: "#fff" };
const hotelName = { color: "#d4af37", marginBottom: "6px" };

const header = {
  display: "flex",
  justifyContent: "space-between",
  alignItems: "center",
  marginBottom: "25px",
};

const title = { fontSize: "42px", marginBottom: "6px" };
const subtitle = { color: "#aaa" };

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

const statLabel = {
  display: "block",
  color: "#d4af37",
  fontSize: "13px",
  marginBottom: "10px",
};

const statValue = { fontSize: "28px" };

const tableCard = {
  background: "#0f0f0f",
  border: "1px solid #222",
  borderRadius: "18px",
  overflowX: "auto",
  padding: "10px",
};

const table = {
  width: "100%",
  borderCollapse: "collapse",
  minWidth: "1250px",
};

const th = {
  padding: "16px",
  textAlign: "left",
  color: "#d4af37",
  borderBottom: "1px solid #222",
};

const td = {
  padding: "16px",
  borderBottom: "1px solid #1f1f1f",
  verticalAlign: "top",
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

const closeBtn = {
  background: "#222",
  color: "#fff",
  border: "1px solid #444",
  borderRadius: "8px",
  padding: "8px 12px",
  cursor: "pointer",
};

const badge = (status) => ({
  padding: "7px 12px",
  borderRadius: "999px",
  background:
    status === "paid"
      ? "rgba(46,204,113,.18)"
      : "rgba(255,170,0,.18)",
  color: status === "paid" ? "#2ecc71" : "#ffaa00",
  fontWeight: 700,
  textTransform: "capitalize",
});

const modalOverlay = {
  position: "fixed",
  inset: 0,
  background: "rgba(0,0,0,0.82)",
  display: "flex",
  alignItems: "flex-start",
  justifyContent: "center",
  zIndex: 9999,
  overflowY: "auto",
  padding: "30px",
};

const modal = {
  width: "100%",
  maxWidth: "900px",
};

const modalActions = {
  display: "flex",
  justifyContent: "flex-end",
  marginBottom: "12px",
};

const invoicePaper = {
  background: "#fff",
  color: "#111",
  borderRadius: "10px",
  padding: "42px",
  fontFamily: "Arial, sans-serif",
};

const brandBadge = {
  display: "inline-block",
  background: "#111",
  color: "#d4af37",
  padding: "8px 12px",
  borderRadius: "999px",
  fontWeight: 800,
  marginBottom: "12px",
};

const invoiceTop = {
  display: "flex",
  justifyContent: "space-between",
  gap: "30px",
};

const invoiceHotel = {
  margin: 0,
  color: "#111",
  fontSize: "30px",
};

const invoiceTitle = {
  margin: 0,
  color: "#b9962d",
  fontSize: "30px",
};

const invoiceMuted = {
  margin: "6px 0",
  color: "#555",
  fontSize: "14px",
};

const invoiceText = {
  margin: "6px 0",
  color: "#111",
  fontSize: "15px",
};

const invoiceLine = {
  border: "none",
  borderTop: "1px solid #ddd",
  margin: "28px 0",
};

const invoiceGrid = {
  display: "grid",
  gridTemplateColumns: "1fr 1fr",
  gap: "30px",
  marginBottom: "30px",
};

const invoiceSectionTitle = {
  margin: "0 0 8px",
  color: "#b9962d",
  fontSize: "16px",
};

const invoiceTable = {
  width: "100%",
  borderCollapse: "collapse",
  marginTop: "10px",
};

const invoiceTh = {
  background: "#111",
  color: "#fff",
  padding: "14px",
  textAlign: "left",
};

const invoiceThRight = {
  ...invoiceTh,
  textAlign: "right",
};

const invoiceTd = {
  padding: "14px",
  borderBottom: "1px solid #ddd",
  color: "#111",
};

const invoiceTdRight = {
  ...invoiceTd,
  textAlign: "right",
  fontWeight: 700,
};

const invoiceTotalBox = {
  marginTop: "28px",
  padding: "18px",
  background: "#f7f7f7",
  border: "1px solid #ddd",
  borderRadius: "8px",
  display: "flex",
  justifyContent: "space-between",
  fontSize: "22px",
};

const invoiceNote = {
  marginTop: "26px",
  background: "#fafafa",
  border: "1px solid #eee",
  borderRadius: "8px",
  padding: "14px",
  color: "#555",
  fontSize: "13px",
};

const invoiceFooter = {
  marginTop: "40px",
  paddingTop: "20px",
  borderTop: "1px solid #ddd",
  color: "#555",
  fontSize: "13px",
};