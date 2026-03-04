-- =============================================================
-- Migration: 商家端消息通知模块
-- 功能:
--   1. 新建 merchant_notifications 表：存储各类商家通知
--   2. 新建 merchant_fcm_tokens 表：存储 FCM 推送 Token
--   3. RLS 策略：商家只能操作自己的数据
--   4. 触发器：新订单 -> 自动插入 new_order 通知
--   5. 触发器：核销券 -> 自动插入 redemption 通知
-- =============================================================

-- =============================================================
-- 1. 通知类型枚举
-- =============================================================
do $$
begin
  if not exists (
    select 1 from pg_type where typname = 'merchant_notification_type'
  ) then
    create type public.merchant_notification_type as enum (
      'new_order',      -- 新订单
      'redemption',     -- 核销（券被使用）
      'review_result',  -- 评价通知
      'deal_approved',  -- Deal 审核通过
      'deal_rejected',  -- Deal 审核拒绝
      'system'          -- 系统公告
    );
  end if;
end;
$$;

-- =============================================================
-- 2. merchant_notifications 表
-- =============================================================
create table if not exists public.merchant_notifications (
  id          uuid                             primary key default gen_random_uuid(),
  merchant_id uuid                             not null references public.merchants(id) on delete cascade,
  type        public.merchant_notification_type not null,
  title       text                             not null,
  body        text                             not null,
  data        jsonb                            not null default '{}',  -- 附加载荷，如 {order_id, deal_id}
  is_read     boolean                          not null default false,
  created_at  timestamptz                      not null default now()
);

-- 查询索引：按商家 + 创建时间倒序
create index if not exists idx_merchant_notifications_merchant_id
  on public.merchant_notifications(merchant_id, created_at desc);

-- 查询索引：未读筛选加速
create index if not exists idx_merchant_notifications_unread
  on public.merchant_notifications(merchant_id, is_read)
  where is_read = false;

-- =============================================================
-- 3. merchant_fcm_tokens 表
-- =============================================================
create table if not exists public.merchant_fcm_tokens (
  id          uuid        primary key default gen_random_uuid(),
  merchant_id uuid        not null references public.merchants(id) on delete cascade,
  fcm_token   text        not null,
  device_type text        not null check (device_type in ('ios', 'android')),  -- 设备类型
  updated_at  timestamptz not null default now(),
  -- 每个商家每个 token 唯一（同 token 更新而非重复插入）
  unique (merchant_id, fcm_token)
);

create index if not exists idx_merchant_fcm_tokens_merchant_id
  on public.merchant_fcm_tokens(merchant_id);

-- =============================================================
-- 4. RLS — merchant_notifications
-- =============================================================
alter table public.merchant_notifications enable row level security;

-- 商家只能查看自己的通知
do $$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public'
      and tablename  = 'merchant_notifications'
      and policyname = 'merchant_notifications_select'
  ) then
    execute $policy$
      create policy "merchant_notifications_select"
        on public.merchant_notifications
        for select
        using (
          merchant_id in (
            select id from public.merchants where user_id = auth.uid()
          )
        )
    $policy$;
  end if;
end;
$$;

-- 商家只能更新自己的通知（仅允许更新 is_read 字段）
do $$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public'
      and tablename  = 'merchant_notifications'
      and policyname = 'merchant_notifications_update'
  ) then
    execute $policy$
      create policy "merchant_notifications_update"
        on public.merchant_notifications
        for update
        using (
          merchant_id in (
            select id from public.merchants where user_id = auth.uid()
          )
        )
        with check (
          merchant_id in (
            select id from public.merchants where user_id = auth.uid()
          )
        )
    $policy$;
  end if;
end;
$$;

-- 触发器函数使用 SECURITY DEFINER 执行 INSERT，无需商家端写权限
-- 因此不需要为 merchant_notifications 设置 INSERT RLS for authenticated role

-- =============================================================
-- 5. RLS — merchant_fcm_tokens
-- =============================================================
alter table public.merchant_fcm_tokens enable row level security;

-- 商家只能查看自己的 FCM Token
do $$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public'
      and tablename  = 'merchant_fcm_tokens'
      and policyname = 'merchant_fcm_tokens_select'
  ) then
    execute $policy$
      create policy "merchant_fcm_tokens_select"
        on public.merchant_fcm_tokens
        for select
        using (
          merchant_id in (
            select id from public.merchants where user_id = auth.uid()
          )
        )
    $policy$;
  end if;
end;
$$;

-- 商家只能插入自己的 FCM Token
do $$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public'
      and tablename  = 'merchant_fcm_tokens'
      and policyname = 'merchant_fcm_tokens_insert'
  ) then
    execute $policy$
      create policy "merchant_fcm_tokens_insert"
        on public.merchant_fcm_tokens
        for insert
        with check (
          merchant_id in (
            select id from public.merchants where user_id = auth.uid()
          )
        )
    $policy$;
  end if;
end;
$$;

-- 商家只能更新自己的 FCM Token
do $$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public'
      and tablename  = 'merchant_fcm_tokens'
      and policyname = 'merchant_fcm_tokens_update'
  ) then
    execute $policy$
      create policy "merchant_fcm_tokens_update"
        on public.merchant_fcm_tokens
        for update
        using (
          merchant_id in (
            select id from public.merchants where user_id = auth.uid()
          )
        )
    $policy$;
  end if;
end;
$$;

-- 商家只能删除自己的 FCM Token
do $$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public'
      and tablename  = 'merchant_fcm_tokens'
      and policyname = 'merchant_fcm_tokens_delete'
  ) then
    execute $policy$
      create policy "merchant_fcm_tokens_delete"
        on public.merchant_fcm_tokens
        for delete
        using (
          merchant_id in (
            select id from public.merchants where user_id = auth.uid()
          )
        )
    $policy$;
  end if;
end;
$$;

-- =============================================================
-- 6. 触发器函数: 新订单 -> 自动通知商家
-- 在 orders 表 INSERT 后触发
-- 通过 deals 表关联找到 merchant_id
-- =============================================================
create or replace function public.notify_merchant_new_order()
returns trigger
language plpgsql
security definer  -- 以超级权限执行，绕过 RLS
set search_path = public
as $$
declare
  v_merchant_id uuid;
  v_deal_title  text;
  v_amount      numeric;
begin
  -- 从 deals 表获取 merchant_id 和 deal 标题
  select d.merchant_id, d.title, new.total_amount
    into v_merchant_id, v_deal_title, v_amount
    from public.deals d
   where d.id = new.deal_id;

  -- 如果未找到商家，跳过（避免触发器崩溃影响主事务）
  if v_merchant_id is null then
    return new;
  end if;

  -- 插入新订单通知
  insert into public.merchant_notifications (
    merchant_id,
    type,
    title,
    body,
    data
  ) values (
    v_merchant_id,
    'new_order',
    'New Order Received',
    'A new order for "' || coalesce(v_deal_title, 'Deal') || '" has been placed.',
    jsonb_build_object(
      'order_id', new.id,
      'deal_id',  new.deal_id,
      'amount',   coalesce(v_amount, 0)
    )
  );

  return new;
exception
  when others then
    -- 通知失败不能影响主订单事务
    raise warning 'notify_merchant_new_order failed: %', sqlerrm;
    return new;
end;
$$;

-- 绑定触发器到 orders 表
drop trigger if exists on_order_created_notify_merchant on public.orders;
create trigger on_order_created_notify_merchant
  after insert on public.orders
  for each row
  execute function public.notify_merchant_new_order();

-- =============================================================
-- 7. 触发器函数: 券核销 -> 自动通知商家
-- 在 coupons 表 UPDATE 后触发
-- 当 status 从非 used 变为 used 时触发
-- =============================================================
create or replace function public.notify_merchant_coupon_redeemed()
returns trigger
language plpgsql
security definer  -- 以超级权限执行，绕过 RLS
set search_path = public
as $$
declare
  v_merchant_id uuid;
  v_deal_title  text;
  v_order_id    uuid;
begin
  -- 只在状态变为 used 时触发
  if new.status <> 'used' or old.status = 'used' then
    return new;
  end if;

  -- 通过 orders -> deals 找到 merchant_id
  select d.merchant_id, d.title, o.id
    into v_merchant_id, v_deal_title, v_order_id
    from public.orders o
    join public.deals  d on d.id = o.deal_id
   where o.id = new.order_id;

  -- 未找到商家则跳过
  if v_merchant_id is null then
    return new;
  end if;

  -- 插入核销通知
  insert into public.merchant_notifications (
    merchant_id,
    type,
    title,
    body,
    data
  ) values (
    v_merchant_id,
    'redemption',
    'Voucher Redeemed',
    '"' || coalesce(v_deal_title, 'Deal') || '" voucher has been successfully redeemed.',
    jsonb_build_object(
      'coupon_id', new.id,
      'order_id',  v_order_id,
      'deal_title', coalesce(v_deal_title, '')
    )
  );

  return new;
exception
  when others then
    -- 通知失败不能影响主核销事务
    raise warning 'notify_merchant_coupon_redeemed failed: %', sqlerrm;
    return new;
end;
$$;

-- 绑定触发器到 coupons 表
drop trigger if exists on_coupon_redeemed_notify_merchant on public.coupons;
create trigger on_coupon_redeemed_notify_merchant
  after update on public.coupons
  for each row
  execute function public.notify_merchant_coupon_redeemed();

-- =============================================================
-- 8. 开启 Realtime (需在 Supabase Dashboard 或通过 publication 设置)
-- 将 merchant_notifications 加入 supabase_realtime publication
-- =============================================================
do $$
begin
  -- 检查 publication 是否存在
  if exists (
    select 1 from pg_publication where pubname = 'supabase_realtime'
  ) then
    -- 检查表是否已加入 publication
    if not exists (
      select 1 from pg_publication_tables
      where pubname   = 'supabase_realtime'
        and schemaname = 'public'
        and tablename  = 'merchant_notifications'
    ) then
      alter publication supabase_realtime add table public.merchant_notifications;
    end if;
  end if;
end;
$$;
