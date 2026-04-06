import { NextRequest, NextResponse } from 'next/server'
import { createClient } from '@/lib/supabase/server'
import { createClient as createServiceClient } from '@supabase/supabase-js'

const SUPABASE_URL = process.env.NEXT_PUBLIC_SUPABASE_URL!
const SERVICE_ROLE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY!

// 通用图片上传接口，上传到 admin-uploads bucket
export async function POST(req: NextRequest) {
  try {
    // 鉴权：仅 admin / super_admin
    const supabase = await createClient()
    const { data: { session } } = await supabase.auth.getSession()
    if (!session) {
      return NextResponse.json({ message: 'Unauthorized' }, { status: 401 })
    }
    const { data: profile } = await supabase
      .from('users')
      .select('role')
      .eq('id', session.user.id)
      .single()
    if (!profile || (profile.role !== 'admin' && profile.role !== 'super_admin')) {
      return NextResponse.json({ message: 'Forbidden' }, { status: 403 })
    }

    // 解析文件
    const formData = await req.formData()
    const file = formData.get('file') as File | null
    const folder = (formData.get('folder') as string) || 'general'

    if (!file) {
      return NextResponse.json({ message: 'file is required' }, { status: 400 })
    }

    // 校验类型和大小
    const allowedTypes = ['image/jpeg', 'image/png', 'image/webp', 'image/gif']
    if (!allowedTypes.includes(file.type)) {
      return NextResponse.json({ message: 'Only JPEG, PNG, WebP, GIF allowed' }, { status: 400 })
    }
    if (file.size > 5 * 1024 * 1024) {
      return NextResponse.json({ message: 'File size must be under 5MB' }, { status: 400 })
    }

    // 生成文件路径
    const ext = file.name.split('.').pop() || 'jpg'
    const fileName = `${folder}/${Date.now()}_${crypto.randomUUID().slice(0, 8)}.${ext}`

    // 使用 service role client 上传
    const serviceClient = createServiceClient(SUPABASE_URL, SERVICE_ROLE_KEY)
    const buffer = await file.arrayBuffer()

    const { error } = await serviceClient.storage
      .from('admin-uploads')
      .upload(fileName, buffer, {
        contentType: file.type,
        upsert: false,
      })

    if (error) {
      return NextResponse.json({ message: error.message }, { status: 500 })
    }

    // 返回公开 URL
    const { data: urlData } = serviceClient.storage
      .from('admin-uploads')
      .getPublicUrl(fileName)

    return NextResponse.json({ url: urlData.publicUrl })
  } catch (err) {
    return NextResponse.json({ message: (err as Error).message }, { status: 500 })
  }
}
