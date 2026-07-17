import { useEffect, useRef, useState } from "react";
import { supabase } from "../../lib/supabase";
import { getCurrentHotel } from "../../lib/currentHotel";
import html2canvas from "html2canvas";
import jsPDF from "jspdf";

export default function Invoices() {
  const [invoices, setInvoices] = useState([]);
  const [loading, setLoading] = useState(true);
  const [selectedInvoice, setSelectedInvoice] =
    useState(null);

  const [currentHotel, setCurrentHotel] =
    useState(null);

  const invoiceRef = useRef(null);

  useEffect(() => {
    initPage();
  }, []);

  useEffect(() => {
    if (!currentHotel?.id) return undefined;

    const invoiceChannel = supabase
      .channel(`invoice_breakdown_${currentHotel.id}`)
      .on(
        "postgres_changes",
        {
          event: "*",
          schema: "public",
          table: "invoices",
          filter: `hotel_id=eq.${currentHotel.id}`,
        },
        () => {
          fetchInvoices(currentHotel.id);
        }
      )
      .subscribe();

    const itemChannel = supabase
      .channel(`invoice_items_${currentHotel.id}`)
      .on(
        "postgres_changes",
        {
          event: "*",
          schema: "public",
          table: "invoice_items",
          filter: `hotel_id=eq.${currentHotel.id}`,
        },
        () => {
          fetchInvoices(currentHotel.id);
        }
      )
      .subscribe();

    return () => {
      supabase.removeChannel(invoiceChannel);
      supabase.removeChannel(itemChannel);
    };
  }, [currentHotel?.id]);

  async function initPage() {
    const hotel = await getCurrentHotel();

    if (!hotel) {
      alert("No hotel assigned");
      setLoading(false);
      return;
    }

    setCurrentHotel(hotel);
    await fetchInvoices(hotel.id);
  }

  async function fetchInvoices(
    hotelId = currentHotel?.id
  ) {
    if (!hotelId) return;

    setLoading(true);

    const { data, error } = await supabase
      .from("invoices")
      .select(`
        *,
        invoice_items (
          id,
          item_type,
          description,
          quantity,
          unit_price,
          amount,
          source_id,
          created_at
        ),
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
      console.error("Invoice fetch error:", error);
      alert(error.message);
      setLoading(false);
      return;
    }

    const normalizedInvoices = (data || []).map(
      (invoice) => ({
        ...invoice,

        invoice_items: [
          ...(invoice.invoice_items || []),
        ].sort(
          (first, second) =>
            new Date(
              first.created_at || 0
            ).getTime() -
            new Date(
              second.created_at || 0
            ).getTime()
        ),
      })
    );

    setInvoices(normalizedInvoices);

    if (selectedInvoice) {
      const refreshedSelected =
        normalizedInvoices.find(
          (invoice) =>
            String(invoice.id) ===
            String(selectedInvoice.id)
        );

      if (refreshedSelected) {
        setSelectedInvoice(refreshedSelected);
      }
    }

    setLoading(false);
  }

  function openInvoice(invoice) {
    setSelectedInvoice(invoice);
  }

  async function downloadPDF() {
    if (!invoiceRef.current || !selectedInvoice) {
      return;
    }

    try {
      const canvas = await html2canvas(
        invoiceRef.current,
        {
          scale: 2,
          backgroundColor: "#ffffff",
          useCORS: true,
        }
      );

      const imgData =
        canvas.toDataURL("image/png");

      const pdf = new jsPDF("p", "mm", "a4");

      const pageWidth =
        pdf.internal.pageSize.getWidth();

      const pageHeight =
        pdf.internal.pageSize.getHeight();

      const imgWidth = pageWidth;

      const imgHeight =
        (canvas.height * imgWidth) /
        canvas.width;

      let heightLeft = imgHeight;
      let position = 0;

      pdf.addImage(
        imgData,
        "PNG",
        0,
        position,
        imgWidth,
        imgHeight
      );

      heightLeft -= pageHeight;

      while (heightLeft > 0) {
        position = heightLeft - imgHeight;

        pdf.addPage();

        pdf.addImage(
          imgData,
          "PNG",
          0,
          position,
          imgWidth,
          imgHeight
        );

        heightLeft -= pageHeight;
      }

      pdf.save(
        `${
          selectedInvoice.invoice_number ||
          "StayQR-Invoice"
        }.pdf`
      );
    } catch (error) {
      console.error("Invoice PDF error:", error);
      alert("Unable to download invoice PDF.");
    }
  }

  function printInvoice() {
    window.print();
  }

  const totalInvoiceValue = invoices.reduce(
    (sum, invoice) =>
      sum + Number(invoice.total_amount || 0),
    0
  );

  const totalPaid = invoices.reduce(
    (sum, invoice) =>
      sum + Number(invoice.paid_amount || 0),
    0
  );

  const totalPending = invoices.reduce(
    (sum, invoice) =>
      sum +
      Number(
        invoice.pending_amount ??
          invoice.amount_to_collect ??
          0
      ),
    0
  );

  if (loading) {
    return (
      <div style={page}>
        Loading invoices...
      </div>
    );
  }

  return (
    <div style={page}>
      <div style={header}>
        <div>
          <p style={kicker}>
            DIGITAL BILLING
          </p>

          <h1 style={title}>Invoices</h1>

          <p style={hotelName}>
            {currentHotel?.hotel_name || "Hotel"}
          </p>

          <p style={subtitle}>
            View, print and download professional
            itemised hotel invoices.
          </p>
        </div>

        <button
          style={refreshBtn}
          onClick={() =>
            fetchInvoices(currentHotel?.id)
          }
        >
          Refresh
        </button>
      </div>

      <div style={statsGrid}>
        <Card
          title="Total Invoices"
          value={invoices.length}
        />

        <Card
          title="Paid Invoices"
          value={
            invoices.filter(
              (invoice) =>
                getInvoicePaymentStatus(invoice) ===
                "paid"
            ).length
          }
        />

        <Card
          title="Pending / Partial"
          value={
            invoices.filter(
              (invoice) =>
                getInvoicePaymentStatus(invoice) !==
                "paid"
            ).length
          }
        />

        <Card
          title="Invoice Value"
          value={`₹${totalInvoiceValue}`}
        />

        <Card
          title="Collected"
          value={`₹${totalPaid}`}
        />

        <Card
          title="Outstanding"
          value={`₹${totalPending}`}
        />
      </div>

      <div style={tableCard}>
        {invoices.length === 0 ? (
          <div style={emptyState}>
            <h3>No invoices found</h3>

            <p>
              Completed guest checkouts will appear
              here.
            </p>
          </div>
        ) : (
          <table style={table}>
            <thead>
              <tr>
                <th style={th}>Invoice</th>
                <th style={th}>Guest</th>
                <th style={th}>Room</th>
                <th style={th}>Items</th>
                <th style={th}>Subtotal</th>
                <th style={th}>Tax</th>
                <th style={th}>Discount</th>
                <th style={th}>Total</th>
                <th style={th}>Paid</th>
                <th style={th}>Balance</th>
                <th style={th}>Status</th>
                <th style={th}>Date</th>
                <th style={th}>Action</th>
              </tr>
            </thead>

            <tbody>
              {invoices.map((invoice) => {
                const balance = getInvoiceBalance(
                  invoice
                );

                return (
                  <tr key={invoice.id}>
                    <td style={td}>
                      <strong>
                        {invoice.invoice_number}
                      </strong>

                      <small style={tableSubText}>
                        {invoice.invoice_items?.length ||
                          0}{" "}
                        line item(s)
                      </small>
                    </td>

                    <td style={td}>
                      <strong>
                        {invoice.guests?.full_name ||
                          "-"}
                      </strong>

                      <small style={tableSubText}>
                        {invoice.guests?.phone || ""}
                      </small>
                    </td>

                    <td style={td}>
                      Room{" "}
                      {invoice.rooms?.room_number ||
                        "-"}

                      <small style={tableSubText}>
                        {invoice.rooms?.room_type || ""}
                      </small>
                    </td>

                    <td style={td}>
                      {invoice.food_item_count || 0}{" "}
                      food item(s)
                    </td>

                    <td style={td}>
                      ₹
                      {Number(
                        invoice.subtotal_amount ??
                          invoice.total_amount ??
                          0
                      )}
                    </td>

                    <td style={td}>
                      ₹
                      {Number(
                        invoice.tax_amount || 0
                      )}
                    </td>

                    <td style={td}>
                      ₹
                      {Number(
                        invoice.discount_amount || 0
                      )}
                    </td>

                    <td style={td}>
                      <strong>
                        ₹
                        {Number(
                          invoice.total_amount || 0
                        )}
                      </strong>
                    </td>

                    <td style={td}>
                      ₹
                      {Number(
                        invoice.paid_amount ||
                          invoice.previous_paid_amount ||
                          0
                      )}
                    </td>

                    <td style={td}>
                      ₹{balance}
                    </td>

                    <td style={td}>
                      <span
                        style={badge(
                          getInvoicePaymentStatus(
                            invoice
                          )
                        )}
                      >
                        {formatLabel(
                          getInvoicePaymentStatus(
                            invoice
                          )
                        )}
                      </span>
                    </td>

                    <td style={td}>
                      {invoice.created_at
                        ? new Date(
                            invoice.created_at
                          ).toLocaleString("en-IN")
                        : "-"}
                    </td>

                    <td style={td}>
                      <button
                        style={smallBtn}
                        onClick={() =>
                          openInvoice(invoice)
                        }
                      >
                        View Invoice
                      </button>
                    </td>
                  </tr>
                );
              })}
            </tbody>
          </table>
        )}
      </div>

      {selectedInvoice && (
        <div style={modalOverlay}>
          <div style={modal}>
            <div style={modalActions}>
              <button
                style={smallBtn}
                onClick={downloadPDF}
              >
                Download PDF
              </button>

              <button
                style={smallBtn}
                onClick={printInvoice}
              >
                Print
              </button>

              <button
                style={closeBtn}
                onClick={() =>
                  setSelectedInvoice(null)
                }
              >
                Close
              </button>
            </div>

            <div
              ref={invoiceRef}
              style={invoicePaper}
            >
              <div style={invoiceTop}>
                <div>
                  <div style={brandBadge}>
                    StayQR
                  </div>

                  <h1 style={invoiceHotel}>
                    {currentHotel?.hotel_name ||
                      "StayQR Hotel"}
                  </h1>

                  <p style={invoiceMuted}>
                    {currentHotel?.location ||
                      currentHotel?.address ||
                      "Hotel Address"}
                  </p>
                </div>

                <div style={invoiceTopRight}>
                  <h2 style={invoiceTitle}>
                    INVOICE
                  </h2>

                  <p style={invoiceMuted}>
                    Invoice No:{" "}
                    <strong>
                      {
                        selectedInvoice.invoice_number
                      }
                    </strong>
                  </p>

                  <p style={invoiceMuted}>
                    Date:{" "}
                    <strong>
                      {selectedInvoice.created_at
                        ? new Date(
                            selectedInvoice.created_at
                          ).toLocaleDateString(
                            "en-IN"
                          )
                        : "-"}
                    </strong>
                  </p>

                  <span
                    style={invoiceStatusBadge(
                      getInvoicePaymentStatus(
                        selectedInvoice
                      )
                    )}
                  >
                    {formatLabel(
                      getInvoicePaymentStatus(
                        selectedInvoice
                      )
                    )}
                  </span>
                </div>
              </div>

              <hr style={invoiceLine} />

              <div style={invoiceGrid}>
                <div>
                  <h3 style={invoiceSectionTitle}>
                    Bill To
                  </h3>

                  <p style={invoiceText}>
                    <strong>
                      {selectedInvoice.guests
                        ?.full_name || "-"}
                    </strong>
                  </p>

                  <p style={invoiceMuted}>
                    Phone:{" "}
                    {selectedInvoice.guests?.phone ||
                      "-"}
                  </p>
                </div>

                <div>
                  <h3 style={invoiceSectionTitle}>
                    Stay Details
                  </h3>

                  <p style={invoiceText}>
                    Room{" "}
                    {selectedInvoice.rooms
                      ?.room_number || "-"}
                  </p>

                  <p style={invoiceMuted}>
                    {selectedInvoice.rooms?.room_type ||
                      "Hotel Room"}
                  </p>

                  <p style={invoiceMuted}>
                    Stay:{" "}
                    <strong>
                      {selectedInvoice.stay_nights ||
                        1}{" "}
                      night(s)
                    </strong>
                  </p>

                  <p style={invoiceMuted}>
                    Check-in:{" "}
                    {selectedInvoice.checkin_time
                      ? new Date(
                          selectedInvoice.checkin_time
                        ).toLocaleString("en-IN")
                      : "-"}
                  </p>

                  <p style={invoiceMuted}>
                    Checkout:{" "}
                    {selectedInvoice.checkout_time
                      ? new Date(
                          selectedInvoice.checkout_time
                        ).toLocaleString("en-IN")
                      : "-"}
                  </p>
                </div>
              </div>

              <table style={invoiceTable}>
                <thead>
                  <tr>
                    <th style={invoiceTh}>
                      Description
                    </th>

                    <th style={invoiceThCenter}>
                      Qty
                    </th>

                    <th style={invoiceThRight}>
                      Rate
                    </th>

                    <th style={invoiceThRight}>
                      Amount
                    </th>
                  </tr>
                </thead>

                <tbody>
                  {selectedInvoice.invoice_items
                    ?.length > 0 ? (
                    selectedInvoice.invoice_items.map(
                      (item) => (
                        <InvoiceItemRow
                          key={item.id}
                          item={item}
                        />
                      )
                    )
                  ) : (
                    <>
                      <InvoiceRow
                        label="Room Charges"
                        value={
                          selectedInvoice.room_amount
                        }
                      />

                      <InvoiceRow
                        label="Food Charges"
                        value={
                          selectedInvoice.food_amount
                        }
                      />

                      <InvoiceRow
                        label="Manual Charges"
                        value={
                          selectedInvoice.manual_amount
                        }
                      />

                      <InvoiceRow
                        label="Service Charges"
                        value={
                          selectedInvoice.service_amount
                        }
                      />
                    </>
                  )}
                </tbody>
              </table>

              <div style={invoiceSummary}>
                <SummaryRow
                  label="Subtotal"
                  value={
                    selectedInvoice.subtotal_amount ??
                    selectedInvoice.total_amount
                  }
                />

                <SummaryRow
                  label={`Tax (${
                    selectedInvoice.tax_percent || 0
                  }%)`}
                  value={
                    selectedInvoice.tax_amount || 0
                  }
                />

                <SummaryRow
                  label="Discount"
                  value={
                    selectedInvoice.discount_amount ||
                    0
                  }
                  negative
                />

                <div style={summaryDivider} />

                <SummaryRow
                  label="Grand Total"
                  value={
                    selectedInvoice.total_amount || 0
                  }
                  strong
                />

                <SummaryRow
                  label="Previously Paid"
                  value={
                    selectedInvoice.previous_paid_amount ||
                    selectedInvoice.paid_amount ||
                    0
                  }
                />

                <SummaryRow
                  label="Balance Due"
                  value={getInvoiceBalance(
                    selectedInvoice
                  )}
                  strong
                />
              </div>

              {selectedInvoice.invoice_notes && (
                <div style={invoiceNote}>
                  <strong>Invoice Notes</strong>

                  <p>
                    {selectedInvoice.invoice_notes}
                  </p>
                </div>
              )}

              <div style={invoiceNote}>
                <p>
                  This invoice contains the charges
                  recorded for the guest stay. Please
                  contact reception for any billing
                  clarification.
                </p>
              </div>

              <div style={invoiceFooter}>
                <p>
                  Thank you for staying with us.
                </p>

                <p>
                  Powered by StayQR · Smart Hospitality
                  Experience
                </p>
              </div>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}

function InvoiceItemRow({ item }) {
  return (
    <tr>
      <td style={invoiceTd}>
        <strong>
          {item.description || "Invoice Item"}
        </strong>

        <span style={invoiceItemType}>
          {formatInvoiceItemType(item.item_type)}
        </span>
      </td>

      <td style={invoiceTdCenter}>
        {Number(item.quantity || 0)}
      </td>

      <td style={invoiceTdRight}>
        ₹{Number(item.unit_price || 0)}
      </td>

      <td style={invoiceTdRight}>
        ₹{Number(item.amount || 0)}
      </td>
    </tr>
  );
}

function InvoiceRow({ label, value }) {
  return (
    <tr>
      <td style={invoiceTd}>{label}</td>

      <td style={invoiceTdCenter}>1</td>

      <td style={invoiceTdRight}>
        ₹{Number(value || 0)}
      </td>

      <td style={invoiceTdRight}>
        ₹{Number(value || 0)}
      </td>
    </tr>
  );
}

function SummaryRow({
  label,
  value,
  negative = false,
  strong = false,
}) {
  return (
    <div
      style={{
        ...summaryRow,
        ...(strong ? summaryRowStrong : {}),
      }}
    >
      <span>{label}</span>

      <strong>
        {negative ? "- " : ""}
        ₹{Number(value || 0)}
      </strong>
    </div>
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

function getInvoiceBalance(invoice) {
  return Math.max(
    0,
    Number(
      invoice.pending_amount ??
        invoice.amount_to_collect ??
        0
    )
  );
}

function getInvoicePaymentStatus(invoice) {
  if (invoice.invoice_status === "paid") {
    return "paid";
  }

  if (
    invoice.invoice_status === "partially_paid"
  ) {
    return "partial";
  }

  if (invoice.payment_status === "paid") {
    return "paid";
  }

  if (
    invoice.payment_status === "partial" ||
    Number(invoice.paid_amount || 0) > 0
  ) {
    return "partial";
  }

  return "pending";
}

function formatInvoiceItemType(type) {
  const labels = {
    room: "Room Charge",
    food: "Food & Beverage",
    service: "Hotel Service",
    manual_charge: "Additional Charge",
    tax: "Tax",
    discount: "Discount",
    other: "Other",
  };

  return labels[type] || "Charge";
}

function formatLabel(value) {
  return String(value || "")
    .replaceAll("_", " ")
    .replace(/\b\w/g, (letter) =>
      letter.toUpperCase()
    );
}

const page = {
  padding: "32px",
  color: "#fff",
};

const kicker = {
  margin: "0 0 7px",
  color: "#d4af37",
  fontSize: "12px",
  fontWeight: 900,
  letterSpacing: "2px",
};

const hotelName = {
  color: "#d4af37",
  marginBottom: "6px",
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
  margin: "0 0 6px",
};

const subtitle = {
  color: "#aaa",
  margin: 0,
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
  gridTemplateColumns:
    "repeat(auto-fit,minmax(180px,1fr))",
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

const statValue = {
  fontSize: "28px",
};

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
  minWidth: "1650px",
};

const th = {
  padding: "16px",
  textAlign: "left",
  color: "#d4af37",
  borderBottom: "1px solid #222",
  whiteSpace: "nowrap",
};

const td = {
  padding: "16px",
  borderBottom: "1px solid #1f1f1f",
  verticalAlign: "top",
};

const tableSubText = {
  display: "block",
  marginTop: "5px",
  color: "#777",
  fontSize: "11px",
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
  display: "inline-block",
  padding: "7px 12px",
  borderRadius: "999px",

  background:
    status === "paid"
      ? "rgba(46,204,113,.18)"
      : status === "partial"
        ? "rgba(52,152,219,.18)"
        : "rgba(255,170,0,.18)",

  color:
    status === "paid"
      ? "#2ecc71"
      : status === "partial"
        ? "#3498db"
        : "#ffaa00",

  fontWeight: 700,
  whiteSpace: "nowrap",
});

const emptyState = {
  padding: "45px",
  textAlign: "center",
  color: "#888",
};

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
  maxWidth: "950px",
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

const invoiceTopRight = {
  textAlign: "right",
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

const invoiceThCenter = {
  ...invoiceTh,
  textAlign: "center",
  width: "80px",
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

const invoiceTdCenter = {
  ...invoiceTd,
  textAlign: "center",
};

const invoiceTdRight = {
  ...invoiceTd,
  textAlign: "right",
  fontWeight: 700,
};

const invoiceItemType = {
  display: "block",
  marginTop: "4px",
  color: "#777",
  fontSize: "11px",
  fontWeight: 500,
};

const invoiceSummary = {
  width: "100%",
  maxWidth: "390px",
  margin: "28px 0 0 auto",
  padding: "18px",
  background: "#f7f7f7",
  border: "1px solid #ddd",
  borderRadius: "8px",
};

const summaryRow = {
  display: "flex",
  justifyContent: "space-between",
  gap: "20px",
  padding: "7px 0",
  color: "#333",
  fontSize: "14px",
};

const summaryRowStrong = {
  color: "#111",
  fontSize: "18px",
};

const summaryDivider = {
  borderTop: "1px solid #ccc",
  margin: "8px 0",
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

const invoiceStatusBadge = (status) => ({
  display: "inline-block",
  marginTop: "8px",
  padding: "6px 10px",
  borderRadius: "999px",

  background:
    status === "paid"
      ? "#eaf8ef"
      : status === "partial"
        ? "#eaf4fb"
        : "#fff4dc",

  color:
    status === "paid"
      ? "#178943"
      : status === "partial"
        ? "#2473a7"
        : "#a56b00",

  fontSize: "11px",
  fontWeight: 800,
});