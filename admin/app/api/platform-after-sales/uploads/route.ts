import { NextRequest, NextResponse } from 'next/server'
import { createClient } from '@/lib/supabase/server'

const SUPABASE_URL = process.env.NEXT_PUBLIC_SUPABASE_URL
const SERVICE_ROLE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY

async function requireAdminToken() {
  const supabase = await createClient()
  const { data: { session } } = await supabase.auth.getSession()
  if (!session) {
    throw new Response('Unauthorized', { status: 401 })
  }
  const { data: profile } = await supabase
    .from('users')
    .select('role')
    .eq('id', session.user.id)
    .single()
  if (!profile || (profile.role !== 'admin' && profile.role !== 'super_admin')) {
    throw new Response('Forbidden', { status: 403 })
  }
  return session.access_token
}

export async function POST(req: NextRequest) {
  try {
    if (!SUPABASE_URL || !SERVICE_ROLE_KEY) {
      return NextResponse.json({ message: 'Supabase environment missing' }, { status: 500 })
    }
    const token = await requireAdminToken()
    const body = await req.json().catch(() => ({}))
    const files = Array.isArray(body?.files) ? body.files : []
    if (!files.length) {
      return NextResponse.json({ message: 'files array required' }, { status: 400 })
    }
    const url = new URL('/functions/v1/platform-after-sales/uploads', SUPABASE_URL)
    const response = await fetch(url, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        apikey: SERVICE_ROLE_KEY,
        Authorization: `Bearer ${token}`,
      },
      cache: 'no-store',
      body: JSON.stringify({ ...body, access_token: token }),
    })
    const data = await response.json().catch(() => ({}))
    if (!response.ok) {
      return NextResponse.json(data, { status: response.status })
    }
    return NextResponse.json(data)
  } catch (err) {
    if (err instanceof Response) {
      const text = (await err.text()).trim()
      return NextResponse.json(
        { message: text || 'Request failed' },
        { status: err.status },
      )
    }
    return NextResponse.json({ message: (err as Error).message }, { status: 500 })
  }
}
