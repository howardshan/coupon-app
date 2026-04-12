/**
 * 审批相关 server action 成功后 revalidateTag，用于失效其它可能依赖该 tag 的缓存（如未来若恢复角标缓存）。
 * 当前 dashboard layout 侧边栏待审数为每次请求实时查询，不依赖此 tag。
 */
export const APPROVALS_PENDING_COUNT_TAG = 'approvals-pending-count'
