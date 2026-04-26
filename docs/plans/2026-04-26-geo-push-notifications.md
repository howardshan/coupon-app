# Geo-Targeted Push Notifications (Admin Campaign Tool)

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Admin 可以选择一个 Deal 或商家、设置半径（默认 25 miles），编辑通知标题/内容，发送给该范围内有 App 的用户，用户点击后直接跳转到对应 Deal 或商家页。

**Architecture:** 分 4 层实现：① Flutter App 登录时将用户 GPS 存入 `users` 表；② DB RPC 按 Haversine 公式找指定半径内有 FCM token 的用户；③ 新 Edge Function `send-geo-push` 负责查用户、批量推送、记录 campaign；④ Admin 新增 `/notifications` 页面提供表单 UI。

**Tech Stack:** Flutter + Geolocator（已有）、Supabase PostgreSQL RPC、Deno Edge Function、Next.js 15 Server Actions、Tailwind CSS、Sonner toast

---

## 关键路径速查

| 文件 | 用途 |
|------|------|
| `deal_joy/lib/shared/services/location_sync_service.dart` | 新建：登录后同步 GPS 到 users 表 |
| `deal_joy/lib/app.dart` | 修改：登录时调用 location sync |
| `deal_joy/lib/shared/services/push_notification_service.dart` | 修改：增加 `promo` 通知类型处理 |
| `deal_joy/supabase/migrations/20260426000002_geo_push.sql` | 新建：DB 迁移（users 位置字段 + campaigns 表 + RPC） |
| `deal_joy/supabase/functions/send-geo-push/index.ts` | 新建：Edge Function |
| `deal_joy/supabase/functions/send-push-notification/index.ts` | 修改：validTypes 加 `promo` |
| `admin/app/(dashboard)/notifications/page.tsx` | 新建：Admin 通知页（Server Component） |
| `admin/components/notifications-page-client.tsx` | 新建：表单 UI（Client Component） |
| `admin/app/actions/push-notifications.ts` | 新建：Server Actions |
| `admin/components/sidebar.tsx` | 修改：加导航项 |

---

## Task 1: DB Migration — users 表加位置字段 + campaigns 表 + RPC

**Files:**
- Create: `deal_joy/supabase/migrations/20260426000002_geo_push.sql`

**Step 1: 写迁移文件**

```sql
-- ============================================================
-- Geo Push Notifications
-- 1. users 表增加位置字段（App 登录时写入）
-- 2. push_campaigns 表记录发送历史
-- 3. find_users_for_geo_push RPC 查找范围内用户
-- ============================================================

-- 1. users 表加字段
ALTER TABLE public.users
  ADD COLUMN IF NOT EXISTS last_lat  double precision,
  ADD COLUMN IF NOT EXISTS last_lng  double precision,
  ADD COLUMN IF NOT EXISTS last_location_at timestamptz;

-- 空间索引（加速地理查询）
CREATE INDEX IF NOT EXISTS idx_users_location
  ON public.users (last_lat, last_lng)
  WHERE last_lat IS NOT NULL AND last_lng IS NOT NULL;

-- RLS：用户只能更新自己的位置
CREATE POLICY "users can update own location"
  ON public.users
  FOR UPDATE
  USING (auth.uid() = id)
  WITH CHECK (auth.uid() = id);

-- 2. push_campaigns 表
CREATE TABLE IF NOT EXISTS public.push_campaigns (
  id               uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  title            text        NOT NULL,
  body             text        NOT NULL,
  deal_id          uuid        REFERENCES public.deals(id) ON DELETE SET NULL,
  merchant_id      uuid        REFERENCES public.merchants(id) ON DELETE SET NULL,
  radius_meters    int         NOT NULL DEFAULT 40234, -- 25 miles
  target_lat       double precision NOT NULL,
  target_lng       double precision NOT NULL,
  sent_user_count  int         NOT NULL DEFAULT 0,
  created_by       uuid        REFERENCES public.users(id) ON DELETE SET NULL,
  created_at       timestamptz NOT NULL DEFAULT now()
);

-- RLS：只有 admin 可读写 campaigns
ALTER TABLE public.push_campaigns ENABLE ROW LEVEL SECURITY;

CREATE POLICY "admin can manage push_campaigns"
  ON public.push_campaigns
  FOR ALL
  USING (
    EXISTS (
      SELECT 1 FROM public.users
      WHERE id = auth.uid() AND role = 'admin'
    )
  );

-- 3. RPC：找指定半径内有 FCM token 的用户
CREATE OR REPLACE FUNCTION find_users_for_geo_push(
  p_lat      double precision,
  p_lng      double precision,
  p_radius_m int DEFAULT 40234
)
RETURNS TABLE (user_id uuid)
LANGUAGE sql
STABLE
SECURITY DEFINER
AS $$
  SELECT DISTINCT u.id
  FROM public.users u
  JOIN public.user_fcm_tokens t ON t.user_id = u.id
  WHERE
    u.last_lat IS NOT NULL
    AND u.last_lng IS NOT NULL
    AND (
      3958.8 * 2 * ASIN(SQRT(
        POWER(SIN(RADIANS((u.last_lat - p_lat) / 2)), 2) +
        COS(RADIANS(p_lat)) * COS(RADIANS(u.last_lat)) *
        POWER(SIN(RADIANS((u.last_lng - p_lng) / 2)), 2)
      )) * 1609.34
    ) <= p_radius_m;
$$;
```

**Step 2: 推送迁移**

```bash
/opt/homebrew/bin/supabase db push --project-ref kqyolvmgrdekybjrwizx
```

Expected: `Applying migration 20260426000002_geo_push.sql... done`

**Step 3: Commit**

```bash
git add deal_joy/supabase/migrations/20260426000002_geo_push.sql
git commit -m "feat: add user location fields and push_campaigns table"
```

---

## Task 2: Flutter — 登录后同步用户 GPS 到 DB

**Files:**
- Create: `deal_joy/lib/shared/services/location_sync_service.dart`
- Modify: `deal_joy/lib/app.dart`

**Step 1: 创建 location_sync_service.dart**

```dart
import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class LocationSyncService {
  final _supabase = Supabase.instance.client;

  /// 获取 GPS 并同步到 users 表，失败静默忽略
  Future<void> syncUserLocation(String userId) async {
    try {
      final permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) return;

      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.low,
        ),
      ).timeout(const Duration(seconds: 10));

      await _supabase.from('users').update({
        'last_lat': pos.latitude,
        'last_lng': pos.longitude,
        'last_location_at': DateTime.now().toIso8601String(),
      }).eq('id', userId);
    } catch (_) {
      // 位置同步失败不影响主流程
    }
  }
}
```

**Step 2: 修改 app.dart — 登录后调用**

在 `deal_joy/lib/app.dart` 找到 `push.init(user.id)` 那行，在其后加一行：

```dart
// 现有代码（第 39 行附近）
push.init(user.id);
// 新增：后台同步用户位置
LocationSyncService().syncUserLocation(user.id);
```

同时在文件顶部加 import：
```dart
import 'package:deal_joy/shared/services/location_sync_service.dart';
```

**Step 3: 运行 App，登录，验证 DB**

```bash
/opt/homebrew/bin/psql "postgresql://postgres.kqyolvmgrdekybjrwizx:dealjoy20260228!@aws-0-us-west-2.pooler.supabase.com:5432/postgres" \
  -c "SELECT id, last_lat, last_lng, last_location_at FROM users WHERE last_lat IS NOT NULL LIMIT 5;"
```

Expected: 看到登录账号的 lat/lng 已写入。

**Step 4: Commit**

```bash
git add deal_joy/lib/shared/services/location_sync_service.dart deal_joy/lib/app.dart
git commit -m "feat: sync user GPS location to DB on login"
```

---

## Task 3: Flutter — 支持 promo 通知类型点击跳转

**Files:**
- Modify: `deal_joy/lib/shared/services/push_notification_service.dart`

在 `_navigateByData()` 函数（第 180 行附近）找到 `switch (type)` 或 `if/else` 块，添加 `promo` 处理：

**Step 1: 找到 `_navigateByData` 中最后一个 case，在其前面插入**

```dart
case 'promo':
  final dealId = data?['deal_id'];
  final merchantId = data?['merchant_id'];
  if (dealId != null) {
    _navigatorKey.currentState?.pushNamed('/deals/$dealId');
  } else if (merchantId != null) {
    _navigatorKey.currentState?.pushNamed('/merchant/$merchantId');
  }
  break;
```

或者如果用的是 go_router context.go 风格（实际代码使用 rootNavigatorKey + context.go），参考现有 case 的写法做相同处理。

**Step 2: Commit**

```bash
git add deal_joy/lib/shared/services/push_notification_service.dart
git commit -m "feat: handle promo notification type for deal/merchant deep link"
```

---

## Task 4: Edge Function — 更新 send-push-notification validTypes

**Files:**
- Modify: `deal_joy/supabase/functions/send-push-notification/index.ts`

找到第 54-61 行的 `validTypes` 数组，添加 `'promo'`：

```typescript
const validTypes = [
  "transaction",
  "announcement",
  "friend_activity",
  "friend_request",
  "review_reply",
  "chat_message",
  "promo",           // 新增：地理定向促销推送
];
```

**Deploy:**

```bash
/opt/homebrew/bin/supabase functions deploy send-push-notification \
  --no-verify-jwt --project-ref kqyolvmgrdekybjrwizx
```

---

## Task 5: Edge Function — 新建 send-geo-push

**Files:**
- Create: `deal_joy/supabase/functions/send-geo-push/index.ts`

```typescript
// send-geo-push Edge Function
// Admin 调用：按地理范围批量推送，记录 campaign
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { sendToUser } from "../_shared/fcm.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return new Response("Method not allowed", { status: 405 });

  try {
    const {
      title,
      body,
      deal_id,
      merchant_id,
      target_lat,
      target_lng,
      radius_meters = 40234, // 默认 25 miles
      created_by,
    } = await req.json();

    if (!title || !body || !target_lat || !target_lng) {
      return new Response(
        JSON.stringify({ error: "Missing required fields: title, body, target_lat, target_lng" }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!
    );

    // 1. 找范围内有 FCM token 的用户
    const { data: users, error: rpcError } = await supabase.rpc("find_users_for_geo_push", {
      p_lat: target_lat,
      p_lng: target_lng,
      p_radius_m: radius_meters,
    });

    if (rpcError) throw new Error(rpcError.message);

    const userIds: string[] = (users ?? []).map((r: { user_id: string }) => r.user_id);

    // 2. 批量推送（并行，最多 50 并发）
    const fcmData: Record<string, string> = { type: "promo" };
    if (deal_id) fcmData.deal_id = deal_id;
    if (merchant_id) fcmData.merchant_id = merchant_id;

    const BATCH = 50;
    for (let i = 0; i < userIds.length; i += BATCH) {
      await Promise.all(
        userIds.slice(i, i + BATCH).map((uid) =>
          sendToUser(supabase, uid, title, body, fcmData).catch(() => null)
        )
      );
    }

    // 3. 记录 campaign
    await supabase.from("push_campaigns").insert({
      title,
      body,
      deal_id: deal_id ?? null,
      merchant_id: merchant_id ?? null,
      radius_meters,
      target_lat,
      target_lng,
      sent_user_count: userIds.length,
      created_by: created_by ?? null,
    });

    return new Response(
      JSON.stringify({ success: true, sent_count: userIds.length }),
      { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  } catch (err) {
    console.error("[send-geo-push] error:", err);
    return new Response(
      JSON.stringify({ error: (err as Error).message }),
      { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  }
});
```

**Deploy:**

```bash
/opt/homebrew/bin/supabase functions deploy send-geo-push \
  --no-verify-jwt --project-ref kqyolvmgrdekybjrwizx
```

**Step: Commit**

```bash
git add deal_joy/supabase/functions/send-geo-push/ \
        deal_joy/supabase/functions/send-push-notification/index.ts
git commit -m "feat: add send-geo-push edge function and promo notification type"
```

---

## Task 6: Admin Server Actions

**Files:**
- Create: `admin/app/actions/push-notifications.ts`

```typescript
'use server'

import { createClient } from '@/lib/supabase/server'
import { getServiceRoleClient } from '@/lib/supabase/service'

async function requireAdmin() {
  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()
  if (!user) throw new Error('Unauthorized')
  const { data: profile } = await supabase
    .from('users').select('role').eq('id', user.id).single()
  if (profile?.role !== 'admin') throw new Error('Forbidden')
  return user
}

/** 获取 deals 和 merchants 列表供下拉选择 */
export async function getDealsAndMerchants() {
  const db = getServiceRoleClient()
  const [{ data: deals }, { data: merchants }] = await Promise.all([
    db.from('deals')
      .select('id, title, merchant_id, merchants(lat, lng, name)')
      .eq('is_active', true)
      .order('created_at', { ascending: false })
      .limit(200),
    db.from('merchants')
      .select('id, name, lat, lng')
      .eq('status', 'active')
      .order('name')
      .limit(200),
  ])
  return { deals: deals ?? [], merchants: merchants ?? [] }
}

/** 预览：统计目标范围内有多少用户 */
export async function previewGeoNotification(
  lat: number,
  lng: number,
  radiusMeters: number
): Promise<{ count: number; error?: string }> {
  try {
    await requireAdmin()
    const db = getServiceRoleClient()
    const { data, error } = await db.rpc('find_users_for_geo_push', {
      p_lat: lat,
      p_lng: lng,
      p_radius_m: radiusMeters,
    })
    if (error) return { count: 0, error: error.message }
    return { count: (data ?? []).length }
  } catch (e) {
    return { count: 0, error: (e as Error).message }
  }
}

/** 发送地理定向推送 */
export async function sendGeoNotification(payload: {
  title: string
  body: string
  dealId?: string
  merchantId?: string
  targetLat: number
  targetLng: number
  radiusMeters: number
}): Promise<{ success: boolean; sentCount?: number; error?: string }> {
  try {
    const user = await requireAdmin()

    const resp = await fetch(
      `${process.env.NEXT_PUBLIC_SUPABASE_URL}/functions/v1/send-geo-push`,
      {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          Authorization: `Bearer ${process.env.SUPABASE_SERVICE_ROLE_KEY}`,
        },
        body: JSON.stringify({
          title: payload.title,
          body: payload.body,
          deal_id: payload.dealId,
          merchant_id: payload.merchantId,
          target_lat: payload.targetLat,
          target_lng: payload.targetLng,
          radius_meters: payload.radiusMeters,
          created_by: user.id,
        }),
      }
    )

    const result = await resp.json()
    if (!resp.ok) return { success: false, error: result.error }
    return { success: true, sentCount: result.sent_count }
  } catch (e) {
    return { success: false, error: (e as Error).message }
  }
}

/** 获取已发送的 campaign 列表 */
export async function getPushCampaigns() {
  const db = getServiceRoleClient()
  const { data } = await db
    .from('push_campaigns')
    .select(`
      id, title, body, radius_meters, sent_user_count, created_at,
      deals(id, title),
      merchants(id, name)
    `)
    .order('created_at', { ascending: false })
    .limit(50)
  return data ?? []
}
```

---

## Task 7: Admin UI — Notifications 页面

**Files:**
- Create: `admin/app/(dashboard)/notifications/page.tsx`
- Create: `admin/components/notifications-page-client.tsx`

**`page.tsx` (Server Component):**

```typescript
import { createClient } from '@/lib/supabase/server'
import { redirect } from 'next/navigation'
import { getDealsAndMerchants, getPushCampaigns } from '@/app/actions/push-notifications'
import NotificationsPageClient from '@/components/notifications-page-client'

export const dynamic = 'force-dynamic'

export default async function NotificationsPage() {
  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()
  const { data: profile } = await supabase
    .from('users').select('role').eq('id', user!.id).single()
  if (profile?.role !== 'admin') redirect('/dashboard')

  const [{ deals, merchants }, campaigns] = await Promise.all([
    getDealsAndMerchants(),
    getPushCampaigns(),
  ])

  return (
    <NotificationsPageClient
      deals={deals}
      merchants={merchants}
      campaigns={campaigns}
    />
  )
}
```

**`notifications-page-client.tsx` (Client Component):**

```typescript
'use client'

import { useState, useTransition } from 'react'
import { toast } from 'sonner'
import {
  previewGeoNotification,
  sendGeoNotification,
} from '@/app/actions/push-notifications'

const RADIUS_OPTIONS = [
  { label: '10 miles', value: 16093 },
  { label: '25 miles', value: 40234 },
  { label: '50 miles', value: 80467 },
  { label: '100 miles', value: 160934 },
]

type Deal = { id: string; title: string; merchants: { lat: number | null; lng: number | null; name: string } | null }
type Merchant = { id: string; name: string; lat: number | null; lng: number | null }
type Campaign = {
  id: string; title: string; body: string; radius_meters: number
  sent_user_count: number; created_at: string
  deals: { id: string; title: string } | null
  merchants: { id: string; name: string } | null
}

interface Props {
  deals: Deal[]
  merchants: Merchant[]
  campaigns: Campaign[]
}

export default function NotificationsPageClient({ deals, merchants, campaigns }: Props) {
  const [isPending, startTransition] = useTransition()

  // 表单状态
  const [targetType, setTargetType] = useState<'deal' | 'merchant'>('deal')
  const [selectedDealId, setSelectedDealId] = useState('')
  const [selectedMerchantId, setSelectedMerchantId] = useState('')
  const [radiusMeters, setRadiusMeters] = useState(40234)
  const [title, setTitle] = useState('')
  const [body, setBody] = useState('')
  const [previewCount, setPreviewCount] = useState<number | null>(null)

  // 获取当前选择的 lat/lng
  const getTargetCoords = (): { lat: number; lng: number } | null => {
    if (targetType === 'deal') {
      const deal = deals.find(d => d.id === selectedDealId)
      if (!deal?.merchants?.lat || !deal?.merchants?.lng) return null
      return { lat: deal.merchants.lat, lng: deal.merchants.lng }
    } else {
      const merchant = merchants.find(m => m.id === selectedMerchantId)
      if (!merchant?.lat || !merchant?.lng) return null
      return { lat: merchant.lat, lng: merchant.lng }
    }
  }

  const handlePreview = () => {
    const coords = getTargetCoords()
    if (!coords) { toast.error('Please select a deal or merchant with location data'); return }
    startTransition(async () => {
      const { count, error } = await previewGeoNotification(coords.lat, coords.lng, radiusMeters)
      if (error) { toast.error(error); return }
      setPreviewCount(count)
    })
  }

  const handleSend = () => {
    const coords = getTargetCoords()
    if (!coords) { toast.error('Please select a deal or merchant with location data'); return }
    if (!title.trim() || !body.trim()) { toast.error('Title and message are required'); return }

    startTransition(async () => {
      const { success, sentCount, error } = await sendGeoNotification({
        title: title.trim(),
        body: body.trim(),
        dealId: targetType === 'deal' ? selectedDealId : undefined,
        merchantId: targetType === 'merchant' ? selectedMerchantId : undefined,
        targetLat: coords.lat,
        targetLng: coords.lng,
        radiusMeters,
      })
      if (!success) { toast.error(error || 'Failed to send'); return }
      toast.success(`Sent to ${sentCount} users!`)
      setTitle(''); setBody(''); setPreviewCount(null)
    })
  }

  return (
    <div className="space-y-8">
      <div>
        <h1 className="text-2xl font-bold text-gray-900">Push Notifications</h1>
        <p className="mt-1 text-sm text-gray-500">Send geo-targeted push notifications to nearby users</p>
      </div>

      {/* 新建通知表单 */}
      <div className="rounded-xl border border-gray-200 bg-white p-6 space-y-5">
        <h2 className="text-base font-semibold text-gray-900">New Campaign</h2>

        {/* 目标类型 */}
        <div className="flex gap-3">
          {(['deal', 'merchant'] as const).map(t => (
            <button
              key={t}
              onClick={() => { setTargetType(t); setPreviewCount(null) }}
              className={`px-4 py-2 rounded-lg text-sm font-medium transition-colors ${
                targetType === t
                  ? 'bg-blue-600 text-white'
                  : 'bg-gray-100 text-gray-700 hover:bg-gray-200'
              }`}
            >
              {t === 'deal' ? 'By Deal' : 'By Merchant'}
            </button>
          ))}
        </div>

        {/* Deal 或 Merchant 选择 */}
        {targetType === 'deal' ? (
          <div>
            <label className="block text-sm font-medium text-gray-700 mb-1">Select Deal</label>
            <select
              value={selectedDealId}
              onChange={e => { setSelectedDealId(e.target.value); setPreviewCount(null) }}
              className="w-full px-3 py-2 border border-gray-300 rounded-lg bg-white text-gray-900"
            >
              <option value="">-- Choose a deal --</option>
              {deals.map(d => (
                <option key={d.id} value={d.id}>
                  {d.title} {d.merchants ? `(${d.merchants.name})` : ''}
                </option>
              ))}
            </select>
          </div>
        ) : (
          <div>
            <label className="block text-sm font-medium text-gray-700 mb-1">Select Merchant</label>
            <select
              value={selectedMerchantId}
              onChange={e => { setSelectedMerchantId(e.target.value); setPreviewCount(null) }}
              className="w-full px-3 py-2 border border-gray-300 rounded-lg bg-white text-gray-900"
            >
              <option value="">-- Choose a merchant --</option>
              {merchants.map(m => (
                <option key={m.id} value={m.id}>{m.name}</option>
              ))}
            </select>
          </div>
        )}

        {/* 半径 */}
        <div>
          <label className="block text-sm font-medium text-gray-700 mb-1">Radius</label>
          <div className="flex gap-2">
            {RADIUS_OPTIONS.map(opt => (
              <button
                key={opt.value}
                onClick={() => { setRadiusMeters(opt.value); setPreviewCount(null) }}
                className={`px-3 py-1.5 rounded-lg text-sm font-medium transition-colors ${
                  radiusMeters === opt.value
                    ? 'bg-blue-600 text-white'
                    : 'bg-gray-100 text-gray-700 hover:bg-gray-200'
                }`}
              >
                {opt.label}
              </button>
            ))}
          </div>
        </div>

        {/* 标题 */}
        <div>
          <label className="block text-sm font-medium text-gray-700 mb-1">Title</label>
          <input
            type="text"
            value={title}
            onChange={e => setTitle(e.target.value)}
            placeholder="e.g. New Deal Near You! 🎉"
            maxLength={65}
            className="w-full px-3 py-2 border border-gray-300 rounded-lg"
          />
          <p className="mt-1 text-xs text-gray-400">{title.length}/65</p>
        </div>

        {/* 内容 */}
        <div>
          <label className="block text-sm font-medium text-gray-700 mb-1">Message</label>
          <textarea
            value={body}
            onChange={e => setBody(e.target.value)}
            placeholder="e.g. Crave & Cook now offers 40% off — tap to check it out!"
            rows={3}
            maxLength={178}
            className="w-full px-3 py-2 border border-gray-300 rounded-lg resize-none"
          />
          <p className="mt-1 text-xs text-gray-400">{body.length}/178</p>
        </div>

        {/* 预览 + 发送 */}
        <div className="flex items-center gap-3 pt-2">
          <button
            onClick={handlePreview}
            disabled={isPending || (!selectedDealId && !selectedMerchantId)}
            className="px-4 py-2 rounded-lg border border-gray-300 text-sm text-gray-700 hover:bg-gray-50 disabled:opacity-40"
          >
            Preview Audience
          </button>

          {previewCount !== null && (
            <span className="text-sm text-gray-600 font-medium">
              ~<strong>{previewCount}</strong> users in range
            </span>
          )}

          <button
            onClick={handleSend}
            disabled={isPending || !title || !body || (!selectedDealId && !selectedMerchantId)}
            className="ml-auto px-5 py-2 rounded-lg bg-blue-600 text-white text-sm font-medium hover:bg-blue-700 disabled:opacity-40 transition-colors"
          >
            {isPending ? 'Sending...' : 'Send Now'}
          </button>
        </div>
      </div>

      {/* 历史记录 */}
      <div className="rounded-xl border border-gray-200 bg-white overflow-hidden">
        <div className="px-6 py-4 border-b border-gray-100">
          <h2 className="text-base font-semibold text-gray-900">Campaign History</h2>
        </div>
        {campaigns.length === 0 ? (
          <p className="px-6 py-8 text-sm text-gray-400 text-center">No campaigns sent yet.</p>
        ) : (
          <table className="w-full text-sm">
            <thead className="bg-gray-50 text-xs text-gray-500 uppercase">
              <tr>
                <th className="px-4 py-3 text-left">Title</th>
                <th className="px-4 py-3 text-left">Target</th>
                <th className="px-4 py-3 text-left">Radius</th>
                <th className="px-4 py-3 text-right">Sent</th>
                <th className="px-4 py-3 text-left">Date</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-gray-100">
              {campaigns.map(c => (
                <tr key={c.id} className="hover:bg-gray-50">
                  <td className="px-4 py-3 font-medium text-gray-900">{c.title}</td>
                  <td className="px-4 py-3 text-gray-600">
                    {c.deals?.title ?? c.merchants?.name ?? '—'}
                  </td>
                  <td className="px-4 py-3 text-gray-600">
                    {Math.round(c.radius_meters / 1609.34)} mi
                  </td>
                  <td className="px-4 py-3 text-right font-medium">{c.sent_user_count}</td>
                  <td className="px-4 py-3 text-gray-500">
                    {new Date(c.created_at).toLocaleDateString()}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        )}
      </div>
    </div>
  )
}
```

**Step: Commit**

```bash
git add admin/app/(dashboard)/notifications/ admin/components/notifications-page-client.tsx admin/app/actions/push-notifications.ts
git commit -m "feat: add admin notifications page for geo-targeted push campaigns"
```

---

## Task 8: Admin Sidebar — 添加导航项

**Files:**
- Modify: `admin/components/sidebar.tsx`

在 `adminNav` 数组中找到合适位置（如 `users` 条目后面），添加：

```typescript
{ kind: 'link', href: '/notifications', label: 'Notifications', icon: '🔔' },
```

**Step: Commit**

```bash
git add admin/components/sidebar.tsx
git commit -m "feat: add notifications to admin sidebar"
```

---

## Task 9: 端到端验证

**Step 1: 验证 location 同步**
```sql
SELECT last_lat, last_lng, last_location_at FROM users WHERE email = 'shayiqing16@gmail.com';
```
Expected: 有非 null 的坐标值。

**Step 2: 验证 RPC**
```sql
SELECT * FROM find_users_for_geo_push(33.13, -96.65, 40234);
```
Expected: 返回有 FCM token 的用户 ID 列表。

**Step 3: 测试 Admin 页面**
1. 打开 Admin → Notifications
2. 选择一个 deal，选半径 25 miles
3. 点 Preview Audience → 看到用户数量
4. 填 title/body → 点 Send Now
5. 手机收到推送，点击 → 跳转到对应 Deal 页

**Step 4: 验证 campaign 记录**
```sql
SELECT title, sent_user_count, created_at FROM push_campaigns ORDER BY created_at DESC LIMIT 1;
```

---

## 注意事项

- `_navigateByData()` 实际导航方式需对照现有 case 写法（有的用 `context.go`，有的用 `rootNavigatorKey`），保持一致
- `users` 表 RLS 已有 `users can update own profile` policy，新增的 `update own location` policy 需确认不冲突（可合并或用 IF NOT EXISTS）
- Edge Function 的 `SUPABASE_SERVICE_ROLE_KEY` 环境变量已自动注入，无需手动配置
- Admin `SUPABASE_SERVICE_ROLE_KEY` 在 `.env.local` 中需已配置
