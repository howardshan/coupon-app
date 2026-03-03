# 6.团购券系统 Implementation Plan

## Priority: Bug Fix > Enhance Existing > New Features

### Step 1: Backend — Migration
- **File**: `deal_joy/supabase/migrations/20260301000001_coupon_gifting.sql`
- Add `gifted_from` (uuid, nullable, self-ref) to coupons — tracks gift origin
- Add `verified_by` (uuid, nullable, ref merchants) to coupons — who scanned
- Add RLS policy for gifted coupon select (recipient can see)
- Add `gift_coupon()` DB function for atomic gifting

### Step 2: Frontend — CouponModel
- **File**: `deal_joy/lib/features/orders/data/models/coupon_model.dart`
- Proper typed model with: id, orderId, userId, dealId, merchantId, qrCode, status, expiresAt, usedAt, createdAt, giftedFrom, verifiedBy
- Join data: dealTitle, dealImageUrl, merchantName, merchantLogo, merchantAddress, merchantPhone, refundPolicy

### Step 3: Frontend — CouponsRepository
- **File**: `deal_joy/lib/features/orders/data/repositories/coupons_repository.dart`
- fetchUserCoupons(userId) — joins deals + merchants
- fetchCouponDetail(couponId) — full detail with deal/merchant info
- giftCoupon(couponId, recipientUserId) — calls DB function

### Step 4: Frontend — CouponsProvider
- **File**: `deal_joy/lib/features/orders/domain/providers/coupons_provider.dart`
- couponsRepositoryProvider
- userCouponsProvider — all user coupons
- filteredCouponsProvider(status) — filtered by tab
- couponDetailProvider(couponId) — rich detail

### Step 5: Frontend — CouponsScreen (Tab List)
- **File**: `deal_joy/lib/features/orders/presentation/screens/coupons_screen.dart`
- TabBar: Unused / Used / Expired / Refunded
- CouponCard: merchant logo + name + deal title + status badge + expiry + purchase time
- Empty state: "No coupons yet" + "Browse Deals" button
- Tap → navigate to /coupon/:couponId

### Step 6: Frontend — Enhance CouponScreen (Detail)
- **File**: `deal_joy/lib/features/orders/presentation/screens/coupon_screen.dart`
- Show QR only for unused coupons; "Used on date at time" for used
- Auto-brightness on enter (screen.setBrightness)
- Deal title + description section
- Merchant name + address section
- Usage rules / refund policy
- Action buttons: Navigate to Store, Call Store, Request Refund, Gift to Friend
- Expiry display

### Step 7: Frontend — Router Update
- **File**: `deal_joy/lib/core/router/app_router.dart`
- Add `/coupons` route for CouponsScreen
- Replace "Orders" tab or add alongside

### Step 8: Frontend — QR Scanner Enhancement
- **File**: `deal_joy/lib/features/merchant/presentation/screens/qr_scanner_screen.dart`
- Record verified_by (merchant user ID) when marking coupon used
- Show "Verified!" text on success

### Step 9: Tests
- Fix widget_test.dart
- Write coupon model tests
- Write coupon repository tests (mock)
