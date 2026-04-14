import { createClient } from '@/lib/supabase/server'
import { redirect } from 'next/navigation'
import { getTaxRevenueReport } from '@/app/actions/tax-revenue'
import TaxRevenueTable from './tax-revenue-table'

// 月度税费 / 营业额统计页（基于已 redeem 且未退款的 order_items）
// 税归属按 order_items.tax_metro_area 快照分组（下单时锁定的主门店 metro_area）
export default async function TaxRevenuePage({
  searchParams,
}: {
  searchParams: Promise<{ month?: string }>
}) {
  const { month } = await searchParams

  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()
  const { data: profile } = await supabase
    .from('users')
    .select('role')
    .eq('id', user!.id)
    .single()

  if (profile?.role !== 'admin') redirect('/dashboard')

  // 默认当前月份
  const now = new Date()
  const defaultMonth = `${now.getFullYear()}-${String(now.getMonth() + 1).padStart(2, '0')}`
  const yearMonth = month ?? defaultMonth

  const { rows, error } = await getTaxRevenueReport(yearMonth)

  // 计算合计
  const totals = (rows ?? []).reduce(
    (acc, r) => ({
      redeemedCount: acc.redeemedCount + r.redeemedCount,
      grossRevenue: acc.grossRevenue + r.grossRevenue,
      taxCollected: acc.taxCollected + r.taxCollected,
      platformCommission: acc.platformCommission + r.platformCommission,
      brandCommission: acc.brandCommission + r.brandCommission,
      stripeFee: acc.stripeFee + r.stripeFee,
      netToMerchants: acc.netToMerchants + r.netToMerchants,
    }),
    {
      redeemedCount: 0,
      grossRevenue: 0,
      taxCollected: 0,
      platformCommission: 0,
      brandCommission: 0,
      stripeFee: 0,
      netToMerchants: 0,
    },
  )

  return (
    <div className="p-6">
      <div className="mb-6">
        <h1 className="text-2xl font-bold text-gray-900">Tax Revenue Report</h1>
        <p className="mt-1 text-sm text-gray-500">
          Monthly sales tax &amp; gross revenue by city, based on redeemed vouchers (excludes refunded).
          Tax is attributed to each order&rsquo;s purchase-time merchant metro area (snapshot).
        </p>
      </div>

      <TaxRevenueTable
        yearMonth={yearMonth}
        rows={rows ?? []}
        totals={totals}
        errorMessage={error}
      />
    </div>
  )
}
