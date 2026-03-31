import { createClient } from '@/lib/supabase/server'
import { getServiceRoleClient } from '@/lib/supabase/service'
import { redirect } from 'next/navigation'
import CategoriesManager from './categories-manager'

export default async function CategoriesPage() {
  // 权限校验
  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()
  const { data: profile } = await supabase
    .from('users')
    .select('role')
    .eq('id', user!.id)
    .single()

  if (profile?.role !== 'admin') redirect('/dashboard')

  // 获取所有分类
  const serviceClient = getServiceRoleClient()
  const { data: categories } = await serviceClient
    .from('categories')
    .select('id, name, icon, order')
    .order('order')

  // 获取每个分类下的商家数量
  const { data: counts } = await serviceClient
    .from('merchant_categories')
    .select('category_id')

  // 统计每个分类的商家数
  const countMap: Record<number, number> = {}
  if (counts) {
    for (const row of counts) {
      countMap[row.category_id] = (countMap[row.category_id] || 0) + 1
    }
  }

  const total = categories?.length ?? 0

  return (
    <div>
      <div className="mb-6">
        <h1 className="text-2xl font-bold text-gray-900">Categories</h1>
        <p className="text-sm text-gray-500 mt-1">
          Manage global categories displayed on the customer app homepage. Merchants select these categories for their stores.
        </p>
      </div>

      {/* 统计概览 */}
      <div className="grid grid-cols-2 gap-4 mb-8">
        <div className="bg-white rounded-xl border border-gray-200 px-5 py-4">
          <p className="text-xs font-medium text-gray-500 uppercase tracking-wide">Total Categories</p>
          <p className="text-3xl font-bold text-gray-900 mt-1">{total}</p>
        </div>
        <div className="bg-white rounded-xl border border-gray-200 px-5 py-4">
          <p className="text-xs font-medium text-blue-600 uppercase tracking-wide">With Merchants</p>
          <p className="text-3xl font-bold text-blue-600 mt-1">
            {Object.keys(countMap).length}
          </p>
        </div>
      </div>

      <CategoriesManager
        initialCategories={(categories ?? []).map(c => ({
          ...c,
          merchant_count: countMap[c.id] || 0,
        }))}
      />
    </div>
  )
}
