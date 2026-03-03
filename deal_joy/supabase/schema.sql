-- =============================================================
-- DealJoy Supabase Schema
-- Run this in your Supabase SQL Editor (Dashboard > SQL Editor)
-- =============================================================

-- Enable extensions
create extension if not exists "uuid-ossp";
create extension if not exists "postgis"; -- for location queries (optional)

-- =============================================================
-- ENUMS
-- =============================================================
create type user_role as enum ('user', 'merchant', 'admin');
create type merchant_status as enum ('pending', 'approved', 'rejected');
create type order_status as enum ('unused', 'used', 'refunded', 'refund_requested', 'expired');
create type coupon_status as enum ('unused', 'used', 'expired', 'refunded');

-- =============================================================
-- USERS
-- Mirror of auth.users with extra profile fields
-- =============================================================
create table public.users (
  id          uuid primary key references auth.users(id) on delete cascade,
  email       text not null,
  full_name   text,
  avatar_url  text,
  phone       text,
  role        user_role not null default 'user',
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

-- Auto-create user profile on signup
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer as $$
begin
  insert into public.users (id, email, full_name, avatar_url)
  values (
    new.id,
    new.email,
    new.raw_user_meta_data->>'full_name',
    new.raw_user_meta_data->>'avatar_url'
  );
  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute procedure public.handle_new_user();

-- =============================================================
-- CATEGORIES
-- =============================================================
create table public.categories (
  id    serial primary key,
  name  text not null unique,
  icon  text,
  "order" int default 0
);

insert into public.categories (name, icon, "order") values
  ('BBQ', '🥩', 1),
  ('Hot Pot', '🍲', 2),
  ('Coffee', '☕', 3),
  ('Dessert', '🍰', 4),
  ('Massage', '💆', 5),
  ('Sushi', '🍣', 6),
  ('Pizza', '🍕', 7),
  ('Ramen', '🍜', 8),
  ('Korean', '🫕', 9);

-- =============================================================
-- MERCHANTS
-- =============================================================
create table public.merchants (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references public.users(id) on delete cascade,
  name        text not null,
  description text,
  logo_url    text,
  address     text,
  lat         double precision,
  lng         double precision,
  phone       text,
  website     text,
  status      merchant_status not null default 'pending',
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

create index idx_merchants_user_id on public.merchants(user_id);
create index idx_merchants_status  on public.merchants(status);

-- =============================================================
-- DEALS
-- =============================================================
create table public.deals (
  id               uuid primary key default gen_random_uuid(),
  merchant_id      uuid not null references public.merchants(id) on delete cascade,
  title            text not null,
  description      text not null,
  category         text not null,
  original_price   numeric(10,2) not null,
  discount_price   numeric(10,2) not null,
  discount_percent int not null generated always as
    (round((1 - discount_price / original_price) * 100)) stored,
  image_urls       text[] not null default '{}',
  stock_limit      int not null default 100,
  total_sold       int not null default 0,
  rating           numeric(3,2) not null default 0,
  review_count     int not null default 0,
  is_featured      boolean not null default false,
  is_active        boolean not null default true,
  refund_policy    text not null default 'Risk-Free Refund within 7 days',
  lat              double precision,
  lng              double precision,
  address          text,
  discount_label   text not null default '',
  dishes           jsonb not null default '[]',
  merchant_hours   text,
  expires_at       timestamptz not null,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now()
);

create index idx_deals_merchant_id  on public.deals(merchant_id);
create index idx_deals_category     on public.deals(category);
create index idx_deals_is_active    on public.deals(is_active);
create index idx_deals_is_featured  on public.deals(is_featured);
create index idx_deals_expires_at   on public.deals(expires_at);

-- =============================================================
-- ORDERS
-- =============================================================
create table public.orders (
  id                 uuid primary key default gen_random_uuid(),
  user_id            uuid not null references public.users(id),
  deal_id            uuid not null references public.deals(id),
  coupon_id          uuid, -- nullable; auto-filled by on_order_created trigger
  quantity           int not null default 1,
  unit_price         numeric(10,2) not null,
  total_amount       numeric(10,2) not null,
  status             order_status not null default 'unused',
  payment_intent_id  text not null,
  stripe_charge_id   text,
  refund_reason      text,
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now()
);

create index idx_orders_user_id  on public.orders(user_id);
create index idx_orders_deal_id  on public.orders(deal_id);
create index idx_orders_status   on public.orders(status);

-- =============================================================
-- COUPONS
-- One coupon per order (can be extended for multi-coupon orders)
-- =============================================================
create table public.coupons (
  id          uuid primary key default gen_random_uuid(),
  order_id    uuid not null references public.orders(id) on delete cascade,
  user_id     uuid not null references public.users(id),
  deal_id     uuid not null references public.deals(id),
  merchant_id uuid not null references public.merchants(id),
  qr_code     text not null unique, -- signed token for verification
  status      coupon_status not null default 'unused',
  expires_at  timestamptz not null,
  used_at     timestamptz,
  created_at  timestamptz not null default now()
);

create index idx_coupons_order_id    on public.coupons(order_id);
create index idx_coupons_user_id     on public.coupons(user_id);
create index idx_coupons_merchant_id on public.coupons(merchant_id);
create index idx_coupons_qr_code     on public.coupons(qr_code);

-- Add FK from orders to coupons
alter table public.orders
  add constraint fk_orders_coupon_id
  foreign key (coupon_id) references public.coupons(id);

-- =============================================================
-- REVIEWS
-- =============================================================
create table public.reviews (
  id          uuid primary key default gen_random_uuid(),
  deal_id     uuid not null references public.deals(id) on delete cascade,
  user_id     uuid not null references public.users(id),
  order_id    uuid references public.orders(id),
  rating      int not null check (rating between 1 and 5),
  comment     text,
  is_verified boolean not null default false, -- verified purchase
  created_at  timestamptz not null default now(),
  unique (deal_id, user_id) -- one review per user per deal
);

create index idx_reviews_deal_id on public.reviews(deal_id);

-- Auto-update deal rating on review insert/update
create or replace function update_deal_rating()
returns trigger language plpgsql as $$
begin
  update public.deals
  set
    rating = (select round(avg(rating)::numeric, 2) from public.reviews where deal_id = new.deal_id),
    review_count = (select count(*) from public.reviews where deal_id = new.deal_id)
  where id = new.deal_id;
  return new;
end;
$$;

create trigger on_review_change
  after insert or update on public.reviews
  for each row execute procedure update_deal_rating();

-- =============================================================
-- PAYMENTS
-- Audit log for Stripe transactions
-- =============================================================
create table public.payments (
  id                 uuid primary key default gen_random_uuid(),
  order_id           uuid not null references public.orders(id),
  user_id            uuid not null references public.users(id),
  amount             numeric(10,2) not null,
  currency           text not null default 'usd',
  payment_intent_id  text not null unique,
  stripe_charge_id   text,
  status             text not null, -- 'succeeded' | 'refunded' | 'failed'
  refund_amount      numeric(10,2),
  created_at         timestamptz not null default now()
);

create index idx_payments_order_id on public.payments(order_id);
create index idx_payments_user_id  on public.payments(user_id);

-- =============================================================
-- SAVED DEALS
-- =============================================================
create table public.saved_deals (
  user_id    uuid not null references public.users(id) on delete cascade,
  deal_id    uuid not null references public.deals(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (user_id, deal_id)
);

create index idx_saved_deals_user_id on public.saved_deals(user_id);

-- =============================================================
-- ROW LEVEL SECURITY (RLS)
-- =============================================================
alter table public.users       enable row level security;
alter table public.merchants   enable row level security;
alter table public.deals       enable row level security;
alter table public.orders      enable row level security;
alter table public.coupons     enable row level security;
alter table public.reviews     enable row level security;
alter table public.payments    enable row level security;
alter table public.saved_deals enable row level security;

-- Users: can read/update own profile
create policy "users_select_own" on public.users
  for select using (auth.uid() = id);
create policy "users_update_own" on public.users
  for update using (auth.uid() = id);

-- Deals: anyone can read active deals
create policy "deals_read_active" on public.deals
  for select using (is_active = true);
-- Merchants can manage their own deals
create policy "deals_merchant_manage" on public.deals
  for all using (
    merchant_id in (
      select id from public.merchants where user_id = auth.uid()
    )
  );

-- Orders: users see own orders only
create policy "orders_select_own" on public.orders
  for select using (auth.uid() = user_id);
create policy "orders_insert_own" on public.orders
  for insert with check (auth.uid() = user_id);

-- Coupons: users see own coupons; merchants see coupons for their deals
create policy "coupons_select_own" on public.coupons
  for select using (auth.uid() = user_id);
create policy "coupons_merchant_scan" on public.coupons
  for update using (
    merchant_id in (
      select id from public.merchants where user_id = auth.uid()
    )
  );

-- Reviews: anyone can read; authenticated users insert own
create policy "reviews_read_all" on public.reviews
  for select using (true);
create policy "reviews_insert_own" on public.reviews
  for insert with check (auth.uid() = user_id);

-- Saved deals: own only
create policy "saved_deals_own" on public.saved_deals
  for all using (auth.uid() = user_id);

-- Merchants: approved merchants visible to all
create policy "merchants_read_approved" on public.merchants
  for select using (status = 'approved');
create policy "merchants_manage_own" on public.merchants
  for all using (auth.uid() = user_id);

-- Categories: public read
alter table public.categories enable row level security;
create policy "categories_read_all" on public.categories
  for select using (true);

-- =============================================================
-- AUTO-CREATE COUPON ON ORDER INSERT
-- Removes the circular dependency: order no longer needs
-- coupon_id at insert time — it is back-filled by this trigger.
-- =============================================================
create or replace function public.auto_create_coupon()
returns trigger language plpgsql security definer as $$
declare
  new_coupon_id uuid;
  deal_row record;
begin
  select merchant_id, expires_at into deal_row
    from public.deals where id = new.deal_id;

  insert into public.coupons (order_id, user_id, deal_id, merchant_id, qr_code, expires_at)
  values (
    new.id, new.user_id, new.deal_id, deal_row.merchant_id,
    encode(gen_random_bytes(32), 'hex'),
    deal_row.expires_at
  )
  returning id into new_coupon_id;

  update public.orders set coupon_id = new_coupon_id where id = new.id;
  return new;
end;
$$;

create trigger on_order_created
  after insert on public.orders
  for each row execute procedure public.auto_create_coupon();
