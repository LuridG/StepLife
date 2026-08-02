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
- **规则**：分类绑定模板（`store_categories.templateKey`）：movie / dining / book / place / shopping / generic，新建走模板画廊，表单按模板动态渲染。
- **规则**：模板专属字段值统一存 `extrasJson`（store_items 与 store_logs 均有），通用列（name/category/rating/imagesJson/address/notes/cost/memo/visitor*）保留，旧数据无 extras 按通用模板渲染。
- **规则**：分类自定义字段存 `store_categories.extraFieldsJson`（`TemplateField` JSON 数组），key 自动生成 `custom_N`，新增/删除/排序在分类编辑弹窗中管理。
- **规则**：打卡履约 `StoreLog` 必须记录分钟级打卡时刻 (`timestamp`)、消费金额 (`cost`) 与同行成员 (`visitorIdsJson` / `visitorNamesJson`)。
- **规则**：支持 **Card ↔ 紧凑列表双视图模式**，且通过 `app_settings['preferredViewMode']` 持久化（回退旧字段）。
- **规则**：侧边栏 Drawer 支持分类创建、重命名（含模板绑定与自定义字段）与安全删除（删除后记录自动归入「通用分类」）。
- **规则**：选图必须复制进应用缓存目录（`CacheManager.copyToCache`）后再存路径，禁止直接存相册原路径；图片质量读 `app_settings['image_quality']`。

### 7. 应用图标与透明化规则
- **规则**：图标必须保持 100% 透明 Alpha 通道 (`RGBA`) DIB ICO 格式，严禁带有白色或浅色背景余边。

### 8. 版本号与发布同步规范
- **规则**：应用版本号以 [pubspec.yaml](file:///g:/MiniProject2026/steplife/pubspec.yaml) 的 `version` 为准（当前 `1.3.0+20260730`）；Android 通过 `flutter.versionCode / flutter.versionName` 自动继承，无需手动同步。
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
│   ├── main.dart                   # 应用入口：FFI 初始化、MultiProvider、PageView + 底部导航 (5个Tab: 路线/家务/生活/成员/关于)
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
│       ├── store_journal/          # 生活记录 (模板化打卡, 6 大模板+自定义字段, TMDB 导入)
      │       ├── domain/life_templates.dart  # 模板注册表 + 字段模型 + 分类匹配
      │       └── presentation/template_gallery.dart / template_field_widget.dart # 模板画廊与动态表单
│       ├── profile/                # 全局生理档案与统一成员管理 (MemberScreen/ProfileDialog)
│       └── about/                  # 关于程序与版本 Changelog (v1.3.0 Build 20260730)
├── test/                           # 单元与组件自动化测试
│   ├── fitness_calculator_test.dart
│   ├── number_formatter_test.dart
│   └── widget_test.dart
├── pubspec.yaml                    # 依赖与资源声明、版本号 (1.3.0+20260730)
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