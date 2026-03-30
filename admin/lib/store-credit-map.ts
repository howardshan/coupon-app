// 纯函数，供 Server Component 与 Client 共用（勿放入带 'use client' 的文件）

export type StoreCreditTransactionRow = {
  id: string
  amount: number
  type: string
  description: string | null
  order_item_id: string | null
  created_at: string
}

function parseAmount(raw: unknown): number {
  const n = Number(raw)
  return Number.isFinite(n) ? n : 0
}

export function mapStoreCreditTransaction(r: Record<string, unknown>): StoreCreditTransactionRow {
  return {
    id: String(r.id),
    amount: parseAmount(r.amount),
    type: String(r.type ?? ''),
    description: r.description != null ? String(r.description) : null,
    order_item_id: r.order_item_id != null ? String(r.order_item_id) : null,
    created_at: String(r.created_at ?? ''),
  }
}
