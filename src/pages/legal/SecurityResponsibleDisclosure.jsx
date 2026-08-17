// src/pages/legal/SecurityResponsibleDisclosure.jsx

const SECURITYRESPONSIBLEDISCLOSURE_HTML = String.raw`
<p>StayQR values responsible security research and good-faith reporting that helps protect Hotels, guests and the StayQR platform.</p>
<p>This Policy explains how to report a suspected security vulnerability and the boundaries for authorised good-faith research.</p>
<h2>1. Reporting Channel</h2>
<p>Report suspected StayQR vulnerabilities to:</p>
<p><strong>support@stayqr.in</strong></p>
<p>Use the subject:</p>
<p><strong>SECURITY</strong></p>
<p>Include, where reasonably available:</p>
<ul><li>affected URL/feature;</li><li>vulnerability type;</li><li>reproducible steps;</li><li>impact;</li><li>screenshots or proof of concept;</li><li>browser/system context;</li><li>suggested mitigation, if known.</li></ul>
<p>Do not include unnecessary guest data, identity documents, passwords, payment-card details or secrets.</p>
<h2>2. Acknowledgement</h2>
<p>StayQR aims to acknowledge a responsible vulnerability report within <strong>3 business days</strong>.</p>
<p>This is an acknowledgement target, not a guaranteed remediation deadline.</p>
<h2>3. Good-Faith Research</h2>
<p>StayQR welcomes research that:</p>
<ul><li>is conducted in good faith;</li><li>uses only accounts/data the researcher owns or is expressly authorised to use;</li><li>minimises access to personal or confidential information;</li><li>stops when unintended sensitive data is encountered;</li><li>avoids service disruption;</li><li>provides StayQR a reasonable opportunity to investigate and remediate before public disclosure;</li><li>complies with applicable law.</li></ul>
<h2>4. Prohibited Testing</h2>
<p>Do not perform:</p>
<ul><li>denial-of-service, stress or resource-exhaustion testing;</li><li>destructive testing;</li><li>malware/ransomware deployment;</li><li>social engineering or phishing of StayQR staff/customers;</li><li>credential stuffing, password spraying or brute-force attacks;</li><li>physical attacks;</li><li>persistent access or backdoors;</li><li>mass scanning that materially affects the service;</li><li>deletion, corruption or modification of production data;</li><li>downloading or retaining another Hotel’s/guest’s data beyond the minimum necessary to demonstrate a vulnerability;</li><li>extortion, threats or demands tied to non-disclosure;</li><li>public disclosure before reasonable coordination.</li></ul>
<h2>5. Tenant and Guest Data</h2>
<p>If research unexpectedly exposes data belonging to another Hotel, guest or user:</p>
<ol><li>1. stop testing;</li><li>2. do not copy, download, alter or share additional data;</li><li>3. report the issue immediately;</li><li>4. delete any unintentionally retained copy where safe and lawful to do so;</li><li>5. follow StayQR’s reasonable containment instructions.</li></ol>
<h2>6. No Automatic Bug Bounty</h2>
<p>StayQR does not currently operate a public paid bug-bounty programme.</p>
<p>Submission of a vulnerability does not create a right to payment, reward, employment, contract or public recognition.</p>
<p>StayQR may voluntarily acknowledge helpful researchers at its discretion and with the researcher’s consent.</p>
<h2>7. Researcher Treatment</h2>
<p>Where a researcher acts in good faith and complies with this Policy, StayQR does not intend to initiate legal action <strong>solely because of that compliant security research</strong>.</p>
<p>This statement is not authorisation to violate applicable law, access another person’s data, cause damage or ignore a lawful restriction.</p>
<h2>8. Disclosure Coordination</h2>
<p>Please allow StayQR reasonable time to:</p>
<ul><li>reproduce the issue;</li><li>assess severity;</li><li>develop and test remediation;</li><li>coordinate with providers where required;</li><li>deploy a safe correction.</li></ul>
<p>StayQR does not promise a fixed remediation deadline because security issues vary in complexity and provider dependency.</p>
<p>Coordinated disclosure timing should be agreed where possible.</p>
<h2>9. Severity and Incident Handling</h2>
<p>StayQR may classify a validated security issue according to its operational severity model.</p>
<p>A security report may also trigger the StayQR incident-response, Support + Escalation, DPA or Privacy processes.</p>
<h2>10. Legal and Regulatory Reporting</h2>
<p>Where a cyber incident or Personal Data Breach triggers a legal reporting duty, StayQR will handle regulatory reporting according to applicable law and lawful directions.</p>
<p>This may include reporting to CERT-In where the applicable CERT-In directions require it.</p>
<h2>11. Security Controls</h2>
<p>StayQR uses reasonable security measures appropriate to the deployed service, which may include:</p>
<ul><li>tenant-aware access controls;</li><li>row-level security;</li><li>role-based access;</li><li>private document storage;</li><li>signed/rotatable/revocable guest links;</li><li>environment separation;</li><li>security headers;</li><li>logging and diagnostics;</li><li>backup/restore procedures;</li><li>incident investigation and containment.</li></ul>
<p>No internet-connected service can guarantee absolute security.</p>
<h2>12. CERT-In Coordination</h2>
<p>Researchers may independently use CERT-In’s responsible vulnerability disclosure and coordination processes where appropriate.</p>
<p>StayQR may also coordinate with CERT-In, infrastructure providers, affected customers or lawful authorities where required for incident response.</p>
<h2>13. Confidentiality</h2>
<p>StayQR will attempt to limit disclosure of vulnerability information to persons/providers reasonably requiring it for investigation, remediation, legal compliance or coordinated disclosure.</p>
<h2>14. Changes</h2>
<p>StayQR may update this Policy as the platform, security programme or applicable law evolves.</p>
<h2>15. Contact</h2>
<p><strong>Legal Operator:</strong> Vishant Dani <strong>Trade / Business Name:</strong> StayQR Technologies <strong>Brand:</strong> StayQR <strong>Address:</strong> Dighori, Nagpur, Maharashtra – 440034, India <strong>Support:</strong> support@stayqr.in <strong>Privacy / Grievance:</strong> vishantdani@gmail.com</p>
<hr />
`

export default function SecurityResponsibleDisclosure() {
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
              <span>Security & Disclosure</span>
            </div>
          </a>
          <a className="sq-legal-home" href="/legal">Legal &amp; Policies</a>
        </div>

        <article className="sq-legal-card">
          <h1>StayQR Security + Responsible Disclosure Policy</h1>
          <p className="sq-legal-meta">
            <strong>Effective Date:</strong> 17 August 2026 &nbsp; <strong>Last Updated:</strong> 17 August 2026
          </p>
          <div dangerouslySetInnerHTML={{ __html: SECURITYRESPONSIBLEDISCLOSURE_HTML }} />
        </article>

        <p className="sq-legal-note">
          Related: <a href="/legal">Legal & Policies</a> · <a href="/privacy">Privacy</a> · <a href="/terms">Terms</a> · <a href="/support">Support</a>
        </p>
      </div>
    </main>
  )
}
