# Admin Portal Phase 3 Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 补全 DealJoy 后台管理系统剩余功能：修复 RLS 权限、Dashboard 告警、Deal 上下架、订单管理。

**Architecture:** Next.js 15 App Router。Server Components 负责数据读取，Server Actions 处理写操作，Client Components 只做交互 UI。

**Tech Stack:** Next.js 15, TypeScript, Tailwind CSS, `@supabase/ssr`, `sonner`（已安装）

---

## 现有文件结构（已完成，勿重复创建）

```
admin/
├── app/
│   ├── actions/admin.ts          # updateUserRole, approveMerchant, rejectMerchant, revokeMerchantApproval
│   ├── (dashboard)/
│   │   ├── layout.tsx            # 读 users.role，渲染 Sidebar
│   │   ├── dashboard/page.tsx    # 统计卡片
│   │   ├── users/page.tsx        # 用户列表 + role 下拉
│   │   ├── merchants/page.tsx    # 商家列表 + 快速审核按钮
│   │   ├── merchants/[id]/page.tsx  # 商家详情审核页（含 merchant_documents）
│   │   └── deals/page.tsx        # Deal 列表（只读，discount_price/is_active/expires_at）
│   └── login/page.tsx
├── components/
│   ├── sidebar.tsx               # adminNav: Overview/Users/Merchants/Deals
│   ├── role-select.tsx           # 角色下拉（含 toast）
│   ├── merchant-action-buttons.tsx  # 列表页快速 Approve/Reject
│   └── merchant-review-actions.tsx  # 详情页完整操作（含拒绝原因、撤销）
└── lib/supabase/client.ts + server.ts
```

## 数据库关键字段（已从 schema.sql 确认）

```sql
-- deals: id, merchant_id, title, discount_price, original_price, is_active(boolean), expires_at, created_at
-- orders: id, user_id, deal_id, quantity, unit_price, total_amount, status(unused|used|refunded|refund_requested|expired), refund_reason, created_at
-- orders 表没有 merchant_id 列，需通过 deals 关联: orders → deals → merchants
-- merchants: id, user_id, name, status(pending|approved|rejected), rejection_reason, ...
```

---

## Task 1：修复 RLS 策略（Supabase SQL Editor）

**背景：** admin 账号当前只能看到自己一条用户记录，且无法更新其他人的 role 或商家 status、查看他人订单。所有后续功能依赖此步骤。

**操作：在 Supabase Dashboard → SQL Editor 中运行以下 SQL，全部一次性执行**

```sql
-- ① Admin 可查看所有用户
DROP POLICY IF EXISTS "admin_select_all_users" ON public.users;
CREATE POLICY "admin_select_all_users" ON public.users
  FOR SELECT USING (
    auth.uid() = id
    OR public.is_current_user_admin()
  );

-- ② Admin 可更新任何用户的 role
DROP POLICY IF EXISTS "admin_update_any_user" ON public.users;
CREATE POLICY "admin_update_any_user" ON public.users
  FOR UPDATE USING (
    auth.uid() = id
    OR public.is_current_user_admin()
  );

-- ③ Admin 可更新任何商家的 status / rejection_reason
DROP POLICY IF EXISTS "admin_update_merchant_status" ON public.merchants;
CREATE POLICY "admin_update_merchant_status" ON public.merchants
  FOR UPDATE USING (
    user_id = auth.uid()
    OR public.is_current_user_admin()
  );

-- ④ Admin 可查看所有订单
DROP POLICY IF EXISTS "admin_select_all_orders" ON public.orders;
CREATE POLICY "admin_select_all_orders" ON public.orders
  FOR SELECT USING (
    auth.uid() = user_id
    OR public.is_current_user_admin()
  );

-- ⑤ Admin 可更新订单状态（处理退款）
DROP POLICY IF EXISTS "admin_update_order_status" ON public.orders;
CREATE POLICY "admin_update_order_status" ON public.orders
  FOR UPDATE USING (
    public.is_current_user_admin()
  );
```

> **注意：** `is_current_user_admin()` 函数已在 migration `20260304000000_admin_merchant_documents.sql` 中创建，直接引用即可。

**验证：**
- 刷新 `http://localhost:3000/users`，应看到所有注册用户（不止一条）
- 尝试修改一个用户的 role，不报 RLS 错误

---

## Task 2：Dashboard 增加告警信息

**背景：** 当前 Dashboard 只有基础统计数字，admin 无法一眼看出有多少商家待审核、多少退款待处理。

**涉及文件：**
- 修改：`admin/app/(dashboard)/dashboard/page.tsx`

**修改 `getStats` 函数**，在 admin 分支额外查询 pending 数量：

```ts
// 在现有 admin 分支的 Promise.all 中追加两个查询：
const [
  { count: userCount },
  { count: merchantCount },
  { count: dealCount },
  { count: pendingMerchantCount },  // 新增
  { count: refundCount },           // 新增
] = await Promise.all([
  supabase.from('users').select('*', { count: 'exact', head: true }),
  supabase.from('merchants').select('*', { count: 'exact', head: true }),
  supabase.from('deals').select('*', { count: 'exact', head: true }),
  supabase.from('merchants').select('*', { count: 'exact', head: true }).eq('status', 'pending'),
  supabase.from('orders').select('*', { count: 'exact', head: true }).eq('status', 'refund_requested'),
])
return { role: 'admin', userCount, merchantCount, dealCount, pendingMerchantCount, refundCount }
```

**修改 `DashboardPage` 渲染**，在统计卡片下方加告警条：

```tsx
{/* 统计卡片（原有） */}
<div className="grid grid-cols-3 gap-4">
  <StatCard label="Total Users" value={stats.userCount ?? 0} color="blue" />
  <StatCard label="Total Merchants" value={stats.merchantCount ?? 0} color="green" />
  <StatCard label="Total Deals" value={stats.dealCount ?? 0} color="purple" />
</div>

{/* 告警区域（新增） */}
{((stats.pendingMerchantCount ?? 0) > 0 || (stats.refundCount ?? 0) > 0) && (
  <div className="mt-6 space-y-3">
    {(stats.pendingMerchantCount ?? 0) > 0 && (
      <a href="/merchants" className="flex items-center justify-between p-4 bg-yellow-50 border border-yellow-200 rounded-xl hover:bg-yellow-100 transition-colors">
        <div>
          <p className="text-sm font-semibold text-yellow-800">Merchants pending review</p>
          <p className="text-xs text-yellow-600 mt-0.5">Review applications and approve or reject</p>
        </div>
        <span className="text-2xl font-bold text-yellow-700">{stats.pendingMerchantCount}</span>
      </a>
    )}
    {(stats.refundCount ?? 0) > 0 && (
      <a href="/orders" className="flex items-center justify-between p-4 bg-orange-50 border border-orange-200 rounded-xl hover:bg-orange-100 transition-colors">
        <div>
          <p className="text-sm font-semibold text-orange-800">Refund requests pending</p>
          <p className="text-xs text-orange-600 mt-0.5">Review and approve or reject refunds</p>
        </div>
        <span className="text-2xl font-bold text-orange-700">{stats.refundCount}</span>
      </a>
    )}
  </div>
)}
```

**验证：**
- Dashboard 页面有待审商家时显示黄色告警条，点击跳转到 `/merchants`
- 有退款请求时显示橙色告警条，点击跳转到 `/orders`（Task 4 完成后可验证）

---

## Task 3：Deal 上下架开关

**背景：** 当前 Deals 页面只能查看，admin 需要能直接切换 deal 的 `is_active` 状态。

**涉及文件：**
- 新建：`admin/app/actions/deals.ts`
- 新建：`admin/components/deal-toggle.tsx`
- 修改：`admin/app/(dashboard)/deals/page.tsx`

### Step 1：新建 `admin/app/actions/deals.ts`

```ts
'use server'

import { revalidatePath } from 'next/cache'
import { createClient } from '@/lib/supabase/server'

export async function toggleDealActive(dealId: string, isActive: boolean) {
  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()
  if (!user) throw new Error('Unauthorized')

  const { error } = await supabase
    .from('deals')
    .update({ is_active: isActive })
    .eq('id', dealId)

  if (error) throw new Error(error.message)
  revalidatePath('/deals')
}
```

### Step 2：新建 `admin/components/deal-toggle.tsx`

```tsx
'use client'

import { useState, useTransition } from 'react'
import { toggleDealActive } from '@/app/actions/deals'
import { toast } from 'sonner'

export default function DealToggle({
  dealId,
  initialIsActive,
  isExpired,
}: {
  dealId: string
  initialIsActive: boolean
  isExpired: boolean
}) {
  const [isActive, setIsActive] = useState(initialIsActive)
  const [isPending, startTransition] = useTransition()

  // 已过期的 deal 不可操作
  if (isExpired) {
    return (
      <span className="px-2 py-0.5 rounded-full text-xs font-medium bg-red-100 text-red-700">
        Expired
      </span>
    )
  }

  function handleToggle() {
    const next = !isActive
    setIsActive(next)
    startTransition(async () => {
      try {
        await toggleDealActive(dealId, next)
        toast.success(next ? 'Deal activated' : 'Deal deactivated')
      } catch {
        setIsActive(!next) // 回滚
        toast.error('Failed to update deal status')
      }
    })
  }

  return (
    <button
      onClick={handleToggle}
      disabled={isPending}
      className={`px-2 py-0.5 rounded-full text-xs font-medium transition-colors disabled:opacity-50 cursor-pointer ${
        isActive
          ? 'bg-green-100 text-green-700 hover:bg-green-200'
          : 'bg-gray-100 text-gray-500 hover:bg-gray-200'
      }`}
    >
      {isActive ? 'Active' : 'Inactive'}
    </button>
  )
}
```

### Step 3：修改 `admin/app/(dashboard)/deals/page.tsx`

在文件顶部导入：
```ts
import DealToggle from '@/components/deal-toggle'
```

将 `<DealStatusBadge>` 组件整体替换为 `<DealToggle>`：

```tsx
// 删除整个 DealStatusBadge 函数组件

// 将表格 status 列从：
<td className="px-4 py-3">
  <DealStatusBadge isActive={d.is_active} expiresAt={d.expires_at} />
</td>

// 改为：
<td className="px-4 py-3">
  <DealToggle
    dealId={d.id}
    initialIsActive={d.is_active}
    isExpired={new Date(d.expires_at) < new Date()}
  />
</td>
```

**验证：**
- Deals 页面的 status 列变成可点击按钮
- 点击 Active → 变为 Inactive，右上角显示 toast
- 刷新后状态保持

---

## Task 4：订单管理页

**背景：** Admin 需要查看所有订单，并处理 `refund_requested` 状态的退款申请。

**注意：** `orders` 表没有 `merchant_id` 列，商家信息需通过 `deals.merchant_id` 关联获取。

**涉及文件：**
- 新建：`admin/app/actions/orders.ts`
- 新建：`admin/components/order-refund-buttons.tsx`
- 新建：`admin/app/(dashboard)/orders/page.tsx`
- 修改：`admin/components/sidebar.tsx`

### Step 1：新建 `admin/app/actions/orders.ts`

```ts
'use server'

import { revalidatePath } from 'next/cache'
import { createClient } from '@/lib/supabase/server'

export async function approveRefund(orderId: string) {
  const supabase = await createClient()
  const { error } = await supabase
    .from('orders')
    .update({ status: 'refunded' })
    .eq('id', orderId)

  if (error) throw new Error(error.message)
  revalidatePath('/orders')
}

export async function rejectRefund(orderId: string) {
  const supabase = await createClient()
  // 拒绝退款：恢复为 used 状态
  const { error } = await supabase
    .from('orders')
    .update({ status: 'used' })
    .eq('id', orderId)

  if (error) throw new Error(error.message)
  revalidatePath('/orders')
}
```

### Step 2：新建 `admin/components/order-refund-buttons.tsx`

```tsx
'use client'

import { useState, useTransition } from 'react'
import { approveRefund, rejectRefund } from '@/app/actions/orders'
import { toast } from 'sonner'

const STATUS_STYLES: Record<string, string> = {
  unused:           'bg-blue-100 text-blue-700',
  used:             'bg-gray-100 text-gray-600',
  refunded:         'bg-purple-100 text-purple-700',
  refund_requested: 'bg-orange-100 text-orange-700',
  expired:          'bg-red-100 text-red-700',
}

const STATUS_LABELS: Record<string, string> = {
  unused:           'Unused',
  used:             'Used',
  refunded:         'Refunded',
  refund_requested: 'Refund Requested',
  expired:          'Expired',
}

export default function OrderRefundButtons({
  orderId,
  initialStatus,
}: {
  orderId: string
  initialStatus: string
}) {
  const [status, setStatus] = useState(initialStatus)
  const [isPending, startTransition] = useTransition()

  // 非 refund_requested 状态只显示标签
  if (status !== 'refund_requested') {
    return (
      <span className={`px-2 py-0.5 rounded-full text-xs font-medium ${STATUS_STYLES[status] ?? STATUS_STYLES.used}`}>
        {STATUS_LABELS[status] ?? status}
      </span>
    )
  }

  function handle(action: 'approve' | 'reject') {
    startTransition(async () => {
      try {
        if (action === 'approve') {
          await approveRefund(orderId)
          setStatus('refunded')
          toast.success('Refund approved')
        } else {
          await rejectRefund(orderId)
          setStatus('used')
          toast.success('Refund rejected')
        }
      } catch {
        toast.error('Action failed. Check permissions.')
      }
    })
  }

  return (
    <div className="flex items-center gap-2">
      <span className="text-xs text-orange-600 font-medium">Refund Req.</span>
      <button
        onClick={() => handle('approve')}
        disabled={isPending}
        className="px-2 py-1 text-xs font-medium bg-green-600 text-white rounded-lg hover:bg-green-700 disabled:opacity-50 transition-colors"
      >
        Approve
      </button>
      <button
        onClick={() => handle('reject')}
        disabled={isPending}
        className="px-2 py-1 text-xs font-medium bg-red-100 text-red-700 rounded-lg hover:bg-red-200 disabled:opacity-50 transition-colors"
      >
        Reject
      </button>
    </div>
  )
}
```

### Step 3：新建 `admin/app/(dashboard)/orders/page.tsx`

```tsx
import { createClient } from '@/lib/supabase/server'
import { redirect } from 'next/navigation'
import OrderRefundButtons from '@/components/order-refund-buttons'

export default async function OrdersPage() {
  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()
  const { data: profile } = await supabase
    .from('users').select('role').eq('id', user!.id).single()

  if (profile?.role !== 'admin') redirect('/dashboard')

  // orders 通过 deal_id → deals.merchant_id → merchants.name 获取商家名
  const { data: orders } = await supabase
    .from('orders')
    .select(`
      id,
      total_amount,
      quantity,
      status,
      refund_reason,
      created_at,
      users ( email ),
      deals ( title, merchants ( name ) )
    `)
    .order('created_at', { ascending: false })
    .limit(100)

  const refundCount = orders?.filter(o => o.status === 'refund_requested').length ?? 0

  return (
    <div>
      <div className="flex items-center justify-between mb-6">
        <h1 className="text-2xl font-bold text-gray-900">Orders</h1>
        {refundCount > 0 && (
          <span className="text-sm bg-orange-100 text-orange-700 px-3 py-1 rounded-full font-medium">
            {refundCount} refund {refundCount === 1 ? 'request' : 'requests'}
          </span>
        )}
      </div>

      <div className="bg-white rounded-xl border border-gray-200 overflow-hidden">
        <table className="w-full text-sm">
          <thead className="bg-gray-50 border-b border-gray-200">
            <tr>
              <th className="text-left px-4 py-3 font-medium text-gray-600">Deal</th>
              <th className="text-left px-4 py-3 font-medium text-gray-600">Merchant</th>
              <th className="text-left px-4 py-3 font-medium text-gray-600">Customer</th>
              <th className="text-left px-4 py-3 font-medium text-gray-600">Amount</th>
              <th className="text-left px-4 py-3 font-medium text-gray-600">Status</th>
              <th className="text-left px-4 py-3 font-medium text-gray-600">Date</th>
            </tr>
          </thead>
          <tbody className="divide-y divide-gray-100">
            {(orders as any[])?.map(o => (
              <tr
                key={o.id}
                className={o.status === 'refund_requested' ? 'bg-orange-50/60' : 'hover:bg-gray-50'}
              >
                <td className="px-4 py-3 font-medium text-gray-900">{o.deals?.title ?? '—'}</td>
                <td className="px-4 py-3 text-gray-600">{o.deals?.merchants?.name ?? '—'}</td>
                <td className="px-4 py-3 text-gray-600">{o.users?.email ?? '—'}</td>
                <td className="px-4 py-3 text-gray-900">
                  ${o.total_amount}
                  {o.quantity > 1 && (
                    <span className="text-gray-400 text-xs ml-1">×{o.quantity}</span>
                  )}
                </td>
                <td className="px-4 py-3">
                  <OrderRefundButtons orderId={o.id} initialStatus={o.status} />
                </td>
                <td className="px-4 py-3 text-gray-500">
                  {new Date(o.created_at).toLocaleDateString()}
                </td>
              </tr>
            ))}
          </tbody>
        </table>
        {(!orders || orders.length === 0) && (
          <p className="text-center text-gray-400 py-8">No orders yet</p>
        )}
      </div>
    </div>
  )
}
```

### Step 4：在侧边栏添加 Orders 菜单

修改 `admin/components/sidebar.tsx`，在 `adminNav` 数组中加入 Orders：

```ts
const adminNav = [
  { href: '/dashboard', label: 'Overview',  icon: '📊' },
  { href: '/users',     label: 'Users',     icon: '👥' },
  { href: '/merchants', label: 'Merchants', icon: '🏪' },
  { href: '/deals',     label: 'Deals',     icon: '🏷️' },
  { href: '/orders',    label: 'Orders',    icon: '📦' },  // ← 新增
]
```

**验证：**
- 侧边栏出现"📦 Orders"
- 点击进入 Orders 页面，显示订单列表
- `refund_requested` 状态的行背景为淡橙色，显示 Approve/Reject 按钮
- 点击 Approve → 状态变为 Refunded，显示绿色 toast

---

## 执行顺序

| # | Task | 操作位置 | 优先级 |
|---|------|---------|--------|
| 1 | 修复 RLS 策略 | Supabase SQL Editor | **必须先做** |
| 2 | Dashboard 告警 | VS Code / Cursor | 高 |
| 3 | Deal 上下架开关 | VS Code / Cursor | 高 |
| 4 | 订单管理页 | VS Code / Cursor | 高 |

**给 Cursor 的使用建议：**
- 每个 Task 单独开一个对话或 Composer，不要一次全部粘贴
- Task 1 直接在 Supabase 执行，不需要 Cursor
- 每个 Task 完成后在浏览器验证，再进行下一个
- 如遇到 TypeScript 类型错误，在相关 `.select()` 调用后加 `as any[]` 即可绕过，后续再完善类型
