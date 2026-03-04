# DealJoy Influencer Module Design

> Merchant + Influencer dual-sided feature. DealJoy's 2nd core differentiator (1st = instant refund).

## Compensation Models (3 types)

| Mode | Description | Example |
|------|-------------|---------|
| Flat Fee | One-time payment on task completion | Post 1 Reel = $50 |
| Per Redemption | Fixed amount per voucher redeemed | $10 per redemption |
| Revenue Share | % of each sale from referral | 6% of each sale |

Can be combined (e.g. $20 base + 5% share).

## Merchant Side Pages

### Campaign List (Influencer Hub)
- Tabs: Active / Completed / Draft
- Card: Deal name + compensation mode + budget progress + participants + sales
- CTA: "+ Create New Campaign"

### Create Campaign Form
- Select Deal (from merchant's published deals)
- Campaign Title
- Description / Requirements
- Content Platform checkboxes: IG Post/Reel, TikTok, YouTube Short, Xiaohongshu
- Compensation Model (radio: Flat Fee / Per Redemption / Revenue Share)
- Total Budget (auto-pause at limit)
- Campaign Duration (start-end dates)
- Max Influencers
- Min Follower Count (optional)

### Campaign Detail / Management
- Stats: Participants / Clicks / Redemptions / Amount Paid
- Influencer list with Approve/Deny/Pause actions
- Sales attribution bar chart per influencer
- Campaign settings: Edit / Pause / End

## Influencer Side Pages (inside User App)

### Entry: Me page -> "Influencer Portal" (requires application)

### Application Form (first time)
- Name, Platform, Handle, Follower Count
- Categories: Food/Beauty/Fitness/Lifestyle
- Payout: Stripe Connect or PayPal

### Influencer Dashboard
- Stats: Total Earnings / Total Sales / Active Campaigns
- Tabs: Browse Campaigns / My Campaigns
- Campaign cards: merchant photo, title, compensation, platform required, spots left

### Campaign Detail + Apply
- Merchant + Deal info, requirements, compensation details
- Text field for pitch
- [Apply to This Campaign]

### Active Campaign Work Page
- Referral Link (copyable)
- Promo Code (customer gets extra discount)
- Real-time: Clicks / Purchases / Redemptions / Earnings / Pending
- Activity Log (daily)
- Next payout date

## Data Model

### campaigns table
id, merchant_id, deal_id, title, description,
compensation_type (flat_fee/per_redemption/revenue_share),
flat_fee_amount, per_redemption_amount, revenue_share_pct,
total_budget, spent_amount, max_influencers, min_follower_count,
required_platforms[], content_guidelines,
start_date, end_date, status (draft/active/paused/completed/cancelled)

### influencer_profiles table
id, user_id, primary_platform, handle, follower_count,
categories[], payout_method, stripe_connect_id,
status (pending/approved/rejected/suspended)

### campaign_applications table
id, campaign_id, influencer_id, pitch,
status (pending/approved/rejected/completed),
referral_code (unique), referral_link (unique)

### referral_tracking table
id, application_id, event_type (click/purchase/redemption),
order_id, order_amount, commission_amount,
commission_status (pending/confirmed/paid/cancelled)

### influencer_payouts table
id, influencer_id, amount, payout_method,
stripe_transfer_id, status (pending/processing/completed/failed),
period_start, period_end

## Settlement Rules

- Per Redemption: commission confirmed after voucher redeemed
- Revenue Share: calculated as order_amount x percentage after redemption
- Flat Fee: influencer submits content proof, merchant manually confirms
- Payout cycle: 1st and 15th of each month
- Minimum payout: $25 (accumulates if under)
- User refund -> commission cancelled; if already paid, deduct from next cycle
