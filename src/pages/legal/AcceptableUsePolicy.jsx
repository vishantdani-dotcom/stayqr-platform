// src/pages/legal/AcceptableUsePolicy.jsx

const ACCEPTABLEUSEPOLICY_HTML = String.raw`
<p>This Acceptable Use Policy (“AUP”) forms part of the StayQR Terms of Service and governs use of StayQR by Customers, Hotel owners, administrators, staff and other authorised users.</p>
<p>The service is operated by <strong>Vishant Dani, operating under the trade name StayQR Technologies and the brand StayQR</strong>.</p>
<h2>1. Lawful and Authorised Use</h2>
<p>StayQR may be used only for lawful hospitality, Hotel, guest-service, reservation, operational, billing, support and other purposes permitted by the StayQR Terms and the Customer’s applicable subscription.</p>
<p>Users must have appropriate authority to access the Hotel account, Hotel data and any personal data entered into StayQR.</p>
<h2>2. Prohibited Activities</h2>
<p>You must not use StayQR to:</p>
<ul><li>violate applicable law, regulation, court order or lawful government direction;</li><li>commit fraud, impersonation, deception, phishing, identity theft or payment abuse;</li><li>upload, distribute or facilitate malware, ransomware, spyware, malicious code or destructive content;</li><li>obtain or attempt unauthorised access to another Hotel, tenant, user, guest, system, account, credential, token, API, database or storage resource;</li><li>bypass tenant isolation, role restrictions, authentication, rate limits, room limits, subscription controls or other technical safeguards;</li><li>probe, scan or test StayQR security except under the StayQR Security + Responsible Disclosure Policy;</li><li>interfere with, overload, degrade or disrupt StayQR or supporting infrastructure;</li><li>use automated scraping, extraction or high-volume access in a manner that materially harms the service or violates another person’s rights;</li><li>knowingly enter false, fraudulent or unlawfully obtained KYC, identity, payment or guest information;</li><li>use StayQR to send unlawful spam, deceptive promotions or communications without required authority or consent;</li><li>infringe intellectual-property, privacy, confidentiality or other legal rights;</li><li>access, copy or disclose another Hotel’s or person’s data without lawful authority;</li><li>reverse engineer, circumvent or misuse the service except to the extent a restriction is prohibited by applicable law;</li><li>resell, sublicense or commercially exploit StayQR except under a written arrangement permitting it.</li></ul>
<h2>3. Customer Responsibility</h2>
<p>The Customer is responsible for:</p>
<ul><li>users it authorises;</li><li>role and permission configuration;</li><li>credential protection;</li><li>lawful Hotel data collection;</li><li>actions performed through its authorised accounts;</li><li>promptly removing access for persons who should no longer have access.</li></ul>
<h2>4. Guest and KYC Data</h2>
<p>Hotels must not collect unnecessary identity/KYC information through StayQR.</p>
<p>Where identity information is legally required, the Hotel should use minimisation, masking or redaction where legally permitted and operationally appropriate.</p>
<p>StayQR must not be used to create unofficial identity repositories, sell identity information or collect sensitive information unrelated to a legitimate Hotel purpose.</p>
<h2>5. Messaging and External Services</h2>
<p>Where StayQR provides links or workflows involving WhatsApp, email, review platforms, payment providers or other external services, the Customer must comply with the external provider’s terms and applicable law.</p>
<p>StayQR does not currently authorise use of the platform for unsolicited bulk promotional messaging.</p>
<h2>6. Security Testing</h2>
<p>Security research must follow the StayQR Security + Responsible Disclosure Policy.</p>
<p>Without written permission, users must not conduct denial-of-service testing, destructive testing, social engineering, credential attacks, persistence, mass scanning or testing that accesses another customer’s data.</p>
<h2>7. Fair Use and Technical Protection</h2>
<p>StayQR may use reasonable technical controls to protect service availability, security and contractual plan limits.</p>
<p>Activity that causes unusual load, excessive automated requests, material degradation or security risk may be limited or temporarily blocked while investigated.</p>
<h2>8. Enforcement</h2>
<p>StayQR may investigate suspected AUP violations and may:</p>
<ul><li>warn the Customer;</li><li>require corrective action;</li><li>limit the affected feature;</li><li>suspend an account or user where reasonably necessary;</li><li>terminate service for material or repeated violations;</li><li>preserve or disclose information where lawfully required;</li><li>cooperate with lawful authorities.</li></ul>
<p>Where practicable and safe, StayQR will attempt proportionate action rather than unnecessary broad suspension.</p>
<h2>9. Emergency Action</h2>
<p>StayQR may act immediately without prior notice where reasonably necessary to address:</p>
<ul><li>a material security incident;</li><li>active abuse;</li><li>unlawful access;</li><li>threat to another tenant;</li><li>fraud;</li><li>data-integrity risk;</li><li>legal or regulatory requirement.</li></ul>
<h2>10. Relationship with Other Policies</h2>
<p>This AUP supplements the StayQR Terms of Service, Privacy Policy, DPA, SLA / Service Commitments, Support + Escalation Policy and Security + Responsible Disclosure Policy.</p>
<p>If a separately signed agreement expressly conflicts with this AUP, the signed agreement controls to the extent of that conflict.</p>
<h2>11. Changes</h2>
<p>StayQR may update this AUP to address new abuse patterns, security risks, legal requirements or service changes. Material changes will receive reasonable notice where appropriate.</p>
<h2>12. Contact</h2>
<p><strong>Legal Operator:</strong> Vishant Dani <strong>Trade / Business Name:</strong> StayQR Technologies <strong>Brand:</strong> StayQR <strong>Address:</strong> Dighori, Nagpur, Maharashtra – 440034, India <strong>Support:</strong> support@stayqr.in <strong>Privacy / Grievance:</strong> vishantdani@gmail.com</p>
<hr />
`

export default function AcceptableUsePolicy() {
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
              <span>Acceptable Use</span>
            </div>
          </a>
          <a className="sq-legal-home" href="/legal">Legal &amp; Policies</a>
        </div>

        <article className="sq-legal-card">
          <h1>StayQR Acceptable Use Policy (AUP)</h1>
          <p className="sq-legal-meta">
            <strong>Effective Date:</strong> 17 August 2026 &nbsp; <strong>Last Updated:</strong> 17 August 2026
          </p>
          <div dangerouslySetInnerHTML={{ __html: ACCEPTABLEUSEPOLICY_HTML }} />
        </article>

        <p className="sq-legal-note">
          Related: <a href="/legal">Legal & Policies</a> · <a href="/privacy">Privacy</a> · <a href="/terms">Terms</a> · <a href="/support">Support</a>
        </p>
      </div>
    </main>
  )
}
