# StepLife (步履生活) - AI 协作规范与架构更新规则 (`update_rules.md`)

本文档放置于项目根目录，旨在为后续 AI 助手或开发者提供完整的**更新注意事项**、**核心规则约束**及**整体架构蓝图**，确保后续迭代不破坏既有业务逻辑与代码约定。

---

## ⚠️ 每次代码更新必须遵守的核心注意事项 (Update Rules)

### 1. 数据库升级规范 (SQLite Schema Versioning)
- 数据库位于 [lib/core/db/database_service.dart](file:///g:/MiniProject2026/steplife/lib/core/db/database_service.dart)。
- **规则**：若修改表结构或新增字段，必须递增数据库版本号（当前版本：`steplife_v7.db` / `version: 7`），并在 `_onUpgrade` 中编写 `ALTER TABLE` 或 `CREATE TABLE IF NOT EXISTS` 兼容逻辑，同时确保 `_onCreate` 新建逻辑一致。

### 2. 桌面端 SQLite FFI 兼容规则
- **规则**：[lib/main.dart](file:///g:/MiniProject2026/steplife/lib/main.dart) 顶部的 `sqfliteFfiInit()` 与 `databaseFactory = databaseFactoryFfi` 判断不可删除！这是 Windows / Linux / macOS 桌面端能正常读写 SQLite 的关键前置初始化。

### 3. 路线资产与行走打卡解耦原则
- **规则**：客观路线 (`RouteItem`: 名称、描述、测量人、测量步数、`isLocked` 锁定) 与行走打卡履约 (`StepLog`: 行走人、完成圈数、实测步数、耗时、公里数、千卡、打卡日期) 必须保持**严格解耦**。

### 4. 统一家庭成员系统与生理数据精准换算
- **规则**：步量打卡与家务打卡共用同一套家庭成员库 (`Member`)。打卡换算距离与千卡时，必须优先使用选定 `Member` 的专属身高 (`heightCm`) 估计步长，以及专属体重 (`weightKg`) 计算 MET 卡路里。

### 5. uHabits 习惯量化格展示与缩写规范
- **规则**：开启量化登记的家务，在主页 5 天日期打卡阵列中**绝对不能显示打勾图标 `✓`**，必须统一调用 `NumberFormatter.formatQuantifiableValue` 转换为 `1.2k` / `15k` / `1.5M` 格式呈现。

### 6. 生活记录 (Life Journal) 通用打卡与视图持久化规范
- **规则**：支持影视、图书、餐饮、景点与场所通用打卡。支持 1-5 星级 Rate 评分、至多 3 张照片 (存储于 `imagesJson`)。支持 **Card ↔ 紧凑列表双视图模式** 且通过 SQLite 持久化记忆上次选择。侧边栏 Drawer 支持分类创建、重命名与安全删除。

### 7. 应用图标与透明化规则
- **规则**：图标必须保持 100% 透明 Alpha 通道 (`RGBA`) DIB ICO 格式，严禁带有白色或浅色背景余边。

---

## 🏗️ 项目整体架构蓝图 (Architecture Blueprint)

```
steplife/
├── android/                        # Android 原生配置与 Manifest (应用名: 步履生活)
├── windows/                        # Windows 原生桌面 Runner
│   └── runner/resources/
│       └── app_icon.ico            # 32位 DIB 标准桌面透明图标
├── assets/                         # 静态资源目录
│   ├── icon/app_icon.png           # 高清无白边透明应用图标
│   └── walkthrough.md              # 内嵌系统架构与更新日志文档
├── lib/
│   ├── main.dart                   # 应用入口、MultiProvider & BottomNavigationBar (4个Tab)
│   ├── core/
│   │   ├── db/
│   │   │   └── database_service.dart # SQLite 单例 DAO (Schema v7)
│   │   ├── theme/
│   │   │   └── app_theme.dart      # 全局深色高颜值主题与样式 Token
│   │   └── utils/
│   │       ├── fitness_calculator.dart # 身高/体重 MET 千卡与步长推算逻辑
│   │       └── number_formatter.dart   # uHabits 1.2k / 1.5M 数值智能缩写算法
│   └── features/
│       ├── step_tracker/           # 路线资产与步量打卡模块
│       ├── chore_tracker/          # 家务习惯与打卡模块
│       ├── store_journal/          # 生活记录 (探店/影视/图书/景点/Card与列表视图)
│       └── about/                  # 关于程序与版本 Changelog (v1.1.0 Build 2)
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
