import { useEffect, useMemo, useState } from "react";
import { supabase } from "../../lib/supabase";
import {
  GUEST_CONSENT_PURPOSES,
  createGuestWhatsAppCampaign,
  getGuestCommunicationAudience,
  getWhatsAppProviderReadiness,
  prepareManualWhatsAppContact,
  setGuestChannelSuppression,
  setGuestConsent,
  sendWhatsAppCampaignRecipient,
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
  const [campaigns, setCampaigns] = useState([]);
  const [recipients, setRecipients] = useState([]);
  const [providerProfile, setProviderProfile] = useState(null);
  const [templates, setTemplates] = useState([]);
  const [channelSettings, setChannelSettings] = useState(null);
  const [deliveryHealth, setDeliveryHealth] = useState(null);
  const [search, setSearch] = useState("");
  const [consentFilter, setConsentFilter] = useState("all");
  const [selectedIds, setSelectedIds] = useState([]);
  const [busyId, setBusyId] = useState(null);
  const [campaign, setCampaign] = useState({
    name: "",
    purpose: "transactional",
    providerMode: "manual",
    templateName: "",
    templateLanguage: "en",
  });
  const [campaignBusy, setCampaignBusy] = useState(false);
  const [sendingCampaignId, setSendingCampaignId] = useState(null);

  async function loadAudience() {
    if (!currentHotel?.id) return;
    setLoading(true);
    try {
      const [audience, campaignResult, recipientResult, providerReadiness] = await Promise.all([
        getGuestCommunicationAudience(currentHotel.id),
        supabase
          .from("guest_communication_campaigns")
          .select("id, name, purpose, provider_mode, provider_template_name, provider_template_language, status, created_at")
          .eq("hotel_id", currentHotel.id)
          .order("created_at", { ascending: false })
          .limit(20),
        supabase
          .from("guest_communication_recipients")
          .select("id, campaign_id, guest_id, phone_e164, status, provider_message_id, error_code, error_message, attempt_count, last_attempt_at, sent_at, delivered_at, read_at, failed_at, created_at")
          .eq("hotel_id", currentHotel.id)
          .order("created_at", { ascending: false })
          .limit(500),
        getWhatsAppProviderReadiness(currentHotel.id),
      ]);
      if (campaignResult.error) throw campaignResult.error;
      if (recipientResult.error) throw recipientResult.error;
      setRows(audience);
      setCampaigns(campaignResult.data || []);
      setRecipients(recipientResult.data || []);
      setProviderProfile(providerReadiness.profile);
      setTemplates(providerReadiness.templates);
      setChannelSettings(providerReadiness.settings);
      setDeliveryHealth(providerReadiness.health);
    } catch (error) {
      console.error("Guest communications load error:", error);
      onNotice?.("error", error.message || "Unable to load communication audience.");
    } finally {
      setLoading(false);
    }
  }

  useEffect(() => {
    loadAudience();
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

  const approvedTemplates = useMemo(
    () => templates.filter((item) => item.provider_name === "meta_cloud" && item.provider_status === "approved"),
    [templates]
  );

  const selectedTemplate = useMemo(
    () => approvedTemplates.find((item) =>
      item.template_name === campaign.templateName &&
      (item.provider_language || item.locale || "en") === campaign.templateLanguage
    ) || null,
    [approvedTemplates, campaign.templateLanguage, campaign.templateName]
  );

  const metaReady = providerProfile?.status === "active" && approvedTemplates.length > 0 && channelSettings?.channel_enabled === true && deliveryHealth?.circuit_state !== "open";

  async function changeConsent(row, purpose, grant) {
    if (grant && !window.confirm(`Confirm that ${row.full_name || "this guest"} explicitly consented to receive ${purpose} WhatsApp messages from this hotel.`)) {
      return;
    }
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
          statement: grant
            ? "Guest consent recorded by authorized hotel staff."
            : "Guest consent revoked by authorized hotel staff.",
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
    const reason = row.suppressed ? "staff_block" : "guest_opt_out";
    setBusyId(`${row.guest_id}:suppression`);
    try {
      await setGuestChannelSuppression({
        hotelId: currentHotel.id,
        guestId: row.guest_id,
        active: !row.suppressed,
        reason,
      });
      onNotice?.("success", row.suppressed ? "WhatsApp suppression removed." : "Guest opted out of WhatsApp.");
      await loadAudience();
    } catch (error) {
      onNotice?.("error", error.message || "Unable to update suppression.");
    } finally {
      setBusyId(null);
    }
  }

  async function openManualWhatsApp(row, purpose = "transactional") {
    setBusyId(`${row.guest_id}:manual`);
    try {
      const prepared = await prepareManualWhatsAppContact({
        hotelId: currentHotel.id,
        guestId: row.guest_id,
        purpose,
      });
      const message = purpose === "marketing"
        ? `Hello ${prepared.guest_name || "Guest"}, this is ${currentHotel?.hotel_name || currentHotel?.name || "your hotel"}.`
        : `Hello ${prepared.guest_name || "Guest"}, this is ${currentHotel?.hotel_name || currentHotel?.name || "your hotel"}. We would like to share an update regarding your stay.`;
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

  function toggleSelection(guestId) {
    setSelectedIds((current) => current.includes(guestId)
      ? current.filter((id) => id !== guestId)
      : [...current, guestId]);
  }

  async function createCampaign(event) {
    event.preventDefault();
    if (selectedIds.length === 0) {
      onNotice?.("error", "Select at least one guest for the campaign.");
      return;
    }
    if (!campaign.name.trim()) {
      onNotice?.("error", "Campaign name is required.");
      return;
    }
    if (campaign.providerMode === "meta_cloud" && !metaReady) {
      onNotice?.("error", "Meta Cloud is not ready for this hotel. Keep manual mode until an active hotel-owned sender and approved template are configured.");
      return;
    }
    if (campaign.providerMode === "meta_cloud" && !selectedTemplate) {
      onNotice?.("error", "Select a template that has confirmed Meta approval for this hotel.");
      return;
    }

    setCampaignBusy(true);
    try {
      const result = await createGuestWhatsAppCampaign({
        hotelId: currentHotel.id,
        name: campaign.name.trim(),
        purpose: campaign.purpose,
        providerMode: campaign.providerMode,
        templateName: campaign.templateName.trim(),
        templateLanguage: campaign.templateLanguage.trim() || "en",
        guestIds: selectedIds,
      });
      onNotice?.(
        "success",
        `Campaign prepared: ${result?.eligible_count || 0} eligible, ${result?.suppressed_count || 0} suppressed.`
      );
      setSelectedIds([]);
      setCampaign((current) => ({ ...current, name: "" }));
      await loadAudience();
    } catch (error) {
      onNotice?.("error", error.message || "Unable to prepare WhatsApp campaign.");
    } finally {
      setCampaignBusy(false);
    }
  }

  async function sendEligibleCampaign(campaignItem) {
    const eligible = recipients.filter((recipient) =>
      recipient.campaign_id === campaignItem.id && ["eligible", "failed"].includes(recipient.status)
    );
    if (eligible.length === 0) {
      onNotice?.("error", "This campaign has no eligible recipients to send.");
      return;
    }
    if (!window.confirm(`Send approved WhatsApp template to ${eligible.length} eligible recipient(s)? Consent and suppression will be rechecked before every send.`)) return;
    setSendingCampaignId(campaignItem.id);
    let sent = 0;
    let failed = 0;
    try {
      for (const recipient of eligible) {
        try {
          await sendWhatsAppCampaignRecipient({ recipientId: recipient.id });
          sent += 1;
        } catch (error) {
          console.error("WhatsApp recipient send error:", error);
          failed += 1;
        }
      }
      onNotice?.(failed > 0 ? "warning" : "success", `WhatsApp template run finished: ${sent} sent, ${failed} failed or blocked.`);
      await loadAudience();
    } finally {
      setSendingCampaignId(null);
    }
  }

  return (
    <div className="guest-comms-shell">
      <section className="guest-comms-hero">
        <div>
          <p className="guest-directory-kicker">CONSENT & COMMUNICATIONS</p>
          <h2>Guest communications</h2>
          <p>Consent-led WhatsApp audience, suppression, campaign preparation and delivery evidence.</p>
        </div>
        <button type="button" className="secondary" onClick={loadAudience}>Refresh audience</button>
      </section>

      <div className="guest-comms-warning">
        <strong>WhatsApp compliance guard</strong>
        <span>StayQR blocks contact without stored consent or when the guest is suppressed. Automated Meta Cloud sending stays unavailable until this hotel has an active sender profile, a provider-approved template, production credentials and the feature flag.</span>
      </div>

      <div className={`guest-provider-readiness ${metaReady ? "ready" : "manual-only"}`}>
        <div>
          <strong>{metaReady ? "Meta Cloud ready" : "Manual WhatsApp only"}</strong>
          <span>{providerProfile?.status === "active" ? `${providerProfile.sender_display_name || "Hotel sender"} · active sender` : "No active hotel-owned Meta Cloud sender is configured."}</span>
        </div>
        <span>{approvedTemplates.length} provider-approved template(s)</span>
      </div>

      <div className="guest-comms-metrics">
        <Metric label="Guests" value={metrics.guests} />
        <Metric label="Transactional consent" value={metrics.transactional} />
        <Metric label="Marketing consent" value={metrics.marketing} />
        <Metric label="Suppressed" value={metrics.suppressed} />
      </div>

      <section className="guest-comms-card">
        <div className="guest-comms-toolbar">
          <input value={search} onChange={(event) => setSearch(event.target.value)} placeholder="Search guest, phone or room…" />
          <select value={consentFilter} onChange={(event) => setConsentFilter(event.target.value)}>
            <option value="all">All guests</option>
            <option value="transactional">Transactional consent</option>
            <option value="marketing">Marketing consent</option>
            <option value="no-consent">No WhatsApp consent</option>
            <option value="suppressed">Suppressed</option>
          </select>
        </div>

        {loading ? (
          <p className="guest-comms-empty">Loading audience…</p>
        ) : visibleRows.length === 0 ? (
          <p className="guest-comms-empty">No guests match the current filters.</p>
        ) : (
          <div className="guest-comms-table-wrap">
            <table className="guest-comms-table">
              <thead>
                <tr><th>Select</th><th>Guest</th><th>Phone</th><th>Room</th><th>Consent</th><th>Suppression</th><th>Actions</th></tr>
              </thead>
              <tbody>
                {visibleRows.map((row) => (
                  <tr key={row.guest_id}>
                    <td><input type="checkbox" checked={selectedIds.includes(row.guest_id)} onChange={() => toggleSelection(row.guest_id)} /></td>
                    <td><strong>{row.full_name}</strong></td>
                    <td>{row.phone_e164 || "Invalid / missing"}</td>
                    <td>{row.active_room || "—"}</td>
                    <td>
                      <div className="guest-comms-pills">
                        <button type="button" className={row.transactional_consent ? "pill on" : "pill"} disabled={busyId === `${row.guest_id}:transactional`} onClick={() => changeConsent(row, "transactional", !row.transactional_consent)}>
                          Transactional {row.transactional_consent ? "✓" : "+"}
                        </button>
                        <button type="button" className={row.marketing_consent ? "pill on" : "pill"} disabled={busyId === `${row.guest_id}:marketing`} onClick={() => changeConsent(row, "marketing", !row.marketing_consent)}>
                          Marketing {row.marketing_consent ? "✓" : "+"}
                        </button>
                      </div>
                    </td>
                    <td>
                      <button type="button" className={row.suppressed ? "danger" : "secondary"} disabled={busyId === `${row.guest_id}:suppression`} onClick={() => toggleSuppression(row)}>
                        {row.suppressed ? "Unsuppress" : "Opt out"}
                      </button>
                      {row.suppression_reason && <small className="guest-comms-reason">{row.suppression_reason.replaceAll("_", " ")}</small>}
                    </td>
                    <td>
                      <button type="button" disabled={!row.transactional_consent || row.suppressed || !row.phone_e164 || busyId === `${row.guest_id}:manual`} onClick={() => openManualWhatsApp(row, "transactional")}>WhatsApp</button>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </section>

      <form className="guest-comms-card guest-campaign-builder" onSubmit={createCampaign}>
        <div>
          <p className="guest-directory-kicker">CONTROLLED CAMPAIGN</p>
          <h3>Prepare WhatsApp campaign</h3>
          <p>{selectedIds.length} guest(s) selected. Consent and suppression are rechecked server-side for every recipient.</p>
        </div>
        <div className="guest-campaign-grid">
          <label>Campaign name<input value={campaign.name} onChange={(event) => setCampaign((current) => ({ ...current, name: event.target.value }))} placeholder="Arrival updates" /></label>
          <label>Purpose<select value={campaign.purpose} onChange={(event) => setCampaign((current) => ({ ...current, purpose: event.target.value }))}><option value="transactional">Transactional</option><option value="marketing">Marketing</option></select></label>
          <label>Delivery mode<select value={campaign.providerMode} onChange={(event) => {
            const providerMode = event.target.value;
            const first = providerMode === "meta_cloud" ? approvedTemplates[0] : null;
            setCampaign((current) => ({
              ...current,
              providerMode,
              templateName: first?.template_name || "",
              templateLanguage: first?.provider_language || first?.locale || "en",
            }));
          }}><option value="manual">Manual / click-to-chat</option><option value="meta_cloud" disabled={!metaReady}>Meta Cloud approved template</option></select></label>
          {campaign.providerMode === "meta_cloud" ? (
            <>
              <label>Approved template<select value={`${campaign.templateName}::${campaign.templateLanguage}`} onChange={(event) => {
                const chosen = approvedTemplates.find((item) => `${item.template_name}::${item.provider_language || item.locale || "en"}` === event.target.value);
                setCampaign((current) => ({ ...current, templateName: chosen?.template_name || "", templateLanguage: chosen?.provider_language || chosen?.locale || "en" }));
              }}>{approvedTemplates.map((item) => <option key={item.id} value={`${item.template_name}::${item.provider_language || item.locale || "en"}`}>{item.template_name} · {item.provider_language || item.locale || "en"}</option>)}</select></label>
              <div className="guest-template-preview wide" aria-live="polite">
                <span>Approved template preview</span>
                <strong>{selectedTemplate?.template_name || "No approved template"}</strong>
                <p>{selectedTemplate?.body_template || "Meta Cloud delivery remains disabled until a provider-approved template is available."}</p>
              </div>
            </>
          ) : (
            <div className="guest-template-preview wide">
              <span>Manual fallback</span>
              <p>One recipient at a time opens in WhatsApp after StayQR rechecks consent, suppression and phone validity. No bulk send is claimed.</p>
            </div>
          )}
        </div>
        <button type="submit" disabled={campaignBusy || selectedIds.length === 0}>{campaignBusy ? "Preparing…" : "Prepare campaign"}</button>
      </form>

      <section className="guest-comms-card">
        <div>
          <p className="guest-directory-kicker">DELIVERY EVIDENCE</p>
          <h3>Recent WhatsApp campaigns</h3>
          <p className="guest-muted">Recipient state is persisted from preparation through provider sent, delivered, read or failed events.</p>
        </div>
        {campaigns.length === 0 ? (
          <p className="guest-comms-empty">No campaigns prepared yet.</p>
        ) : (
          <div className="guest-campaign-list">
            {campaigns.map((item) => {
              const campaignRecipients = recipients.filter((recipient) => recipient.campaign_id === item.id);
              const counts = campaignRecipients.reduce((map, recipient) => {
                map[recipient.status] = (map[recipient.status] || 0) + 1;
                return map;
              }, {});
              return (
                <article key={item.id}>
                  <div className="guest-campaign-head">
                    <div><strong>{item.name}</strong><small>{item.purpose} · {item.provider_mode === "meta_cloud" ? `Meta template ${item.provider_template_name || "—"}` : "manual click-to-chat"}</small></div>
                    <span className="guest-chip neutral">{item.status}</span>
                  </div>
                  <div className="guest-campaign-counts">
                    {["eligible", "suppressed", "queued", "sent", "delivered", "read", "failed"].map((status) => (
                      <span key={status}><b>{counts[status] || 0}</b> {status}</span>
                    ))}
                  </div>
                  {item.provider_mode === "meta_cloud" && (
                    <button type="button" className="secondary" disabled={sendingCampaignId === item.id || !campaignRecipients.some((recipient) => ["eligible", "failed"].includes(recipient.status))} onClick={() => sendEligibleCampaign(item)}>
                      {sendingCampaignId === item.id ? "Sending approved template…" : "Send eligible approved template"}
                    </button>
                  )}
                  {campaignRecipients.some((recipient) => recipient.attempt_count > 0) && (
                    <small className="guest-campaign-attempts">Provider attempts: {campaignRecipients.reduce((sum, recipient) => sum + Number(recipient.attempt_count || 0), 0)}</small>
                  )}
                  {campaignRecipients.some((recipient) => recipient.error_message) && (
                    <small className="guest-campaign-error">{campaignRecipients.find((recipient) => recipient.error_message)?.error_message}</small>
                  )}
                </article>
              );
            })}
          </div>
        )}
      </section>
    </div>
  );
}

function Metric({ label, value }) {
  return <div className="guest-comms-metric"><span>{label}</span><strong>{value}</strong></div>;
}
