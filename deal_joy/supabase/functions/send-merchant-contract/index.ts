// send-merchant-contract
// 从管理后台调用，将商家合同通过 DocuSign 发送给商家签署
// 入参: { contract_id: string }
// 商家合同里包含佣金率、促销期、$500 违约金条款
// 商家在 DocuSign 中需自行填写 Business / DBA Name

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { createSign } from "node:crypto";

const supabase = createClient(
  Deno.env.get("SUPABASE_URL") ?? "",
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
);

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

function errorResponse(message: string, status = 400) {
  return new Response(JSON.stringify({ error: message }), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

// ── Base64Url 编码工具 ──────────────────────────────────────────────────────

function base64UrlEncode(str: string): string {
  const b64 = btoa(unescape(encodeURIComponent(str)));
  return b64.replace(/\+/g, "-").replace(/\//g, "_").replace(/=/g, "");
}

function b64ToB64Url(b64: string): string {
  return b64.replace(/\+/g, "-").replace(/\//g, "_").replace(/=/g, "");
}

// ── DocuSign JWT 认证 ───────────────────────────────────────────────────────
// 使用 RSA-SHA256 签名 JWT，换取 DocuSign access token
// 需提前在 DocuSign 账户授权 JWT grant consent

interface DocuSignAuth {
  accessToken: string;
  accountId: string;
  apiBaseUrl: string;
}

async function getDocuSignAccessToken(): Promise<DocuSignAuth> {
  const integrationKey = Deno.env.get("DOCUSIGN_INTEGRATION_KEY") ?? "";
  const userId = Deno.env.get("DOCUSIGN_USER_ID") ?? "";
  // DOCUSIGN_RSA_PRIVATE_KEY_B64 存储 base64 编码的 PEM，解码还原多行私钥
  const privateKeyRaw = Deno.env.get("DOCUSIGN_RSA_PRIVATE_KEY_B64") ?? "";
  const privateKeyPem = privateKeyRaw.startsWith("-----")
    ? privateKeyRaw
    : new TextDecoder().decode(
        Uint8Array.from(atob(privateKeyRaw), (c) => c.charCodeAt(0)),
      );
  const baseUrl = Deno.env.get("DOCUSIGN_AUTH_BASE_URL") ??
    "https://account-d.docusign.com";

  const now = Math.floor(Date.now() / 1000);
  const header = { alg: "RS256", typ: "JWT" };
  const payload = {
    iss: integrationKey,
    sub: userId,
    aud: baseUrl.replace("https://", ""),
    iat: now,
    exp: now + 3600,
    scope: "signature impersonation",
  };

  const headerB64 = base64UrlEncode(JSON.stringify(header));
  const payloadB64 = base64UrlEncode(JSON.stringify(payload));
  const signingInput = `${headerB64}.${payloadB64}`;

  // node:crypto createSign 支持 PKCS#1 PEM 格式私钥
  const sign = createSign("RSA-SHA256");
  sign.update(signingInput);
  const signature = sign.sign(privateKeyPem, "base64");
  const sigB64Url = b64ToB64Url(signature);

  const jwt = `${signingInput}.${sigB64Url}`;

  const tokenResponse = await fetch(`${baseUrl}/oauth/token`, {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion: jwt,
    }),
  });

  if (!tokenResponse.ok) {
    const body = await tokenResponse.text();
    throw new Error(`DocuSign JWT auth failed: ${body}`);
  }

  const data = await tokenResponse.json();
  const accessToken = data.access_token as string;

  // 通过 userinfo 获取实际的 accountId 和 API base URI
  // 避免因 account ID 配置不匹配导致 PARTNER_AUTHENTICATION_FAILED
  const userInfoResp = await fetch(`${baseUrl}/oauth/userinfo`, {
    headers: { Authorization: `Bearer ${accessToken}` },
  });
  if (!userInfoResp.ok) {
    throw new Error(`DocuSign userinfo failed: ${await userInfoResp.text()}`);
  }
  const userInfo = await userInfoResp.json();
  // 取第一个账户的 accountId 和 baseUri
  const account = userInfo.accounts?.[0];
  if (!account) {
    throw new Error("DocuSign: no accounts found in userinfo");
  }
  return {
    accessToken,
    accountId: account.account_id as string,
    apiBaseUrl: account.base_uri as string, // e.g. "https://demo.docusign.net"
  };
}

// ── 合同 HTML 生成 ──────────────────────────────────────────────────────────
// 将合同模板填充商家专属佣金率，并嵌入 DocuSign anchor 标记：
//   \s1\  → 签名 tab
//   \d1\  → 日期 tab
//   \bn1\ → 商家自填 Business/DBA Name 文字 tab

function generateContractHtml(contract: {
  recipient_name: string;
  promo_months: number;
  promo_commission_rate: number;
  standard_commission_rate: number;
  booster_credit_amount: number;
  cp_signer_name?: string;
}): string {
  const today = new Date().toLocaleDateString("en-US", {
    year: "numeric",
    month: "long",
    day: "numeric",
  });
  const year = new Date().getFullYear();
  const promoRate = (contract.promo_commission_rate * 100).toFixed(1);
  const standardRate = (contract.standard_commission_rate * 100).toFixed(1);

  return `<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8">
<style>
  body { font-family: Arial, sans-serif; font-size: 11pt; line-height: 1.6; color: #222; margin: 0; padding: 40px 50px; max-width: 800px; }
  h1 { font-size: 18pt; text-align: center; margin-bottom: 4px; }
  h2 { font-size: 13pt; margin-top: 28px; margin-bottom: 6px; border-bottom: 1px solid #bbb; padding-bottom: 4px; }
  h3 { font-size: 11pt; margin-top: 14px; margin-bottom: 4px; }
  p { margin: 6px 0; }
  .center { text-align: center; }
  .notice { border: 2px solid #c00; padding: 12px 16px; margin: 20px 0; font-weight: bold; font-size: 10.5pt; }
  .schedule { width: 100%; border-collapse: collapse; margin: 12px 0; }
  .schedule th, .schedule td { border: 1px solid #999; padding: 8px 12px; }
  .schedule th { background: #f0f0f0; text-align: left; }
  .sig-block { margin-top: 60px; page-break-inside: avoid; }
  .sig-section { margin-bottom: 32px; }
  .sig-label { font-weight: bold; margin-bottom: 2px; }
  .sig-line { border-bottom: 1px solid #000; min-height: 28px; width: 360px; margin-bottom: 2px; }
  /* DocuSign anchor: 1px 白色文字，让 anchor 不可见但存在于文档中 */
  .ds-anchor { font-size: 1px; color: white; line-height: 0; display: inline-block; }
</style>
</head>
<body>

<h1>MERCHANT AGREEMENT</h1>
<p class="center">
  <strong>Crunchy Plum, LLC</strong><br>
  Effective Date: ${today}
</p>

<div class="notice">
  IMPORTANT NOTICE — THIS AFFECTS YOUR LEGAL RIGHTS<br><br>
  THIS MERCHANT AGREEMENT CONTAINS A MANDATORY ARBITRATION PROVISION AND A CLASS ACTION WAIVER IN SECTION 16.
  BY SIGNING BELOW, YOU WAIVE YOUR RIGHT TO PARTICIPATE IN A CLASS ACTION LAWSUIT OR CLASS-WIDE ARBITRATION
  AGAINST CRUNCHY PLUM. PLEASE READ SECTION 16 CAREFULLY.
</div>

<h2>COMMISSION SCHEDULE</h2>
<p>The following commission rates apply to <strong>${contract.recipient_name}</strong>:</p>
<table class="schedule">
  <tr>
    <th>Period</th>
    <th>Commission Rate</th>
    <th>Duration</th>
  </tr>
  <tr>
    <td>Promotional Period</td>
    <td><strong>${promoRate}%</strong></td>
    <td>First ${contract.promo_months} month${contract.promo_months !== 1 ? "s" : ""} from account activation</td>
  </tr>
  <tr>
    <td>Standard Rate</td>
    <td><strong>${standardRate}%</strong></td>
    <td>After promotional period (ongoing)</td>
  </tr>
</table>
${
    contract.booster_credit_amount > 0
      ? `<p>A booster credit of <strong>$${
        contract.booster_credit_amount.toFixed(2)
      }</strong> will be applied to Merchant's promotional account upon agreement execution.</p>`
      : ""
  }

<h2>1. Acceptance of Agreement</h2>
<p>By signing this Agreement, the entity or individual identified below ("Merchant" or "you") agrees to be bound by this Merchant Agreement ("Agreement"), the Crunchy Plum Privacy Policy, the Merchant Payment and Settlement Terms, and the Merchant Terms of Use, each of which is incorporated herein by reference.</p>
<p>If you are entering into this Agreement on behalf of a business entity, you represent and warrant that you have the legal authority to bind that entity to this Agreement.</p>
<p>This Agreement is entered into between Merchant and Crunchy Plum, LLC, a Texas limited liability company ("Crunchy Plum," "we," "us," or "our"), and is governed by the laws of the State of Texas.</p>

<h2>2. Definitions</h2>
<p><strong>Deal</strong> means a discounted offer or promotional package created by Merchant and listed on the Platform for purchase by users.</p>
<p><strong>Commission Rate</strong> means the percentage of each Deal's Gross Transaction Value retained by Crunchy Plum, as set forth in the Commission Schedule above.</p>
<p><strong>Gross Transaction Value (GTV)</strong> means the total amount paid by a user for a Deal, excluding taxes collected by Crunchy Plum on behalf of Merchant.</p>
<p><strong>Net Settlement Amount</strong> means the GTV of completed Transactions minus (a) the Commission Rate, (b) any refunds, chargebacks, or adjustments, and (c) any other amounts owed to Crunchy Plum under this Agreement.</p>
<p><strong>Paid Value</strong> has the meaning given in the Refund Policy.</p>
<p><strong>Redemption</strong> means a user presenting a valid Deal code to Merchant and Merchant accepting such code in exchange for the goods or services described in the Deal.</p>
<p><strong>Transaction</strong> means a completed purchase by a user of a Deal listed by Merchant on the Platform.</p>

<h2>3. Merchant Eligibility and KYC</h2>
<h3>3.1 Eligibility Requirements</h3>
<p>To register and maintain an active merchant account, Merchant must: (a) be a legally registered business or self-employed individual operating in compliance with applicable laws; (b) hold all required licenses and permits; (c) have a valid and active Stripe Connect account; and (d) not be listed on any government sanctions list.</p>
<h3>3.2 Identity and Business Verification</h3>
<p>Merchant agrees to provide accurate, current, and complete information during registration, including legal business name, business address, and tax identification number (EIN or SSN). Merchant authorizes Crunchy Plum and Stripe to verify the information provided.</p>
<h3>3.3 Ongoing Compliance</h3>
<p>Merchant shall promptly notify Crunchy Plum at support@crunchyplum.com of any material change to its registration information, including changes to business ownership, address, or Stripe account status.</p>
<h3>3.4 Right to Reject</h3>
<p>Crunchy Plum reserves the right to reject any merchant application or suspend/terminate any merchant account that does not meet eligibility requirements.</p>
<h3>3.5 Personal Guarantee (Sole Proprietors and Single-Member LLCs)</h3>
<p>If Merchant is a sole proprietor or single-member LLC, the individual completing merchant registration ("Guarantor") agrees to be personally liable, jointly and severally with Merchant, for all financial obligations under this Agreement, including outstanding settlement deficits, refund obligations, and chargeback liabilities. This personal guarantee shall survive the termination or dissolution of Merchant's business entity.</p>
<p>Guarantor waives all defenses available to a guarantor under applicable law, including notice of acceptance, presentment, demand, protest, and notice of default. Guarantor further waives any right to require Crunchy Plum to first proceed against Merchant before enforcing this guarantee against Guarantor.</p>

<hr style="border:none;border-top:1px solid #ddd;margin:16px 0;">

<h2>4. Platform Role</h2>
<h3>4.1 Technology and Marketplace Services</h3>
<p>Crunchy Plum provides a technology platform enabling Merchants to list Deals and reach consumers. Crunchy Plum is not a party to any transaction between Merchant and a user, does not take title to any goods or services, and is not a buyer, seller, agent, or fiduciary of Merchant or any user.</p>
<h3>4.2 No Endorsement</h3>
<p>The listing of a Deal on the Platform does not constitute an endorsement, guarantee, or warranty by Crunchy Plum of the quality, accuracy, safety, or legality of the goods or services offered by Merchant.</p>
<h3>4.3 Independent Contractor</h3>
<p>Merchant is an independent contractor of Crunchy Plum. Nothing in this Agreement creates an employment, agency, partnership, joint venture, or franchise relationship between the parties.</p>

<h2>5. Deal Submission and Approval</h2>
<h3>5.1 Submission Requirements</h3>
<p>Each Deal submission must include: (a) an accurate description of the goods or services; (b) the original retail price and discounted Deal price; (c) the Deal validity period (not to exceed 90 days from purchase); (d) the redemption location(s); and (e) any material terms, conditions, restrictions, or exclusions.</p>
<h3>5.2 Platform Review and Approval</h3>
<p>All Deal submissions are subject to review and approval by Crunchy Plum. Crunchy Plum reserves the right to approve, request modifications to, reject, or remove any Deal submission in its reasonable discretion.</p>
<h3>5.3 No Liability for Rejection or Removal</h3>
<p>Crunchy Plum shall not be liable to Merchant for any damages resulting from the rejection, modification, or removal of any Deal submission.</p>

<h2>6. Commission and Settlement</h2>
<h3>6.1 Commission</h3>
<p>For each completed Transaction, Crunchy Plum will retain a Commission at the rate set forth in the Commission Schedule above. During the promotional period of <strong>${contract.promo_months} month${
    contract.promo_months !== 1 ? "s" : ""
  }</strong> from account activation, the commission rate is <strong>${promoRate}%</strong> of the GTV. After the promotional period, the standard commission rate of <strong>${standardRate}%</strong> applies.</p>
<h3>6.2 Settlement Cycle</h3>
<p>Crunchy Plum will disburse the Net Settlement Amount to Merchant's connected Stripe account on a T+7 basis, subject to: (a) Merchant's Stripe Connect account being active and in good standing; (b) no pending investigations or disputes; and (c) the Net Settlement Amount being positive after all deductions.</p>
<h3>6.3 Deductions from Settlement</h3>
<p>Crunchy Plum may deduct from any settlement: (a) the applicable Commission; (b) refunds; (c) chargebacks; (d) Rolling Reserve amounts; and (e) any other amounts owed by Merchant. Refunds and chargebacks have priority over settlement disbursements. Crunchy Plum may set off amounts owed by Merchant against settlement payments without prior notice. Negative balances will be carried forward and may be invoiced after 30 days.</p>
<h3>6.4 Commission Rate Changes</h3>
<p>Crunchy Plum reserves the right to modify the Commission Rate upon 30 days' prior written notice. If Merchant disagrees, Merchant may terminate this Agreement within the notice period.</p>
<h3>6.5 No Interest</h3>
<p>Crunchy Plum shall not be obligated to pay interest on funds held pending settlement, except as required by applicable law.</p>
<h3>6.6 Rolling Reserve</h3>
<p>Crunchy Plum may withhold a rolling reserve of up to 10% of GTV for up to 90 days following each Transaction to cover potential refunds and chargebacks. The Rolling Reserve does not bear interest. Upon termination, Crunchy Plum may continue holding the Rolling Reserve for up to 180 days following the last Transaction date. Any remaining balance, net of outstanding obligations, will be released to Merchant's Stripe account thereafter.</p>

<hr style="border:none;border-top:1px solid #ddd;margin:16px 0;">

<h2>7. Deal Content Standards and Prohibited Conduct</h2>
<h3>7.1 Content Standards</h3>
<p>All Deal content must not be false, misleading, or deceptive; must not involve goods or services Merchant cannot legally provide; must not include illegal goods or services; must not violate Stripe's Prohibited and Restricted Businesses policy; must not infringe third-party intellectual property rights; and must not contain defamatory or obscene content.</p>
<h3>7.2 Prohibited Merchant Conduct</h3>
<p>Merchant agrees not to:</p>
<p>(a) manipulate or solicit user reviews or ratings in a deceptive manner or in violation of FTC guidelines;</p>
<p>(b) <strong>engage in or facilitate any transaction outside of the Platform that was initiated through Platform activity, for the purpose of circumventing Crunchy Plum's Commission — including but not limited to accepting payment directly from a user at the point of service, or offering a discount equivalent to or based on a Deal listed on the Platform, when that user discovered or initiated contact through the Platform;</strong></p>
<p>(c) create multiple merchant accounts for the same business without prior written approval;</p>
<p>(d) use the Platform to sell to sanctioned persons or entities; or</p>
<p>(e) disrupt, damage, or interfere with the Platform or Crunchy Plum's systems.</p>
<h3>7.3 Liquidated Damages for Platform Circumvention</h3>
<p>Merchant acknowledges that it would be difficult to precisely calculate the actual damages suffered by Crunchy Plum if Merchant engages in the conduct described in Section 7.2(b), including lost commission revenue, harm to user trust, and damage to the Platform's marketplace integrity. Accordingly, for each verified incident in which Merchant accepts payment directly from a user outside of the Platform — or offers a discount equivalent to a Platform-listed Deal to a user who was acquired through Platform activity — Merchant agrees to pay Crunchy Plum liquidated damages in the amount of <strong>Five Hundred U.S. Dollars ($500.00)</strong> per incident. The parties agree that this amount represents a reasonable estimate of the damages and is not intended as a penalty.</p>
<p>Crunchy Plum may deduct any liquidated damages owed under this Section directly from Merchant's settlement balance without prior notice, or invoice Merchant directly if settlement funds are insufficient. This obligation is in addition to, and not in lieu of, any other remedies available to Crunchy Plum, including suspension or immediate termination under Section 13.2.</p>
<h3>7.4 Merchant Compliance Responsibility</h3>
<p>Merchant is solely responsible for ensuring that all Deals, goods, services, and business practices comply with all applicable laws and regulations, including consumer protection laws, health and safety regulations, licensing requirements, and Texas sales tax laws.</p>

<h2>8. Refunds</h2>
<h3>8.1 Merchant Authorization for Refunds</h3>
<p>Merchant hereby authorizes Crunchy Plum to process refunds to users in accordance with the Crunchy Plum Refund Policy, without requiring Merchant's prior approval for each individual refund.</p>
<h3>8.2 Refund Deductions</h3>
<p>The full amount of each refund processed by Crunchy Plum will be deducted from Merchant's Net Settlement Amount in the settlement period in which the refund is processed.</p>
<h3>8.3 Termination-Related Refunds</h3>
<p>If this Agreement is terminated and unredeemed Deals remain outstanding, Crunchy Plum will process refunds of the Paid Value. If termination is due to Merchant's breach, the Paid Value and all processing fees shall be deducted from or invoiced to Merchant. If termination is initiated by Crunchy Plum without Merchant fault, processing fees shall be borne by Crunchy Plum.</p>
<h3>8.4 No Obligation to Fund Refunds</h3>
<p>Crunchy Plum does not fund refunds from its own assets. Merchant remains ultimately liable for all refund obligations arising from its Deals.</p>

<h2>9. Chargebacks</h2>
<h3>9.1 Merchant Liability</h3>
<p>Merchant is solely responsible for all chargebacks initiated by users. The full amount of each chargeback, including any Stripe or card network fees, will be deducted from Merchant's Net Settlement Amount.</p>
<h3>9.2 Chargeback Ratio</h3>
<p>Excessive chargebacks may result in disbursement suspension, required corrective measures, or termination of this Agreement.</p>
<h3>9.3 Dispute Assistance</h3>
<p>Merchant agrees to cooperate fully with Crunchy Plum in responding to chargebacks, including providing supporting documentation within required timeframes.</p>

<h2>10. Redemption Obligations</h2>
<h3>10.1 Mandatory Acceptance</h3>
<p>Merchant must honor all valid, unexpired Deals presented by users for redemption in accordance with the Deal terms. Refusal to honor a valid Deal without cause constitutes a material breach of this Agreement.</p>
<h3>10.2 Redemption Process</h3>
<p>Merchant is responsible for maintaining the capability to verify and accept Deal redemption codes at all times during the Deal's validity period through the Platform's designated redemption mechanism.</p>
<h3>10.3 Merchant Changes Affecting Redemption</h3>
<p>Merchant must notify Crunchy Plum at support@crunchyplum.com at least 7 days in advance of any changes affecting its ability to honor outstanding Deals, including location changes or temporary closures.</p>

<hr style="border:none;border-top:1px solid #ddd;margin:16px 0;">

<h2>11. Tax Responsibilities</h2>
<h3>11.1 Merchant's Tax Obligations</h3>
<p>Merchant is solely responsible for determining, collecting, reporting, and remitting all taxes arising from the sale of goods or services through Deals, including Texas sales tax and use tax. Crunchy Plum does not collect or remit sales tax on behalf of Merchant unless separately agreed in writing.</p>
<h3>11.2 1099-K Reporting</h3>
<p>Crunchy Plum or Stripe will issue IRS Form 1099-K to Merchant for reportable payment transactions as required by applicable law. Merchant is responsible for accurately reporting all income to applicable tax authorities.</p>
<h3>11.3 Tax Indemnification</h3>
<p>Merchant agrees to indemnify, defend, and hold harmless Crunchy Plum from any taxes, penalties, interest, or governmental charges arising from Merchant's failure to comply with its tax obligations.</p>

<h2>12. Deal Removal and Account Suspension</h2>
<h3>12.1 Platform's Right to Remove</h3>
<p>Crunchy Plum reserves the right to remove, suspend, or modify any Deal at any time, including for Content Standards violations, user complaints, legal changes, or other reasons to protect the integrity of the Platform.</p>
<h3>12.2 Account Suspension</h3>
<p>Crunchy Plum may suspend Merchant's account if it reasonably believes Merchant has violated this Agreement, applicable law, or Stripe's policies, pending investigation and resolution.</p>
<h3>12.3 No Liability for Removal</h3>
<p>Crunchy Plum shall not be liable for any loss arising from the removal of a Deal or suspension of a merchant account.</p>

<h2>13. Termination</h2>
<h3>13.1 Termination by Merchant</h3>
<p>Merchant may terminate this Agreement upon 30 days' prior written notice to support@crunchyplum.com. During the notice period, Merchant remains obligated to honor all outstanding Deals.</p>
<h3>13.2 Termination by Crunchy Plum</h3>
<p>Crunchy Plum may terminate this Agreement for convenience upon 30 days' notice, or immediately upon: (i) Merchant's material breach; (ii) violation of applicable law; (iii) Stripe account termination or suspension; (iv) insolvency or cessation of operations; or (v) legal, reputational, or financial risk to the Platform.</p>
<h3>13.3 Effect of Termination</h3>
<p>Upon termination: Merchant's access will be disabled; Crunchy Plum will process refunds for unredeemed Deals; any negative settlement balance becomes immediately due; and Sections 2, 9, 11, 14, 15, 16, and 17 survive termination.</p>

<hr style="border:none;border-top:1px solid #ddd;margin:16px 0;">

<h2>14. Merchant Indemnification</h2>
<p>To the fullest extent permitted by law, Merchant agrees to indemnify, defend, and hold harmless Crunchy Plum and its officers, directors, members, employees, agents, and successors from all claims, liabilities, damages, losses, costs, and expenses (including reasonable attorneys' fees) arising out of or related to: (a) Merchant's breach of this Agreement or applicable law; (b) goods or services offered through the Platform; (c) false or inaccurate Deal content; (d) failure to honor valid Deals; (e) tax obligations; (f) chargebacks; or (g) third-party claims from Merchant's use of the Platform.</p>

<h2>15. Limitation of Liability</h2>
<h3>15.1 Disclaimer of Warranties</h3>
<p>THE PLATFORM IS PROVIDED "AS IS" AND "AS AVAILABLE." CRUNCHY PLUM MAKES NO WARRANTIES, EXPRESS OR IMPLIED, REGARDING THE PLATFORM, INCLUDING WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE, OR UNINTERRUPTED OPERATION.</p>
<h3>15.2 Limitation of Damages</h3>
<p>TO THE FULLEST EXTENT PERMITTED BY APPLICABLE LAW, CRUNCHY PLUM SHALL NOT BE LIABLE TO MERCHANT FOR ANY INDIRECT, INCIDENTAL, SPECIAL, CONSEQUENTIAL, PUNITIVE, OR EXEMPLARY DAMAGES, INCLUDING LOSS OF PROFITS, LOSS OF DATA, LOSS OF GOODWILL, OR BUSINESS INTERRUPTION, ARISING OUT OF OR RELATED TO THIS AGREEMENT OR THE PLATFORM.</p>
<h3>15.3 Liability Cap</h3>
<p>TO THE FULLEST EXTENT PERMITTED BY APPLICABLE LAW, CRUNCHY PLUM'S TOTAL CUMULATIVE LIABILITY TO MERCHANT SHALL NOT EXCEED THE TOTAL COMMISSION AMOUNTS PAID BY MERCHANT TO CRUNCHY PLUM DURING THE TWELVE (12) MONTHS IMMEDIATELY PRECEDING THE EVENT GIVING RISE TO THE CLAIM.</p>

<h2>16. Dispute Resolution and Arbitration</h2>
<h3>16.1 Informal Resolution</h3>
<p>Before initiating formal dispute resolution, the parties agree to first attempt resolution informally by written notice with 30 days for good-faith negotiation. Notices to Crunchy Plum should be sent to support@crunchyplum.com.</p>
<h3>16.2 Binding Arbitration</h3>
<p>IF THE PARTIES CANNOT RESOLVE A DISPUTE INFORMALLY, ALL DISPUTES, CLAIMS, OR CONTROVERSIES ARISING OUT OF OR RELATING TO THIS AGREEMENT SHALL BE RESOLVED EXCLUSIVELY THROUGH FINAL AND BINDING ARBITRATION ADMINISTERED BY THE AMERICAN ARBITRATION ASSOCIATION ("AAA") UNDER ITS COMMERCIAL ARBITRATION RULES. THE ARBITRATION SHALL TAKE PLACE IN COLLIN COUNTY, TEXAS, AND THE ARBITRATOR SHALL APPLY TEXAS SUBSTANTIVE LAW CONSISTENT WITH THE FEDERAL ARBITRATION ACT (9 U.S.C. § 1 ET SEQ.).</p>
<h3>16.3 Class Action Waiver</h3>
<p>MERCHANT AND CRUNCHY PLUM EACH AGREE THAT ANY DISPUTE RESOLUTION PROCEEDING SHALL BE CONDUCTED ONLY ON AN INDIVIDUAL BASIS AND NOT AS A CLASS, CONSOLIDATED, OR REPRESENTATIVE ACTION. MERCHANT EXPRESSLY WAIVES ANY RIGHT TO PARTICIPATE IN A CLASS ACTION LAWSUIT OR CLASS-WIDE ARBITRATION AGAINST CRUNCHY PLUM.</p>
<h3>16.4 Injunctive Relief</h3>
<p>Either party may seek emergency injunctive or equitable relief from a court of competent jurisdiction to prevent irreparable harm pending arbitration.</p>
<h3>16.5 Time Limitation</h3>
<p>ANY CLAIM ARISING UNDER THIS AGREEMENT MUST BE BROUGHT WITHIN ONE (1) YEAR AFTER THE CAUSE OF ACTION ARISES OR IT SHALL BE PERMANENTLY BARRED.</p>

<h2>17. General Provisions</h2>
<h3>17.1 Governing Law</h3>
<p>This Agreement is governed by the laws of the State of Texas, without regard to conflict of law principles. To the extent any dispute is not subject to arbitration, the parties consent to exclusive jurisdiction in the state or federal courts of Collin County, Texas.</p>
<h3>17.2 Entire Agreement</h3>
<p>This Agreement, together with the Merchant Payment and Settlement Terms, Merchant Terms of Use, and Privacy Policy, constitutes the entire agreement between the parties with respect to its subject matter.</p>
<h3>17.3 Amendment</h3>
<p>Crunchy Plum reserves the right to modify this Agreement upon 30 days' prior written notice. Merchant's continued use of the Platform after modification constitutes acceptance of the revised Agreement.</p>
<h3>17.4 Assignment</h3>
<p>Merchant may not assign this Agreement without Crunchy Plum's prior written consent. Crunchy Plum may freely assign this Agreement, including in connection with a merger, acquisition, or sale of assets.</p>
<h3>17.5 Severability</h3>
<p>If any provision is found invalid or unenforceable, it shall be modified to the minimum extent necessary or severed, and remaining provisions shall continue in full force.</p>
<h3>17.6 Waiver</h3>
<p>Failure to enforce any provision shall not constitute a waiver of that provision.</p>
<h3>17.7 Force Majeure</h3>
<p>Neither party shall be liable for failure or delay due to causes beyond its reasonable control, including acts of God, natural disasters, war, government actions, or pandemic.</p>
<h3>17.8 Electronic Acceptance</h3>
<p>This Agreement may be accepted electronically. Electronic acceptance has the same legal effect as a handwritten signature under the E-Sign Act and Texas Business &amp; Commerce Code § 322.</p>
<h3>17.9 Notices</h3>
<p>All notices shall be in writing and delivered to registered email addresses. Notices to Crunchy Plum shall be sent to support@crunchyplum.com.</p>

<h2>18. Contact Information</h2>
<p>
  <strong>Crunchy Plum, LLC</strong><br>
  Email: support@crunchyplum.com<br>
  Website: https://crunchyplum.com
</p>

<p><em>&copy; ${year} Crunchy Plum, LLC. All rights reserved.</em></p>

<!-- ── 签名页（page-break 前加强制分页）── -->
<div class="sig-block" style="page-break-before:always;">
  <h2>SIGNATURE PAGE</h2>

  <table style="width:100%; border-collapse:collapse; margin-top:24px;">
    <tr>
      <!-- 左栏：商家签字 -->
      <td style="width:48%; vertical-align:top; padding-right:24px; border-right:1px solid #ccc;">
        <p class="sig-label">MERCHANT</p>

        <!-- Business / DBA Name：商家自填文字 tab（anchor: \\bn1\\）-->
        <p style="margin-top:20px; margin-bottom:2px;">Business / DBA Name (as registered):</p>
        <span class="ds-anchor">\\bn1\\</span>
        <div class="sig-line">&nbsp;</div>

        <!-- 授权签字人姓名（预填）-->
        <p style="margin-top:16px; margin-bottom:2px;">Authorized Signatory: <strong>${contract.recipient_name}</strong></p>

        <!-- 签名 tab（anchor: \\s1\\）-->
        <p style="margin-top:16px; margin-bottom:2px;">Signature:</p>
        <span class="ds-anchor">\\s1\\</span>
        <div class="sig-line">&nbsp;</div>

        <!-- 日期 tab（anchor: \\d1\\，DocuSign 自动填入签署日期）-->
        <p style="margin-top:12px; margin-bottom:2px;">Date:</p>
        <span class="ds-anchor">\\d1\\</span>
        <div class="sig-line" style="width:200px">&nbsp;</div>
      </td>

      <!-- 右栏：Crunchy Plum 签字（countersign, signer 2）-->
      <td style="width:48%; vertical-align:top; padding-left:24px;">
        <p class="sig-label">CRUNCHY PLUM, LLC</p>

        <p style="margin-top:20px; margin-bottom:2px;">Authorized Representative: <strong>${contract.cp_signer_name ?? "Howard Shan"}</strong></p>
        <p style="margin-bottom:2px;">Title: Founder &amp; CEO</p>

        <!-- 公司签名 tab（anchor: \\s2\\，signer 2）-->
        <p style="margin-top:16px; margin-bottom:2px;">Signature:</p>
        <span class="ds-anchor">\\s2\\</span>
        <div class="sig-line">&nbsp;</div>

        <!-- 公司日期 tab（anchor: \\d2\\）-->
        <p style="margin-top:12px; margin-bottom:2px;">Date:</p>
        <span class="ds-anchor">\\d2\\</span>
        <div class="sig-line" style="width:200px">&nbsp;</div>
      </td>
    </tr>
  </table>
</div>

</body>
</html>`;
}

// ── 主 Handler ──────────────────────────────────────────────────────────────

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const { contract_id } = await req.json();
    if (!contract_id) return errorResponse("contract_id is required");

    // 1. 从 DB 拉取合同记录
    const { data: contract, error: contractErr } = await supabase
      .from("merchant_contracts")
      .select(
        "id, name, recipient_name, recipient_email, promo_months, promo_commission_rate, standard_commission_rate, booster_credit_amount, status, docusign_envelope_id",
      )
      .eq("id", contract_id)
      .single();

    if (contractErr || !contract) {
      return errorResponse(`Contract not found: ${contractErr?.message}`, 404);
    }
    if (contract.status !== "draft") {
      return errorResponse(
        `Contract is already in status '${contract.status}', cannot re-send`,
        409,
      );
    }

    // 2. 生成合同 HTML
    const cpSignerName = Deno.env.get("CP_SIGNER_NAME") ?? "Howard Shan";
    const contractHtml = generateContractHtml({
      recipient_name: contract.recipient_name,
      promo_months: contract.promo_months,
      promo_commission_rate: contract.promo_commission_rate,
      standard_commission_rate: contract.standard_commission_rate,
      booster_credit_amount: contract.booster_credit_amount,
      cp_signer_name: cpSignerName,
    });

    // 3. DocuSign JWT 认证（同时从 userinfo 获取正确的 accountId 和 baseUri）
    const { accessToken, accountId, apiBaseUrl } = await getDocuSignAccessToken();
    const apiBase = `${apiBaseUrl}/restapi/v2.1/accounts/${accountId}`;

    // 4. 构造 DocuSign 信封（含文档 + 签名者 + tab 定义）
    const htmlB64 = btoa(unescape(encodeURIComponent(contractHtml)));

    const envelopeBody = {
      emailSubject:
        `Crunchy Plum Merchant Agreement — Action Required: ${contract.name}`,
      emailBlurb:
        `Dear ${contract.recipient_name},\n\nPlease review and sign the attached Merchant Agreement with Crunchy Plum, LLC.\n\nBefore signing, you will be asked to fill in your Business / DBA Name.\n\nThank you!`,
      documents: [
        {
          documentBase64: htmlB64,
          name: "Merchant Agreement",
          fileExtension: "html",
          documentId: "1",
        },
      ],
      recipients: {
        signers: [
          // ── Signer 1: 商家（先签）──
          {
            email: contract.recipient_email,
            name: contract.recipient_name,
            recipientId: "1",
            routingOrder: "1",
            tabs: {
              // 签名 tab
              signHereTabs: [
                {
                  anchorString: "\\s1\\",
                  anchorXOffset: "0",
                  anchorYOffset: "-5",
                  anchorUnits: "pixels",
                  tabLabel: "Signature",
                },
              ],
              // 日期 tab（DocuSign 自动填入签署日期）
              dateSignedTabs: [
                {
                  anchorString: "\\d1\\",
                  anchorXOffset: "0",
                  anchorYOffset: "-5",
                  anchorUnits: "pixels",
                  tabLabel: "DateSigned",
                },
              ],
              // 商家自填 Business / DBA Name 文字 tab
              textTabs: [
                {
                  anchorString: "\\bn1\\",
                  anchorXOffset: "0",
                  anchorYOffset: "-5",
                  anchorUnits: "pixels",
                  tabLabel: "BusinessName",
                  required: "true",
                  width: "300",
                  height: "28",
                  font: "Arial",
                  fontSize: "size11",
                },
              ],
              // 每页底部 initial tabs：页码坐标定位，必须指定 documentId
              // x=490（靠右边距）y=730（letter 页 792pt 底部约 62pt 处）
              // 超出实际页数的 tab DocuSign 自动忽略；最后一页（签名页）不加
              initialHereTabs: [1, 2, 3, 4, 5, 6, 7, 8].map((p) => ({
                documentId: "1",
                pageNumber: String(p),
                xPosition: "490",
                yPosition: "730",
                tabLabel: `Initial${p}`,
              })),
            },
          },
          // ── Signer 2: Crunchy Plum（商家签完后反签，从 env 读取）──
          {
            email: Deno.env.get("CP_SIGNER_EMAIL") ?? "shayiqing16@gmail.com",
            name: Deno.env.get("CP_SIGNER_NAME") ?? "Howard Shan",
            recipientId: "2",
            routingOrder: "2", // 商家签完后才收到邮件
            tabs: {
              signHereTabs: [
                {
                  anchorString: "\\s2\\",
                  anchorXOffset: "0",
                  anchorYOffset: "-5",
                  anchorUnits: "pixels",
                  tabLabel: "CPSignature",
                },
              ],
              dateSignedTabs: [
                {
                  anchorString: "\\d2\\",
                  anchorXOffset: "0",
                  anchorYOffset: "-5",
                  anchorUnits: "pixels",
                  tabLabel: "CPDateSigned",
                },
              ],
            },
          },
        ],
      },
      status: "sent", // sent = 立即发送；draft = 草稿不发
    };

    const envelopeResp = await fetch(`${apiBase}/envelopes`, {
      method: "POST",
      headers: {
        Authorization: `Bearer ${accessToken}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify(envelopeBody),
    });

    if (!envelopeResp.ok) {
      const errBody = await envelopeResp.text();
      console.error("[send-merchant-contract] DocuSign envelope error:", errBody);
      return errorResponse(`DocuSign envelope creation failed: ${errBody}`, 502);
    }

    const envelopeData = await envelopeResp.json();
    const envelopeId = envelopeData.envelopeId as string;

    // 5. 更新 DB：记录 envelope ID、状态改为 sent、保存合同 HTML
    const { error: updateErr } = await supabase
      .from("merchant_contracts")
      .update({
        docusign_envelope_id: envelopeId,
        status: "sent",
        sent_at: new Date().toISOString(),
        content_html: contractHtml,
      })
      .eq("id", contract_id);

    if (updateErr) {
      console.error("[send-merchant-contract] DB update error:", updateErr);
      // 信封已发出，不回滚；仅记录错误
    }

    return new Response(
      JSON.stringify({
        success: true,
        envelope_id: envelopeId,
        envelope_status: envelopeData.status,
      }),
      {
        status: 200,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      },
    );
  } catch (e) {
    console.error("[send-merchant-contract] Unexpected error:", e);
    return errorResponse(
      e instanceof Error ? e.message : "Internal server error",
      500,
    );
  }
});
