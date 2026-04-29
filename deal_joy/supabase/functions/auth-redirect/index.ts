/**
 * auth-redirect — 密码重置邮件中间跳转页
 *
 * 成功路径：带 PKCE code → 302 / HTML 按钮唤起 App。
 * 失败路径：302 到自有域名静态页（避免部分 iOS WebKit 对 *.supabase.co 返回的 HTML 当纯文本展示）。
 */

const APP_SCHEME = "io.supabase.crunchyplum";
const CALLBACK_HOST = "login-callback";
const ANDROID_PACKAGE = "com.crunchyplum.crunchy_plum";
const FALLBACK_URL = "https://crunchyplum.com";

/** 与 web/auth/reset-link-expired/index.html 对应，需部署到 crunchyplum.com */
const RESET_LINK_EXPIRED_URL = "https://crunchyplum.com/auth/reset-link-expired/";

/** 302 附带 fallback HTML 时的响应头 */
function htmlBridgeHeaders(location: string): Headers {
  return new Headers({
    Location: location,
    "Content-Type": "text/html; charset=UTF-8",
    "X-Content-Type-Options": "nosniff",
    "Cache-Control": "no-store, no-cache",
  });
}

Deno.serve(async (req: Request) => {
  const reqUrl = new URL(req.url);
  const err = reqUrl.searchParams.get("error");
  const errCode = reqUrl.searchParams.get("error_code");

  const isAuthFailure =
    err === "access_denied" ||
    errCode === "otp_expired" ||
    errCode === "otp_disabled" ||
    reqUrl.searchParams.has("error_description");

  // 自有域名托管 HTML，Safari / Gmail WebView 均按正常网页渲染
  if (isAuthFailure) {
    return new Response(null, {
      status: 302,
      headers: new Headers({
        Location: RESET_LINK_EXPIRED_URL,
        "Cache-Control": "no-store, no-cache",
      }),
    });
  }

  const params = reqUrl.searchParams.toString();
  const paramStr = params ? `?${params}` : "";

  const deepLinkUrl = `${APP_SCHEME}://${CALLBACK_HOST}/${paramStr}`;
  const intentUri =
    `intent://${CALLBACK_HOST}/${paramStr}#Intent;scheme=${APP_SCHEME};package=${ANDROID_PACKAGE};S.browser_fallback_url=${encodeURIComponent(FALLBACK_URL)};end`;

  const ua = req.headers.get("user-agent") ?? "";
  const isIOS = /iPhone|iPad|iPod/i.test(ua);
  const buttonHref = isIOS ? deepLinkUrl : intentUri;

  const body = `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta http-equiv="Content-Type" content="text/html; charset=UTF-8">
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
    headers: htmlBridgeHeaders(deepLinkUrl),
  });
});
