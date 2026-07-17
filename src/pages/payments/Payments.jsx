import {
  Fragment,
  useEffect,
  useMemo,
  useState,
} from "react";
import { supabase } from "../../lib/supabase";
import { getCurrentHotel } from "../../lib/currentHotel";
import { getCurrentStaff } from "../../lib/currentStaff";

export default function Payments() {
  const [payments, setPayments] = useState([]);
  const [collections, setCollections] = useState([]);
  const [currentHotel, setCurrentHotel] = useState(null);
  const [currentStaff, setCurrentStaff] = useState(null);

  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);

  const [collectingPaymentId, setCollectingPaymentId] =
    useState(null);

  const [expandedPaymentId, setExpandedPaymentId] =
    useState(null);

  const [collectionAmount, setCollectionAmount] =
    useState("");

  const [paymentMethod, setPaymentMethod] =
    useState("cash");

  const [
    transactionReference,
    setTransactionReference,
  ] = useState("");

  const [paymentNotes, setPaymentNotes] = useState("");

  useEffect(() => {
    initPage();
  }, []);

  useEffect(() => {
    if (!currentHotel?.id) return undefined;

    const paymentsChannel = supabase
      .channel(`payments_${currentHotel.id}`)
      .on(
        "postgres_changes",
        {
          event: "*",
          schema: "public",
          table: "payments",
          filter: `hotel_id=eq.${currentHotel.id}`,
        },
        () => {
          loadData(currentHotel.id);
        }
      )
      .subscribe((status) => {
        console.log("Payments realtime status:", status);
      });

    const collectionsChannel = supabase
      .channel(`payment_collections_${currentHotel.id}`)
      .on(
        "postgres_changes",
        {
          event: "*",
          schema: "public",
          table: "payment_collections",
          filter: `hotel_id=eq.${currentHotel.id}`,
        },
        () => {
          loadData(currentHotel.id);
        }
      )
      .subscribe((status) => {
        console.log(
          "Payment collections realtime status:",
          status
        );
      });

    return () => {
      supabase.removeChannel(paymentsChannel);
      supabase.removeChannel(collectionsChannel);
    };
  }, [currentHotel?.id]);

  async function initPage() {
    setLoading(true);

    try {
      const [hotel, staff] = await Promise.all([
        getCurrentHotel(),
        getCurrentStaff(),
      ]);

      if (!hotel) {
        alert("No hotel assigned");
        return;
      }

      setCurrentHotel(hotel);
      setCurrentStaff(staff || null);

      await loadData(hotel.id);
    } catch (error) {
      console.error(
        "Payments initialization error:",
        error
      );

      alert(
        error.message || "Unable to load payments"
      );
    } finally {
      setLoading(false);
    }
  }

  async function loadData(
    hotelId = currentHotel?.id
  ) {
    if (!hotelId) return;

    const [
      {
        data: paymentData,
        error: paymentError,
      },
      {
        data: collectionData,
        error: collectionError,
      },
    ] = await Promise.all([
      supabase
        .from("payments")
        .select(`
          *,
          guests (
            full_name,
            phone
          ),
          rooms (
            room_number
          )
        `)
        .eq("hotel_id", hotelId)
        .order("created_at", {
          ascending: false,
        }),

      supabase
        .from("payment_collections")
        .select("*")
        .eq("hotel_id", hotelId)
        .order("collected_at", {
          ascending: false,
        }),
    ]);

    if (paymentError) {
      console.error(
        "Payments fetch error:",
        paymentError
      );

      alert(paymentError.message);
      return;
    }

    if (collectionError) {
      console.error(
        "Payment collections fetch error:",
        collectionError
      );

      alert(collectionError.message);
      return;
    }

    setPayments(paymentData || []);
    setCollections(collectionData || []);
  }

  function getPaymentCollections(paymentId) {
    return collections
      .filter(
        (collection) =>
          String(collection.payment_id) ===
          String(paymentId)
      )
      .sort(
        (first, second) =>
          new Date(
            second.collected_at ||
              second.created_at ||
              0
          ).getTime() -
          new Date(
            first.collected_at ||
              first.created_at ||
              0
          ).getTime()
      );
  }

  function getCollectedAmount(payment) {
    const paymentCollections =
      getPaymentCollections(payment.id);

    const collectionTotal =
      paymentCollections.reduce(
        (sum, collection) =>
          sum + Number(collection.amount || 0),
        0
      );

    /*
     * Backward compatibility:
     * Older payment records may already be marked paid
     * before payment_collections was introduced.
     */
    if (
      collectionTotal === 0 &&
      payment.payment_status === "paid"
    ) {
      return Number(payment.amount || 0);
    }

    return collectionTotal;
  }

  function getRemainingAmount(payment) {
    return Math.max(
      0,
      Number(payment.amount || 0) -
        getCollectedAmount(payment)
    );
  }

  function getDerivedStatus(payment) {
    const totalAmount = Number(
      payment.amount || 0
    );

    const collectedAmount =
      getCollectedAmount(payment);

    if (collectedAmount <= 0) {
      return "pending";
    }

    if (collectedAmount < totalAmount) {
      return "partial";
    }

    return "paid";
  }

  function resetCollectionForm() {
    setCollectingPaymentId(null);
    setCollectionAmount("");
    setPaymentMethod("cash");
    setTransactionReference("");
    setPaymentNotes("");
  }

  function openCollectionModal(payment) {
    const remaining =
      getRemainingAmount(payment);

    if (remaining <= 0) {
      alert(
        "This payment has already been fully paid."
      );
      return;
    }

    setCollectingPaymentId(payment.id);
    setCollectionAmount(String(remaining));
    setPaymentMethod("cash");
    setTransactionReference("");
    setPaymentNotes("");
  }

  function closeCollectionModal() {
    if (saving) return;
    resetCollectionForm();
  }

  async function collectPayment() {
    const payment = payments.find(
      (item) =>
        String(item.id) ===
        String(collectingPaymentId)
    );

    if (!payment || !currentHotel?.id) {
      return;
    }

    const amount = Number(collectionAmount);

    const remainingBeforeCollection =
      getRemainingAmount(payment);

    if (
      !Number.isFinite(amount) ||
      amount <= 0
    ) {
      alert(
        "Please enter a valid collection amount."
      );
      return;
    }

    if (amount > remainingBeforeCollection) {
      alert(
        `Collection amount cannot exceed the pending balance of ₹${remainingBeforeCollection}.`
      );
      return;
    }

    const referenceRequiredMethods = [
      "upi",
      "card",
      "bank_transfer",
    ];

    if (
      referenceRequiredMethods.includes(
        paymentMethod
      ) &&
      !transactionReference.trim()
    ) {
      alert(
        "Please enter a transaction or reference number."
      );
      return;
    }

    try {
      setSaving(true);

      const collectedAt =
        new Date().toISOString();

      const { error: collectionError } =
        await supabase
          .from("payment_collections")
          .insert([
            {
              hotel_id: currentHotel.id,
              payment_id: payment.id,
              guest_id:
                payment.guest_id || null,
              room_id: payment.room_id || null,
              amount,
              payment_method: paymentMethod,
              transaction_reference:
                transactionReference.trim() ||
                null,
              notes:
                paymentNotes.trim() || null,
              collected_by:
                currentStaff?.id || null,
              collected_at: collectedAt,
            },
          ]);

      if (collectionError) {
        throw collectionError;
      }

      const totalCollectedAfter =
        getCollectedAmount(payment) + amount;

      const totalBilledAmount = Number(
        payment.amount || 0
      );

      const newStatus =
        totalCollectedAfter >= totalBilledAmount
          ? "paid"
          : "partial";

      const paymentUpdate = {
        payment_status: newStatus,
        payment_method: paymentMethod,
        transaction_reference:
          transactionReference.trim() || null,
        payment_notes:
          paymentNotes.trim() || null,
        collected_by:
          currentStaff?.id || null,
      };

      if (newStatus === "paid") {
        paymentUpdate.paid_at = collectedAt;
      } else {
        paymentUpdate.paid_at = null;
      }

      const { error: paymentUpdateError } =
        await supabase
          .from("payments")
          .update(paymentUpdate)
          .eq("id", payment.id)
          .eq(
            "hotel_id",
            currentHotel.id
          );

      if (paymentUpdateError) {
        throw paymentUpdateError;
      }

      alert(
        newStatus === "paid"
          ? "Payment collected in full."
          : "Partial payment recorded successfully."
      );

      resetCollectionForm();
      await loadData(currentHotel.id);
    } catch (error) {
      console.error(
        "Collect payment error:",
        error
      );

      alert(
        error.message ||
          "Unable to record payment"
      );
    } finally {
      setSaving(false);
    }
  }

  const paymentRows = useMemo(
    () =>
      payments.map((payment) => {
        const collectedAmount =
          getCollectedAmount(payment);

        const remainingAmount = Math.max(
          0,
          Number(payment.amount || 0) -
            collectedAmount
        );

        return {
          ...payment,
          collectedAmount,
          remainingAmount,
          derivedStatus:
            getDerivedStatus(payment),
        };
      }),
    [payments, collections]
  );

  const totalBilled = paymentRows.reduce(
    (sum, payment) =>
      sum + Number(payment.amount || 0),
    0
  );

  const totalCollected = paymentRows.reduce(
    (sum, payment) =>
      sum +
      Number(payment.collectedAmount || 0),
    0
  );

  const pendingRevenue = paymentRows.reduce(
    (sum, payment) =>
      sum +
      Number(payment.remainingAmount || 0),
    0
  );

  const fullyPaidCount = paymentRows.filter(
    (payment) =>
      payment.derivedStatus === "paid"
  ).length;

  const partialCount = paymentRows.filter(
    (payment) =>
      payment.derivedStatus === "partial"
  ).length;

  const pendingCount = paymentRows.filter(
    (payment) =>
      payment.derivedStatus === "pending"
  ).length;

  const selectedPayment = payments.find(
    (payment) =>
      String(payment.id) ===
      String(collectingPaymentId)
  );

  if (loading) {
    return (
      <div style={page}>
        Loading payments...
      </div>
    );
  }

  return (
    <div style={page}>
      <div style={header}>
        <div>
          <p style={kicker}>
            Billing Operations
          </p>

          <h1 style={title}>Payments</h1>

          <p style={hotelName}>
            {currentHotel?.hotel_name ||
              "Hotel"}{" "}
            · Collect cash, UPI, card,
            partial and split payments.
          </p>
        </div>

        <button
          type="button"
          style={refreshButton}
          onClick={() =>
            loadData(currentHotel?.id)
          }
        >
          Refresh
        </button>
      </div>

      <div style={statsGrid}>
        <StatCard
          title="Total Billed"
          value={`₹${totalBilled}`}
        />

        <StatCard
          title="Total Collected"
          value={`₹${totalCollected}`}
        />

        <StatCard
          title="Pending Balance"
          value={`₹${pendingRevenue}`}
        />

        <StatCard
          title="Fully Paid"
          value={fullyPaidCount}
        />

        <StatCard
          title="Partial Payments"
          value={partialCount}
        />

        <StatCard
          title="Pending Payments"
          value={pendingCount}
        />

        <StatCard
          title="Transactions"
          value={collections.length}
        />
      </div>

      <div style={tableCard}>
        {paymentRows.length === 0 ? (
          <div style={emptyState}>
            <h3>No payments found</h3>

            <p>
              Check-in and billing records
              will appear here.
            </p>
          </div>
        ) : (
          <table style={table}>
            <thead>
              <tr>
                <th style={th}>Room</th>
                <th style={th}>Guest</th>
                <th style={th}>Type</th>
                <th style={th}>Billed</th>
                <th style={th}>
                  Collected
                </th>
                <th style={th}>Balance</th>
                <th style={th}>Status</th>
                <th style={th}>
                  Latest Method
                </th>
                <th style={th}>
                  Reference
                </th>
                <th style={th}>Date</th>
                <th style={th}>History</th>
                <th style={th}>Action</th>
              </tr>
            </thead>

            <tbody>
              {paymentRows.map((payment) => {
                const paymentCollections =
                  getPaymentCollections(
                    payment.id
                  );

                const isExpanded =
                  String(expandedPaymentId) ===
                  String(payment.id);

                return (
                  <Fragment key={payment.id}>
                    <tr>
                      <td style={td}>
                        Room{" "}
                        {payment.rooms
                          ?.room_number || "-"}
                      </td>

                      <td style={td}>
                        <strong>
                          {payment.guests
                            ?.full_name || "-"}
                        </strong>

                        <small style={subText}>
                          {payment.guests
                            ?.phone || ""}
                        </small>
                      </td>

                      <td style={td}>
                        {formatLabel(
                          payment.payment_type ||
                            "payment"
                        )}
                      </td>

                      <td style={td}>
                        ₹
                        {Number(
                          payment.amount || 0
                        )}
                      </td>

                      <td style={td}>
                        ₹
                        {
                          payment.collectedAmount
                        }
                      </td>

                      <td style={td}>
                        ₹
                        {
                          payment.remainingAmount
                        }
                      </td>

                      <td style={td}>
                        <span
                          style={statusBadge(
                            payment.derivedStatus
                          )}
                        >
                          {formatLabel(
                            payment.derivedStatus
                          )}
                        </span>
                      </td>

                      <td style={td}>
                        {payment
                          .payment_method
                          ? formatLabel(
                              payment.payment_method
                            )
                          : "-"}
                      </td>

                      <td style={td}>
                        {payment.transaction_reference ||
                          "-"}
                      </td>

                      <td style={td}>
                        {payment.created_at
                          ? new Date(
                              payment.created_at
                            ).toLocaleString(
                              "en-IN"
                            )
                          : "-"}
                      </td>

                      <td style={td}>
                        {paymentCollections.length >
                        0 ? (
                          <button
                            type="button"
                            style={
                              historyButton
                            }
                            onClick={() =>
                              setExpandedPaymentId(
                                isExpanded
                                  ? null
                                  : payment.id
                              )
                            }
                          >
                            {isExpanded
                              ? "Hide History"
                              : `View History (${paymentCollections.length})`}
                          </button>
                        ) : payment.payment_status ===
                          "paid" ? (
                          <span
                            style={
                              legacyPaidText
                            }
                          >
                            Legacy paid record
                          </span>
                        ) : (
                          <span
                            style={
                              noHistoryText
                            }
                          >
                            No collections
                          </span>
                        )}
                      </td>

                      <td style={td}>
                        {payment.remainingAmount >
                        0 ? (
                          <button
                            type="button"
                            style={button}
                            onClick={() =>
                              openCollectionModal(
                                payment
                              )
                            }
                          >
                            Collect Payment
                          </button>
                        ) : (
                          <span
                            style={paidText}
                          >
                            Paid
                          </span>
                        )}
                      </td>
                    </tr>

                    {isExpanded && (
                      <tr>
                        <td
                          colSpan={12}
                          style={historyCell}
                        >
                          <div
                            style={
                              historyPanel
                            }
                          >
                            <div
                              style={
                                historyHeader
                              }
                            >
                              <div>
                                <strong>
                                  Payment
                                  Collection
                                  History
                                </strong>

                                <p
                                  style={
                                    historySubtitle
                                  }
                                >
                                  Room{" "}
                                  {payment.rooms
                                    ?.room_number ||
                                    "-"}{" "}
                                  ·{" "}
                                  {payment.guests
                                    ?.full_name ||
                                    "Guest"}
                                </p>
                              </div>

                              <span
                                style={
                                  historySummary
                                }
                              >
                                {
                                  paymentCollections.length
                                }{" "}
                                transaction(s)
                              </span>
                            </div>

                            <div
                              style={
                                historyList
                              }
                            >
                              {paymentCollections.map(
                                (
                                  collection,
                                  index
                                ) => (
                                  <div
                                    key={
                                      collection.id
                                    }
                                    style={
                                      historyItem
                                    }
                                  >
                                    <div
                                      style={
                                        historyAmountBlock
                                      }
                                    >
                                      <span
                                        style={
                                          historyTransactionNumber
                                        }
                                      >
                                        Transaction{" "}
                                        {paymentCollections.length -
                                          index}
                                      </span>

                                      <strong
                                        style={
                                          historyAmount
                                        }
                                      >
                                        ₹
                                        {Number(
                                          collection.amount ||
                                            0
                                        )}
                                      </strong>

                                      <span
                                        style={
                                          historyMethod
                                        }
                                      >
                                        {formatLabel(
                                          collection.payment_method
                                        )}
                                      </span>
                                    </div>

                                    <div
                                      style={
                                        historyDetails
                                      }
                                    >
                                      <span>
                                        <strong>
                                          Collected:
                                        </strong>{" "}
                                        {collection.collected_at
                                          ? new Date(
                                              collection.collected_at
                                            ).toLocaleString(
                                              "en-IN"
                                            )
                                          : "-"}
                                      </span>

                                      <span>
                                        <strong>
                                          Reference:
                                        </strong>{" "}
                                        {collection.transaction_reference ||
                                          "-"}
                                      </span>

                                      <span>
                                        <strong>
                                          Notes:
                                        </strong>{" "}
                                        {collection.notes ||
                                          "-"}
                                      </span>
                                    </div>
                                  </div>
                                )
                              )}
                            </div>
                          </div>
                        </td>
                      </tr>
                    )}
                  </Fragment>
                );
              })}
            </tbody>
          </table>
        )}
      </div>

      {collectingPaymentId &&
        selectedPayment && (
          <div style={modalOverlay}>
            <div style={modal}>
              <p style={modalKicker}>
                PAYMENT COLLECTION
              </p>

              <h2 style={modalTitle}>
                Collect Payment
              </h2>

              <p style={modalSubtitle}>
                {selectedPayment.guests
                  ?.full_name || "Guest"}{" "}
                · Room{" "}
                {selectedPayment.rooms
                  ?.room_number || "-"}
              </p>

              <div style={balanceCard}>
                <span>Pending Balance</span>

                <strong>
                  ₹
                  {getRemainingAmount(
                    selectedPayment
                  )}
                </strong>
              </div>

              <label style={label}>
                Amount Received
              </label>

              <input
                style={input}
                type="number"
                min="1"
                max={getRemainingAmount(
                  selectedPayment
                )}
                value={collectionAmount}
                onChange={(event) =>
                  setCollectionAmount(
                    event.target.value
                  )
                }
                placeholder="Enter amount"
              />

              <label style={label}>
                Payment Method
              </label>

              <select
                style={input}
                value={paymentMethod}
                onChange={(event) =>
                  setPaymentMethod(
                    event.target.value
                  )
                }
              >
                <option value="cash">
                  Cash
                </option>

                <option value="upi">
                  UPI
                </option>

                <option value="card">
                  Card
                </option>

                <option value="bank_transfer">
                  Bank Transfer
                </option>

                <option value="other">
                  Other
                </option>
              </select>

              <label style={label}>
                Transaction / Reference
                Number
              </label>

              <input
                style={input}
                value={
                  transactionReference
                }
                onChange={(event) =>
                  setTransactionReference(
                    event.target.value
                  )
                }
                placeholder={
                  paymentMethod === "cash"
                    ? "Optional for cash"
                    : "Required"
                }
              />

              <label style={label}>
                Notes
              </label>

              <textarea
                style={{
                  ...input,
                  minHeight: "90px",
                  resize: "vertical",
                }}
                value={paymentNotes}
                onChange={(event) =>
                  setPaymentNotes(
                    event.target.value
                  )
                }
                placeholder="Optional payment notes"
              />

              <div style={modalActions}>
                <button
                  type="button"
                  style={cancelButton}
                  disabled={saving}
                  onClick={
                    closeCollectionModal
                  }
                >
                  Cancel
                </button>

                <button
                  type="button"
                  style={saveButton}
                  disabled={saving}
                  onClick={collectPayment}
                >
                  {saving
                    ? "Saving..."
                    : "Confirm Collection"}
                </button>
              </div>
            </div>
          </div>
        )}
    </div>
  );
}

function StatCard({ title, value }) {
  return (
    <div style={statCard}>
      <span style={statTitle}>
        {title}
      </span>

      <strong style={statValue}>
        {value}
      </strong>
    </div>
  );
}

function formatLabel(value) {
  return String(value || "")
    .replaceAll("_", " ")
    .replace(/\b\w/g, (letter) =>
      letter.toUpperCase()
    );
}

const statusBadge = (status) => ({
  display: "inline-block",
  padding: "7px 11px",
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

  fontSize: "12px",
  fontWeight: 800,
  whiteSpace: "nowrap",
});

const page = {
  padding: "30px",
  color: "#fff",
};

const header = {
  display: "flex",
  alignItems: "center",
  justifyContent: "space-between",
  gap: "20px",
  marginBottom: "25px",
};

const kicker = {
  margin: "0 0 7px",
  color: "#d4af37",
  fontSize: "12px",
  fontWeight: 900,
  letterSpacing: "2px",
};

const hotelName = {
  color: "#aaa",
  margin: 0,
};

const title = {
  fontSize: "42px",
  margin: "0 0 8px",
};

const refreshButton = {
  background: "#d4af37",
  color: "#000",
  border: "none",
  padding: "11px 17px",
  borderRadius: "9px",
  cursor: "pointer",
  fontWeight: 800,
};

const statsGrid = {
  display: "grid",
  gridTemplateColumns:
    "repeat(auto-fit,minmax(170px,1fr))",
  gap: "18px",
  marginBottom: "25px",
};

const statCard = {
  background: "#0f0f0f",
  border: "1px solid #222",
  borderRadius: "15px",
  padding: "20px",
};

const statTitle = {
  display: "block",
  color: "#d4af37",
  fontSize: "12px",
  marginBottom: "9px",
};

const statValue = {
  fontSize: "27px",
};

const tableCard = {
  background: "#0f0f0f",
  border: "1px solid #222",
  borderRadius: "15px",
  overflowX: "auto",
};

const table = {
  width: "100%",
  minWidth: "1600px",
  borderCollapse: "collapse",
};

const th = {
  padding: "15px",
  textAlign: "left",
  borderBottom: "1px solid #222",
  color: "#d4af37",
  whiteSpace: "nowrap",
};

const td = {
  padding: "15px",
  borderBottom: "1px solid #1f1f1f",
  verticalAlign: "top",
};

const subText = {
  display: "block",
  marginTop: "5px",
  color: "#888",
};

const button = {
  background: "#d4af37",
  color: "#000",
  border: "none",
  padding: "9px 13px",
  borderRadius: "8px",
  cursor: "pointer",
  fontWeight: 800,
};

const paidText = {
  color: "#2ecc71",
  fontWeight: 800,
};

const legacyPaidText = {
  color: "#888",
  fontSize: "11px",
};

const emptyState = {
  padding: "45px",
  color: "#888",
  textAlign: "center",
};

const historyButton = {
  padding: "8px 12px",
  border:
    "1px solid rgba(212,175,55,.35)",
  borderRadius: "8px",
  background:
    "rgba(212,175,55,.08)",
  color: "#d4af37",
  fontWeight: 800,
  cursor: "pointer",
  whiteSpace: "nowrap",
};

const noHistoryText = {
  color: "#777",
  fontSize: "12px",
};

const historyCell = {
  padding: "0 15px 15px",
  borderBottom: "1px solid #1f1f1f",
};

const historyPanel = {
  padding: "18px",
  border: "1px solid #292929",
  borderRadius: "13px",
  background: "#090909",
};

const historyHeader = {
  display: "flex",
  alignItems: "center",
  justifyContent: "space-between",
  gap: "15px",
  marginBottom: "14px",
};

const historySubtitle = {
  margin: "5px 0 0",
  color: "#888",
  fontSize: "12px",
};

const historySummary = {
  color: "#d4af37",
  fontSize: "12px",
  fontWeight: 800,
};

const historyList = {
  display: "grid",
  gap: "10px",
};

const historyItem = {
  display: "flex",
  alignItems: "center",
  justifyContent: "space-between",
  gap: "20px",
  padding: "14px",
  border: "1px solid #242424",
  borderRadius: "10px",
  background: "#101010",
};

const historyAmountBlock = {
  minWidth: "130px",
};

const historyTransactionNumber = {
  display: "block",
  marginBottom: "5px",
  color: "#777",
  fontSize: "10px",
  fontWeight: 700,
  textTransform: "uppercase",
};

const historyAmount = {
  display: "block",
  fontSize: "20px",
};

const historyMethod = {
  display: "block",
  marginTop: "4px",
  color: "#d4af37",
  fontSize: "11px",
  fontWeight: 700,
};

const historyDetails = {
  display: "grid",
  gap: "5px",
  color: "#999",
  fontSize: "11px",
  textAlign: "right",
};

const modalOverlay = {
  position: "fixed",
  inset: 0,
  zIndex: 9999,
  display: "flex",
  alignItems: "center",
  justifyContent: "center",
  padding: "20px",
  background: "rgba(0,0,0,.78)",
};

const modal = {
  width: "100%",
  maxWidth: "500px",
  maxHeight: "90vh",
  overflowY: "auto",
  padding: "27px",
  border: "1px solid #333",
  borderRadius: "18px",
  background: "#0f0f0f",
  boxShadow:
    "0 25px 70px rgba(0,0,0,.55)",
};

const modalKicker = {
  margin: "0 0 7px",
  color: "#d4af37",
  fontSize: "11px",
  fontWeight: 900,
  letterSpacing: "2px",
};

const modalTitle = {
  margin: "0 0 5px",
  fontSize: "28px",
};

const modalSubtitle = {
  margin: "0 0 20px",
  color: "#999",
};

const balanceCard = {
  display: "flex",
  alignItems: "center",
  justifyContent: "space-between",
  gap: "15px",
  marginBottom: "20px",
  padding: "15px",
  border:
    "1px solid rgba(212,175,55,.3)",
  borderRadius: "12px",
  background:
    "rgba(212,175,55,.07)",
};

const label = {
  display: "block",
  marginBottom: "7px",
  color: "#d4af37",
  fontSize: "12px",
  fontWeight: 800,
};

const input = {
  width: "100%",
  boxSizing: "border-box",
  marginBottom: "15px",
  padding: "12px",
  border: "1px solid #333",
  borderRadius: "10px",
  outline: "none",
  background: "#090909",
  color: "#fff",
};

const modalActions = {
  display: "flex",
  justifyContent: "flex-end",
  gap: "10px",
  marginTop: "5px",
};

const cancelButton = {
  padding: "11px 15px",
  border: "1px solid #444",
  borderRadius: "9px",
  background: "#1a1a1a",
  color: "#fff",
  cursor: "pointer",
};

const saveButton = {
  padding: "11px 15px",
  border: "none",
  borderRadius: "9px",
  background: "#d4af37",
  color: "#000",
  fontWeight: 800,
  cursor: "pointer",
};