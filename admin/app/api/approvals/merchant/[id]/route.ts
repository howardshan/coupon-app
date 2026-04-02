import { NextRequest, NextResponse } from 'next/server'
import { createClient } from '@/lib/supabase/server'
import { getServiceRoleClient } from '@/lib/supabase/service'

export async function GET(
  _req: NextRequest,
  { params }: { params: Promise<{ id: string }> }
) {
  // 验证 admin 身份
  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()
  if (!user) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })

  const { data: profile } = await supabase
    .from('users')
    .select('role')
    .eq('id', user.id)
    .single()

  if (!profile || profile.role !== 'admin') {
    return NextResponse.json({ error: 'Forbidden' }, { status: 403 })
  }

  const { id } = await params
  const db = getServiceRoleClient()

  // 商家完整信息
  const { data: merchant, error: merchantError } = await db
    .from('merchants')
    .select(
      'id, user_id, name, company_name, description, contact_name, contact_email, phone, category, ein, address, status, rejection_reason, submitted_at, created_at'
    )
    .eq('id', id)
    .single()

  if (merchantError || !merchant) {
    return NextResponse.json({ error: 'Merchant not found' }, { status: 404 })
  }

  // 上传的证件材料
  const { data: documents } = await db
    .from('merchant_documents')
    .select('id, document_type, file_url, file_name, uploaded_at')
    .eq('merchant_id', id)
    .order('uploaded_at', { ascending: true })

  return NextResponse.json({ merchant, documents: documents ?? [] })
}
