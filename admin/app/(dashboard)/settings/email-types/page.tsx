import { createClient } from '@/lib/supabase/server'
import { getServiceRoleClient } from '@/lib/supabase/service'
import { redirect } from 'next/navigation'
import EmailTypeSettingsTable from '@/components/email-type-settings-table'

export default async function EmailTypesPage() {
  // 权限校验
  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()
  const { data: profile } = await supabase
    .from('users')
    .select('role')
    .eq('id', user!.id)
    .single()

  if (profile?.role !== 'admin') redirect('/dashboard')

  // 读取全部邮件类型配置（service_role 确保可读）
  const serviceClient = getServiceRoleClient()
  const { data: settings } = await serviceClient
    .from('email_type_settings')
    .select('id, email_code, email_name, recipient_type, global_enabled, user_configurable, admin_recipient_emails, description, updated_at')
    .order('email_code')

  // 统计数据
  const total   = settings?.length ?? 0
  const enabled = settings?.filter(s => s.global_enabled).length ?? 0
  const disabled = total - enabled

  return (
    <div>
      {/* 页面标题 */}
      <div className="mb-6">
        <h1 className="text-2xl font-bold text-gray-900">Email Notifications</h1>
        <p className="text-sm text-gray-500 mt-1">
          Manage global on/off switches for all email types. Turning off a type stops delivery
          immediately — user preferences for that type are also hidden.
        </p>
      </div>

      {/* 统计概览 */}
      <div className="grid grid-cols-3 gap-4 mb-8">
        <div className="bg-white rounded-xl border border-gray-200 px-5 py-4">
          <p className="text-xs font-medium text-gray-500 uppercase tracking-wide">Total Types</p>
          <p className="text-3xl font-bold text-gray-900 mt-1">{total}</p>
        </div>
        <div className="bg-white rounded-xl border border-gray-200 px-5 py-4">
          <p className="text-xs font-medium text-green-600 uppercase tracking-wide">Enabled</p>
          <p className="text-3xl font-bold text-green-600 mt-1">{enabled}</p>
        </div>
        <div className="bg-white rounded-xl border border-gray-200 px-5 py-4">
          <p className="text-xs font-medium text-gray-400 uppercase tracking-wide">Disabled</p>
          <p className="text-3xl font-bold text-gray-400 mt-1">{disabled}</p>
        </div>
      </div>

      {/* 邮件类型表格（Client Component，含开关交互） */}
      {settings && settings.length > 0 ? (
        <EmailTypeSettingsTable settings={settings as any} />
      ) : (
        <div className="bg-white rounded-xl border border-gray-200 p-12 text-center">
          <p className="text-gray-400">No email type settings found.</p>
          <p className="text-sm text-gray-400 mt-1">
            Run the database migration to seed the 37 email types.
          </p>
        </div>
      )}
    </div>
  )
}
