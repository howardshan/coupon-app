import { createClient } from '@/lib/supabase/server'
import { getServiceRoleClient } from '@/lib/supabase/service'
import { redirect } from 'next/navigation'
import OnboardingConfigEditor from './onboarding-config-editor'

export default async function OnboardingConfigPage() {
  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()
  const { data: profile } = await supabase
    .from('users')
    .select('role')
    .eq('id', user!.id)
    .single()

  if (profile?.role !== 'admin') redirect('/dashboard')

  const serviceClient = getServiceRoleClient()
  const { data: configs } = await serviceClient
    .from('onboarding_configs')
    .select('*')
    .order('created_at', { ascending: false })

  const activeConfig = configs?.find(c => c.is_active) ?? null

  return (
    <div>
      <div className="mb-6">
        <h1 className="text-2xl font-bold text-gray-900">Onboarding</h1>
        <p className="text-sm text-gray-500 mt-1">
          Configure the onboarding slides shown to first-time users only.
          After completing onboarding, users will not see it again.
        </p>
      </div>

      <div className="grid grid-cols-2 gap-4 mb-8">
        <div className="bg-white rounded-xl border border-gray-200 px-5 py-4">
          <p className="text-xs text-gray-500 uppercase tracking-wide">Status</p>
          <p className="text-lg font-bold text-gray-900 mt-1">
            {activeConfig && (activeConfig.slides as unknown[]).length > 0 ? '🟢 Active' : '⚪ Inactive'}
          </p>
        </div>
        <div className="bg-white rounded-xl border border-gray-200 px-5 py-4">
          <p className="text-xs text-gray-500 uppercase tracking-wide">Slides</p>
          <p className="text-lg font-bold text-gray-900 mt-1">
            {activeConfig ? (activeConfig.slides as unknown[]).length : 0} / 5 max
          </p>
        </div>
      </div>

      <OnboardingConfigEditor config={activeConfig} />
    </div>
  )
}
