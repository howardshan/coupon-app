'use client'

import { useState } from 'react'
import { toast } from 'sonner'
import { OnboardingSlidesEditor, type OnboardingSlideData } from '@/components/slides-editor'
import { updateOnboardingConfig } from '@/app/actions/welcome-config'

interface OnboardingConfigEditorProps {
  config: {
    id: string
    slides: OnboardingSlideData[]
    is_active: boolean
  } | null
}

export default function OnboardingConfigEditor({ config }: OnboardingConfigEditorProps) {
  const [saving, setSaving] = useState(false)

  if (!config) {
    return (
      <div className="bg-gray-50 rounded-xl border border-gray-200 px-8 py-12 text-center">
        <p className="text-gray-500">No onboarding configuration found.</p>
      </div>
    )
  }

  async function handleSave(slides: OnboardingSlideData[]) {
    setSaving(true)
    try {
      await updateOnboardingConfig(config!.id, slides as any)
      toast.success('Onboarding configuration saved')
    } catch (e: any) {
      toast.error(e.message || 'Failed to save')
    } finally {
      setSaving(false)
    }
  }

  return (
    <OnboardingSlidesEditor
      slides={config.slides ?? []}
      onSave={handleSave}
      saving={saving}
    />
  )
}
