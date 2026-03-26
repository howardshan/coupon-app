'use server'

import { createClient } from '@/lib/supabase/server'

// 权限校验：仅 admin 可操作推荐算法配置
async function requireAdmin() {
  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()
  if (!user) return null

  const { data: profile } = await supabase
    .from('users')
    .select('role')
    .eq('id', user.id)
    .single()

  if (profile?.role !== 'admin') return null
  return supabase
}

// Edge Function 调用辅助
const SUPABASE_URL = process.env.NEXT_PUBLIC_SUPABASE_URL!
const SERVICE_ROLE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY!

async function callEdgeFunction(body: Record<string, unknown>) {
  const res = await fetch(
    `${SUPABASE_URL}/functions/v1/parse-recommendation-config`,
    {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${SERVICE_ROLE_KEY}`,
      },
      body: JSON.stringify(body),
    }
  )

  if (!res.ok) {
    const text = await res.text()
    throw new Error(`Edge Function error (${res.status}): ${text}`)
  }

  return res.json()
}

// 解析算法描述：调用 Edge Function 生成权重配置
export async function parseAlgorithm(description: string) {
  const supabase = await requireAdmin()
  if (!supabase) return { error: 'Forbidden' }

  try {
    const result = await callEdgeFunction({
      action: 'parse',
      description,
    })
    return { data: result }
  } catch (e: unknown) {
    const msg = e instanceof Error ? e.message : 'Unknown error'
    return { error: msg }
  }
}

// 激活指定配置
export async function activateConfig(configId: string) {
  const supabase = await requireAdmin()
  if (!supabase) return { error: 'Forbidden' }

  try {
    const result = await callEdgeFunction({
      action: 'activate',
      config_id: configId,
    })
    return { data: result }
  } catch (e: unknown) {
    const msg = e instanceof Error ? e.message : 'Unknown error'
    return { error: msg }
  }
}

// 获取配置历史列表
export async function listConfigs() {
  const supabase = await requireAdmin()
  if (!supabase) return { error: 'Forbidden' }

  try {
    const result = await callEdgeFunction({
      action: 'list',
    })
    return { data: result }
  } catch (e: unknown) {
    const msg = e instanceof Error ? e.message : 'Unknown error'
    return { error: msg }
  }
}

// 恢复历史配置
export async function restoreConfig(configId: string) {
  const supabase = await requireAdmin()
  if (!supabase) return { error: 'Forbidden' }

  try {
    const result = await callEdgeFunction({
      action: 'restore',
      config_id: configId,
    })
    return { data: result }
  } catch (e: unknown) {
    const msg = e instanceof Error ? e.message : 'Unknown error'
    return { error: msg }
  }
}
