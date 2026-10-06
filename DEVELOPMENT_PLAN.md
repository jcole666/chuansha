# 穿啥 · 开发计划

> 最后更新：2026-10-06
> 当前版本：`1.1.3+9`

---

## 〇、进度总览

| 任务 | 状态 |
|---|---|
| 1.1 编辑衣物换图 + 重新抠图 | ✅ 已完成 |
| 1.2 我的搭配支持编辑 | ✅ 已完成 |
| 1.3 详情页「今天穿了」 | ✅ 已完成 |
| 1.4 设置页 / 关于页 | ✅ 已完成 |
| 2.1 忘记密码 | ✅ 已完成 |
| 2.2 注销账号 + 数据清空 | ✅ 客户端 + Edge Function 代码完成（**函数需你部署**） |
| 2.3 隐私政策 | ✅ 已完成（引导页已加同意勾选） |
| 6.1 清理死代码与未使用依赖 | ✅ 已完成 |
| 6.3 CI | ✅ 已完成 |
| 其余（3.x / 4.x / 5.x / 6.2 / 6.4 / 7.x） | ⬜ 待办 |

---

## 一、现状

### 已经跑通的闭环

```
录入衣物 → 抠图 → 衣橱管理 → 天气推荐 → 今天穿这套 → 穿搭日历 → 统计
```

这条链路上每一环都有真实实现。已完成的三轮修复：

| 批次 | 内容 |
|---|---|
| 第一轮 | 平台权限补全、搭配列表加载、性别链路打通、路由守卫 |
| 第二轮 | 自动抠图重写、手动描边抠图、rotateImage 后缀修复 |
| 第三轮 | 假成功提示修复、RLS 策略、天气真实定位 + 密钥外置、copyWith 置空、release 签名 |

### ⚠️ 待用户手动完成

- **执行 Supabase RLS 策略**：`supabase/rls_policies.sql` 需在 Supabase 控制台跑一次。
  仓库是公开的，未开 RLS 等于所有人都能用你的 key 读写全部用户数据。
- **配置天气密钥**：`flutter run --dart-define=OWM_API_KEY=你的密钥`
- **配置 Android 签名**：`android/key.properties`（见 `key.properties.example`）

---

## 二、阶段规划

优先级说明：**P0 = 必须做（体验断裂 / 合规硬要求）**，**P1 = 应该做**，**P2 = 可以缓**。
工作量：小 ≈ 半天内，中 ≈ 1–2 天，大 ≈ 3 天以上。

---

### 阶段 1 · 补断裂（P0）

把「功能明明写了却差最后一步」的地方补上。这一阶段性价比最高。

#### 1.1 编辑衣物支持换图 + 重新抠图　`中`

**问题**：`edit_item_page.dart` 里没有任何图片相关代码。照片拍糊了、抠图不满意，只能删掉重录，
已填的分类、标签、价格、穿着记录全部丢失。而抠图功能（智能 + 手动）**只有录入那一刻能用一次**。

**改动点**：
- 抽取 `add_item_provider.dart` 里的抠图流程为可复用的组件/流程，
  或直接在编辑页内嵌一段「换图」流程
- `edit_item_page.dart`：顶部缩略图改为可点击，点击后弹出「重新拍照 / 从相册选」
- 换图后走同一套抠图选择（智能 / 手动 / 跳过），完成后替换 `imageUrl` 并重新上传

**验收标准**：
- 编辑页点击图片能换图，抠图后可预览
- 换图后保存，衣橱列表缩略图更新
- 分类/标签/价格等字段不被清空
- 旧图片最好从 Storage 删除（避免孤儿文件堆积）

**依赖**：无

---

#### 1.2 我的搭配支持编辑　`小`

**问题**：`outfit_provider.updateOutfit()` 已实现，但**没有任何 UI 调用它**。
搭配建好后改不了名字、加减单品，只能删了重建。

**改动点**：
- `outfit_list_page.dart`：搭配卡片加「编辑」入口（长按菜单或详情页）
- 复用现有的 `_CreateOutfitDialog`，改为支持传入初始值
- 保存时调 `updateOutfit`，按返回值提示真实结果（参考 `addOutfit` 的写法）

**验收标准**：能改名称、能增减单品、失败有真实错误提示

**依赖**：无（`updateOutfit` 已就绪）

---

#### 1.3 详情页支持「今天穿了」　`小`

**问题**：`item_detail_page.dart` 只有编辑/删除。想记录"今天穿了这件"，
得绕到日历页手动勾选。

**改动点**：
- `item_detail_page.dart` AppBar 加操作：一键写入今日 `wear_record`
- 复用 `wearCalendarProvider.addRecord()`
- 已记录过则显示「今天已穿」并禁用（参考 `recommend_page._recordToday` 的防连点写法）

**验收标准**：点击后日历页当天出现该衣物，`wearCount` +1

**依赖**：无

---

#### 1.4 设置页 / 关于页落地　`小`

**问题**：`profile_page.dart:88,94` 两个菜单项都是 `onTap: () {}`；
「关于」写死"版本 1.0.0"，实际是 `1.1.3+9`；`AppRoutes.settings` 常量存在但无对应路由。

**改动点**：
- `core/router.dart` 注册 `AppRoutes.settings` 路由
- 新建 `settings_page.dart`：性别修改、默认视图模式、清除缓存、退出登录
- 新建 `about_page.dart`：版本号从 `package_info_plus` 读（不要写死）、开源许可、联系方式
- 版本号同步修正

**验收标准**：两个入口都能进真实页面，版本号与实际一致

**依赖**：需新增依赖 `package_info_plus`

---

### 阶段 2 · 账号与合规（P0）

应用市场（尤其 App Store）审核的硬要求，缺了可能上不了架。

#### 2.1 忘记密码　`小`

**问题**：只有登录/注册，用户忘记密码直接卡死。

**改动点**：
- `auth_provider.dart` 加 `resetPassword(email)` → `Supabase.auth.resetPasswordForEmail`
- `auth_page.dart` 登录表单下加「忘记密码？」入口，弹窗输入邮箱
- 提示「重置链接已发送到邮箱」

**验收标准**：能收到重置邮件，链接可改密

**依赖**：Supabase 后台需配置邮件模板与跳转地址

---

#### 2.2 注销账号 + 数据清空　`中`

**问题**：无账号删除入口。**App Store 审核强制要求**提供账号删除功能。

**改动点**：
- `settings_page.dart` 加「注销账号」，二次确认（输入"确认注销"防误触）
- 删除顺序：`clothing_items` / `wear_records` / `outfits` → Storage 图片 → `users` → `auth.users`
- 前端只能删自己的数据行；**删除 `auth.users` 需要服务端能力**，
  方案二选一：
  - Supabase Edge Function + service_role key（推荐）
  - 数据库 trigger / RPC 函数
- 删除后清本地缓存并登出

**验收标准**：注销后该账号数据全部消失，无法再登录

**依赖**：需要写一个 Supabase Edge Function 或 RPC

---

#### 2.3 隐私政策 / 用户协议　`小`

**改动点**：
- 新增两个页面或在「关于」里内嵌
- 首次启动（引导页）加勾选同意
- 内容需说明：收集哪些数据（衣物照片、位置、邮箱）、用途、存储位置（Supabase）、如何删除

**验收标准**：上架时能提供隐私政策 URL

**依赖**：需要你提供正式文本（可用模板改）

---

### 阶段 3 · 数据可靠性（P1）

#### 3.1 引入本地持久化　`中`

**问题**：项目**连本地存储依赖都没有**（无 `shared_preferences`），
所有状态都是内存态，冷启动全丢。

**改动点**：
- 引入 `shared_preferences`（或 `hive` 用于结构化数据）
- 封装 `LocalStore` 统一读写，避免各处散落
- 首批要持久化的：引导页已读标记、视图模式、筛选偏好、上次定位坐标

**验收标准**：重启 App 后这些偏好保持

**依赖**：无

---

#### 3.2 引导页只出现一次　`小`

**问题**：没有 `hasSeenOnboarding` 标记，未登录用户**每次冷启动都要滑三页**。

**改动点**：
- 依赖 3.1 的本地存储
- `core/router.dart` 的 `redirect` 里加判断：已看过引导 → 直接去登录页
- 引导页加「跳过」按钮

**验收标准**：看过一次后不再出现

**依赖**：3.1

---

#### 3.3 离线缓存 + 网络状态真实化　`大`

**问题**：所有数据每次从 Supabase 实时拉，断网即白屏 + 报错。
`network_provider.dart` 是假的（永远"有网"）且**全项目零引用**。

**改动点**：
- 引入 `connectivity_plus`，让 `network_provider` 变成真实监听
- 仓库层加本地缓存：网络可用时写缓存，不可用时读缓存
- 顶部加离线提示条
- 写入操作在离线时排队或明确禁用（不要让用户以为存上了）

**验收标准**：飞行模式下仍能看到上次的衣橱数据，并有明确离线提示

**依赖**：3.1

---

### 阶段 4 · 智能与个性化（P1）

#### 4.1 偏好反馈落库　`中`

**问题**：`recommend_provider.dart:161` 挂着 `// TODO: V2 - 存储到 Supabase`。
👍/👎 只活在内存里，退出就没。

**改动点**：
- 新建 Supabase 表 `preference_feedback`（`user_id` / `item_ids` / `liked` / `created_at`）
- 补 RLS 策略（追加到 `supabase/rls_policies.sql`）
- `recommend_provider.like/dislike` 改为写入数据库
- 失败时不要假装成功（沿用第三轮的 `Future<bool>` + rethrow 模式）

**验收标准**：点赞后重启 App 仍记得

**依赖**：需在 Supabase 建表

---

#### 4.2 让偏好真正参与推荐评分　`中`

**问题**：`recommendation_service.dart` 里 `preferenceScore = 5` 是**硬编码**，
"偏好"这一维度（满分 10）压根没参与推荐。`dislikedCombinations` 参数也从未被使用。

**改动点**：
- 读 `preference_feedback`，计算单品/标签维度的偏好权重
- `_score()` 里用真实偏好分替换硬编码的 5 分
- 让 `dislikedCombinations` 真正过滤掉用户讨厌的组合

**验收标准**：多次点赞某风格后，推荐结果中该风格占比上升

**依赖**：4.1

---

#### 4.3 推荐理由展示　`小`

**问题**：`RecommendationResult.scoreDetails` 已经算出了「风格协调 / 颜色搭配 / 新鲜度 /
天气匹配 / 偏好」五个维度，但**界面上没展示**。

**改动点**：
- `recommend_page.dart` 的推荐卡片加「为什么推荐这套」，展开显示各维度得分
- 或翻译成人话，如「15°C 适合这件针织衫 · 和你的裤子是同色系」

**验收标准**：用户能看懂推荐依据

**依赖**：无（数据已就绪，纯展示）

---

### 阶段 5 · 体验打磨（P2）

#### 5.1 深色模式　`中`

`app.dart` 只给了 `theme: AppTheme.lightTheme`，没有 `darkTheme`。
`app_theme.dart` 需补一套暗色配色，`MaterialApp.router` 加 `darkTheme` + `themeMode`。
配合 3.1 记住用户选择。

#### 5.2 图片加载与缓存优化　`小`

`ItemImage` 用了 `cached_network_image`，但可以补：占位骨架屏、加载失败重试、
缩略图尺寸参数（避免列表里加载原图）。

#### 5.3 空态 / 加载态统一　`小`

各页面空态文案与样式不统一，抽一个 `EmptyView` / `ErrorView` 组件复用。
（`recommend_page` 已有 `ErrorView`，可提取到 `shared/widgets/`）

---

### 阶段 6 · 工程健康（P2，可与前面并行）

#### 6.1 清理死代码与未使用依赖　`小`

**零引用依赖**（可直接从 `pubspec.yaml` 删除）：
`dio`、`flutter_image_compress`、`flutter_cache_manager`、`freezed`、`freezed_annotation`、
`json_annotation`、`json_serializable`、`build_runner`、`mocktail`、`riverpod_annotation`

> 注意：`geolocator` / `geocoding` / `http` / `uuid` / `intl` / `cached_network_image`
> 都在用，**不要删**。

**死代码**：
- `lib/features/auth/presentation/providers/network_provider.dart`（零引用且逻辑是假的，被 3.3 取代后可删）
- `lib/data/models/wear_log.dart`（零引用，被 `wear_record.dart` 取代）
- `lib/data/models/user_preferences.dart`（零引用）
- `AppRoutes.recommend` / `register` 无对应路由

> `memory_wardrobe_repository.dart` **不是**死代码，测试在用。

#### 6.2 补单元测试　`中`

目前只有 2 个测试文件，核心算法零覆盖。优先补：

| 目标 | 说明 |
|---|---|
| `matte_geometry.dart` | 扫描线填充、平滑、吸附（已抽成纯 Dart，就是为了可测） |
| `matting_service.dart` | 各背景/衣物颜色组合的抠图结果 |
| `recommendation_service.dart` | 温度过滤边界、评分逻辑 |
| `color_utils.dart` | 色相差异计算 |
| 各模型 `copyWith` | 特别是 clearXxx 开关 |

#### 6.3 CI（analyze + test）　`小`

新增 `.github/workflows/ci.yml`：push / PR 时跑 `flutter analyze` + `flutter test`。
仓库已在 GitHub 上，接上很划算。

#### 6.4 错误上报　`中`

目前异常只弹 SnackBar，线上出问题无从查起。
接入 Sentry 或 Firebase Crashlytics，至少覆盖：Supabase 调用失败、抠图失败、图片上传失败。

---

### 阶段 7 · 发布准备（P0，准备上架时做）

- **7.1 应用图标与启动页** `小` — 当前是 Flutter 默认图标
- **7.2 版本管理** `小` — `pubspec.yaml` 的 `version` 与「关于」页打通
- **7.3 上架材料** `中` — 应用截图、描述、隐私政策 URL、账号删除入口（依赖 2.2 / 2.3）
- **7.4 包体积优化** `小` — 当前 8 个未使用依赖会白占体积；可用 `--split-per-abi`

---

## 三、建议的推进顺序

```
阶段 1（补断裂）  ──┐
                    ├──→ 阶段 2（合规）──→ 阶段 7（发布）
阶段 6.1 / 6.3 ────┘

阶段 3（数据可靠性）──→ 阶段 4（智能化）──→ 阶段 5（打磨）
```

**如果只做三件事**，按这个顺序：

1. **1.1 编辑衣物换图** —— 抠图刚做完却只能用一次，这是最大的体验断裂
2. **1.2 搭配编辑** —— `updateOutfit` 已就绪，纯接线活，投入产出比最高
3. **2.2 注销账号** —— 上架硬门槛，早做早省事

---

## 四、风险与注意事项

| 风险 | 说明 |
|---|---|
| **RLS 未执行** | 仓库公开 + 前端 key 可提取，未开 RLS 等于数据裸奔。**这是当前唯一的高危项** |
| 删除 `auth.users` 需服务端 | 纯前端做不到，必须写 Edge Function 或 RPC（2.2 的卡点） |
| 换图产生孤儿文件 | 1.1 换图后要删旧 Storage 文件，否则存储越用越满 |
| 天气免费额度 | OpenWeatherMap 免费档有调用上限，用户量上来需换付费档或加缓存 |
| 抠图算法天花板 | 纯算法只适合纯色背景，复杂背景靠手动。要"秒抠"需接 ML 模型，成本高，暂不建议 |
| 无本地缓存 | 冷启动慢、断网不可用，3.1 / 3.3 解决 |

---

## 五、验收清单（发布前逐项确认）

- [ ] Supabase RLS 已执行并通过自检查询
- [ ] 天气密钥通过 `--dart-define` 注入，未写入源码
- [ ] `android/key.properties` 已配置正式签名
- [ ] 账号注销功能可用
- [ ] 隐私政策页面可访问
- [ ] 忘记密码流程可走通
- [ ] 深色模式下无文字不可读
- [ ] `flutter analyze` 无 error
- [ ] `flutter test` 全绿
- [ ] 真机跑通：拍照 → 抠图 → 保存 → 推荐 → 记录 → 统计
