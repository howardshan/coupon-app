import { createClient } from '@/lib/supabase/server'
import { getServiceRoleClient } from '@/lib/supabase/service'
import { redirect } from 'next/navigation'
import Link from 'next/link'
import LegalDocEditor from './legal-doc-editor'

// 文档类型对应的颜色配置
const typeStyles: Record<string, { bg: string; text: string; label: string }> = {
  user: { bg: 'bg-blue-50', text: 'text-blue-700', label: 'User' },
  merchant: { bg: 'bg-green-50', text: 'text-green-700', label: 'Merchant' },
  both: { bg: 'bg-purple-50', text: 'text-purple-700', label: 'Both' },
}

export default async function LegalDocumentEditPage({
  params,
}: {
  params: Promise<{ slug: string }>
}) {
  const { slug } = await params

  // 权限校验
  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()
  const { data: profile } = await supabase
    .from('users')
    .select('role')
    .eq('id', user!.id)
    .single()

  if (profile?.role !== 'admin') redirect('/dashboard')

  // 用 service role client 获取文档（绕过 RLS）
  const serviceClient = getServiceRoleClient()

  // 获取文档信息
  const { data: document, error: docError } = await serviceClient
    .from('legal_documents')
    .select('*')
    .eq('slug', slug)
    .single()

  // 文档不存在则跳回列表页
  if (docError || !document) {
    redirect('/settings/legal')
  }

  // 获取该文档的所有版本，按版本号倒序
  const { data: versions } = await serviceClient
    .from('legal_document_versions')
    .select('*')
    .eq('document_id', document.id)
    .order('version', { ascending: false })

  const style = typeStyles[document.document_type] ?? typeStyles.user

  return (
    <div>
      {/* 顶部导航 + 标题 */}
      <div className="mb-6">
        <Link
          href="/settings/legal"
          className="inline-flex items-center text-sm text-gray-500 hover:text-gray-700 mb-3"
        >
          <svg className="w-4 h-4 mr-1" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M15 19l-7-7 7-7" />
          </svg>
          Back to Legal Documents
        </Link>

        <div className="flex items-center gap-3">
          <h1 className="text-2xl font-bold text-gray-900">{document.title}</h1>
          <span
            className={`inline-flex items-center rounded-full px-2.5 py-0.5 text-xs font-medium ${style.bg} ${style.text}`}
          >
            {style.label}
          </span>
        </div>
        <p className="text-sm text-gray-500 mt-1">
          Slug: <code className="bg-gray-100 px-1.5 py-0.5 rounded text-xs">{document.slug}</code>
          {' '}&middot;{' '}
          Current version: <strong>v{document.current_version}</strong>
        </p>
      </div>

      {/* 编辑器（客户端组件） */}
      <LegalDocEditor
        document={{
          id: document.id,
          slug: document.slug,
          title: document.title,
          document_type: document.document_type,
          requires_re_consent: document.requires_re_consent,
          current_version: document.current_version,
          is_active: document.is_active,
          created_at: document.created_at,
          updated_at: document.updated_at,
        }}
        versions={versions ?? []}
      />
    </div>
  )
}
