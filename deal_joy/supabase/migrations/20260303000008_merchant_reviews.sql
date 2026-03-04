-- =============================================================
-- Migration: 商家端评价管理模块
-- 功能:
--   1. reviews 表新增 merchant_reply + replied_at 列
--   2. 创建 get_review_stats 函数（平均分 + 分布 + 关键词）
--   3. RLS 策略：商家可更新自己门店评价的 merchant_reply 字段
-- =============================================================

-- =============================================================
-- 1. reviews 表新增商家回复字段
-- =============================================================
alter table public.reviews
  add column if not exists merchant_reply text,           -- 商家回复内容（null 表示未回复）
  add column if not exists replied_at     timestamptz;    -- 回复时间戳

-- 为已回复评价创建部分索引（查询加速）
create index if not exists idx_reviews_replied
  on public.reviews(id)
  where merchant_reply is not null;

-- =============================================================
-- 2. DB 函数: get_review_stats
-- 返回指定商家的评价统计信息
-- 参数:
--   p_merchant_id uuid — 商家 ID
-- 返回:
--   avg_rating          numeric  — 平均评分（保留2位小数）
--   total_count         bigint   — 评价总数
--   rating_distribution jsonb    — 各星评价数量 {"1":n,"2":n,"3":n,"4":n,"5":n}
--   top_keywords        text[]   — 高频关键词（最多10个，从 comment 提取）
-- =============================================================
create or replace function public.get_review_stats(
  p_merchant_id uuid
)
returns table(
  avg_rating          numeric,
  total_count         bigint,
  rating_distribution jsonb,
  top_keywords        text[]
)
language plpgsql
security definer
as $$
declare
  v_words       text[];
  v_word        text;
  v_keywords    text[]  := '{}';
  -- 停用词列表（常见无意义词）
  v_stopwords   text[]  := array[
    'the','a','an','is','it','in','on','at','to','for','of','and','or',
    'was','were','be','been','being','have','has','had','do','does','did',
    'will','would','could','should','may','might','this','that','these',
    'those','i','we','you','he','she','they','my','our','your','his','her',
    'its','their','with','very','so','just','like','get','got','not','no'
  ];
  -- 词频临时表
  v_word_counts jsonb   := '{}';
  v_count       int;
  v_max_count   int     := 0;
  v_sorted_keys text[];
begin
  -- 安全校验：调用者必须是该商家的 owner
  if not exists (
    select 1 from public.merchants
    where id = p_merchant_id and user_id = auth.uid()
  ) then
    raise exception 'access_denied'
      using hint = 'You do not own this merchant account';
  end if;

  -- 基础统计（平均分 + 各星数量 + 总数）
  return query
  with review_base as (
    -- 获取该商家下所有 deals 的评价
    select
      r.rating,
      r.comment
    from public.reviews r
    join public.deals d on d.id = r.deal_id
    where d.merchant_id = p_merchant_id
  ),
  stats as (
    select
      coalesce(round(avg(rating::numeric), 2), 0::numeric)   as avg_r,
      count(*)                                               as total,
      jsonb_build_object(
        '1', count(*) filter (where rating = 1),
        '2', count(*) filter (where rating = 2),
        '3', count(*) filter (where rating = 3),
        '4', count(*) filter (where rating = 4),
        '5', count(*) filter (where rating = 5)
      )                                                      as distribution
    from review_base
  ),
  -- 提取所有评价的分词（按空格和标点分割，转小写，过滤短词和停用词）
  words_raw as (
    select
      lower(
        regexp_replace(word, '[^a-zA-Z]', '', 'g')
      ) as word
    from review_base,
    lateral regexp_split_to_table(
      coalesce(comment, ''), '\s+'
    ) as word
    where length(word) > 0
  ),
  clean_words as (
    select word
    from words_raw
    where
      length(word) >= 4
      and word not in (
        'the','a','an','is','it','in','on','at','to','for','of','and','or',
        'was','were','be','been','being','have','has','had','do','does','did',
        'will','would','could','should','may','might','this','that','these',
        'those','my','our','your','his','her','its','their','with','very',
        'just','like','great','good','nice','also','from','they','were',
        'really','very','more','some','than','when','then','here','food',
        'place','time','back','came','came','went','said'
      )
  ),
  -- 词频统计，取前10
  word_freq as (
    select word, count(*) as cnt
    from clean_words
    where word != ''
    group by word
    order by cnt desc
    limit 10
  )
  select
    s.avg_r,
    s.total,
    s.distribution,
    array(select word from word_freq)
  from stats s;
end;
$$;

-- 授予函数执行权限（商家端 Edge Function 通过 authenticated 调用）
GRANT EXECUTE ON FUNCTION public.get_review_stats(uuid) TO authenticated;

-- =============================================================
-- 3. RLS 策略：商家可更新自己门店评价的 merchant_reply 字段
-- =============================================================

-- 商家更新自己门店评价的 merchant_reply（限 UPDATE，通过 deal→merchant 关联校验）
do $$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public'
      and tablename  = 'reviews'
      and policyname = 'reviews_merchant_reply_update'
  ) then
    execute $policy$
      create policy "reviews_merchant_reply_update" on public.reviews
        for update
        using (
          -- 仅允许更新属于自己门店 deal 的评价
          deal_id in (
            select d.id from public.deals d
            join public.merchants m on m.id = d.merchant_id
            where m.user_id = auth.uid()
          )
        )
        with check (
          -- 校验回复内容长度（冗余保护）
          merchant_reply is null or length(merchant_reply) <= 300
        )
    $policy$;
  end if;
end;
$$;
