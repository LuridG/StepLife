> 📌 历史方案文档（2026-07）：原计划中的 `update_rules.md` 与 `ARCHITECTURE.md` 已于 2026-08 重组为 [architecture.md](architecture.md)（红线并入 [AGENTS.md](../AGENTS.md)），文中相关引用仅代表当时计划。

﻿# StepLife 生活模板化 + 设置中心 + 缓存管理 + WebDAV 同步 方案 v2.1

> 版本：v2.1 讨论稿（2026-08-02）
> 实施状态：7 个开放决策点已按推荐确认，Phase 0-7 已完成代码实施并通过 flutter analyze / flutter test（2026-08-02）
> 更新：补充完整「现有用户数据非破坏迁移方案」（备份 / 表级迁移清单 / 回滚 / 对账 / 测试）
> 范围：生活 Tab 模板化（含 TMDB）、主页 UI 改造、设置中心、缓存管理、WebDAV 同步

## 0. 用户诉求汇总

1. 生活 Tab 不再共用一套添加模板，改为"分类绑定基础模板"，例如电影→影视模板、日常小店→餐饮小店模板，开箱即用且各有针对性。
2. 通用/自定义模板支持用户追加字段（文本、图片、数字、下拉等）。
3. 影视模板可选接入 TMDB 自动填充影片信息。
4. 主页新增设置入口（右上角/左上角），把用户可调控选项统一收进设置中心。
5. 缓存上限与调控放进设置中心。
6. 增加 WebDAV 上传同步（备份 + 恢复）。

## 1. 主页 UI 设计

### 1.1 现状

- 5 个 Tab（路线 / 家务 / 生活 / 成员 / 关于）各自持有独立 Scaffold + AppBar + 操作按钮，底部为固定 BottomNavigationBar + PageView。
- 各页顶栏操作差异大（路线页有步量打卡入口、家务页有成员管理、生活页有视图切换和 + 新建），不宜强行统一成全局 AppBar。

### 1.2 设置入口位置：右上角齿轮（推荐）

| 位置 | 优劣 |
| --- | --- |
| 右上角齿轮（推荐） | 符合 Android/iOS 通用惯例；不干扰生活页左侧 Drawer（分类管理）与居中标题；注入各 Tab AppBar 的 actions 首位即可全局可达 |
| 左上角 | 与生活页 Drawer 菜单、居中标题布局冲突；桌面端左上角是窗口控制区 |
| 仅放主页 | 其他 Tab 内想改设置要来回切 Tab，路径长 |

落地方式：

- 封装统一组件 `SettingsButton`（齿轮 IconButton），注入 5 个 Tab 的 AppBar `actions`（放最右侧或最左侧均可，统一即可）。
- 全屏 `SettingsScreen`（Material 惯例，支持返回），不阻塞各 Tab 原有顶栏操作。
- 主页整体结构保持 PageView + BottomNavigationBar 不变，零破坏式接入。

### 1.3 主页视觉与交互

- 沿用现有深色毛玻璃语言：渐变背景 `0xFF090D16 → 0xFF111C38 → 0xFF0F172A`、玻璃卡片 `white 16% + blur`、主色 Emerald `0xFF10B981`、强调 Indigo `0xFF6366F1` / Cyan `0xFF06B6D4`。
- 生活 Tab 顶栏右侧改为 `[⚙ 设置] [视图切换] [+ 新建]`，`+ 新建` 弹出**模板画廊**（见 4.1）。
- 设置中心内提供"生活 Tab 默认视图（卡片/列表）"，迁移现有 `preferredViewMode` 偏好。

## 2. 设置中心（settings_screen.dart）

### 2.1 结构总览

```
设置
├─ 外观与偏好
│   ├─ 主题模式       深色 / 浅色 / 跟随系统（本期至少深色+浅色）
│   ├─ 生活默认视图   卡片 / 紧凑列表（迁移 preferredViewMode）
│   └─ 打卡默认成员   自己 / 上次使用的成员
├─ 模板与分类
│   ├─ TMDB API Key   影视模板搜索用（留空=不启用，完全离线可用）
│   ├─ 分类模板管理   每个分类绑定的模板 + 自定义字段增删排序
│   └─ 恢复内置模板   一键重置模板绑定
├─ 数据与同步（WebDAV）
│   ├─ 服务器配置     地址 / 账号 / 密码 / 远程路径前缀 / 允许自签名 TLS
│   ├─ 立即上传 / 立即恢复（从云端拉取）
│   ├─ 自动同步       关闭 / 修改后防抖30s / 每日定时
│   ├─ 冲突策略       以最新 mtime / 以本地 / 以远端
│   └─ 状态           上次同步时间、条目数、图片数、数据库大小
├─ 缓存管理
│   ├─ 当前占用       数据库 + 图片 + TMDB 海报 分类统计
│   ├─ 缓存上限       不限 / 50MB / 100MB / 200MB / 500MB
│   ├─ 图片质量       60 / 75 / 85（影响新选图压缩）
│   └─ 立即清理 / 一键清空
└─ 关于
    ├─ 版本与更新日志
    ├─ TMDB 数据归属说明（"数据来源 TMDB"）
    └─ 开源许可
```

### 2.2 设置存储

- 新表 `app_settings(key TEXT PRIMARY KEY, value TEXT)`，全部设置项以字符串存取（主题、视图、缓存上限、WebDAV 配置、API Key 等）。
- `preferredViewMode` 读取逻辑向后兼容：新读 app_settings，缺省回退旧 `user_profile.preferredViewMode`。
- 设置变更走 `SettingsProvider`（ChangeNotifier），各模块读取最新值。

### 2.3 可迁入设置中心的现有选项盘点

| 现有散落选项 | 当前位置 | 迁入设置中心 |
| --- | --- | --- |
| 生活卡片/列表视图 | 生活页顶栏切换按钮 | 外观与偏好 + 顶栏快捷按钮保留（双向同步） |
| 个人身体参数（身高/体重/步长） | 成员页/个人档案 | 保留原位置（高频编辑），设置中心只放只读摘要或快捷跳转 |
| 家务量化开关 | 新建家务弹窗 | 属于条目属性，不进全局设置 |

## 3. 生活模板系统

### 3.1 核心机制

- 每个分类绑定一个模板（`templateKey`），模板定义"新建项目表单"与"打卡表单"的字段集合。
- 模板内建字段 + 分类自定义字段一起动态渲染；模板专属值统一存 `extrasJson`。
- 通用字段（名称、评分、图片、时间、成员、消费）仍用现有列，统计与视图逻辑不受影响。

### 3.2 内置模板（6 个）

| 模板 key | 名称 | 默认绑定分类 | 新建项目字段要点 | 打卡字段要点 |
| --- | --- | --- | --- | --- |
| movie | 影视观影 | 电影 / 电视剧 / 动漫 / 纪录片 | 片名、类型、年份、导演/主演、片长、观看平台、评分、海报、种草理由 | 消费、观影渠道、是否二刷、观后感 |
| dining | 餐饮探店 | 餐厅 / 小吃 / 咖啡甜品 / 日常小店 | 店名、品类、地址商圈、人均参考、招牌推荐菜、评分、照片、排队提示 | 消费、点了哪些菜、口味/环境评价、推荐指数 |
| book | 书籍阅读 | 小说 / 社科 / 工具书 | 书名、作者、出版社、页数、状态、评分、封面、简介 | 阅读进度、阅读时长、摘抄感想 |
| place | 景点游玩 | 景点 / 公园 / 展馆 / 演出 | 名称、位置、门票参考、建议时长、交通、最佳季节、评分、照片、攻略 | 消费、游玩时长、亮点项目、感受 |
| shopping | 购物好物 | 百货 / 数码 / 生鲜 / 服饰 | 商品、品类、位置、参考价、购买理由、评分、照片 | 实付金额、购买明细、使用体验 |
| generic | 通用（自定义） | 用户自定义分类兜底 | 名称/评分/图片/位置/备注骨架，用户可自由增删字段 | 消费/成员/心得/时刻 |

### 3.3 字段模型（life_templates.dart，纯 Dart 配置）

```dart
enum TemplateFieldType { text, multiline, number, rating, choice, date, image, images, switch, tags }

class TemplateField {
  final String key;              // 'director' / 'custom_1'
  final String label;            // 显示名
  final TemplateFieldType type;
  final String hint;
  final bool required;
  final List<String>? options;   // choice 类型用
  final String? defaultValue;
}

class LifeTemplate {
  final String key;              // 'movie'
  final String name;             // '影视观影'
  final String iconName;
  final String description;
  final String itemNameLabel;    // '片名'
  final String itemNameHint;
  final List<TemplateField> itemFields;
  final List<TemplateField> checkinFields;
}
```

### 3.4 自定义字段（分类级）

- `store_categories.extraFieldsJson` 存用户追加的字段定义（JSON 数组，元素 = TemplateField）。
- 字段 key 自动生成 `custom_1 / custom_2`，避免中文标签冲突。
- 交互：创建/编辑分类时进入"管理字段"：添加（选类型：文本/多行/数字/单选/日期/图片/图片集/开关/标签）、删除、排序。
- 渲染：模板内建字段在前，自定义字段在后；值写入 `extrasJson`。

### 3.5 TMDB 影视信息接入（可选增强）

- 定位：默认关闭；填 API Key 才启用搜索；不填完全不影响手动录入。
- 流程：片名旁 🔍 搜索 → `GET /3/search/movie?language=zh-CN` → 结果列表 → 选中后拉详情 + credits 自动填充表单。
- 字段映射：中文片名→name；海报→images（下载到本地缓存目录存路径）；导演/主演/简介/片长/类型/年份/tmdbId→extrasJson。
- 失败兜底：离线/限流 → Toast + 手动填写；UI 标注"数据来源 TMDB"。
- 工程：新增 `http` 依赖 + `core/network/tmdb_client.dart`。

## 4. 数据层升级（Schema v8 → v9）

### 4.1 表结构变更

| 表 | 变更 | 说明 |
| --- | --- | --- |
| store_categories | + templateKey TEXT DEFAULT 'generic' | 分类绑定模板 |
| store_categories | + extraFieldsJson TEXT DEFAULT '[]' | 用户自定义字段定义 |
| store_items | + extrasJson TEXT DEFAULT '{}' | 模板专属项目字段值 |
| store_logs | + extrasJson TEXT DEFAULT '{}' | 模板专属打卡字段值 |
| app_settings（新表） | key TEXT PRIMARY KEY, value TEXT | 全局设置 |

### 4.2 迁移原则（非破坏性）

核心红线：**只加不改、只增不删、可回滚、可验证**。升级绝不允许 DROP/重建现有表，不允许改写既有字段值（仅补充默认值或新增列）。

1. **只增列不重建表**：所有结构变更 = `ALTER TABLE ... ADD COLUMN`（带默认值）+ `CREATE TABLE IF NOT EXISTS` 新表，绝不重建、清空或改名现有表。
2. **新增列全部带默认值**：`extrasJson TEXT NOT NULL DEFAULT '{}'`、`templateKey TEXT NOT NULL DEFAULT 'generic'`、`extraFieldsJson TEXT NOT NULL DEFAULT '[]'`，保证旧行读取即为合法值。
3. **旧字段原样保留**：`store_items` 的 name/category/rating/imagesJson/address/notes/createdAt，`store_logs` 的 cost/memo/visitorIdsJson/visitorNamesJson/timestamp 等全部保留，现有读改写逻辑不破坏。
4. **迁移是「复制 + 增量」而非替换**：升级前先整体备份旧库文件；升级失败自动回滚；升级成功后旧库文件仍保留（见 4.6），用户可随时找回。
5. **迁移全程在单个事务内完成**：任一环节失败整体回滚，库仍停留在 v8 可用状态。

### 4.3 升级前备份（自动）

- 首次检测到旧库（`steplife_v8.db` 存在且 `version=8`）时，打开新库**之前**先备份：
  - `steplife_v8.db` → `steplife_v8_backup_<yyyyMMdd_HHmmss>.db`（若存在 `-wal` / `-shm` 一并复制，先执行 `PRAGMA wal_checkpoint(TRUNCATE)` 保证文件完整）。
- 备份保留策略：**保留最近 3 份**，更早的仅清理备份文件，绝不动当前库。
- 备份动作失败 → **拒绝升级**，弹窗提示（宁可停在旧版本，也不冒数据风险）。
- 备份路径与现库同目录（`getDatabasesPath()`），用户可通过系统文件管理找到。

### 4.4 表级迁移清单

| 表 | 结构迁移动作 | 数据修补（事务内） |
| --- | --- | --- |
| store_categories | `ADD COLUMN templateKey TEXT NOT NULL DEFAULT 'generic'`；`ADD COLUMN extraFieldsJson TEXT NOT NULL DEFAULT '[]'` | 按分类名称智能绑定模板（见下方映射） |
| store_items | `ADD COLUMN extrasJson TEXT NOT NULL DEFAULT '{}'` | 无需改写既有行，旧条目按 `{}` 渲染通用模板 |
| store_logs | `ADD COLUMN extrasJson TEXT NOT NULL DEFAULT '{}'` | 无需改写既有行 |
| app_settings（新表） | `CREATE TABLE IF NOT EXISTS app_settings(key TEXT PRIMARY KEY, value TEXT)` | `user_profile.preferredViewMode` 非空时 `INSERT OR IGNORE` 迁入，旧字段保留作回退 |
| members | 不重复迁移，沿用现有 `onOpen` 补丁 `birthDate` 逻辑 | — |

分类名称 → 模板智能绑定（名称含关键词即匹配，不区分大小写）：

| 关键词（含） | templateKey | 兜底 |
| --- | --- | --- |
| 电影 / 影视 / 剧 / 动漫 / 纪录 | movie | — |
| 餐厅 / 小吃 / 咖啡 / 甜品 / 小店 / 奶茶 / 美食 / 餐饮 | dining | — |
| 书 / 阅读 / 小说 / 工具书 | book | — |
| 景点 / 公园 / 展馆 / 演出 / 旅行 / 游玩 | place | — |
| 购物 / 百货 / 数码 / 生鲜 / 服饰 / 好物 | shopping | — |
| 其他全部 | generic | 用户自定义分类兜底 |

> 绑定结果写入 `templateKey` 列，与分类名称解耦：用户之后重命名分类，模板绑定不丢失。

### 4.5 图片路径迁移（惰性，不破坏旧路径）

- 现状：`imagesJson` 直接存相册/系统路径（`image_picker` 返回值），v9 起新选图才复制进应用缓存目录。
- **旧条目一律不动**：升级时绝不改写旧 `imagesJson`。旧条目按原路径只读展示；文件被系统清理后仅该图缺失，其余数据不受影响。
- **后台惰性迁移**：启动后空闲时扫描旧条目图片路径：
  - 文件仍存在 → 复制进 `cache/images/`，逐条更新 `imagesJson` 为新路径（单条失败跳过，不中断）；
  - 文件不存在 → 标记跳过，不报错。
- 幂等可中断：已迁移的条目不再处理；随时可恢复，不阻塞首屏。

### 4.6 回滚与降级

| 场景 | 处理 |
| --- | --- |
| 迁移事务失败 | 自动回滚事务 → 删除半成品 v9 文件 → 从备份恢复 v8 文件 → 弹窗提示，数据停留在升级前可用状态 |
| 新版本运行异常 | 设置中心提供「回滚到上一个备份」：先把当前库另存为备份，再用旧备份重建 |
| 用户手动装回旧版 App | 旧 `steplife_v8.db` 文件保留在原目录不删除，旧版 App 仍能读取升级前数据 |

数据库文件命名决策（新增开放决策点 7）：

- **方案 A（推荐，沿用项目惯例）**：新库 `steplife_v9.db`；旧 `steplife_v8.db` **不删除、不改名**，另生成独立备份副本。装回旧版 App 时旧版仍读自己的 v8.db（升级前数据），天然非破坏；代价是多一份旧库文件，可在设置中心「清理旧版本数据库」手动删除。
- 方案 B：沿用单一 `steplife.db` + version 字段。无文件冗余，但装回旧版时旧版以低版本号打开高版本库会报错，风险更高。

### 4.7 迁移验证与对账

升级事务收尾（仍在事务内）执行：

1. **行数对账**：迁移前记录每张表 `COUNT(*)`，迁移后逐一比对，不一致即抛异常回滚。
2. **新列抽查**：`SELECT COUNT(*) FROM store_items WHERE extrasJson IS NULL OR extrasJson = ''` 应为 0；`store_categories.templateKey` 同理（不允许空值）。
3. **完整性**：`PRAGMA integrity_check` 通过后才提交。
4. **迁移留痕**：写 `app_settings['last_schema_migration'] = 'v8_to_v9:<timestamp>:ok'`，供排查与支持。

### 4.8 迁移自动化测试（并入 Phase 1 验收）

- 用真实 v8 fixture 库（含各类分类、带图/无图条目、多成员打卡记录、preferredViewMode 已设置）执行升级，断言：行数不变、模板绑定符合映射表、extrasJson 默认值正确、偏好已迁入 app_settings 且旧字段仍在。
- 注入失败用例（迁移中途制造 SQL 错误）：断言事务回滚、v9 文件不存在、备份可恢复、库仍为 v8 可用状态。
- 幂等测试：重复执行迁移不产生重复数据与重复备份。
- 同步更新 `update_rules.md` 第 1 条：Schema 升级必须「先备份 → 事务内增量迁移 → 对账 → 留痕」。

### 4.9 兼容性

- address / notes / cost / memo 保留，通用模板继续使用。
- preferredViewMode 读 app_settings，读取时回退旧字段，无感迁移。
- 无 extrasJson 的旧条目按通用模板渲染，统计与视图逻辑不受影响。

## 5. 模板画廊与动态表单（生活 Tab 交互）

- 生活页 `+`：弹出**模板画廊**（6 张卡片：图标 + 名称 + 描述 + 默认绑定分类）→ 选择后进入对应模板动态表单；分类下拉与模板联动（切分类自动带出该分类模板）。
- 动态表单组件抽为 `template_field_widget.dart`（按 TemplateFieldType 渲染对应控件）。
- 打卡弹窗、详情页、列表卡片按模板渲染字段（影视卡片显示导演/年份，餐饮显示招牌菜等）。
- 旧数据兼容：无 extras 字段的条目按通用模板渲染。

## 6. 缓存管理

- 现状问题：图片直接引用相册原路径（`image_picker` 返回 path），相册变动或系统清理会导致图片失效；无缓存占用概念。
- 方案：选图后复制到 `getApplicationSupportDirectory()/cache/images/`（TMDB 海报 → `cache/tmdb/`），数据路径受应用管理。
- 服务：`core/cache/cache_manager.dart`
  - 统计：遍历缓存目录 + DB 文件大小，分类展示。
  - 清理：按 mtime 从旧到新删除，直到降至上限 80%；一键清空。
  - 写入前检查：达到上限阈值时先触发清理再写。
- 上限策略：不限 / 50MB / 100MB / 200MB / 500MB；"不限"只手动清理。
- 图片质量：`pickImage(imageQuality:)` 改为读设置（60 / 75 / 85），旧图不受影响。

## 7. WebDAV 同步

### 7.1 目标与原理

- 依赖：新增 `webdav_client` + `http`（需要网络权限）。
- 原理：SQLite 数据库文件 + 图片目录增量备份到用户自建 WebDAV（坚果云 / Nextcloud / NAS）。
- 远程结构：`<远程前缀>/steplife/db/` + `<远程前缀>/steplife/images/`。

### 7.2 同步内容与增量

| 内容 | 策略 |
| --- | --- |
| steplife_v9.db | 整体覆盖，以 mtime 最新者为准（先复制快照再传，避免写库中拷贝） |
| 图片文件 | 文件粒度增量：比对 大小 + mtime，只传变化的 |
| 删除 | 仅备份用途，远端不做删除镜像（防误删） |

### 7.3 冲突与恢复

- 自动同步：可选"每次修改后（防抖 30s）"或"每日定时"；首发可只做手动同步。
- 冲突策略：默认以最新 mtime 为准；提供"以本地为准 / 以远端为准"。
- 恢复：设置中心"从云端恢复"——下载远端 DB 替换本地 + 按缺失下载图片。

### 7.4 安全与合规

- WebDAV 账号密码 v1 存 `app_settings`（本地 SQLite），UI 标注风险提示；后续可换 `flutter_secure_storage`。
- 默认校验 TLS，提供"允许自签名"开关。
- 平台注意：桌面端直接拷贝 DB；Android/iOS 需走 sqflite 备份 API（先 `getDatabasesPath` 拷贝文件再上传）。

## 8. 实施路线

| Phase | 内容 | 验收 |
| --- | --- | --- |
| 0 | 主页设置入口 + SettingsScreen 骨架 + app_settings 表 + SettingsProvider + 偏好迁移 | 5 个 Tab 均可进设置，视图偏好双向同步；偏好迁移走备份 + 回退逻辑 |
| 1 | Schema v9 升级 + 非破坏迁移（备份 / 对账 / 回滚）+ 分类按名称智能绑定模板 | 迁移单测通过（v8 fixture 行数一致、失败回滚、幂等），旧库零丢失 |
| 2 | life_templates.dart：6 个模板 + 字段模型 | 模板配置单测通过 |
| 3 | 表单动态化：模板画廊、动态字段渲染、自定义字段管理、打卡弹窗改造 | 电影/小店新建与打卡走不同表单 |
| 4 | 缓存管理：CacheManager、选图复制、上限/清理/质量设置 | 缓存统计与清理功能可用 |
| 5 | TMDB 接入：http + tmdb_client + 设置页 Key + 搜索填充 | 填 Key 后影视模板可搜索自动填充 |
| 6 | WebDAV 同步：同步服务 + 配置/同步/恢复 UI | 坚果云手动备份/恢复闭环 |
| 7 | 展示收尾：详情页/卡片模板字段、回归测试、ARCHITECTURE.md 与 update_rules.md 同步 | 全量构建 APK 通过 |

> 建议节奏：先交付 Phase 0-3（主页 UI + 设置中心 + 模板化，用户感知最强），再迭代 Phase 4-6。

## 9. 依赖与工程变更

- 新增依赖：`http`（TMDB / WebDAV 请求）、`webdav_client`（WebDAV 协议）；可选 `flutter_secure_storage`（密码加固，二期）。
- 新增文件：`core/settings/settings_provider.dart`、`core/settings/settings_screen.dart`、`core/cache/cache_manager.dart`、`core/network/tmdb_client.dart`、`features/store_journal/domain/life_templates.dart`、`features/store_journal/presentation/template_gallery.dart`、`template_field_widget.dart`。
- 修改文件：`main.dart`（注册 SettingsProvider）、5 个 Tab Screen（注入 SettingsButton）、`store_journal_screen.dart`（模板画廊 + 动态表单）、`store_detail_screen.dart`（模板字段展示）、`database_service.dart`（Schema v9）。

## 10. 开放决策点

1. 实施范围：Phase 0-3 先发一版，还是 0-7 一次做完？
2. 设置入口：右上角齿轮注入全部 5 个 Tab（推荐），还是仅生活页？
3. 海报存储：下载到本地缓存（推荐，可离线 + 受缓存管理）还是存 URL 直连展示？
4. 浅色主题：本期是否新增（当前仅深色主题）？
5. WebDAV 自动同步：首发只做手动同步，还是直接做修改后防抖自动同步？
6. WebDAV 密码：v1 明文存本地 SQLite（简化）还是直接上 flutter_secure_storage？
7. 数据库文件命名：沿用版本化文件名（steplife_v9.db，保留旧 v8 文件，推荐）还是单一 steplife.db？