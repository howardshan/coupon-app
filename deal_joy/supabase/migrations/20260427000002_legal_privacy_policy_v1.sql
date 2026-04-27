-- ============================================================
-- Privacy Policy v1 — 发布初始版本
-- App Store / Google Play 合规要求
-- ============================================================

DO $$
DECLARE
  v_doc_id    UUID;
  v_next_ver  INTEGER;
BEGIN

SELECT id INTO v_doc_id FROM legal_documents WHERE slug = 'privacy-policy';
IF v_doc_id IS NULL THEN
  RAISE NOTICE 'privacy-policy document not found, skipping';
  RETURN;
END IF;

SELECT COALESCE(MAX(version), 0) + 1 INTO v_next_ver
FROM legal_document_versions WHERE document_id = v_doc_id;

INSERT INTO legal_document_versions (
  document_id, version, content_html, summary_of_changes, published_at
) VALUES (
  v_doc_id,
  v_next_ver,
  $HTML$
<h1>Privacy Policy</h1>
<p><em>Effective Date: [EFFECTIVE DATE]<br>Last Updated: [LAST UPDATED]</em></p>

<p>CrunchyPlum ("Platform", "we", "us", or "our") is committed to protecting your privacy. This Privacy Policy explains how we collect, use, disclose, and protect your personal information when you use our mobile application and services.</p>

<h2>1. Information We Collect</h2>

<h3>1.1 Account Information</h3>
<ul>
  <li>Name, email address, and password when you register</li>
  <li>Profile photo (optional)</li>
  <li>Date of birth (for age verification where required)</li>
  <li>Phone number (optional, for account recovery)</li>
</ul>

<h3>1.2 Transaction Information</h3>
<ul>
  <li>Purchase history, coupon status, and redemption records</li>
  <li>Refund requests and Store Credit balances</li>
  <li>Payment method details (stored and processed by Stripe; we do not store full card numbers)</li>
  <li>Billing address</li>
</ul>

<h3>1.3 Location Information</h3>
<ul>
  <li>Approximate GPS coordinates when you grant location permission, used to show nearby deals and send geo-targeted push notifications</li>
  <li>City or region selected manually if you prefer not to share GPS</li>
  <li>We do not track your location continuously in the background</li>
</ul>

<h3>1.4 Device and Usage Information</h3>
<ul>
  <li>Device type, operating system, and app version</li>
  <li>Firebase Cloud Messaging (FCM) token for push notifications</li>
  <li>App usage patterns (screens visited, features used) for service improvement</li>
  <li>IP address and locale</li>
</ul>

<h3>1.5 Communications</h3>
<ul>
  <li>Messages sent through in-app support chat</li>
  <li>Review content you submit for merchants and deals</li>
</ul>

<h2>2. How We Use Your Information</h2>
<ul>
  <li><strong>Provide the Service:</strong> Process purchases, issue coupons, handle refunds, and facilitate redemptions</li>
  <li><strong>Push Notifications:</strong> Send deal alerts and promotional notifications based on your location and preferences (you may opt out in device settings)</li>
  <li><strong>Tax Compliance:</strong> Calculate and remit sales tax as required by Texas law and applicable regulations</li>
  <li><strong>Customer Support:</strong> Respond to inquiries and resolve disputes</li>
  <li><strong>Legal Compliance:</strong> Maintain consent records, audit logs, and fulfill legal obligations</li>
  <li><strong>Safety and Fraud Prevention:</strong> Detect and prevent fraudulent transactions</li>
  <li><strong>Service Improvement:</strong> Analyze usage patterns to improve the Platform</li>
</ul>

<h2>3. Information Sharing</h2>
<p>We do not sell your personal information. We share information only as follows:</p>

<h3>3.1 Merchants</h3>
<p>When you redeem a coupon, we share your name and redemption details with the Merchant solely to verify and complete your transaction.</p>

<h3>3.2 Service Providers</h3>
<ul>
  <li><strong>Stripe:</strong> Payment processing and Merchant settlement (governed by Stripe's Privacy Policy)</li>
  <li><strong>Firebase / Google:</strong> Push notification delivery and analytics</li>
  <li><strong>Supabase:</strong> Database and authentication infrastructure</li>
</ul>

<h3>3.3 Legal Requirements</h3>
<p>We may disclose information when required by law, court order, or to protect the rights and safety of our users or the public.</p>

<h2>4. Data Retention</h2>
<ul>
  <li>Account data is retained for the lifetime of your account plus 3 years after deletion for legal compliance</li>
  <li>Transaction and audit records are retained for 7 years as required by financial regulations</li>
  <li>Location data (GPS coordinates) is updated on each app login and not retained historically</li>
  <li>Support chat messages are retained for 2 years</li>
</ul>

<h2>5. Your Rights</h2>
<p>You have the following rights regarding your personal information:</p>
<ul>
  <li><strong>Access:</strong> Request a copy of the personal data we hold about you</li>
  <li><strong>Correction:</strong> Update inaccurate or incomplete information via your profile settings</li>
  <li><strong>Deletion:</strong> Request deletion of your account and associated data (subject to legal retention requirements)</li>
  <li><strong>Opt-Out of Push Notifications:</strong> Disable notifications in your device settings at any time</li>
  <li><strong>Location Permission:</strong> Revoke location access at any time in your device settings; the app will still function without it</li>
</ul>
<p>To exercise these rights, contact us at [PRIVACY EMAIL].</p>

<h2>6. Children's Privacy</h2>
<p>CrunchyPlum is not directed at children under the age of 13. We do not knowingly collect personal information from children under 13. If you believe a child has provided us with their information, please contact us at [SUPPORT EMAIL].</p>

<h2>7. Security</h2>
<p>We implement industry-standard security measures including encryption in transit (TLS), encrypted storage, access controls, and regular security reviews. However, no method of transmission over the internet is 100% secure.</p>

<h2>8. Third-Party Links</h2>
<p>The Platform may contain links to third-party websites or services. We are not responsible for the privacy practices of those third parties.</p>

<h2>9. Changes to This Policy</h2>
<p>We may update this Privacy Policy from time to time. If we make material changes, we will notify you through the app and require your acknowledgment before you can continue using the Platform. The "Last Updated" date at the top reflects when this policy was last revised.</p>

<h2>10. Contact Us</h2>
<p>For privacy-related inquiries or to exercise your rights, please contact:</p>
<ul>
  <li><strong>Email:</strong> [PRIVACY EMAIL]</li>
  <li><strong>Mailing Address:</strong> CrunchyPlum, [ADDRESS]</li>
  <li><strong>Support:</strong> [SUPPORT EMAIL]</li>
</ul>

<h2>11. Governing Law</h2>
<p>This Privacy Policy is governed by the laws of the State of Texas, United States.</p>
  $HTML$,
  'Initial version: Covers data collection (account, transaction, location, device), usage purposes, Stripe/Firebase sharing, user rights, CCPA-aligned deletion rights, and contact information.',
  now()
);

UPDATE legal_documents
SET current_version = v_next_ver, updated_at = now()
WHERE id = v_doc_id;

RAISE NOTICE 'Privacy Policy v% published successfully', v_next_ver;

END $$;
