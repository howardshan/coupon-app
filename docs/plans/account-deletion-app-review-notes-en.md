# App Review Notes — Account Deletion (English)

Use this text in **App Review Information → Notes** for both **Crunchy Plum (customer)** and **Crunchy Plum Merchant**, adjusted per app.

## Customer app

- **Where to find it**: Profile tab → scroll to **Delete account** (destructive action, red outline). User must confirm in a dialog.
- **What it does**: Calls our backend (`account-delete` Edge Function with `scope: full`). Deletes the Supabase Auth user and anonymizes or reassigns personal data per our privacy policy; unused vouchers are marked for refund through the same pipeline as store closure. Stripe Customer / saved cards are detached or removed server-side where applicable.
- **Merchant linkage**: Copy explains that the **same email** cannot access the merchant app after a full deletion if they shared one account.
- **Demo**: Provide a disposable test account; after deletion the account cannot sign in again.

## Merchant app

- **Where to find it**: Settings → **Privacy** → **Delete account**.
- **Two options**:  
  - **B — Merchant only**: Removes merchant roles (staff / brand admin / store owner). Store owners get the same close-store orchestration as **Close Store** before unlinking; the user **keeps** customer-app login.  
  - **A — Entire account**: Same backend path as the customer app’s full deletion (`scope: full`).
- **Stripe Connect**: We do **not** disconnect the user’s Stripe Connect account in-app; they can still use Stripe’s own dashboards. We only remove in-app merchant binding and consumer data per policy.

## Screen recording checklist (both apps)

1. Log in with a test account.  
2. Navigate to the delete entry above.  
3. Show the explanation and confirmation.  
4. Complete deletion and land on the login screen (or equivalent).  

---

**End of document**
