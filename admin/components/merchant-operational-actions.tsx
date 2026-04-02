'use client'

import { useTransition } from 'react'
import { useRouter } from 'next/navigation'
import { toast } from 'sonner'
import { approveMerchant, revokeMerchantApproval } from '@/app/actions/admin'

interface MerchantOperationalActionsProps {
  merchantId: string
  merchantUserId: string
  status: string
}

/**
 * Merchant 详情页运营操作：待审入驻在统一审批中心处理；
 * 此处恢复已通过商家的「撤销认证」与已拒绝商家的「批准」。
 */
export default function MerchantOperationalActions({
  merchantId,
  merchantUserId,
  status,
}: MerchantOperationalActionsProps) {
  const router = useRouter()
  const [isPending, startTransition] = useTransition()

  if (status === 'pending') {
    return null
  }

  function handleApprove() {
    startTransition(async () => {
      try {
        await approveMerchant(merchantId, merchantUserId)
        toast.success('Merchant approved')
        router.refresh()
      } catch (e) {
        toast.error(e instanceof Error ? e.message : 'Action failed')
      }
    })
  }

  function handleRevoke() {
    if (!confirm('Revoke approval and put this merchant back under review?')) return
    startTransition(async () => {
      try {
        await revokeMerchantApproval(merchantId)
        toast.success('Approval revoked. Merchant is pending review again.')
        router.refresh()
      } catch (e) {
        toast.error(e instanceof Error ? e.message : 'Action failed')
      }
    })
  }

  return (
    <div className="flex flex-wrap items-center justify-end gap-2">
      {status === 'approved' && (
        <button
          type="button"
          onClick={handleRevoke}
          disabled={isPending}
          className="px-4 py-2 text-sm font-medium rounded-lg border border-amber-300 bg-amber-100 text-amber-800 shadow-sm hover:bg-amber-200 disabled:opacity-50 transition-colors"
        >
          Revoke approval
        </button>
      )}
      {status === 'rejected' && (
        <button
          type="button"
          onClick={handleApprove}
          disabled={isPending}
          className="px-4 py-2 text-sm font-medium rounded-lg border border-green-600 bg-green-600 text-white shadow-sm hover:bg-green-700 disabled:opacity-50 transition-colors"
        >
          Approve
        </button>
      )}
    </div>
  )
}
