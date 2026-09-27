-- ============================================================
-- 穿啥 · Supabase 行级安全（RLS）策略
-- ============================================================
--
-- 为什么必须开：
--   前端打包的 anon / publishable key 是公开的（反编译即可提取）。
--   如果表没开 RLS，任何人都能用这个 key 读写**全部用户**的数据
--   （别人的衣橱、穿搭记录，甚至直接删库）。
--   开启 RLS 且策略限制 `auth.uid() = user_id` 之后，
--   每个用户只能看到/修改自己的行。
--
-- 怎么用：
--   打开 Supabase 控制台 → SQL Editor → 新建查询 → 整段粘进去 → Run。
--   这段 SQL 是幂等的（drop ... if exists + create），可以重复执行。
--
-- 执行完请务必用「验证」小节里的查询自检一遍。
-- ============================================================


-- ------------------------------------------------------------
-- 0. 前置检查：这四张表是否已存在
-- ------------------------------------------------------------
-- 若报 relation does not exist，说明表名不同，请先对照调整。
-- 期望存在：users / clothing_items / wear_records / outfits


-- ------------------------------------------------------------
-- 1. users
-- ------------------------------------------------------------
-- 用途：存用户档案（id 即 auth.users.id，还有 gender / email）
-- 策略要点：
--   - 只能读自己的记录
--   - 只能插入/更新自己的记录（id 必须等于 auth.uid()）
--   - 允许删除自己（级联清理用，视业务可去掉）
-- 注意：insert/update 的 with check 必须是 auth.uid() = id，
--       不能是 = user_id（这张表没有 user_id 列）。

alter table public.users enable row level security;

drop policy if exists "users_select_own" on public.users;
create policy "users_select_own"
  on public.users for select
  to authenticated
  using (auth.uid() = id);

drop policy if exists "users_insert_own" on public.users;
create policy "users_insert_own"
  on public.users for insert
  to authenticated
  with check (auth.uid() = id);

drop policy if exists "users_update_own" on public.users;
create policy "users_update_own"
  on public.users for update
  to authenticated
  using (auth.uid() = id)
  with check (auth.uid() = id);

drop policy if exists "users_delete_own" on public.users;
create policy "users_delete_own"
  on public.users for delete
  to authenticated
  using (auth.uid() = id);


-- ------------------------------------------------------------
-- 2. clothing_items
-- ------------------------------------------------------------
-- 用途：衣物单品（含图片 URL、分类、标签、价格等）
-- 注意：本项目 update/delete 目前是按 id 操作（没有 .eq('user_id', ...)），
--       所以这里的 using 子句是**唯一**的越权防线，必须保留。

alter table public.clothing_items enable row level security;

drop policy if exists "clothing_items_select_own" on public.clothing_items;
create policy "clothing_items_select_own"
  on public.clothing_items for select
  to authenticated
  using (auth.uid() = user_id);

drop policy if exists "clothing_items_insert_own" on public.clothing_items;
create policy "clothing_items_insert_own"
  on public.clothing_items for insert
  to authenticated
  with check (auth.uid() = user_id);

drop policy if exists "clothing_items_update_own" on public.clothing_items;
create policy "clothing_items_update_own"
  on public.clothing_items for update
  to authenticated
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

drop policy if exists "clothing_items_delete_own" on public.clothing_items;
create policy "clothing_items_delete_own"
  on public.clothing_items for delete
  to authenticated
  using (auth.uid() = user_id);


-- ------------------------------------------------------------
-- 3. wear_records
-- ------------------------------------------------------------
-- 用途：穿搭日历记录（某天穿了哪些衣服）
-- 注意：代码里还会 update clothing_items 的 wear_count / last_worn_date
--       （见 wear_calendar_provider），那条更新同样受 clothing_items 策略约束。

alter table public.wear_records enable row level security;

drop policy if exists "wear_records_select_own" on public.wear_records;
create policy "wear_records_select_own"
  on public.wear_records for select
  to authenticated
  using (auth.uid() = user_id);

drop policy if exists "wear_records_insert_own" on public.wear_records;
create policy "wear_records_insert_own"
  on public.wear_records for insert
  to authenticated
  with check (auth.uid() = user_id);

drop policy if exists "wear_records_update_own" on public.wear_records;
create policy "wear_records_update_own"
  on public.wear_records for update
  to authenticated
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

drop policy if exists "wear_records_delete_own" on public.wear_records;
create policy "wear_records_delete_own"
  on public.wear_records for delete
  to authenticated
  using (auth.uid() = user_id);


-- ------------------------------------------------------------
-- 4. outfits
-- ------------------------------------------------------------
-- 用途：用户自建的搭配组合

alter table public.outfits enable row level security;

drop policy if exists "outfits_select_own" on public.outfits;
create policy "outfits_select_own"
  on public.outfits for select
  to authenticated
  using (auth.uid() = user_id);

drop policy if exists "outfits_insert_own" on public.outfits;
create policy "outfits_insert_own"
  on public.outfits for insert
  to authenticated
  with check (auth.uid() = user_id);

drop policy if exists "outfits_update_own" on public.outfits;
create policy "outfits_update_own"
  on public.outfits for update
  to authenticated
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

drop policy if exists "outfits_delete_own" on public.outfits;
create policy "outfits_delete_own"
  on public.outfits for delete
  to authenticated
  using (auth.uid() = user_id);


-- ------------------------------------------------------------
-- 5. Storage（衣物图片）
-- ------------------------------------------------------------
-- 图片存在 Storage bucket `clothing` 里（见 image_upload_service.dart）。
-- 上传路径约定：users/{userId}/{timestamp}.{ext}
-- 因此用 storage.foldername 取第二段比对 auth.uid()。
--
-- 若 bucket 名有变化，请同步改掉下面的 'clothing'。

-- 读取：登录用户可读（bucket 若为 public 可省略这条）
drop policy if exists "clothing_storage_read" on storage.objects;
create policy "clothing_storage_read"
  on storage.objects for select
  to authenticated
  using (bucket_id = 'clothing');

-- 只允许往自己的 users/{uid}/ 目录写
drop policy if exists "clothing_storage_insert_own" on storage.objects;
create policy "clothing_storage_insert_own"
  on storage.objects for insert
  to authenticated
  with check (
    bucket_id = 'clothing'
    and (storage.foldername(name))[1] = 'users'
    and (storage.foldername(name))[2] = auth.uid()::text
  );

drop policy if exists "clothing_storage_update_own" on storage.objects;
create policy "clothing_storage_update_own"
  on storage.objects for update
  to authenticated
  using (
    bucket_id = 'clothing'
    and (storage.foldername(name))[1] = 'users'
    and (storage.foldername(name))[2] = auth.uid()::text
  );

drop policy if exists "clothing_storage_delete_own" on storage.objects;
create policy "clothing_storage_delete_own"
  on storage.objects for delete
  to authenticated
  using (
    bucket_id = 'clothing'
    and (storage.foldername(name))[1] = 'users'
    and (storage.foldername(name))[2] = auth.uid()::text
  );


-- ------------------------------------------------------------
-- 6. 验证：确认 RLS 已开启
-- ------------------------------------------------------------
-- 期望每行 rowsecurity = true，且 policies 数量 > 0。
select
  c.relname                          as 表名,
  c.relrowsecurity                   as rls已开启,
  count(p.policyname)                as 策略数
from pg_class c
join pg_namespace n on n.oid = c.relnamespace
left join pg_policies p
  on p.schemaname = 'public' and p.tablename = c.relname
where n.nspname = 'public'
  and c.relname in ('users', 'clothing_items', 'wear_records', 'outfits')
group by c.relname, c.relrowsecurity
order by c.relname;


-- ------------------------------------------------------------
-- 7. 验证：模拟越权读取（应返回 0 行）
-- ------------------------------------------------------------
-- 说明：RLS 对 service_role / postgres 不生效，所以这里的查询
-- 在 SQL Editor 里可能仍能看到全部数据 —— 这是正常的。
-- 真正的验证方式见 README 里的「用 anon key 越权测试」。
