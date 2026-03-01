-- =============================================================
-- Fix circular FK: orders.coupon_id ↔ coupons.order_id
-- Problem: cannot insert order without coupon, cannot insert
--          coupon without order.
-- Solution: make orders.coupon_id nullable, auto-create coupon
--           via trigger on order insert.
-- =============================================================

-- 1. Drop the NOT NULL constraint on orders.coupon_id
alter table public.orders alter column coupon_id drop not null;

-- 2. Set default to NULL (was previously required)
alter table public.orders alter column coupon_id set default null;

-- 3. Create trigger function: auto-generate coupon after order insert
create or replace function public.auto_create_coupon()
returns trigger language plpgsql security definer as $$
declare
  new_coupon_id uuid;
  deal_row record;
begin
  -- Fetch the deal to get merchant_id and expires_at
  select merchant_id, expires_at into deal_row
    from public.deals where id = new.deal_id;

  -- Generate a coupon for this order
  insert into public.coupons (order_id, user_id, deal_id, merchant_id, qr_code, expires_at)
  values (
    new.id,
    new.user_id,
    new.deal_id,
    deal_row.merchant_id,
    encode(gen_random_bytes(32), 'hex'),  -- 64-char hex token
    deal_row.expires_at
  )
  returning id into new_coupon_id;

  -- Back-fill orders.coupon_id
  update public.orders set coupon_id = new_coupon_id where id = new.id;

  return new;
end;
$$;

create trigger on_order_created
  after insert on public.orders
  for each row execute procedure public.auto_create_coupon();
