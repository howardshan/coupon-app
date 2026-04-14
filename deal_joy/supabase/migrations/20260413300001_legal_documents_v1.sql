-- =============================================================
-- Migration: 法律文书 v1 内容 + RESERVE_RATE 占位符更新
--
-- Phase 3: 插入四份文书的第一个发布版本
--   3A. Terms of Service (terms-of-service) v1
--   3B. Refund Policy (refund-policy) v1
--   3C. Merchant Agreement (merchant-agreement) v1
--   3D. Merchant Payment & Settlement Terms (payment-terms) v1
-- Phase 4: 更新 RESERVE_RATE 占位符为 100
--
-- 关键法律立场：
--   - CrunchyPlum 是 Marketplace Agent，代表商家促成交易
--   - "随时退"是商家的合同义务，由平台代商家执行
--   - Commission 仅在成功核销后收取；退款/过期时退还
--   - Service fee 在主动取消和过期场景保留（非 Store Credit 退款时）
--   - Store Credit 退款触发 Contractual Novation
-- =============================================================

DO $$
DECLARE
  v_tos_id      UUID;
  v_refund_id   UUID;
  v_merchant_id UUID;
  v_payment_id  UUID;
  v_next_ver    INTEGER;
BEGIN

-- =============================================================
-- Phase 4: 更新 RESERVE_RATE 占位符
-- =============================================================
UPDATE legal_placeholders
SET value = '100', updated_at = now()
WHERE key = 'RESERVE_RATE';

-- =============================================================
-- 3A. Terms of Service (consumer) — v1
-- =============================================================
SELECT id INTO v_tos_id FROM legal_documents WHERE slug = 'terms-of-service';
IF v_tos_id IS NOT NULL THEN
  SELECT COALESCE(MAX(version), 0) + 1 INTO v_next_ver
  FROM legal_document_versions WHERE document_id = v_tos_id;

  INSERT INTO legal_document_versions (document_id, version, content_html, summary_of_changes, published_at)
  VALUES (
    v_tos_id,
    v_next_ver,
    $HTML$
<h1>Terms of Service</h1>
<p><em>Effective Date: [EFFECTIVE DATE]<br>Last Updated: [LAST UPDATED]</em></p>

<p>Welcome to CrunchyPlum ("Platform", "we", "us", or "our"). Please read these Terms of Service carefully before using our platform.</p>

<h2>1. Platform Role and Agent Status</h2>
<p>CrunchyPlum operates as a <strong>Marketplace Agent</strong> that connects consumers with local merchants. We act as a limited agent on behalf of participating merchants to facilitate transactions. We are <strong>not</strong> a merchant of record and do not take title to any goods or services sold through the Platform.</p>
<p>When you purchase a deal on CrunchyPlum, you are entering into a transaction directly with the participating Merchant. CrunchyPlum acts as a limited payment collection agent on behalf of the Merchant solely for the purpose of accepting payments.</p>

<h2>2. Refund Rights and "Anytime Refund" Commitment</h2>
<p>The "Anytime Refund" feature reflects each participating Merchant's contractual obligation to honor pre-redemption refund requests. CrunchyPlum executes refunds as Marketplace Agent on behalf of the Merchant.</p>
<p>You may request a refund for any unredeemed coupon at any time before the coupon expires, subject to the terms below.</p>

<h2>3. Refund Amounts by Scenario</h2>
<table>
  <thead>
    <tr>
      <th>Scenario</th>
      <th>Refund to Consumer</th>
      <th>Service Fee</th>
      <th>Notes</th>
    </tr>
  </thead>
  <tbody>
    <tr>
      <td>Voluntary cancellation — original payment method</td>
      <td>Deal price + applicable tax</td>
      <td>Non-refundable</td>
      <td>Service fee covers marketplace access and transaction processing</td>
    </tr>
    <tr>
      <td>Voluntary cancellation — Store Credit</td>
      <td>Deal price + service fee + applicable tax (full amount as Store Credit)</td>
      <td>Included in Store Credit</td>
      <td>Full value returned as Store Credit when you choose this option</td>
    </tr>
    <tr>
      <td>Coupon expired (unused, auto-refund)</td>
      <td>Deal price + applicable tax</td>
      <td>Non-refundable</td>
      <td>Service fee retained to discourage speculative purchases</td>
    </tr>
    <tr>
      <td>Successfully redeemed</td>
      <td>No refund</td>
      <td>Retained</td>
      <td>Transaction complete; Merchant has fulfilled the deal</td>
    </tr>
  </tbody>
</table>
<p>Platform commission is not retained from refunded or expired coupons. Commission is collected only upon successful redemption.</p>

<h2>4. Store Credit and Novation</h2>
<p>When you elect to receive a refund as Store Credit, you agree to a <strong>Contractual Novation</strong>: your right to receive the refund amount is transferred from the original Merchant to CrunchyPlum. Upon novation:</p>
<ul>
  <li>The Merchant's refund obligation to you is extinguished.</li>
  <li>CrunchyPlum becomes the sole obligor for the Store Credit balance.</li>
  <li>Store Credit has no expiration date and remains valid for the lifetime of your account.</li>
  <li>Store Credit is non-transferable and has no cash value.</li>
</ul>

<h2>5. Service Fee</h2>
<p>A service fee of [SERVICE FEE] per coupon is charged at the time of purchase. This fee covers marketplace access, payment processing, and platform services. The service fee is non-refundable upon voluntary cancellation or coupon expiry, but is included in full Store Credit refunds.</p>

<h2>6. Taxes</h2>
<p>CrunchyPlum collects and remits sales tax as required by applicable law, including as a Marketplace Facilitator under Texas state law. Applicable tax is calculated based on the merchant's location and included in your order total.</p>

<h2>7. Governing Law</h2>
<p>These Terms are governed by the laws of the State of Texas, United States, without regard to conflict of law principles.</p>
    $HTML$,
    'Initial version: Added Agent/marketplace positioning, refund scenarios by case, Store Credit Novation clause, service fee policy.',
    now()
  );

  UPDATE legal_documents
  SET current_version = v_next_ver, updated_at = now()
  WHERE id = v_tos_id;
END IF;

-- =============================================================
-- 3B. Refund Policy — v1
-- =============================================================
SELECT id INTO v_refund_id FROM legal_documents WHERE slug = 'refund-policy';
IF v_refund_id IS NOT NULL THEN
  SELECT COALESCE(MAX(version), 0) + 1 INTO v_next_ver
  FROM legal_document_versions WHERE document_id = v_refund_id;

  INSERT INTO legal_document_versions (document_id, version, content_html, summary_of_changes, published_at)
  VALUES (
    v_refund_id,
    v_next_ver,
    $HTML$
<h1>Refund Policy</h1>
<p><em>Effective Date: [EFFECTIVE DATE]<br>Last Updated: [LAST UPDATED]</em></p>

<h2>Our Commitment</h2>
<p>CrunchyPlum offers an "Anytime Refund" policy for unredeemed coupons. This commitment is made possible because each Merchant on our platform has contractually agreed to honor pre-redemption refund requests. CrunchyPlum executes refunds as Marketplace Agent on behalf of the Merchant.</p>

<h2>Refund Eligibility</h2>
<ul>
  <li>Refunds are available for <strong>unused (unredeemed) coupons only</strong>.</li>
  <li>Once a coupon has been redeemed, refunds require a dispute process with Merchant approval.</li>
  <li>Gifted coupons follow the gift recipient's refund rights.</li>
</ul>

<h2>Refund Amounts</h2>
<table>
  <thead>
    <tr>
      <th>Scenario</th>
      <th>Amount Refunded</th>
      <th>Service Fee</th>
      <th>Platform Commission</th>
    </tr>
  </thead>
  <tbody>
    <tr>
      <td>Voluntary cancellation → Original payment method</td>
      <td>Deal price + tax</td>
      <td>Non-refundable</td>
      <td>Refunded to Merchant (platform retains $0 commission)</td>
    </tr>
    <tr>
      <td>Voluntary cancellation → Store Credit</td>
      <td>Deal price + service fee + tax (full, as Store Credit)</td>
      <td>Included in Store Credit</td>
      <td>Refunded to Merchant (platform retains $0 commission)</td>
    </tr>
    <tr>
      <td>Coupon expired unused (auto-refund)</td>
      <td>Deal price + tax</td>
      <td>Non-refundable</td>
      <td>Refunded to Merchant (platform retains $0 commission)</td>
    </tr>
    <tr>
      <td>Successfully redeemed</td>
      <td>N/A — no refund</td>
      <td>Retained</td>
      <td>Retained by platform</td>
    </tr>
  </tbody>
</table>

<h2>Service Fee Policy</h2>
<p>The service fee of [SERVICE FEE] per coupon covers marketplace access and transaction processing costs. It is <strong>non-refundable</strong> upon voluntary cancellation or coupon expiry. However, when you choose Store Credit as your refund method, the full amount including the service fee is returned as Store Credit.</p>

<h2>Why We Retain the Service Fee on Expiry</h2>
<p>The service fee upon coupon expiry is retained to prevent speculative purchasing (buying coupons without intent to use). The deal price and tax are always refunded in full on expiry.</p>

<h2>Commission Policy</h2>
<p>CrunchyPlum's platform commission is only collected when a coupon is successfully redeemed. In all refund and expiry scenarios, any commission is returned, ensuring that Merchants only pay for completed transactions.</p>

<h2>Refund Source</h2>
<p>Refunds are funded from the Merchant's reserved funds held in connection with each transaction. The Merchant authorizes CrunchyPlum to execute refunds from these reserve funds on the Merchant's behalf.</p>

<h2>Refund Processing Time</h2>
<ul>
  <li><strong>Store Credit:</strong> Instant</li>
  <li><strong>Original payment method:</strong> 5–10 business days (varies by bank/card issuer)</li>
  <li><strong>Auto-refund on expiry:</strong> Processed within 24 hours of expiration</li>
</ul>

<h2>How to Request a Refund</h2>
<p>Open the CrunchyPlum app, navigate to your Coupons, select the unused coupon, and tap "Request Refund." Choose your preferred refund method and confirm.</p>
    $HTML$,
    'Initial version: Detailed refund amounts by scenario, service fee explanation, commission policy, Merchant Reserve as refund source.',
    now()
  );

  UPDATE legal_documents
  SET current_version = v_next_ver, updated_at = now()
  WHERE id = v_refund_id;
END IF;

-- =============================================================
-- 3C. Merchant Agreement — v1
-- =============================================================
SELECT id INTO v_merchant_id FROM legal_documents WHERE slug = 'merchant-agreement';
IF v_merchant_id IS NOT NULL THEN
  SELECT COALESCE(MAX(version), 0) + 1 INTO v_next_ver
  FROM legal_document_versions WHERE document_id = v_merchant_id;

  INSERT INTO legal_document_versions (document_id, version, content_html, summary_of_changes, published_at)
  VALUES (
    v_merchant_id,
    v_next_ver,
    $HTML$
<h1>Merchant Agreement</h1>
<p><em>Effective Date: [EFFECTIVE DATE]<br>Last Updated: [LAST UPDATED]</em></p>

<p>This Merchant Agreement ("Agreement") governs your participation as a Merchant on the CrunchyPlum Marketplace Platform ("Platform"). By creating an account and listing deals, you agree to these terms.</p>

<h2>1. Platform Relationship — Agent Model</h2>
<p>CrunchyPlum acts as your <strong>Marketplace Agent</strong> to facilitate transactions between you and consumers. CrunchyPlum is not a principal buyer or reseller of your goods or services. All transactions are between you (Merchant) and the consumer, with CrunchyPlum acting solely as agent.</p>
<p>CrunchyPlum acts as your Limited Payment Collection Agent solely to accept payments from consumers on your behalf.</p>

<h2>2. Refund Obligation ("Anytime Refund")</h2>
<p>You <strong>irrevocably commit</strong> to honor all pre-redemption refund requests initiated through the Platform. Specifically:</p>
<ul>
  <li>You authorize CrunchyPlum to execute refunds on your behalf for any unused coupon, at any time before redemption.</li>
  <li>CrunchyPlum will execute such refunds from your Reserve funds (see Section 4).</li>
  <li>You may not unilaterally revoke this refund obligation for previously sold coupons.</li>
</ul>

<h2>3. Fees and Commission</h2>
<p>The Platform charges a commission of [COMMISSION RATE]% of the deal price (net of any promotional discounts) per successfully redeemed coupon.</p>
<ul>
  <li><strong>Commission is collected only upon successful redemption.</strong></li>
  <li>If a coupon is refunded (whether voluntary or expired), no commission is charged. Any previously collected commission is refunded to the consumer.</li>
  <li>Service fees charged to consumers are not shared with Merchants and are retained by the Platform.</li>
  <li>Individual commission rates may vary as specified in your Merchant onboarding agreement.</li>
</ul>

<h2>4. Payment Settlement and Reserve</h2>
<p>For each transaction, the Merchant Net Amount (deal price minus Platform commission) is transferred to your Stripe Connect account at the time of consumer payment. However, these funds are subject to a <strong>[RESERVE RATE]% Reserve</strong> until the corresponding coupon is redeemed:</p>
<ul>
  <li><strong>Reserve:</strong> [RESERVE RATE]% of your Merchant Net Amount is held as Reserve until the coupon is redeemed.</li>
  <li><strong>Release Trigger:</strong> Reserve is released upon successful coupon redemption (not on a time-based schedule).</li>
  <li><strong>Refund Priority:</strong> In refund or expiry scenarios, Reserve funds are used to execute the refund. If Reserve is insufficient, CrunchyPlum may advance funds and seek reimbursement from you.</li>
  <li><strong>Withdrawal:</strong> You may withdraw funds corresponding to redeemed coupons only, subject to any applicable settlement delay.</li>
</ul>

<h2>5. Stripe Connect Requirement</h2>
<p>You must complete Stripe Connect Express onboarding before activating any deals on the Platform. This is required to receive Merchant Net Amounts and to enable refund fund flows consistent with the Agent model.</p>

<h2>6. Store Credit Novation Authorization</h2>
<p>When a consumer elects to receive a refund as Platform Store Credit, you pre-authorize CrunchyPlum to perform a <strong>Contractual Novation</strong>:</p>
<ul>
  <li>Your refund obligation to the consumer is extinguished.</li>
  <li>CrunchyPlum assumes the obligation to honor the Store Credit.</li>
  <li>Your Reserve funds for the relevant transaction are transferred to CrunchyPlum as consideration for the novation.</li>
</ul>

<h2>7. Taxes</h2>
<p>CrunchyPlum collects and remits all applicable sales taxes as a Marketplace Facilitator under applicable law, including Texas Tax Code §151.0242. You are not responsible for collecting or remitting sales tax on transactions facilitated through the Platform.</p>

<h2>8. Governing Law</h2>
<p>This Agreement is governed by the laws of the State of Texas, United States.</p>
    $HTML$,
    'Initial version: Agent positioning, irrevocable refund obligation, Commission-on-redemption-only policy, 100% Reserve mechanism, Stripe Connect requirement, Store Credit Novation authorization.',
    now()
  );

  UPDATE legal_documents
  SET current_version = v_next_ver, updated_at = now()
  WHERE id = v_merchant_id;
END IF;

-- =============================================================
-- 3D. Merchant Payment & Settlement Terms — v1
-- =============================================================
SELECT id INTO v_payment_id FROM legal_documents WHERE slug = 'payment-terms';
IF v_payment_id IS NOT NULL THEN
  SELECT COALESCE(MAX(version), 0) + 1 INTO v_next_ver
  FROM legal_document_versions WHERE document_id = v_payment_id;

  INSERT INTO legal_document_versions (document_id, version, content_html, summary_of_changes, published_at)
  VALUES (
    v_payment_id,
    v_next_ver,
    $HTML$
<h1>Merchant Payment and Settlement Terms</h1>
<p><em>Effective Date: [EFFECTIVE DATE]<br>Last Updated: [LAST UPDATED]</em></p>

<p>These Payment and Settlement Terms ("Terms") govern how CrunchyPlum handles Merchant payments, reserves, and settlements.</p>

<h2>1. Payment Flow</h2>
<p>When a consumer purchases a deal, the transaction proceeds as follows:</p>
<ol>
  <li>The consumer pays the full amount (deal price + service fee + applicable tax) to CrunchyPlum as Limited Payment Collection Agent.</li>
  <li>The Platform commission ([COMMISSION RATE]% of deal price net of discounts) and the service fee are retained by CrunchyPlum.</li>
  <li>The <strong>Merchant Net Amount</strong> (deal price minus Platform commission) is transferred to your Stripe Connect account at the time of payment.</li>
  <li>The Merchant Net Amount is subject to a [RESERVE RATE]% Reserve (see Section 2).</li>
</ol>

<h2>2. Reserve Mechanism</h2>
<p>A Reserve of <strong>[RESERVE RATE]%</strong> of your Merchant Net Amount is held for each transaction:</p>
<ul>
  <li><strong>Purpose:</strong> To fund refunds in accordance with the Merchant Agreement's refund obligation and to maintain Marketplace Agent status under applicable law.</li>
  <li><strong>Release Trigger:</strong> Reserve is released upon <strong>successful coupon redemption</strong>. There is no time-based automatic release — the release event is the redemption event.</li>
  <li><strong>Refund Use:</strong> If a refund is requested before redemption, Reserve funds are used to execute the refund. This includes voluntary cancellations and auto-refunds on coupon expiry.</li>
  <li><strong>Expiry Refunds:</strong> For expired unused coupons, the Reserve is used to refund the consumer (deal price + tax). The service fee is retained by the Platform from the application fee, not from your Reserve.</li>
</ul>

<h2>3. Settlement Schedule</h2>
<ul>
  <li>Funds become available for withdrawal after coupon redemption, subject to a settlement delay to accommodate potential chargeback disputes.</li>
  <li>Commission is deducted only upon successful redemption. No commission is charged for refunded or expired coupons.</li>
</ul>

<h2>4. Withdrawal Conditions</h2>
<p>You may initiate a withdrawal of settled funds subject to the following conditions:</p>
<ul>
  <li>Funds correspond to redeemed coupons (Reserve has been released).</li>
  <li>No outstanding refunds or disputes are pending against the relevant transactions.</li>
  <li>Your Stripe Connect account is in good standing.</li>
  <li>Minimum withdrawal amount: $10.00 USD.</li>
</ul>

<h2>5. Refund Fund Priority</h2>
<p>In the event of a refund:</p>
<ol>
  <li>Funds are drawn from your Reserve first.</li>
  <li>If Reserve is insufficient (e.g., due to a disputed amount), CrunchyPlum may advance the refund and seek reimbursement from you.</li>
  <li>Platform commission collected is returned to the consumer as part of the refund. CrunchyPlum does not retain commission on refunded transactions.</li>
  <li>Platform service fee is retained by CrunchyPlum in voluntary cancellation and expiry scenarios (non-Store Credit refunds).</li>
</ol>

<h2>6. Stripe Connect</h2>
<p>All Merchant payments are processed through Stripe Connect Express. You must maintain an active, verified Stripe Connect account to receive payments and to activate deals on the Platform. CrunchyPlum reserves the right to withhold settlement if your Stripe Connect account is restricted or unverified.</p>

<h2>7. Taxes</h2>
<p>CrunchyPlum remits applicable sales taxes collected from consumers. Tax amounts are not included in your Merchant Net Amount and do not affect your commission calculation.</p>

<h2>8. Currency</h2>
<p>All amounts are in United States Dollars (USD).</p>
    $HTML$,
    'Initial version: 100% Reserve rate, redemption-triggered settlement release, refund fund priority, commission-on-redemption-only policy, Stripe Connect requirement.',
    now()
  );

  UPDATE legal_documents
  SET current_version = v_next_ver, updated_at = now()
  WHERE id = v_payment_id;
END IF;

END $$;
