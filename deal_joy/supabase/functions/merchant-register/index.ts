// ============================================================
// DealJoy — merchant-register Edge Function
// 接受商家注册信息，插入 merchants + merchant_documents 表
// 返回 merchant_id 和 pending 状态
// ============================================================

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

// 请求体结构
interface RegisterRequest {
  company_name: string;
  contact_name: string;
  contact_email: string;
  phone: string;
  category: string;
  ein: string;
  address: string;
  // 注册类型: single（独立门店）/ multiple（连锁品牌）
  registration_type?: 'single' | 'multiple';
  // 连锁注册时的品牌信息
  brand_name?: string;
  brand_logo_url?: string;
  brand_description?: string;
  // 已上传到 Storage 的文件 URL 列表
  documents: Array<{
    document_type: string;
    file_url: string;
    file_name?: string;
    file_size?: number;
    mime_type?: string;
  }>;
}

// 响应体结构
interface RegisterResponse {
  merchant_id: string;
  status: "pending";
  message: string;
  registration_type?: string;
  brand_id?: string;
}

Deno.serve(async (req: Request) => {
  // 处理 CORS preflight
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

  // 只接受 POST 请求
  if (req.method !== "POST") {
    return jsonResponse({ error: "Method not allowed" }, 405);
  }

  // 获取 Authorization header（JWT token）
  const authHeader = req.headers.get("Authorization");
  if (!authHeader) {
    return jsonResponse({ error: "Missing authorization header" }, 401);
  }

  // 初始化 Supabase 客户端（使用调用方的 JWT token，保证 RLS 生效）
  const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
  const supabaseAnonKey = Deno.env.get("SUPABASE_ANON_KEY")!;
  const supabase = createClient(supabaseUrl, supabaseAnonKey, {
    global: { headers: { Authorization: authHeader } },
  });

  // 使用 Service Role 客户端（用于绕过 RLS 做系统操作）
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
  const adminSupabase = createClient(supabaseUrl, serviceRoleKey);

  // 验证当前用户 JWT
  const { data: { user }, error: authError } = await supabase.auth.getUser();
  if (authError || !user) {
    return jsonResponse({ error: "Invalid or expired token" }, 401);
  }

  // 解析请求体
  let body: RegisterRequest;
  try {
    body = await req.json();
  } catch {
    return jsonResponse({ error: "Invalid JSON body" }, 400);
  }

  // 基础参数校验
  const validationError = validateRequest(body);
  if (validationError) {
    return jsonResponse({ error: validationError }, 400);
  }

  // 检查该用户是否已有 merchant 记录（避免重复注册）
  const { data: existingMerchant } = await adminSupabase
    .from("merchants")
    .select("id, status")
    .eq("user_id", user.id)
    .maybeSingle();

  let merchantId: string;

  if (existingMerchant) {
    // 已存在（重新提交场景）：更新 merchants 记录
    const { error: updateError } = await adminSupabase
      .from("merchants")
      .update({
        company_name: body.company_name,
        name: body.company_name,           // 同步更新展示名
        contact_name: body.contact_name,
        contact_email: body.contact_email,
        phone: body.phone,
        category: body.category,
        ein: body.ein,
        address: body.address,
        status: "pending",                 // 重新提交后回到 pending
        rejection_reason: null,            // 清空拒绝原因
        submitted_at: new Date().toISOString(),
        updated_at: new Date().toISOString(),
      })
      .eq("id", existingMerchant.id);

    if (updateError) {
      console.error("[merchant-register] update merchant error:", updateError);
      return jsonResponse({ error: "Failed to update merchant record" }, 500);
    }

    merchantId = existingMerchant.id;

    // 删除旧证件记录（重新上传覆盖）
    await adminSupabase
      .from("merchant_documents")
      .delete()
      .eq("merchant_id", merchantId);
  } else {
    // 新商家：先查 users 表确认用户存在
    const { data: userProfile } = await adminSupabase
      .from("users")
      .select("id")
      .eq("id", user.id)
      .maybeSingle();

    if (!userProfile) {
      // users 表由 trigger 自动创建，如果不存在则手动插入
      await adminSupabase.from("users").insert({
        id: user.id,
        email: user.email!,
        full_name: body.contact_name,
        role: "merchant",
      });
    } else {
      // 更新 role 为 merchant
      await adminSupabase
        .from("users")
        .update({ role: "merchant" })
        .eq("id", user.id);
    }

    // 插入新的 merchants 记录
    const { data: newMerchant, error: insertError } = await adminSupabase
      .from("merchants")
      .insert({
        user_id: user.id,
        company_name: body.company_name,
        name: body.company_name,
        contact_name: body.contact_name,
        contact_email: body.contact_email,
        phone: body.phone,
        category: body.category,
        ein: body.ein,
        address: body.address,
        status: "pending",
        submitted_at: new Date().toISOString(),
      })
      .select("id")
      .single();

    if (insertError || !newMerchant) {
      console.error("[merchant-register] insert merchant error:", insertError);
      return jsonResponse({ error: "Failed to create merchant record" }, 500);
    }

    merchantId = newMerchant.id;
  }

  // 连锁注册：创建品牌并关联门店
  const registrationType = body.registration_type ?? 'single';
  if (registrationType === 'multiple' && !existingMerchant) {
    const brandName = body.brand_name?.trim() || body.company_name;

    // 创建品牌（brands 表无 owner_user_id 列，通过 brand_admins 关联 owner）
    const { data: newBrand, error: brandError } = await adminSupabase
      .from('brands')
      .insert({
        name: brandName,
        logo_url: body.brand_logo_url ?? null,
        description: body.brand_description ?? null,
      })
      .select('id')
      .single();

    if (brandError || !newBrand) {
      console.error('[merchant-register] create brand error:', brandError);
      // 品牌创建失败不阻断注册，但记录错误
    } else {
      // 关联门店到品牌
      await adminSupabase
        .from('merchants')
        .update({ brand_id: newBrand.id })
        .eq('id', merchantId);

      // 创建品牌管理员记录（owner）
      await adminSupabase
        .from('brand_admins')
        .insert({
          brand_id: newBrand.id,
          user_id: user.id,
          role: 'owner',
        });
    }
  }

  // 批量插入 merchant_documents 记录
  if (body.documents && body.documents.length > 0) {
    const docRows = body.documents.map((doc) => ({
      merchant_id: merchantId,
      document_type: doc.document_type,
      file_url: doc.file_url,
      file_name: doc.file_name ?? null,
      file_size: doc.file_size ?? null,
      mime_type: doc.mime_type ?? null,
    }));

    const { error: docsError } = await adminSupabase
      .from("merchant_documents")
      .insert(docRows);

    if (docsError) {
      console.error("[merchant-register] insert documents error:", docsError);
      // 文件记录插入失败时回滚 merchant（删除刚创建的记录）
      if (!existingMerchant) {
        await adminSupabase.from("merchants").delete().eq("id", merchantId);
      }
      return jsonResponse({ error: "Failed to save document records" }, 500);
    }
  }

  // 查询是否关联了品牌
  let brandId: string | undefined;
  if (registrationType === 'multiple') {
    const { data: merchantData } = await adminSupabase
      .from('merchants')
      .select('brand_id')
      .eq('id', merchantId)
      .single();
    brandId = merchantData?.brand_id ?? undefined;
  }

  // 成功返回
  const response: RegisterResponse = {
    merchant_id: merchantId,
    status: "pending",
    message:
      "Application submitted successfully. Review takes 24-48 hours.",
    registration_type: registrationType,
    brand_id: brandId,
  };

  return jsonResponse(response, 200);
});

// ----------------------------------------------------------
// 辅助函数：校验请求参数
// ----------------------------------------------------------
function validateRequest(body: RegisterRequest): string | null {
  if (!body.company_name?.trim()) return "Company name is required";
  if (!body.contact_name?.trim()) return "Contact name is required";
  if (!body.contact_email?.trim()) return "Contact email is required";
  if (!body.phone?.trim()) return "Phone number is required";
  if (!body.category?.trim()) return "Business category is required";
  if (!body.ein?.trim()) return "EIN/Tax ID is required";

  // EIN 格式校验: XX-XXXXXXX
  const einPattern = /^\d{2}-\d{7}$/;
  if (!einPattern.test(body.ein.trim())) {
    return "EIN/Tax ID must be in format XX-XXXXXXX";
  }

  if (!body.address?.trim()) return "Store address is required";

  // 合法的类别列表
  const validCategories = [
    "Restaurant",
    "SpaAndMassage",
    "HairAndBeauty",
    "Fitness",
    "FunAndGames",
    "NailAndLash",
    "Wellness",
    "Other",
  ];
  if (!validCategories.includes(body.category)) {
    return `Invalid category. Must be one of: ${validCategories.join(", ")}`;
  }

  return null;
}

// ----------------------------------------------------------
// 辅助函数：构建 JSON 响应
// ----------------------------------------------------------
function jsonResponse(data: unknown, status: number): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: {
      "Content-Type": "application/json",
      "Access-Control-Allow-Origin": "*",
    },
  });
}
