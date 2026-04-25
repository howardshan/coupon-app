type Props = {
  tipsEnabled: boolean
  tipsMode: string | null
  tipsPreset1: number | null
  tipsPreset2: number | null
  tipsPreset3: number | null
  titleClassName?: string
  valueClassName?: string
  gridClassName?: string
}

function formatTipPreset(mode: string, value: number): string {
  if (mode === 'fixed') return `$${value.toFixed(2)}`
  return `${value % 1 === 0 ? value.toFixed(0) : value}%`
}

export default function DealTipsSummary({
  tipsEnabled,
  tipsMode,
  tipsPreset1,
  tipsPreset2,
  tipsPreset3,
  titleClassName = 'text-gray-500',
  valueClassName = 'font-medium text-gray-900',
  gridClassName = 'grid grid-cols-1 sm:grid-cols-2 gap-x-4 gap-y-3 text-sm',
}: Props) {
  if (!tipsEnabled) {
    return <p className="text-sm text-gray-600">Disabled</p>
  }

  const mode = tipsMode === 'fixed' ? 'fixed' : 'percent'
  const presets = [tipsPreset1, tipsPreset2, tipsPreset3]
    .filter((v): v is number => v != null && Number.isFinite(Number(v)))
    .map((v) => formatTipPreset(mode, Number(v)))

  return (
    <dl className={gridClassName}>
      <div>
        <dt className={titleClassName}>Status</dt>
        <dd className={valueClassName}>Enabled</dd>
      </div>
      <div>
        <dt className={titleClassName}>Mode</dt>
        <dd className={valueClassName}>
          {mode === 'fixed' ? 'Fixed (USD)' : 'Percent of purchase'}
        </dd>
      </div>
      <div className="sm:col-span-2">
        <dt className={titleClassName}>{mode === 'fixed' ? 'Presets (USD)' : 'Presets (%)'}</dt>
        <dd className={valueClassName}>{presets.length > 0 ? presets.join(' · ') : 'None configured'}</dd>
      </div>
      <div className="sm:col-span-2">
        <dt className={titleClassName}>Customer UI</dt>
        <dd className={valueClassName}>Preset buttons + custom amount (including $0)</dd>
      </div>
    </dl>
  )
}
