// =============================================================
// Crunchy Plum FCM 推送通知共享模块
// 封装 Firebase Cloud Messaging HTTP v1 API 调用逻辑
// =============================================================

import { SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2";
import {
  create,
  getNumericDate,
} from "https://deno.land/x/djwt@v3.0.2/mod.ts";

// ---- OAuth2 Access Token 缓存 ----
let _cachedToken: string | null = null;
let _tokenExpiresAt = 0;

/**
 * 使用 Service Account 私钥签发 JWT，换取 OAuth2 access_token
 * 结果会缓存，过期前不会重复请求
 */
async function getAccessToken(): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  if (_cachedToken && now < _tokenExpiresAt - 60) {
    return _cachedToken;
  }

  const clientEmail = Deno.env.get("FIREBASE_CLIENT_EMAIL");
  const privateKeyPem = Deno.env.get("FIREBASE_PRIVATE_KEY")?.replace(
    /\\n/g,
    "\n"
  );

  if (!clientEmail || !privateKeyPem) {
    throw new Error(
      "Missing FIREBASE_CLIENT_EMAIL or FIREBASE_PRIVATE_KEY env vars"
    );
  }

  // 解析 PEM 私钥为 CryptoKey
  const pemBody = privateKeyPem
    .replace("-----BEGIN PRIVATE KEY-----", "")
    .replace("-----END PRIVATE KEY-----", "")
    .replace(/\s/g, "");
  const binaryDer = Uint8Array.from(atob(pemBody), (c) => c.charCodeAt(0));
  const cryptoKey = await crypto.subtle.importKey(
    "pkcs8",
    binaryDer,
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"]
  );

  const iat = now;
  const exp = iat + 3600;

  const jwt = await create(
    { alg: "RS256", typ: "JWT" },
    {
      iss: clientEmail,
      scope: "https://www.googleapis.com/auth/firebase.messaging",
      aud: "https://oauth2.googleapis.com/token",
      iat: getNumericDate(0) + iat - Math.floor(Date.now() / 1000),
      exp: getNumericDate(3600),
    },
    cryptoKey
  );

  // 用 JWT 换取 access_token
  const resp = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion: jwt,
    }),
  });

  if (!resp.ok) {
    const body = await resp.text();
    throw new Error(`Failed to get access token: ${resp.status} ${body}`);
  }

  const data = await resp.json();
  _cachedToken = data.access_token;
  _tokenExpiresAt = now + (data.expires_in ?? 3600);
  return _cachedToken!;
}

/**
 * 向单个设备发送 FCM 推送
 * 返回 true 表示成功，false 表示 token 无效（应删除）
 */
export async function sendToDevice(
  token: string,
  title: string,
  body: string,
  data: Record<string, string> = {}
): Promise<boolean> {
  const projectId = Deno.env.get("FIREBASE_PROJECT_ID");
  if (!projectId) {
    throw new Error("Missing FIREBASE_PROJECT_ID env var");
  }

  const accessToken = await getAccessToken();

  const resp = await fetch(
    `https://fcm.googleapis.com/v1/projects/${projectId}/messages:send`,
    {
      method: "POST",
      headers: {
        Authorization: `Bearer ${accessToken}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        message: {
          token,
          notification: { title, body },
          data,
          // Android 高优先级确保后台收到
          android: {
            priority: "high",
            notification: {
              channel_id: "crunchyplum_notifications",
            },
          },
          // iOS APNs 配置
          apns: {
            payload: {
              aps: {
                alert: { title, body },
                sound: "default",
                badge: 1,
              },
            },
          },
        },
      }),
    }
  );

  if (resp.ok) {
    return true;
  }

  const errBody = await resp.json().catch(() => ({}));
  const errorCode = errBody?.error?.details?.[0]?.errorCode ?? "";

  // token 无效或已注销 → 返回 false，调用方应删除该 token
  if (
    resp.status === 404 ||
    errorCode === "UNREGISTERED" ||
    errorCode === "INVALID_ARGUMENT"
  ) {
    console.warn(`[FCM] Invalid token (${errorCode}), should remove`);
    return false;
  }

  console.error(`[FCM] Send failed: ${resp.status}`, errBody);
  return true; // 其他错误不删 token（可能是临时问题）
}

/**
 * 向指定用户的所有设备发送推送，并自动清理无效 token
 */
export async function sendToUser(
  supabase: SupabaseClient,
  userId: string,
  title: string,
  body: string,
  data: Record<string, string> = {}
): Promise<void> {
  // 查询用户的所有 FCM token
  const { data: tokens, error } = await supabase
    .from("user_fcm_tokens")
    .select("id, fcm_token")
    .eq("user_id", userId);

  if (error || !tokens || tokens.length === 0) {
    console.log(`[FCM] No tokens for user ${userId}`);
    return;
  }

  // 并行发送到所有设备
  const invalidTokenIds: string[] = [];
  await Promise.all(
    tokens.map(async (t: { id: string; fcm_token: string }) => {
      const ok = await sendToDevice(t.fcm_token, title, body, data);
      if (!ok) {
        invalidTokenIds.push(t.id);
      }
    })
  );

  // 删除无效 token
  if (invalidTokenIds.length > 0) {
    await supabase
      .from("user_fcm_tokens")
      .delete()
      .in("id", invalidTokenIds);
    console.log(
      `[FCM] Removed ${invalidTokenIds.length} invalid tokens for user ${userId}`
    );
  }
}
