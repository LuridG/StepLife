<p align="center">
  <img src="assets/icon/app_icon.png" width="120" height="120" alt="StepLife App Icon" />
</p>

<h1 align="center">StepLife · 步履生活</h1>

<p align="center">
  <b>涵盖路线步量换算、uHabits 风格家务习惯与生活记录 (探店/影视/图书) 的全能跨平台助手</b>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Flutter-3.27+-02569B?logo=flutter" alt="Flutter" />
  <img src="https://img.shields.io/badge/Dart-3.6+-0175C2?logo=dart" alt="Dart" />
  <img src="https://img.shields.io/badge/Platform-Android%20%7C%20Windows-green" alt="Platform" />
  <img src="https://img.shields.io/badge/Version-v1.1.0-emerald" alt="Version" />
  <img src="https://img.shields.io/badge/License-MIT-blue.svg" alt="License" />
</p>

---
## 纯Ai生成
本人非码农专业，本程序根据本人需求高度量身定制（
如果你也有类似的个人记录需求可以参考。
纯AI纯AI，解决问题的能力几乎 = 0 

## 🌟 核心功能亮点 (Features)

### 🏃 1. 客观路线资产与步量打卡 (Step Tracker)
- **客观路线资产拆分 (`RouteItem`)**：将路线固定属性（名称、描述、测量人、测量步数、`isLocked` 锁定）与具体打卡履约日志（`StepLog`）严格解耦。
- **锁定防误触防护**：支持对重要路线进行一键锁定，锁定状态下防止误删或误改。
- **一键 `⚡ 记一次`**：根据路线参考步数快速倍增打卡，自动精准换算实际里程 (`km`) 与卡路里消耗 (`kcal`)。

### 🏠 2. uHabits 风格家务习惯追踪 (Chore Tracker)
- **5 天日期近况矩阵**：主页直观展示近 5 天打卡状况，符合大拇指舒适触控区间 (`38x38dp`)。
- **量化打卡智能格式化 (`1.2k`)**：开启量化属性的家务（如买菜记账 `元`），打卡格取消 `✓` 勾选，自动换算展示如 `1.2k` / `15k` / `1.5M` 等智能缩写。
- **单项独立热力图与饼图 (`ChoreDetailScreen`)**：点击任意家务可生成专属的年度 Calendar Heatmap 热力图与成员贡献占比饼图。

### 🛍️ 3. 生活记录 (探店 / 影视 / 阅读 / 景点打卡)
- **通用生活打卡表单**：涵盖电影、电视剧、书籍、美食餐馆、景点场所等多维生活项目打卡。
- **1.0 ~ 5.0 亮金星级 Rating 评分**：支持在表单中自由点选星级评分，列表直观星级呈现。
- **照片画廊 (至多 3 张)**：集成 `image_picker` 选择器，支持上传至多 3 张剧照/海报/店铺实拍照片预览。
- **Card 模式 ↔ 紧凑列表模式**：提供 3D 玻璃网格卡片与单行紧凑列表双视图切换，**上次视图选择自动在数据库持久化记忆**，重启应用完美还原。
- **可收缩分类侧边栏 (Drawer)**：支持自定义分类创建、重命名与安全平滑删除（删除后记录自动归类到“通用未分类”）。

### 👥 4. 统一家庭成员系统 (Unified Member System)
- `Member` 实体融合了姓名、性别、身高 (cm)、体重 (kg)、年龄与自定义步长。
- 步量 Tab 和家务 Tab 共享同一套家庭成员档案库。
- 步量打卡时自动联动选定成员的专属身高与体重，实现**多成员差异化精准里程与 MET 卡路里换算**。

---

## 🛠️ 技术栈与架构设计 (Tech Stack)

- **核心框架**: Flutter (Dart) Material 3 & Google Fonts (`Outfit`)
- **状态管理**: Provider (`ProfileProvider`, `StepProvider`, `ChoreProvider`, `StoreProvider`)
- **本地持久化**: SQLite (`sqflite` / `sqflite_common_ffi` Schema v7)
- **UI 风格**: Modern Frosted Glassmorphism (毛玻璃模糊 + 霓虹暗夜色彩系统)
- **图像选择**: `image_picker`

---

## 🚀 快速启动与构建指南 (Getting Started)

### 环境要求
- Flutter SDK `>= 3.27.0`
- Dart SDK `>= 3.6.0`

### 1. 克隆仓库与安装依赖
```bash
git clone https://github.com/your-username/steplife.git
cd steplife
flutter pub get
```

### 2. 本地运行调试
- **Windows 桌面端运行**：
  ```bash
  flutter run -d windows
  ```
- **Android 设备运行**：
  ```bash
  flutter run -d <android-device-id>
  ```

### 3. 构建发布包 (Build Releases)
- **构建 Android Release APK**：
  ```bash
  flutter build apk --release
  ```
  *产物路径：`build/app/outputs/flutter-apk/app-release.apk`*

- **构建 Windows Release 桌面程序**：
  ```bash
  flutter build windows --release
  ```
  *产物路径：`build/windows/x64/runner/Release/`*

---

## 📄 AI 协作规范与更新规则

项目根目录下附带有 [update_rules.md](file:///g:/MiniProject2026/steplife/update_rules.md) 说明文档，包含详细的数据库 Upgrade 升版规则、桌面 FFI 适配规则、解耦与成员换算规则，方便任何 AI 助手无缝接续维护。

---

## 📝 开源协议 (License)

本项目采用 [MIT License](LICENSE) 协议开源。
