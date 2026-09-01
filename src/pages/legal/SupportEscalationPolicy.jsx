// src/pages/legal/SupportEscalationPolicy.jsx

const SUPPORTESCALATIONPOLICY_HTML = String.raw`
<p>This Support + Escalation Policy describes StayQR’s standard customer-support channels, severity model, acknowledgement targets and escalation process for active StayQR subscriptions.</p>
<h2>1. Support Channels</h2>
<p>Primary support channel: the dedicated StayQR WhatsApp support number displayed inside the authenticated StayQR application after provider configuration.</p>
<p>In-app support tickets and <strong>support@stayqr.in</strong> remain available as fallback channels.</p>
<p>Support requests should include the Hotel/property name, affected feature, relevant time, screenshots/error details and sufficient information to reproduce or understand the issue.</p>
<p>Do not email passwords, full payment-card details, unnecessary identity documents or service-role/API secrets.</p>
<h2>2. 24×7 Support Coverage</h2>
<p>Support requests may be submitted <strong>24 hours a day, 7 days a week</strong>.</p>
<p>Critical after-hours incidents are escalated to the StayQR founder, who owns after-hours triage and coordination.</p>
<p>24×7 intake and triage is not a guarantee of immediate final resolution. Provider dependencies, reproducibility, security controls and the availability of a safe workaround may affect restoration and resolution time.</p>
<h2>3. Severity Levels</h2>
<h3>P0 / Critical</h3>
<p>Examples:</p>
<ul><li>widespread core production outage;</li><li>confirmed tenant-isolation failure;</li><li>confirmed or reasonably suspected material security incident;</li><li>material data-loss or financial-integrity risk;</li><li>inability of multiple Hotels to access core production functionality with no reasonable workaround.</li></ul>
<p><strong>Handling:</strong> immediate priority classification and after-hours founder escalation.</p>
<h3>P1 / High</h3>
<p>Examples:</p>
<ul><li>major production feature materially unavailable;</li><li>severe degradation affecting normal Hotel operations;</li><li>important workflow blocked with no reasonable normal workaround.</li></ul>
<p><strong>Handling:</strong> high-priority triage and escalation based on operational impact.</p>
<h3>P2 / Medium</h3>
<p>Examples:</p>
<ul><li>partial impairment;</li><li>non-critical feature issue;</li><li>issue with a practical workaround;</li><li>isolated operational defect.</li></ul>
<p><strong>Acknowledgement target:</strong> within 1 business day.</p>
<h3>P3 / Low</h3>
<p>Examples:</p>
<ul><li>cosmetic issue;</li><li>general question;</li><li>documentation request;</li><li>enhancement or feature request;</li><li>low-impact defect.</li></ul>
<p><strong>Acknowledgement target:</strong> within 2 business days.</p>
<h2>4. Acknowledgement Is Not Resolution</h2>
<p>The targets above apply to acknowledgement and initial handling, not guaranteed final resolution.</p>
<p>Resolution time depends on cause, reproducibility, technical complexity, provider dependency, security impact and whether a safe workaround is available.</p>
<h2>5. Escalation</h2>
<p>StayQR may escalate an issue internally where:</p>
<ul><li>severity increases;</li><li>multiple Hotels are affected;</li><li>data security or integrity may be involved;</li><li>financial integrity may be involved;</li><li>a third-party infrastructure provider must be engaged;</li><li>repeated remediation attempts fail.</li></ul>
<p>Customers may request escalation by replying to the active support thread and stating the business impact and requested escalation reason.</p>
<h2>6. Scale Priority Support</h2>
<p>Scale plan customers receive priority queue treatment over ordinary non-critical Starter/Growth requests.</p>
<p>Priority treatment does not create a guaranteed resolution time and does not override active P0/P1 incidents affecting other customers.</p>
<h2>7. Enterprise / Custom Support</h2>
<p>Enterprise / Custom customers may receive separately negotiated:</p>
<ul><li>extended staffed hours;</li><li>named escalation contacts;</li><li>enhanced acknowledgement targets;</li><li>incident bridge procedures;</li><li>service credits;</li><li>RTO/RPO commitments;</li><li>other support arrangements.</li></ul>
<p>Only a separately signed written agreement creates those enhanced commitments.</p>
<h2>8. Security and Privacy Reports</h2>
<p>Security reports should use:</p>
<p><strong>support@stayqr.in</strong> Subject: <strong>SECURITY</strong></p>
<p>Privacy or data-protection requests should use:</p>
<p><strong>vishantdani@gmail.com</strong></p>
<p>A support ticket involving a Personal Data Breach or cyber incident may be handled under the StayQR DPA, Privacy Policy, Security Policy and applicable law in addition to this Support Policy.</p>
<h2>9. Third-Party Provider Incidents</h2>
<p>StayQR may depend on external infrastructure and service providers.</p>
<p>Where an incident originates in a third-party system, StayQR will use reasonable efforts to investigate, escalate with the provider and communicate material impact, but cannot guarantee the third party’s restoration time.</p>
<h2>10. Customer Cooperation</h2>
<p>Customers should:</p>
<ul><li>provide accurate incident details;</li><li>preserve relevant screenshots/log details where reasonably available;</li><li>avoid repeated changes that make reproduction impossible;</li><li>identify urgent business impact;</li><li>follow reasonable troubleshooting instructions;</li><li>protect credentials and secrets.</li></ul>
<p>Failure to provide sufficient information may delay investigation.</p>
<h2>11. Abuse of Support</h2>
<p>Threats, harassment, excessive duplicate tickets, knowingly false incident claims or repeated misuse of emergency channels may be managed under the StayQR AUP.</p>
<p>Legitimate complaints and escalation requests will not be treated as abuse merely because they are critical of the service.</p>
<h2>12. Relationship with SLA</h2>
<p>Availability targets are governed by the StayQR SLA / Service Commitments.</p>
<p>This Support Policy does not convert acknowledgement targets into uptime guarantees, service credits or fixed resolution times.</p>
<h2>13. Changes</h2>
<p>StayQR may update support processes as staffing, scale and service architecture evolve. Material reductions to an active paid plan’s published support commitments will receive reasonable notice where appropriate.</p>
<h2>14. Contact</h2>
<p><strong>Legal Operator:</strong> Vishant Dani <strong>Trade / Business Name:</strong> StayQR Technologies <strong>Brand:</strong> StayQR <strong>Address:</strong> Dighori, Nagpur, Maharashtra – 440034, India <strong>Support:</strong> support@stayqr.in <strong>Privacy / Grievance:</strong> vishantdani@gmail.com</p>
<hr />
`

export default function SupportEscalationPolicy() {
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
              <span>Customer Support</span>
            </div>
          </a>
          <a className="sq-legal-home" href="/legal">Legal &amp; Policies</a>
        </div>

        <article className="sq-legal-card">
          <h1>StayQR Support + Escalation Policy</h1>
          <p className="sq-legal-meta">
            <strong>Effective Date:</strong> 17 August 2026 &nbsp; <strong>Last Updated:</strong> 01 September 2026
          </p>
          <div dangerouslySetInnerHTML={{ __html: SUPPORTESCALATIONPOLICY_HTML }} />
        </article>

        <p className="sq-legal-note">
          Related: <a href="/legal">Legal & Policies</a> · <a href="/privacy">Privacy</a> · <a href="/terms">Terms</a>
        </p>
      </div>
    </main>
  )
}
