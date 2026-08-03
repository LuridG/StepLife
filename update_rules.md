# StepLife (步履生活) - AI 协作规范与架构更新规则 (`update_rules.md`)

本文档放置于项目根目录，旨在为后续 AI 助手或开发者提供完整的**更新注意事项**、**核心规则约束**及**整体架构蓝图**，确保后续迭代不破坏既有业务逻辑与代码约定。
> 完整架构说明（目录结构、分层数据流、数据库设计、扩展指南）详见 [ARCHITECTURE.md](ARCHITECTURE.md)。

---

## ⚠️ 每次代码更新必须遵守的核心注意事项 (Update Rules)

### 1. 数据库升级规范 (SQLite Schema Versioning)
- 数据库位于 [lib/core/db/database_service.dart](file:///g:/MiniProject2026/steplife/lib/core/db/database_service.dart)。
- **规则**：当前版本：`steplife_v9.db` / `version: 9`。若修改表结构或新增字段，必须递增版本号，并在 `_onUpgrade` 编写 `ALTER TABLE` / `CREATE TABLE IF NOT EXISTS` 兼容逻辑，同时确保 `_onCreate` 新建逻辑一致（新装与升级双路径一致）。
- **规则（非破坏迁移）**：升级前必须先把旧库复制为 `steplife_v8_backup_<时间戳>.db`（保留最近 3 份，含 WAL/SHM）；迁移全程在单个事务内执行「只增列、不重建表」的增量变更，收尾做行数对账（`COUNT(*)` 前后一致）、`PRAGMA integrity_check` 与迁移留痕（`app_settings.last_schema_migration`），任一失败整体回滚；迁移必须幂等（列已存在则跳过，用 `PRAGMA table_info` 探测）。
- **补充**：`onOpen` 中幂等执行 `ALTER TABLE members ADD COLUMN birthDate`（报错忽略），用于兼容旧库补齐出生日期列。
- **规则（偏好迁移）**：`preferredViewMode` 新读 `app_settings`，缺省回退旧 `user_profile.preferredViewMode`，写入时双写保持降级兼容。

### 2. 桌面端 SQLite FFI 兼容规则
- **规则**：[lib/main.dart](file:///g:/MiniProject2026/steplife/lib/main.dart) 顶部的 `sqfliteFfiInit()` 与 `databaseFactory = databaseFactoryFfi` 判断不可删除！这是 Windows / Linux / macOS 桌面端能正常读写 SQLite 的关键前置初始化。

### 3. 路线资产与行走打卡解耦原则
- **规则**：客观路线 (`RouteItem`: 名称、描述、测量人、参考步数、`isLocked` 锁定) 与行走打卡履约 (`StepLog`: 行走人、完成圈数、实测步数、耗时、公里数、千卡、打卡时刻) 必须保持**严格解耦**。
- **规则**：锁定状态下的路线禁止删除或误编辑，打卡记录按 `timestamp` 倒序管理。

### 4. 统一家庭成员系统与生理数据精准换算
- **规则**：`Member` 为全局共享的家庭成员库，步量打卡、家务打卡与生活记录同行成员共用同一套数据（模型定义于 `chore_tracker/domain/chore_models.dart`）。
- **规则**：换算距离与千卡时，必须优先使用选定 `Member` 的专属身高 (`heightCm`) 估计步长、专属体重 (`weightKg`) 计算 MET 卡路里；无选定成员时回退到全局 `UserProfile`（`profile` 模块）。
- **规则**：`Member.age` 必须根据 `birthDate` 动态计算，禁止直接持久化固定年龄。

### 5. uHabits 习惯量化展示与缩写规范
- **规则**：开启量化登记的家务，在主页 5 天日期打卡阵列中**绝对不能显示打勾图标 `✓`**，必须统一调用 `NumberFormatter.formatQuantifiableValue` 转换为 `1.2k` / `15k` / `1.5M` 格式呈现。

### 6. 生活记录 (Life Journal) 模板化打卡与视图持久化规范
- **规则**：分类绑定模板（`store_categories.templateKey`）：movie / dining / book / place / shopping / basket / snack / generic，新建走模板画廊，表单按模板动态渲染。
- **规则**：模板专属字段值统一存 `extrasJson`（store_items 与 store_logs 均有），通用列（name/category/rating/imagesJson/address/notes/cost/memo/visitor*）保留，旧数据无 extras 按通用模板渲染。
- **规则**：分类自定义字段存 `store_categories.extraFieldsJson`（`TemplateField` JSON 数组），key 自动生成 `custom_N`，新增/删除/排序在分类编辑弹窗中管理。
- **规则**：打卡履约 `StoreLog` 必须记录分钟级打卡时刻 (`timestamp`)、消费金额 (`cost`) 与同行成员 (`visitorIdsJson` / `visitorNamesJson`)。
- **规则**：支持 **Card ↔ 紧凑列表双视图模式**，且通过 `app_settings['preferredViewMode']` 持久化（回退旧字段）。
- **规则**：侧边栏 Drawer 支持分类创建、重命名（含模板绑定与自定义字段）与安全删除（删除后记录自动归入「通用分类」）。
- **规则**：选图必须复制进应用缓存目录（`CacheManager.copyToCache`）后再存路径，禁止直接存相册原路径；图片质量读 `app_settings['image_quality']`。

### 7. 应用图标与透明化规则
- **规则**：图标必须保持 100% 透明 Alpha 通道 (`RGBA`) DIB ICO 格式，严禁带有白色或浅色背景余边。

### 8. 版本号与发布同步规范
- **规则**：应用版本号以 [pubspec.yaml](file:///g:/MiniProject2026/steplife/pubspec.yaml) 的 `version` 为准（当前 `1.5.0+20260819`）；Android 通过 `flutter.versionCode / flutter.versionName` 自动继承，无需手动同步。
- **规则**：发布新版本时须同步更新 [lib/features/about/presentation/about_screen.dart](file:///g:/MiniProject2026/steplife/lib/features/about/presentation/about_screen.dart) 的版本号文案与 [assets/walkthrough.md](file:///g:/MiniProject2026/steplife/assets/walkthrough.md) 的更新日志，保持三处一致。

---

## 🏗️ 项目整体架构蓝图 (Architecture Blueprint)

```
steplife/
├── android/                        # Android 原生配置与 Manifest (应用名: 步履生活)
├── ios/                            # iOS 原生 Runner
├── windows/                        # Windows 原生桌面 Runner
│   └── runner/resources/
│       └── app_icon.ico            # 32位 DIB 标准桌面透明图标
├── linux/  macos/  web/            # 其余平台壳工程
├── assets/                         # 静态资源目录
│   ├── icon/app_icon.png           # 高清无白边透明应用图标
│   ├── walkthrough.md              # 内嵌系统架构与更新日志文档
│   └── screenshots/                # README 应用截图资源
├── lib/
│   ├── main.dart                   # 应用入口：FFI 初始化、MultiProvider、PageView + 底部导航 (4个Tab: 路线/家务/生活/成员（关于已合并进设置中心）)
│   ├── core/
│   │   ├── db/
│   │   │   └── database_service.dart # SQLite 单例 DAO (Schema v9, 非破坏迁移+app_settings)
│   │   ├── settings/
│   │   │   ├── settings_provider.dart # 全局设置状态 (app_settings 读写)
│   │   │   ├── settings_screen.dart   # 设置中心 UI (主题/模板/缓存/WebDAV/关于)
│   │   │   └── settings_button.dart   # 右上角齿轮入口
│   │   ├── cache/
│   │   │   ├── cache_manager.dart     # 图片复制/统计/按上限清理
│   │   │   └── image_migrator.dart    # 旧相册路径惰性迁移
│   │   ├── network/
│   │   │   └── tmdb_client.dart       # TMDB 搜索/详情/海报下载
│   │   ├── sync/
│   │   │   ├── webdav_service.dart    # 轻量 WebDAV 客户端 (MKCOL/PUT/GET/PROPFIND)
│   │   │   └── sync_service.dart      # 备份/恢复编排
│   │   ├── theme/
│   │   │   └── app_theme.dart      # 深色+浅色主题 (对话框保持深色毛玻璃)
│   │   └── utils/
│   │       ├── fitness_calculator.dart # 步长推算、公里转换与 MET 千卡计算
│   │       └── number_formatter.dart   # uHabits 1.2k / 1.5M 数值智能缩写算法
│   └── features/
│       ├── step_tracker/           # 路线资产与步量打卡模块 (StepTrackerScreen)
│       ├── chore_tracker/          # 家务习惯与打卡模块 (主屏/详情热力图/成员弹窗)
│       ├── store_journal/          # 生活记录 (模板化打卡, 8 大模板+自定义字段（movie/dining/book/place/shopping/basket/snack/generic）, TMDB 导入)
      │       ├── domain/life_templates.dart  # 模板注册表 + 字段模型 + 分类匹配
      │       └── presentation/template_gallery.dart / template_field_widget.dart # 模板画廊与动态表单
│       ├── profile/                # 全局生理档案与统一成员管理 (MemberScreen/ProfileDialog)
│       └── about/                  # 关于程序与版本 Changelog (v1.4.16 Build 20260818)
├── test/                           # 单元与组件自动化测试
│   ├── fitness_calculator_test.dart
│   ├── number_formatter_test.dart
│   └── widget_test.dart
├── pubspec.yaml                    # 依赖与资源声明、版本号 (1.4.16+20260818)
├── ARCHITECTURE.md                 # 完整架构说明文档
└── update_rules.md                 # 【本文件】AI 协作规范与更新注意事项
```

---

## 🧪 常用验证与测试命令

在每次完成修改后，AI 助手**必须依次运行**以下校验命令，确保 0 错误后方可交付：

1. **静态代码分析**：
   ```powershell
   flutter analyze
   ```
2. **单元与组件自动化测试**：
   ```powershell
   flutter test
   ```
3. **Android Release APK 构建**：
   ```powershell
   flutter build apk --release
   ```

---

## 🆕 近期全局注意点（2026-08 起生效，后续迭代持续遵守）

### 9. WebDAV 备份/恢复完整性
- **规则**：新增任何数据库表，必须同步加入 `DatabaseService._syncTables`（备份表清单）与恢复校验，并在 WebDAV「数据概览」文案里体现；图片与 TMDB 海报缓存（cache/tmdb）随备份增量上传/按缺失恢复，恢复后自动重映射路径。
- **规则**：WebDAV 网络异常在 SyncService 统一走 `_friendlyError` 翻译（服务器未启动/跨网段/认证失败/超时/证书），禁止直接暴露原始 SocketException。

### 10. 应用内自动更新链路
- **规则**：更新检查与 APK 下载均支持多源回退（api.github.com → ghproxy.net / gh-proxy.com / ghfast.top / mirror.ghproxy.com），逐个失败才报错。
- **规则**：APK 必须下载到应用 **cache 目录**（getApplicationCacheDirectory），FileProvider 的 `cache-path` 已覆盖；改回 documents 目录会导致「无法打开安装器」（FileProvider 找不到匹配根）。
- **规则**：拉起系统安装器前，Android 8+ 需检查 `canRequestPackageInstalls()`，未授权跳 `ACTION_MANAGE_UNKNOWN_APP_SOURCES` 引导并返回 false 由 UI 提示。
- **规则**：发布新版本 = 提升 pubspec 版本 → 更新 walkthrough.md 版本历史与 README → 本地 release 构建验证 → commit → push → 远端 tag `v1.4.x+YYYYMMDD` 触发 CI 自动构建 4 架构 APK 并发布。

### 11. Android 权限清单
- **规则**：AndroidManifest 已含 INTERNET / 定位 / RECORD_AUDIO / ACTIVITY_RECOGNITION / REQUEST_INSTALL_PACKAGES。新增需要系统权限的功能，先核对清单并同步运行时申请与设置引导。

### 12. 生活模板与菜篮子规范
- **规则**：模板键 8 个（movie/dining/book/place/shopping/basket/snack/generic）；每个模板的图片/备注输入框文案必须专门化（菜篮子=商品图片/备忘，影视=相关图片·剧照/长评，美食=美食图片/特色说明·推荐好菜·备忘）。
- **规则**：菜篮子同一品类支持多品牌（佳农香蕉/辉众香蕉），打卡记录品牌留空=通用；走势图、总表、浏览卡片需展示品牌信息。
- **规则**：餐饮菜单支持份量规格（大份/小份、一两/二两）独立定价；招牌推荐菜/不推荐在浏览卡片小字展示。

### 13. 智能助手（DeepSeek）约束
- **规则**：模型固定 `deepseek-v4-flash`；Key 存 `app_settings`（同 TMDB Key 模式）；入口为家务/生活 AppBar 左上角纯图标（无文字）。
- **规则**：AI 仅返回结构化 JSON 动作；客户端必须做「存在性二次校验」（AI 的 matchedName 需命中本地清单，未命中降级为新建确认）；**一切动作先渲染确认卡片，用户确认后才调用 provider 落库**。
- **规则**：语音用 speech_to_text（Android 系统识别），Windows 桌面退化为文本输入；录音权限需运行时申请。

### 14. 计步测量
- **规则**：计步测量依赖 ACTIVITY_RECOGNITION 权限（Android 10+ 运行时请求）；计步器流需 onError 兜底；测量中状态用 Wrap 布局避免窄屏溢出；「无计步器」文案仅在非 Android 或权限被拒时展示（初始按 Platform 判断，禁止默认 false 误导）。

### 15. 构建与代码环境约定
- **规则**：本环境 `apply_patch` 不可用，文件读写走 Node REPL；Dart `${...}` 在 JS 模板串中写 `\${...}`；JS 字符串替换用 `split(old).join(new)`。
- **规则**：git 需拆成单个已批准前缀命令执行（组合命令会被沙箱拦截）；commit 用 `git commit -F <临时文件>`。
- **规则**：大部分 Dart 文件为 LF 行尾（git 提示 CRLF 警告属正常，勿批量转换行尾）。
