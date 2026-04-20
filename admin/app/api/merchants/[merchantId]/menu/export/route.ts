import { createClient } from '@/lib/supabase/server'
import { getServiceRoleClient } from '@/lib/supabase/service'

function escapeCsvField(s: string): string {
  if (s.includes(',') || s.includes('"') || s.includes('\n')) {
    return `"${s.replace(/"/g, '""')}"`
  }
  return s
}

export async function GET(
  _req: Request,
  { params }: { params: Promise<{ merchantId: string }> }
) {
  const { merchantId } = await params
  const supabase = await createClient()
  const {
    data: { user },
  } = await supabase.auth.getUser()
  if (!user) {
    return new Response('Unauthorized', { status: 401 })
  }
  const { data: profile } = await supabase.from('users').select('role').eq('id', user.id).single()
  if (profile?.role !== 'admin') {
    return new Response('Forbidden', { status: 403 })
  }

  const db = getServiceRoleClient()
  const { data, error } = await db
    .from('menu_items')
    .select('id, name, price')
    .eq('merchant_id', merchantId)
    .order('sort_order', { ascending: true })
    .order('created_at', { ascending: true })
  if (error) {
    return new Response(error.message, { status: 500 })
  }
  const rows = data ?? []
  const bodyLines = [
    'id,name,price',
    ...rows.map((r) => {
      const p = r.price as number | null
      return `${r.id as string},${escapeCsvField(String(r.name))},${p == null ? '' : String(p)}`
    }),
  ]
  const body = '\uFEFF' + bodyLines.join('\r\n')
  return new Response(body, {
    headers: {
      'Content-Type': 'text/csv; charset=utf-8',
      'Content-Disposition': `attachment; filename="menu-items-${merchantId.slice(0, 8)}.csv"`,
    },
  })
}
