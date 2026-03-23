-- 用户多地址管理：billing_addresses 表
create table if not exists public.billing_addresses (
  id            uuid primary key default gen_random_uuid(),
  user_id       uuid not null references public.users(id) on delete cascade,
  label         text not null default '',           -- 用户自定义标签，如 "Home", "Office"
  address_line1 text not null default '',
  address_line2 text not null default '',
  city          text not null default '',
  state         text not null default '',
  postal_code   text not null default '',
  country       text not null default 'US',
  is_default    boolean not null default false,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);

-- 索引：按用户查询
create index if not exists idx_billing_addresses_user_id on public.billing_addresses(user_id);

-- 确保每个用户只有一个 default 地址（部分唯一索引）
create unique index if not exists idx_billing_addresses_user_default
  on public.billing_addresses(user_id) where is_default = true;

-- RLS 策略
alter table public.billing_addresses enable row level security;

-- 用户只能看到自己的地址
create policy "Users can view own billing addresses"
  on public.billing_addresses for select
  using (auth.uid() = user_id);

-- 用户可以插入自己的地址
create policy "Users can insert own billing addresses"
  on public.billing_addresses for insert
  with check (auth.uid() = user_id);

-- 用户可以更新自己的地址
create policy "Users can update own billing addresses"
  on public.billing_addresses for update
  using (auth.uid() = user_id);

-- 用户可以删除自己的地址
create policy "Users can delete own billing addresses"
  on public.billing_addresses for delete
  using (auth.uid() = user_id);
