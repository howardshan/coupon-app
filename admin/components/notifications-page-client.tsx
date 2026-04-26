'use client'

import { useState, useTransition } from 'react'
import { toast } from 'sonner'
import { previewGeoNotification, sendGeoNotification } from '@/app/actions/push-notifications'

const RADIUS_OPTIONS = [
  { label: '10 miles', value: 16093 },
  { label: '25 miles', value: 40234 },
  { label: '50 miles', value: 80467 },
  { label: '100 miles', value: 160934 },
]

type Deal = { id: string; title: string; merchants: { lat: number | null; lng: number | null; name: string } | null }
type Merchant = { id: string; name: string; lat: number | null; lng: number | null }
type Campaign = {
  id: string; title: string; body: string; radius_meters: number
  sent_user_count: number; created_at: string
  deals: { id: string; title: string } | null
  merchants: { id: string; name: string } | null
}

interface Props {
  deals: Deal[]
  merchants: Merchant[]
  campaigns: Campaign[]
}

export default function NotificationsPageClient({ deals, merchants, campaigns: initialCampaigns }: Props) {
  const [isPending, startTransition] = useTransition()
  const [targetType, setTargetType] = useState<'deal' | 'merchant'>('deal')
  const [selectedDealId, setSelectedDealId] = useState('')
  const [selectedMerchantId, setSelectedMerchantId] = useState('')
  const [radiusMeters, setRadiusMeters] = useState(40234)
  const [title, setTitle] = useState('')
  const [body, setBody] = useState('')
  const [previewCount, setPreviewCount] = useState<number | null>(null)
  const [campaigns, setCampaigns] = useState(initialCampaigns)

  const getTargetCoords = (): { lat: number; lng: number } | null => {
    if (targetType === 'deal') {
      const deal = deals.find(d => d.id === selectedDealId)
      if (!deal?.merchants?.lat || !deal?.merchants?.lng) return null
      return { lat: deal.merchants.lat, lng: deal.merchants.lng }
    }
    const merchant = merchants.find(m => m.id === selectedMerchantId)
    if (!merchant?.lat || !merchant?.lng) return null
    return { lat: merchant.lat, lng: merchant.lng }
  }

  const handlePreview = () => {
    const coords = getTargetCoords()
    if (!coords) { toast.error('Please select a deal or merchant with location data'); return }
    startTransition(async () => {
      const { count, error } = await previewGeoNotification(coords.lat, coords.lng, radiusMeters)
      if (error) { toast.error(error); return }
      setPreviewCount(count)
    })
  }

  const handleSend = () => {
    const coords = getTargetCoords()
    if (!coords) { toast.error('Please select a deal or merchant with location data'); return }
    if (!title.trim() || !body.trim()) { toast.error('Title and message are required'); return }
    startTransition(async () => {
      const { success, sentCount, error } = await sendGeoNotification({
        title: title.trim(),
        body: body.trim(),
        dealId: targetType === 'deal' ? selectedDealId : undefined,
        merchantId: targetType === 'merchant' ? selectedMerchantId : undefined,
        targetLat: coords.lat,
        targetLng: coords.lng,
        radiusMeters,
      })
      if (!success) { toast.error(error || 'Failed to send'); return }
      toast.success(`Sent to ${sentCount} users!`)
      setTitle(''); setBody(''); setPreviewCount(null)
      // 乐观更新历史列表
      setCampaigns(prev => [{
        id: Date.now().toString(),
        title: title.trim(),
        body: body.trim(),
        radius_meters: radiusMeters,
        sent_user_count: sentCount ?? 0,
        created_at: new Date().toISOString(),
        deals: targetType === 'deal' ? { id: selectedDealId, title: deals.find(d => d.id === selectedDealId)?.title ?? '' } : null,
        merchants: targetType === 'merchant' ? { id: selectedMerchantId, name: merchants.find(m => m.id === selectedMerchantId)?.name ?? '' } : null,
      }, ...prev])
    })
  }

  return (
    <div className="space-y-8">
      <div>
        <h1 className="text-2xl font-bold text-gray-900">Push Notifications</h1>
        <p className="mt-1 text-sm text-gray-500">Send geo-targeted push notifications to nearby users</p>
      </div>

      <div className="rounded-xl border border-gray-200 bg-white p-6 space-y-5">
        <h2 className="text-base font-semibold text-gray-900">New Campaign</h2>

        <div className="flex gap-3">
          {(['deal', 'merchant'] as const).map(t => (
            <button key={t} onClick={() => { setTargetType(t); setPreviewCount(null) }}
              className={`px-4 py-2 rounded-lg text-sm font-medium transition-colors ${targetType === t ? 'bg-blue-600 text-white' : 'bg-gray-100 text-gray-700 hover:bg-gray-200'}`}>
              {t === 'deal' ? 'By Deal' : 'By Merchant'}
            </button>
          ))}
        </div>

        {targetType === 'deal' ? (
          <div>
            <label className="block text-sm font-medium text-gray-700 mb-1">Select Deal</label>
            <select value={selectedDealId} onChange={e => { setSelectedDealId(e.target.value); setPreviewCount(null) }}
              className="w-full px-3 py-2 border border-gray-300 rounded-lg bg-white text-gray-900">
              <option value="">-- Choose a deal --</option>
              {deals.map(d => <option key={d.id} value={d.id}>{d.title}{d.merchants ? ` (${d.merchants.name})` : ''}</option>)}
            </select>
          </div>
        ) : (
          <div>
            <label className="block text-sm font-medium text-gray-700 mb-1">Select Merchant</label>
            <select value={selectedMerchantId} onChange={e => { setSelectedMerchantId(e.target.value); setPreviewCount(null) }}
              className="w-full px-3 py-2 border border-gray-300 rounded-lg bg-white text-gray-900">
              <option value="">-- Choose a merchant --</option>
              {merchants.map(m => <option key={m.id} value={m.id}>{m.name}</option>)}
            </select>
          </div>
        )}

        <div>
          <label className="block text-sm font-medium text-gray-700 mb-1">Radius</label>
          <div className="flex gap-2 flex-wrap">
            {RADIUS_OPTIONS.map(opt => (
              <button key={opt.value} onClick={() => { setRadiusMeters(opt.value); setPreviewCount(null) }}
                className={`px-3 py-1.5 rounded-lg text-sm font-medium transition-colors ${radiusMeters === opt.value ? 'bg-blue-600 text-white' : 'bg-gray-100 text-gray-700 hover:bg-gray-200'}`}>
                {opt.label}
              </button>
            ))}
          </div>
        </div>

        <div>
          <label className="block text-sm font-medium text-gray-700 mb-1">Title</label>
          <input type="text" value={title} onChange={e => setTitle(e.target.value)}
            placeholder="e.g. New Deal Near You!" maxLength={65}
            className="w-full px-3 py-2 border border-gray-300 rounded-lg" />
          <p className="mt-1 text-xs text-gray-400">{title.length}/65</p>
        </div>

        <div>
          <label className="block text-sm font-medium text-gray-700 mb-1">Message</label>
          <textarea value={body} onChange={e => setBody(e.target.value)}
            placeholder="e.g. Crave & Cook now offers 40% off — tap to check it out!"
            rows={3} maxLength={178} className="w-full px-3 py-2 border border-gray-300 rounded-lg resize-none" />
          <p className="mt-1 text-xs text-gray-400">{body.length}/178</p>
        </div>

        <div className="flex items-center gap-3 pt-2">
          <button onClick={handlePreview} disabled={isPending || (!selectedDealId && !selectedMerchantId)}
            className="px-4 py-2 rounded-lg border border-gray-300 text-sm text-gray-700 hover:bg-gray-50 disabled:opacity-40">
            Preview Audience
          </button>
          {previewCount !== null && (
            <span className="text-sm text-gray-600 font-medium">~<strong>{previewCount}</strong> users in range</span>
          )}
          <button onClick={handleSend} disabled={isPending || !title || !body || (!selectedDealId && !selectedMerchantId)}
            className="ml-auto px-5 py-2 rounded-lg bg-blue-600 text-white text-sm font-medium hover:bg-blue-700 disabled:opacity-40 transition-colors">
            {isPending ? 'Sending...' : 'Send Now'}
          </button>
        </div>
      </div>

      <div className="rounded-xl border border-gray-200 bg-white overflow-hidden">
        <div className="px-6 py-4 border-b border-gray-100">
          <h2 className="text-base font-semibold text-gray-900">Campaign History</h2>
        </div>
        {campaigns.length === 0 ? (
          <p className="px-6 py-8 text-sm text-gray-400 text-center">No campaigns sent yet.</p>
        ) : (
          <table className="w-full text-sm">
            <thead className="bg-gray-50 text-xs text-gray-500 uppercase">
              <tr>
                <th className="px-4 py-3 text-left">Title</th>
                <th className="px-4 py-3 text-left">Target</th>
                <th className="px-4 py-3 text-left">Radius</th>
                <th className="px-4 py-3 text-right">Sent</th>
                <th className="px-4 py-3 text-left">Date</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-gray-100">
              {campaigns.map(c => (
                <tr key={c.id} className="hover:bg-gray-50">
                  <td className="px-4 py-3 font-medium text-gray-900">{c.title}</td>
                  <td className="px-4 py-3 text-gray-600">{c.deals?.title ?? c.merchants?.name ?? '—'}</td>
                  <td className="px-4 py-3 text-gray-600">{Math.round(c.radius_meters / 1609.34)} mi</td>
                  <td className="px-4 py-3 text-right font-medium">{c.sent_user_count}</td>
                  <td className="px-4 py-3 text-gray-500">{new Date(c.created_at).toLocaleDateString()}</td>
                </tr>
              ))}
            </tbody>
          </table>
        )}
      </div>
    </div>
  )
}
