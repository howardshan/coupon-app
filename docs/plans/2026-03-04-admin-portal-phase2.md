# Admin Portal Phase 2 Implementation Plan

**Goal:** 完善 DealJoy 后台管理系统，补全 Deal 管理、订单管理、店铺资料编辑、通知反馈等核心功能。

**Architecture:** Next.js 15 App Router，Server Components 负责数据获取，Server Actions 处理数据变更，Client Components 只负责交互 UI。Supabase SSR 处理服务端认证。

**Tech Stack:** Next.js 15, TypeScript, Tailwind CSS, Supabase JS SDK (`@supabase/ssr`), Sonner（Toast 通知）

---

## 背景与现状

### 项目路径
- 后台管理系统：`coupon-app/admin/`
- Flutter 移动端：`coupon-app/deal_joy/`
- Supabase 数据库：共享，通过 `.env.local` 中的 key 连接

### 已完成
- 登录页（`app/login/page.tsx`）
- 中间件路由守卫（`middleware.ts`）
- 用户列表 + 角色管理（`app/(dashboard)/users/page.tsx`）
- 商家列表 + 审核（`app/(dashboard)/merchants/page.tsx`）
- Deal 列表（只读，`app/(dashboard)/deals/page.tsx`）
- Server Actions（`app/actions/admin.ts`）

### 数据库关键表结构
```sql
-- users: id, email, full_name, role(user|merchant|admin), created_at
-- merchants: id, name, description, category, address, phone, status(pending|approved|rejected), user_id, created_at
-- deals: id, title, description, price, original_price, quantity, sold_count, status(active|inactive|expired), merchant_id, created_at, expires_at
-- orders: id, user_id, deal_id, merchant_id, amount, status(unused|used|refunded|refund_requested|expired), created_at
-- coupons: id, order_id, deal_id, merchant_id, code, status(unused|used|expired|refunded)
```

---

## Task 1：修复 RLS 策略（Supabase SQL）

**背景：** admin 账号当前只能看到自己一个用户，且无法更新其他用户 role 或商家 status，因为 RLS 策略限制。

**操作：** 在 Supabase Dashboard → SQL Editor 中运行以下 SQL。

**Step 1：运行 SQL**

```sql
-- 1. 让 admin 能看到所有用户
DROP POLICY IF EXISTS "users_select_own" ON public.users;
CREATE POLICY "users_select_any" ON public.users
  FOR SELECT USING (
    auth.uid() = id
    OR EXISTS (
      SELECT 1 FROM public.users WHERE id = auth.uid() AND role = 'admin'
    )
  );

-- 2. 让 admin 能更新任何用户的 role
CREATE POLICY "admin_update_any_user" ON public.users
  FOR UPDATE USING (
    auth.uid() = id
    OR EXISTS (
      SELECT 1 FROM public.users WHERE id = auth.uid() AND role = 'admin'
    )
  );

-- 3. 让 admin 能更新任何商家的 status
CREATE POLICY "admin_update_merchant_status" ON public.merchants
  FOR UPDATE USING (
    user_id = auth.uid()
    OR EXISTS (
      SELECT 1 FROM public.users WHERE id = auth.uid() AND role = 'admin'
    )
  );
```

**Step 2：验证**
- 刷新 `http://localhost:3000/users`，应看到所有注册用户
- 尝试修改某用户 role，不应报错

---

## Task 2：添加 Toast 通知（全局反馈）

**背景：** 当前操作（角色修改、商家审核）没有成功/失败的视觉反馈，用户体验差。

**Files:**
- 安装依赖：`sonner`
- Modify: `admin/app/layout.tsx`
- Modify: `admin/components/role-select.tsx`
- Modify: `admin/components/merchant-action-buttons.tsx`

**Step 1：安装 sonner**

```bash
cd coupon-app/admin
npm install sonner
```

**Step 2：在根 layout 添加 Toaster**

修改 `admin/app/layout.tsx`，在 `<body>` 内加入：

```tsx
import { Toaster } from 'sonner'

// 在 <body> 最后加
<Toaster position="top-right" richColors />
```

**Step 3：在 RoleSelect 中使用 toast**

修改 `admin/components/role-select.tsx`：

```tsx
import { toast } from 'sonner'

// 成功时：
toast.success(`Role updated to ${newRole}`)

// 失败时：
toast.error('Failed to update role. Check permissions.')
```

**Step 4：在 MerchantActionButtons 中使用 toast**

修改 `admin/components/merchant-action-buttons.tsx`：

```tsx
import { toast } from 'sonner'

// Approve 成功：
toast.success('Merchant approved')

// Reject 成功：
toast.success('Merchant rejected')

// 失败：
toast.error('Action failed. Check RLS policies.')
```

**Step 5：验证**
- 修改一个用户 role，右上角应出现绿色 toast
- 故意断网操作，应出现红色 toast

---

## Task 3：Deal 创建表单（商家端）

**背景：** 商家需要从 Web 端创建新的优惠 Deal。

**Files:**
- Create: `admin/components/create-deal-dialog.tsx`
- Create: `admin/app/actions/deals.ts`
- Modify: `admin/app/(dashboard)/deals/page.tsx`

**Step 1：创建 Server Action**

新建 `admin/app/actions/deals.ts`：

```ts
'use server'

import { revalidatePath } from 'next/cache'
import { createClient } from '@/lib/supabase/server'

export async function createDeal(formData: FormData) {
  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()
  if (!user) throw new Error('Unauthorized')

  // 获取当前用户的商家 ID
  const { data: merchant } = await supabase
    .from('merchants')
    .select('id')
    .eq('user_id', user.id)
    .single()

  if (!merchant) throw new Error('No merchant found for this user')

  const title = formData.get('title') as string
  const description = formData.get('description') as string
  const price = parseFloat(formData.get('price') as string)
  const originalPrice = parseFloat(formData.get('original_price') as string)
  const quantity = parseInt(formData.get('quantity') as string)
  const expiresAt = formData.get('expires_at') as string

  const { error } = await supabase.from('deals').insert({
    title,
    description,
    price,
    original_price: originalPrice || null,
    quantity,
    expires_at: expiresAt || null,
    merchant_id: merchant.id,
    status: 'active',
  })

  if (error) throw new Error(error.message)
  revalidatePath('/deals')
}

export async function updateDealStatus(
  dealId: string,
  status: 'active' | 'inactive'
) {
  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()
  if (!user) throw new Error('Unauthorized')

  const { error } = await supabase
    .from('deals')
    .update({ status })
    .eq('id', dealId)

  if (error) throw new Error(error.message)
  revalidatePath('/deals')
}
```

**Step 2：创建 CreateDealDialog 组件**

新建 `admin/components/create-deal-dialog.tsx`：

```tsx
'use client'

import { useState, useTransition } from 'react'
import { createDeal } from '@/app/actions/deals'
import { toast } from 'sonner'

export default function CreateDealDialog() {
  const [open, setOpen] = useState(false)
  const [isPending, startTransition] = useTransition()

  function handleSubmit(e: React.FormEvent<HTMLFormElement>) {
    e.preventDefault()
    const formData = new FormData(e.currentTarget)
    startTransition(async () => {
      try {
        await createDeal(formData)
        toast.success('Deal created successfully')
        setOpen(false)
      } catch (err: any) {
        toast.error(err.message || 'Failed to create deal')
      }
    })
  }

  return (
    <>
      <button
        onClick={() => setOpen(true)}
        className="px-4 py-2 bg-blue-600 text-white text-sm font-medium rounded-lg hover:bg-blue-700 transition-colors"
      >
        + Create Deal
      </button>

      {open && (
        <div className="fixed inset-0 bg-black/40 flex items-center justify-center z-50">
          <div className="bg-white rounded-2xl shadow-xl w-full max-w-md p-6">
            <h2 className="text-lg font-bold text-gray-900 mb-4">Create New Deal</h2>

            <form onSubmit={handleSubmit} className="space-y-4">
              <Field label="Title" name="title" required />
              <Field label="Description" name="description" textarea />
              <div className="grid grid-cols-2 gap-3">
                <Field label="Sale Price ($)" name="price" type="number" step="0.01" required />
                <Field label="Original Price ($)" name="original_price" type="number" step="0.01" />
              </div>
              <div className="grid grid-cols-2 gap-3">
                <Field label="Quantity" name="quantity" type="number" required />
                <Field label="Expires At" name="expires_at" type="date" />
              </div>

              <div className="flex gap-3 pt-2">
                <button
                  type="button"
                  onClick={() => setOpen(false)}
                  className="flex-1 py-2 border border-gray-300 rounded-lg text-sm hover:bg-gray-50"
                >
                  Cancel
                </button>
                <button
                  type="submit"
                  disabled={isPending}
                  className="flex-1 py-2 bg-blue-600 text-white rounded-lg text-sm font-medium hover:bg-blue-700 disabled:opacity-50"
                >
                  {isPending ? 'Creating...' : 'Create'}
                </button>
              </div>
            </form>
          </div>
        </div>
      )}
    </>
  )
}

function Field({
  label, name, textarea, ...props
}: { label: string; name: string; textarea?: boolean } & React.InputHTMLAttributes<HTMLInputElement>) {
  const cls = "w-full px-3 py-2 border border-gray-300 rounded-lg text-sm text-gray-900 focus:outline-none focus:ring-2 focus:ring-blue-500"
  return (
    <div>
      <label className="block text-xs font-medium text-gray-600 mb-1">{label}</label>
      {textarea
        ? <textarea name={name} rows={3} className={cls} />
        : <input name={name} {...props} className={cls} />
      }
    </div>
  )
}
```

**Step 3：在 Deals 页面加入创建按钮**

修改 `admin/app/(dashboard)/deals/page.tsx`，在商家 role 下显示按钮：

```tsx
import CreateDealDialog from '@/components/create-deal-dialog'

// 在页面标题行：
{profile?.role === 'merchant' && <CreateDealDialog />}
```

**Step 4：验证**
- 用商家账号登录
- Deals 页右上角应出现"+ Create Deal"按钮
- 填写表单提交，Deal 应出现在列表中
- admin 账号不应看到此按钮

---

## Task 4：Deal 上架/下架（admin + merchant）

**背景：** 需要能快速切换 Deal 的激活状态。

**Files:**
- Create: `admin/components/deal-status-toggle.tsx`
- Modify: `admin/app/(dashboard)/deals/page.tsx`

**Step 1：创建 DealStatusToggle 组件**

新建 `admin/components/deal-status-toggle.tsx`：

```tsx
'use client'

import { useState, useTransition } from 'react'
import { updateDealStatus } from '@/app/actions/deals'
import { toast } from 'sonner'

export default function DealStatusToggle({
  dealId,
  initialStatus,
}: {
  dealId: string
  initialStatus: string
}) {
  const [status, setStatus] = useState(initialStatus)
  const [isPending, startTransition] = useTransition()

  function toggle() {
    const newStatus = status === 'active' ? 'inactive' : 'active'
    startTransition(async () => {
      try {
        await updateDealStatus(dealId, newStatus)
        setStatus(newStatus)
        toast.success(`Deal ${newStatus === 'active' ? 'activated' : 'deactivated'}`)
      } catch {
        toast.error('Failed to update status')
      }
    })
  }

  return (
    <button
      onClick={toggle}
      disabled={isPending}
      className={`px-2 py-0.5 rounded-full text-xs font-medium transition-colors disabled:opacity-50 ${
        status === 'active'
          ? 'bg-green-100 text-green-700 hover:bg-green-200'
          : 'bg-gray-100 text-gray-500 hover:bg-gray-200'
      }`}
    >
      {status === 'active' ? 'Active' : 'Inactive'}
    </button>
  )
}
```

**Step 2：在 Deals 页面替换静态状态标签**

修改 `admin/app/(dashboard)/deals/page.tsx`，将状态列改为：

```tsx
import DealStatusToggle from '@/components/deal-status-toggle'

// 在表格 status 列：
<td className="px-4 py-3">
  {d.status === 'expired'
    ? <span className="px-2 py-0.5 rounded-full text-xs font-medium bg-red-100 text-red-700">expired</span>
    : <DealStatusToggle dealId={d.id} initialStatus={d.status} />
  }
</td>
```

**Step 3：验证**
- 点击 Active 标签，应变为 Inactive
- 刷新页面，状态应保持

---

## Task 5：订单管理页（admin + merchant）

**背景：** 查看订单列表，处理退款申请。

**Files:**
- Create: `admin/app/(dashboard)/orders/page.tsx`
- Create: `admin/app/actions/orders.ts`
- Create: `admin/components/refund-action-button.tsx`
- Modify: `admin/components/sidebar.tsx`

**Step 1：添加 sidebar 导航项**

修改 `admin/components/sidebar.tsx`，在 `adminNav` 和 `merchantNav` 中加入 Orders：

```ts
// adminNav 中加：
{ href: '/orders', label: 'Orders', icon: '📦' },

// merchantNav 中加：
{ href: '/orders', label: 'Orders', icon: '📦' },
```

**Step 2：创建退款 Server Action**

新建 `admin/app/actions/orders.ts`：

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
  const { error } = await supabase
    .from('orders')
    .update({ status: 'used' }) // 拒绝退款，恢复为 used
    .eq('id', orderId)

  if (error) throw new Error(error.message)
  revalidatePath('/orders')
}
```

**Step 3：创建 RefundActionButton 组件**

新建 `admin/components/refund-action-button.tsx`：

```tsx
'use client'

import { useState, useTransition } from 'react'
import { approveRefund, rejectRefund } from '@/app/actions/orders'
import { toast } from 'sonner'

const statusLabels: Record<string, { label: string; style: string }> = {
  unused: { label: 'Unused', style: 'bg-blue-100 text-blue-700' },
  used: { label: 'Used', style: 'bg-gray-100 text-gray-600' },
  refunded: { label: 'Refunded', style: 'bg-purple-100 text-purple-700' },
  refund_requested: { label: 'Refund Requested', style: 'bg-orange-100 text-orange-700' },
  expired: { label: 'Expired', style: 'bg-red-100 text-red-700' },
}

export default function RefundActionButton({
  orderId,
  initialStatus,
}: {
  orderId: string
  initialStatus: string
}) {
  const [status, setStatus] = useState(initialStatus)
  const [isPending, startTransition] = useTransition()

  if (status !== 'refund_requested') {
    const config = statusLabels[status] ?? statusLabels.used
    return (
      <span className={`px-2 py-0.5 rounded-full text-xs font-medium ${config.style}`}>
        {config.label}
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
        toast.error('Action failed')
      }
    })
  }

  return (
    <div className="flex items-center gap-2">
      <span className="text-xs text-orange-600 font-medium">Refund Req.</span>
      <button
        onClick={() => handle('approve')}
        disabled={isPending}
        className="px-2 py-0.5 text-xs bg-green-600 text-white rounded-lg hover:bg-green-700 disabled:opacity-50"
      >
        Approve
      </button>
      <button
        onClick={() => handle('reject')}
        disabled={isPending}
        className="px-2 py-0.5 text-xs bg-red-100 text-red-700 rounded-lg hover:bg-red-200 disabled:opacity-50"
      >
        Reject
      </button>
    </div>
  )
}
```

**Step 4：创建 Orders 页面**

新建 `admin/app/(dashboard)/orders/page.tsx`：

```tsx
import { createClient } from '@/lib/supabase/server'
import RefundActionButton from '@/components/refund-action-button'

export default async function OrdersPage() {
  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()
  const { data: profile } = await supabase.from('users').select('role').eq('id', user!.id).single()

  let orders
  if (profile?.role === 'admin') {
    const { data } = await supabase
      .from('orders')
      .select('id, amount, status, created_at, users(email), deals(title)')
      .order('created_at', { ascending: false })
      .limit(100)
    orders = data
  } else {
    const { data: merchant } = await supabase
      .from('merchants').select('id').eq('user_id', user!.id).single()
    if (merchant) {
      const { data } = await supabase
        .from('orders')
        .select('id, amount, status, created_at, users(email), deals(title)')
        .eq('merchant_id', merchant.id)
        .order('created_at', { ascending: false })
        .limit(100)
      orders = data
    }
  }

  const refundCount = orders?.filter(o => o.status === 'refund_requested').length ?? 0

  return (
    <div>
      <div className="flex items-center justify-between mb-6">
        <h1 className="text-2xl font-bold text-gray-900">Orders</h1>
        {refundCount > 0 && (
          <span className="text-sm bg-orange-100 text-orange-700 px-3 py-1 rounded-full font-medium">
            {refundCount} refund requests
          </span>
        )}
      </div>

      <div className="bg-white rounded-xl border border-gray-200 overflow-hidden">
        <table className="w-full text-sm">
          <thead className="bg-gray-50 border-b border-gray-200">
            <tr>
              <th className="text-left px-4 py-3 font-medium text-gray-600">Deal</th>
              <th className="text-left px-4 py-3 font-medium text-gray-600">Customer</th>
              <th className="text-left px-4 py-3 font-medium text-gray-600">Amount</th>
              <th className="text-left px-4 py-3 font-medium text-gray-600">Status</th>
              <th className="text-left px-4 py-3 font-medium text-gray-600">Date</th>
            </tr>
          </thead>
          <tbody className="divide-y divide-gray-100">
            {orders?.map((o: any) => (
              <tr key={o.id} className={o.status === 'refund_requested' ? 'bg-orange-50/50' : 'hover:bg-gray-50'}>
                <td className="px-4 py-3 font-medium text-gray-900">{o.deals?.title ?? '—'}</td>
                <td className="px-4 py-3 text-gray-600">{o.users?.email ?? '—'}</td>
                <td className="px-4 py-3 text-gray-900">${o.amount}</td>
                <td className="px-4 py-3">
                  <RefundActionButton orderId={o.id} initialStatus={o.status} />
                </td>
                <td className="px-4 py-3 text-gray-500">
                  {new Date(o.created_at).toLocaleDateString()}
                </td>
              </tr>
            ))}
          </tbody>
        </table>
        {(!orders || orders.length === 0) && (
          <p className="text-center text-gray-400 py-8">No orders found</p>
        )}
      </div>
    </div>
  )
}
```

**Step 5：添加 RLS（SQL Editor）**

```sql
-- admin 查看所有订单
CREATE POLICY "admin_select_all_orders" ON public.orders
  FOR SELECT USING (
    user_id = auth.uid()
    OR EXISTS (SELECT 1 FROM public.users WHERE id = auth.uid() AND role = 'admin')
    OR merchant_id IN (SELECT id FROM public.merchants WHERE user_id = auth.uid())
  );

-- admin/merchant 更新订单状态
CREATE POLICY "admin_merchant_update_order" ON public.orders
  FOR UPDATE USING (
    EXISTS (SELECT 1 FROM public.users WHERE id = auth.uid() AND role = 'admin')
    OR merchant_id IN (SELECT id FROM public.merchants WHERE user_id = auth.uid())
  );
```

**Step 6：验证**
- 侧边栏出现"Orders"菜单项
- 订单列表正常显示
- refund_requested 状态的订单显示 Approve/Reject 按钮

---

## Task 6：店铺资料管理（商家端）

**背景：** 商家需要查看和编辑自己的店铺信息（名称、地址、电话、简介等）。

**Files:**
- Create: `admin/app/(dashboard)/store/page.tsx`
- Create: `admin/app/actions/store.ts`
- Modify: `admin/components/sidebar.tsx`

**Step 1：添加 sidebar 导航项**

修改 `admin/components/sidebar.tsx`，在 `merchantNav` 中加入：

```ts
{ href: '/store', label: 'My Store', icon: '🏪' },
```

**Step 2：创建 Store Server Action**

新建 `admin/app/actions/store.ts`：

```ts
'use server'

import { revalidatePath } from 'next/cache'
import { createClient } from '@/lib/supabase/server'

export async function updateStore(formData: FormData) {
  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()
  if (!user) throw new Error('Unauthorized')

  const { error } = await supabase
    .from('merchants')
    .update({
      name: formData.get('name') as string,
      description: formData.get('description') as string,
      address: formData.get('address') as string,
      phone: formData.get('phone') as string,
    })
    .eq('user_id', user.id)

  if (error) throw new Error(error.message)
  revalidatePath('/store')
}
```

**Step 3：创建 Store 页面**

新建 `admin/app/(dashboard)/store/page.tsx`：

```tsx
import { createClient } from '@/lib/supabase/server'
import { redirect } from 'next/navigation'
import StoreForm from '@/components/store-form'

export default async function StorePage() {
  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()
  const { data: profile } = await supabase.from('users').select('role').eq('id', user!.id).single()

  if (profile?.role !== 'merchant') redirect('/dashboard')

  const { data: merchant } = await supabase
    .from('merchants')
    .select('id, name, description, category, address, phone, status')
    .eq('user_id', user!.id)
    .single()

  return (
    <div>
      <h1 className="text-2xl font-bold text-gray-900 mb-6">My Store</h1>
      {merchant
        ? <StoreForm merchant={merchant} />
        : <p className="text-gray-400">No store profile found. Contact admin.</p>
      }
    </div>
  )
}
```

**Step 4：创建 StoreForm 组件**

新建 `admin/components/store-form.tsx`：

```tsx
'use client'

import { useTransition } from 'react'
import { updateStore } from '@/app/actions/store'
import { toast } from 'sonner'

interface StoreFormProps {
  merchant: {
    name: string
    description: string | null
    category: string | null
    address: string | null
    phone: string | null
    status: string
  }
}

const statusStyles: Record<string, string> = {
  approved: 'bg-green-100 text-green-700',
  pending: 'bg-yellow-100 text-yellow-700',
  rejected: 'bg-red-100 text-red-700',
}

export default function StoreForm({ merchant }: StoreFormProps) {
  const [isPending, startTransition] = useTransition()

  function handleSubmit(e: React.FormEvent<HTMLFormElement>) {
    e.preventDefault()
    const formData = new FormData(e.currentTarget)
    startTransition(async () => {
      try {
        await updateStore(formData)
        toast.success('Store profile updated')
      } catch (err: any) {
        toast.error(err.message || 'Failed to update')
      }
    })
  }

  return (
    <div className="max-w-lg">
      <div className="flex items-center gap-3 mb-6">
        <span className={`px-3 py-1 rounded-full text-sm font-medium ${statusStyles[merchant.status] ?? ''}`}>
          {merchant.status}
        </span>
        {merchant.category && (
          <span className="text-sm text-gray-500">{merchant.category}</span>
        )}
      </div>

      <form onSubmit={handleSubmit} className="bg-white rounded-xl border border-gray-200 p-6 space-y-4">
        <Field label="Store Name" name="name" defaultValue={merchant.name} required />
        <Field label="Description" name="description" textarea defaultValue={merchant.description ?? ''} />
        <Field label="Address" name="address" defaultValue={merchant.address ?? ''} />
        <Field label="Phone" name="phone" defaultValue={merchant.phone ?? ''} />

        <button
          type="submit"
          disabled={isPending}
          className="w-full py-2 bg-blue-600 text-white rounded-lg text-sm font-medium hover:bg-blue-700 disabled:opacity-50 transition-colors"
        >
          {isPending ? 'Saving...' : 'Save Changes'}
        </button>
      </form>
    </div>
  )
}

function Field({
  label, name, textarea, defaultValue, required,
}: {
  label: string; name: string; textarea?: boolean
  defaultValue?: string; required?: boolean
}) {
  const cls = "w-full px-3 py-2 border border-gray-300 rounded-lg text-sm text-gray-900 focus:outline-none focus:ring-2 focus:ring-blue-500"
  return (
    <div>
      <label className="block text-xs font-medium text-gray-600 mb-1">{label}</label>
      {textarea
        ? <textarea name={name} rows={3} defaultValue={defaultValue} className={cls} />
        : <input name={name} defaultValue={defaultValue} required={required} className={cls} />
      }
    </div>
  )
}
```

**Step 5：验证**
- 商家账号登录，侧边栏显示"My Store"
- 填写表单并保存，数据持久化
- admin 账号不显示此菜单

---

## 最终文件结构

完成后 `admin/` 目录新增文件：

```
admin/
├── app/
│   ├── actions/
│   │   ├── admin.ts       ✅ 已完成
│   │   ├── deals.ts       ← Task 3
│   │   ├── orders.ts      ← Task 5
│   │   └── store.ts       ← Task 6
│   └── (dashboard)/
│       ├── orders/
│       │   └── page.tsx   ← Task 5
│       └── store/
│           └── page.tsx   ← Task 6
└── components/
    ├── role-select.tsx             ✅ 已完成
    ├── merchant-action-buttons.tsx ✅ 已完成
    ├── create-deal-dialog.tsx      ← Task 3
    ├── deal-status-toggle.tsx      ← Task 4
    ├── refund-action-button.tsx    ← Task 5
    └── store-form.tsx              ← Task 6
```

## 执行顺序

| Task | 优先级 | 时间估计 |
|------|--------|---------|
| Task 1：修复 RLS | 必须先做 | 5 分钟 |
| Task 2：Toast 通知 | 基础体验 | 10 分钟 |
| Task 3：Deal 创建 | 商家核心功能 | 20 分钟 |
| Task 4：Deal 上下架 | 配合 Task 3 | 10 分钟 |
| Task 5：订单管理 | admin 核心 | 25 分钟 |
| Task 6：店铺管理 | 商家补全 | 15 分钟 |
