# Supabase 后端代码模式参考

> 本文件是后端开发 Agent 的核心参考。

## 1. SQL Migration 标准模板

```sql
-- ============================================================
-- Migration: 001_create_profiles
-- 描述: 创建用户资料表，扩展 Supabase Auth
-- ============================================================

-- 枚举类型
DO $$ BEGIN
  CREATE TYPE user_status AS ENUM ('active', 'suspended', 'banned');
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;

-- 用户资料表
CREATE TABLE IF NOT EXISTS public.profiles (
  id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  username VARCHAR(30) NOT NULL UNIQUE,
  display_name VARCHAR(50),
  avatar_url TEXT,
  phone VARCHAR(20),
  status user_status NOT NULL DEFAULT 'active',
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 索引
CREATE INDEX IF NOT EXISTS idx_profiles_username ON public.profiles(username);
CREATE INDEX IF NOT EXISTS idx_profiles_status ON public.profiles(status);

-- updated_at 自动更新 trigger
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS set_updated_at ON public.profiles;
CREATE TRIGGER set_updated_at
  BEFORE UPDATE ON public.profiles
  FOR EACH ROW
  EXECUTE FUNCTION update_updated_at_column();

-- ============================================================
-- RLS 策略（先开启，默认拒绝所有，再逐条开放）
-- ============================================================
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;

-- 用户只能读取自己的 profile
CREATE POLICY "profiles_select_own"
  ON public.profiles FOR SELECT
  USING (auth.uid() = id);

-- 用户只能更新自己的 profile（不能改 status）
CREATE POLICY "profiles_update_own"
  ON public.profiles FOR UPDATE
  USING (auth.uid() = id)
  WITH CHECK (auth.uid() = id);

-- 新用户注册时允许插入（由 trigger 或 Edge Function 调用）
CREATE POLICY "profiles_insert_own"
  ON public.profiles FOR INSERT
  WITH CHECK (auth.uid() = id);

-- 注意：不设置 DELETE 策略 = 用户不能删除自己的 profile

-- ============================================================
-- 用户注册时自动创建 profile 的 trigger
-- ============================================================
CREATE OR REPLACE FUNCTION handle_new_user()
RETURNS TRIGGER AS $$
BEGIN
  INSERT INTO public.profiles (id, username)
  VALUES (
    NEW.id,
    COALESCE(NEW.raw_user_meta_data->>'username', 'user_' || substr(NEW.id::text, 1, 8))
  );
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW
  EXECUTE FUNCTION handle_new_user();
```

## 2. Edge Function 标准模板

```typescript
// functions/auth-register/index.ts
// 用户注册 Edge Function

import { serve } from "https://deno.land/std@0.177.0/http/server.ts"
import { createClient } from "https://esm.sh/@supabase/supabase-js@2"

// 统一 CORS 头
const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

// 统一响应格式
function jsonResponse(data: unknown, status = 200) {
  return new Response(
    JSON.stringify(data),
    {
      status,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    }
  )
}

function errorResponse(code: string, message: string, status = 400) {
  return jsonResponse({ success: false, error: { code, message } }, status)
}

function successResponse(data: unknown) {
  return jsonResponse({ success: true, data })
}

// 入参校验
interface RegisterInput {
  email: string
  password: string
  username: string
}

function validateInput(body: unknown): RegisterInput {
  const { email, password, username } = body as Record<string, unknown>

  if (!email || typeof email !== 'string') {
    throw { code: 'INVALID_EMAIL', message: 'Email is required' }
  }
  if (!/^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$/.test(email)) {
    throw { code: 'INVALID_EMAIL', message: 'Invalid email format' }
  }
  if (!password || typeof password !== 'string' || password.length < 8) {
    throw { code: 'WEAK_PASSWORD', message: 'Password must be at least 8 characters' }
  }
  if (!username || typeof username !== 'string' || username.length < 2 || username.length > 30) {
    throw { code: 'INVALID_USERNAME', message: 'Username must be 2-30 characters' }
  }
  if (!/^[a-zA-Z0-9_]+$/.test(username)) {
    throw { code: 'INVALID_USERNAME', message: 'Username can only contain letters, numbers, and underscores' }
  }

  return { email: email.trim().toLowerCase(), password, username: username.trim() }
}

serve(async (req) => {
  // 处理 CORS 预检
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    // 1. 解析和校验入参
    const body = await req.json()
    const input = validateInput(body)

    // 2. 初始化 Supabase Admin 客户端
    const supabaseAdmin = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '',
    )

    // 3. 检查 username 是否已存在
    const { data: existing } = await supabaseAdmin
      .from('profiles')
      .select('id')
      .eq('username', input.username)
      .single()

    if (existing) {
      return errorResponse('USERNAME_TAKEN', 'This username is already taken')
    }

    // 4. 创建用户（Supabase Auth）
    const { data: authData, error: authError } = await supabaseAdmin.auth.admin.createUser({
      email: input.email,
      password: input.password,
      user_metadata: { username: input.username },
      email_confirm: false, // 需要邮箱验证
    })

    if (authError) {
      if (authError.message.includes('already registered')) {
        return errorResponse('EMAIL_EXISTS', 'This email is already registered')
      }
      throw authError
    }

    // 5. 返回成功
    return successResponse({
      user_id: authData.user.id,
      email: authData.user.email,
      username: input.username,
    })

  } catch (error) {
    // 业务错误（有 code）
    if (error.code) {
      return errorResponse(error.code, error.message)
    }
    // 未知错误
    console.error('Unhandled error:', error)
    return errorResponse('INTERNAL_ERROR', 'An unexpected error occurred', 500)
  }
})
```

## 3. RLS 策略设计原则

```
原则1: 默认拒绝 → 开启 RLS 后不创建策略 = 所有人都不能访问
原则2: 最小权限 → 只开放必要的操作
原则3: 行级隔离 → auth.uid() = 表中的 user_id 字段
原则4: 服务端特权 → Edge Function 用 service_role_key 绕过 RLS
原则5: 公开数据 → 商家信息、Deal列表 用 SELECT FOR anon 策略
```

| 表 | SELECT | INSERT | UPDATE | DELETE |
|---|---|---|---|---|
| profiles | 自己 | 自己 (trigger) | 自己 | ❌ |
| orders | 自己 | 自己 | ❌ (Edge Function) | ❌ |
| deals | 所有人(已上架) | 商家自己 | 商家自己 | ❌ |
| reviews | 所有人 | 自己(已核销) | 自己 | ❌ |

## 4. Edge Function 目录结构

```
supabase/
├── functions/
│   ├── _shared/               # 共享工具
│   │   ├── cors.ts
│   │   ├── response.ts
│   │   └── validate.ts
│   ├── auth-register/
│   │   └── index.ts
│   ├── auth-login/
│   │   └── index.ts
│   ├── auth-reset-password/
│   │   └── index.ts
│   └── auth-verify-email/
│       └── index.ts
├── migrations/
│   ├── 001_create_profiles.sql
│   ├── 002_create_deals.sql
│   └── ...
└── seed.sql
```
