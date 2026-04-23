# Post-redemption tip — `create-tip-payment-intent`

Edge: `POST /functions/v1/create-tip-payment-intent`  
Auth: `Authorization: Bearer <merchant_access_token>` + `X-Merchant-Id: <merchant_uuid>` (same as other merchant functions).  
Body (JSON):

```json
{
  "coupon_id": "<uuid>",
  "amount_cents": 500,
  "preset_choice": "custom",
  "signature_png_base64": "<optional base64 or data URL>"
}
```

Example (replace placeholders):

```bash
curl -sS -X POST "$SUPABASE_URL/functions/v1/create-tip-payment-intent" \
  -H "Authorization: Bearer $MERCHANT_JWT" \
  -H "X-Merchant-Id: $MERCHANT_ID" \
  -H "apikey: $SUPABASE_ANON_KEY" \
  -H "Content-Type: application/json" \
  -d "{\"coupon_id\":\"$COUPON_ID\",\"amount_cents\":500,\"preset_choice\":\"p2\"}"
```

Notes:

- Amount must pass server validation against the deal’s `tips_mode` / presets and the coupon’s tip base (`order_items.unit_price` snapshot).
- `trainee` role is rejected.
- After PI succeeds, `stripe-webhook` updates `coupon_tips` to `paid`.
