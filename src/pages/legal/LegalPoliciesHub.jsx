// src/pages/legal/LegalPoliciesHub.jsx

const groups = [
  {
    title: 'Privacy & Data',
    items: [
      { href: '/privacy', title: 'Privacy Policy', description: 'How StayQR handles personal data across the platform and guest-facing services.' },
      { href: '/dpa', title: 'Data Processing Agreement', description: 'Hotel / StayQR data-processing responsibilities and processor commitments.' },
      { href: '/cookies', title: 'Cookie & Browser Storage Notice', description: 'Current use of functional browser storage, cookies and similar technologies.' },
    ],
  },
  {
    title: 'Service & Commercial',
    items: [
      { href: '/terms', title: 'Terms of Service', description: 'Core contractual terms for use of StayQR.' },
      { href: '/aup', title: 'Acceptable Use Policy', description: 'Rules for lawful, secure and authorised use of StayQR.' },
      { href: '/sla', title: 'SLA / Service Commitments', description: 'Availability target, maintenance and standard service commitments.' },
      { href: '/support', title: 'Support + Escalation Policy', description: 'Support hours, severity levels, acknowledgement targets and escalation.' },
      { href: '/subscription-policy', title: 'Subscription / Cancellation / Refund Policy', description: 'Plan, cancellation, renewal, refund and billing rules.' },
    ],
  },
  {
    title: 'Security',
    items: [
      { href: '/security', title: 'Security + Responsible Disclosure', description: 'How to report vulnerabilities and boundaries for good-faith security research.' },
    ],
  },
]

export default function LegalPoliciesHub() {
  return (
    <main className="sq-legal-hub">
      <style>{`
        .sq-legal-hub {
          min-height: 100vh;
          background: #09090b;
          color: #f4f4f5;
          padding: 28px 18px 64px;
          font-family: Inter, system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
        }
        .sq-legal-hub-shell { width: min(1040px, 100%); margin: 0 auto; }
        .sq-legal-hub-top {
          display: flex; align-items: center; justify-content: space-between;
          gap: 18px; margin-bottom: 26px;
        }
        .sq-legal-hub-brand { display: flex; gap: 12px; align-items: center; color: #fff; text-decoration: none; }
        .sq-legal-hub-brand img { width: 44px; height: 44px; object-fit: contain; }
        .sq-legal-hub-brand strong { display: block; font-size: 15px; }
        .sq-legal-hub-brand span { display: block; margin-top: 3px; color: #a1a1aa; font-size: 11px; }
        .sq-legal-hub-home { color: #e8c75c; text-decoration: none; font-weight: 700; font-size: 13px; }
        .sq-legal-hub-hero {
          border: 1px solid #303036; border-radius: 18px; padding: clamp(24px, 5vw, 48px);
          background: #151517; margin-bottom: 24px;
        }
        .sq-legal-hub-hero h1 { margin: 0 0 12px; font-size: clamp(34px, 5vw, 50px); }
        .sq-legal-hub-hero p { color: #b8b8bf; line-height: 1.7; max-width: 760px; margin: 0; }
        .sq-legal-group { margin-top: 28px; }
        .sq-legal-group h2 { color: #e8c75c; font-size: 19px; margin: 0 0 12px; }
        .sq-legal-grid { display: grid; grid-template-columns: repeat(2, minmax(0, 1fr)); gap: 12px; }
        .sq-legal-card-link {
          display: block; border: 1px solid #2f2f35; border-radius: 14px; padding: 18px;
          background: #131315; color: inherit; text-decoration: none;
        }
        .sq-legal-card-link:hover { border-color: #6f5e27; background: #171713; }
        .sq-legal-card-link strong { display: block; font-size: 15px; color: #fff; margin-bottom: 6px; }
        .sq-legal-card-link span { color: #9f9fa8; font-size: 13px; line-height: 1.55; }
        .sq-legal-contact {
          margin-top: 28px; border-top: 1px solid #25252a; padding-top: 20px;
          color: #9f9fa8; font-size: 13px; line-height: 1.7;
        }
        .sq-legal-contact a { color: #e8c75c; }
        @media (max-width: 720px) {
          .sq-legal-grid { grid-template-columns: 1fr; }
          .sq-legal-hub { padding: 18px 12px 48px; }
        }
      `}</style>

      <div className="sq-legal-hub-shell">
        <div className="sq-legal-hub-top">
          <a className="sq-legal-hub-brand" href="https://stayqr.in">
            <img src="/assets/stayqr-official-logo.png" alt="StayQR" />
            <div>
              <strong>StayQR</strong>
              <span>Legal, Privacy, Service &amp; Security</span>
            </div>
          </a>
          <a className="sq-legal-hub-home" href="https://stayqr.in">stayqr.in</a>
        </div>

        <section className="sq-legal-hub-hero">
          <h1>Legal &amp; Policies</h1>
          <p>
            StayQR’s current legal, privacy, commercial, service and security documents are available here in one place.
            These documents apply according to their scope and the applicable StayQR service relationship.
          </p>
        </section>

        {groups.map((group) => (
          <section className="sq-legal-group" key={group.title}>
            <h2>{group.title}</h2>
            <div className="sq-legal-grid">
              {group.items.map((item) => (
                <a className="sq-legal-card-link" href={item.href} key={item.href}>
                  <strong>{item.title}</strong>
                  <span>{item.description}</span>
                </a>
              ))}
            </div>
          </section>
        ))}

        <div className="sq-legal-contact">
          Legal Operator: Vishant Dani, operating under the trade name StayQR Technologies and the brand StayQR.<br />
          Support: <a href="mailto:support@stayqr.in">support@stayqr.in</a> · Privacy / Grievance: <a href="mailto:vishantdani@gmail.com">vishantdani@gmail.com</a>
        </div>
      </div>
    </main>
  )
}
