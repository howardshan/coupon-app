/**
 * auth-redirect — 密码重置邮件中间跳转页
 *
 * 解决方案：
 * - 服务端 302 跳转自定义协议 → Chrome 阻止 ✗
 * - intent:// URL → Chrome 新版阻止 ✗
 * - setTimeout 自动触发 → 非用户手势，Chrome 阻止 ✗
 * - <a href="io.supabase.crunchyplum://..."> 用户点击 → Chrome 允许 ✓
 *
 * 最可靠的方案：展示一个大按钮，用户点击后通过标准 <a> 标签跳转自定义协议。
 */

const APP_SCHEME = 'io.supabase.crunchyplum';
const CALLBACK_HOST = 'login-callback';

Deno.serve(async (req: Request) => {
  const reqUrl = new URL(req.url);

  // 透传所有查询参数（code、type 等）
  const params = reqUrl.searchParams.toString();
  const paramStr = params ? `?${params}` : '';

  // 自定义协议 URL（用户点击 <a> 标签时 Chrome 允许跳转）
  const deepLinkUrl = `${APP_SCHEME}://${CALLBACK_HOST}/${paramStr}`;

  const html = `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Reset Password — Crunchy Plum</title>
  <style>
    * { box-sizing: border-box; margin: 0; padding: 0; }
    body {
      font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif;
      background: #f5f5f5;
      display: flex;
      align-items: center;
      justify-content: center;
      min-height: 100vh;
      padding: 16px;
    }
    .card {
      background: #fff;
      border-radius: 20px;
      padding: 40px 32px;
      text-align: center;
      box-shadow: 0 4px 16px rgba(0,0,0,0.10);
      max-width: 360px;
      width: 100%;
    }
    .logo {
      width: 72px;
      height: 72px;
      background: linear-gradient(135deg, #FF6B2C 0%, #FF9A57 100%);
      border-radius: 18px;
      margin: 0 auto 20px;
      display: flex;
      align-items: center;
      justify-content: center;
      font-size: 36px;
    }
    h2 {
      font-size: 22px;
      font-weight: 700;
      color: #1a1a1a;
      margin-bottom: 10px;
    }
    p {
      color: #666;
      font-size: 15px;
      line-height: 1.5;
      margin-bottom: 28px;
    }
    .btn {
      display: block;
      background: #FF6B2C;
      color: #fff;
      text-decoration: none;
      padding: 18px 24px;
      border-radius: 12px;
      font-size: 17px;
      font-weight: 700;
      letter-spacing: 0.2px;
    }
    .hint {
      margin-top: 20px;
      color: #aaa;
      font-size: 12px;
      line-height: 1.6;
    }
  </style>
</head>
<body>
  <div class="card">
    <div class="logo">🍑</div>
    <h2>Reset Your Password</h2>
    <p>Tap the button below to open the Crunchy Plum app and set your new password.</p>

    <!-- 用 <a> 标签 + 用户点击，Chrome 允许跳转自定义协议 -->
    <a class="btn" href="${deepLinkUrl}">
      Open Crunchy Plum App
    </a>

    <p class="hint">
      If the app doesn't open, make sure Crunchy Plum is installed on this device.
    </p>
  </div>
</body>
</html>`;

  return new Response(html, {
    status: 200,
    headers: {
      'Content-Type': 'text/html; charset=utf-8',
      'Cache-Control': 'no-store, no-cache',
      'X-Robots-Tag': 'noindex',
    },
  });
});
