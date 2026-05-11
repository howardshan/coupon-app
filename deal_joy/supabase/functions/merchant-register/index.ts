// ============================================================
// Crunchy Plum — merchant-register Edge Function
// 接受商家注册信息，插入 merchants + merchant_documents 表
// 写入逻辑与 admin-merchant-onboard 共用 _shared/merchant_application_submit.ts
// ============================================================

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import {
  submitMerchantApplication,
  validateMerchantRegisterRequest,
  type MerchantRegisterRequestBody,
} from "../_shared/merchant_application_submit.ts";

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response(null, {
      status: 204,
      headers: {
        "Access-Control-Allow-Origin": "*",
        "Access-Control-Allow-Methods": "POST, OPTIONS",
        "Access-Control-Allow-Headers": "Authorization, Content-Type",
      },
    });
  }

  if (req.method !== "POST") {
    return jsonResponse({ error: "Method not allowed" }, 405);
  }

  const authHeader = req.headers.get("Authorization");
  if (!authHeader) {
    return jsonResponse({ error: "Missing authorization header" }, 401);
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
  const supabaseAnonKey = Deno.env.get("SUPABASE_ANON_KEY")!;
  const supabase = createClient(supabaseUrl, supabaseAnonKey, {
    global: { headers: { Authorization: authHeader } },
  });

  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
  const adminSupabase = createClient(supabaseUrl, serviceRoleKey);

  const { data: { user }, error: authError } = await supabase.auth.getUser();
  if (authError || !user) {
    return jsonResponse({ error: "Invalid or expired token" }, 401);
  }

  let body: MerchantRegisterRequestBody;
  try {
    body = await req.json();
  } catch {
    return jsonResponse({ error: "Invalid JSON body" }, 400);
  }

  const validationError = validateMerchantRegisterRequest(body);
  if (validationError) {
    return jsonResponse({ error: validationError }, 400);
  }

  const result = await submitMerchantApplication(adminSupabase, {
    ownerUserId: user.id,
    ownerAuthEmail: user.email,
    body,
    activity: {
      actorType: "merchant_owner",
      actorUserId: user.id,
      detail: null,
    },
  });

  if (!("merchant_id" in result)) {
    return jsonResponse({ error: result.error }, result.status);
  }

  return jsonResponse(
    {
      merchant_id: result.merchant_id,
      status: result.status,
      message: result.message,
      registration_type: result.registration_type,
      brand_id: result.brand_id,
    },
    200,
  );
});

function jsonResponse(data: unknown, status: number): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: {
      "Content-Type": "application/json",
      "Access-Control-Allow-Origin": "*",
    },
  });
}
