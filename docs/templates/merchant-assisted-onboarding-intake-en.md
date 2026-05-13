# Merchant onboarding intake form (admin-assisted entry)

**Purpose**: After the merchant grants authorization for your team to enter data on their behalf, they complete this form; operators transcribe it into the admin portal **Admin-assisted onboarding** at `/guanli/merchants/onboard`.  
**Internal runbook**: [SOP: admin-assisted merchant onboarding](../sop/admin-assisted-merchant-onboarding-sop.md) (Chinese).  
**Other formats**: [中文版](./merchant-assisted-onboarding-intake-zh.md) · [CSV / Excel template](./merchant-assisted-onboarding-intake-template.csv) (UTF-8 BOM; open in Excel)

---

## How to complete this form

- Use values that match the admin UI and APIs (legal names and addresses as on documents). **Category** must be exactly one of the English enum values listed below.
- **Login email** is both the Supabase account email and the application contact email; they must match.
- Documents: **PDF**, **JPEG**, **PNG**, or **WebP**. Use the **API document codes** in this form so operators can map files to upload slots.
- **US address**: use the line-by-line fields; ZIP must be 5 digits or ZIP+4 (e.g. `75201` or `75201-1234`).

---

## A. Account path (choose one)

| Field | Your answer |
|------|---------------|
| □ New account (`create_user`) / □ Existing account (`link_existing`) | |
| **Login email** (required) | |
| If new: set initial password now (≥8 chars), or let the system generate a one-time password delivered securely? | □ Merchant-provided password: ______________ / □ System-generated |
| If existing: **Supabase User ID** (if unknown, provide email so ops can Lookup) | |

---

## B. Store type

| Field | Your answer |
|------|---------------|
| □ Single store (`single`) / □ Chain or brand (`multiple`) | |
| If chain/brand: **Brand name** (optional) | |
| **Brand description** (optional) | |

---

## C. Business information

| Field | Your answer |
|------|---------------|
| **Legal company name** (Company name) | |
| **Contact person name** (Contact name) | |
| **Phone** (include country/area code if applicable) | |

(Contact email is the same as **login email** in section A—do not use a different address.)

---

## D. Business category (exactly one; must match admin dropdown)

Circle **one** of these values:

`Restaurant` · `SpaAndMassage` · `HairAndBeauty` · `Fitness` · `FunAndGames` · `NailAndLash` · `Wellness` · `Other`

**Selected category**: ________________

---

## E. EIN and documents

### E1. EIN / Tax ID

Example format: `12-3456789`

| **EIN / Tax ID** | |
|------------------|---|

### E2. Documents by category

**Every category** requires these four (`apiValue` in backticks):

| # | Document (API code) | File name or notes (merchant) |
|---|---------------------|-------------------------------|
| 1 | Business license (`business_license`) | |
| 2 | Owner / principal ID (`owner_id`) | |
| 3 | Storefront photo (`storefront_photo`) | |
| 4 | General liability insurance (`liability_insurance`) | |

**Additional documents for the category you selected in D** (use only the row that matches your category):

| Category | Additional API codes |
|----------|----------------------|
| Restaurant | `health_permit` · `food_service_license` |
| SpaAndMassage | `health_permit` · `cosmetology_license` · `massage_therapy_license` |
| HairAndBeauty | `cosmetology_license` |
| Fitness | `facility_license` |
| NailAndLash | `health_permit` · `cosmetology_license` |
| Wellness | `massage_therapy_license` |
| Other | `general_business_permit` |
| FunAndGames | *(none beyond the four base documents above)* |

**Extra rows for this merchant (duplicate as needed)**:

| API code | File description |
|----------|------------------|
| | |

---

## F. Store address (United States)

| Field | Your answer |
|------|---------------|
| **Address line 1** (required) | |
| Address line 2 (optional, suite/unit) | |
| **City** | |
| **State** (2-letter code, e.g. TX) | |
| **ZIP code** (5 digits or ZIP+4) | |

---

## G. Authorization and internal notes (Audit fields in admin)

| Field | Your answer |
|------|---------------|
| **Authorization / ticket reference** (maps to *Consent / ticket reference*; must be traceable) | |
| Internal note (maps to *Internal note*, optional) | |

---

## H. Acknowledgment (optional; follow your legal process)

I confirm that I authorize ________________ (platform / company name) to submit the above information and documents in the system on my behalf, and that the materials provided are accurate.

Merchant signature: ________________ Date: ________________  
(or electronic ticket / case ID: ________________)

---

## Operator checklist (before submitting in admin)

- [ ] Email matches chosen path (new vs existing); no accidental duplicate signup (`409 EMAIL_EXISTS`).
- [ ] Category matches the document set; all required files present.
- [ ] Address and ZIP follow US rules.
- [ ] **Consent / ticket reference** is filled in.
- [ ] If a one-time password was generated for a new account, it was delivered through a secure channel.

---

*Aligned with the May 2026 admin assisted onboarding form; update this template, the Chinese version, and the CSV template if backend fields change.*
