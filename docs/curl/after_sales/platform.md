# Platform Edge Function (`platform-after-sales`)

Use an admin access token (DealJoy ops team account) to call these endpoints.

## Prerequisites

```bash
export SUPABASE_URL="https://<project>.supabase.co"
export ADMIN_ACCESS_TOKEN="<admin_token>"
```

## 1. List escalated cases

```bash
curl -X GET   "$SUPABASE_URL/functions/v1/platform-after-sales?status=awaiting_platform&access_token=$ADMIN_ACCESS_TOKEN"   -H "Authorization: Bearer $ADMIN_ACCESS_TOKEN"
```

## 2. Fetch request detail + timeline

```bash
curl -X GET   "$SUPABASE_URL/functions/v1/platform-after-sales/<REQUEST_ID>?access_token=$ADMIN_ACCESS_TOKEN"   -H "Authorization: Bearer $ADMIN_ACCESS_TOKEN"
```

## 3. Approve (issue refund)

```bash
curl -X POST   "$SUPABASE_URL/functions/v1/platform-after-sales/<REQUEST_ID>/approve"   -H "Authorization: Bearer $ADMIN_ACCESS_TOKEN"   -H "Content-Type: application/json"   -d '{
    "note": "Approved after desk review.",
    "attachments": [],
    "access_token": "'$ADMIN_ACCESS_TOKEN'"
  }'
```

## 4. Reject with new evidence

Request signed upload URLs:

```bash
curl -X POST "$SUPABASE_URL/functions/v1/platform-after-sales/uploads"   -H "Authorization: Bearer $ADMIN_ACCESS_TOKEN"   -H "Content-Type: application/json"   -d '{
    "files": [ { "filename": "audit-log.pdf" } ],
    "access_token": "'$ADMIN_ACCESS_TOKEN'"
  }'
```

Upload `audit-log.pdf` to the `signedUrl`, then use the returned `path` when rejecting:

```bash
curl -X POST   "$SUPABASE_URL/functions/v1/platform-after-sales/<REQUEST_ID>/reject"   -H "Authorization: Bearer $ADMIN_ACCESS_TOKEN"   -H "Content-Type: application/json"   -d '{
    "note": "Logs confirm the merchant fulfilled obligations.",
    "attachments": ["after-sales-evidence/platform/<...>/audit-log.pdf"],
    "access_token": "'$ADMIN_ACCESS_TOKEN'"
  }'
```

Every response mirrors what the Next.js admin console consumes, making these commands ideal for smoke tests or seeding demo data.
