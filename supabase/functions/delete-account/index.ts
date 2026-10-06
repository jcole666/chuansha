// Supabase Edge Function: delete-account
//
// 用途：注销账号。删除 auth.users 里的用户记录需要 service_role 权限，
//       纯前端做不到，所以放在这里。
//
// 部署方式（在项目根目录执行）：
//   supabase functions deploy delete-account
//
// 需要环境变量（Supabase 会自动注入前两个，SERVICE_ROLE 需手动设置）：
//   SUPABASE_URL
//   SUPABASE_ANON_KEY
//   SUPABASE_SERVICE_ROLE_KEY
//
//   supabase secrets set SUPABASE_SERVICE_ROLE_KEY=你的service_role_key
//
// 客户端调用（见 lib/services/account_service.dart）：
//   await client.functions.invoke('delete-account');
// 请求头会自动带上当前用户的 Authorization，函数据此确认"你是谁"。

import { createClient } from "jsr:@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) {
      return json({ error: "缺少认证信息" }, 401);
    }

    const supabaseUrl = Deno.env.get("SUPABASE_URL");
    const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
    const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");

    if (!supabaseUrl || !anonKey || !serviceRoleKey) {
      return json({ error: "函数未正确配置环境变量" }, 500);
    }

    // 用调用者的 token 确认身份 —— 只能删自己，不能删别人
    const asUser = createClient(supabaseUrl, anonKey, {
      global: { headers: { Authorization: authHeader } },
    });

    const {
      data: { user },
      error: userError,
    } = await asUser.auth.getUser();

    if (userError || !user) {
      return json({ error: "身份校验失败" }, 401);
    }

    // 用 service_role 删除账号；表数据靠外键 ON DELETE CASCADE 级联清理。
    // 若你的表没有配级联，客户端会先自行删除业务数据（见 account_service.dart）。
    const admin = createClient(supabaseUrl, serviceRoleKey);
    const { error: deleteError } = await admin.auth.admin.deleteUser(user.id);

    if (deleteError) {
      return json({ error: deleteError.message }, 500);
    }

    return json({ ok: true, deletedUserId: user.id }, 200);
  } catch (e) {
    return json({ error: String(e) }, 500);
  }
});

function json(body: unknown, status: number): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}
