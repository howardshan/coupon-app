# After-Sales (Post-Verification Refund) Build Report

_Last updated: 2026-03-17_

## Summary

- **Edge Functions & Shared Helpers**
  - `after-sales-request`, `merchant-after-sales`, and `platform-after-sales` now write attachment storage keys, hydrate responses with fresh signed URLs, and emit structured rows into `after_sales_events` for every status change.
  - Shared utilities in `supabase/functions/_shared/after-sales.ts` normalize upload slots, decorate responses with signed evidence links, and encapsulate refund issuance.
- **User App (deal_joy)**
  - Riverpod-backed `after_sales` module is live: order detail screen launches the timeline, and users can submit requests with signed evidence uploads plus escalation.
- **Merchant App (dealjoy_merchant)**
  - Added a dedicated “After-Sales” view inside the Orders module (`AfterSalesListPage`) with status tabs, masked customer names, countdown SLA chips, and pagination driven by the new repository/provider stack.
  - Detail experience (`AfterSalesDetailPage`) shows reason, attachments, timeline, and approve/reject actions. Reject flows request signed upload URLs and attach merchant evidence before calling `merchant-after-sales`.
  - State management now lives under `lib/features/after_sales/providers`, backed by `MerchantAfterSalesRepository` (HTTP signed uploads + Supabase functions).
- **Admin Console (Next.js)**
  - New route `/after-sales` (under the dashboard layout) renders a server-fetched table of escalated cases with store, masked user, status, submission time, and SLA countdown.
  - Clicking a row opens a drawer with full timeline, attachments, and approve/reject controls. Client-side actions call the new API routes under `app/api/platform-after-sales/*`, which proxy to the Edge Function using the service-role key server-side only.
- **Tests, Docs & Tooling**
  - Widget test skeletons now live at `deal_joy/test/after_sales_test.dart` and `dealjoy_merchant/test/after_sales_test.dart` to guard the primary UI states.
  - Added cURL playbooks for every actor: `docs/curl/after_sales/after_sales_request.md`, `merchant.md`, and `platform.md`.
  - Build report now carries a manual QA script and sample data guidance so ops can rehearse the flow without additional tooling.

## Deployment / Verification

1. **Supabase Edge Functions**
   ```bash
   cd deal_joy/supabase/functions
   supabase functions deploy after-sales-request merchant-after-sales platform-after-sales
   ```
2. **Flutter apps**
   ```bash
   # User
   cd deal_joy && flutter pub get && flutter build apk

   # Merchant
   cd ../dealjoy_merchant && flutter pub get && flutter build apk
   ```
3. **Admin console**
   ```bash
   cd ../admin
   npm install
   npm run build && npm start
   # or `npm run dev` for local verification (requires NEXT_PUBLIC_SUPABASE_URL / ANON + SUPABASE_SERVICE_ROLE_KEY)
   ```

## Manual QA Script

1. **Seed data** – Use the steps in `docs/curl/after_sales/after_sales_request.md` to submit a user request that includes at least one attachment.
2. **Merchant review** – In the merchant app, open Orders ▸ tap the headset icon ▸ verify the new case appears under “Action Required” with countdown badge and masked user name. Open the detail view, upload a dummy image while rejecting, then refresh to ensure status moves to “Closed”.
3. **Platform arbitration** – Re-run the user cURL (or merchant UI) to escalate another request to `awaiting_platform`. In the admin console `/after-sales`, filter by “Awaiting Platform”, open the drawer, and approve the request. Confirm the status badge flips to “Refunded” and that the action API route responds with the updated timeline.
4. **Edge verification** – Use the merchant/admin cURL snippets to spot-check that evidence uploads continue working outside the UI (each call now returns hydrated signed URLs).

## Sample Data / Seeding Tips

- User, merchant, and platform examples under `docs/curl/after_sales/` are copy/paste-ready. Running through those three files is the fastest way to seed realistic after-sales data in any environment.
- For demo purposes: submit a user claim, reject it as the merchant with evidence, then escalate via the user script so the admin drawer has a live timeline to review.

## Tests & Observability

- Flutter widget tests:
  - `deal_joy/test/after_sales_test.dart` validates that the consumer timeline shows the empty state and renders timeline entries when provided by the provider override.
  - `dealjoy_merchant/test/after_sales_test.dart` locks in the list empty state and ensures pending requests render with status pills.
- Documentation-driven API tests live in `docs/curl/after_sales/*.md` and double as smoke scripts for CI or ops checklists.

## Known Gaps

- _None_. The merchant UI, admin console, docs, and tests required for hand-off are all merged; any net-new scope should enter the next sprint as a separate story.
