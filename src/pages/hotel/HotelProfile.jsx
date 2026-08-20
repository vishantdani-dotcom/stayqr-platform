import { useCallback, useEffect, useState } from "react";
import { supabase } from "../../lib/supabase";
import { getCurrentHotel } from "../../lib/currentHotel";
import {
  removeGuestGuideMediaFile,
  saveGuestGuideMedia,
  uploadGuestGuideMediaFile,
} from "../../lib/guestGuideBuilder";

const supportedLocales = [
  { code: "en", label: "English" },
  { code: "hi", label: "हिन्दी" },
];

export default function HotelProfile() {
  const [currentHotel, setCurrentHotel] = useState(null);
  const [info, setInfo] = useState(defaultHotelInfo);
  const [contentLocale, setContentLocale] = useState("en");
  const [guestContent, setGuestContent] = useState(defaultGuestContent);
  const [availableLocales, setAvailableLocales] = useState([]);
  const [feedbackRows, setFeedbackRows] = useState([]);
  const [loading, setLoading] = useState(true);
  const [contentLoading, setContentLoading] = useState(false);
  const [saving, setSaving] = useState(false);
  const [contentSaving, setContentSaving] = useState(false);
  const [brandingSaving, setBrandingSaving] = useState("");

  const fetchHotelInfo = useCallback(async (hotel) => {
    const { data, error } = await supabase
      .from("hotel_info")
      .select("*")
      .eq("hotel_id", hotel.id)
      .maybeSingle();

    if (error) {
      throw error;
    }

    if (data) {
      setInfo(data);
      return;
    }

    setInfo({
      ...defaultHotelInfo,
      hotel_id: hotel.id,
      hotel_name: hotel.hotel_name || defaultHotelInfo.hotel_name,
      address: hotel.location || defaultHotelInfo.address,
    });
  }, []);

  const fetchGuestContent = useCallback(async (hotel, locale = "en") => {
    setContentLoading(true);

    try {
      const { data, error } = await supabase.rpc("get_hotel_guest_content", {
        p_hotel_id: hotel.id,
        p_locale: locale,
      });

      if (error) throw error;

      setGuestContent({
        ...defaultGuestContent,
        ...(data?.content || {}),
      });
      setAvailableLocales(
        Array.isArray(data?.available_locales) ? data.available_locales : []
      );
    } catch (error) {
      console.error("Guest content load error:", error);
      alert(error.message || "Unable to load guest-guide content.");
      setGuestContent(defaultGuestContent);
    } finally {
      setContentLoading(false);
    }
  }, []);


  const fetchHotelFeedback = useCallback(async (hotel) => {
    const { data, error } = await supabase
      .from("guest_feedback")
      .select(
        "id, guest_session_id, rating, message, consent_to_follow_up, status, submitted_at"
      )
      .eq("hotel_id", hotel.id)
      .order("submitted_at", { ascending: false })
      .limit(20);

    if (error) throw error;
    setFeedbackRows(Array.isArray(data) ? data : []);
  }, []);

  const initPage = useCallback(async () => {
    setLoading(true);

    try {
      const hotel = await getCurrentHotel();

      if (!hotel) {
        alert("No hotel assigned");
        return;
      }

      setCurrentHotel(hotel);
      await Promise.all([
        fetchHotelInfo(hotel),
        fetchGuestContent(hotel, "en"),
        fetchHotelFeedback(hotel),
      ]);
    } catch (error) {
      console.error("Hotel profile initialization error:", error);
      alert(error.message || "Unable to load the hotel profile.");
    } finally {
      setLoading(false);
    }
  }, [fetchGuestContent, fetchHotelFeedback, fetchHotelInfo]);

  useEffect(() => {
    void initPage();
  }, [initPage]);

  function handleChange(event) {
    setInfo((current) => ({
      ...current,
      [event.target.name]: event.target.value,
    }));
  }

  function handleGuestContentChange(event) {
    setGuestContent((current) => ({
      ...current,
      [event.target.name]: event.target.value,
    }));
  }

  async function handleLocaleChange(event) {
    const nextLocale = event.target.value;
    setContentLocale(nextLocale);

    if (currentHotel?.id) {
      await fetchGuestContent(currentHotel, nextLocale);
    }
  }

  async function saveBrandAsset(kind, file) {
    if (!currentHotel?.id || !file) return;
    if (!['image/jpeg', 'image/png', 'image/webp'].includes(file.type)) {
      alert('Branding images must be JPG, PNG or WebP.');
      return;
    }

    setBrandingSaving(kind);
    try {
      const mediaKey = kind === 'logo' ? 'dashboard_logo' : 'dashboard_cover';
      const category = kind === 'logo' ? 'logo' : 'hero';
      const { data: previous } = await supabase
        .from('guest_guide_media')
        .select('*')
        .eq('hotel_id', currentHotel.id)
        .eq('scope_type', 'hotel')
        .eq('media_key', mediaKey)
        .maybeSingle();

      const upload = await uploadGuestGuideMediaFile({
        hotelId: currentHotel.id,
        file,
        scopeType: 'hotel',
        category,
      });

      await saveGuestGuideMedia(currentHotel.id, {
        scope_type: 'hotel',
        room_type_id: null,
        room_id: null,
        section_id: null,
        item_id: null,
        media_key: mediaKey,
        category,
        object_path: upload.objectPath,
        mime_type: upload.mimeType,
        title: kind === 'logo' ? 'Hotel logo' : 'Hotel dashboard cover',
        caption: '',
        alt_text: kind === 'logo' ? `${currentHotel.hotel_name} logo` : `${currentHotel.hotel_name} cover`,
        locale: null,
        sort_order: kind === 'logo' ? 0 : 10,
        is_active: true,
        metadata: { usage: `dashboard_${kind}` },
      });

      const nextLogo = kind === 'logo' ? upload.publicUrl : currentHotel.logo_url || null;
      const nextCover = kind === 'cover' ? upload.publicUrl : currentHotel.cover_url || null;
      const { error } = await supabase.rpc('update_hotel_branding', {
        p_hotel_id: currentHotel.id,
        p_logo_url: nextLogo,
        p_cover_url: nextCover,
      });
      if (error) throw error;

      if (previous?.object_path && previous.object_path !== upload.objectPath) {
        await removeGuestGuideMediaFile(previous.object_path).catch(() => undefined);
      }

      setCurrentHotel((current) => ({ ...current, logo_url: nextLogo, cover_url: nextCover }));
      alert(`${kind === 'logo' ? 'Hotel logo' : 'Dashboard cover'} updated.`);
    } catch (error) {
      console.error('Branding upload error:', error);
      alert(error?.message || 'Unable to update hotel branding.');
    } finally {
      setBrandingSaving('');
    }
  }

  async function removeBrandAsset(kind) {
    if (!currentHotel?.id) return;
    if (!window.confirm(`Remove the current ${kind}?`)) return;
    setBrandingSaving(kind);
    try {
      const mediaKey = kind === 'logo' ? 'dashboard_logo' : 'dashboard_cover';
      const { data: previous } = await supabase
        .from('guest_guide_media')
        .select('*')
        .eq('hotel_id', currentHotel.id)
        .eq('scope_type', 'hotel')
        .eq('media_key', mediaKey)
        .maybeSingle();

      if (previous) {
        await saveGuestGuideMedia(currentHotel.id, { ...previous, is_active: false });
      }

      const nextLogo = kind === 'logo' ? null : currentHotel.logo_url || null;
      const nextCover = kind === 'cover' ? null : currentHotel.cover_url || null;
      const { error } = await supabase.rpc('update_hotel_branding', {
        p_hotel_id: currentHotel.id,
        p_logo_url: nextLogo,
        p_cover_url: nextCover,
      });
      if (error) throw error;
      if (previous?.object_path) await removeGuestGuideMediaFile(previous.object_path).catch(() => undefined);
      setCurrentHotel((current) => ({ ...current, logo_url: nextLogo, cover_url: nextCover }));
    } catch (error) {
      alert(error?.message || 'Unable to remove hotel branding.');
    } finally {
      setBrandingSaving('');
    }
  }

  async function saveHotelInfo() {
    if (!currentHotel?.id) {
      alert("No hotel assigned");
      return;
    }

    setSaving(true);

    try {
      const payload = {
        hotel_id: currentHotel.id,
        hotel_name: cleanText(info.hotel_name) || currentHotel.hotel_name,
        address: cleanText(info.address) || cleanText(currentHotel.location),
        reception_phone: cleanText(info.reception_phone),
        emergency_phone: cleanText(info.emergency_phone),
        checkin_time: cleanText(info.checkin_time),
        checkout_time: cleanText(info.checkout_time),
        breakfast_time: cleanText(info.breakfast_time),
        wifi_name: cleanText(info.wifi_name),
        wifi_password: cleanText(info.wifi_password),
        hotel_rules: cleanText(info.hotel_rules),
        about: cleanText(info.about),
        google_review_url: cleanText(info.google_review_url),
        reward_title: cleanText(info.reward_title),
        reward_description: cleanText(info.reward_description),
        reward_enabled: info.reward_enabled ?? false,
      };

      const query = info?.id
        ? supabase
            .from("hotel_info")
            .update(payload)
            .eq("id", info.id)
            .eq("hotel_id", currentHotel.id)
        : supabase.from("hotel_info").insert([payload]);

      const { data, error } = await query.select().single();

      if (error) throw error;

      setInfo(data);
      alert("Hotel profile saved successfully");
    } catch (error) {
      console.error("Hotel profile save error:", error);
      alert(error.message || "Unable to save the hotel profile.");
    } finally {
      setSaving(false);
    }
  }

  async function saveGuestContent() {
    if (!currentHotel?.id) {
      alert("No hotel assigned");
      return;
    }

    setContentSaving(true);

    try {
      const { data, error } = await supabase.rpc("upsert_hotel_guest_content", {
        p_hotel_id: currentHotel.id,
        p_locale: contentLocale,
        p_content: cleanGuestContent(guestContent),
      });

      if (error) throw error;

      setGuestContent({
        ...defaultGuestContent,
        ...(data?.content || guestContent),
      });
      setAvailableLocales((current) =>
        current.includes(contentLocale)
          ? current
          : [...current, contentLocale].sort()
      );
      alert(`${getLocaleLabel(contentLocale)} guest content saved successfully`);
    } catch (error) {
      console.error("Guest content save error:", error);
      alert(error.message || "Unable to save guest-guide content.");
    } finally {
      setContentSaving(false);
    }
  }

  if (loading) return <div className="hotel-profile-page" style={page}>Loading Hotel Profile...</div>;

  return (
    <div className="hotel-profile-page" style={page}>
      <h1 style={title}>Hotel Profile &amp; Guest Content</h1>
      <p style={hotelName}>{currentHotel?.hotel_name || "Hotel"}</p>
      <p style={sub}>
        Manage hotel information, multilingual guest-guide content, review links
        and reward terms.
      </p>

      <section style={sectionBlock}>
        <div style={sectionHeader}>
          <div>
            <p style={sectionKicker}>HOTEL BRANDING</p>
            <h2 style={sectionTitle}>Dashboard identity</h2>
          </div>
          <span style={statusPill}>Shared media library</span>
        </div>
        <div style={brandingGrid}>
          <BrandAsset
            label="Hotel logo"
            url={currentHotel?.logo_url}
            busy={brandingSaving === 'logo'}
            onUpload={(file) => void saveBrandAsset('logo', file)}
            onRemove={() => void removeBrandAsset('logo')}
          />
          <BrandAsset
            label="Dashboard cover"
            url={currentHotel?.cover_url}
            wide
            busy={brandingSaving === 'cover'}
            onUpload={(file) => void saveBrandAsset('cover', file)}
            onRemove={() => void removeBrandAsset('cover')}
          />
        </div>
      </section>

      <section style={sectionBlock}>
        <div style={sectionHeader}>
          <div>
            <p style={sectionKicker}>CORE HOTEL PROFILE</p>
            <h2 style={sectionTitle}>Operational guest information</h2>
          </div>
          <span style={statusPill}>Default profile</span>
        </div>

        <div style={card}>
          <Input label="Hotel Name" name="hotel_name" value={info?.hotel_name} onChange={handleChange} />
          <Input label="Address" name="address" value={info?.address} onChange={handleChange} />
          <Input label="Reception Phone" name="reception_phone" value={info?.reception_phone} onChange={handleChange} />
          <Input label="Emergency Phone" name="emergency_phone" value={info?.emergency_phone} onChange={handleChange} />
          <Input label="Check-In Time" name="checkin_time" value={info?.checkin_time} onChange={handleChange} />
          <Input label="Check-Out Time" name="checkout_time" value={info?.checkout_time} onChange={handleChange} />
          <Input label="Breakfast Time" name="breakfast_time" value={info?.breakfast_time} onChange={handleChange} />
          <Input label="WiFi Name" name="wifi_name" value={info?.wifi_name} onChange={handleChange} />
          <Input label="WiFi Password" name="wifi_password" value={info?.wifi_password} onChange={handleChange} />
          <Input label="Google Review URL" name="google_review_url" value={info?.google_review_url} onChange={handleChange} />
          <Input label="Reward Title" name="reward_title" value={info?.reward_title} onChange={handleChange} />

          <Textarea label="About Hotel" name="about" value={info?.about} onChange={handleChange} />
          <Textarea label="Hotel Rules" name="hotel_rules" value={info?.hotel_rules} onChange={handleChange} />
          <Textarea label="Reward Description" name="reward_description" value={info?.reward_description} onChange={handleChange} />

          <div style={field}>
            <label style={labelStyle}>Rewards Enabled</label>
            <select
              style={input}
              name="reward_enabled"
              value={String(info?.reward_enabled ?? false)}
              onChange={(event) =>
                setInfo((current) => ({
                  ...current,
                  reward_enabled: event.target.value === "true",
                }))
              }
            >
              <option value="true">Enabled</option>
              <option value="false">Disabled</option>
            </select>
          </div>

          <button style={saveBtn} onClick={saveHotelInfo} disabled={saving}>
            {saving ? "Saving..." : "Save Hotel Profile"}
          </button>
        </div>
      </section>

      <section style={sectionBlock}>
        <div style={sectionHeader}>
          <div>
            <p style={sectionKicker}>MULTILINGUAL GUEST GUIDE</p>
            <h2 style={sectionTitle}>Guest-facing content</h2>
          </div>

          <div style={localeControl}>
            <label style={labelStyle}>Editing language</label>
            <select
              style={input}
              value={contentLocale}
              onChange={handleLocaleChange}
              disabled={contentLoading}
            >
              {supportedLocales.map((locale) => (
                <option key={locale.code} value={locale.code}>
                  {locale.label}
                  {availableLocales.includes(locale.code) ? " · configured" : ""}
                </option>
              ))}
            </select>
          </div>
        </div>

        {contentLoading ? (
          <div style={loadingCard}>Loading guest content...</div>
        ) : (
          <div style={card}>
            <Input label="Welcome Kicker" name="welcome_kicker" value={guestContent.welcome_kicker} onChange={handleGuestContentChange} />
            <Input label="Welcome Title" name="welcome_title" value={guestContent.welcome_title} onChange={handleGuestContentChange} />
            <Textarea label="Welcome Message" name="welcome_message" value={guestContent.welcome_message} onChange={handleGuestContentChange} />
            <Input label="Concierge Title" name="concierge_title" value={guestContent.concierge_title} onChange={handleGuestContentChange} />
            <Input label="Concierge Subtitle" name="concierge_subtitle" value={guestContent.concierge_subtitle} onChange={handleGuestContentChange} />
            <Input label="Amenities Section Title" name="amenities_title" value={guestContent.amenities_title} onChange={handleGuestContentChange} />
            <Input label="Private Feedback Title" name="feedback_title" value={guestContent.feedback_title} onChange={handleGuestContentChange} />
            <Textarea label="Private Feedback Prompt" name="feedback_prompt" value={guestContent.feedback_prompt} onChange={handleGuestContentChange} />
            <Input label="Review Section Title" name="review_title" value={guestContent.review_title} onChange={handleGuestContentChange} />
            <Textarea label="Review Prompt" name="review_prompt" value={guestContent.review_prompt} onChange={handleGuestContentChange} />
            <Input label="Guest Guide Footer" name="footer_message" value={guestContent.footer_message} onChange={handleGuestContentChange} />

            <div style={contentHelp}>
              Amenities are managed from the Amenities module. Only active,
              guest-visible amenities appear on the signed guest guide.
            </div>

            <button style={saveBtn} onClick={saveGuestContent} disabled={contentSaving}>
              {contentSaving
                ? "Saving..."
                : `Save ${getLocaleLabel(contentLocale)} Guest Content`}
            </button>
          </div>
        )}
      </section>

      <section style={sectionBlock}>
        <div style={sectionHeader}>
          <div>
            <p style={sectionKicker}>PRIVATE FEEDBACK INBOX</p>
            <h2 style={sectionTitle}>Recent guest responses</h2>
          </div>
          <span style={statusPill}>{feedbackRows.length} loaded</span>
        </div>

        {feedbackRows.length === 0 ? (
          <div style={loadingCard}>No private guest feedback has been submitted yet.</div>
        ) : (
          <div style={feedbackGrid}>
            {feedbackRows.map((feedback) => (
              <article key={feedback.id} style={feedbackCard}>
                <div style={feedbackTop}>
                  <strong style={feedbackStars}>
                    {"★".repeat(feedback.rating)}{"☆".repeat(5 - feedback.rating)}
                  </strong>
                  <span style={feedbackStatus}>{feedback.status}</span>
                </div>

                <p style={feedbackMessage}>
                  {feedback.message || "No written message was provided."}
                </p>

                <small style={feedbackMeta}>
                  {feedback.submitted_at
                    ? new Date(feedback.submitted_at).toLocaleString("en-IN")
                    : "-"}
                  {feedback.consent_to_follow_up
                    ? " · Follow-up consent provided"
                    : " · No follow-up consent"}
                </small>
              </article>
            ))}
          </div>
        )}
      </section>
    </div>
  );
}

const defaultHotelInfo = {
  hotel_name: "",
  address: "",
  reception_phone: "",
  emergency_phone: "",
  checkin_time: "",
  checkout_time: "",
  breakfast_time: "",
  wifi_name: "",
  wifi_password: "",
  hotel_rules: "",
  about: "",
  google_review_url: "",
  reward_title: "",
  reward_description: "",
  reward_enabled: false,
};

const defaultGuestContent = {
  welcome_kicker: "WELCOME TO A SMART STAY EXPERIENCE",
  welcome_title: "",
  welcome_message: "Digital Guest Guide · Powered by StayQR",
  concierge_title: "Your Digital Concierge",
  concierge_subtitle: "Everything you need, at your fingertips.",
  amenities_title: "Hotel Amenities",
  feedback_title: "How Is Your Stay?",
  feedback_prompt: "Share private feedback directly with the hotel team.",
  review_title: "Share Your Experience",
  review_prompt: "Your honest review is optional and helps future guests make informed decisions.",
  footer_message: "Luxury Smart Hospitality Experience",
};

function cleanText(value) {
  const text = String(value || "").trim();
  return text || null;
}

function cleanGuestContent(content) {
  return Object.fromEntries(
    Object.entries(content).map(([key, value]) => [key, String(value || "").trim()])
  );
}

function getLocaleLabel(locale) {
  return supportedLocales.find((item) => item.code === locale)?.label || locale;
}

function BrandAsset({ label, url, wide = false, busy, onUpload, onRemove }) {
  return (
    <article style={{ ...brandingCard, gridColumn: wide ? '1 / -1' : undefined }}>
      <div style={brandingPreview}>
        {url ? <img src={url} alt={label} style={brandingImage} /> : <span>No {label.toLowerCase()} uploaded</span>}
      </div>
      <strong>{label}</strong>
      <div style={brandingActions}>
        <label style={uploadLabel}>
          {busy ? 'Working…' : `Upload ${label.toLowerCase()}`}
          <input type="file" accept="image/jpeg,image/png,image/webp" hidden disabled={busy} onChange={(event) => { const file = event.target.files?.[0]; if (file) onUpload(file); event.target.value = ''; }} />
        </label>
        {url && <button type="button" style={removeButton} disabled={busy} onClick={onRemove}>Remove</button>}
      </div>
    </article>
  );
}

function Input({ label, name, value, onChange }) {
  return (
    <div style={field}>
      <label style={labelStyle}>{label}</label>
      <input style={input} name={name} value={value || ""} onChange={onChange} />
    </div>
  );
}

function Textarea({ label, name, value, onChange }) {
  return (
    <div style={{ ...field, gridColumn: "1 / -1" }}>
      <label style={labelStyle}>{label}</label>
      <textarea style={textarea} name={name} value={value || ""} onChange={onChange} />
    </div>
  );
}

const brandingGrid = { display: 'grid', gridTemplateColumns: 'repeat(auto-fit,minmax(240px,1fr))', gap: 14, marginBottom: 22 }
const brandingCard = { padding: 16, border: '1px solid #292929', borderRadius: 16, background: '#101010', display: 'grid', gap: 12, minWidth: 0 }
const brandingPreview = { minHeight: 130, borderRadius: 12, overflow: 'hidden', background: '#080808', display: 'grid', placeItems: 'center', color: '#777' }
const brandingImage = { width: '100%', height: 180, objectFit: 'cover' }
const brandingActions = { display: 'flex', gap: 8, flexWrap: 'wrap' }
const uploadLabel = { padding: '9px 12px', borderRadius: 9, background: '#d4af37', color: '#080808', fontWeight: 800, cursor: 'pointer' }
const removeButton = { padding: '9px 12px', borderRadius: 9, border: '1px solid #6f2b2b', background: '#291010', color: '#ffaaaa', fontWeight: 800, cursor: 'pointer' }
const page = {
  padding: "32px",
  color: "#fff",
};

const title = {
  fontSize: "42px",
  marginBottom: "6px",
};

const hotelName = {
  color: "#d4af37",
  marginBottom: "6px",
};

const sub = {
  color: "#aaa",
  marginBottom: "28px",
  maxWidth: "760px",
};

const sectionBlock = {
  marginBottom: "28px",
};

const sectionHeader = {
  display: "flex",
  justifyContent: "space-between",
  alignItems: "flex-end",
  flexWrap: "wrap",
  gap: "16px",
  marginBottom: "14px",
};

const sectionKicker = {
  margin: "0 0 6px",
  color: "#d4af37",
  fontSize: "12px",
  fontWeight: "900",
  letterSpacing: "0.12em",
};

const sectionTitle = {
  margin: 0,
  fontSize: "25px",
};

const statusPill = {
  border: "1px solid #3b3215",
  borderRadius: "999px",
  padding: "8px 12px",
  color: "#d4af37",
  background: "#181405",
  fontSize: "12px",
  fontWeight: "800",
};

const localeControl = {
  display: "grid",
  gap: "7px",
  minWidth: "220px",
};

const card = {
  background: "#0f0f0f",
  border: "1px solid #222",
  borderRadius: "20px",
  padding: "28px",
  display: "grid",
  gridTemplateColumns: "repeat(auto-fit, minmax(260px, 1fr))",
  gap: "20px",
};

const field = {
  display: "flex",
  flexDirection: "column",
  gap: "8px",
};

const labelStyle = {
  color: "#d4af37",
  fontSize: "13px",
  fontWeight: "700",
};

const input = {
  background: "#050505",
  color: "#fff",
  border: "1px solid #333",
  borderRadius: "10px",
  padding: "12px",
};

const textarea = {
  ...input,
  minHeight: "110px",
  resize: "vertical",
};

const contentHelp = {
  gridColumn: "1 / -1",
  border: "1px solid #2f2a18",
  borderRadius: "12px",
  padding: "13px 15px",
  color: "#c9bd8a",
  background: "#151207",
  lineHeight: 1.55,
};

const loadingCard = {
  ...card,
  display: "block",
  color: "#aaa",
};


const feedbackGrid = {
  display: "grid",
  gridTemplateColumns: "repeat(auto-fit, minmax(280px, 1fr))",
  gap: "14px",
};

const feedbackCard = {
  border: "1px solid #282828",
  borderRadius: "16px",
  padding: "18px",
  background: "#0f0f0f",
};

const feedbackTop = {
  display: "flex",
  justifyContent: "space-between",
  gap: "12px",
};

const feedbackStars = {
  color: "#d4af37",
  letterSpacing: "2px",
};

const feedbackStatus = {
  color: "#aaa",
  fontSize: "11px",
  textTransform: "uppercase",
};

const feedbackMessage = {
  color: "#eee",
  lineHeight: 1.55,
  margin: "14px 0",
};

const feedbackMeta = {
  color: "#888",
  lineHeight: 1.5,
};

const saveBtn = {
  gridColumn: "1 / -1",
  background: "#d4af37",
  color: "#000",
  border: "none",
  padding: "14px 18px",
  borderRadius: "12px",
  fontWeight: "800",
  cursor: "pointer",
};
