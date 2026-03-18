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

async function callPlatformAfterSales(path: string, token: string, init?: RequestInit) {
  if (!SUPABASE_URL || !SERVICE_ROLE_KEY) {
    throw new Response('Supabase environment missing', { status: 500 })
  }
  const url = new URL(`/functions/v1/platform-after-sales${path}`, SUPABASE_URL)
  const headers = new Headers(init?.headers)
  headers.set('apikey', SERVICE_ROLE_KEY)
  headers.set('Authorization', `Bearer ${token}`)
  if (!headers.has('Content-Type') && init?.body) {
    headers.set('Content-Type', 'application/json')
  }
  const response = await fetch(url, {
    ...init,
    headers,
    cache: 'no-store',
  })
  const data = await response.json().catch(() => ({}))
  if (!response.ok) {
    const message = typeof data?.message === 'string' ? data.message : 'Request failed'
    throw new Response(message, { status: response.status })
  }
  return data
}

export async function GET(_req: NextRequest, { params }: { params: { id: string } }) {
  try {
    const token = await requireAdminToken()
    const data = await callPlatformAfterSales(`/${params.id}?access_token=${encodeURIComponent(token)}`, token, {
      method: 'GET',
    })
    return NextResponse.json(data)
  } catch (err) {
    if (err instanceof Response) {
      return new NextResponse(await err.text(), { status: err.status })
    }
    return NextResponse.json({ message: (err as Error).message }, { status: 500 })
  }
}

export async function POST(req: NextRequest, { params }: { params: { id: string } }) {
  try {
    const token = await requireAdminToken()
    const body = await req.json().catch(() => ({}))
    const action = typeof body?.action === 'string' ? body.action : ''
    if (action !== 'approve' && action !== 'reject') {
      return NextResponse.json({ message: 'action must be approve or reject' }, { status: 400 })
    }
    const payload: Record<string, unknown> = {
      note: body?.note,
      attachments: body?.attachments ?? [],
      access_token: token,
    }
    const data = await callPlatformAfterSales(`/${params.id}/${action}`, token, {
      method: 'POST',
      body: JSON.stringify(payload),
    })
    return NextResponse.json(data)
  } catch (err) {
    if (err instanceof Response) {
      return new NextResponse(await err.text(), { status: err.status })
    }
    return NextResponse.json({ message: (err as Error).message }, { status: 500 })
  }
}
