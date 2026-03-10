/**
 * Service role Supabase client — 仅服务端、仅用于管理员写操作，绕过 RLS。
 * 不要暴露到前端，不要使用 NEXT_PUBLIC_* 的 key。
 */
import { createServerClient } from '@supabase/ssr'

export function getServiceRoleClient() {
  const url = process.env.NEXT_PUBLIC_SUPABASE_URL
  const serviceRoleKey = process.env.SUPABASE_SERVICE_ROLE_KEY

  if (!url || !serviceRoleKey) {
    throw new Error('SUPABASE_SERVICE_ROLE_KEY or URL is not set. Add it to .env.local for admin write operations.')
  }

  return createServerClient(url, serviceRoleKey, {
    cookies: {
      getAll() { return [] },
      setAll() {},
    },
  })
}
