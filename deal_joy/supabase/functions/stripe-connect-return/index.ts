Deno.serve(async (req: Request) => {
  const url = new URL(req.url)
  const status = url.searchParams.get('status')

  // 直接跳回商家 App，iOS/Android 系统会拦截 deep link 打开 App
  const deepLink = status === 'refresh'
    ? 'crunchyplum-merchant://stripe-connect-refresh'
    : 'crunchyplum-merchant://stripe-connect-return'

  return new Response(null, {
    status: 302,
    headers: { 'Location': deepLink },
  })
})
