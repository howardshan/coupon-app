# Merchant Edge Function (`merchant-after-sales`)

Run these commands with a merchant/staff Supabase access token to replicate what the DealJoy Merchant app performs.

## Prerequisites

```bash
export SUPABASE_URL="https://<project>.supabase.co"
export MERCHANT_ACCESS_TOKEN="<merchant_or_staff_token>"
```

## 1. List pending cases

```bash
curl -X GET   "$SUPABASE_URL/functions/v1/merchant-after-sales?status=pending,awaiting_platform&access_token=$MERCHANT_ACCESS_TOKEN"   -H "Authorization: Bearer $MERCHANT_ACCESS_TOKEN"
```

## 2. Fetch detail for a specific request

```bash
curl -X GET   "$SUPABASE_URL/functions/v1/merchant-after-sales/<REQUEST_ID>?access_token=$MERCHANT_ACCESS_TOKEN"   -H "Authorization: Bearer $MERCHANT_ACCESS_TOKEN"
```

## 3. Approve & refund

```bash
curl -X POST   "$SUPABASE_URL/functions/v1/merchant-after-sales/<REQUEST_ID>/approve"   -H "Authorization: Bearer $MERCHANT_ACCESS_TOKEN"   -H "Content-Type: application/json"   -d '{
    "note": "Refund approved after reviewing POS logs.",
    "attachments": [],
    "access_token": "'$MERCHANT_ACCESS_TOKEN'"
  }'
```

## 4. Reject with evidence

Request upload slots first:

```bash
curl -X POST "$SUPABASE_URL/functions/v1/merchant-after-sales/uploads"   -H "Authorization: Bearer $MERCHANT_ACCESS_TOKEN"   -H "Content-Type: application/json"   -d '{
    "files": [ { "filename": "camera-proof.png" } ],
    "access_token": "'$MERCHANT_ACCESS_TOKEN'"
  }'
```

Upload the binary file to the returned `signedUrl`, then submit the rejection referencing the `path`:

```bash
curl -X POST   "$SUPABASE_URL/functions/v1/merchant-after-sales/<REQUEST_ID>/reject"   -H "Authorization: Bearer $MERCHANT_ACCESS_TOKEN"   -H "Content-Type: application/json"   -d '{
    "note": "Camera footage shows the party redeemed successfully.",
    "attachments": ["after-sales-evidence/merchant/<...>/camera-proof.png"],
    "access_token": "'$MERCHANT_ACCESS_TOKEN'"
  }'
```

The service responds with the updated request payload, including refreshed signed URLs for attachments.
