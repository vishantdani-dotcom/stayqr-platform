import { useEffect, useMemo, useState } from "react";
import {
  GUEST_CONSENT_PURPOSES,
  getGuestCommunicationAudience,
  prepareManualWhatsAppContact,
  setGuestChannelSuppression,
  setGuestConsent,
} from "../../lib/guestCompliance";
import "./GuestCommunications.css";

function purposeToConsent(purpose) {
  return purpose === "marketing"
    ? GUEST_CONSENT_PURPOSES.WHATSAPP_MARKETING
    : GUEST_CONSENT_PURPOSES.WHATSAPP_TRANSACTIONAL;
}

export default function GuestCommunications({ currentHotel, onNotice }) {
  const [loading, setLoading] = useState(true);
  const [rows, setRows] = useState([]);
  const [search, setSearch] = useState("");
  const [consentFilter, setConsentFilter] = useState("all");
  const [busyId, setBusyId] = useState(null);

  async function loadAudience() {
    if (!currentHotel?.id) return;
    setLoading(true);
    try {
      setRows(await getGuestCommunicationAudience(currentHotel.id));
    } catch (error) {
      console.error("Guest contact load error:", error);
      onNotice?.("error", error.message || "Unable to load guest contact preferences.");
    } finally {
      setLoading(false);
    }
  }

  useEffect(() => {
    void loadAudience();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [currentHotel?.id]);

  const visibleRows = useMemo(() => {
    const term = search.trim().toLowerCase();
    return rows.filter((row) => {
      const matchesSearch = !term || [row.full_name, row.phone_e164, row.active_room]
        .filter(Boolean).join(" ").toLowerCase().includes(term);
      if (!matchesSearch) return false;
      if (consentFilter === "transactional") return row.transactional_consent && !row.suppressed;
      if (consentFilter === "marketing") return row.marketing_consent && !row.suppressed;
      if (consentFilter === "suppressed") return row.suppressed;
      if (consentFilter === "no-consent") return !row.transactional_consent && !row.marketing_consent;
      return true;
    });
  }, [rows, search, consentFilter]);

  const metrics = useMemo(() => ({
    guests: rows.length,
    transactional: rows.filter((row) => row.transactional_consent && !row.suppressed).length,
    marketing: rows.filter((row) => row.marketing_consent && !row.suppressed).length,
    suppressed: rows.filter((row) => row.suppressed).length,
  }), [rows]);

  async function changeConsent(row, purpose, grant) {
    if (grant && !window.confirm(`Confirm that ${row.full_name || "this guest"} explicitly consented to receive ${purpose} WhatsApp messages from this hotel.`)) return;
    setBusyId(`${row.guest_id}:${purpose}`);
    try {
      await setGuestConsent({
        hotelId: currentHotel.id,
        guestId: row.guest_id,
        purpose: purposeToConsent(purpose),
        status: grant ? "granted" : "revoked",
        source: "staff_recorded",
        evidence: {
          channel: "whatsapp",
          purpose,
          statement: grant ? "Guest consent recorded by authorized hotel staff." : "Guest consent revoked by authorized hotel staff.",
        },
      });
      onNotice?.("success", `WhatsApp ${purpose} consent ${grant ? "recorded" : "revoked"}.`);
      await loadAudience();
    } catch (error) {
      onNotice?.("error", error.message || "Unable to update consent.");
    } finally {
      setBusyId(null);
    }
  }

  async function toggleSuppression(row) {
    setBusyId(`${row.guest_id}:suppression`);
    try {
      await setGuestChannelSuppression({
        hotelId: currentHotel.id,
        guestId: row.guest_id,
        active: !row.suppressed,
        reason: row.suppressed ? "staff_unblock" : "guest_opt_out",
      });
      onNotice?.("success", row.suppressed ? "WhatsApp suppression removed." : "Guest opted out of WhatsApp.");
      await loadAudience();
    } catch (error) {
      onNotice?.("error", error.message || "Unable to update suppression.");
    } finally {
      setBusyId(null);
    }
  }

  async function openManualWhatsApp(row) {
    setBusyId(`${row.guest_id}:manual`);
    try {
      const prepared = await prepareManualWhatsAppContact({
        hotelId: currentHotel.id,
        guestId: row.guest_id,
        purpose: "transactional",
      });
      const message = `Hello ${prepared.guest_name || "Guest"}, this is ${currentHotel?.hotel_name || currentHotel?.name || "your hotel"}. We would like to share an update regarding your stay.`;
      window.open(
        `https://wa.me/${String(prepared.phone_e164 || "").replace(/\D/g, "")}?text=${encodeURIComponent(message)}`,
        "_blank",
        "noopener,noreferrer"
      );
    } catch (error) {
      onNotice?.("error", error.message || "WhatsApp contact is not permitted for this guest.");
    } finally {
      setBusyId(null);
    }
  }

  return (
    <div className="guest-comms-shell">
      <section className="guest-comms-hero">
        <div>
          <p className="guest-directory-kicker">CONTACT &amp; CONSENT</p>
          <h2>Guest contact preferences</h2>
          <p>Manage WhatsApp consent, opt-outs and safe one-to-one contact from the hotel team.</p>
        </div>
        <button type="button" className="secondary" onClick={loadAudience}>Refresh</button>
      </section>

      <div className="guest-comms-warning">
        <strong>Automated WhatsApp campaigns — upcoming</strong>
        <span>Bulk/template automation is intentionally on hold for launch. StayQR keeps the consent and suppression foundation ready while hotels can use consent-aware manual WhatsApp contact.</span>
      </div>

      <div className="guest-comms-metrics">
        <Metric label="Guests" value={metrics.guests} />
        <Metric label="Stay-update consent" value={metrics.transactional} />
        <Metric label="Marketing consent" value={metrics.marketing} />
        <Metric label="Opted out" value={metrics.suppressed} />
      </div>

      <section className="guest-comms-card">
        <div className="guest-comms-toolbar">
          <input value={search} onChange={(event) => setSearch(event.target.value)} placeholder="Search guest, phone or room…" />
          <select value={consentFilter} onChange={(event) => setConsentFilter(event.target.value)}>
            <option value="all">All guests</option>
            <option value="transactional">Stay-update consent</option>
            <option value="marketing">Marketing consent</option>
            <option value="no-consent">No WhatsApp consent</option>
            <option value="suppressed">Opted out</option>
          </select>
        </div>

        {loading ? (
          <p className="guest-comms-empty">Loading guest contact preferences…</p>
        ) : visibleRows.length === 0 ? (
          <p className="guest-comms-empty">No guests match the current filters.</p>
        ) : (
          <div className="guest-comms-table-wrap">
            <table className="guest-comms-table">
              <thead><tr><th>Guest</th><th>Phone</th><th>Room</th><th>Consent</th><th>Opt-out</th><th>Action</th></tr></thead>
              <tbody>
                {visibleRows.map((row) => (
                  <tr key={row.guest_id}>
                    <td><strong>{row.full_name}</strong></td>
                    <td>{row.phone_e164 || "Missing"}</td>
                    <td>{row.active_room || "—"}</td>
                    <td>
                      <div className="guest-comms-pills">
                        <button type="button" className={row.transactional_consent ? "pill on" : "pill"} disabled={busyId === `${row.guest_id}:transactional`} onClick={() => changeConsent(row, "transactional", !row.transactional_consent)}>
                          Stay updates {row.transactional_consent ? "✓" : "+"}
                        </button>
                        <button type="button" className={row.marketing_consent ? "pill on" : "pill"} disabled={busyId === `${row.guest_id}:marketing`} onClick={() => changeConsent(row, "marketing", !row.marketing_consent)}>
                          Marketing {row.marketing_consent ? "✓" : "+"}
                        </button>
                      </div>
                    </td>
                    <td>
                      <button type="button" className={row.suppressed ? "danger" : "secondary"} disabled={busyId === `${row.guest_id}:suppression`} onClick={() => toggleSuppression(row)}>
                        {row.suppressed ? "Restore" : "Opt out"}
                      </button>
                    </td>
                    <td>
                      <button type="button" disabled={!row.transactional_consent || row.suppressed || !row.phone_e164 || busyId === `${row.guest_id}:manual`} onClick={() => openManualWhatsApp(row)}>
                        Open WhatsApp
                      </button>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </section>
    </div>
  );
}

function Metric({ label, value }) {
  return <div className="guest-comms-metric"><span>{label}</span><strong>{value}</strong></div>;
}
