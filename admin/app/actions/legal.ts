'use server'

import { revalidatePath } from 'next/cache'
import { createClient } from '@/lib/supabase/server'
import { getServiceRoleClient } from '@/lib/supabase/service'
import { createHash } from 'crypto'

// ─── 类型定义 ───

type AdminSession = {
  supabase: Awaited<ReturnType<typeof createClient>>
  adminUserId: string
}

// ─── 内部工具函数 ───

// 权限校验：必须是 admin 角色
async function requireAdmin(): Promise<AdminSession> {
  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()
  if (!user) throw new Error('Unauthorized')

  const { data: profile } = await supabase
    .from('users')
    .select('role')
    .eq('id', user.id)
    .single()

  if (profile?.role !== 'admin') throw new Error('Forbidden')
  return { supabase, adminUserId: user.id }
}

// 生成审计日志完整性哈希（SHA-256）
function computeIntegrityHash(
  logId: string,
  userId: string,
  eventType: string,
  documentId: string,
  version: number,
  timestamp: string,
): string {
  return createHash('sha256')
    .update(logId + userId + eventType + documentId + String(version) + timestamp)
    .digest('hex')
}

// 写入法律审计日志（内部工具函数，使用 service_role 客户端）
async function writeAuditLog(
  serviceClient: ReturnType<typeof getServiceRoleClient>,
  params: {
    userId: string
    actorId: string
    actorRole: string
    eventType: string
    documentId: string
    documentSlug: string
    documentTitle: string
    documentVersion: number
    details: Record<string, unknown>
    platform: string
  },
) {
  const logId = crypto.randomUUID()
  const now = new Date().toISOString()
  const hash = computeIntegrityHash(
    logId,
    params.userId,
    params.eventType,
    params.documentId,
    params.documentVersion,
    now,
  )

  const { error } = await serviceClient.from('legal_audit_log').insert({
    id: logId,
    user_id: params.userId,
    actor_id: params.actorId,
    actor_role: params.actorRole,
    event_type: params.eventType,
    document_id: params.documentId,
    document_slug: params.documentSlug,
    document_title: params.documentTitle,
    document_version: params.documentVersion,
    details: params.details,
    platform: params.platform,
    created_at: now,
    integrity_hash: hash,
  })

  if (error) {
    console.error('[writeAuditLog] Failed to write audit log:', error)
    throw new Error(error.message)
  }
}

// ─── 导出的 Server Actions ───

// 获取所有法律文档列表，包含最新版本的 published_at
export async function getLegalDocuments() {
  await requireAdmin()
  const supabase = getServiceRoleClient()

  const { data, error } = await supabase
    .from('legal_documents')
    .select(`
      id, slug, title, document_type, requires_re_consent,
      current_version, current_version_label, is_active, created_at, updated_at,
      legal_document_versions(published_at, version, version_label)
    `)
    .order('created_at', { ascending: true })

  if (error) throw new Error(error.message)

  // 为每个文档附上最新已发布版本的 published_at
  const documents = (data ?? []).map((doc) => {
    const versions = (doc.legal_document_versions ?? []) as Array<{
      published_at: string | null
      version: number
      version_label: string | null
    }>
    // 找到当前版本对应的 published_at
    const currentVersionRecord = versions.find(
      (v) => v.version === doc.current_version,
    )
    return {
      id: doc.id,
      slug: doc.slug,
      title: doc.title,
      document_type: doc.document_type,
      requires_re_consent: doc.requires_re_consent,
      current_version: doc.current_version,
      current_version_label: (doc as any).current_version_label as string | null,
      is_active: doc.is_active,
      created_at: doc.created_at,
      updated_at: doc.updated_at,
      last_published_at: currentVersionRecord?.published_at ?? null,
    }
  })

  return documents
}

// 获取单个文档详情 + 所有版本历史（按版本倒序）
export async function getLegalDocument(slug: string) {
  await requireAdmin()
  const supabase = getServiceRoleClient()

  const { data: doc, error } = await supabase
    .from('legal_documents')
    .select(`
      id, slug, title, document_type, requires_re_consent,
      current_version, is_active, created_at, updated_at,
      legal_document_versions(
        id, document_id, version, version_label, content_html,
        summary_of_changes, published_at, published_by, created_at
      )
    `)
    .eq('slug', slug)
    .single()

  if (error) throw new Error(error.message)
  if (!doc) throw new Error('Document not found')

  // 按版本号倒序排列
  const versions = (doc.legal_document_versions ?? []) as Array<{
    id: string
    document_id: string
    version: number
    version_label: string | null
    content_html: string
    summary_of_changes: string | null
    published_at: string | null
    published_by: string | null
    created_at: string
  }>
  versions.sort((a, b) => b.version - a.version)

  return {
    id: doc.id,
    slug: doc.slug,
    title: doc.title,
    document_type: doc.document_type,
    requires_re_consent: doc.requires_re_consent,
    current_version: doc.current_version,
    current_version_label: (doc as any).current_version_label as string | null,
    is_active: doc.is_active,
    created_at: doc.created_at,
    updated_at: doc.updated_at,
    versions,
  }
}

// 保存草稿：如果已有未发布版本就更新，否则创建新版本
export async function saveDraft(slug: string, contentHtml: string) {
  const { adminUserId } = await requireAdmin()
  const supabase = getServiceRoleClient()

  // 查询文档
  const { data: doc, error: docError } = await supabase
    .from('legal_documents')
    .select('id, current_version, title')
    .eq('slug', slug)
    .single()

  if (docError || !doc) throw new Error(docError?.message ?? 'Document not found')

  // 查找是否已有未发布的草稿版本（published_at 为 null）
  const { data: existingDraft } = await supabase
    .from('legal_document_versions')
    .select('id, version')
    .eq('document_id', doc.id)
    .is('published_at', null)
    .order('version', { ascending: false })
    .limit(1)
    .maybeSingle()

  if (existingDraft) {
    // 更新现有草稿
    const { error: updateError } = await supabase
      .from('legal_document_versions')
      .update({ content_html: contentHtml })
      .eq('id', existingDraft.id)

    if (updateError) throw new Error(updateError.message)

    return { versionId: existingDraft.id, version: existingDraft.version, isNew: false }
  } else {
    // 创建新版本（version = current_version + 1）
    const newVersion = doc.current_version + 1
    const { data: newDraft, error: insertError } = await supabase
      .from('legal_document_versions')
      .insert({
        document_id: doc.id,
        version: newVersion,
        content_html: contentHtml,
        published_at: null,
        published_by: null,
      })
      .select('id')
      .single()

    if (insertError) throw new Error(insertError.message)

    return { versionId: newDraft!.id, version: newVersion, isNew: true }
  }
}

// 发布新版本
export async function publishVersion(
  slug: string,
  contentHtml: string,
  summaryOfChanges: string,
  versionLabel?: string,
) {
  const { adminUserId } = await requireAdmin()
  const supabase = getServiceRoleClient()

  // 查询文档
  const { data: doc, error: docError } = await supabase
    .from('legal_documents')
    .select('id, current_version, title, requires_re_consent')
    .eq('slug', slug)
    .single()

  if (docError || !doc) throw new Error(docError?.message ?? 'Document not found')

  const now = new Date().toISOString()
  const newVersion = doc.current_version + 1

  // 查找是否已有未发布的草稿版本
  const { data: existingDraft } = await supabase
    .from('legal_document_versions')
    .select('id, version')
    .eq('document_id', doc.id)
    .is('published_at', null)
    .order('version', { ascending: false })
    .limit(1)
    .maybeSingle()

  let publishedVersionId: string
  let publishedVersion: number

  const effectiveLabel = versionLabel?.trim() || `v${existingDraft ? existingDraft.version : newVersion}`

  if (existingDraft) {
    // 更新草稿为已发布
    publishedVersion = existingDraft.version
    const { error: updateError } = await supabase
      .from('legal_document_versions')
      .update({
        content_html: contentHtml,
        summary_of_changes: summaryOfChanges,
        version_label: effectiveLabel,
        published_at: now,
        published_by: adminUserId,
      })
      .eq('id', existingDraft.id)

    if (updateError) throw new Error(updateError.message)
    publishedVersionId = existingDraft.id
  } else {
    // 创建新版本并直接发布
    publishedVersion = newVersion
    const { data: newRow, error: insertError } = await supabase
      .from('legal_document_versions')
      .insert({
        document_id: doc.id,
        version: newVersion,
        version_label: effectiveLabel,
        content_html: contentHtml,
        summary_of_changes: summaryOfChanges,
        published_at: now,
        published_by: adminUserId,
      })
      .select('id')
      .single()

    if (insertError) throw new Error(insertError.message)
    publishedVersionId = newRow!.id
  }

  // 更新 legal_documents.current_version 和 current_version_label
  const { error: updateDocError } = await supabase
    .from('legal_documents')
    .update({ current_version: publishedVersion, current_version_label: effectiveLabel, updated_at: now })
    .eq('id', doc.id)

  if (updateDocError) throw new Error(updateDocError.message)

  // 写入 document_published 审计日志
  await writeAuditLog(supabase, {
    userId: adminUserId,
    actorId: adminUserId,
    actorRole: 'admin',
    eventType: 'document_published',
    documentId: doc.id,
    documentSlug: slug,
    documentTitle: doc.title,
    documentVersion: publishedVersion,
    details: {
      summary_of_changes: summaryOfChanges,
      version_id: publishedVersionId,
    },
    platform: 'admin',
  })

  // 如果文档要求重新同意，为所有持有旧版同意的用户写入 consent_superseded 审计日志
  if (doc.requires_re_consent) {
    // 查询所有 version < publishedVersion 的用户同意记录
    const { data: oldConsents, error: consentError } = await supabase
      .from('user_consents')
      .select('user_id, version')
      .eq('document_id', doc.id)
      .lt('version', publishedVersion)

    if (consentError) {
      console.error('[publishVersion] Failed to query old consents:', consentError)
    } else if (oldConsents && oldConsents.length > 0) {
      // 批量写入 consent_superseded 审计日志
      const auditRows = oldConsents.map((consent) => {
        const logId = crypto.randomUUID()
        const logNow = new Date().toISOString()
        const hash = computeIntegrityHash(
          logId,
          consent.user_id,
          'consent_superseded',
          doc.id,
          publishedVersion,
          logNow,
        )
        return {
          id: logId,
          user_id: consent.user_id,
          actor_id: adminUserId,
          actor_role: 'admin',
          event_type: 'consent_superseded',
          document_id: doc.id,
          document_slug: slug,
          document_title: doc.title,
          document_version: publishedVersion,
          details: {
            previous_consented_version: consent.version,
            new_version: publishedVersion,
          },
          platform: 'admin',
          created_at: logNow,
          integrity_hash: hash,
        }
      })

      // 分批插入，每批 500 条，避免请求体过大
      const BATCH_SIZE = 500
      for (let i = 0; i < auditRows.length; i += BATCH_SIZE) {
        const batch = auditRows.slice(i, i + BATCH_SIZE)
        const { error: batchError } = await supabase
          .from('legal_audit_log')
          .insert(batch)

        if (batchError) {
          console.error(
            `[publishVersion] consent_superseded batch insert failed (offset ${i}):`,
            batchError,
          )
        }
      }
    }
  }

  revalidatePath('/settings/legal')
  revalidatePath(`/settings/legal/${slug}`)

  return { publishedVersionId, publishedVersion }
}

// 更新文档设置（requires_re_consent / is_active）
export async function updateDocumentSettings(
  slug: string,
  settings: { requires_re_consent?: boolean; is_active?: boolean },
) {
  const { adminUserId } = await requireAdmin()
  const supabase = getServiceRoleClient()

  // 查询文档当前信息
  const { data: doc, error: docError } = await supabase
    .from('legal_documents')
    .select('id, title, current_version, requires_re_consent, is_active')
    .eq('slug', slug)
    .single()

  if (docError || !doc) throw new Error(docError?.message ?? 'Document not found')

  // 构建更新对象（只更新传入的字段）
  const updatePayload: Record<string, unknown> = {
    updated_at: new Date().toISOString(),
  }
  if (settings.requires_re_consent !== undefined) {
    updatePayload.requires_re_consent = settings.requires_re_consent
  }
  if (settings.is_active !== undefined) {
    updatePayload.is_active = settings.is_active
  }

  const { error: updateError } = await supabase
    .from('legal_documents')
    .update(updatePayload)
    .eq('id', doc.id)

  if (updateError) throw new Error(updateError.message)

  // 写入审计日志
  await writeAuditLog(supabase, {
    userId: adminUserId,
    actorId: adminUserId,
    actorRole: 'admin',
    eventType: 'document_setting_changed',
    documentId: doc.id,
    documentSlug: slug,
    documentTitle: doc.title,
    documentVersion: doc.current_version,
    details: {
      changes: settings,
      previous: {
        requires_re_consent: doc.requires_re_consent,
        is_active: doc.is_active,
      },
    },
    platform: 'admin',
  })

  revalidatePath('/settings/legal')
  revalidatePath(`/settings/legal/${slug}`)
}

// 获取用户法律时间线（分页，按 created_at DESC）
export async function getUserLegalTimeline(
  userId: string,
  page: number,
  pageSize: number = 20,
  eventTypeFilter?: string,
) {
  await requireAdmin()
  const supabase = getServiceRoleClient()

  const from = (page - 1) * pageSize
  const to = from + pageSize - 1

  let query = supabase
    .from('legal_audit_log')
    .select('*', { count: 'exact' })
    .eq('user_id', userId)
    .order('created_at', { ascending: false })
    .range(from, to)

  if (eventTypeFilter) {
    query = query.eq('event_type', eventTypeFilter)
  }

  const { data, count, error } = await query

  if (error) throw new Error(error.message)

  return {
    items: data ?? [],
    total: count ?? 0,
    page,
    pageSize,
    totalPages: Math.ceil((count ?? 0) / pageSize),
  }
}

// 获取用户当前同意状态（与 legal_documents 的 current_version 对比）
export async function getUserConsentStatus(userId: string) {
  await requireAdmin()
  const supabase = getServiceRoleClient()

  // 获取所有激活的法律文档
  const { data: documents, error: docError } = await supabase
    .from('legal_documents')
    .select('id, slug, title, document_type, current_version, requires_re_consent, is_active')
    .eq('is_active', true)
    .order('created_at', { ascending: true })

  if (docError) throw new Error(docError.message)

  // 获取用户的所有同意记录
  const { data: consents, error: consentError } = await supabase
    .from('user_consents')
    .select('document_id, version, consented_at')
    .eq('user_id', userId)

  if (consentError) throw new Error(consentError.message)

  // 构建同意状态映射（每个文档取最新版本的同意记录）
  const consentMap = new Map<string, { version: number; consented_at: string }>()
  for (const consent of consents ?? []) {
    const existing = consentMap.get(consent.document_id)
    if (!existing || consent.version > existing.version) {
      consentMap.set(consent.document_id, {
        version: consent.version,
        consented_at: consent.consented_at,
      })
    }
  }

  // 对比每个文档的当前版本和用户同意版本
  const statuses = (documents ?? []).map((doc) => {
    const consent = consentMap.get(doc.id)
    const isUpToDate = consent ? consent.version >= doc.current_version : false

    return {
      document_id: doc.id,
      slug: doc.slug,
      title: doc.title,
      document_type: doc.document_type,
      current_version: doc.current_version,
      requires_re_consent: doc.requires_re_consent,
      consented_version: consent?.version ?? null,
      consented_at: consent?.consented_at ?? null,
      is_up_to_date: isUpToDate,
      needs_re_consent: doc.requires_re_consent && !isUpToDate,
    }
  })

  return statuses
}

// 导出用户法律时间线全量数据（CSV 或 JSON 格式）
export async function exportUserLegalTimeline(
  userId: string,
  format: 'csv' | 'json',
) {
  await requireAdmin()
  const supabase = getServiceRoleClient()

  // 查询全量审计日志
  const { data, error } = await supabase
    .from('legal_audit_log')
    .select('*')
    .eq('user_id', userId)
    .order('created_at', { ascending: false })

  if (error) throw new Error(error.message)

  const rows = data ?? []

  if (format === 'json') {
    return {
      format: 'json' as const,
      data: JSON.stringify(rows, null, 2),
      filename: `legal-timeline-${userId}.json`,
    }
  }

  // CSV 格式
  if (rows.length === 0) {
    return {
      format: 'csv' as const,
      data: '',
      filename: `legal-timeline-${userId}.csv`,
    }
  }

  const headers = [
    'id',
    'user_id',
    'actor_id',
    'actor_role',
    'event_type',
    'document_id',
    'document_slug',
    'document_title',
    'document_version',
    'details',
    'ip_address',
    'user_agent',
    'device_info',
    'app_version',
    'platform',
    'locale',
    'created_at',
    'integrity_hash',
  ]

  // CSV 转义辅助函数
  const escapeCsv = (value: unknown): string => {
    if (value === null || value === undefined) return ''
    const str = typeof value === 'object' ? JSON.stringify(value) : String(value)
    // 如果包含逗号、双引号或换行，用双引号包裹并转义内部双引号
    if (str.includes(',') || str.includes('"') || str.includes('\n')) {
      return `"${str.replace(/"/g, '""')}"`
    }
    return str
  }

  const csvLines = [headers.join(',')]
  for (const row of rows) {
    const values = headers.map((h) => escapeCsv((row as Record<string, unknown>)[h]))
    csvLines.push(values.join(','))
  }

  return {
    format: 'csv' as const,
    data: csvLines.join('\n'),
    filename: `legal-timeline-${userId}.csv`,
  }
}

// ─── 占位符管理 ─────────────────────────────────────

// 获取所有占位符配置
export async function getLegalPlaceholders() {
  await requireAdmin()
  const serviceClient = getServiceRoleClient()

  const { data, error } = await serviceClient
    .from('legal_placeholders')
    .select('*')
    .order('key', { ascending: true })

  if (error) throw new Error(error.message)
  return data ?? []
}

// 更新占位符值
export async function updateLegalPlaceholder(key: string, value: string) {
  await requireAdmin()
  const serviceClient = getServiceRoleClient()

  const { error } = await serviceClient
    .from('legal_placeholders')
    .update({ value })
    .eq('key', key)

  if (error) throw new Error(error.message)
  revalidatePath('/settings/legal')
  revalidatePath('/settings/legal/placeholders')
}

// 批量更新占位符
export async function updateLegalPlaceholders(updates: { key: string; value: string }[]) {
  await requireAdmin()
  const serviceClient = getServiceRoleClient()

  for (const { key, value } of updates) {
    const { error } = await serviceClient
      .from('legal_placeholders')
      .update({ value })
      .eq('key', key)

    if (error) throw new Error(`Failed to update ${key}: ${error.message}`)
  }

  revalidatePath('/settings/legal')
  revalidatePath('/settings/legal/placeholders')
}

// 使用占位符渲染文档内容（预览用）
export async function renderDocumentWithPlaceholders(contentHtml: string) {
  await requireAdmin()
  const serviceClient = getServiceRoleClient()

  const { data, error } = await serviceClient
    .rpc('render_legal_document', { p_content_html: contentHtml })

  if (error) throw new Error(error.message)
  return data as string
}
