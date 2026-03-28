import { createClient } from '@/lib/supabase/server'
import { getServiceRoleClient } from '@/lib/supabase/service'
import { redirect } from 'next/navigation'
import SplashConfigEditor from './splash-config-editor'

export default async function SplashConfigPage() {
  // 权限校验
  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()
  const { data: profile } = await supabase
    .from('users')
    .select('role')
    .eq('id', user!.id)
    .single()

  if (profile?.role !== 'admin') redirect('/dashboard')

  // 获取所有 splash 配置（含 active 和 draft）
  const serviceClient = getServiceRoleClient()
  const { data: configs } = await serviceClient
    .from('splash_configs')
    .select('*')
    .order('created_at', { ascending: false })

  const activeConfig = configs?.find(c => c.is_active) ?? null

  return (
    <div>
      <div className="mb-6">
        <h1 className="text-2xl font-bold text-gray-900">Splash Screen</h1>
        <p className="text-sm text-gray-500 mt-1">
          Configure the full-screen ad splash shown every time the app launches.
          Users can skip via countdown button. Empty slides = splash is skipped.
        </p>
      </div>

      {/* 状态卡片 */}
      <div className="grid grid-cols-3 gap-4 mb-8">
        <div className="bg-white rounded-xl border border-gray-200 px-5 py-4">
          <p className="text-xs text-gray-500 uppercase tracking-wide">Status</p>
          <p className="text-lg font-bold text-gray-900 mt-1">
            {activeConfig && (activeConfig.slides as unknown[]).length > 0 ? '🟢 Active' : '⚪ Inactive'}
          </p>
        </div>
        <div className="bg-white rounded-xl border border-gray-200 px-5 py-4">
          <p className="text-xs text-gray-500 uppercase tracking-wide">Slides</p>
          <p className="text-lg font-bold text-gray-900 mt-1">
            {activeConfig ? (activeConfig.slides as unknown[]).length : 0}
          </p>
        </div>
        <div className="bg-white rounded-xl border border-gray-200 px-5 py-4">
          <p className="text-xs text-gray-500 uppercase tracking-wide">Duration</p>
          <p className="text-lg font-bold text-gray-900 mt-1">
            {activeConfig?.duration_seconds ?? 5}s per slide
          </p>
        </div>
      </div>

      <SplashConfigEditor config={activeConfig} />
    </div>
  )
}
