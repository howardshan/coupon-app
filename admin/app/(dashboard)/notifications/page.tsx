import { createClient } from '@/lib/supabase/server'
import { redirect } from 'next/navigation'
import { getDealsAndMerchants, getPushCampaigns } from '@/app/actions/push-notifications'
import NotificationsPageClient from '@/components/notifications-page-client'

export const dynamic = 'force-dynamic'

export default async function NotificationsPage() {
  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()
  const { data: profile } = await supabase
    .from('users').select('role').eq('id', user!.id).single()
  if (profile?.role !== 'admin') redirect('/dashboard')

  const [{ deals, merchants }, campaigns] = await Promise.all([
    getDealsAndMerchants(),
    getPushCampaigns(),
  ])

  // Supabase join 返回数组，规范化为单对象或 null
  const normalizedDeals = (deals as unknown[]).map((d: unknown) => {
    const deal = d as { id: string; title: string; merchant_id: string; merchants: unknown }
    const m = Array.isArray(deal.merchants) ? (deal.merchants[0] ?? null) : deal.merchants
    return { id: deal.id, title: deal.title, merchants: m as { lat: number | null; lng: number | null; name: string } | null }
  })

  const normalizedCampaigns = (campaigns as unknown[]).map((c: unknown) => {
    const camp = c as { id: string; title: string; body: string; radius_meters: number; sent_user_count: number; created_at: string; deals: unknown; merchants: unknown }
    const dl = Array.isArray(camp.deals) ? (camp.deals[0] ?? null) : camp.deals
    const mc = Array.isArray(camp.merchants) ? (camp.merchants[0] ?? null) : camp.merchants
    return {
      id: camp.id,
      title: camp.title,
      body: camp.body,
      radius_meters: camp.radius_meters,
      sent_user_count: camp.sent_user_count,
      created_at: camp.created_at,
      deals: dl as { id: string; title: string } | null,
      merchants: mc as { id: string; name: string } | null,
    }
  })

  return (
    <NotificationsPageClient
      deals={normalizedDeals}
      merchants={merchants as { id: string; name: string; lat: number | null; lng: number | null }[]}
      campaigns={normalizedCampaigns}
    />
  )
}
