'use client'

import type { ReactNode } from 'react'

/** 列表表格区域：固定最大高度可滚动（与订单页原 OrdersTableContainer 一致） */
export default function AdminListScrollArea({ children }: { children: ReactNode }) {
  return (
    <div className="relative max-h-[70vh] w-full max-w-full min-w-0 overflow-auto">
      {children}
    </div>
  )
}
