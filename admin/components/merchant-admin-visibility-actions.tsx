'use client'

import { useTransition } from 'react'
import { useRouter } from 'next/navigation'
import { toast } from 'sonner'
import { adminSetMerchantStoreOnline } from '@/app/actions/admin'

type Props = {
  merchantId: string
  /** 当前对消费者是否在线展示 */
  isOnline: boolean
}

/**
 * 已通过审核门店：管理员强制上下线（写入 merchant_activity_events）
 */
export default function MerchantAdminVisibilityActions({ merchantId, isOnline }: Props) {
  const router = useRouter()
  const [pending, startTransition] = useTransition()

  function run(next: boolean) {
    startTransition(async () => {
      try {
        await adminSetMerchantStoreOnline(merchantId, next)
        toast.success(next ? 'Store set online' : 'Store set offline')
        router.refresh()
      } catch (e) {
        toast.error(e instanceof Error ? e.message : 'Action failed')
      }
    })
  }

  return (
    <div className="flex flex-wrap gap-2">
      {isOnline ? (
        <button
          type="button"
          disabled={pending}
          onClick={() => run(false)}
          className="px-3 py-1.5 text-xs font-medium rounded-lg border border-slate-300 bg-white text-slate-800 hover:bg-slate-50 disabled:opacity-50"
        >
          Take offline (admin)
        </button>
      ) : (
        <button
          type="button"
          disabled={pending}
          onClick={() => run(true)}
          className="px-3 py-1.5 text-xs font-medium rounded-lg border border-emerald-600 bg-emerald-600 text-white hover:bg-emerald-700 disabled:opacity-50"
        >
          Put online (admin)
        </button>
      )}
    </div>
  )
}
