# DealJoy Merchant App UI Reference

> All merchant-side agents MUST read this before generating code.
> Design: clean North American style, functional dashboard layout.

## Global Design (same brand as user app)

Colors: Primary #FF6B35 (Orange), Background #F8F9FA, Card #FFFFFF
Font: SF Pro / Roboto
Corner radius: 12px cards, 8px buttons

## Bottom Navigation (4 tabs)

| Tab | Icon | Page |
|-----|------|------|
| Dashboard | grid/home | Merchant home with stats |
| Scan | qr-code-scan | Voucher verification (most used) |
| Orders | receipt | Order list |
| Me | person | Merchant profile + settings |

## 1. Merchant Onboarding Flow (Registration)

Multi-step wizard, each step = one screen:

### Step 1: Create Account
- Email + Password (or Google/Apple sign-in)
- Separate from user registration (different Supabase role)

### Step 2: Business Info
- Company Name (text input, required)
- Contact Person Name
- Contact Phone
- Contact Email (pre-filled from step 1)

### Step 3: Select Category
- Grid of category cards (single select):
  Restaurant, Spa & Massage, Hair & Beauty, Fitness,
  Fun & Games, Nail & Lash, Wellness, Other
- Each card: icon + label, selected = orange border

### Step 4: Upload Documents (DYNAMIC based on category)
- Business License: ALL categories (required)
- EIN / Tax ID: ALL (text input, format XX-XXXXXXX)
- IF Restaurant: + Health Permit + Food Service License
- IF Spa/Beauty/Nail: + Cosmetology License
- IF Spa/Wellness: + Massage Therapy License
- IF Fitness: + Facility License
- IF Other: + General Business Permit
- Each upload: tap to select file, show preview thumbnail, support image/PDF
- Owner ID: ALL (required)
- Storefront Photo: ALL (required)

### Step 5: Store Address
- Google Places autocomplete input
- Map preview showing pin
- Confirm button

### Step 6: Review & Submit
- Summary of all info entered
- Edit buttons next to each section
- [Submit for Review] button
- Checkbox: agree to Terms of Service

### Step 7: Under Review
- Status page: submitted timestamp, expected review time (24-48h)
- Illustration + friendly message
- Can close app and come back

### Rejection Flow
- Push notification + email with rejection reason
- Return to edit screen with problem fields highlighted in red
- [Resubmit] button

## 2. Dashboard (Merchant Home)

Top section: 4 stat cards in 2x2 grid
- Today Orders | Today Revenue | Pending Scans | Rating
Each card: large number + label + trend arrow

Quick Actions row (horizontal scroll):
- Scan Voucher (primary, highlighted)
- Manage Deals
- View Orders
- Reviews
- Influencer Hub
- Settings

Alerts section:
- Pending reviews to reply: X
- Pending refunds: X
- Pending influencer applications: X

Bottom: Mini line chart (7-day revenue trend)

Online/Offline toggle at top right (switch store status)

## 3. Store Management

Simple form page:
- Store Name, Description (multiline)
- Phone, Hours (per weekday picker)
- Photos: storefront (1 required) + environment (up to 10)
- Tags: WiFi, Parking, Wheelchair, etc. (chip selection)
- Category shown but not editable

## 4. Deal Management

### Deal List
- Tabs: All / Active / Inactive / Pending Review
- Each card: thumbnail + title + price + sold count + status badge
- FAB button: + Create Deal

### Create/Edit Deal Form
- Title (text)
- Description (multiline)
- Package contents (rich text or bullet list)
- Original Price + Deal Price (auto-calc discount %)
- Stock quantity (number, or toggle unlimited)
- Validity: date range OR X days after purchase
- Usage rules: available days, max per table, stackable toggle
- Images: 1-5, first = cover image
- [Submit for Review] button

## 5. Voucher Scan (Most Used Feature)

### Main Scan Page
- Large camera viewfinder (center 70% of screen)
- Bottom: [Enter Code Manually] text button
- Scanned -> Confirmation Page

### Scan Confirmation
- Deal name + package content
- Customer name (partial)
- Voucher code
- Expiry date
- Status badge (Valid/Expired/Used/Refunded)
- [Confirm Redemption] large orange button
- [Cancel] text button

### Manual Entry
- Text input for voucher code
- Same confirmation flow

### Redemption Success
- Large checkmark animation
- Redemption timestamp
- [Scan Another] button

### Error States
- Already used: show when & where
- Expired: show expiry date
- Refunded: show refund date
- Invalid code: show error message

### Scan History
- List view: date, customer, deal, voucher code
- Filter by date range and deal
- [Undo] button within 10 minutes

## 6. Order Management

- Tabs: All / Active / Redeemed / Refunded
- Each order card: order#, customer, deal, amount, status, date
- Tap -> detail page with full timeline
- Refunds are automatic in DealJoy (merchant view only, no approval needed)
- Export button (CSV)

## 7. Earnings

- Top: This Month Revenue / Pending Settlement / Total Settled
- Transaction list: each row = order#, amount, platform fee, net amount
- Filter by date
- Settlement info: T+N days after redemption, Stripe Connect payout
- Bank account info display

## 8. Reviews

- List: star rating, text, customer name, date, photos
- [Reply] button (one reply per review)
- Top stats: average rating, rating distribution bar chart

## 9. Notifications

- List view with icons per type
- Types: new order, redemption, review, system
- Unread dot indicator
- Tap to navigate to relevant page

## 10. Influencer Hub

See docs/features/influencer-module.md for full spec.
Summary: Campaign list, Create campaign, Approve influencers, Track performance.

## 11. Settings

- Account security (change password, 2FA)
- Staff accounts (add employee with limited permissions)
- Notification preferences (toggles per type)
- Help center / FAQ
- Sign out

## Key Interaction Details

### Pull to Refresh
- Dashboard, Orders, Reviews all support pull-to-refresh

### Loading States
- Skeleton shimmer while loading (not spinner)

### Empty States
- No orders yet: illustration + Go create your first deal
- No reviews: illustration + Deals need more exposure

### Error Handling
- Network error: retry button
- Session expired: redirect to login
