import type { ReactNode } from 'react'

/** 列表页表格横向滚动容器，配合主区 p-4 使用负边距贴边滚动 */
export default function AdminTableScroll({ children }: { children: ReactNode }) {
  return (
    <div className="w-full min-w-0 overflow-x-auto -mx-4 px-4 sm:mx-0 sm:px-0">{children}</div>
  )
}
