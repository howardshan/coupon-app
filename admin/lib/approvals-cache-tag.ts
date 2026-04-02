/**
 * 与 dashboard layout 中 unstable_cache 的 tags 一致。
 * 任意审批类操作成功后应 revalidateTag，否则侧边栏待审角标可能滞留最多 5 分钟。
 */
export const APPROVALS_PENDING_COUNT_TAG = 'approvals-pending-count'
