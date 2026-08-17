// src/pages/legal/ServiceCommitments.jsx

const SLA_HTML = String.raw`

<p>These SLA / Service Commitments (“Service Commitments”) describe the standard service-availability and operational commitments for the StayQR production SaaS service.</p>
<p>The service is operated by <strong>Vishant Dani, operating under the trade name StayQR Technologies and the brand StayQR</strong> (“StayQR”, “we”, “us” or “our”), having its business address at <strong>Dighori, Nagpur, Maharashtra – 440034, India</strong>.</p>
<p>These Service Commitments supplement the StayQR Terms of Service and apply to active paid subscriptions unless a separately signed enterprise agreement expressly provides different service levels.</p>
<h2>1. Scope</h2>
<p>These Service Commitments apply to the core StayQR production SaaS service hosted through <strong>app.stayqr.in</strong>, including the Hotel dashboard and StayQR-hosted guest-facing QR/digital guest experiences.</p>
<p>They do not create service-level commitments for:</p>
<ul><li>the public marketing website except where expressly stated;</li><li>third-party websites or services linked from StayQR;</li><li>Hotel internet connectivity, devices or local networks;</li><li>payment networks, banks or independent payment-provider systems;</li><li>Hotel-configured external links, messaging destinations or review platforms;</li><li>beta, preview, experimental or expressly non-production features.</li></ul>
<h2>2. Standard Availability Target</h2>
<p>StayQR’s standard production availability <strong>target</strong> is:</p>
<p><strong>99.5% monthly availability</strong></p>
<p>for the core StayQR production service.</p>
<p>This is an operational target and not a guarantee that the service will be uninterrupted or error-free.</p>
<p>Unless StayQR expressly agrees otherwise in a separately signed written agreement, the standard StayQR plans do <strong>not</strong> include automatic service credits, penalties or refunds for failure to meet this target.</p>
<h2>3. Availability Measurement</h2>
<p>Monthly availability may be measured using StayQR’s production monitoring, platform diagnostics, provider records and other reasonable operational evidence.</p>
<p>A material service outage generally means an unplanned condition in which the core StayQR production service is substantially unavailable to affected Hotels.</p>
<p>Availability calculations may exclude events described in Section 5.</p>
<h2>4. Service Reliability Commitment</h2>
<p>StayQR will use reasonable efforts to:</p>
<ul><li>maintain the production service in an operational condition;</li><li>monitor material production failures and operational errors;</li><li>investigate confirmed material outages or severe degradation;</li><li>restore affected service or provide a reasonable workaround where feasible;</li><li>maintain production/staging environment separation;</li><li>maintain operational backup, restore and rollback procedures appropriate to the deployed service;</li><li>use reasonable security and application-hardening practices;</li><li>communicate material incidents according to the applicable Support + Escalation Policy.</li></ul>
<p>StayQR does not promise that every incident will be resolved within a fixed period unless a separately signed agreement expressly states a resolution commitment.</p>
<h2>5. Availability Exclusions</h2>
<p>The availability target does not include downtime or degradation caused by:</p>
<ul><li>planned maintenance notified in accordance with Section 6;</li><li>emergency maintenance required for security, integrity or material service protection;</li><li>force majeure events;</li><li>internet, telecommunications, DNS or network failures outside StayQR’s reasonable control;</li><li>material failures of third-party infrastructure or service providers outside StayQR’s reasonable control;</li><li>payment-provider, bank or payment-network outages;</li><li>Customer or Hotel configuration errors;</li><li>unauthorised, abusive, unlawful or prohibited use;</li><li>Customer devices, browsers, local systems or connectivity;</li><li>suspension for non-payment, security risk, legal requirement or breach of the Terms;</li><li>attacks or security events that StayQR could not reasonably prevent;</li><li>beta, preview, test or non-production functionality;</li><li>actions expressly requested or caused by the Customer;</li><li>circumstances where StayQR has provided a functioning workaround that restores the materially affected core service.</li></ul>
<h2>6. Planned Maintenance</h2>
<p>Where reasonably practicable, StayQR will aim to provide at least <strong>24 hours’ prior notice</strong> for planned maintenance expected to cause material production unavailability.</p>
<p>Notice may be provided through:</p>
<ul><li>the StayQR platform;</li><li>registered Customer email;</li><li>support communication;</li><li>another reasonable electronic channel.</li></ul>
<p>StayQR may perform maintenance without 24 hours’ notice where urgent action is reasonably required for security, availability, data integrity, legal compliance or provider continuity.</p>
<h2>7. Emergency Maintenance</h2>
<p>StayQR may perform emergency maintenance immediately where reasonably necessary to:</p>
<ul><li>contain or remediate a security incident;</li><li>prevent data corruption or material data loss;</li><li>protect tenant isolation;</li><li>restore a failed production service;</li><li>respond to critical third-party infrastructure failure;</li><li>comply with a lawful requirement.</li></ul>
<p>Where practical, affected Customers will be informed as soon as reasonably possible.</p>
<h2>8. Incident Severity</h2>
<p>StayQR’s operational support model uses severity levels including:</p>
<ul><li><strong>P0 / Critical</strong> — widespread or severe production outage, confirmed material security incident, reproducible tenant-isolation failure, material financial/data-loss risk, or another launch/production-critical condition;</li><li><strong>P1 / High</strong> — major production functionality materially impaired without a reasonable normal workflow;</li><li><strong>P2 / Medium</strong> — partial impairment with a workaround or non-critical operational impact;</li><li><strong>P3 / Low</strong> — minor defect, cosmetic issue, question, enhancement or low-impact problem.</li></ul>
<p>Detailed contact channels, acknowledgement targets, escalation ownership and communication handling are governed by the separate <strong>StayQR Support + Escalation Policy</strong>.</p>
<h2>9. Restoration and Resolution</h2>
<p>StayQR distinguishes between:</p>
<ul><li><strong>acknowledgement</strong> — confirming receipt and initial classification;</li><li><strong>response</strong> — investigation or active handling;</li><li><strong>workaround/restoration</strong> — restoring a materially usable service where possible;</li><li><strong>resolution</strong> — completing the underlying correction or remediation.</li></ul>
<p>A workaround may restore service before the underlying defect is permanently resolved.</p>
<p>Standard StayQR plans do not include guaranteed resolution times.</p>
<h2>10. Third-Party Infrastructure</h2>
<p>StayQR relies on external infrastructure and service providers, including providers used for hosting, database/backend functionality and payment processing.</p>
<p>Current principal providers include:</p>
<ul><li>Supabase;</li><li>Netlify;</li><li>Cashfree where payment functionality is enabled.</li></ul>
<p>StayQR will use reasonable efforts to manage provider incidents affecting StayQR but cannot guarantee the independent availability or performance of third-party systems.</p>
<h2>11. Backups, Restore and Recovery</h2>
<p>StayQR maintains backup/restore and operational recovery procedures appropriate to the deployed production architecture.</p>
<p>However:</p>
<ul><li>no backup system can guarantee that data loss is impossible;</li><li>restoration time depends on the nature and scope of an incident;</li><li>the standard plans do not promise a fixed contractual Recovery Time Objective (RTO) or Recovery Point Objective (RPO);</li><li>StayQR may restore from available provider or application-level recovery mechanisms as appropriate.</li></ul>
<p>Any enterprise customer requiring contractually fixed RTO/RPO commitments must obtain a separately agreed written service level.</p>
<h2>12. Security Incidents</h2>
<p>Security incidents are handled according to StayQR’s security, incident-response, Privacy Policy and Data Processing Agreement commitments.</p>
<p>Where a Personal Data Breach affects Hotel-controlled Customer Personal Data, StayQR’s notification obligation to the affected Hotel is governed by the StayQR DPA.</p>
<h2>13. Customer Responsibilities</h2>
<p>The Hotel must:</p>
<ul><li>maintain working internet connectivity and supported devices/browsers;</li><li>use supported StayQR workflows;</li><li>protect credentials and authorised accounts;</li><li>configure roles and permissions responsibly;</li><li>promptly report suspected material incidents;</li><li>provide sufficient information for troubleshooting;</li><li>avoid unauthorised modifications, abuse or prohibited use;</li><li>maintain any Hotel-side records or contingency procedures reasonably required for Hotel operations.</li></ul>
<p>StayQR is not responsible for service impact caused solely by Customer-side systems or configuration.</p>
<h2>14. Plan Treatment</h2>
<p>Unless stated otherwise:</p>
<ul><li><strong>Starter, Growth and Scale</strong> use the same standard production availability target;</li><li>plan differences may affect feature entitlements, limits and support priority;</li><li><strong>Scale</strong> may include priority-support handling as described in the Support + Escalation Policy;</li><li><strong>Enterprise / Custom</strong> customers may receive separately negotiated service levels, support commitments, RTO/RPO targets or service-credit arrangements.</li></ul>
<p>Trial accounts may receive standard operational support on a reasonable-efforts basis but are not entitled to enhanced or enterprise service commitments.</p>
<h2>15. Service Credits and Refunds</h2>
<p>The standard StayQR plans currently do <strong>not</strong> include automatic service credits for service interruption or failure to meet the availability target.</p>
<p>Refund eligibility, if any, is governed by the StayQR Subscription / Cancellation / Refund Policy, applicable written commercial commitments and applicable law.</p>
<p>Nothing in these Service Commitments removes a statutory right or remedy that cannot lawfully be excluded.</p>
<h2>16. Reporting an Availability Incident</h2>
<p>Customers should report suspected service outages or material degradation through the official StayQR support channel:</p>
<p><strong>support@stayqr.in</strong></p>
<p>Reports should include, where reasonably available:</p>
<ul><li>Hotel/property name;</li><li>affected feature;</li><li>time the issue began;</li><li>screenshots or error details;</li><li>affected users or rooms;</li><li>whether a workaround exists;</li><li>any relevant transaction/reference identifier that does not expose unnecessary sensitive information.</li></ul>
<p>Security or privacy incidents should be clearly identified as such.</p>
<h2>17. Service Changes</h2>
<p>StayQR may update infrastructure, architecture, providers, operational processes or these Service Commitments as the service evolves.</p>
<p>StayQR will not intentionally make a material reduction to an active paid Customer’s standard service commitments during an already-paid subscription period without a reasonable security, technical, legal or operational basis.</p>
<p>Material changes will be reflected through an updated Last Updated date and reasonable notice where appropriate.</p>
<h2>18. Relationship with Other StayQR Documents</h2>
<p>These Service Commitments should be read together with:</p>
<ul><li>StayQR Terms of Service;</li><li>StayQR Privacy Policy;</li><li>StayQR Data Processing Agreement;</li><li>StayQR Support + Escalation Policy;</li><li>StayQR Subscription / Cancellation / Refund Policy.</li></ul>
<p>If a separately signed enterprise or customer agreement expressly conflicts with these Service Commitments, the signed agreement will control to the extent of that conflict.</p>
<h2>19. Liability</h2>
<p>The liability framework in the StayQR Terms of Service applies to these Service Commitments unless a separately signed written agreement expressly states otherwise.</p>
<h2>20. Governing Law and Jurisdiction</h2>
<p>These Service Commitments are governed by the laws of India.</p>
<p>Subject to any mandatory statutory forum or jurisdiction that cannot validly be excluded, the courts at <strong>Nagpur, Maharashtra, India</strong> will have jurisdiction over disputes relating to these Service Commitments.</p>
<h2>21. Contact</h2>
<p><strong>Legal Operator:</strong> Vishant Dani <strong>Trade / Business Name:</strong> StayQR Technologies <strong>Brand:</strong> StayQR <strong>Address:</strong> Dighori, Nagpur, Maharashtra – 440034, India <strong>Support:</strong> support@stayqr.in <strong>Privacy / Grievance:</strong> vishantdani@gmail.com</p>
<hr />
`

export default function ServiceCommitments() {
  return (
    <main className="sq-sla-page">
      <style>{`
        .sq-sla-page {
          min-height: 100vh;
          background: #09090b;
          color: #f4f4f5;
          padding: 28px 18px 56px;
          font-family: Inter, system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
        }
        .sq-sla-shell { width: min(980px, 100%); margin: 0 auto; }
        .sq-sla-top {
          display: flex; align-items: center; justify-content: space-between;
          gap: 18px; margin-bottom: 18px;
        }
        .sq-sla-brand {
          display: flex; align-items: center; gap: 12px; color: #fff;
          text-decoration: none;
        }
        .sq-sla-brand img { width: 44px; height: 44px; object-fit: contain; }
        .sq-sla-brand strong { display: block; font-size: 15px; }
        .sq-sla-brand span { display: block; color: #a1a1aa; font-size: 11px; margin-top: 3px; }
        .sq-sla-home { color: #e8c75c; text-decoration: none; font-size: 13px; font-weight: 700; }
        .sq-sla-card {
          background: #151517; border: 1px solid #303036; border-radius: 18px;
          padding: clamp(22px, 4vw, 46px); box-shadow: 0 18px 60px rgba(0,0,0,.28);
        }
        .sq-sla-card h1 { margin: 0 0 12px; font-size: clamp(32px, 5vw, 48px); line-height: 1.05; color: #fff; }
        .sq-sla-card h2 { margin: 34px 0 12px; font-size: 22px; line-height: 1.3; color: #e8c75c; }
        .sq-sla-card h3 { margin: 24px 0 10px; font-size: 17px; color: #fff; }
        .sq-sla-card p, .sq-sla-card li { color: #d4d4d8; font-size: 15px; line-height: 1.75; }
        .sq-sla-card p { margin: 10px 0; }
        .sq-sla-card ul, .sq-sla-card ol { margin: 8px 0 16px 22px; padding: 0; }
        .sq-sla-card li { margin: 5px 0; }
        .sq-sla-card strong { color: #fff; }
        .sq-sla-card a { color: #e8c75c; }
        .sq-sla-card hr { border: 0; border-top: 1px solid #2a2a30; margin: 34px 0; }
        .sq-sla-meta { color: #d4d4d8; font-size: 13px; margin: 0 0 22px; }
        .sq-sla-note { margin-top: 22px; color: #8f8f98; font-size: 12px; line-height: 1.7; text-align: center; }
        .sq-sla-note a { color: #c7a94b; }
        @media (max-width: 640px) {
          .sq-sla-page { padding: 18px 12px 42px; }
          .sq-sla-top { align-items: flex-start; }
          .sq-sla-brand img { width: 38px; height: 38px; }
        }
      `}</style>

      <div className="sq-sla-shell">
        <div className="sq-sla-top">
          <a className="sq-sla-brand" href="https://stayqr.in">
            <img src="/assets/stayqr-official-logo.png" alt="StayQR" />
            <div>
              <strong>StayQR</strong>
              <span>Service Availability & Commitments</span>
            </div>
          </a>
          <a className="sq-sla-home" href="https://stayqr.in">stayqr.in</a>
        </div>

        <article className="sq-sla-card">
          <h1>StayQR SLA / Service Commitments</h1>
          <p className="sq-sla-meta"><strong>Effective Date:</strong> 17 August 2026 &nbsp; <strong>Last Updated:</strong> 17 August 2026</p>
          <div dangerouslySetInnerHTML={{ __html: SLA_HTML }} />
        </article>

        <p className="sq-sla-note">
          Related documents: <a href="/support">Support + Escalation Policy</a> · <a href="/subscription-policy">Subscription / Cancellation / Refund Policy</a> · <a href="/legal">Legal &amp; Policies</a>
        </p>
      </div>
    </main>
  )
}
