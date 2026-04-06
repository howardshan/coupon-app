'use server'

import { revalidatePath } from 'next/cache'
import { createClient } from '@/lib/supabase/server'
import { getServiceRoleClient } from '@/lib/supabase/service'

// 权限校验：仅 admin 可操作
async function requireAdmin() {
  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()
  if (!user) throw new Error('Unauthorized')

  const { data: profile } = await supabase
    .from('users')
    .select('role')
    .eq('id', user.id)
    .single()

  if (profile?.role !== 'admin') throw new Error('Forbidden')
  return user
}

// ── 通用类型 ──
interface SlideBase {
  id: string
  image_url: string
  sort_order: number
}

export interface WelcomeSlide extends SlideBase {
  link_type: 'deal' | 'merchant' | 'external' | 'none'
  link_value?: string
}

export interface OnboardingSlide extends SlideBase {
  title: string
  subtitle: string
  cta_label?: string
}

// ── Splash 配置 ──

export async function getSplashConfig() {
  const supabase = getServiceRoleClient()
  const { data } = await supabase
    .from('splash_configs')
    .select('*')
    .order('created_at', { ascending: false })
  return data ?? []
}

export async function updateSplashConfig(
  configId: string,
  slides: WelcomeSlide[],
  durationSeconds: number
) {
  await requireAdmin()
  const supabase = getServiceRoleClient()

  const { error } = await supabase
    .from('splash_configs')
    .update({
      slides: JSON.parse(JSON.stringify(slides)),
      duration_seconds: durationSeconds,
      updated_at: new Date().toISOString(),
    })
    .eq('id', configId)

  if (error) throw new Error(error.message)
  revalidatePath('/settings/splash')
}

export async function activateSplashConfig(configId: string) {
  await requireAdmin()
  const supabase = getServiceRoleClient()

  // 先将所有配置设为 inactive
  await supabase
    .from('splash_configs')
    .update({ is_active: false })
    .neq('id', configId)

  // 再激活目标配置
  const { error } = await supabase
    .from('splash_configs')
    .update({ is_active: true, updated_at: new Date().toISOString() })
    .eq('id', configId)

  if (error) throw new Error(error.message)
  revalidatePath('/settings/splash')
}

export async function deactivateSplashConfig(configId: string) {
  await requireAdmin()
  const supabase = getServiceRoleClient()

  const { error } = await supabase
    .from('splash_configs')
    .update({ is_active: false, updated_at: new Date().toISOString() })
    .eq('id', configId)

  if (error) throw new Error(error.message)
  revalidatePath('/settings/splash')
}

export async function createSplashConfig(slides: WelcomeSlide[], durationSeconds: number) {
  const user = await requireAdmin()
  const supabase = getServiceRoleClient()

  const { error } = await supabase
    .from('splash_configs')
    .insert({
      slides: JSON.parse(JSON.stringify(slides)),
      duration_seconds: durationSeconds,
      is_active: false,
      created_by: user.id,
    })

  if (error) throw new Error(error.message)
  revalidatePath('/settings/splash')
}

// ── Onboarding 配置 ──

export async function getOnboardingConfig() {
  const supabase = getServiceRoleClient()
  const { data } = await supabase
    .from('onboarding_configs')
    .select('*')
    .order('created_at', { ascending: false })
  return data ?? []
}

export async function updateOnboardingConfig(
  configId: string,
  slides: OnboardingSlide[]
) {
  await requireAdmin()
  const supabase = getServiceRoleClient()

  const { error } = await supabase
    .from('onboarding_configs')
    .update({
      slides: JSON.parse(JSON.stringify(slides)),
      updated_at: new Date().toISOString(),
    })
    .eq('id', configId)

  if (error) throw new Error(error.message)
  revalidatePath('/settings/onboarding')
}

export async function activateOnboardingConfig(configId: string) {
  await requireAdmin()
  const supabase = getServiceRoleClient()

  await supabase
    .from('onboarding_configs')
    .update({ is_active: false })
    .neq('id', configId)

  const { error } = await supabase
    .from('onboarding_configs')
    .update({ is_active: true, updated_at: new Date().toISOString() })
    .eq('id', configId)

  if (error) throw new Error(error.message)
  revalidatePath('/settings/onboarding')
}

export async function deactivateOnboardingConfig(configId: string) {
  await requireAdmin()
  const supabase = getServiceRoleClient()

  const { error } = await supabase
    .from('onboarding_configs')
    .update({ is_active: false, updated_at: new Date().toISOString() })
    .eq('id', configId)

  if (error) throw new Error(error.message)
  revalidatePath('/settings/onboarding')
}

// ── Banner 配置 ──

export async function getBannerConfig() {
  const supabase = getServiceRoleClient()
  const { data } = await supabase
    .from('banner_configs')
    .select('*')
    .order('created_at', { ascending: false })
  return data ?? []
}

export async function updateBannerConfig(
  configId: string,
  slides: WelcomeSlide[],
  autoPlaySeconds: number
) {
  await requireAdmin()
  const supabase = getServiceRoleClient()

  const { error } = await supabase
    .from('banner_configs')
    .update({
      slides: JSON.parse(JSON.stringify(slides)),
      auto_play_seconds: autoPlaySeconds,
      updated_at: new Date().toISOString(),
    })
    .eq('id', configId)

  if (error) throw new Error(error.message)
  revalidatePath('/settings/banner')
}

export async function activateBannerConfig(configId: string) {
  await requireAdmin()
  const supabase = getServiceRoleClient()

  await supabase
    .from('banner_configs')
    .update({ is_active: false })
    .neq('id', configId)

  const { error } = await supabase
    .from('banner_configs')
    .update({ is_active: true, updated_at: new Date().toISOString() })
    .eq('id', configId)

  if (error) throw new Error(error.message)
  revalidatePath('/settings/banner')
}

export async function deactivateBannerConfig(configId: string) {
  await requireAdmin()
  const supabase = getServiceRoleClient()

  const { error } = await supabase
    .from('banner_configs')
    .update({ is_active: false, updated_at: new Date().toISOString() })
    .eq('id', configId)

  if (error) throw new Error(error.message)
  revalidatePath('/settings/banner')
}
