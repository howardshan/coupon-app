# Merchant Payment and Settlement Terms

**Crunchy Plum, LLC**
**Effective Date:** [DATE]
**Last Updated:** [DATE]

---

## Overview

These Merchant Payment and Settlement Terms ("Payment Terms") govern how Crunchy Plum processes payments, calculates settlements, and disburses funds to Merchants. These Payment Terms are incorporated into and subject to the Merchant Agreement. Capitalized terms not defined here have the meanings given in the Merchant Agreement.

---

## 1. Stripe Connect Requirement

### 1.1 Mandatory Enrollment
All Merchants must maintain an active and compliant Stripe Connect account to receive settlement payments through the Platform. Merchant is responsible for completing Stripe's identity verification and onboarding requirements. Crunchy Plum will not disburse funds to any Merchant that has not completed Stripe Connect onboarding or whose Stripe Connect account is suspended, restricted, or terminated.

### 1.2 Stripe Terms
By connecting a Stripe account, Merchant agrees to be bound by Stripe's Connected Account Agreement and Stripe's Terms of Service, available at stripe.com/legal. Crunchy Plum is not a party to the agreement between Merchant and Stripe and is not responsible for Stripe's performance, policies, or decisions regarding Merchant's account.

### 1.3 Stripe Account Changes
Merchant must promptly notify Crunchy Plum at [MERCHANT SUPPORT EMAIL] of any change to its Stripe Connect account status, including suspension, restriction, closure, or change of connected bank account. Failure to maintain an active Stripe Connect account does not relieve Merchant of any financial obligations under the Merchant Agreement or these Payment Terms.

### 1.4 Platform Not Liable for Stripe Delays
Crunchy Plum shall not be liable for any delays, failures, errors, or losses in the disbursement of settlement funds caused by Stripe, any card network, any issuing or receiving bank, or any other third-party financial institution. Settlement timing is subject to Stripe's processing schedules and applicable banking hours.

---

## 2. Settlement Calculation

### 2.1 Net Settlement Amount
For each settlement period, Crunchy Plum will calculate the Net Settlement Amount as follows:

```
Gross Transaction Value (GTV)
- Commission ([COMMISSION RATE]% of GTV)
- Refunds processed during the settlement period
- Chargebacks received during the settlement period
- Rolling Reserve withheld (if applicable)
- Any other amounts owed by Merchant to Crunchy Plum
= Net Settlement Amount
```

### 2.2 Priority of Deductions
Deductions are applied in the following order of priority:

(a) Refunds and chargebacks owed to users — first priority;

(b) Crunchy Plum's Commission — second priority;

(c) Rolling Reserve withholding — third priority;

(d) Any other outstanding amounts owed by Merchant — fourth priority.

The Net Settlement Amount payable to Merchant is the remainder after all deductions have been applied. If the Net Settlement Amount is zero or negative, no disbursement will be made for that period and any negative balance will be carried forward in accordance with Section 4.

### 2.3 Settlement Currency
All settlements are denominated and disbursed in United States Dollars (USD). Crunchy Plum does not currently support multi-currency settlement. Merchant is responsible for any currency conversion costs associated with receiving funds in a currency other than USD.

---

## 3. Automatic Settlement and Withdrawal

### 3.1 Automatic T+7 Disbursement
Crunchy Plum will automatically disburse the Net Settlement Amount to Merchant's connected Stripe account on a T+7 basis, meaning funds from Transactions completed on a given calendar day will be automatically disbursed seven (7) calendar days after the transaction date, subject to the conditions in Section 3.3. No action is required by Merchant to initiate the standard T+7 settlement.

### 3.2 On-Demand Withdrawal
In addition to the automatic T+7 disbursement, Merchant may request an on-demand withdrawal of available settlement balance at any time through the merchant dashboard, subject to:

(a) the requested amount being available as a positive settlement balance after all pending deductions;

(b) Merchant's Stripe Connect account being active and in good standing;

(c) no active investigation, hold, or dispute on Merchant's account; and

(d) the withdrawal amount meeting or exceeding the minimum withdrawal threshold of **[MINIMUM WITHDRAWAL AMOUNT]**.

Crunchy Plum may, in its reasonable discretion, delay or reject any on-demand withdrawal request to protect against potential refunds, chargebacks, fraud risk, or other financial exposure associated with Merchant's account. Crunchy Plum will notify Merchant of any such delay or rejection within three (3) business days of the request.

### 3.3 Conditions for Disbursement
All disbursements — whether automatic or on-demand — are subject to:

(a) Merchant's account being in good standing with no outstanding violations of the Merchant Agreement;

(b) Merchant's Stripe Connect account being active and verified;

(c) no active suspension, investigation, or hold placed on Merchant's account by Crunchy Plum or Stripe; and

(d) the Net Settlement Amount being positive after all deductions under Section 2.

### 3.4 Settlement Delay Notification
If a scheduled automatic disbursement is delayed beyond three (3) business days from the expected settlement date for reasons within Crunchy Plum's control, Crunchy Plum will notify Merchant at its registered email address. Delays caused by Stripe, banking institutions, or events of force majeure are not subject to this notification obligation.

---

## 4. Negative Balances

### 4.1 Carry-Forward
If deductions in any settlement period exceed the Gross Transaction Value for that period, resulting in a negative Net Settlement Amount, the deficit will be carried forward and deducted from future settlement payments until the negative balance is fully recovered.

### 4.2 Demand for Payment
If a negative balance is not fully recovered through settlement deductions within thirty (30) days of arising, Crunchy Plum may, at its discretion:

(a) issue a written demand to Merchant for immediate payment of the outstanding negative balance;

(b) suspend Merchant's account and cease processing new Transactions until the negative balance is resolved; and

(c) pursue any other remedies available under the Merchant Agreement or applicable law, including referral to collections.

### 4.3 Set-Off
Crunchy Plum's set-off rights as set forth in Section 6.3 of the Merchant Agreement apply in full to any negative balance recovery under these Payment Terms.

---

## 5. Suspension of Payments

### 5.1 Grounds for Suspension
Crunchy Plum may suspend, delay, or withhold settlement payments, in whole or in part, without prior notice, in the following circumstances:

(a) Crunchy Plum has a reasonable basis to suspect fraudulent activity, money laundering, or platform abuse involving Merchant's account;

(b) an investigation is pending regarding Merchant's compliance with the Merchant Agreement, applicable law, or Stripe's policies;

(c) Merchant's chargeback ratio exceeds acceptable thresholds;

(d) a legal order, government directive, or Stripe instruction requires withholding of funds;

(e) unusual or sudden spikes in Transaction volume that are inconsistent with Merchant's historical activity; or

(f) Merchant's Stripe Connect account has been suspended or restricted by Stripe.

### 5.2 Duration of Suspension
Crunchy Plum will use commercially reasonable efforts to resolve the circumstances giving rise to a payment suspension as promptly as practicable. Crunchy Plum will notify Merchant of the suspension and the general reason for it within three (3) business days of initiating the suspension, unless prohibited by law or ongoing investigation requirements.

### 5.3 No Liability for Suspension
Crunchy Plum shall not be liable to Merchant for any losses, damages, or lost profits resulting from a good-faith suspension of payments under this Section.

---

## 6. Rolling Reserve

The Rolling Reserve provisions set forth in Section 6.6 of the Merchant Agreement are incorporated herein by reference and apply in full to these Payment Terms. For clarity:

(a) Rolling Reserve amounts are withheld from each settlement disbursement at the applicable rate;

(b) Rolling Reserve funds are released on a rolling basis, subject to no outstanding disputes, refunds, chargebacks, or unresolved obligations;

(c) upon termination of the Merchant Agreement, Rolling Reserve funds may be held for up to one hundred eighty (180) days following the last Transaction date; and

(d) Rolling Reserve balances do not bear interest.

---

## 7. Account Security and Withdrawal Responsibility

### 7.1 Merchant's Responsibility
Merchant is solely responsible for the security of its merchant dashboard credentials and Stripe Connect account. All withdrawal requests submitted through Merchant's account will be treated as authorized by Merchant, regardless of whether the request was actually made by an authorized representative of Merchant.

### 7.2 Unauthorized Transactions
If Merchant believes an unauthorized withdrawal or account access has occurred, Merchant must immediately notify Crunchy Plum at [MERCHANT SUPPORT EMAIL] and Stripe. Crunchy Plum is not liable for any funds disbursed pursuant to withdrawal instructions that appeared to originate from Merchant's authenticated account session, provided that Crunchy Plum followed its standard security procedures.

### 7.3 Bank Account Accuracy
Merchant is responsible for ensuring that the bank account information linked to its Stripe Connect account is accurate and up to date. Crunchy Plum is not responsible for misdirected payments resulting from incorrect bank account information provided by Merchant or maintained in Merchant's Stripe account. Crunchy Plum will not reissue or recover misdirected payments caused by Merchant error.

---

## 8. Tax Reporting

### 8.1 1099-K Issuance
To the extent required by applicable law, Crunchy Plum or Stripe will issue IRS Form 1099-K to Merchant for reportable payment transactions processed through the Platform during each calendar year. The 1099-K will reflect the gross amount of payments processed, before deduction of Commission, refunds, or other adjustments.

### 8.2 Merchant's Tax Obligations
Merchant is solely responsible for accurately reporting all income received through the Platform to the applicable federal, state, and local tax authorities, and for remitting all taxes owed. Crunchy Plum's issuance of a 1099-K does not constitute tax advice and does not relieve Merchant of any independent tax reporting obligations.

### 8.3 Tax Indemnification
Merchant agrees to indemnify and hold harmless Crunchy Plum from any taxes, penalties, interest, or governmental assessments arising from Merchant's failure to comply with its tax reporting and remittance obligations. This indemnification is in addition to and does not limit the tax indemnification provisions in Section 11 of the Merchant Agreement.

### 8.4 Backup Withholding
If Merchant fails to provide a valid taxpayer identification number (TIN) or if the IRS notifies Crunchy Plum that Merchant is subject to backup withholding, Crunchy Plum or Stripe may be required to withhold a percentage of settlement payments and remit such amounts to the IRS in accordance with applicable law.

---

## 9. Dormant Settlement Balances

### 9.1 Dormancy Definition
A Merchant's settlement balance is considered dormant if the Merchant has had no login activity, no new Transactions, and no withdrawal activity for a continuous period of three (3) years.

### 9.2 Notice Before Reporting
No later than sixty (60) days before the end of the three-year dormancy period, Crunchy Plum will send a written notice to Merchant's registered email address informing Merchant that its settlement balance will be reported to the State of Texas as unclaimed property if not claimed before the deadline.

### 9.3 Reporting to State
If the dormant balance remains unclaimed after the notice period, Crunchy Plum will report and remit the unclaimed funds to the Texas State Comptroller's office in accordance with the Texas Unclaimed Property Law (Texas Property Code Chapters 72–75). Upon such remittance, Crunchy Plum's obligations with respect to the dormant balance are fully discharged. Merchant may subsequently claim the funds directly from the State of Texas at www.claimittexas.gov.

---

## 10. Limitations and General Provisions

### 10.1 No Guarantee of Timing
Crunchy Plum does not guarantee that settlement payments will be received by Merchant on any specific date. Settlement timing is subject to Stripe's processing schedules, banking system availability, and other factors outside of Crunchy Plum's control.

### 10.2 Errors and Adjustments
If Crunchy Plum discovers an error in a settlement calculation — whether resulting in an overpayment or underpayment to Merchant — Crunchy Plum reserves the right to correct the error in the next available settlement period. Merchant agrees to promptly return any overpayment upon notice from Crunchy Plum.

### 10.3 Modification
Crunchy Plum reserves the right to modify these Payment Terms at any time by providing thirty (30) days' prior written notice to Merchant's registered email address. Merchant's continued use of the Platform after the effective date of any modification constitutes acceptance of the revised Payment Terms.

### 10.4 Governing Law and Disputes
These Payment Terms are governed by the laws of the State of Texas. Any disputes arising from these Payment Terms are subject to the dispute resolution and arbitration provisions of the Merchant Agreement.

### 10.5 Incorporation
These Payment Terms are incorporated into the Merchant Agreement. In the event of any conflict between these Payment Terms and the Merchant Agreement, the Merchant Agreement shall control.

---

## 11. Contact Information

For questions about settlement, payments, or withdrawal issues, please contact us at:

**Crunchy Plum, LLC**
[ADDRESS]
Email: [MERCHANT SUPPORT EMAIL]
Website: [WEBSITE URL]

---

*© [YEAR] Crunchy Plum, LLC. All rights reserved.*
