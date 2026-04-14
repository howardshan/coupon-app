'use server'

import { getServiceRoleClient } from '@/lib/supabase/service'
import { createClient } from '@/lib/supabase/server'

// 月度税费报表行（与 Supabase RPC get_tax_revenue_report 输出一致）
export type TaxRevenueRow = {
  metroArea: string
  redeemedCount: number
  grossRevenue: number
  taxCollected: number
  platformCommission: number
  brandCommission: number
  stripeFee: number
  netToMerchants: number
}

// 权限校验：仅 admin 可查看
async function assertAdmin() {
  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()
  if (!user) return false
  const { data: profile } = await supabase
    .from('users')
    .select('role')
    .eq('id', user.id)
    .single()
  return profile?.role === 'admin'
}

/**
 * 拉取指定月份的税费/营业额报表
 * @param yearMonth YYYY-MM 格式（如 '2026-04'）
 */
export async function getTaxRevenueReport(
  yearMonth: string,
): Promise<{ rows?: TaxRevenueRow[]; error?: string }> {
  if (!/^\d{4}-\d{2}$/.test(yearMonth)) {
    return { error: 'Invalid month format, expected YYYY-MM' }
  }

  const ok = await assertAdmin()
  if (!ok) return { error: 'Forbidden' }

  const service = getServiceRoleClient()
  const { data, error } = await service.rpc('get_tax_revenue_report', {
    p_year_month: yearMonth,
  })

  if (error) return { error: error.message }

  const rows: TaxRevenueRow[] = (data ?? []).map((r: any) => ({
    metroArea: r.metro_area as string,
    redeemedCount: Number(r.redeemed_count ?? 0),
    grossRevenue: Number(r.gross_revenue ?? 0),
    taxCollected: Number(r.tax_collected ?? 0),
    platformCommission: Number(r.platform_commission ?? 0),
    brandCommission: Number(r.brand_commission ?? 0),
    stripeFee: Number(r.stripe_fee ?? 0),
    netToMerchants: Number(r.net_to_merchants ?? 0),
  }))

  return { rows }
}

/**
 * 导出 CSV 字符串（client 端触发下载）
 * 返回内容行 + 表头，前端用 Blob + a[download] 存为文件
 */
export async function exportTaxRevenueCsv(
  yearMonth: string,
): Promise<{ csv?: string; filename?: string; error?: string }> {
  const { rows, error } = await getTaxRevenueReport(yearMonth)
  if (error || !rows) return { error: error ?? 'Unknown error' }

  const header = [
    'metro_area',
    'redeemed_count',
    'gross_revenue',
    'tax_collected',
    'platform_commission',
    'brand_commission',
    'stripe_fee',
    'net_to_merchants',
  ].join(',')

  const lines = rows.map((r) =>
    [
      r.metroArea,
      r.redeemedCount,
      r.grossRevenue.toFixed(2),
      r.taxCollected.toFixed(2),
      r.platformCommission.toFixed(2),
      r.brandCommission.toFixed(2),
      r.stripeFee.toFixed(2),
      r.netToMerchants.toFixed(2),
    ].join(','),
  )

  // 合计行
  const totals = rows.reduce(
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

  lines.push(
    [
      'TOTAL',
      totals.redeemedCount,
      totals.grossRevenue.toFixed(2),
      totals.taxCollected.toFixed(2),
      totals.platformCommission.toFixed(2),
      totals.brandCommission.toFixed(2),
      totals.stripeFee.toFixed(2),
      totals.netToMerchants.toFixed(2),
    ].join(','),
  )

  return {
    csv: [header, ...lines].join('\n'),
    filename: `tax-revenue-${yearMonth}.csv`,
  }
}
