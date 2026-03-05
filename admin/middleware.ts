import { createServerClient } from '@supabase/ssr'
import { NextResponse, type NextRequest } from 'next/server'

export async function middleware(request: NextRequest) {
  let supabaseResponse = NextResponse.next({ request })

  const supabase = createServerClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
    {
      cookies: {
        getAll() {
          return request.cookies.getAll()
        },
        setAll(cookiesToSet) {
          cookiesToSet.forEach(({ name, value }) => request.cookies.set(name, value))
          supabaseResponse = NextResponse.next({ request })
          cookiesToSet.forEach(({ name, value, options }) =>
            supabaseResponse.cookies.set(name, value, options)
          )
        },
      },
    }
  )

  const { data: { user } } = await supabase.auth.getUser()
  const { pathname } = request.nextUrl

  // 未登录且访问非登录页，跳转到登录页（重定向时带上 Supabase 可能更新的 cookie）
  if (!user && pathname !== '/login') {
    const redirectRes = NextResponse.redirect(new URL('/login', request.url))
    supabaseResponse.cookies.getAll().forEach((c) =>
      redirectRes.cookies.set(c.name, c.value, { path: c.path ?? '/' })
    )
    return redirectRes
  }

  // 已登录且访问登录页：仅 admin/merchant 才重定向到 dashboard，避免普通用户被 layout 踢回 login 形成重定向循环
  if (user && pathname === '/login') {
    const { data: profile } = await supabase
      .from('users')
      .select('role')
      .eq('id', user.id)
      .single()
    if (profile && (profile.role === 'admin' || profile.role === 'merchant')) {
      const redirectRes = NextResponse.redirect(new URL('/dashboard', request.url))
      supabaseResponse.cookies.getAll().forEach((c) =>
        redirectRes.cookies.set(c.name, c.value, { path: c.path ?? '/' })
      )
      return redirectRes
    }
  }

  return supabaseResponse
}

export const config = {
  matcher: ['/((?!_next/static|_next/image|favicon.ico|.*\\.(?:svg|png|jpg|jpeg|gif|webp)$).*)'],
}
