// =============================================================
// DealJoy 共享鉴权模块
// 所有 merchant-* Edge Function 统一使用此模块进行角色/权限判定
// =============================================================

import { SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2";

// 角色类型
export type UserRole =
  | "brand_owner"
  | "brand_admin"
  | "store_owner"
  | "regional_manager"
  | "manager"
  | "finance"
  | "cashier"
  | "service"
  | "trainee";

// 权限类型
export type Permission =
  | "scan"
  | "orders"
  | "orders_detail"
  | "reviews"
  | "deals"
  | "store"
  | "finance"
  | "staff"
  | "influencer"
  | "marketing"
  | "analytics"
  | "settings"
  | "brand";

// 鉴权结果
export interface AuthResult {
  userId: string;
  merchantId: string; // 当前操作的门店 ID
  merchantIds: string[]; // 该用户可管理的所有门店 ID
  role: UserRole;
  brandId: string | null;
  isBrandAdmin: boolean;
  permissions: Permission[];
}

// 角色 → 权限映射
const ROLE_PERMISSIONS: Record<UserRole, Permission[]> = {
  brand_owner: [
    "scan",
    "orders",
    "orders_detail",
    "reviews",
    "deals",
    "store",
    "finance",
    "staff",
    "influencer",
    "marketing",
    "analytics",
    "settings",
    "brand",
  ],
  brand_admin: [
    "scan",
    "orders",
    "orders_detail",
    "reviews",
    "deals",
    "store",
    "finance",
    "staff",
    "influencer",
    "marketing",
    "analytics",
    "settings",
    "brand",
  ],
  store_owner: [
    "scan",
    "orders",
    "orders_detail",
    "reviews",
    "deals",
    "store",
    "finance",
    "staff",
    "influencer",
    "marketing",
    "analytics",
    "settings",
  ],
  // V2.3 区域经理：管理多店，含品牌权限但不含 settings
  regional_manager: [
    "scan",
    "orders",
    "orders_detail",
    "reviews",
    "deals",
    "store",
    "finance",
    "staff",
    "influencer",
    "marketing",
    "analytics",
    "brand",
  ],
  manager: [
    "scan",
    "orders",
    "orders_detail",
    "reviews",
    "deals",
    "store",
    "finance",
    "staff",
    "influencer",
    "marketing",
    "analytics",
  ],
  // V2.3 财务角色：只看财务 + 订单相关
  finance: ["orders", "orders_detail", "finance", "analytics"],
  service: ["scan", "orders", "orders_detail", "reviews"],
  cashier: ["scan", "orders"],
  // V2.3 实习生：只读扫码（不能核销，只能查看）
  trainee: ["scan"],
};

/**
 * 解析当前请求的用户角色和权限
 *
 * 判定优先级：
 * 1. 品牌管理员 (brand_admins 表)
 * 2. 门店 owner (merchants.user_id)
 * 3. 门店员工 (merchant_staff 表)
 *
 * 品牌管理员和门店 owner 可通过 X-Merchant-Id header 指定操作的门店。
 * 员工只能操作自己所属的门店。
 */
export async function resolveAuth(
  supabase: SupabaseClient,
  userId: string,
  headers: Headers
): Promise<AuthResult> {
  // 1. 检查是否品牌管理员
  const { data: brandAdmin } = await supabase
    .from("brand_admins")
    .select("brand_id, role")
    .eq("user_id", userId)
    .maybeSingle();

  // 2. 检查是否门店 owner
  const { data: ownedStores } = await supabase
    .from("merchants")
    .select("id, brand_id")
    .eq("user_id", userId);

  // 3. 检查是否门店员工
  const { data: staffRecords } = await supabase
    .from("merchant_staff")
    .select("merchant_id, role")
    .eq("user_id", userId)
    .eq("is_active", true);

  // 收集所有可访问的 merchantIds
  const allMerchantIds = new Set<string>();

  // 品牌管理员：获取品牌下所有门店
  let brandId: string | null = null;
  let isBrandAdmin = false;
  let role: UserRole = "cashier"; // 默认最低权限

  if (brandAdmin) {
    brandId = brandAdmin.brand_id;
    isBrandAdmin = true;
    role =
      brandAdmin.role === "owner" ? "brand_owner" : "brand_admin";

    const { data: brandStores } = await supabase
      .from("merchants")
      .select("id")
      .eq("brand_id", brandId);

    (brandStores ?? []).forEach((s: { id: string }) =>
      allMerchantIds.add(s.id)
    );
  }

  // 门店 owner
  if (ownedStores && ownedStores.length > 0) {
    ownedStores.forEach((s: { id: string; brand_id: string | null }) => {
      allMerchantIds.add(s.id);
      if (s.brand_id && !brandId) {
        brandId = s.brand_id;
      }
    });
    // 如果不是品牌管理员，角色设为 store_owner
    if (!isBrandAdmin) {
      role = "store_owner";
    }
  }

  // 门店员工
  if (staffRecords && staffRecords.length > 0) {
    staffRecords.forEach(
      (s: { merchant_id: string; role: string }) => {
        allMerchantIds.add(s.merchant_id);
      }
    );
    // 如果既不是品牌管理员也不是 owner，用员工角色
    if (!isBrandAdmin && (!ownedStores || ownedStores.length === 0)) {
      // 取最高权限的员工角色
      const staffRolePriority: Record<string, number> = {
        regional_manager: 5,
        manager: 4,
        finance: 3,
        service: 2,
        cashier: 1,
        trainee: 0,
      };
      let highestPriority = 0;
      for (const sr of staffRecords) {
        const p = staffRolePriority[sr.role] ?? 0;
        if (p > highestPriority) {
          highestPriority = p;
          role = sr.role as UserRole;
        }
      }
    }
  }

  const merchantIds = Array.from(allMerchantIds);

  if (merchantIds.length === 0) {
    throw new Error("No merchant found for this user");
  }

  // 4. 确定当前操作的 merchantId
  const headerMerchantId = headers.get("X-Merchant-Id");
  let merchantId: string;

  if (headerMerchantId) {
    // 安全校验：确认该门店在用户可访问范围内
    if (!merchantIds.includes(headerMerchantId)) {
      throw new Error("Unauthorized: you cannot access this merchant");
    }
    // 品牌管理员额外校验：确认门店属于该品牌
    if (isBrandAdmin && brandId) {
      const { data: targetMerchant } = await supabase
        .from("merchants")
        .select("brand_id")
        .eq("id", headerMerchantId)
        .single();
      if (targetMerchant && targetMerchant.brand_id !== brandId) {
        throw new Error("Unauthorized: merchant not in your brand");
      }
    }
    merchantId = headerMerchantId;
  } else {
    // 默认使用第一个可访问的门店
    merchantId = merchantIds[0];
  }

  // 5. 生成权限列表
  const permissions = ROLE_PERMISSIONS[role] ?? [];

  return {
    userId,
    merchantId,
    merchantIds,
    role,
    brandId,
    isBrandAdmin,
    permissions,
  };
}

/**
 * 权限检查 — 如果没有指定权限则抛出异常
 */
export function requirePermission(
  auth: AuthResult,
  permission: Permission
): void {
  if (!auth.permissions.includes(permission)) {
    throw new Error(
      `Forbidden: ${auth.role} does not have '${permission}' permission`
    );
  }
}

/**
 * 检查用户是否有指定权限（不抛异常，返回 boolean）
 */
export function hasPermission(
  auth: AuthResult,
  permission: Permission
): boolean {
  return auth.permissions.includes(permission);
}
