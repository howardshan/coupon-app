'use client'

import { useState } from 'react'

// ── 通用类型 ──
export interface WelcomeSlideData {
  id: string
  image_url: string
  link_type: 'deal' | 'merchant' | 'external' | 'none'
  link_value: string
  sort_order: number
}

export interface OnboardingSlideData {
  id: string
  image_url: string
  title: string
  subtitle: string
  sort_order: number
}

// ── Splash / Banner Slide 编辑器 ──
export function WelcomeSlidesEditor({
  slides: initialSlides,
  onSave,
  saving,
  durationSeconds: initialDuration,
  onDurationChange,
  durationLabel,
}: {
  slides: WelcomeSlideData[]
  onSave: (slides: WelcomeSlideData[]) => void
  saving: boolean
  durationSeconds?: number
  onDurationChange?: (v: number) => void
  durationLabel?: string
}) {
  const [slides, setSlides] = useState<WelcomeSlideData[]>(initialSlides)
  const [editIdx, setEditIdx] = useState<number | null>(null)

  function addSlide() {
    const newSlide: WelcomeSlideData = {
      id: crypto.randomUUID(),
      image_url: '',
      link_type: 'none',
      link_value: '',
      sort_order: slides.length,
    }
    setSlides([...slides, newSlide])
    setEditIdx(slides.length)
  }

  function removeSlide(idx: number) {
    setSlides(slides.filter((_, i) => i !== idx).map((s, i) => ({ ...s, sort_order: i })))
    setEditIdx(null)
  }

  function moveSlide(idx: number, dir: -1 | 1) {
    const target = idx + dir
    if (target < 0 || target >= slides.length) return
    const next = [...slides]
    ;[next[idx], next[target]] = [next[target], next[idx]]
    setSlides(next.map((s, i) => ({ ...s, sort_order: i })))
  }

  function updateSlide(idx: number, patch: Partial<WelcomeSlideData>) {
    setSlides(slides.map((s, i) => (i === idx ? { ...s, ...patch } : s)))
  }

  return (
    <div className="space-y-4">
      {/* Duration / AutoPlay 设置 */}
      {durationLabel && onDurationChange && initialDuration !== undefined && (
        <div className="flex items-center gap-3 mb-4">
          <label className="text-sm font-medium text-gray-700">{durationLabel}</label>
          <input
            type="number"
            min={2}
            max={10}
            value={initialDuration}
            onChange={e => onDurationChange(Number(e.target.value))}
            className="w-20 px-3 py-1.5 border border-gray-300 rounded-lg text-sm"
          />
          <span className="text-sm text-gray-500">seconds</span>
        </div>
      )}

      {/* Slide 列表 */}
      {slides.map((slide, idx) => (
        <div key={slide.id} className="bg-white rounded-xl border border-gray-200 px-5 py-4">
          <div className="flex items-start gap-4">
            {/* 排序按钮 */}
            <div className="flex flex-col gap-1 pt-1">
              <button
                type="button"
                onClick={() => moveSlide(idx, -1)}
                disabled={idx === 0}
                className="text-gray-400 hover:text-gray-600 disabled:opacity-30 text-xs"
              >▲</button>
              <button
                type="button"
                onClick={() => moveSlide(idx, 1)}
                disabled={idx === slides.length - 1}
                className="text-gray-400 hover:text-gray-600 disabled:opacity-30 text-xs"
              >▼</button>
            </div>

            {/* 缩略图 */}
            <div className="w-20 h-14 bg-gray-100 rounded-lg overflow-hidden flex-shrink-0">
              {slide.image_url ? (
                <img src={slide.image_url} alt="" className="w-full h-full object-cover" />
              ) : (
                <div className="w-full h-full flex items-center justify-center text-gray-400 text-xs">
                  No image
                </div>
              )}
            </div>

            {/* 信息 */}
            <div className="flex-1 min-w-0">
              <p className="text-sm font-medium text-gray-900">Slide {idx + 1}</p>
              <p className="text-xs text-gray-500 truncate">
                Link: {slide.link_type}{slide.link_value ? ` → ${slide.link_value}` : ''}
              </p>
            </div>

            {/* 操作按钮 */}
            <div className="flex gap-2">
              <button
                type="button"
                onClick={() => setEditIdx(editIdx === idx ? null : idx)}
                className="px-3 py-1 text-xs bg-gray-100 text-gray-700 rounded-lg hover:bg-gray-200"
              >
                {editIdx === idx ? 'Close' : 'Edit'}
              </button>
              <button
                type="button"
                onClick={() => removeSlide(idx)}
                className="px-3 py-1 text-xs bg-red-50 text-red-600 rounded-lg hover:bg-red-100"
              >
                Delete
              </button>
            </div>
          </div>

          {/* 编辑面板 */}
          {editIdx === idx && (
            <div className="mt-4 pt-4 border-t border-gray-100 space-y-3">
              <div>
                <label className="block text-xs font-medium text-gray-600 mb-1">Image URL</label>
                <input
                  type="url"
                  value={slide.image_url}
                  onChange={e => updateSlide(idx, { image_url: e.target.value })}
                  placeholder="https://..."
                  className="w-full px-3 py-2 border border-gray-300 rounded-lg text-sm"
                />
              </div>
              <div>
                <label className="block text-xs font-medium text-gray-600 mb-1">Link Type</label>
                <select
                  value={slide.link_type}
                  onChange={e => updateSlide(idx, { link_type: e.target.value as WelcomeSlideData['link_type'] })}
                  className="w-full px-3 py-2 border border-gray-300 rounded-lg text-sm"
                >
                  <option value="none">No link</option>
                  <option value="deal">Deal</option>
                  <option value="merchant">Merchant</option>
                  <option value="external">External URL</option>
                </select>
              </div>
              {slide.link_type !== 'none' && (
                <div>
                  <label className="block text-xs font-medium text-gray-600 mb-1">
                    {slide.link_type === 'deal' ? 'Deal ID' : slide.link_type === 'merchant' ? 'Merchant ID' : 'URL'}
                  </label>
                  <input
                    type="text"
                    value={slide.link_value}
                    onChange={e => updateSlide(idx, { link_value: e.target.value })}
                    placeholder={slide.link_type === 'external' ? 'https://...' : 'Enter ID...'}
                    className="w-full px-3 py-2 border border-gray-300 rounded-lg text-sm"
                  />
                </div>
              )}
            </div>
          )}
        </div>
      ))}

      {/* 添加按钮 */}
      <button
        type="button"
        onClick={addSlide}
        className="w-full py-3 border-2 border-dashed border-gray-300 rounded-xl text-sm text-gray-500 hover:border-blue-400 hover:text-blue-600 transition-colors"
      >
        + Add Slide
      </button>

      {/* 保存按钮 */}
      <div className="flex justify-end pt-2">
        <button
          type="button"
          onClick={() => onSave(slides)}
          disabled={saving}
          className="px-6 py-2.5 bg-blue-600 text-white rounded-lg hover:bg-blue-700 disabled:opacity-50 text-sm font-medium"
        >
          {saving ? 'Saving...' : 'Save Changes'}
        </button>
      </div>
    </div>
  )
}

// ── Onboarding Slide 编辑器 ──
export function OnboardingSlidesEditor({
  slides: initialSlides,
  onSave,
  saving,
}: {
  slides: OnboardingSlideData[]
  onSave: (slides: OnboardingSlideData[]) => void
  saving: boolean
}) {
  const [slides, setSlides] = useState<OnboardingSlideData[]>(initialSlides)
  const [editIdx, setEditIdx] = useState<number | null>(null)

  function addSlide() {
    if (slides.length >= 5) return
    const newSlide: OnboardingSlideData = {
      id: crypto.randomUUID(),
      image_url: '',
      title: '',
      subtitle: '',
      sort_order: slides.length,
    }
    setSlides([...slides, newSlide])
    setEditIdx(slides.length)
  }

  function removeSlide(idx: number) {
    if (slides.length <= 1) return
    setSlides(slides.filter((_, i) => i !== idx).map((s, i) => ({ ...s, sort_order: i })))
    setEditIdx(null)
  }

  function moveSlide(idx: number, dir: -1 | 1) {
    const target = idx + dir
    if (target < 0 || target >= slides.length) return
    const next = [...slides]
    ;[next[idx], next[target]] = [next[target], next[idx]]
    setSlides(next.map((s, i) => ({ ...s, sort_order: i })))
  }

  function updateSlide(idx: number, patch: Partial<OnboardingSlideData>) {
    setSlides(slides.map((s, i) => (i === idx ? { ...s, ...patch } : s)))
  }

  return (
    <div className="space-y-4">
      {slides.map((slide, idx) => (
        <div key={slide.id} className="bg-white rounded-xl border border-gray-200 px-5 py-4">
          <div className="flex items-start gap-4">
            <div className="flex flex-col gap-1 pt-1">
              <button type="button" onClick={() => moveSlide(idx, -1)} disabled={idx === 0}
                className="text-gray-400 hover:text-gray-600 disabled:opacity-30 text-xs">▲</button>
              <button type="button" onClick={() => moveSlide(idx, 1)} disabled={idx === slides.length - 1}
                className="text-gray-400 hover:text-gray-600 disabled:opacity-30 text-xs">▼</button>
            </div>

            <div className="w-20 h-14 bg-gray-100 rounded-lg overflow-hidden flex-shrink-0">
              {slide.image_url ? (
                <img src={slide.image_url} alt="" className="w-full h-full object-cover" />
              ) : (
                <div className="w-full h-full flex items-center justify-center text-gray-400 text-xs">
                  No image
                </div>
              )}
            </div>

            <div className="flex-1 min-w-0">
              <p className="text-sm font-medium text-gray-900">{slide.title || `Slide ${idx + 1}`}</p>
              <p className="text-xs text-gray-500 truncate">{slide.subtitle || 'No subtitle'}</p>
            </div>

            <div className="flex gap-2">
              <button type="button" onClick={() => setEditIdx(editIdx === idx ? null : idx)}
                className="px-3 py-1 text-xs bg-gray-100 text-gray-700 rounded-lg hover:bg-gray-200">
                {editIdx === idx ? 'Close' : 'Edit'}
              </button>
              <button type="button" onClick={() => removeSlide(idx)}
                disabled={slides.length <= 1}
                className="px-3 py-1 text-xs bg-red-50 text-red-600 rounded-lg hover:bg-red-100 disabled:opacity-30">
                Delete
              </button>
            </div>
          </div>

          {editIdx === idx && (
            <div className="mt-4 pt-4 border-t border-gray-100 space-y-3">
              <div>
                <label className="block text-xs font-medium text-gray-600 mb-1">Image URL</label>
                <input type="url" value={slide.image_url}
                  onChange={e => updateSlide(idx, { image_url: e.target.value })}
                  placeholder="https://..." className="w-full px-3 py-2 border border-gray-300 rounded-lg text-sm" />
              </div>
              <div>
                <label className="block text-xs font-medium text-gray-600 mb-1">Title</label>
                <input type="text" value={slide.title}
                  onChange={e => updateSlide(idx, { title: e.target.value })}
                  placeholder="Discover Local Deals" className="w-full px-3 py-2 border border-gray-300 rounded-lg text-sm" />
              </div>
              <div>
                <label className="block text-xs font-medium text-gray-600 mb-1">Subtitle</label>
                <input type="text" value={slide.subtitle}
                  onChange={e => updateSlide(idx, { subtitle: e.target.value })}
                  placeholder="Save up to 60%..." className="w-full px-3 py-2 border border-gray-300 rounded-lg text-sm" />
              </div>
            </div>
          )}
        </div>
      ))}

      {slides.length < 5 && (
        <button type="button" onClick={addSlide}
          className="w-full py-3 border-2 border-dashed border-gray-300 rounded-xl text-sm text-gray-500 hover:border-blue-400 hover:text-blue-600 transition-colors">
          + Add Slide
        </button>
      )}

      <div className="bg-amber-50 border border-amber-200 rounded-lg px-4 py-3 text-xs text-amber-700">
        Activating will show this onboarding to first-time users only. Existing users will not see it.
      </div>

      <div className="flex justify-end pt-2">
        <button type="button" onClick={() => onSave(slides)} disabled={saving}
          className="px-6 py-2.5 bg-blue-600 text-white rounded-lg hover:bg-blue-700 disabled:opacity-50 text-sm font-medium">
          {saving ? 'Saving...' : 'Save Changes'}
        </button>
      </div>
    </div>
  )
}
