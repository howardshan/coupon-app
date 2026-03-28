'use client'

import { useState } from 'react'
import { toast } from 'sonner'
import { WelcomeSlidesEditor, type WelcomeSlideData } from '@/components/slides-editor'
import { updateBannerConfig } from '@/app/actions/welcome-config'

interface BannerConfigEditorProps {
  config: {
    id: string
    auto_play_seconds: number
    slides: WelcomeSlideData[]
    is_active: boolean
  } | null
}

export default function BannerConfigEditor({ config }: BannerConfigEditorProps) {
  const [saving, setSaving] = useState(false)
  const [autoPlay, setAutoPlay] = useState(config?.auto_play_seconds ?? 3)

  if (!config) {
    return (
      <div className="bg-gray-50 rounded-xl border border-gray-200 px-8 py-12 text-center">
        <p className="text-gray-500">No banner configuration found.</p>
      </div>
    )
  }

  async function handleSave(slides: WelcomeSlideData[]) {
    setSaving(true)
    try {
      await updateBannerConfig(config!.id, slides as any, autoPlay)
      toast.success('Banner configuration saved')
    } catch (e: any) {
      toast.error(e.message || 'Failed to save')
    } finally {
      setSaving(false)
    }
  }

  return (
    <WelcomeSlidesEditor
      slides={config.slides ?? []}
      onSave={handleSave}
      saving={saving}
      durationSeconds={autoPlay}
      onDurationChange={setAutoPlay}
      durationLabel="Auto-play interval"
    />
  )
}
