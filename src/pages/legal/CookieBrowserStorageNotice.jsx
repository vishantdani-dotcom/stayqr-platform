// src/pages/legal/CookieBrowserStorageNotice.jsx

const COOKIEBROWSERSTORAGENOTICE_HTML = String.raw`
<p>This Notice explains how StayQR currently uses browser storage, cookies and similar technologies across the StayQR website, SaaS platform and guest-facing digital experiences.</p>
<p>It should be read with the StayQR Privacy Policy.</p>
<h2>1. Current Position</h2>
<p>StayQR currently does <strong>not</strong> deploy:</p>
<ul><li>Google Analytics;</li><li>Meta Pixel;</li><li>behavioural-advertising trackers;</li><li>third-party advertising pixels;</li><li>advertising cookies used by StayQR to build behavioural profiles.</li></ul>
<p>StayQR does not sell browser-derived personal data for behavioural advertising.</p>
<h2>2. Functional Browser Storage</h2>
<p>StayQR uses browser local storage for functional application state.</p>
<p>Depending on the page/workflow, this may include information such as:</p>
<ul><li>selected tenant or Hotel;</li><li>guest-language/locale preference;</li><li>onboarding/application state;</li><li>other non-advertising interface state required to provide the requested experience.</li></ul>
<h2>3. Authentication and Security Technologies</h2>
<p>StayQR or its infrastructure/authentication providers may use strictly necessary session, authentication, security, load-delivery or similar browser technologies where required to:</p>
<ul><li>keep a user signed in;</li><li>protect authentication;</li><li>maintain requested application state;</li><li>prevent abuse;</li><li>deliver the service securely.</li></ul>
<p>Because provider implementations may evolve, StayQR does not represent that the service will never use any cookie or equivalent browser technology.</p>
<h2>4. Guest QR Pages</h2>
<p>Guest-facing StayQR pages may store functional preferences such as selected language/locale so the requested guest experience can work consistently.</p>
<p>StayQR does not currently use guest QR pages for behavioural advertising.</p>
<h2>5. Local Storage vs Cookies</h2>
<p>Browser local storage and cookies are different browser technologies.</p>
<p>This Notice covers both because each can be used to remember application/session information.</p>
<p>StayQR’s current first-party application implementation primarily relies on local storage for the functional state identified above rather than creating advertising cookies.</p>
<h2>6. Third-Party Links and Services</h2>
<p>A StayQR page may link to or integrate with third-party services such as:</p>
<ul><li>payment providers;</li><li>Hotel-configured websites;</li><li>review platforms;</li><li>messaging services;</li><li>maps/local services.</li></ul>
<p>When a user opens or interacts with an external provider, that provider may use its own cookies/storage under its own privacy notice.</p>
<p>StayQR does not control independent third-party storage outside the StayQR service.</p>
<h2>7. Payment Providers</h2>
<p>Payment services such as Cashfree may use security, fraud-prevention, payment or session technologies required for payment processing.</p>
<p>Those technologies may be governed by the payment provider’s own privacy and cookie practices.</p>
<h2>8. Consent and Necessary Technologies</h2>
<p>Where applicable law requires consent for a non-essential browser technology, StayQR will implement an appropriate consent mechanism before using that technology.</p>
<p>Strictly necessary technologies may be used where legally permitted without optional marketing consent because they are required to provide or secure the requested service.</p>
<p>StayQR does not currently operate an advertising-cookie consent banner because it does not currently deploy the advertising/behavioural technologies listed in Section 1.</p>
<h2>9. Browser Controls</h2>
<p>Users can use browser settings to clear or block local storage/cookies.</p>
<p>Blocking necessary browser storage may cause:</p>
<ul><li>sign-in problems;</li><li>loss of saved language/interface settings;</li><li>repeated setup steps;</li><li>reduced or broken application functionality.</li></ul>
<h2>10. Changes</h2>
<p>If StayQR later introduces analytics, advertising pixels or other non-essential tracking, this Notice will be updated and an appropriate consent/notice mechanism will be implemented where required by applicable law.</p>
<h2>11. Privacy Rights and Contact</h2>
<p>For personal-data questions relating to browser technologies, contact the StayQR privacy channel.</p>
<p><strong>Legal Operator:</strong> Vishant Dani <strong>Trade / Business Name:</strong> StayQR Technologies <strong>Brand:</strong> StayQR <strong>Address:</strong> Dighori, Nagpur, Maharashtra – 440034, India <strong>Support:</strong> support@stayqr.in <strong>Privacy / Grievance:</strong> vishantdani@gmail.com</p>
<hr />
`

export default function CookieBrowserStorageNotice() {
  return (
    <main className="sq-legal-page">
      <style>{`
        .sq-legal-page {
          min-height: 100vh;
          background: #09090b;
          color: #f4f4f5;
          padding: 28px 18px 56px;
          font-family: Inter, system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
        }
        .sq-legal-shell { width: min(980px, 100%); margin: 0 auto; }
        .sq-legal-top {
          display: flex; align-items: center; justify-content: space-between;
          gap: 18px; margin-bottom: 18px;
        }
        .sq-legal-brand {
          display: flex; align-items: center; gap: 12px; color: #fff; text-decoration: none;
        }
        .sq-legal-brand img { width: 44px; height: 44px; object-fit: contain; }
        .sq-legal-brand strong { display: block; font-size: 15px; }
        .sq-legal-brand span { display: block; color: #a1a1aa; font-size: 11px; margin-top: 3px; }
        .sq-legal-home { color: #e8c75c; text-decoration: none; font-size: 13px; font-weight: 700; }
        .sq-legal-card {
          background: #151517; border: 1px solid #303036; border-radius: 18px;
          padding: clamp(22px, 4vw, 46px); box-shadow: 0 18px 60px rgba(0,0,0,.28);
        }
        .sq-legal-card h1 {
          margin: 0 0 12px; font-size: clamp(30px, 5vw, 46px); line-height: 1.08; color: #fff;
        }
        .sq-legal-card h2 { margin: 34px 0 12px; font-size: 22px; line-height: 1.3; color: #e8c75c; }
        .sq-legal-card h3 { margin: 24px 0 10px; font-size: 17px; color: #fff; }
        .sq-legal-card p, .sq-legal-card li { color: #d4d4d8; font-size: 15px; line-height: 1.75; }
        .sq-legal-card p { margin: 10px 0; }
        .sq-legal-card ul, .sq-legal-card ol { margin: 8px 0 16px 22px; padding: 0; }
        .sq-legal-card li { margin: 5px 0; }
        .sq-legal-card strong { color: #fff; }
        .sq-legal-card a, .sq-legal-note a { color: #e8c75c; }
        .sq-legal-card hr { border: 0; border-top: 1px solid #2a2a30; margin: 34px 0; }
        .sq-legal-meta { color: #d4d4d8; font-size: 13px; margin: 0 0 22px; }
        .sq-legal-note { margin-top: 22px; color: #8f8f98; font-size: 12px; line-height: 1.7; text-align: center; }
        @media (max-width: 640px) {
          .sq-legal-page { padding: 18px 12px 42px; }
          .sq-legal-top { align-items: flex-start; }
          .sq-legal-brand img { width: 38px; height: 38px; }
        }
      `}</style>

      <div className="sq-legal-shell">
        <div className="sq-legal-top">
          <a className="sq-legal-brand" href="https://stayqr.in">
            <img src="/assets/stayqr-official-logo.png" alt="StayQR" />
            <div>
              <strong>StayQR</strong>
              <span>Cookies & Browser Storage</span>
            </div>
          </a>
          <a className="sq-legal-home" href="/legal">Legal &amp; Policies</a>
        </div>

        <article className="sq-legal-card">
          <h1>StayQR Cookie & Browser Storage Notice</h1>
          <p className="sq-legal-meta">
            <strong>Effective Date:</strong> 17 August 2026 &nbsp; <strong>Last Updated:</strong> 17 August 2026
          </p>
          <div dangerouslySetInnerHTML={{ __html: COOKIEBROWSERSTORAGENOTICE_HTML }} />
        </article>

        <p className="sq-legal-note">
          Related: <a href="/legal">Legal & Policies</a> · <a href="/privacy">Privacy</a> · <a href="/terms">Terms</a> · <a href="/support">Support</a>
        </p>
      </div>
    </main>
  )
}
