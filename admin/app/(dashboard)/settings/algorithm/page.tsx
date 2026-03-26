import { createClient } from '@/lib/supabase/server'
import { redirect } from 'next/navigation'
import { listConfigs } from '@/app/actions/recommendation'
import AlgorithmConfig from '@/components/algorithm-config'

export default async function AlgorithmPage() {
  // 权限校验
  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()
  if (!user) redirect('/login')

  const { data: profile } = await supabase
    .from('users')
    .select('role')
    .eq('id', user.id)
    .single()

  if (profile?.role !== 'admin') redirect('/dashboard')

  // 获取配置历史列表
  const result = await listConfigs()
  const configs = result.data?.configs ?? []

  return (
    <div>
      <div className="mb-6">
        <h1 className="text-2xl font-bold text-gray-900">Recommendation Algorithm</h1>
        <p className="text-sm text-gray-500 mt-1">
          Configure deal recommendation weights using natural language descriptions.
        </p>
      </div>

      <AlgorithmConfig initialConfigs={configs} />
    </div>
  )
}
