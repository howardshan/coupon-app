import { createClient } from '@/lib/supabase/server'
import { redirect } from 'next/navigation'
import Link from 'next/link'

// 文档类型对应的颜色配置
const typeStyles: Record<string, { bg: string; text: string; label: string }> = {
  user: { bg: 'bg-blue-50', text: 'text-blue-700', label: 'User' },
  merchant: { bg: 'bg-green-50', text: 'text-green-700', label: 'Merchant' },
  both: { bg: 'bg-purple-50', text: 'text-purple-700', label: 'Both' },
}

// 格式化日期
function formatDate(dateStr: string | null): string {
  if (!dateStr) return '—'
  return new Date(dateStr).toLocaleDateString('en-US', {
    year: 'numeric',
    month: 'short',
    day: 'numeric',
    hour: '2-digit',
    minute: '2-digit',
  })
}

export default async function LegalDocumentsPage() {
  // 权限校验
  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()
  const { data: profile } = await supabase
    .from('users')
    .select('role')
    .eq('id', user!.id)
    .single()

  if (profile?.role !== 'admin') redirect('/dashboard')

  // 查询所有法律文档
  const { data: documents } = await supabase
    .from('legal_documents')
    .select('*')
    .order('created_at', { ascending: true })

  const total = documents?.length ?? 0
  // 统计已发布的文档数（current_version > 0）
  const publishedCount = documents?.filter(d => d.current_version > 0).length ?? 0
  // 统计需要重新同意的文档数
  const reConsentCount = documents?.filter(d => d.requires_re_consent).length ?? 0

  return (
    <div>
      {/* 页面标题 + 占位符管理入口 */}
      <div className="flex items-start justify-between mb-6">
        <div>
          <h1 className="text-2xl font-bold text-gray-900">Legal Documents</h1>
          <p className="text-sm text-gray-500 mt-1">
            Manage legal documents, terms and policies. Published versions are immutable for compliance.
          </p>
        </div>
        <Link
          href="/settings/legal/placeholders"
          className="inline-flex items-center gap-2 px-4 py-2 text-sm font-medium rounded-lg border border-gray-300 bg-white text-gray-700 shadow-sm hover:bg-gray-50 transition-colors whitespace-nowrap"
        >
          ⚙️ Placeholders
        </Link>
      </div>

      {/* 统计概览 */}
      <div className="grid grid-cols-3 gap-4 mb-8">
        <div className="bg-white rounded-xl border border-gray-200 px-5 py-4">
          <p className="text-xs font-medium text-gray-500 uppercase tracking-wide">Total Documents</p>
          <p className="text-3xl font-bold text-gray-900 mt-1">{total}</p>
        </div>
        <div className="bg-white rounded-xl border border-gray-200 px-5 py-4">
          <p className="text-xs font-medium text-green-600 uppercase tracking-wide">Published</p>
          <p className="text-3xl font-bold text-green-600 mt-1">{publishedCount}</p>
        </div>
        <div className="bg-white rounded-xl border border-gray-200 px-5 py-4">
          <p className="text-xs font-medium text-amber-600 uppercase tracking-wide">Re-consent Required</p>
          <p className="text-3xl font-bold text-amber-600 mt-1">{reConsentCount}</p>
        </div>
      </div>

      {/* 文档卡片网格 */}
      {total === 0 ? (
        <div className="bg-white rounded-xl border border-gray-200 px-6 py-16 text-center">
          <p className="text-gray-400 text-sm">No legal documents found.</p>
        </div>
      ) : (
        <div className="grid grid-cols-1 md:grid-cols-2 xl:grid-cols-3 gap-4">
          {documents!.map((doc) => {
            const style = typeStyles[doc.document_type] ?? typeStyles.user
            const hasPublished = doc.current_version > 0

            return (
              <Link
                key={doc.id}
                href={`/settings/legal/${doc.slug}`}
                className="block bg-white rounded-xl border border-gray-200 px-5 py-4 hover:shadow-md hover:border-gray-300 transition-all"
              >
                {/* 标题行 + 类型标签 */}
                <div className="flex items-start justify-between gap-2 mb-3">
                  <h3 className="text-sm font-semibold text-gray-900 leading-snug">
                    {doc.title}
                  </h3>
                  <span className={`shrink-0 inline-flex items-center rounded-full px-2 py-0.5 text-xs font-medium ${style.bg} ${style.text}`}>
                    {style.label}
                  </span>
                </div>

                {/* 版本号 */}
                <div className="mb-3">
                  {hasPublished ? (
                    <span className="inline-flex items-center rounded-md bg-gray-100 px-2 py-0.5 text-xs font-medium text-gray-700">
                      {doc.current_version_label ?? `v${doc.current_version}`}
                    </span>
                  ) : (
                    <span className="inline-flex items-center rounded-md bg-orange-50 px-2 py-0.5 text-xs font-medium text-orange-600">
                      No published version
                    </span>
                  )}
                </div>

                {/* 标签区域 */}
                <div className="flex flex-wrap gap-1.5 mb-3">
                  {/* 启用状态 */}
                  {doc.is_active ? (
                    <span className="inline-flex items-center rounded-full bg-green-50 px-2 py-0.5 text-xs font-medium text-green-700">
                      Active
                    </span>
                  ) : (
                    <span className="inline-flex items-center rounded-full bg-red-50 px-2 py-0.5 text-xs font-medium text-red-600">
                      Inactive
                    </span>
                  )}

                  {/* 需要重新同意 */}
                  {doc.requires_re_consent && (
                    <span className="inline-flex items-center rounded-full bg-amber-50 px-2 py-0.5 text-xs font-medium text-amber-700">
                      ⚠️ Re-consent required
                    </span>
                  )}
                </div>

                {/* 最后更新时间 */}
                <p className="text-xs text-gray-400">
                  Updated {formatDate(doc.updated_at)}
                </p>
              </Link>
            )
          })}
        </div>
      )}
    </div>
  )
}
