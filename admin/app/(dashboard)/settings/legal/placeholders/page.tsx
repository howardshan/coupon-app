import { createClient } from '@/lib/supabase/server'
import { redirect } from 'next/navigation'
import Link from 'next/link'
import PlaceholdersEditor from './placeholders-editor'

export default async function LegalPlaceholdersPage() {
  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()
  const { data: profile } = await supabase.from('users').select('role').eq('id', user!.id).single()
  if (profile?.role !== 'admin') redirect('/dashboard')

  // 获取所有占位符
  const { data: placeholders } = await supabase
    .from('legal_placeholders')
    .select('*')
    .order('key', { ascending: true })

  return (
    <div className="max-w-4xl mx-auto">
      {/* 顶部导航 */}
      <div className="flex items-center gap-3 mb-6">
        <Link
          href="/settings/legal"
          className="text-sm text-gray-500 hover:text-gray-700 transition-colors"
        >
          ← Legal Documents
        </Link>
      </div>

      <h1 className="text-2xl font-bold text-gray-900">Legal Placeholders</h1>
      <p className="text-sm text-gray-500 mt-1 mb-8">
        Configure values for placeholders used across all legal documents. These values will be automatically substituted when documents are displayed to users.
        <br />
        <code className="text-xs bg-gray-100 px-1 py-0.5 rounded">[DATE]</code> and <code className="text-xs bg-gray-100 px-1 py-0.5 rounded">[YEAR]</code> are auto-filled with the current date/year.
      </p>

      <PlaceholdersEditor initialData={placeholders ?? []} />
    </div>
  )
}
