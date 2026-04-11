# Claude Code Prompt — User & Merchant App Unfinished Entrances (2026-03-19)

> Copy this entire file into Claude Code to orchestrate delivery. Each point enumerates concrete tasks for Product, Architecture, Backend, Database, Frontend, DevOps, and Testing (excluding Builder). All file paths are relative to repo root. Supabase = `./supabase`.

---

## Point 1 · User Profile Header – Avatar Editing & "My Home Page"

### Product (12-CTO-Product)

- Deliver PRD section `docs/product/profile-header.md` covering user stories, acceptance criteria, telemetry.
- Specify editable fields (avatar, display name, short bio, homepage slug) and validation (jpeg/png <= 5MB, name length 2-32, slug regex `^[a-z0-9-]{3,20}$`).
- Define fallback UX (upload failure, slug collision, offline) and instrumentation events (`profile_edit_open`, `profile_avatar_upload_success`, etc.).
- Document dependency on Supabase Storage bucket `avatars` and marketing review for homepage slug guidelines.

### Architecture (12-CTO-Architecture)

- Update `deal_joy/lib/core/router/app_router.dart`: add routes `/profile/edit` and `/profile/homepage/:slug` using `GoRoute`.
- Introduce `ProfileEditRepository` with methods `uploadAvatar`, `updateProfile`, `reserveSlug`; expose via Riverpod `profileEditProvider`.
- Prepare ADR (`docs/adr/ADR-joy-profile-edit.md`) covering Storage choice, offline cache (keep old avatar path until success), slug uniqueness strategy.
- Sequence diagram for edit flow (user -> Flutter -> Edge Function -> Storage -> Postgres) added to `/docs/diagrams/profile-edit.mermaid`.

### Backend (12-CTO-Backend)

- Create Supabase Edge Function `supabase/functions/profile-edit/index.ts` to: validate JWT, resize image (Sharp), upload to `avatars/{userId}/{timestamp}.jpg`, return public URL.
- Implement `supabase/functions/profile-homepage/index.ts` to serve homepage content (slug lookup) and enforce privacy (only user-specific or public slug).
- Add REST endpoints doc to `docs/api/profile.md` including error codes (`AVATAR_UNSUPPORTED_TYPE`, `SLUG_TAKEN`).
- Ensure functions log `request_id`, `user_id`, `latency` and push to Sentry.

### Database (12-CTO-Database)

- Migration `supabase/migrations/20260319_profile_header.sql` adding columns `homepage_slug TEXT UNIQUE`, `bio TEXT`, `avatar_version INT DEFAULT 0` to `profiles`.
- Create table `profile_homepage_views` for analytics (user_id, viewer_id, created_at).
- Add trigger to increment `avatar_version` on avatar change (for CDN busting).
- RLS policies: only owners can update their row; homepage slug unique constraint enforced at DB.

### Frontend (12-CTO-Frontend)

- Files: `lib/features/profile/presentation/screens/edit_profile_screen.dart`, `lib/features/profile/presentation/screens/profile_homepage_screen.dart`, `widgets/avatar_uploader.dart`.
- Use `image_picker` + `image_cropper` for avatar; show progress HUD; support retry after failure.
- Optimistic updates but rollback on API error; maintain offline cache in Hive box `profileCache`.
- Add share button on homepage (uses `share_plus`).
- Update analytics calls via `app_logger.logEvent` with defined payload.

### DevOps (12-CTO-DevOps)

- Configure Supabase Storage bucket `avatars` with correct policies; document command in `docs/runbooks/storage.md`.
- Extend CI to run `supabase db diff` for migration verification + `deno test` for new functions.
- Secrets: store `IMG_MAX_SIZE_MB` and `ALLOWED_MIME_TYPES` in `.env` templates; ensure GitHub Actions inject them.
- Monitoring: create Datadog dashboard for `profile-edit` function (p95 latency, error rate, throughput).

### Testing (12-CTO-Testing)

- Backend deno tests: avatar type rejection, slug collision, concurrent slug reservations.
- Flutter widget tests: avatar uploader (loading, success, error), homepage view (empty bio, long bio).
- Integration test `integration_test/profile_edit_flow_test.dart` covering full edit + homepage share.
- QA checklist: various image sizes, offline editing, malicious slug attempt, cross-language characters.

---

## Point 2 · User Profile Member Center Card

### Product

- Extend `docs/product/membership.md` with tier definitions, growth value formula, benefit catalog, change management plan.
- Acceptance: member card shows current tier badge, growth progress (value & percentage), CTA to benefits list; data refresh pull-to-refresh + auto refresh every 15 mins.
- KPIs: member conversion %, benefits usage, card click-through.
- Dependency: operations team to input benefit copy via CMS (specify dataset format).

### Architecture

- Add `/membership` route & `MembershipRepository` under `lib/features/profile`.
- Define `MembershipSummary` model with `tier`, `growth`, `nextTier`, `benefits[]`, `lastUpdated`.
- Caching strategy: store summary in Hive for offline display; refresh background using `ref.listen`. Document in ADR.

### Backend

- Edge Function `membership-summary`: query `membership_tiers`, `membership_growth_logs`, `membership_benefits` (with locale) and aggregate.
- Provide `membership/benefits` endpoint used by both app + marketing site; include `is_available` flag.
- Logging: output when benefit config missing for tier.

### Database

- Tables: `membership_tiers(id, name, min_growth, badge_assets)`, `membership_growth_logs(user_id, source, value, created_at)`, `membership_benefits(tier_id, title, description, icon_url, priority, locale)`.
- Materialized view `membership_user_summary` (refresh nightly + on trigger) to speed up reads.
- Migration adds indexes on `user_id`, `tier_id`.

### Frontend

- UI: `membership_screen.dart` with sections—Tier Hero, Growth timeline (list), Benefits grid, FAQ link.
- `Gold Member` card on profile becomes dynamic: gradient colors from tier config, stars count equals tier.
- Implement `BenefitsModal` showing detail, deep link to specific benefit.
- Offline mode: show cached summary + toast "Data may be outdated".

### DevOps

- Schedule job (Supabase cron) nightly to recompute summary view.
- Setup feature flag `membership.v1.enabled` in ConfigCat (or env) to guard release.
- Observability: metrics for summary function (cache hit, DB miss); alert if latency > 1s.

### Testing

- Unit tests for growth calculation (orders, reviews, manual adjustments).
- Snapshot tests for each tier UI.
- End-to-end: simulate user crossing tier boundary -> verify card updates.
- Accessibility: ensure screen reader labels for benefit icons.

---

## Point 3 · User Profile Joy Coins (Rewards Wallet)

### Product (12-CTO-Product)

- Own `docs/product/joy-coins.md` (already created) and keep all six sections updated: Information Architecture, Interaction Flows, Business Rules, Performance/Observability, Internationalization, Support Strategy.
- Capture detailed user stories for: Entry tile exposure, Balance hero card, 30-day transaction list, Empty state with "去逛 Deals" CTA, Rules link fallback.
- Document interaction variants: first load, pull-to-refresh, API retry, zero balance, no transactions, weak network/offline, timeout >3s, pagination.
- Maintain accrual/deduction rule tables (order cashback %, review bonus, CS adjustment, refunds, violation debit, redemption) plus balance constraint + approval workflow for negative adjustments.
- Define analytics spec (event names, payload schema) and KPIs (entry CTR, Joy Coins DAU, average balance, failure rate <1%).
- Provide localized copy IDs + default zh/en strings + rule page URL owner, include JoyCoinReasonMapper mapping table.
- Add acceptance checklist + dependencies (Finance, Risk, Marketing) + release checklist (User App 2.5.0, gray 10% rollout, store copy updates) into PRD + Jira.

### Architecture (12-CTO-Architecture)

- Router: add `/joy-coins` route + deep link metadata; ensure Profile shortcut navigates with hero animation args.
- Data layer: `JoyCoinsRepository` handling cache-first fetch, pagination (`?cursor=`), retry/backoff, analytics hooks; `JoyCoinsNotifier extends AutoDisposeAsyncNotifier<JoyCoinsState>` with states Loading/Success/Error/Cached.
- Models: `JoyCoinsSummary`, `JoyCoinTransaction`, `JoyCoinReasonMeta`; include serialization + Hive adapters (register via `hive_box_registry.dart`).
- State management: throttle refresh (1 request / 2s) & centralize inside repository; expose `loadMore()` and `refresh()` APIs.
- Offline strategy: persist latest response with timestamp; provide `InfoBannerState` when showing cached data; document fallback diagram in `docs/diagrams/joy-coins-flow.mmd`.
- Accessibility & telemetry hooks: architecture doc to define semantics interface, event dispatch points, and failure logging pipeline.

### Backend (12-CTO-Backend)

- Edge Function `supabase/functions/joy-coins-history/index.ts`:
  - Auth: `getUser(jwt)`; 401 when missing/invalid.
  - Inputs: `cursor` (ISO8601, optional), `limit` (1–50, default 30), `type` filter (ALL/EARN/SPEND future flag) but ignore for now.
  - Query view `joy_coin_transactions_last30`; if cursor provided, apply `< cursor` pagination; respond with `transactions`, `nextCursor`, `balance`, `lastUpdated`.
  - Include `cache_control` headers for CDN (max-age 5s) and `request_id` logging; send metrics to Datadog (latency, error rate, throttled count).
- Helper module `lib/utils/joyCoins.ts` implementing `addJoyCoinTransaction(payload)` with idempotency key + negative-balance guard + approval override field.
- API reference `docs/api/joy-coins.md` now details error codes (`INSUFFICIENT_FUNDS`, `THROTTLED`, `CURSOR_INVALID`, `RATE_LIMITED`) and sample payloads.
- Emit structured logs with `user_id`, `balance_before`, `balance_after`, `reason_code`, `source_ref`, `request_id`.

### Database (12-CTO-Database)

- Migration `supabase/migrations/20260319_joy_coins.sql` includes:
  - Tables `joy_coin_wallets` (pk user_id, balance numeric, updated_at) & `joy_coin_transactions` (id uuid, user_id, delta, reason_code, metadata jsonb, created_at, source_ref, approver_id, idempotency_key).
  - Trigger `prevent_negative_balance` except when `allow_negative=true` flag set + `approved_by` not null.
  - Materialized view `joy_coin_transactions_last30` refreshed on demand (SQL + comment with refresh strategy) and indexes `(user_id, created_at DESC)`.
- Policies: `select` on wallets limited to `auth.uid() = user_id`; transactions insert allowed for service role + CS Edge Function; view exposed only via RPC.
- Seed reason code dictionary table for analytics/backfill.

### Frontend (12-CTO-Frontend)

- Directory `lib/features/profile/presentation/joy_coins/` with:
  - `joy_coins_screen.dart`: `Scaffold` + `NestedScrollView` + `RefreshIndicator`; `SliverAppBar` pinned hero card; `SliverList` for timeline; attaches `ScrollController` for pagination.
  - Widgets: `joy_coin_balance_card.dart`, `joy_coin_transaction_list.dart`, `joy_coin_transaction_tile.dart`, `joy_coin_empty_state.dart`, `joy_coin_error_state.dart`, `joy_coin_info_banner.dart`.
  - `JoyCoinReasonMapper` mapping `reasonCode -> JoyCoinReasonMeta` (icon, localized label). Source reason strings from generated l10n.
- UI/UX specifics:
  - Loading: shimmer skeleton for balance + three rows.
  - Success: InfoBanner when showing cached data ("Last updated at…").
  - Error: inline component with "Tap to retry" hooking to notifier refresh.
  - Pull-to-refresh uses `throttle(2s)` to prevent spam.
  - Pagination trigger near bottom to call `loadMore()` with spinner & retry chip.
  - Rule link opens `AppWebView(url: AppConstants.joyCoinRulesUrl)`; fallback to Markdown page if `canLaunch` fails.
  - Accessibility: semantics for hero card + each transaction reading "Plus two hundred Joy Coins" / "Minus fifty…" etc.
  - All widgets expose `Key(...)` for testability; follow `AppColors`/`AppTypography` tokens.
  - Analytics hook `JoyCoinsAnalytics.trackView()` on init, `trackRuleClick()` on CTA.
  - Currency formatting via `NumberFormat('#,###')` + `Joy Coin` suffix.

### DevOps (12-CTO-DevOps)

- Config env vars `JOY_COINS_PAGE_SIZE`, `JOY_COINS_CACHE_TTL_SEC`, `JOY_COINS_REFRESH_TIMEOUT_MS` in `.env`, `.env.example`, GitHub Actions secrets.
- CI: add `deno test supabase/functions/joy-coins-history` + `npm run lint` for TS helper.
- Monitoring: Datadog/Supabase metrics board for p95 latency (<1s), error rate (<1%), throughput, cache hits; alert when failure rate >1% or latency >1.5s.
- Feature flag `profile.joyCoins.enabled` managed via remote config for 10% gray rollout; runbook `docs/runbooks/joy-coins.md` instructs how to reprocess failed tx + disable flag if needed.
- Update release checklist (App v2.5.0 store copy, App Store/Play description, analytics dashboards) and document owner.

### Testing (12-CTO-Testing)

- Database pgTAP: enforce triggers, negative-balance prevention, allow-negative override with approval, idempotency uniqueness, materialized view refresh integrity.
- Edge Function Deno tests: happy path, invalid cursor, cursor from other user, throttling after >N req/min, unauthorized, pagination, limit bounds.
- Flutter unit/widget tests: balance card, transaction tile (positive/negative), empty state CTA navigation, InfoBanner, error retry, pagination spinner, throttle behavior (mock clock), semantics labels.
- Integration test `integration_test/profile_joy_coins_test.dart`: covers first load success, offline cached view, pull-to-refresh success/failure, load more, rule link open.
- QA manual plan: create order -> +delta, refund -> -delta, manual adjustment requiring approval, offline mode, slow network (>3s) verifying fallback, localization (en/zh), accessibility (screen reader), analytics event validation.

---

## Point 4 · User Profile Utilities (Recharge, Review Team, Charity)

### Product

- Create three subsections in `docs/product/profile-utilities.md` with flows, compliance requirements, and dependencies.
- Recharge: specify supported payment rails (Stripe, Apple Pay, Google Pay), top-up denominations, refund policy, AML/KYC constraints.
- Review Team: outline application form fields, screening SLA, backend CRM integration.
- Charity: list campaigns, min donation, tax receipt handling, recurring donations (future roadmap).
- Define analytics events per entry.

### Architecture

- Add `/wallet/recharge`, `/community/review-team`, `/charity` routes.
- Recharge flow integrates with existing checkout to reuse payment components; state machine documented as UML.
- Review Team uses multi-step form with autosave; Charity reuses deals list layout with donation CTA.

### Backend

- Recharge: `wallet/topup` function—creates Stripe checkout session, writes pending transaction, handles webhook `checkout.session.completed` to credit wallet.
- Review Team: `review-team/applications` POST (RLS ensures per-user), `review-team/status` GET, admin notification through Supabase webhook.
- Charity: `charity/projects` (GET, cached), `charity/donations` POST (validates minimum, currency), triggered email receipt.
- Document error codes and webhook payloads.

### Database

- `wallet_topups(id, user_id, amount, currency, status, created_at, payment_provider_ref)` + indexes.
- `review_team_applications(id, user_id, experience, availability, status, reviewer_notes, created_at)`.
- `charity_projects(id, title, summary, goal_amount, raised_amount, image_url, is_active)` and `charity_donations(id, user_id, project_id, amount, currency, created_at)`.
- Add RLS policies to restrict updates.

### Frontend

- Recharge screen: amount selector, payment method chips, confirmation dialogue; show top-up history from wallet transactions.
- Review Team: multi-step form wizard with progress indicator, file upload for credentials, submission success page.
- Charity center: list of cards with progress bars, donate modal (input amount + optional message).
- Hook up analytics & deep link support.

### DevOps

- Payment providers secrets in `.env`; ensure test/staging keys separated.
- Webhook endpoint secured with secret; set up retries.
- Cron to sync charity project status from external CMS if needed.

### Testing

- Payment sandbox tests (Stripe test cards) for recharge success/failure/timeout.
- Review application duplicate submission prevention.
- Charity donation receipts (email) verification.
- Security testing: injection attempts in form fields.

---

## Point 5 · User Cart Checkout Button

### Product

- Extend CART PRD: batching rules, split-order logic, coupons compatibility, messaging for partial failure.
- Document dependency on Supabase cart schema and merchant configuration.

### Architecture

- `cart_screen.dart` now calls `CartCheckoutController`. Provide state machine diagram (Idle → Validating → Processing → Result).
- Support both "Checkout All" and per-item selection; ensure new provider `selectedCartItemsProvider`.

### Backend

- Edge Function `cart/checkout` (TypeScript) performing: inventory check via `deals` table, compute totals, create `orders` + `order_items`, initiate payment intent (Stripe) across multiple deals, handle partial store grouping.
- If merchant requires separate orders per store, function should break down payload accordingly.

### Database

- Update `orders` schema with `cart_snapshot JSONB` storing item metadata; add `parent_cart_id` linking multiple orders from single checkout.
- Add `cart_items` table indexes for `user_id, deal_id` to speed up query.

### Frontend

- Improve UI: show summary sheet with subtotal/tax/discount before confirm; disable button when cart empty or invalid.
- Implement success page that iterates through created order IDs and navigates to first order detail.
- Handle errors (inventory, payment declined) with actionable messaging.

### DevOps

- Payment webhook ensures idempotency (cart checkout id recorded); update runbooks for manual rerun.
- Load testing plan for checkout function.
- Logging: add structured logs with `cart_id`, `order_ids`.

### Testing

- Backend unit tests for stock shortage, price mismatch, concurrency.
- Frontend integration test simulating checkout with 2 items different merchants.
- QA scenario matrix covering coupon applied, network drop, user cancels payment.

---

## Point 6 · User Chat Tab Static Placeholder

### Product

- Draft messaging MVP spec: conversation types (support, order thread, broadcast), retention policy, SLA for responses.
- Include compliance requirements (privacy, logging, opt-in for marketing).

### Architecture

- Adopt Supabase Realtime or dedicated socket server; diagram connection lifecycle, reconnection strategy, offline caching.
- Define data contract `ConversationSummary` + `ChatMessage`. Document in `docs/api/chat.md`.

### Backend

- REST endpoints: `GET /chat/conversations`, `GET /chat/conversations/:id/messages?cursor=...`, `POST /chat/send`.
- Webhook to route certain messages to helpdesk (e.g., Zendesk) if agent not online.
- Implement read receipts and typing indicators via realtime channel.

### Database

- Tables: `chat_conversations`, `chat_participants`, `chat_messages`, `chat_read_states` with necessary indexes + TTL (if required by privacy).
- RLS to restrict conversation access.

### Frontend

- Replace dummy `_conversations` with provider hooking to backend; implement list virtualization for long threads; include attachments (images) support (optional flag).
- Provide badges for unread count in tab bar; push notifications for new messages.
- Support multi-device sync by storing `lastReadAt` per conversation.

### DevOps

- Enable Supabase Realtime, tune connection limits; add Sentry instrumentation for message send failures.
- Setup push notification keys for FCM/APNS specific to chat events.

### Testing

- Backend tests for unauthorized access, pagination; concurrency tests for read receipts.
- Frontend integration tests (send/receive/scroll history, offline queue).
- Load test with 1k concurrent chats.

---

## Point 7 · User Merchant Dashboard Placeholder

### Product

- Document Merchant mobile MVP: metrics (today redemptions, total revenue, active deals, total reviews), quick actions (scan, create deal), persona (merchant owner).
- Define freshness requirements (metrics <=15 min old) and offline messaging.

### Architecture

- Merchant-only route `/merchant/dashboard` requiring role guard (`user.role == merchant`); share state provider from merchant app APIs if possible.
- Structure modules: `MerchantMetricsProvider`, `QuickActions`.

### Backend

- Expose metrics endpoint `merchant/mobile-dashboard` returning aggregated KPIs plus shortcuts; reuse merchant backend data sources to avoid duplication.
- Provide `POST /merchant/deals` for quick create flow integration (maybe open builder? specify handshake).

### Database

- Ensure `merchant_stats_hourly` or similar table available; if missing, create mat view summarizing orders, redemptions.

### Frontend

- Replace static cards with real data, add refresh; `Create Deal` button pushes to merchant builder (or webview) with SSO token.
- Show skeleton while loading, error state with retry.

### DevOps

- SSO tokens for merchant builder stored securely; update runbook for mobile merchant metrics pipeline.
- Monitor `merchant-dashboard` API latency.

### Testing

- Unit tests verifying role guard; integration tests hitting API with mocked responses; QA verifying metrics match merchant web dashboard.

---

## Point 8 · User Register TOS/Privacy Links

### Product

- Ensure legal team provides latest URLs + version numbers; record in PRD.

### Architecture/Frontend

- Implement `TapGestureRecognizer` launching `AppConstants.termsUrl` / `privacyUrl`; fallback to `showDialog` if `canLaunch` false.
- Add instrumentation event `register_terms_clicked` with `doc_version`.

### DevOps

- Confirm URLs accessible via in-app webview; add to allowlist if using app transport security.

### Testing

- Widget test verifying gestures trigger `launchUrl`; manual test in restricted network.

---

## Point 9 · User Deal Detail “See All Reviews”

### Product

- Document review listing spec (sorting, filtering, pagination, highlight official replies).

### Architecture

- Add route `/deals/:id/reviews` and provider `dealReviewsProvider` supporting infinite scroll.

### Backend

- API `GET /deals/{id}/reviews?limit=20&cursor=` returning aggregated rating stats + review list; support filtering by rating.

### Database

- Index `reviews(deal_id, created_at DESC)`; optionally mat view for rating counts.

### Frontend

- Build new screen with rating summary, filter chips, review cards (user avatar, name, rating, text, photos, merchant reply); integrate `See All` button.

### DevOps

- Cache layer for reviews; monitor throughput.

### Testing

- API contract tests; front-end scroll/pagination tests; QA verifying 1k reviews load without jank.

---

---

## Point 10 · Merchant Dashboard Influencer Tile (No Route) & Full Influencer Module Missing

### Product

- Draft `docs/product/merchant/influencer.md` describing campaign lifecycle, application workflow, payout rules, KPIs (GMV via influencers, approval SLA).
- Define personas (brand admin vs store owner), permissions, and notification requirements.
- Specify reporting needs (clicks, conversions, pending applications) and integration with accounting (commission payouts).

### Architecture

- Add routes `/influencer`, `/influencer/campaign/:id`, `/influencer/applications`, `/influencer/performance` guarded by role (brand_admin, staff_manager).
- Create `InfluencerRepository` hooking to backend APIs; state slices for campaigns, applications, performance metrics; caching strategy (refresh on pull, background sync every 10 min).
- Update dashboard `_TodoTile` to navigate to `/influencer/applications` with deep links including filter.

### Backend

- Implement REST endpoints: `GET /influencer/campaigns`, `POST /influencer/campaigns`, `PATCH /.../:id`, `GET /influencer/applications?status=pending`, `POST /influencer/applications/:id/approve`, `.../reject`, `GET /influencer/performance?campaignId=`.
- Each endpoint enforces brand ownership, logs actions, and pushes notifications (email/Slack) on new applications or approvals.
- Provide webhook for user app to fetch influencer promo content (future).

### Database

- Tables: `influencer_campaigns` (brand_id, name, brief, goals, status, budget, start/end), `influencer_applications` (campaign_id, influencer_profile, proposal, status, reviewer_id, reviewer_notes), `influencer_tracking` (campaign_id, clicks, orders, commission_amount), `influencer_payouts`.
- Index `applications(status, created_at)` for dashboard queries; add triggers to auto-calc `approved_count`.

### Frontend

- Build influencer module UI: campaign list page (cards with stats), detail page (tabs for overview, performance, creatives), application inbox (swipe actions approve/reject), performance dashboard (charts via `syncfusion_flutter_charts`).
- Add forms for creating/editing campaigns with validation; integrate file upload for assets.
- Dashboard tile now shows pending count + spinner while loading.

### DevOps

- New service environment variables (e.g., `INFLUENCER_APPROVAL_EMAIL`, `WEBHOOK_SECRET`).
- Update CI to run additional backend tests (`supabase/functions/influencer`), lint new Dart modules.
- Create dashboards for influencer endpoints (latency, approvals/day) and set alerts on approval backlog.

### Testing

- Backend unit/integration tests for campaign CRUD, application approval concurrency, permission leakage.
- Frontend widget/integration tests (create campaign, approve application, view performance charts).
- QA scenarios: multiple brands, staff roles, failing network, verifying analytics data accuracy.

---

## Point 11 · Merchant Marketing – Flash Deals Page Placeholder

### Product

- Expand marketing spec with Flash Deal requirements: extra discount %, eligible deals, scheduling, limit per user, surfaces (user app home, search badge).
- Define compliance (stacking rules with coupons) and KPIs.

### Architecture

- Route `/marketing/flash-deals`; `FlashDealsProvider` handles fetch/create/update/delete; offline caching disabled (data must be fresh).
- Document state diagram for flash deal lifecycle (Draft → Active → Expired → Archived).

### Backend

- REST endpoints under `/marketing/flash-deals`: list (with status filters), create, update, delete, bulk publish/unpublish.
- Validation: ensure discount < base discount, schedule does not overlap for same deal, concurrency control via `updated_at` check.
- Webhook to notify user app caches to refresh Flash Deals shelf.

### Database

- Table `flash_deals` (id, brand_id, deal_id, extra_discount_pct, start_at, end_at, status, created_by, updated_at).
- Trigger to auto-set status to `expired` when `end_at < now()`; optional job to enforce.

### Frontend

- Build Flash Deals list UI with status pills, search, quick filters; row actions for edit/duplicate/delete.
- "New" button opens modal/wizard (select deal -> configure discount and schedule -> review summary).
- Provide detail drawer to show analytics (impressions, redemptions) once available.

### DevOps

- Cron job (Supabase or Cloud Scheduler) to transition statuses; monitoring to ensure job runs.
- Feature flag `marketing.flashDeals.enabled` for progressive rollout.
- Logging/alerting for overlapping schedule rejection.

### Testing

- Backend tests for overlapping schedules, invalid discount, permission; front-end tests for wizard steps, validation messaging; e2e verifying user app display (integration test hooking to staging).

---

## Point 12 · Merchant Marketing – New Customer Offer Placeholder

### Product

- Define new customer price strategy: eligibility (first order globally vs per brand), cap per offer, stacking rules.
- Document messaging to user app and measurement plan.

### Architecture

- `/marketing/new-customer-offers` route; provider + local models; consistent state machine (Draft, Active, Paused).

### Backend

- Endpoints `GET/POST/PATCH/DELETE /marketing/new-customer-offers` with validation (price >= cost floor, limit <= 1000, etc.).
- Provide endpoint for analytics (how many new customers converted).
- Ensure user app pricing API accepts `new_customer_offer_id` boost.

### Database

- `new_customer_offers` table with fields (brand_id, deal_id, offer_price, per_user_limit, total_limit, start_at, end_at, status, created_by, updated_at).
- Add view for monitoring redemption counts.

### Frontend

- UI similar to Flash Deals but with highlight for "New customer only"; creation form asks for price, quotas, schedule, description.
- Provide warnings if offer overlaps with flash deal (call backend validation).

### DevOps

- Add nightly job to pause offers once quota reached; instrumentation for conversions.

### Testing

- Backend tests for eligibility enforcement; front-end tests for form validation; QA verifying user app order uses offer price only when user has zero orders.

---

## Point 13 · Merchant Marketing – Promotions (Spend X Get Y) Placeholder

### Product

- Document promotion types (fixed discount, percentage, free item), minimum spend, stacking rules, store inclusion/exclusion.

### Architecture

- `/marketing/promotions`; provider handles effectivity + caching; share components with other marketing pages.

### Backend

- CRUD endpoints verifying spend thresholds >= 0, discount <= spend, schedule; hooking into checkout pipeline via event or rules engine.
- Provide preview endpoint returning sample savings for QA.

### Database

- `promotions` table with JSON `rules` column for flexible conditions; `promotion_store_assignments` table linking to stores.

### Frontend

- Build creation wizard with rule builder UI; list view showing active/inactive promotions, upcoming expiration warnings.

### DevOps

- Cron job to expire promotions; monitoring for rules conflicts; config toggles.

### Testing

- Backend tests for rules evaluation; front-end tests for builder UI; e2e verifying discount applied at checkout.

---

## Point 14 · Merchant Marketing Brand Chips -> 404 Routes Missing

### Product

- Outline brand-level capabilities (Campaigns, Promo Codes, Loyalty) including governance (brand admin only), global vs per-store settings.

### Architecture

- Implement `GoRoute`s `/marketing/brand-campaigns`, `/marketing/brand-promo-codes`, `/marketing/brand-loyalty` plus nested child routes for create/edit.
- Introduce `BrandMarketingRepository` to fetch brand-level data.

### Backend

- Add APIs grouped under `/brand/marketing/...` with RBAC ensuring brand_admin role; integrate with existing brand management data.
- Provide pagination, search, filtering.

### Database

- Tables for `brand_campaigns`, `brand_promo_codes`, `brand_loyalty_tiers`, `brand_loyalty_rewards`; indexes and RLS policies.

### Frontend

- Update `_BrandToolChip` callbacks to new routes; build UI screens similar to marketing ones but scoped to multiple stores; include store selectors.

### DevOps

- Update router tests; monitor 404 rates to ensure drop; add alerts for unauthorized attempts.

### Testing

- Role-based tests verifying only brand admins access; front-end e2e for each route; QA verifying store assignments apply.

---

## Point 15 · Merchant Earnings Payment Account Actions "Coming Soon"

### Product

- Expand payouts spec covering KYC, onboarding, re-onboarding, disconnect flow, and copy for statuses (pending requirements, verified, payouts paused).

### Architecture

- PaymentAccountScreen action buttons must call real functions; top banner indicates status and outstanding requirements; reuse `stripeAccountProvider` with states (Unlinked, Pending, Active, Restricted).

### Backend

- Edge Function `stripe-connect/link` creates account link; `stripe-connect/refresh` for existing accounts; `stripe-connect/disconnect` detaches account and marks payouts paused.
- Webhook endpoint processes events (account.updated, payout.failed), updates DB, emits notifications.

### Database

- `stripe_accounts` table storing `merchant_id`, `stripe_account_id`, `status`, `requirements_json`, `last_synced_at`.
- `payout_events` log table for auditing.

### Frontend

- Buttons: "Connect Stripe" (opens webview with link), "Manage on Stripe" (refresh link), "Disconnect" (confirm dialog). Show requirement checklist with statuses.
- Add toast + auto refresh after returning from Stripe.

### DevOps

- Manage Stripe secrets (test/prod) via GitHub Actions secrets; update webhook endpoint base URL; set monitors for webhook failures.
- Document runbook for reprocessing failed webhooks.

### Testing

- Simulate Stripe onboarding via test mode; unit tests for requirement parsing; integration tests verifying webhook updates UI; QA covering reconnect flow, disconnect behavior.

---

## Point 16 · Merchant Earnings Reports Export Button Inactive

### Product

- Decide export format (PDF+CSV) and contents (summary tables, transaction list); include brand logo + timeframe filters.

### Architecture

- Add `exportStateProvider` handling request lifecycle; UI button shows spinner, disables while running, displays success toast with open/share actions.

### Backend

- Function `earnings/report-export` accepts parameters (periodType, month, format), triggers job to generate file (using e.g., Puppeteer for PDF) stored in Supabase Storage, returns signed URL.
- Implement job queue if generation takes >30s.

### Database

- `report_exports` table storing job_id, merchant_id, params, status, file_url, expires_at.

### Frontend

- On success, present bottom sheet with options: Open, Share, Copy Link; handle expiration (auto refresh if link expired).
- Provide error messaging with log ID for support.

### DevOps

- Ensure Storage bucket `exports` has lifecycle rule (delete after 30 days); monitor job duration; configure CI to run PDF generation tests.

### Testing

- Backend unit tests for job creation, error handling; manual test verifying PDF contents; UI tests for button states; QA cross-check totals vs on-screen data.

---

## Point 17 · Merchant Orders "Export CSV" Lacks File Delivery

### Product

- Document max export rows (e.g., 50k), export fields, timezone handling, email fallback if >20k rows.

### Architecture

- `OrderExportController` triggers backend job, polls status (WebSocket or periodic GET); UI shows progress chip and "Download" button once ready.

### Backend

- Function `orders/export` creates job entry, spawns worker (Supabase queue or background function) generating CSV -> Storage; returns job id. Provide `GET /orders/export/:jobId` for status + file URL.
- Support optional filters (date range, status, store).

### Database

- `order_export_jobs(id uuid, merchant_id, filters jsonb, status enum, file_url, created_at, completed_at, error_message)`.

### Frontend

- Replace toast with actual workflow: after clicking export show dialog summarizing filters + estimated time, then progress indicator, completion state with share/download actions.
- Integrate `share_plus` to share CSV; handle platform file permissions (Android SAF).

### DevOps

- Configure Storage bucket `exports/orders` + lifecycle; ensure worker has sufficient memory/timeouts; log job metrics.

### Testing

- Backend job tests simulate 10k orders; front-end integration test for job polling; QA verifying exported CSV encoding (UTF-8, comma), timezone formatting, failure retry.

---

## Point 18 · Merchant Deal Templates "Edit Template" Not Wired

### Product

- Update template management spec: editable fields, restrictions (e.g., cannot change base price if already published), audit logging, notifications to stores.

### Architecture

- Add route `/brand-manage/deal-templates/:templateId/edit`; share form components with create page but pre-fill data and show read-only sections where needed.

### Backend

- Add endpoints `GET /brand/templates/:id`, `PUT /brand/templates/:id` with validation + optional `sync_to_stores` flag; emit events to trigger store sync (Edge Function or Supabase queue).

### Database

- Add `deal_template_versions` table storing history + `current_version_id` reference; triggers to log user_id/time.
- Possibly table `template_store_overrides` for store-specific adjustments.

### Frontend

- Template list `Edit` action now pushes to new route; edit form shows status badges, unsaved changes guard, preview; after save, toast + refresh list.

### DevOps

- Update CI routes test; ensure store sync job metrics recorded; Sentry instrumentation for edit failures.

### Testing

- Backend tests for permissions + versioning; front-end e2e editing flow; QA verifying published stores reflect updated template (with or without overrides).

---

## Point 19 · Merchant Onboarding Stripe Payout Step Placeholder

### Product

- Extend onboarding spec: after document upload, require payout setup (Stripe Connect) before final submission; define copy for skip flow + reminders.

### Architecture

- Registration state machine adds `PAYOUT_SETUP` step; store progress in provider; display stepper with checkmarks; support "Skip now" but show blocking banner elsewhere until completed.

### Backend

- Reuse Stripe connect endpoints from Point 15; registration step triggers account link creation; store result in `merchant_applications.payout_status`.
- Send reminder emails if payout not completed within X days.

### Database

- Columns `payout_status`, `payout_last_reminder_at` on `merchant_applications`.

### Frontend

- On Step 5 show CTA "Connect Stripe" (webview). On success, mark step complete, allow submission. If skip, log event and show "Complete payout to receive funds" banner on dashboard.

### DevOps

- Add staging/prod Stripe keys for onboarding environment; ensure redirect URIs configured; update runbooks.

### Testing

- E2E test covering connect flow + skip/resume; manual test verifying reminder email; regression test to ensure merchants without payouts cannot receive funds.

---

## Point 20 · Merchant Account Security Page Placeholder

### Product

- Document account security MVP: Change password, phone binding (for SMS recovery), enable/disable TOTP 2FA; include compliance and UX copy.

### Architecture

- AccountSecurityProvider handles fetching/updating auth metadata; flows: change password (modal), phone verification (two-step), 2FA enable (QR code + OTP), disable 2FA (confirmation).

### Backend

- Implement functions: `account/change-password` (verify old password via Supabase Admin API), `account/link-phone` (send OTP via Twilio, verify, save), `account/setup-2fa` (generate secret, return otpauth URL), `account/confirm-2fa`, `account/disable-2fa`.
- Rate limit OTP attempts; log security events.

### Database

- Table `user_security_settings(user_id PK, phone, phone_verified bool, totp_secret encrypted, two_factor_enabled bool, last_totp_verified_at)`; table `phone_verification_codes` with expiry.
- Ensure encryption at rest for secrets.

### Frontend

- Build full UI replacing placeholder: sections for Password, Phone, Two-Factor. Include forms, OTP inputs, QR code (use `qr_flutter`), toggles, success states, error messaging.
- Surface security tips, show last password change date.

### DevOps

- Configure Twilio SMS service (sandbox + prod), secrets in env; set up rate-limiting middleware; create security alerting for repeated OTP failures.

### Testing

- Backend tests for password complexity, OTP expiry, TOTP validation; front-end tests for form states; QA scenario matrix (incorrect OTP, disable 2FA, re-enable, lost device flow).