// src/pages/legal/SubscriptionPolicy.jsx

const SUBSCRIPTIONPOLICY_HTML = String.raw`
<p>This Policy explains the standard subscription, cancellation, plan-change and refund rules for StayQR.</p>
<p>It supplements the StayQR Terms of Service. The applicable checkout, invoice, subscription screen, written proposal or separately signed agreement controls where it expressly states different commercial terms.</p>
<h2>1. Standard Plans</h2>
<h3>Starter</h3>
<ul><li>₹999 per month</li><li>₹9,999 per year</li><li>up to 20 rooms</li><li>1 property</li><li>14-day trial</li></ul>
<h3>Growth</h3>
<ul><li>₹2,499 per month</li><li>₹24,999 per year</li><li>up to 50 rooms</li><li>1 property</li><li>14-day trial</li></ul>
<h3>Scale</h3>
<ul><li>₹4,999 per month</li><li>₹49,999 per year</li><li>up to 100 rooms</li><li>1 property</li><li>14-day trial</li></ul>
<h3>Enterprise / Custom</h3>
<p>Commercial terms are separately agreed.</p>
<p>Taxes, if applicable, may be added or handled according to the applicable invoice/checkout and law.</p>
<h2>2. Trial</h2>
<p>The standard trial period is 14 days unless StayQR states otherwise in writing.</p>
<p>A trial is for evaluation and may:</p>
<ul><li>have feature or usage limits;</li><li>expire automatically;</li><li>require conversion to a paid subscription for continued access;</li><li>be extended only at StayQR’s discretion.</li></ul>
<p>A trial does not guarantee continued access after expiry.</p>
<h2>3. Paid Activation</h2>
<p>Paid access begins after successful payment and subscription activation.</p>
<p>Where payment succeeds but the purchased service does not activate, the Customer should contact support@stayqr.in so StayQR can investigate and attempt reasonable remediation.</p>
<h2>4. Renewal</h2>
<p>Renewal is <strong>not assumed automatic</strong> unless the checkout, payment authorisation, subscription screen or written commercial terms expressly establish automatic renewal.</p>
<p>Where automatic renewal is enabled, the Customer authorises the applicable recurring charge in accordance with the payment arrangement and may cancel future renewal in accordance with this Policy.</p>
<h2>5. Cancellation</h2>
<p>A Customer may request cancellation at any time through available account functionality or by contacting support@stayqr.in.</p>
<p>Unless otherwise stated:</p>
<ul><li>cancellation prevents the next renewal;</li><li>already-paid access normally continues until the end of the current paid subscription period;</li><li>convenience cancellation does not automatically create a refund for unused time;</li><li>access may end earlier where suspension/termination is permitted under the Terms or required by law/security.</li></ul>
<h2>6. Monthly Plans</h2>
<p>For a monthly plan, cancellation normally becomes effective at the end of the already-paid monthly period.</p>
<p>No automatic pro-rata refund is provided for unused days after a convenience cancellation.</p>
<h2>7. Annual Plans</h2>
<p>For an annual plan, cancellation normally prevents the next annual renewal while access continues through the already-paid annual period.</p>
<p>No automatic pro-rata refund is provided for unused months after a convenience cancellation.</p>
<p>Customers should use the 14-day trial to evaluate suitability before committing to an annual plan.</p>
<h2>8. Refund Eligibility</h2>
<p>Standard subscription payments are generally non-refundable after the paid service has been successfully activated.</p>
<p>StayQR may provide a full or partial refund, correction or reversal where:</p>
<ul><li>the same charge was duplicated;</li><li>an amount was charged in error;</li><li>payment succeeded but StayQR failed to activate the purchased service and did not remedy the activation failure within a reasonable opportunity after notice;</li><li>StayQR expressly promised a refund in writing;</li><li>a separately signed agreement provides a refund;</li><li>applicable law creates a non-waivable refund or consumer remedy.</li></ul>
<p>A temporary outage, ordinary defect or convenience cancellation does not automatically create a refund right unless the applicable law or written commercial commitment requires one.</p>
<h2>9. Refund Requests</h2>
<p>Refund/billing-correction requests should be sent to:</p>
<p><strong>support@stayqr.in</strong></p>
<p>The request should include:</p>
<ul><li>Hotel/property name;</li><li>account email;</li><li>payment/order reference;</li><li>payment date and amount;</li><li>reason for the request.</li></ul>
<p>Do not send full payment-card credentials.</p>
<p>StayQR may request reasonable verification before processing a financial correction.</p>
<h2>10. Payment Provider Processing</h2>
<p>Payments may be processed using Cashfree or another payment provider.</p>
<p>Payment-provider processing times, bank settlement times and reversal timelines may affect when an approved refund appears in the Customer’s account.</p>
<p>StayQR does not control the independent processing time of banks/payment networks.</p>
<h2>11. Failed or Pending Payments</h2>
<p>A failed or pending payment does not by itself guarantee activation.</p>
<p>StayQR may retry, request a new payment, reconcile payment status or leave the subscription inactive until successful payment is confirmed.</p>
<h2>12. Upgrades</h2>
<p>Upgrades and plan changes follow the price, effective date and billing treatment shown in the applicable checkout, invoice, subscription screen or written proposal.</p>
<p>StayQR does not promise automatic pro-rata calculations unless the relevant transaction expressly shows them.</p>
<h2>13. Downgrades</h2>
<p>Unless the applicable order says otherwise, a downgrade normally takes effect at the next renewal.</p>
<p>Before downgrade, the Customer may be required to reduce usage to fit the destination plan’s room, property or feature limits.</p>
<p>StayQR may restrict features that are not included in the downgraded plan after the downgrade becomes effective.</p>
<h2>14. Room and Property Limits</h2>
<p>The standard public room limits are contractual plan limits, not a representation that the technical platform cannot support larger deployments.</p>
<p>Hotels requiring more than 100 rooms, multiple properties or custom commercial terms should use Enterprise / Custom arrangements.</p>
<h2>15. Suspension and Non-Payment</h2>
<p>StayQR may suspend or restrict service for:</p>
<ul><li>unpaid amounts;</li><li>payment failure;</li><li>fraud or chargeback risk;</li><li>material Terms/AUP breach;</li><li>security risk;</li><li>lawful requirement.</li></ul>
<p>Where reasonably practicable, StayQR will provide notice and an opportunity to cure ordinary non-payment before material suspension.</p>
<h2>16. Chargebacks and Disputes</h2>
<p>Customers should contact StayQR first where they believe a charge is incorrect.</p>
<p>Fraudulent or abusive chargebacks may result in suspension or termination.</p>
<p>Nothing in this section prevents use of a lawful payment-dispute right.</p>
<h2>17. Pricing Changes</h2>
<p>StayQR may change public pricing or packaging prospectively.</p>
<p>A pricing change applies to a future purchase, renewal or plan change as disclosed through the applicable checkout, invoice, subscription screen, proposal or notice.</p>
<p>Already-paid periods are not retroactively repriced.</p>
<h2>18. Consumer / Statutory Rights</h2>
<p>Nothing in this Policy excludes a refund, remedy, complaint right or other protection that cannot lawfully be excluded under applicable law.</p>
<p>StayQR is primarily offered as a business hospitality SaaS service, but where consumer-protection law validly applies to a particular transaction, mandatory protections remain available.</p>
<h2>19. Termination</h2>
<p>Termination effects are governed by the StayQR Terms, DPA, Privacy Policy and this Policy.</p>
<p>Termination does not require StayQR to erase records that must lawfully or reasonably be retained for financial, security, fraud, audit, dispute or compliance purposes.</p>
<h2>20. Changes</h2>
<p>StayQR may update this Policy prospectively. Material changes affecting active paid subscriptions will receive reasonable notice where appropriate.</p>
<h2>21. Contact</h2>
<p><strong>Legal Operator:</strong> Vishant Dani <strong>Trade / Business Name:</strong> StayQR Technologies <strong>Brand:</strong> StayQR <strong>Address:</strong> Dighori, Nagpur, Maharashtra – 440034, India <strong>Support:</strong> support@stayqr.in <strong>Privacy / Grievance:</strong> vishantdani@gmail.com</p>
<hr />
`

export default function SubscriptionPolicy() {
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
              <span>Subscription & Billing</span>
            </div>
          </a>
          <a className="sq-legal-home" href="/legal">Legal &amp; Policies</a>
        </div>

        <article className="sq-legal-card">
          <h1>StayQR Subscription / Cancellation / Refund Policy</h1>
          <p className="sq-legal-meta">
            <strong>Effective Date:</strong> 17 August 2026 &nbsp; <strong>Last Updated:</strong> 17 August 2026
          </p>
          <div dangerouslySetInnerHTML={{ __html: SUBSCRIPTIONPOLICY_HTML }} />
        </article>

        <p className="sq-legal-note">
          Related: <a href="/legal">Legal & Policies</a> · <a href="/privacy">Privacy</a> · <a href="/terms">Terms</a> · <a href="/support">Support</a>
        </p>
      </div>
    </main>
  )
}
