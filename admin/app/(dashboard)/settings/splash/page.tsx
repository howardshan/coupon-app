import { createClient } from '@/lib/supabase/server'
import { getServiceRoleClient } from '@/lib/supabase/service'
import { redirect } from 'next/navigation'
import SplashConfigEditor from './splash-config-editor'
import { StatusToggle } from '@/components/status-toggle'
import { activateSplashConfig, deactivateSplashConfig } from '@/app/actions/welcome-config'
import { enablePlacement, disablePlacement } from '@/app/actions/ads'

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

  const serviceClient = getServiceRoleClient()

  // 获取竞价广告位配置
  const { data: placementConfig } = await serviceClient
    .from('ad_placement_config')
    .select('*')
    .eq('placement', 'splash')
    .single()

  // 获取当前活跃的 splash campaigns 数量
  const { count: activeCampaignCount } = await serviceClient
    .from('ad_campaigns')
    .select('id', { count: 'exact', head: true })
    .eq('placement', 'splash')
    .eq('status', 'active')

  // 获取所有 splash 配置（含 active 和 draft）
  const { data: configs } = await serviceClient
    .from('splash_configs')
    .select('*')
    .order('created_at', { ascending: false })

  // 优先取 active 配置，没有则取最新一条
  const activeConfig = configs?.find(c => c.is_active) ?? configs?.[0] ?? null

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
          <p className="text-xs text-gray-500 uppercase tracking-wide mb-2">Status</p>
          {activeConfig ? (
            <StatusToggle
              configId={activeConfig.id}
              initialActive={activeConfig.is_active}
              onActivate={activateSplashConfig}
              onDeactivate={deactivateSplashConfig}
            />
          ) : (
            <p className="text-sm text-gray-400">No config</p>
          )}
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

      {/* 竞价广告设置区 */}
      <div className="mb-8">
        <h2 className="text-lg font-semibold text-gray-900 mb-3">Bidding Ads</h2>
        <p className="text-sm text-gray-500 mb-4">
          When enabled, splash screen shows location-based bidding ads from merchants (highest bid wins).
          When disabled or no ads available, falls back to static slides below.
        </p>
        <div className="grid grid-cols-3 gap-4">
          <div className="bg-white rounded-xl border border-gray-200 px-5 py-4">
            <p className="text-xs text-gray-500 uppercase tracking-wide mb-2">Bidding Ads</p>
            {placementConfig ? (
              <StatusToggle
                configId="splash"
                initialActive={placementConfig.is_enabled}
                onActivate={enablePlacement}
                onDeactivate={disablePlacement}
              />
            ) : (
              <p className="text-sm text-gray-400">Not configured</p>
            )}
          </div>
          <div className="bg-white rounded-xl border border-gray-200 px-5 py-4">
            <p className="text-xs text-gray-500 uppercase tracking-wide">Active Campaigns</p>
            <p className="text-lg font-bold text-gray-900 mt-1">{activeCampaignCount ?? 0}</p>
          </div>
          <div className="bg-white rounded-xl border border-gray-200 px-5 py-4">
            <p className="text-xs text-gray-500 uppercase tracking-wide">Max Slots</p>
            <p className="text-lg font-bold text-gray-900 mt-1">{placementConfig?.max_slots ?? 3}</p>
          </div>
        </div>
      </div>

      {/* 静态配置区（Fallback） */}
      <div className="mb-4">
        <h2 className="text-lg font-semibold text-gray-900 mb-1">Static Slides (Fallback)</h2>
        <p className="text-sm text-gray-500 mb-4">
          Shown when bidding ads are disabled or no active campaigns in user's area.
        </p>
      </div>
      <SplashConfigEditor config={activeConfig} />
    </div>
  )
}
