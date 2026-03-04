-- =============================================================
-- Migration: 商家端数据分析模块
-- 功能:
--   1. 新建 deal_views 表：记录 Deal 浏览行为
--   2. 创建函数 get_merchant_overview：经营概览指标
--   3. 创建函数 get_deal_funnel：Deal 转化漏斗
--   4. 创建函数 get_customer_analysis：客群新老分析
--   5. RLS 策略
-- =============================================================

-- =============================================================
-- 1. 新建 deal_views 表
-- 用于记录用户端浏览 Deal 详情的行为
-- 用户端在 DealDetailScreen 打开时执行 INSERT
-- =============================================================
create table if not exists public.deal_views (
  id             uuid        primary key default gen_random_uuid(),
  deal_id        uuid        not null references public.deals(id) on delete cascade,
  merchant_id    uuid        not null references public.merchants(id) on delete cascade,
  viewer_user_id uuid        references public.users(id) on delete set null,  -- 匿名浏览时为 null
  viewed_at      timestamptz not null default now()
);

-- 常用查询索引
create index if not exists idx_deal_views_deal_id     on public.deal_views(deal_id);
create index if not exists idx_deal_views_merchant_id on public.deal_views(merchant_id);
create index if not exists idx_deal_views_viewed_at   on public.deal_views(viewed_at);

-- =============================================================
-- 2. deal_views 表 RLS 策略
-- =============================================================
alter table public.deal_views enable row level security;

-- 商家只能查看自己门店的浏览记录
do $$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public'
      and tablename  = 'deal_views'
      and policyname = 'deal_views_select_merchant'
  ) then
    execute $policy$
      create policy "deal_views_select_merchant" on public.deal_views
        for select using (
          merchant_id in (
            select id from public.merchants where user_id = auth.uid()
          )
        )
    $policy$;
  end if;
end;
$$;

-- 任何认证用户可以 INSERT 浏览记录（用户端 App 调用）
do $$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public'
      and tablename  = 'deal_views'
      and policyname = 'deal_views_insert_authenticated'
  ) then
    execute $policy$
      create policy "deal_views_insert_authenticated" on public.deal_views
        for insert with check (auth.role() = 'authenticated')
    $policy$;
  end if;
end;
$$;

-- =============================================================
-- 3. DB 函数: get_merchant_overview
-- 返回指定时间范围内的核心经营指标
-- 参数:
--   p_merchant_id uuid  — 商家 ID
--   p_days_range  int   — 天数范围 (7 或 30)
-- 返回:
--   views_count       bigint  — 浏览量（deal_views 表）
--   orders_count      bigint  — 下单量（orders 表，非退款）
--   redemptions_count bigint  — 核销量（coupons 表，status='used'）
--   revenue           numeric — 总收入（orders 表，非退款）
-- =============================================================
create or replace function public.get_merchant_overview(
  p_merchant_id uuid,
  p_days_range  int default 7
)
returns table(
  views_count       bigint,
  orders_count      bigint,
  redemptions_count bigint,
  revenue           numeric
)
language plpgsql
security definer
as $$
declare
  v_start_time timestamptz;
begin
  -- 安全校验：调用者必须是该商家的 owner
  if not exists (
    select 1 from public.merchants
    where id = p_merchant_id and user_id = auth.uid()
  ) then
    raise exception 'access_denied'
      using hint = 'You do not own this merchant account';
  end if;

  -- 计算时间范围起点（UTC，包含当天）
  v_start_time := date_trunc('day', now() at time zone 'UTC')
                  - ((p_days_range - 1) * interval '1 day');

  return query
  select
    -- 浏览量：该时间范围内该商家所有 deal 的浏览次数
    (
      select count(*)
      from public.deal_views dv
      where dv.merchant_id = p_merchant_id
        and dv.viewed_at >= v_start_time
    )::bigint as views_count,

    -- 下单量：非退款状态的订单数
    (
      select count(*)
      from public.orders o
      join public.deals d on d.id = o.deal_id
      where d.merchant_id = p_merchant_id
        and o.status not in ('refunded', 'refund_requested')
        and o.created_at >= v_start_time
    )::bigint as orders_count,

    -- 核销量：coupon 已核销（used）的数量
    (
      select count(*)
      from public.coupons c
      where c.merchant_id = p_merchant_id
        and c.status = 'used'
        and c.used_at >= v_start_time
    )::bigint as redemptions_count,

    -- 总收入：非退款订单的 total_amount 合计
    coalesce((
      select sum(o.total_amount)
      from public.orders o
      join public.deals d on d.id = o.deal_id
      where d.merchant_id = p_merchant_id
        and o.status not in ('refunded', 'refund_requested')
        and o.created_at >= v_start_time
    ), 0)::numeric as revenue;
end;
$$;

-- =============================================================
-- 4. DB 函数: get_deal_funnel
-- 返回该商家每个 Deal 的浏览→下单→核销漏斗数据
-- 参数:
--   p_merchant_id uuid — 商家 ID
-- 返回（每行代表一个 Deal）:
--   deal_id                  uuid
--   deal_title               text
--   views                    bigint  — 总浏览量
--   orders                   bigint  — 总下单量（非退款）
--   redemptions              bigint  — 总核销量
--   view_to_order_rate       numeric — 浏览→下单转化率（%，保留1位小数）
--   order_to_redemption_rate numeric — 下单→核销转化率（%，保留1位小数）
-- =============================================================
create or replace function public.get_deal_funnel(
  p_merchant_id uuid
)
returns table(
  deal_id                  uuid,
  deal_title               text,
  views                    bigint,
  orders                   bigint,
  redemptions              bigint,
  view_to_order_rate       numeric,
  order_to_redemption_rate numeric
)
language plpgsql
security definer
as $$
begin
  -- 安全校验
  if not exists (
    select 1 from public.merchants
    where id = p_merchant_id and user_id = auth.uid()
  ) then
    raise exception 'access_denied'
      using hint = 'You do not own this merchant account';
  end if;

  return query
  with deal_stats as (
    select
      d.id                                                       as deal_id,
      d.title                                                    as deal_title,
      -- 浏览量
      coalesce((
        select count(*) from public.deal_views dv
        where dv.deal_id = d.id
      ), 0)::bigint                                              as view_count,
      -- 下单量（非退款）
      coalesce((
        select count(*) from public.orders o
        where o.deal_id = d.id
          and o.status not in ('refunded', 'refund_requested')
      ), 0)::bigint                                              as order_count,
      -- 核销量
      coalesce((
        select count(*) from public.coupons c
        where c.deal_id = d.id
          and c.status = 'used'
      ), 0)::bigint                                              as redemption_count
    from public.deals d
    where d.merchant_id = p_merchant_id
    order by d.created_at desc
  )
  select
    ds.deal_id,
    ds.deal_title,
    ds.view_count,
    ds.order_count,
    ds.redemption_count,
    -- 浏览→下单转化率（避免除以0）
    case
      when ds.view_count > 0
      then round((ds.order_count::numeric / ds.view_count * 100), 1)
      else 0::numeric
    end                                                          as view_to_order_rate,
    -- 下单→核销转化率
    case
      when ds.order_count > 0
      then round((ds.redemption_count::numeric / ds.order_count * 100), 1)
      else 0::numeric
    end                                                          as order_to_redemption_rate
  from deal_stats ds;
end;
$$;

-- =============================================================
-- 5. DB 函数: get_customer_analysis
-- 返回该商家的客群新老分析数据
-- 参数:
--   p_merchant_id uuid — 商家 ID
-- 返回:
--   new_customers_count       bigint  — 新客（在该商家第一次下单的用户数）
--   returning_customers_count bigint  — 老客（曾在该商家下过单的用户数）
--   repeat_rate               numeric — 复购率（老客占有效购买用户的百分比，%，保留1位小数）
-- 说明:
--   统计基准：所有时间的历史下单记录（非退款）
--   新客定义：只在该商家下过 1 笔订单的用户
--   老客定义：在该商家下过 ≥2 笔订单的用户
-- =============================================================
create or replace function public.get_customer_analysis(
  p_merchant_id uuid
)
returns table(
  new_customers_count       bigint,
  returning_customers_count bigint,
  repeat_rate               numeric
)
language plpgsql
security definer
as $$
begin
  -- 安全校验
  if not exists (
    select 1 from public.merchants
    where id = p_merchant_id and user_id = auth.uid()
  ) then
    raise exception 'access_denied'
      using hint = 'You do not own this merchant account';
  end if;

  return query
  with customer_orders as (
    -- 统计每个用户在该商家的有效订单数（非退款）
    select
      o.user_id,
      count(*) as order_count
    from public.orders o
    join public.deals d on d.id = o.deal_id
    where d.merchant_id = p_merchant_id
      and o.status not in ('refunded', 'refund_requested')
    group by o.user_id
  ),
  customer_segments as (
    select
      -- 新客：只下了 1 笔订单
      count(*) filter (where order_count = 1)  as new_count,
      -- 老客：下了 ≥2 笔订单
      count(*) filter (where order_count >= 2) as returning_count,
      -- 全部有效购买用户
      count(*)                                  as total_count
    from customer_orders
  )
  select
    new_count::bigint       as new_customers_count,
    returning_count::bigint as returning_customers_count,
    -- 复购率 = 老客 / 全部有效购买用户 * 100
    case
      when total_count > 0
      then round((returning_count::numeric / total_count * 100), 1)
      else 0::numeric
    end                     as repeat_rate
  from customer_segments;
end;
$$;
