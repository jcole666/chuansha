-- ============================================================
-- 穿啥 · 推荐偏好反馈表
-- ============================================================
--
-- 用途：保存用户对推荐搭配的 👍/👎 反馈，
--       让推荐引擎能按个人偏好调整评分（而不是每次都靠通用规则）。
--
-- 怎么用：Supabase 控制台 → SQL Editor → 整段粘贴 → Run。
--         幂等，可重复执行。
--
-- 执行后请确认最后一条自检查询返回 rls开启 = true。
-- ============================================================

create table if not exists public.preference_feedback (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references public.users (id) on delete cascade,

  -- 这一次反馈涉及的单品（一套搭配可能有 3-4 件）
  item_ids    text[] not null default '{}',

  -- true = 👍 喜欢，false = 👎 不喜欢
  liked       boolean not null,

  created_at  timestamptz not null default now()
);

-- 按用户查反馈是唯一的读取方式，建索引
create index if not exists preference_feedback_user_id_idx
  on public.preference_feedback (user_id, created_at desc);


-- ------------------------------------------------------------
-- 行级安全策略（与其余表保持一致：只能访问自己的行）
-- ------------------------------------------------------------
-- 注意：这里必须开 RLS，否则公开的前端 key 能读到所有人的反馈。

alter table public.preference_feedback enable row level security;

drop policy if exists "preference_feedback_select_own"
  on public.preference_feedback;
create policy "preference_feedback_select_own"
  on public.preference_feedback for select
  to authenticated
  using (auth.uid() = user_id);

drop policy if exists "preference_feedback_insert_own"
  on public.preference_feedback;
create policy "preference_feedback_insert_own"
  on public.preference_feedback for insert
  to authenticated
  with check (auth.uid() = user_id);

drop policy if exists "preference_feedback_update_own"
  on public.preference_feedback;
create policy "preference_feedback_update_own"
  on public.preference_feedback for update
  to authenticated
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

drop policy if exists "preference_feedback_delete_own"
  on public.preference_feedback;
create policy "preference_feedback_delete_own"
  on public.preference_feedback for delete
  to authenticated
  using (auth.uid() = user_id);


-- ------------------------------------------------------------
-- 自检：期望 rls开启 = true，策略数 = 4
-- ------------------------------------------------------------
select
  c.relname                    as 表名,
  c.relrowsecurity             as rls开启,
  count(p.policyname)          as 策略数
from pg_class c
join pg_namespace n on n.oid = c.relnamespace
left join pg_policies p
  on p.schemaname = 'public' and p.tablename = c.relname
where n.nspname = 'public'
  and c.relname = 'preference_feedback'
group by c.relname, c.relrowsecurity;
