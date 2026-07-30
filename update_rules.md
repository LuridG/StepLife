# StepLife (步履家务) - AI 协作规范与架构更新规则 (`update_rules.md`)

本文档放置于项目根目录，旨在为后续 AI 助手或开发者提供完整的**更新注意事项**、**核心规则约束**及**整体架构蓝图**，确保后续迭代不破坏既有业务逻辑与代码约定。

---

## ⚠️ 每次代码更新必须遵守的核心注意事项 (Update Rules)

### 1. 数据库升级规范 (SQLite Schema Versioning)
- 数据库位于 [lib/core/db/database_service.dart](file:///g:/MiniProject2026/steplife/lib/core/db/database_service.dart)。
- **规则**：若修改表结构或新增字段，必须递增数据库版本号（当前版本：`steplife_v5.db` / `version: 5`），并在 `_onUpgrade` 中编写 `ALTER TABLE` 升级兼容逻辑，同时确保 `_onCreate` 新建逻辑一致。

### 2. 桌面端 SQLite FFI 兼容规则
- **规则**：[lib/main.dart](file:///g:/MiniProject2026/steplife/lib/main.dart) 顶部的 `sqfliteFfiInit()` 与 `databaseFactory = databaseFactoryFfi` 判断不可删除！这是 Windows / Linux / macOS 桌面端能正常读写 SQLite 的关键前置初始化。

### 3. 路线资产与行走打卡解耦原则
- **规则**：客观路线 (`RouteItem`: 名称、描述、测量人、测量步数、`isLocked` 锁定) 与行走打卡履约 (`StepLog`: 行走人、完成圈数、实测步数、耗时、公里数、千卡、打卡日期) 必须保持**严格解耦**。
- **锁定防护 (`isLocked`)**：当路线处于 `isLocked == true` 时，禁止删除或编辑该路线资产，除非用户手动解锁。锁定状态在卡片左侧保持美观的常绿路线标志，仅在右侧展示 🔒 / 🔓 开关。

### 4. 统一家庭成员系统与生理数据精准换算
- 成员实体定义位于 [lib/features/chore_tracker/domain/chore_models.dart](file:///g:/MiniProject2026/steplife/lib/features/chore_tracker/domain/chore_models.dart) 的 `Member` 类。
- **规则**：步量打卡与家务打卡共用同一套家庭成员库。打卡换算距离与千卡时，必须优先使用选定 `Member` 的专属身高 (`heightCm`) 估计步长，以及专属体重 (`weightKg`) 计算 MET 卡路里，缺失时才回退到 `ProfileProvider`。

### 5. uHabits 习惯量化格展示与缩写规范
- 数值缩写转换器位于 [lib/core/utils/number_formatter.dart](file:///g:/MiniProject2026/steplife/lib/core/utils/number_formatter.dart)。
- **规则**：开启量化登记的家务（如买菜记账 `元`），在主页 5 天日期打卡阵列中**绝对不能显示打勾图标 `✓`**，必须统一调用 `NumberFormatter.formatQuantifiableValue` 转换为 `1.2k` / `15k` / `1.5M` 格式呈现。

### 6. 应用图标与透明化规则
- 图标资源位于 `assets/icon/app_icon.png` 及 Windows 平台的 `windows/runner/resources/app_icon.ico`。
- **规则**：图标必须保持 100% 透明 Alpha 通道 (`RGBA`) DIB ICO 格式，严禁带有白色或浅色背景余边。

### 7. 资源注册规则
- **规则**：凡是在 `assets/` 目录下新增或修改静态文件（如图片、Markdown 说明文档），必须在 [pubspec.yaml](file:///g:/MiniProject2026/steplife/pubspec.yaml) 的 `assets:` 列表中正确注册。

---

## 🏗️ 项目整体架构蓝图 (Architecture Blueprint)

```
steplife/
├── android/                        # Android 原生配置与 Manifest
├── windows/                        # Windows 原生桌面 Runner
│   └── runner/resources/
│       └── app_icon.ico            # 32位 DIB 标准桌面透明图标
├── assets/                         # 静态资源目录
│   ├── icon/app_icon.png           # 高清无白边透明应用图标
│   └── walkthrough.md              # 内嵌系统架构与更新日志文档
├── lib/
│   ├── main.dart                   # 应用入口、MultiProvider & BottomNavigationBar (3个Tab)
│   ├── core/
│   │   ├── db/
│   │   │   └── database_service.dart # SQLite 单例 DAO (Schema v5)
│   │   ├── theme/
│   │   │   └── app_theme.dart      # 全局深色高颜值主题与样式 Token
│   │   └── utils/
│   │       ├── fitness_calculator.dart # 身高/体重 MET 千卡与步长推算逻辑
│   │       └── number_formatter.dart   # uHabits 1.2k / 1.5M 数值智能缩写算法
│   └── features/
│       ├── step_tracker/           # 路线资产与步量打卡模块
│       │   ├── domain/step_models.dart      # RouteItem & StepLog 模型
│       │   ├── providers/step_provider.dart # 步量状态管理
│       │   └── presentation/step_tracker_screen.dart # 路线列表与打卡界面
│       ├── chore_tracker/          # 家务习惯与打卡模块
│       │   ├── domain/chore_models.dart     # Member, ChoreItem & ChoreLog 模型
│       │   ├── providers/chore_provider.dart # 家务与成员状态管理
│       │   └── presentation/
│       │       ├── chore_tracker_screen.dart # uHabits 风格主页
│       │       ├── chore_detail_screen.dart  # 独立家务热力图与占比统计
│       │       └── member_dialog.dart        # 统一成员生理档案录入/编辑框
│       ├── profile/                # 个人默认体貌参数模块
│       └── about/                  # 关于程序与更新日志模块
│           └── presentation/about_screen.dart # 关于页与版本 Changelog
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
3. **Windows 桌面端编译测试**：
   ```powershell
   flutter build windows --debug
   ```
