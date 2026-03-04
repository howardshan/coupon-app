-- =============================================================
-- Migration: 商家财务与结算模块
-- 新增: settlements 表 + earnings DB 函数 + RLS 策略
-- 扩展: merchants 表新增 stripe_account_id 字段
-- =============================================================

-- =============================================================
-- 1. 扩展 merchants 表：添加 Stripe Connect 账户字段
-- =============================================================
alter table public.merchants
  add column if not exists stripe_account_id text,
  add column if not exists stripe_account_email text,
  add column if not exists stripe_account_status text default 'not_connected';
  -- stripe_account_status: 'not_connected' | 'connected' | 'restricted'

-- =============================================================
-- 2. 新建 settlements 结算记录表
-- 每条记录代表一批已完成的结算打款
-- =============================================================
create table if not exists public.settlements (
  id            uuid primary key default gen_random_uuid(),
  merchant_id   uuid not null references public.merchants(id) on delete cascade,
  period_start  date not null,
  period_end    date not null,
  gross_amount  numeric(10,2) not null default 0,    -- 原始交易金额总计
  platform_fee  numeric(10,2) not null default 0,    -- 平台手续费(15%)
  net_amount    numeric(10,2) not null default 0,    -- 商家实收(85%)
  order_count   int not null default 0,               -- 结算订单数
  status        text not null default 'pending',      -- 'pending' | 'paid'
  paid_at       timestamptz,                          -- 实际打款时间
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  constraint settlements_status_check check (status in ('pending', 'paid'))
);

create index if not exists idx_settlements_merchant_id on public.settlements(merchant_id);
create index if not exists idx_settlements_status       on public.settlements(status);
create index if not exists idx_settlements_period       on public.settlements(period_start, period_end);

-- =============================================================
-- 3. settlements 表 RLS
-- =============================================================
alter table public.settlements enable row level security;

-- 商家只能查看自己的结算记录
create policy "settlements_select_own" on public.settlements
  for select using (
    merchant_id in (
      select id from public.merchants where user_id = auth.uid()
    )
  );

-- 仅允许系统（service_role）写入结算记录，商家不可自行修改
create policy "settlements_insert_service" on public.settlements
  for insert with check (false);  -- 由 Edge Function 以 service_role 写入

create policy "settlements_update_service" on public.settlements
  for update using (false);  -- 由 Edge Function 以 service_role 更新

-- =============================================================
-- 4. DB 函数: get_merchant_earnings_summary
-- 返回指定商家在指定月份的收入概览
-- 参数:
--   p_merchant_id uuid   — 商家 ID
--   p_month_start date   — 月份起始日（如 2026-03-01）
-- 返回:
--   total_revenue        — 本月所有非退款订单金额
--   pending_settlement   — 待结算金额（商家实收 85%）
--   settled_amount       — 已结算金额（settlements.net_amount 合计）
--   refunded_amount      — 退款金额
-- =============================================================
create or replace function public.get_merchant_earnings_summary(
  p_merchant_id uuid,
  p_month_start date
)
returns table(
  total_revenue      numeric,
  pending_settlement numeric,
  settled_amount     numeric,
  refunded_amount    numeric
)
language plpgsql
security definer
as $$
declare
  v_month_end date;
  v_settlement_cutoff timestamptz;
begin
  -- 验证调用者是该商家的 owner（安全校验）
  if not exists (
    select 1 from public.merchants
    where id = p_merchant_id and user_id = auth.uid()
  ) then
    raise exception 'access_denied' using hint = 'You do not own this merchant account';
  end if;

  -- 计算月末
  v_month_end := (p_month_start + interval '1 month - 1 day')::date;

  -- 待结算截止时间：7天前（T+7 已到期的不算 pending，应已在 settlements 中）
  v_settlement_cutoff := now() - interval '7 days';

  return query
  select
    -- 本月总收入（非退款订单）
    coalesce(sum(
      case
        when o.status in ('unused', 'used') and date(o.created_at) between p_month_start and v_month_end
        then o.total_amount
        else 0
      end
    ), 0)::numeric as total_revenue,

    -- 待结算：已核销(coupon used)但核销时间不足7天的订单，商家实收部分
    coalesce(sum(
      case
        when o.status = 'used'
          and c.used_at is not null
          and c.used_at > v_settlement_cutoff
          and not exists (
            select 1 from public.settlements s
            where s.merchant_id = p_merchant_id
              and s.status = 'paid'
              and o.created_at::date between s.period_start and s.period_end
          )
        then (o.total_amount * 0.85)
        else 0
      end
    ), 0)::numeric as pending_settlement,

    -- 已结算：settlements 表中 paid 状态的 net_amount
    coalesce((
      select sum(s.net_amount)
      from public.settlements s
      where s.merchant_id = p_merchant_id
        and s.status = 'paid'
        and s.period_start >= p_month_start
        and s.period_end <= v_month_end
    ), 0)::numeric as settled_amount,

    -- 退款金额（本月内发生退款的订单）
    coalesce(sum(
      case
        when o.status = 'refunded' and date(o.updated_at) between p_month_start and v_month_end
        then o.total_amount
        else 0
      end
    ), 0)::numeric as refunded_amount

  from public.orders o
  join public.deals d on d.id = o.deal_id
  left join public.coupons c on c.order_id = o.id
  where d.merchant_id = p_merchant_id;
end;
$$;

-- =============================================================
-- 5. DB 函数: get_merchant_transactions
-- 返回指定商家的交易列表（分页）
-- 参数:
--   p_merchant_id uuid  — 商家 ID
--   p_date_from   date  — 筛选起始日（含，nullable）
--   p_date_to     date  — 筛选结束日（含，nullable）
--   p_page        int   — 页码，从 1 开始
--   p_per_page    int   — 每页条数（默认 20）
-- 返回列: order_id, amount, platform_fee, net_amount, status, created_at, total_count
-- =============================================================
create or replace function public.get_merchant_transactions(
  p_merchant_id uuid,
  p_date_from   date    default null,
  p_date_to     date    default null,
  p_page        int     default 1,
  p_per_page    int     default 20
)
returns table(
  order_id     uuid,
  amount       numeric,
  platform_fee numeric,
  net_amount   numeric,
  status       text,
  created_at   timestamptz,
  total_count  bigint
)
language plpgsql
security definer
as $$
begin
  -- 验证调用者是该商家的 owner
  if not exists (
    select 1 from public.merchants
    where id = p_merchant_id and user_id = auth.uid()
  ) then
    raise exception 'access_denied' using hint = 'You do not own this merchant account';
  end if;

  return query
  select
    o.id                                    as order_id,
    o.total_amount                          as amount,
    round(o.total_amount * 0.15, 2)        as platform_fee,
    round(o.total_amount * 0.85, 2)        as net_amount,
    o.status::text                          as status,
    o.created_at                            as created_at,
    count(*) over ()                        as total_count
  from public.orders o
  join public.deals d on d.id = o.deal_id
  where d.merchant_id = p_merchant_id
    and (p_date_from is null or date(o.created_at) >= p_date_from)
    and (p_date_to   is null or date(o.created_at) <= p_date_to)
  order by o.created_at desc
  limit p_per_page
  offset (p_page - 1) * p_per_page;
end;
$$;

-- =============================================================
-- 6. DB 函数: get_merchant_report_data
-- 用于对账报表（P2），按天聚合数据
-- 参数:
--   p_merchant_id uuid  — 商家 ID
--   p_date_from   date  — 报表起始日
--   p_date_to     date  — 报表结束日
-- =============================================================
create or replace function public.get_merchant_report_data(
  p_merchant_id uuid,
  p_date_from   date,
  p_date_to     date
)
returns table(
  report_date   date,
  order_count   bigint,
  gross_amount  numeric,
  platform_fee  numeric,
  net_amount    numeric
)
language plpgsql
security definer
as $$
begin
  -- 验证调用者是该商家的 owner
  if not exists (
    select 1 from public.merchants
    where id = p_merchant_id and user_id = auth.uid()
  ) then
    raise exception 'access_denied' using hint = 'You do not own this merchant account';
  end if;

  return query
  select
    date(o.created_at)                               as report_date,
    count(*)                                         as order_count,
    coalesce(sum(o.total_amount), 0)                 as gross_amount,
    coalesce(round(sum(o.total_amount) * 0.15, 2), 0) as platform_fee,
    coalesce(round(sum(o.total_amount) * 0.85, 2), 0) as net_amount
  from public.orders o
  join public.deals d on d.id = o.deal_id
  where d.merchant_id = p_merchant_id
    and o.status not in ('refunded')
    and date(o.created_at) between p_date_from and p_date_to
  group by date(o.created_at)
  order by date(o.created_at) asc;
end;
$$;

-- =============================================================
-- 7. 为 orders 表添加商家视角 RLS（若尚未存在）
-- 商家可查看自己旗下 deals 的所有订单
-- =============================================================
do $$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public'
      and tablename = 'orders'
      and policyname = 'orders_merchant_view'
  ) then
    execute $policy$
      create policy "orders_merchant_view" on public.orders
        for select using (
          deal_id in (
            select d.id from public.deals d
            join public.merchants m on m.id = d.merchant_id
            where m.user_id = auth.uid()
          )
        )
    $policy$;
  end if;
end;
$$;
