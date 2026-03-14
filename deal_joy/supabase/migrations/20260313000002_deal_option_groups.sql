-- =============================================================
-- Deal 选项组 & 选项项（"几选几"功能）
-- =============================================================

-- 选项组表
create table if not exists public.deal_option_groups (
  id          uuid primary key default gen_random_uuid(),
  deal_id     uuid not null references public.deals(id) on delete cascade,
  name        text not null,                -- 组名，如 "Main Course"
  select_min  int not null default 1,       -- 最少选几个
  select_max  int not null default 1,       -- 最多选几个
  sort_order  int not null default 0,
  created_at  timestamptz not null default now()
);

create index idx_deal_option_groups_deal_id on public.deal_option_groups(deal_id);

-- 选项项表
create table if not exists public.deal_option_items (
  id        uuid primary key default gen_random_uuid(),
  group_id  uuid not null references public.deal_option_groups(id) on delete cascade,
  name      text not null,                  -- 项名，如 "Grilled Salmon"
  price     numeric(10,2) not null default 0, -- 该项单价（用于计算原价）
  sort_order int not null default 0,
  created_at timestamptz not null default now()
);

create index idx_deal_option_items_group_id on public.deal_option_items(group_id);

-- orders 表新增 selected_options jsonb 列，存储下单时的选项快照
alter table public.orders
  add column if not exists selected_options jsonb;

-- RLS 策略：选项组/选项项对所有人可读
alter table public.deal_option_groups enable row level security;
alter table public.deal_option_items enable row level security;

-- 所有人可读
create policy "deal_option_groups_select" on public.deal_option_groups
  for select using (true);

create policy "deal_option_items_select" on public.deal_option_items
  for select using (true);

-- 商家可管理自己 deal 的选项组
create policy "deal_option_groups_insert" on public.deal_option_groups
  for insert with check (
    exists (
      select 1 from public.deals d
      join public.merchant_staff ms on ms.merchant_id = d.merchant_id
      where d.id = deal_id and ms.user_id = auth.uid()
    )
  );

create policy "deal_option_groups_update" on public.deal_option_groups
  for update using (
    exists (
      select 1 from public.deals d
      join public.merchant_staff ms on ms.merchant_id = d.merchant_id
      where d.id = deal_id and ms.user_id = auth.uid()
    )
  );

create policy "deal_option_groups_delete" on public.deal_option_groups
  for delete using (
    exists (
      select 1 from public.deals d
      join public.merchant_staff ms on ms.merchant_id = d.merchant_id
      where d.id = deal_id and ms.user_id = auth.uid()
    )
  );

-- 商家可管理选项项（通过 group → deal → merchant_staff 链路）
create policy "deal_option_items_insert" on public.deal_option_items
  for insert with check (
    exists (
      select 1 from public.deal_option_groups g
      join public.deals d on d.id = g.deal_id
      join public.merchant_staff ms on ms.merchant_id = d.merchant_id
      where g.id = group_id and ms.user_id = auth.uid()
    )
  );

create policy "deal_option_items_update" on public.deal_option_items
  for update using (
    exists (
      select 1 from public.deal_option_groups g
      join public.deals d on d.id = g.deal_id
      join public.merchant_staff ms on ms.merchant_id = d.merchant_id
      where g.id = group_id and ms.user_id = auth.uid()
    )
  );

create policy "deal_option_items_delete" on public.deal_option_items
  for delete using (
    exists (
      select 1 from public.deal_option_groups g
      join public.deals d on d.id = g.deal_id
      join public.merchant_staff ms on ms.merchant_id = d.merchant_id
      where g.id = group_id and ms.user_id = auth.uid()
    )
  );
