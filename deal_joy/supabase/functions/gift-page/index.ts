import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

// ----------------------------------------------------------------
// HTML 渲染辅助函数
// ----------------------------------------------------------------

/** 格式化券码为 XXXX-XXXX-XXXX-XXXX */
function formatCouponCode(code: string): string {
  const clean = code.replace(/[^a-zA-Z0-9]/g, '').toUpperCase();
  const chunks: string[] = [];
  for (let i = 0; i < clean.length; i += 4) {
    chunks.push(clean.slice(i, i + 4));
  }
  return chunks.join('-');
}

/** 格式化过期时间为人类可读格式 */
function formatExpiry(isoStr: string): string {
  try {
    const d = new Date(isoStr);
    return d.toLocaleDateString('en-US', {
      year: 'numeric',
      month: 'long',
      day: 'numeric',
    });
  } catch {
    return isoStr;
  }
}

/** 公共 HTML 头部（CSS 内联，响应式移动端）*/
function htmlHead(title: string): string {
  return `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1.0" />
  <title>${title} — CrunchyPlum</title>
  <style>
    /* ---- 全局重置 ---- */
    *, *::before, *::after { box-sizing: border-box; margin: 0; padding: 0; }
    body {
      font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif;
      background: #F7F7F7;
      color: #1A1A1A;
      min-height: 100vh;
    }

    /* ---- 顶部品牌栏 ---- */
    .header {
      background: #FF6B35;
      padding: 18px 20px;
      text-align: center;
    }
    .header-logo {
      font-size: 22px;
      font-weight: 800;
      color: #fff;
      letter-spacing: -0.5px;
    }
    .header-logo span {
      opacity: 0.85;
      font-weight: 400;
    }
    .header-tagline {
      color: rgba(255,255,255,0.85);
      font-size: 12px;
      margin-top: 2px;
    }

    /* ---- 主内容容器 ---- */
    .container {
      max-width: 480px;
      margin: 0 auto;
      padding: 20px 16px 48px;
    }

    /* ---- 卡片 ---- */
    .card {
      background: #fff;
      border-radius: 16px;
      padding: 20px;
      margin-bottom: 16px;
      box-shadow: 0 2px 12px rgba(0,0,0,0.07);
    }

    /* ---- 礼品留言卡片 ---- */
    .gift-card {
      background: linear-gradient(135deg, #FFF3EE 0%, #FFE8DC 100%);
      border: 1.5px solid #FFD0B8;
      border-radius: 16px;
      padding: 20px;
      margin-bottom: 16px;
      position: relative;
    }
    .gift-card-icon {
      font-size: 28px;
      margin-bottom: 8px;
    }
    .gift-card-from {
      font-size: 12px;
      color: #FF6B35;
      font-weight: 600;
      text-transform: uppercase;
      letter-spacing: 0.5px;
      margin-bottom: 6px;
    }
    .gift-card-message {
      font-size: 15px;
      color: #3A2A20;
      line-height: 1.55;
      font-style: italic;
    }

    /* ---- Deal 信息 ---- */
    .deal-title {
      font-size: 20px;
      font-weight: 700;
      color: #1A1A1A;
      margin-bottom: 6px;
      line-height: 1.3;
    }
    .deal-meta {
      display: flex;
      align-items: center;
      gap: 6px;
      color: #666;
      font-size: 13px;
      margin-bottom: 4px;
    }
    .deal-meta-icon { font-size: 14px; }

    /* ---- 券码区域 ---- */
    .coupon-section { text-align: center; }
    .coupon-label {
      font-size: 11px;
      font-weight: 600;
      color: #999;
      text-transform: uppercase;
      letter-spacing: 1px;
      margin-bottom: 10px;
    }
    .coupon-code {
      font-size: 24px;
      font-weight: 800;
      letter-spacing: 3px;
      color: #1A1A1A;
      background: #F0F0F0;
      border-radius: 10px;
      padding: 14px 10px;
      font-family: 'Courier New', Courier, monospace;
      word-break: break-all;
    }

    /* ---- QR 码区域 ---- */
    .qr-toggle-btn {
      display: inline-flex;
      align-items: center;
      gap: 8px;
      margin-top: 14px;
      padding: 10px 22px;
      background: #fff;
      border: 1.5px solid #FF6B35;
      color: #FF6B35;
      border-radius: 50px;
      font-size: 14px;
      font-weight: 600;
      cursor: pointer;
      transition: background 0.18s, color 0.18s;
    }
    .qr-toggle-btn:hover { background: #FF6B35; color: #fff; }
    .qr-wrap {
      display: none;
      margin-top: 16px;
      align-items: center;
      justify-content: center;
    }
    .qr-wrap.visible { display: flex; }
    .qr-wrap img {
      border-radius: 10px;
      border: 1px solid #eee;
    }

    /* ---- 分割线 ---- */
    .divider {
      height: 1px;
      background: #F0F0F0;
      margin: 16px 0;
    }

    /* ---- CTA 按钮 ---- */
    .btn-primary {
      display: block;
      width: 100%;
      padding: 15px;
      background: #FF6B35;
      color: #fff;
      border: none;
      border-radius: 12px;
      font-size: 16px;
      font-weight: 700;
      text-align: center;
      text-decoration: none;
      cursor: pointer;
      margin-bottom: 10px;
      transition: background 0.18s;
    }
    .btn-primary:hover { background: #E85A25; }
    .btn-secondary {
      display: block;
      width: 100%;
      padding: 13px;
      background: #fff;
      color: #1A1A1A;
      border: 1.5px solid #DDD;
      border-radius: 12px;
      font-size: 15px;
      font-weight: 600;
      text-align: center;
      text-decoration: none;
      cursor: pointer;
      margin-bottom: 8px;
      transition: background 0.18s;
    }
    .btn-secondary:hover { background: #F5F5F5; }
    .store-row {
      display: flex;
      gap: 10px;
      margin-top: 4px;
    }
    .store-row .btn-secondary { flex: 1; font-size: 13px; }

    /* ---- 下载引导说明文字 ---- */
    .download-hint {
      font-size: 12px;
      color: #999;
      text-align: center;
      margin-top: 8px;
      line-height: 1.5;
    }

    /* ---- 错误页 ---- */
    .error-wrap {
      display: flex;
      flex-direction: column;
      align-items: center;
      justify-content: center;
      min-height: 60vh;
      text-align: center;
      padding: 32px 24px;
    }
    .error-icon { font-size: 56px; margin-bottom: 16px; }
    .error-title {
      font-size: 20px;
      font-weight: 700;
      color: #1A1A1A;
      margin-bottom: 8px;
    }
    .error-msg { font-size: 15px; color: #666; line-height: 1.5; }
  </style>
</head>
<body>`;
}

/** 品牌顶栏 */
function renderHeader(): string {
  return `
  <div class="header">
    <div class="header-logo">CrunchyPlum<span>™</span></div>
    <div class="header-tagline">Local deals, gifted with love</div>
  </div>`;
}

/** 错误页 HTML */
function renderErrorPage(message: string, icon = '🎁'): string {
  return `${htmlHead('Gift')}
${renderHeader()}
<div class="container">
  <div class="error-wrap">
    <div class="error-icon">${icon}</div>
    <div class="error-title">Oops!</div>
    <div class="error-msg">${message}</div>
  </div>
</div>
</body></html>`;
}

/** 礼品券信息页 HTML */
function renderGiftPage(params: {
  token: string;
  giftMessage: string;
  gifterName: string;
  dealTitle: string;
  merchantName: string;
  merchantAddress: string;
  couponCode: string;
  qrCodeData: string;
  expiresAt: string | null;
}): string {
  const {
    token,
    giftMessage,
    gifterName,
    dealTitle,
    merchantName,
    merchantAddress,
    couponCode,
    qrCodeData,
    expiresAt,
  } = params;

  // 格式化券码
  const formattedCode = formatCouponCode(couponCode);
  const expiryText = expiresAt ? `Valid until ${formatExpiry(expiresAt)}` : 'No expiry date';

  // Google Chart API 生成 QR 码（使用 qr_code 原始数据）
  const qrData = encodeURIComponent(qrCodeData || couponCode);
  const qrUrl = `https://chart.googleapis.com/chart?cht=qr&chs=240x240&chl=${qrData}&choe=UTF-8`;

  // Deep Link（App Scheme）
  const deepLink = `crunchyplum://gift/claim?token=${encodeURIComponent(token)}`;

  // 礼品留言卡片（有留言时才展示）
  const messageCard = giftMessage
    ? `
  <div class="gift-card">
    <div class="gift-card-icon">💌</div>
    <div class="gift-card-from">A gift from ${gifterName || 'Someone special'}</div>
    <div class="gift-card-message">"${giftMessage}"</div>
  </div>`
    : gifterName
    ? `
  <div class="gift-card">
    <div class="gift-card-icon">🎁</div>
    <div class="gift-card-from">A gift from ${gifterName}</div>
    <div class="gift-card-message">Enjoy your treat!</div>
  </div>`
    : '';

  return `${htmlHead('Your Gift')}
${renderHeader()}
<div class="container">

  ${messageCard}

  <!-- Deal 信息卡片 -->
  <div class="card">
    <div class="deal-title">${dealTitle}</div>
    ${merchantName ? `<div class="deal-meta"><span class="deal-meta-icon">🏪</span>${merchantName}</div>` : ''}
    ${merchantAddress ? `<div class="deal-meta"><span class="deal-meta-icon">📍</span>${merchantAddress}</div>` : ''}
    <div class="deal-meta"><span class="deal-meta-icon">🗓</span>${expiryText}</div>
  </div>

  <!-- 券码卡片 -->
  <div class="card coupon-section">
    <div class="coupon-label">Your Coupon Code</div>
    <div class="coupon-code">${formattedCode}</div>

    <!-- QR 码折叠区域 -->
    <button class="qr-toggle-btn" id="qr-btn" onclick="toggleQR()">
      <span id="qr-btn-icon">🔲</span>
      <span id="qr-btn-text">Show QR Code</span>
    </button>
    <div class="qr-wrap" id="qr-wrap">
      <img src="${qrUrl}" alt="QR Code" width="200" height="200" />
    </div>
  </div>

  <!-- CTA 按钮 -->
  <div class="card">
    <a class="btn-primary" href="${deepLink}">Open in App</a>
    <div class="divider"></div>
    <p style="font-size:13px;color:#999;text-align:center;margin-bottom:10px;">
      Don't have the app yet? Download CrunchyPlum:
    </p>
    <div class="store-row">
      <a class="btn-secondary" href="https://apps.apple.com" target="_blank">🍎 App Store</a>
      <a class="btn-secondary" href="https://play.google.com" target="_blank">🤖 Google Play</a>
    </div>
    <div class="download-hint">
      Show the QR code or coupon code at the merchant to redeem.
    </div>
  </div>

</div>

<script>
  // QR 码展开/折叠
  function toggleQR() {
    var wrap = document.getElementById('qr-wrap');
    var btnText = document.getElementById('qr-btn-text');
    var btnIcon = document.getElementById('qr-btn-icon');
    var isVisible = wrap.classList.toggle('visible');
    btnText.textContent = isVisible ? 'Hide QR Code' : 'Show QR Code';
    btnIcon.textContent = isVisible ? '✕' : '🔲';
  }
</script>
</body></html>`;
}

// ----------------------------------------------------------------
// Edge Function 主入口
// ----------------------------------------------------------------
serve(async (req: Request) => {
  // gift-page 仅支持 GET 请求
  if (req.method === 'OPTIONS') {
    return new Response('ok', {
      headers: { 'Access-Control-Allow-Origin': '*' },
    });
  }

  const url = new URL(req.url);
  const token = url.searchParams.get('token');

  // token 为空 → 返回无效链接页
  if (!token) {
    return new Response(renderErrorPage('Invalid gift link.', '🔗'), {
      headers: { 'Content-Type': 'text/html; charset=utf-8' },
      status: 400,
    });
  }

  // 初始化 Supabase service role 客户端（绕过 RLS）
  const supabaseUrl = Deno.env.get('SUPABASE_URL')!;
  const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
  const supabase = createClient(supabaseUrl, serviceRoleKey);

  // ----------------------------------------------------------------
  // 1. 查询 gift 记录（JOIN order_items → deals → merchants）
  // ----------------------------------------------------------------
  const { data: gift, error: giftError } = await supabase
    .from('coupon_gifts')
    .select(`
      id,
      status,
      claimed_at,
      gift_message,
      token_expires_at,
      gifter_user_id,
      order_items!inner(
        id,
        coupon_id,
        deal_id,
        deals!inner(
          id,
          title,
          expires_at,
          merchants!inner(
            id,
            name,
            address
          )
        ),
        coupons(
          id,
          coupon_code,
          qr_code,
          expires_at,
          status
        )
      )
    `)
    .eq('claim_token', token)
    .maybeSingle();

  // token 无效（没有找到记录）
  if (giftError || !gift) {
    return new Response(renderErrorPage('Invalid gift link.', '🔗'), {
      headers: { 'Content-Type': 'text/html; charset=utf-8' },
      status: 404,
    });
  }

  // ----------------------------------------------------------------
  // 2. 状态判断
  // ----------------------------------------------------------------

  // 已撤回
  if (gift.status === 'recalled') {
    return new Response(
      renderErrorPage('This gift has been recalled. The sender has taken it back.', '↩️'),
      {
        headers: { 'Content-Type': 'text/html; charset=utf-8' },
        status: 200,
      },
    );
  }

  // 检查 token 是否超过有效期（自动标记为 expired）
  if (gift.token_expires_at && new Date(gift.token_expires_at as string) < new Date()) {
    // 若数据库还未标记，则异步更新（不阻塞响应）
    if (gift.status !== 'expired') {
      supabase
        .from('coupon_gifts')
        .update({ status: 'expired' })
        .eq('id', gift.id)
        .then(() => {});
    }
    return new Response(
      renderErrorPage('This gift link has expired.', '⏰'),
      {
        headers: { 'Content-Type': 'text/html; charset=utf-8' },
        status: 200,
      },
    );
  }

  // 已在数据库中标记 expired
  if (gift.status === 'expired') {
    return new Response(
      renderErrorPage('This gift link has expired.', '⏰'),
      {
        headers: { 'Content-Type': 'text/html; charset=utf-8' },
        status: 200,
      },
    );
  }

  // ----------------------------------------------------------------
  // 3. 提取关联数据
  // ----------------------------------------------------------------
  const orderItem = gift.order_items as any;
  const deal = orderItem?.deals as any;
  const merchant = deal?.merchants as any;
  const coupon = orderItem?.coupons as any;

  // 检查券本身是否过期
  const couponExpiresAt: string | null = (coupon?.expires_at ?? deal?.expires_at) ?? null;
  if (couponExpiresAt && new Date(couponExpiresAt) < new Date()) {
    return new Response(
      renderErrorPage('This coupon has expired.', '⏰'),
      {
        headers: { 'Content-Type': 'text/html; charset=utf-8' },
        status: 200,
      },
    );
  }

  // ----------------------------------------------------------------
  // 4. 幂等领取：pending → claimed（已 claimed 的直接展示）
  // ----------------------------------------------------------------
  if (gift.status === 'pending') {
    await supabase
      .from('coupon_gifts')
      .update({
        status: 'claimed',
        claimed_at: new Date().toISOString(),
      })
      .eq('id', gift.id);
  }

  // ----------------------------------------------------------------
  // 5. 查询赠送者姓名
  // ----------------------------------------------------------------
  let gifterName = '';
  if (gift.gifter_user_id) {
    const { data: gifterUser } = await supabase
      .from('users')
      .select('full_name')
      .eq('id', gift.gifter_user_id)
      .maybeSingle();
    gifterName = (gifterUser as any)?.full_name ?? '';
  }

  // ----------------------------------------------------------------
  // 6. 渲染礼品券页面
  // ----------------------------------------------------------------
  const html = renderGiftPage({
    token,
    giftMessage: (gift.gift_message as string) ?? '',
    gifterName,
    dealTitle: deal?.title ?? '',
    merchantName: merchant?.name ?? '',
    merchantAddress: merchant?.address ?? '',
    couponCode: coupon?.coupon_code ?? '',
    qrCodeData: coupon?.qr_code ?? coupon?.coupon_code ?? '',
    expiresAt: couponExpiresAt,
  });

  return new Response(html, {
    headers: { 'Content-Type': 'text/html; charset=utf-8' },
    status: 200,
  });
});
