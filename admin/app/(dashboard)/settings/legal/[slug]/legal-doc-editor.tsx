'use client'

import { useState, useTransition } from 'react'
import { toast } from 'sonner'
import { saveDraft, publishVersion, updateDocumentSettings } from '@/app/actions/legal'

// ========== 类型定义 ==========

type LegalDocument = {
  id: string
  slug: string
  title: string
  document_type: string
  requires_re_consent: boolean
  current_version: number
  current_version_label: string | null
  is_active: boolean
  created_at: string
  updated_at: string
}

type LegalDocVersion = {
  id: string
  document_id: string
  version: number
  version_label: string | null
  content_html: string
  summary_of_changes: string | null
  published_at: string | null
  published_by: string | null
  created_at: string
}

interface LegalDocEditorProps {
  document: LegalDocument
  versions: LegalDocVersion[]
}

// ========== 格式化日期 ==========

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

// ========== 主组件 ==========

export default function LegalDocEditor({ document, versions: initialVersions }: LegalDocEditorProps) {
  // 编辑器内容
  const [contentHtml, setContentHtml] = useState(() => {
    // 初始内容：取最新版本的 HTML，没有则为空
    const latest = initialVersions[0]
    return latest?.content_html ?? ''
  })

  // 预览模式
  const [showPreview, setShowPreview] = useState(false)

  // 文档设置
  const [requiresReConsent, setRequiresReConsent] = useState(document.requires_re_consent)
  const [isActive, setIsActive] = useState(document.is_active)

  // 发布对话框
  const [showPublishDialog, setShowPublishDialog] = useState(false)
  const [summaryOfChanges, setSummaryOfChanges] = useState('')
  const [versionLabel, setVersionLabel] = useState('')

  // 版本历史
  const [versions, setVersions] = useState(initialVersions)
  const [selectedVersionId, setSelectedVersionId] = useState<string | null>(null)
  const [isReadonly, setIsReadonly] = useState(false)

  // loading 状态
  const [isSavingDraft, startSaveDraft] = useTransition()
  const [isPublishing, startPublish] = useTransition()
  const [isUpdatingSettings, startUpdateSettings] = useTransition()

  // 保存草稿
  function handleSaveDraft() {
    startSaveDraft(async () => {
      try {
        // saveDraft 以 slug 为标识符
        await saveDraft(document.slug, contentHtml)
        toast.success('Draft saved successfully')
      } catch (e: any) {
        toast.error(e.message || 'Failed to save draft')
      }
    })
  }

  // 发布新版本
  function handlePublish() {
    if (!summaryOfChanges.trim()) {
      toast.error('Please provide a summary of changes')
      return
    }

    startPublish(async () => {
      try {
        // publishVersion 以 slug 为标识符
        const result = await publishVersion(document.slug, contentHtml, summaryOfChanges.trim(), versionLabel.trim())
        setShowPublishDialog(false)
        setSummaryOfChanges('')
        setVersionLabel('')
        toast.success(`Version ${result?.publishedVersion ?? ''} published successfully`)
      } catch (e: any) {
        toast.error(e.message || 'Failed to publish version')
      }
    })
  }

  // 更新文档设置（requires_re_consent / is_active）
  function handleUpdateSettings(field: 'requires_re_consent' | 'is_active', value: boolean) {
    // 先乐观更新 UI
    if (field === 'requires_re_consent') setRequiresReConsent(value)
    if (field === 'is_active') setIsActive(value)

    startUpdateSettings(async () => {
      try {
        // updateDocumentSettings 以 slug 为标识符
        await updateDocumentSettings(document.slug, { [field]: value })
        toast.success('Settings updated')
      } catch (e: any) {
        // 回滚
        if (field === 'requires_re_consent') setRequiresReConsent(!value)
        if (field === 'is_active') setIsActive(!value)
        toast.error(e.message || 'Failed to update settings')
      }
    })
  }

  // 选择查看某个历史版本
  function handleSelectVersion(version: LegalDocVersion) {
    setSelectedVersionId(version.id)
    setContentHtml(version.content_html)
    setIsReadonly(true)
    setShowPreview(false)
  }

  // 返回编辑模式（取消查看历史版本）
  function handleBackToEdit() {
    setSelectedVersionId(null)
    // 恢复到最新版本内容
    const latest = versions[0]
    setContentHtml(latest?.content_html ?? '')
    setIsReadonly(false)
  }

  const selectedVersion = versions.find((v) => v.id === selectedVersionId)

  return (
    <div>
      {/* 设置区域 */}
      <div className="flex items-center gap-6 mb-6 bg-white rounded-xl border border-gray-200 px-5 py-4">
        {/* requires_re_consent 开关 */}
        <label className="flex items-center gap-2 cursor-pointer">
          <span className="text-sm text-gray-700">Requires Re-consent</span>
          <button
            type="button"
            role="switch"
            aria-checked={requiresReConsent}
            disabled={isUpdatingSettings}
            onClick={() => handleUpdateSettings('requires_re_consent', !requiresReConsent)}
            className={`relative inline-flex h-5 w-9 shrink-0 items-center rounded-full transition-colors ${
              requiresReConsent ? 'bg-amber-500' : 'bg-gray-300'
            } ${isUpdatingSettings ? 'opacity-50' : ''}`}
          >
            <span
              className={`inline-block h-4 w-4 rounded-full bg-white shadow transform transition-transform ${
                requiresReConsent ? 'translate-x-4.5' : 'translate-x-0.5'
              }`}
            />
          </button>
        </label>

        {/* is_active 开关 */}
        <label className="flex items-center gap-2 cursor-pointer">
          <span className="text-sm text-gray-700">Active</span>
          <button
            type="button"
            role="switch"
            aria-checked={isActive}
            disabled={isUpdatingSettings}
            onClick={() => handleUpdateSettings('is_active', !isActive)}
            className={`relative inline-flex h-5 w-9 shrink-0 items-center rounded-full transition-colors ${
              isActive ? 'bg-green-500' : 'bg-gray-300'
            } ${isUpdatingSettings ? 'opacity-50' : ''}`}
          >
            <span
              className={`inline-block h-4 w-4 rounded-full bg-white shadow transform transition-transform ${
                isActive ? 'translate-x-4.5' : 'translate-x-0.5'
              }`}
            />
          </button>
        </label>
      </div>

      {/* 主区域：左右分栏 */}
      <div className="flex gap-6">
        {/* 左侧：编辑器区域（70%） */}
        <div className="flex-[7] min-w-0">
          <div className="bg-white rounded-xl border border-gray-200 overflow-hidden">
            {/* 编辑器头部 */}
            <div className="flex items-center justify-between px-5 py-3 border-b border-gray-200 bg-gray-50">
              <div className="flex items-center gap-2">
                <h2 className="text-sm font-semibold text-gray-700">
                  {isReadonly && selectedVersion
                    ? `Viewing Version ${selectedVersion.version} (Read-only)`
                    : 'HTML Content Editor'}
                </h2>
                {isReadonly && (
                  <button
                    onClick={handleBackToEdit}
                    className="text-xs text-blue-600 hover:text-blue-800 underline"
                  >
                    Back to editing
                  </button>
                )}
              </div>

              {/* 预览切换 */}
              <button
                onClick={() => setShowPreview(!showPreview)}
                className={`inline-flex items-center gap-1.5 rounded-md px-3 py-1.5 text-xs font-medium transition-colors ${
                  showPreview
                    ? 'bg-blue-100 text-blue-700'
                    : 'bg-gray-100 text-gray-600 hover:bg-gray-200'
                }`}
              >
                <svg className="w-3.5 h-3.5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path
                    strokeLinecap="round"
                    strokeLinejoin="round"
                    strokeWidth={2}
                    d="M15 12a3 3 0 11-6 0 3 3 0 016 0z"
                  />
                  <path
                    strokeLinecap="round"
                    strokeLinejoin="round"
                    strokeWidth={2}
                    d="M2.458 12C3.732 7.943 7.523 5 12 5c4.478 0 8.268 2.943 9.542 7-1.274 4.057-5.064 7-9.542 7-4.477 0-8.268-2.943-9.542-7z"
                  />
                </svg>
                {showPreview ? 'Editor' : 'Preview'}
              </button>
            </div>

            {/* 编辑器 / 预览区域 */}
            {showPreview ? (
              // HTML 预览
              <div className="p-6 min-h-[500px] max-h-[700px] overflow-y-auto">
                <div
                  className="prose prose-sm max-w-none"
                  dangerouslySetInnerHTML={{ __html: contentHtml }}
                />
              </div>
            ) : (
              // 代码编辑器
              <div className="relative">
                <textarea
                  value={contentHtml}
                  onChange={(e) => setContentHtml(e.target.value)}
                  readOnly={isReadonly}
                  spellCheck={false}
                  className={`w-full min-h-[500px] max-h-[700px] p-4 font-mono text-sm leading-relaxed text-gray-800 bg-white border-0 resize-y focus:outline-none focus:ring-0 ${
                    isReadonly ? 'bg-gray-50 text-gray-500 cursor-not-allowed' : ''
                  }`}
                  placeholder="Enter HTML content here..."
                />
              </div>
            )}

            {/* 底部操作栏 */}
            {!isReadonly && (
              <div className="flex items-center justify-end gap-3 px-5 py-3 border-t border-gray-200 bg-gray-50">
                <button
                  onClick={handleSaveDraft}
                  disabled={isSavingDraft}
                  className="inline-flex items-center rounded-lg bg-gray-200 px-4 py-2 text-sm font-medium text-gray-700 hover:bg-gray-300 transition-colors disabled:opacity-50"
                >
                  {isSavingDraft ? 'Saving...' : 'Save Draft'}
                </button>
                <button
                  onClick={() => {
                    const nextNum = (document.current_version ?? 0) + 1
                    setVersionLabel(`v${nextNum}`)
                    setShowPublishDialog(true)
                  }}
                  disabled={isPublishing}
                  className="inline-flex items-center rounded-lg bg-blue-600 px-4 py-2 text-sm font-medium text-white hover:bg-blue-700 transition-colors disabled:opacity-50"
                >
                  Publish New Version
                </button>
              </div>
            )}
          </div>
        </div>

        {/* 右侧：版本历史面板（30%） */}
        <div className="flex-[3] min-w-0">
          <div className="bg-white rounded-xl border border-gray-200 overflow-hidden">
            <div className="px-5 py-3 border-b border-gray-200 bg-gray-50">
              <h2 className="text-sm font-semibold text-gray-700">Version History</h2>
            </div>

            <div className="max-h-[600px] overflow-y-auto divide-y divide-gray-100">
              {versions.length === 0 ? (
                <div className="px-5 py-8 text-center">
                  <p className="text-sm text-gray-400">No versions yet</p>
                </div>
              ) : (
                versions.map((ver) => {
                  const isPublished = !!ver.published_at
                  const isSelected = ver.id === selectedVersionId

                  return (
                    <button
                      key={ver.id}
                      onClick={() => handleSelectVersion(ver)}
                      className={`w-full text-left px-5 py-3 hover:bg-gray-50 transition-colors ${
                        isSelected ? 'bg-blue-50 border-l-2 border-blue-500' : ''
                      }`}
                    >
                      <div className="flex items-center justify-between mb-1">
                        <span className="text-sm font-semibold text-gray-900">
                          {ver.version_label ?? `v${ver.version}`}
                        </span>
                        {isPublished ? (
                          <span className="inline-flex items-center rounded-full bg-green-50 px-2 py-0.5 text-xs font-medium text-green-700">
                            Published
                          </span>
                        ) : (
                          <span className="inline-flex items-center rounded-full bg-gray-100 px-2 py-0.5 text-xs font-medium text-gray-500">
                            Draft
                          </span>
                        )}
                      </div>

                      {/* 更新摘要 */}
                      {ver.summary_of_changes && (
                        <p className="text-xs text-gray-600 mb-1 line-clamp-2">
                          {ver.summary_of_changes}
                        </p>
                      )}

                      {/* 时间 */}
                      <p className="text-xs text-gray-400">
                        {formatDate(ver.published_at ?? ver.created_at)}
                      </p>
                    </button>
                  )
                })
              )}
            </div>
          </div>
        </div>
      </div>

      {/* 发布确认对话框（模态） */}
      {showPublishDialog && (
        <div className="fixed inset-0 z-50 flex items-center justify-center">
          {/* 遮罩层 */}
          <div
            className="absolute inset-0 bg-black/40"
            onClick={() => setShowPublishDialog(false)}
          />

          {/* 对话框 */}
          <div className="relative bg-white rounded-2xl shadow-xl w-full max-w-md mx-4 p-6">
            <h3 className="text-lg font-semibold text-gray-900 mb-2">Publish New Version</h3>
            <p className="text-sm text-gray-500 mb-4">
              Published versions are immutable.
            </p>

            {/* 版本标签 */}
            <label className="block text-sm font-medium text-gray-700 mb-1">
              Version Label
            </label>
            <input
              type="text"
              value={versionLabel}
              onChange={(e) => setVersionLabel(e.target.value)}
              className="w-full rounded-lg border border-gray-300 px-3 py-2 text-sm focus:border-blue-500 focus:ring-1 focus:ring-blue-500 mb-4"
              placeholder="e.g. v2.1"
            />

            {/* 重新同意警告 */}
            {requiresReConsent && (
              <div className="bg-red-50 border border-red-200 rounded-lg px-4 py-3 mb-4">
                <p className="text-sm text-red-700 font-medium">
                  ⚠️ This will invalidate all existing consents and require all users/merchants to
                  re-accept.
                </p>
              </div>
            )}

            {/* 更新摘要输入 */}
            <label className="block text-sm font-medium text-gray-700 mb-1">
              Summary of Changes <span className="text-red-500">*</span>
            </label>
            <textarea
              value={summaryOfChanges}
              onChange={(e) => setSummaryOfChanges(e.target.value)}
              rows={3}
              className="w-full rounded-lg border border-gray-300 px-3 py-2 text-sm focus:border-blue-500 focus:ring-1 focus:ring-blue-500 resize-none"
              placeholder="Describe what changed in this version..."
            />

            {/* 操作按钮 */}
            <div className="flex items-center justify-end gap-3 mt-5">
              <button
                onClick={() => setShowPublishDialog(false)}
                className="rounded-lg px-4 py-2 text-sm font-medium text-gray-700 hover:bg-gray-100 transition-colors"
              >
                Cancel
              </button>
              <button
                onClick={handlePublish}
                disabled={isPublishing || !summaryOfChanges.trim()}
                className="rounded-lg bg-blue-600 px-4 py-2 text-sm font-medium text-white hover:bg-blue-700 transition-colors disabled:opacity-50"
              >
                {isPublishing ? 'Publishing...' : 'Confirm Publish'}
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  )
}
