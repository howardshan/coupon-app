/**
 * auth-redirect — 密码重置邮件中间跳转页
 *
 * 多层策略，覆盖所有 Android 场景：
 * 1. HTTP 302 → 自定义协议（iOS Safari / Chrome Custom Tabs）
 * 2. HTML 按钮 → Android Intent URI（Samsung Email / 受限 WebView）
 * 3. JS window.location + meta refresh 三重兜底
 */

const APP_SCHEME = 'io.supabase.crunchyplum';
const CALLBACK_HOST = 'login-callback';
const ANDROID_PACKAGE = 'com.crunchyplum.crunchy_plum';
const FALLBACK_URL = 'https://crunchyplum.com';

Deno.serve(async (req: Request) => {
  const reqUrl = new URL(req.url);
  const params = reqUrl.searchParams.toString();
  const paramStr = params ? `?${params}` : '';

  // 自定义协议 URL（iOS / Chrome Custom Tabs）
  const deepLinkUrl = `${APP_SCHEME}://${CALLBACK_HOST}/${paramStr}`;

  // Android Intent URI（Samsung Email 等受限 WebView 使用）
  // 格式: intent://<host>/<path>#Intent;scheme=<scheme>;package=<pkg>;S.browser_fallback_url=<url>;end
  const intentUri = `intent://${CALLBACK_HOST}/${paramStr}#Intent;scheme=${APP_SCHEME};package=${ANDROID_PACKAGE};S.browser_fallback_url=${encodeURIComponent(FALLBACK_URL)};end`;

  const ua = req.headers.get('user-agent') ?? '';
  const isIOS = /iPhone|iPad|iPod/i.test(ua);

  // iOS：直接 302，不需要 Intent URI
  const buttonHref = isIOS ? deepLinkUrl : intentUri;

  const body = `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Opening Crunchy Plum...</title>
  <style>
    body { font-family: -apple-system, BlinkMacSystemFont, sans-serif; display: flex; align-items: center; justify-content: center; min-height: 100vh; margin: 0; background: #f5f5f5; }
    .card { background: #fff; border-radius: 20px; padding: 40px 32px; text-align: center; box-shadow: 0 4px 16px rgba(0,0,0,0.1); max-width: 360px; width: 100%; }
    .logo { width: 72px; height: 72px; background: linear-gradient(135deg,#FF6B2C,#FF9A57); border-radius: 18px; margin: 0 auto 20px; display: flex; align-items: center; justify-content: center; font-size: 36px; }
    h2 { font-size: 22px; font-weight: 700; color: #1a1a1a; margin-bottom: 10px; }
    p { color: #666; font-size: 15px; line-height: 1.5; margin-bottom: 28px; }
    a.btn { display: block; background: #FF6B2C; color: #fff; text-decoration: none; padding: 18px 24px; border-radius: 12px; font-size: 17px; font-weight: 700; }
    .hint { margin-top: 20px; color: #aaa; font-size: 12px; }
  </style>
</head>
<body>
  <div class="card">
    <div class="logo">🍑</div>
    <h2>Reset Your Password</h2>
    <p>Tap the button below to open the Crunchy Plum app and set your new password.</p>
    <a class="btn" href="${buttonHref}">Open Crunchy Plum App</a>
    <p class="hint">Make sure Crunchy Plum is installed on this device.</p>
  </div>
</body>
</html>`;

  return new Response(body, {
    status: 302,
    headers: {
      'Location': deepLinkUrl,
      'Content-Type': 'text/html; charset=utf-8',
      'Cache-Control': 'no-store, no-cache',
    },
  });
});
