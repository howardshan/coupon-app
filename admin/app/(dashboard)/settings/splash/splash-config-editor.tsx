'use client'

import { useState } from 'react'
import { toast } from 'sonner'
import { WelcomeSlidesEditor, type WelcomeSlideData } from '@/components/slides-editor'
import { updateSplashConfig } from '@/app/actions/welcome-config'

interface SplashConfigEditorProps {
  config: {
    id: string
    duration_seconds: number
    slides: WelcomeSlideData[]
    is_active: boolean
  } | null
}

export default function SplashConfigEditor({ config }: SplashConfigEditorProps) {
  const [saving, setSaving] = useState(false)
  const [duration, setDuration] = useState(config?.duration_seconds ?? 5)

  if (!config) {
    return (
      <div className="bg-gray-50 rounded-xl border border-gray-200 px-8 py-12 text-center">
        <p className="text-gray-500">No splash configuration found.</p>
      </div>
    )
  }

  async function handleSave(slides: WelcomeSlideData[]) {
    setSaving(true)
    try {
      await updateSplashConfig(config!.id, slides as any, duration)
      toast.success('Splash configuration saved')
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
      durationSeconds={duration}
      onDurationChange={setDuration}
      durationLabel="Duration per slide"
    />
  )
}
