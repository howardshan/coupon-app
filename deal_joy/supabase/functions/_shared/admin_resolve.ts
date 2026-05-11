// 从请求中解析平台管理员（admin / super_admin），与 platform-after-sales 行为对齐。

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

export type PlatformAdminContext = {
  userId: string;
  role: string;
};

export class AdminResolveError extends Error {
  constructor(
    message: string,
    public readonly status: number,
  ) {
    super(message);
    this.name = "AdminResolveError";
  }
}

/**
 * 使用调用方 Bearer JWT 校验用户，并用 service role 读取 users.role。
 */
export async function resolvePlatformAdmin(
  req: Request,
  opts: { supabaseUrl: string; anonKey: string; serviceKey: string },
): Promise<PlatformAdminContext> {
  const headerToken = (req.headers.get("Authorization") ?? "")
    .replace(/^[Bb]earer\s+/i, "")
    .trim();
  if (!headerToken) {
    throw new AdminResolveError("Missing authorization", 401);
  }

  const anonClient = createClient(opts.supabaseUrl, opts.anonKey, {
    global: { headers: { Authorization: `Bearer ${headerToken}` } },
    auth: { persistSession: false },
  });

  const { data, error } = await anonClient.auth.getUser();
  if (error || !data?.user) {
    throw new AdminResolveError("Invalid or expired token", 401);
  }

  const serviceClient = createClient(opts.supabaseUrl, opts.serviceKey, {
    auth: { persistSession: false },
  });

  const { data: profile } = await serviceClient
    .from("users")
    .select("role")
    .eq("id", data.user.id)
    .maybeSingle();

  if (!profile || !["admin", "super_admin"].includes(profile.role ?? "")) {
    throw new AdminResolveError("Admin access required", 403);
  }

  return { userId: data.user.id, role: profile.role ?? "" };
}
