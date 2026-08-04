# StepLife 项目 AI 协作注意事项（每次修改代码前必读）

本文件会被 AI 自动加载并约束所有改动；完整架构与规则细则见 [docs/architecture.md](docs/architecture.md)。发布节奏与用户偏好见文末。

## 🔴 红线（违反即破坏用户数据/流程，绝对禁止）
1. **数据库非破坏迁移**：库文件 `steplife_v9.db`（schema version 9）。改表结构必须：升级前备份旧库（保留最近 3 份，含 WAL/SHM）、单事务内「只增列不重建表」、幂等（`PRAGMA table_info` 探测）、行数对账 + `integrity_check`、迁移留痕；新装与升级双路径一致。
2. **新表/新列必须同步 WebDAV 备份**：凡新增数据库表，必须加入 `database_service._syncTables`（备份表清单）与 WebDAV 恢复逻辑，否则云端备份缺表。
3. **用户数据零丢失**：禁止破坏性更新、禁止随意删除种子/默认数据（成员 A/B/C、默认分类依赖初始化逻辑）；升级必须可逆。
4. **正式签名不可回退**：release 构建签名由 `android/app/build.gradle.kts` 的 key.properties 决定，禁止改为 debug 签名；CI 用 GitHub Secrets 签名并校验指纹。
5. **打卡时间语义**：所有打卡时间精确到分钟（`yyyy-MM-dd HH:mm`），支持补卡/改时；展示一律按时间倒序（新→旧），与插入先后无关。

## 📐 核心规范（必须遵守，细则见 docs/architecture.md）
- **数据库升级**：改表结构必须递增 version，`_onUpgrade` 写 `ALTER TABLE` / `CREATE TABLE IF NOT EXISTS` 兼容逻辑且与 `_onCreate` 新建逻辑一致；`onOpen` 幂等补齐 `members.birthDate`（报错忽略）；`preferredViewMode` 新读 `app_settings`、缺省回退旧 `user_profile` 字段、写入双写保持降级兼容。
- **桌面端 FFI**：`lib/main.dart` 顶部的 `sqfliteFfiInit()` 与 `databaseFactory = databaseFactoryFfi` 判断不可删除（Windows / Linux / macOS 读写 SQLite 的关键前置）。
- **路线/打卡解耦**：客观路线资产 `RouteItem`（含 `isLocked` 锁定）与打卡履约 `StepLog` 严格解耦；锁定路线禁止删除/误编辑；打卡按 `timestamp` 倒序管理。
- **成员系统**：`Member` 全局共享（步量/家务/生活记录共用一套），换算优先用成员身高 (`heightCm`) 体重 (`weightKg`)，缺失回退全局 `UserProfile`；`age` 由 `birthDate` 动态计算，禁止持久化固定年龄。
- **量化展示**：开启量化登记的家务在主页 5 天日期阵列中**绝不显示 ✓**，统一 `NumberFormatter.formatQuantifiableValue`（1.2k / 15k / 1.5M）。
- **生活模板**：8 个模板键 movie / dining / book / place / shopping / basket / snack / generic；专属字段存 `extrasJson`（store_items 与 store_logs 均有），分类自定义字段存 `store_categories.extraFieldsJson`（`custom_N`）；`StoreLog` 必须记录分钟级时刻 / 消费 / 同行成员；Card ↔ 紧凑列表双视图经 `app_settings['preferredViewMode']` 持久化；Drawer 分类可创建/重命名（含模板绑定与自定义字段）/安全删除（记录归「通用分类」）。
- **图片**：选图必须 `CacheManager.copyToCache` 复制进应用缓存目录后再存路径，禁止存相册原路径；质量读 `app_settings['image_quality']`。
- **图标**：保持 100% 透明 Alpha 通道（RGBA）DIB ICO，严禁白色/浅色背景余边。
- **版本发布**：`pubspec.yaml` `version: 1.5.x+YYYYMMDD`，构建号用打包日期且必须递增；发布时同步更新 `assets/walkthrough.md` 更新日志、设置中心「更新记录与版本历史」与 README，保持多处一致。

- **生活导入导出**：核心在 `lib/core/export_import/`（StoreExporter / StoreImporter / ImportDraft / ImportPreviewScreen / BillParser）；导出支持单分类与全量（JSON v1，图片字段位预留）；导入分 L1 详情页纯打卡（parseLogsOnly）→ L2 新店铺建项目 → L3 模板全量；导入前必须 `vacuumInto` 快照备份（保留 3 份）+ 单事务回滚；AI 账单导入（OCR+DeepSeek）产出仅作建议，须经模拟导入页用户确认后落库；依赖 share_plus / file_picker / google_mlkit_text_recognition。

## 🧭 全局架构要点
- 入口 `lib/main.dart`：底部 4 个 Tab（路线/家务/生活/成员），「关于」已合并进设置中心；桌面 FFI 初始化不可删。
- 分层：presentation（页面，只渲染不碰库）→ providers（`ChangeNotifier`，先落库再更新内存并 `notifyListeners()`）→ domain（纯模型）→ core/db（`DatabaseService` 单例集中 SQL）；核心算法放 core/utils 可单测。
- 设置中心：TMDB Key / DeepSeek Key / WebDAV / 缓存上限与质量 / 主题 / 自动更新开关等，均存 `app_settings`（Key 明文）。
- 智能助手入口：家务/生活 AppBar 左上角纯图标（无文字）。

## 🔐 Android 权限清单（新增功能前先核对）
`INTERNET`（联网）、`ACCESS_*_LOCATION`（美食定位）、`RECORD_AUDIO`（智能助手语音）、`ACTIVITY_RECOGNITION`（计步测量，Android 10+ 运行时授权）、`REQUEST_INSTALL_PACKAGES`（自动更新安装）。加新权限记得同步运行时申请与设置引导。

## 📦 自动更新（核心链路，勿破坏）
- 检查/下载均有多源回退：直连 `api.github.com` 失败 → ghproxy 镜像（ghproxy.net / gh-proxy.com / ghfast.top / mirror.ghproxy.com），逐个失败才报错。
- APK 下载到应用 **cache 目录**（`getApplicationCacheDirectory()`），`file_paths.xml` 的 `cache-path` 已覆盖；勿改回 documents 目录（会导致 FileProvider 找不到路径、安装器拉起失败）。
- 拉起安装器前检查「安装未知应用」授权，未授权先跳系统设置引导。
- 发布：本地 release 构建验证 → commit → push → 远端 tag `v1.5.x+YYYYMMDD` 触发 `.github/workflows/release.yml` 自动构建 4 架构 APK 并发布。

## 🤖 智能助手（DeepSeek）
- 模型固定 `deepseek-v4-flash`；Key 存 `app_settings`；入口为家务/生活 AppBar 左上角纯图标。
- AI 只返回结构化 JSON 动作；客户端做「名称存在性二次校验」（AI 匹配值必须命中本地清单，否则降级为新建确认）；**所有动作必须渲染确认卡片、用户确认后才落库**，禁止 AI 输出直接写库。
- 语音用 speech_to_text（Android 系统识别 + 运行时申请），Windows 桌面退化为文本输入。

## 🧪 交付前验证
依次运行且 0 错误：`flutter analyze` → `flutter test`（如涉及）→ release 构建。

## 🧰 Flutter 工具链卡死排查（僵尸进程防护）
- 现象：`flutter run/analyze` 长时间无响应、CPU 持续烧高，通常是 flutter.bat 包装进程在 `bin\cache\flutter.bat.lock` 的 `:acquire_lock` 循环空转（沙箱写权限不足或残留 wrapper 进程导致），会阻塞后续所有 flutter 命令。
- 先查：`Get-Process | Where-Object { $_.Name -in 'cmd','dart' -and $_.CPU -gt 30 }`，发现高 CPU 的 cmd/dart 即 `Stop-Process -Id <PID>` 清理；勿放任不管（单个进程一天可烧数万 CPU 秒）。
- 一键修复：运行 `scripts/cleanup_flutter_zombies.ps1`（先 `-ListOnly` 预览；结束僵尸进程后会自动清理过期锁文件）。
- 预防：所有 flutter 命令必须用已批准前缀在沙箱外执行（如 `-Last 30` 等已批准后缀），禁止用未批准后缀在沙箱内跑 flutter，避免写锁文件被拒后触发 `:acquire_lock` 死循环。

## 🛠 环境与协作约定（用户偏好）
- 中文沟通；大改动先出方案，用户确认后再实施。
- 常规节奏：改代码 → 验证 → commit → push → 升版本 → 打包 → 发布（用户会明确下令，不要擅自发布）。
- 本环境 `apply_patch` 不可用，文件读写用 Node REPL；Dart 模板字符串 `${...}` 在 JS 模板串中要写成 `\${...}`；JS 替换一律用 `split(old).join(new)`。
- commit 通过临时文件 `git commit -F`；git 只读/写命令需按已批准前缀执行（组合命令会被沙箱拦截，需拆开单独跑）；大部分 Dart 文件 LF 行尾，git 的 CRLF 警告属正常，勿批量转换行尾。
