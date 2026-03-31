// =============================================================
// Edge Function: parse-recommendation-config
// Admin 用自然语言描述算法，Claude 解析成权重配置
// 路由：
//   POST /parse-recommendation-config — 解析自然语言算法描述
//     body: { action: 'parse', description }
//     返回: { configId, config, preview }
//
//   POST /parse-recommendation-config — 激活配置
//     body: { action: 'activate', configId }
//     返回: { success }
//
//   POST /parse-recommendation-config — 获取配置历史
//     body: { action: 'list' }
//     返回: { configs }
//
//   POST /parse-recommendation-config — 回滚到某个配置
//     body: { action: 'restore', configId }
//     返回: { success }
// 认证：Bearer JWT（仅 admin）
// =============================================================

import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

function jsonResponse(data: unknown, status = 200): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });
}

function errorResponse(message: string, status = 400): Response {
  return jsonResponse({ error: message }, status);
}

const PARSE_SYSTEM_PROMPT = `You are an algorithm configuration assistant for Crunchy Plum, a local deals platform in Dallas.

Your job is to translate natural language algorithm descriptions into a JSON weight configuration.

Weight fields and their meaning:
- w_relevance (0~1):  How much user preference history matters
- w_distance (0~1):   How much geographic proximity matters
- w_popularity (0~1): How much trending/popular deals are boosted
- w_quality (0~1):    How much ratings and reviews matter
- w_freshness (0~1):  How much newly listed deals are boosted
- w_time_slot (0~1):  How much meal-time relevance matters
- sponsor_boost:      Score added to sponsored merchants (keep >= 50)
- diversity_penalty:  Penalty for same merchant appearing too much (keep negative)
- max_same_merchant:  Max times same merchant appears in top 20

Rules:
1. All weights (w_*) must sum to exactly 1.0
2. sponsor_boost must be between 50 and 200
3. diversity_penalty must be between -0.5 and -0.1
4. Respond ONLY with valid JSON, no explanation

Example output:
{
  "weights": {
    "w_relevance": 0.30,
    "w_distance": 0.20,
    "w_popularity": 0.20,
    "w_quality": 0.15,
    "w_freshness": 0.10,
    "w_time_slot": 0.05
  },
  "sponsor_boost": 100.0,
  "diversity_penalty": -0.30,
  "max_same_merchant": 2,
  "cache_ttl_minutes": 15,
  "version": "auto-generated",
  "description": "[admin's original description]"
}`;

// 生成权重预览文本
function generatePreviewText(config: Record<string, unknown>): string {
  const weights = config.weights as Record<string, number>;
  const lines: string[] = [];

  const labels: Record<string, string> = {
    w_relevance: 'Relevance (User Preferences)',
    w_distance: 'Distance (Proximity)',
    w_popularity: 'Popularity (Trending)',
    w_quality: 'Quality (Ratings)',
    w_freshness: 'Freshness (New Deals)',
    w_time_slot: 'Time Slot (Meal Time)',
  };

  for (const [key, label] of Object.entries(labels)) {
    const value = weights[key] ?? 0;
    const bar = '\u2588'.repeat(Math.round(value * 20)) + '\u2591'.repeat(20 - Math.round(value * 20));
    lines.push(`${label.padEnd(30)} ${bar} ${value.toFixed(2)}`);
  }

  lines.push('');
  lines.push(`Sponsor Boost: ${config.sponsor_boost}`);
  lines.push(`Diversity Penalty: ${config.diversity_penalty}`);
  lines.push(`Max Same Merchant: ${config.max_same_merchant}`);

  return lines.join('\n');
}

serve(async (req: Request) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  try {
    const supabaseUrl = Deno.env.get('SUPABASE_URL')!;
    const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
    const supabase = createClient(supabaseUrl, serviceRoleKey);

    // 验证 admin 身份
    const authHeader = req.headers.get('Authorization') ?? '';
    const token = authHeader.replace('Bearer ', '');
    const userClient = createClient(supabaseUrl, Deno.env.get('SUPABASE_ANON_KEY')!, {
      global: { headers: { Authorization: `Bearer ${token}` } },
    });
    const { data: { user } } = await userClient.auth.getUser();

    if (!user) {
      return errorResponse('Unauthorized', 401);
    }

    // 检查 admin 角色
    const { data: userData } = await supabase
      .from('users')
      .select('role')
      .eq('id', user.id)
      .single();

    if (userData?.role !== 'admin') {
      return errorResponse('Only admin can manage recommendation config', 403);
    }

    const body = await req.json();
    const action = body.action as string;

    // --- 解析自然语言描述 ---
    if (action === 'parse') {
      const description = body.description as string;
      if (!description) {
        return errorResponse('description is required');
      }

      const anthropicApiKey = Deno.env.get('ANTHROPIC_API_KEY');
      if (!anthropicApiKey) {
        return errorResponse('ANTHROPIC_API_KEY not configured', 500);
      }

      // 调用 Claude API
      const claudeResponse = await fetch('https://api.anthropic.com/v1/messages', {
        method: 'POST',
        headers: {
          'x-api-key': anthropicApiKey,
          'anthropic-version': '2023-06-01',
          'content-type': 'application/json',
        },
        body: JSON.stringify({
          model: 'claude-sonnet-4-20250514',
          max_tokens: 500,
          system: PARSE_SYSTEM_PROMPT,
          messages: [{ role: 'user', content: description }],
        }),
      });

      if (!claudeResponse.ok) {
        const errText = await claudeResponse.text();
        return errorResponse(`Claude API error: ${errText}`, 500);
      }

      const claudeData = await claudeResponse.json();
      const rawJson = claudeData.content?.[0]?.text?.trim() ?? '';

      // 解析 JSON
      let config: Record<string, unknown>;
      try {
        config = JSON.parse(rawJson);
      } catch {
        return errorResponse(`Failed to parse Claude response as JSON: ${rawJson}`, 500);
      }

      // 验证并归一化权重
      const weights = config.weights as Record<string, number>;
      if (weights) {
        const sum = Object.values(weights).reduce((a: number, b: number) => a + b, 0);
        if (Math.abs(sum - 1.0) > 0.01) {
          Object.keys(weights).forEach(k => {
            weights[k] = weights[k] / sum;
          });
        }
      }

      // 写入数据库（pending 状态）
      const version = `admin-${Date.now()}`;
      config.version = version;
      config.description = description;

      const { data: inserted, error: insertError } = await supabase
        .from('recommendation_config')
        .insert({
          version,
          weights: config,
          description,
          is_active: false,
          created_by: user.id,
        })
        .select()
        .single();

      if (insertError) throw insertError;

      return jsonResponse({
        configId: inserted.id,
        config,
        preview: generatePreviewText(config),
      });
    }

    // --- 激活配置 ---
    if (action === 'activate') {
      const configId = body.configId as string;
      if (!configId) return errorResponse('configId is required');

      // 先把旧的设为 inactive
      await supabase
        .from('recommendation_config')
        .update({ is_active: false })
        .eq('is_active', true);

      // 激活新的
      const { error } = await supabase
        .from('recommendation_config')
        .update({ is_active: true, activated_at: new Date().toISOString() })
        .eq('id', configId);

      if (error) throw error;

      return jsonResponse({ success: true, message: 'Config activated' });
    }

    // --- 获取配置历史 ---
    if (action === 'list') {
      const { data: configs, error } = await supabase
        .from('recommendation_config')
        .select('*')
        .order('created_at', { ascending: false })
        .limit(20);

      if (error) throw error;

      return jsonResponse({ configs });
    }

    // --- 回滚到某个配置 ---
    if (action === 'restore') {
      const configId = body.configId as string;
      if (!configId) return errorResponse('configId is required');

      // 读取要恢复的配置
      const { data: oldConfig } = await supabase
        .from('recommendation_config')
        .select('weights, description')
        .eq('id', configId)
        .single();

      if (!oldConfig) return errorResponse('Config not found', 404);

      // 创建一条新记录（复制旧配置）
      const version = `restore-${Date.now()}`;
      const { data: newConfig, error: insertErr } = await supabase
        .from('recommendation_config')
        .insert({
          version,
          weights: oldConfig.weights,
          description: `Restored from: ${oldConfig.description}`,
          is_active: false,
          created_by: user.id,
        })
        .select()
        .single();

      if (insertErr) throw insertErr;

      return jsonResponse({
        configId: newConfig.id,
        config: oldConfig.weights,
        preview: generatePreviewText(oldConfig.weights as Record<string, unknown>),
        message: 'Config restored (not yet activated)',
      });
    }

    return errorResponse(`Unknown action: ${action}`);
  } catch (error) {
    console.error('parse-recommendation-config error:', error);
    return errorResponse((error as Error).message, 500);
  }
});
