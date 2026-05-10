// docusign-webhook
// 接收 DocuSign Connect 的回调通知，更新 merchant_contracts 合同状态
// 当商家签署完成时，同时拉取 tab 值（Business/DBA Name）并写入 DB
//
// 在 DocuSign 开发者控制台 → Settings → Connect 中配置：
//   URL: https://kqyolvmgrdekybjrwizx.supabase.co/functions/v1/docusign-webhook
//   Events: envelope-completed, envelope-voided, envelope-declined
//   Format: JSON

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { createSign } from "node:crypto";

const supabase = createClient(
  Deno.env.get("SUPABASE_URL") ?? "",
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
);

// DocuSign 状态 → 本地 merchant_contracts.status 映射
const DS_STATUS_MAP: Record<string, string> = {
  completed: "signed", // 所有签名者完成
  voided: "voided", // 信封被作废
  declined: "voided", // 签名者拒绝签署
};

// ── DocuSign JWT 认证（与 send-merchant-contract 相同逻辑）───────────────

function base64UrlEncode(str: string): string {
  const b64 = btoa(unescape(encodeURIComponent(str)));
  return b64.replace(/\+/g, "-").replace(/\//g, "_").replace(/=/g, "");
}

function b64ToB64Url(b64: string): string {
  return b64.replace(/\+/g, "-").replace(/\//g, "_").replace(/=/g, "");
}

async function getDocuSignAccessToken(): Promise<string> {
  const integrationKey = Deno.env.get("DOCUSIGN_INTEGRATION_KEY") ?? "";
  const userId = Deno.env.get("DOCUSIGN_USER_ID") ?? "";
  // DOCUSIGN_RSA_PRIVATE_KEY_B64 存储 base64 编码的 PEM
  const privateKeyRaw = Deno.env.get("DOCUSIGN_RSA_PRIVATE_KEY_B64") ?? "";
  const privateKey = privateKeyRaw.startsWith("-----")
    ? privateKeyRaw
    : new TextDecoder().decode(
        Uint8Array.from(atob(privateKeyRaw), (c) => c.charCodeAt(0)),
      );
  const baseUrl = Deno.env.get("DOCUSIGN_AUTH_BASE_URL") ??
    "https://account-d.docusign.com";

  const now = Math.floor(Date.now() / 1000);
  const header = { alg: "RS256", typ: "JWT" };
  const payload = {
    iss: integrationKey,
    sub: userId,
    aud: baseUrl.replace("https://", ""),
    iat: now,
    exp: now + 3600,
    scope: "signature impersonation",
  };

  const headerB64 = base64UrlEncode(JSON.stringify(header));
  const payloadB64 = base64UrlEncode(JSON.stringify(payload));
  const signingInput = `${headerB64}.${payloadB64}`;

  const sign = createSign("RSA-SHA256");
  sign.update(signingInput);
  const signature = sign.sign(privateKey, "base64");
  const sigB64Url = b64ToB64Url(signature);

  const jwt = `${signingInput}.${sigB64Url}`;

  const tokenResp = await fetch(`${baseUrl}/oauth/token`, {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion: jwt,
    }),
  });

  if (!tokenResp.ok) {
    throw new Error(`DocuSign JWT auth failed: ${await tokenResp.text()}`);
  }
  return (await tokenResp.json()).access_token as string;
}

// ── 获取签署后的 tab 值（Business Name）──────────────────────────────────
// 调用 DocuSign API 获取信封的 recipient tabs 表单数据

async function fetchBusinessNameFromEnvelope(
  envelopeId: string,
): Promise<string | null> {
  try {
    const accessToken = await getDocuSignAccessToken();
    const accountId = Deno.env.get("DOCUSIGN_ACCOUNT_ID") ?? "";
    const dsBaseUrl = Deno.env.get("DOCUSIGN_BASE_URL") ??
      "https://demo.docusign.net";

    // 先获取 recipients 列表
    const recipientsResp = await fetch(
      `${dsBaseUrl}/restapi/v2.1/accounts/${accountId}/envelopes/${envelopeId}/recipients`,
      { headers: { Authorization: `Bearer ${accessToken}` } },
    );

    if (!recipientsResp.ok) return null;
    const recipientsData = await recipientsResp.json();
    const signers = recipientsData.signers ?? [];
    if (signers.length === 0) return null;

    const recipientId = signers[0].recipientId;

    // 获取该签名者的 tabs
    const tabsResp = await fetch(
      `${dsBaseUrl}/restapi/v2.1/accounts/${accountId}/envelopes/${envelopeId}/recipients/${recipientId}/tabs`,
      { headers: { Authorization: `Bearer ${accessToken}` } },
    );

    if (!tabsResp.ok) return null;
    const tabsData = await tabsResp.json();

    // 找到 tabLabel === "BusinessName" 的文字 tab
    const textTabs: Array<{ tabLabel: string; value: string }> =
      tabsData.textTabs ?? [];
    const businessNameTab = textTabs.find((t) => t.tabLabel === "BusinessName");
    return businessNameTab?.value?.trim() || null;
  } catch (e) {
    console.error("[docusign-webhook] fetchBusinessName error:", e);
    return null;
  }
}

// ── 主 Handler ──────────────────────────────────────────────────────────────

Deno.serve(async (req) => {
  // DocuSign Connect 发送 POST 请求
  if (req.method !== "POST") {
    return new Response("Method not allowed", { status: 405 });
  }

  try {
    const payload = await req.json();
    console.log("[docusign-webhook] Received event:", payload.event);

    // DocuSign Connect JSON 格式：{ event, data: { envelopeId, envelopeSummary: { status } } }
    const event: string = payload.event ?? "";
    const envelopeId: string = payload.data?.envelopeId ?? "";
    const envelopeStatus: string =
      payload.data?.envelopeSummary?.status ?? "";

    if (!envelopeId) {
      console.warn("[docusign-webhook] No envelopeId in payload");
      return new Response("ok", { status: 200 });
    }

    // 将 DocuSign 状态映射到本地状态
    const localStatus = DS_STATUS_MAP[envelopeStatus];
    if (!localStatus) {
      // 不关心的状态（如 sent, delivered 等），直接返回 200 给 DocuSign
      console.log(
        `[docusign-webhook] Ignoring status '${envelopeStatus}' for envelope ${envelopeId}`,
      );
      return new Response("ok", { status: 200 });
    }

    // 按 envelope ID 查找对应合同
    const { data: contract, error: findErr } = await supabase
      .from("merchant_contracts")
      .select("id, status, business_name")
      .eq("docusign_envelope_id", envelopeId)
      .maybeSingle();

    if (findErr || !contract) {
      console.warn(
        `[docusign-webhook] Contract not found for envelope ${envelopeId}`,
      );
      return new Response("ok", { status: 200 });
    }

    // 构造更新 payload
    const updatePayload: Record<string, unknown> = {
      status: localStatus,
    };

    // 签署完成时：获取商家填写的 Business Name
    if (localStatus === "signed" && !contract.business_name) {
      const businessName = await fetchBusinessNameFromEnvelope(envelopeId);
      if (businessName) {
        updatePayload.business_name = businessName;
        console.log(
          `[docusign-webhook] Business name: ${businessName}`,
        );
      }
    }

    const { error: updateErr } = await supabase
      .from("merchant_contracts")
      .update(updatePayload)
      .eq("id", contract.id);

    if (updateErr) {
      console.error("[docusign-webhook] DB update error:", updateErr);
      // 返回 500 让 DocuSign 重试
      return new Response("DB update failed", { status: 500 });
    }

    console.log(
      `[docusign-webhook] Contract ${contract.id} updated to status '${localStatus}'`,
    );

    // 必须返回 200，否则 DocuSign 会重试
    return new Response("ok", { status: 200 });
  } catch (e) {
    console.error("[docusign-webhook] Unexpected error:", e);
    return new Response("Internal server error", { status: 500 });
  }
});
