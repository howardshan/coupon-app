'use client'

import { useEffect, useState } from 'react'

/** 后台列表/搜索用旋转指示器 */
export default function AdminSpinnerIcon({
  className,
  size = 24,
}: {
  className?: string
  size?: number
}) {
  const [angle, setAngle] = useState(0)
  useEffect(() => {
    let rafId: number
    const tick = () => {
      setAngle((a) => (a + 6) % 360)
      rafId = requestAnimationFrame(tick)
    }
    rafId = requestAnimationFrame(tick)
    return () => cancelAnimationFrame(rafId)
  }, [])
  return (
    <svg
      className={className}
      width={size}
      height={size}
      style={{ display: 'block', transform: `rotate(${angle}deg)` }}
      xmlns="http://www.w3.org/2000/svg"
      fill="none"
      viewBox="0 0 24 24"
      aria-hidden
    >
      <circle
        cx="12"
        cy="12"
        r="10"
        stroke="#6b7280"
        strokeWidth="3"
        strokeLinecap="round"
        strokeDasharray="31.4 31.4"
        strokeDashoffset="10"
      />
    </svg>
  )
}
