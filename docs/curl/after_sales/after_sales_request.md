# User After-Sales Edge Function (`after-sales-request`)

Use these cURL snippets to mimic what the consumer app does when filing and reviewing an after-sales case.

## Prerequisites

```bash
export SUPABASE_URL="https://<project>.supabase.co"
export USER_ACCESS_TOKEN="<user access token>"
```

## 1. List existing requests for an order

```bash
curl -X GET   "$SUPABASE_URL/functions/v1/after-sales-request?order_id=<ORDER_ID>&access_token=$USER_ACCESS_TOKEN"   -H "Authorization: Bearer $USER_ACCESS_TOKEN"
```

## 2. Request evidence upload slots

```bash
curl -X POST "$SUPABASE_URL/functions/v1/after-sales-request/uploads"   -H "Authorization: Bearer $USER_ACCESS_TOKEN"   -H "Content-Type: application/json"   -d '{
    "files": [
      { "filename": "receipt.jpg" }
    ],
    "access_token": "'$USER_ACCESS_TOKEN'"
  }'
```

The response contains a `signedUrl`, `token`, and storage `path`. Upload the binary bytes directly:

```bash
curl -X PUT "<SIGNED_URL_FROM_STEP_2>"   -H "Authorization: Bearer <TOKEN_FROM_STEP_2>"   -H "Content-Type: image/jpeg"   --data-binary @receipt.jpg
```

## 3. File a new after-sales request

```bash
curl -X POST "$SUPABASE_URL/functions/v1/after-sales-request"   -H "Authorization: Bearer $USER_ACCESS_TOKEN"   -H "Content-Type: application/json"   -d '{
    "orderId": "<ORDER_ID>",
    "couponId": "<COUPON_ID>",
    "reasonCode": "bad_experience",
    "reasonDetail": "Server never honored the voucher.",
    "attachments": ["after-sales-evidence/user/<...>/receipt.jpg"],
    "access_token": "'$USER_ACCESS_TOKEN'"
  }'
```

## 4. Escalate an in-progress request

```bash
curl -X POST "$SUPABASE_URL/functions/v1/after-sales-request/<REQUEST_ID>/escalate"   -H "Authorization: Bearer $USER_ACCESS_TOKEN"   -H "Content-Type: application/json"   -d '{"access_token": "'$USER_ACCESS_TOKEN'"}'
```

These calls mirror the Flutter client and are safe to run against staging to seed demo data.
