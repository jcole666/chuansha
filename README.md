# 穿啥 (chuansha)

一款智能衣橱管理 App —— 拍下你的衣服，自动抠图归类，根据天气帮你决定今天穿什么。

Flutter + Riverpod + Supabase 构建，无需 Google 服务，Android / iOS 双端。

---

## 功能

| 模块 | 说明 |
|---|---|
| **衣橱** | 拍照/相册录入衣物，自动抠图去背景，分类、颜色、季节、场合、风格多维标签，支持筛选、搜索、排序 |
| **抠图** | 双方案：**智能抠图**（接 MODNet AI 分割模型，花地板/杂背景/浅色衣服都能抠；模型不可用时自动降级为纯色背景算法）+ **手动抠图**（PS 风磁性套索，沿边缘点/拖自动吸附，右上角放大镜防手指遮挡） |
| **搭配推荐** | 根据实时天气（温度/降水）从你的衣橱里推荐穿搭组合，可 👍/👎 反馈 |
| **穿搭日历** | 记录每天穿了什么，自动累计衣物穿着次数，计算性价比 |
| **统计** | 穿着频次、性价比排行 |
| **账号** | Supabase Auth 邮箱注册/登录、忘记密码、注销账号（含数据清空） |
| **设置** | 性别、主题（跟随系统/浅色/深色）、默认视图、清除缓存、运行日志 |
| **离线可用** | 断网时回退本地缓存并明确提示，不会白屏 |
| **深色模式** | 完整适配，跟随系统或手动切换 |

---

## 技术栈

- **框架**：Flutter（Dart SDK `^3.12.2`）
- **状态管理**：Riverpod 2.6（`StateNotifier` + `Provider`）
- **路由**：go_router 17（含登录态守卫 `redirect`）
- **后端**：Supabase 2.8（Auth + PostgREST + Storage）
- **图像处理**：`image` 4.8（纯 Dart，无原生依赖）
- **定位/天气**：`geolocator` + `geocoding` + OpenWeatherMap API

---

## 快速开始

### 1. 准备环境

```bash
flutter --version   # 需要 Dart SDK ^3.12.2
flutter pub get
```

### 2. 配置天气密钥（必做）

OpenWeatherMap 的 API Key **不再硬编码在源码里**，改为编译期注入：

```bash
# 到 https://openweathermap.org/api 免费申请一个 key，然后：
flutter run --dart-define=OWM_API_KEY=你的密钥
```

> 不传这个参数也能启动，但推荐页会显示「未配置天气服务」而不是假数据 —— 这是有意为之，
> 避免用户看到伪造的天气。

也可以把密钥写进一个本地文件（已 gitignore）再引用：

```bash
# config.json
{ "OWM_API_KEY": "你的密钥" }

flutter run --dart-define-from-file=config.json
```

### 3. 配置 Supabase（首次部署必做）

Supabase 项目 URL 与 publishable key 已写在 `lib/core/supabase_config.dart`，
通常无需改动。**但行级安全（RLS）策略必须手动执行一次**：

打开 Supabase 控制台 → **SQL Editor** → 把 `supabase/rls_policies.sql`
整个文件粘进去 → Run。

> ⚠️ **这一步不能跳过。** 前端打包的 publishable key 是公开的（本仓库也是公开仓库）。
> 如果表没开 RLS，任何人都能用这个 key 读写**全部用户**的衣橱数据，甚至删库。
> 开启后每个用户只能访问自己的行（策略规则 `auth.uid() = user_id`）。
>
> SQL 文件末尾附了自检查询，执行完可以验证每张表的 `rowsecurity = true` 且策略数 > 0。

需要存在的表：

| 表 | 用途 |
|---|---|
| `users` | 用户档案（`id` = `auth.users.id`，含 `gender`） |
| `clothing_items` | 衣物单品 |
| `wear_records` | 穿搭日历记录 |
| `outfits` | 自建搭配组合 |

Storage 需要名为 `clothing` 的 bucket，图片路径约定 `users/{userId}/xxx.jpg`。

### 4. 运行

```bash
flutter run --dart-define=OWM_API_KEY=你的密钥
```

---

## 排查问题

应用内 **设置 → 运行日志** 会记录运行期异常与关键流程失败，
支持一键复制。真机联调时遇到问题，把日志复制出来即可定位。

全局异常（`FlutterError` / 未捕获异步异常）会自动记录，无需手动埋点。

---

## 应用图标

图标由 `tools/make_icon.py` 用代码绘制（矢量风格衣架 + 品牌紫渐变），
结果确定、可复现，不依赖设计稿：

```bash
python tools/make_icon.py
```

会一次性输出 Android 5 档 mipmap 与 iOS 全套 16 个尺寸。
改配色或形状直接改脚本里的常量即可。

---

## 发布构建

### Android

release 包**不再使用 debug 签名**。首次发布前配置签名：

```bash
# 1. 生成 keystore（只做一次，务必备份）
keytool -genkey -v -keystore chuansha-release.jks \
  -keyalg RSA -keysize 2048 -validity 10000 -alias chuansha

# 2. 复制模板并填入真实信息
cp android/key.properties.example android/key.properties
#    然后编辑 android/key.properties

# 3. 构建
flutter build apk --release --dart-define=OWM_API_KEY=你的密钥
```

> `android/key.properties` 与 `*.jks` 已在 `.gitignore` 中，**不要提交**。
> 若未配置，构建会退回 debug 签名并在日志里打警告（仅够本地调试，不能上架）。

打包的 ABI：`arm64-v8a` / `armeabi-v7a` / `x86_64`（覆盖真机与模拟器）。
追求体积可用 `--split-per-abi` 出分包。

### iOS

```bash
flutter build ipa --dart-define=OWM_API_KEY=你的密钥
```

需要在 Xcode 里配置自己的 Team 与 Bundle Identifier。

---

## 项目结构

```
lib/
├── core/                  # 基础设施
│   ├── app_config.dart        # 编译期配置（--dart-define 读取）
│   ├── router.dart            # 路由表 + 登录态守卫
│   ├── supabase_config.dart   # Supabase 连接配置
│   ├── constants/             # 路由路径、分类/颜色/风格数据
│   └── theme/                 # 主题
├── data/
│   ├── models/                # 数据模型（ClothingItem / Outfit / WearRecord ...）
│   └── repositories/          # 仓库层（Supabase 实现 + 内存实现）
├── domain/enums/          # 领域枚举
├── services/              # 无状态服务
│   ├── ai_matting_service.dart     # AI 智能抠图（MODNet ONNX 推理 → alpha 合成白底）
│   ├── matting_service.dart        # 降级抠图（纯色背景洪水填充 + 后处理）
│   ├── manual_matte_service.dart   # 手动抠图（描边 + 扫描线填充）
│   ├── matte_geometry.dart         # 抠图几何算法（Sobel/距离场/Livewire 最短路，纯 Dart 可单测）
│   ├── matte_blend.dart            # 白底合成（二值遮罩 / 连续 alpha 两种）
│   ├── location_service.dart       # 定位
│   ├── weather_service.dart        # 天气
│   └── image_service.dart          # 拍照/相册/旋转
├── features/              # 按功能分模块（presentation / providers / pages）
│   ├── auth/  wardrobe/  outfit/  calendar/  recommend/  profile/
├── shared/widgets/        # 复用组件
assets/
└── models/                # AI 抠图模型
    ├── modnet_fp16.onnx           # MODNet 主体分割（fp16，约 12MB）
    ├── modnet_config.json         # 模型来源参考（注：其中 dtype 标注与权重实际精度不一致）
    └── modnet_preprocessor.json   # 预处理参数（mean/std/短边/整除倍数，代码据此实现）
```

---

## 已知限制

- **智能抠图**接的是 MODNet 分割模型（ONNX），能处理花纹地板、衣服堆叠、浅色衣服等复杂背景。
  模型不可用（机型不支持 / 内存不足）时**自动降级**到纯色背景算法，不会堵死入口。
  衣服占满整个画面时仍建议用**手动抠图**。
- **手动抠图**是 PS 磁性套索风格：点一下落锚点（自动吸附边缘），也可按住沿边拖动走自动吸附线；
  右上角常驻放大镜，避免手指挡住视线。
- 天气依赖第三方 API，免费额度有限；未配置密钥时功能降级为提示而非假数据。
- 目前仅支持邮箱注册登录，暂无第三方登录。
- AI 模型会让 APK 体积增大约 12MB 以上（模型 + onnxruntime native 库）。

---

## 开发说明

```bash
flutter pub get          # 拉依赖（新增 onnxruntime 后必须执行一次）
flutter analyze          # 静态检查
flutter test             # 单元测试
dart format lib/         # 格式化
```

> AI 抠图依赖 `onnxruntime` 与 `assets/models/modnet_fp16.onnx`（约 12MB，已入库）。
> 换机器 / 拉新代码后先 `flutter pub get`，否则 `AiMattingService` 无法编译。

> 若 `flutter analyze` 报 `CreateFile failed 231（管道范例都在使用中）`，
> 那是 Windows 管道句柄耗尽的环境问题，重启终端或改用 IDE 分析器即可。

---

## License

个人项目，暂未指定开源协议。
