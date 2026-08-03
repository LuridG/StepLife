# StepLife 项目 AI 协作注意事项（每次修改代码前必读）

本文件会被 AI 自动加载并约束所有改动。完整规范与架构详见 [update_rules.md](update_rules.md) 与 [ARCHITECTURE.md](ARCHITECTURE.md)；发布节奏与用户偏好见文末。

## 🔴 红线（违反即破坏用户数据/流程，绝对禁止）
1. **数据库非破坏迁移**：库文件 `steplife_v9.db`（schema version 9）。改表结构必须：升级前备份旧库、单事务内「只增列不重建表」、幂等（`PRAGMA table_info` 探测）、行数对账 + `integrity_check`、迁移留痕；新装与升级双路径一致。
2. **新表/新列必须同步 WebDAV 备份**：凡新增数据库表，必须加入 `database_service._syncTables`（备份表清单）与 WebDAV 恢复逻辑，否则云端备份缺表。
3. **用户数据零丢失**：禁止破坏性更新、禁止随意删除种子/默认数据（成员 A/B/C、默认分类依赖初始化逻辑）；升级必须可逆（旧库备份保留最近 3 份）。
4. **正式签名不可回退**：release 构建签名由 `android/app/build.gradle.kts` 的 key.properties 决定，禁止改为 debug 签名；CI 用 GitHub Secrets 签名并校验指纹。
5. **打卡时间语义**：所有打卡时间精确到分钟（`yyyy-MM-dd HH:mm`），支持补卡/改时；展示一律按时间倒序（新→旧），与插入先后无关。

## 🧭 全局架构要点（改动前先对齐）
- 入口 `lib/main.dart`：`sqfliteFfiInit()` 桌面初始化**不可删**；底部 4 个 Tab（路线/家务/生活/成员），「关于」已合并进设置中心。
- 成员系统：`Member` 全局共享（步量/家务/生活记录共用），`age` 由 `birthDate` 动态计算，禁止存固定年龄；换算用成员身高体重。
- 模板系统：`store_categories.templateKey` 现有 **movie / dining / book / place / shopping / basket / snack / generic** 八种；表单按 `LifeTemplates` 动态渲染，专属字段存 `extrasJson`；每个模板的图片/备注输入框文案必须专门化（菜篮子=商品图片/备忘，影视=剧照/长评等）。
- 菜篮子：品类+品牌双维度（如 佳农香蕉/辉众香蕉），价格记录/走势/总表/月份筛选。
- 图片：选图必须 `CacheManager.copyToCache` 复制进应用缓存目录后再存路径，禁止存相册原路径；质量读 `app_settings['image_quality']`。
- 版本号：`pubspec.yaml` `version: 1.4.x+YYYYMMDD`，构建号用打包日期且必须递增。
- 设置中心：TMDB Key / DeepSeek Key / WebDAV / 缓存上限与质量 / 主题 / 自动更新开关等，均存 `app_settings`（Key 明文）。

## 🔐 Android 权限清单（新增功能前先核对）
`INTERNET`（联网）、`ACCESS_*_LOCATION`（美食定位）、`RECORD_AUDIO`（智能助手语音）、`ACTIVITY_RECOGNITION`（计步测量，Android 10+ 需运行时授权）、`REQUEST_INSTALL_PACKAGES`（自动更新安装）。加新权限记得同步运行时申请与设置引导。

## 📦 自动更新（核心链路，勿破坏）
- 检查/下载均有多源回退：直连 `api.github.com` 失败→ghproxy 镜像；下载直链失败→镜像。
- APK 下载到应用 **cache 目录**（`getApplicationCacheDirectory()`），`file_paths.xml` 的 `cache-path` 已覆盖；勿改回 documents 目录（会导致 FileProvider 找不到路径、安装器拉起失败）。
- 拉起安装器前检查「安装未知应用」授权，未授权先跳系统设置。
- 发布：推远端 tag `v1.4.x+YYYYMMDD` 触发 `.github/workflows/release.yml` 自动构建 4 架构 APK 并发布。

## 🤖 智能助手（DeepSeek）
- 模型 `deepseek-v4-flash`，Key 存 `app_settings`，入口为家务/生活 AppBar 左上角纯图标。
- AI 只返回结构化 JSON 动作；客户端做「名称存在性二次校验」（AI 匹配值必须命中本地清单，否则降级为新建确认）；**所有动作必须经用户确认后才落库**，禁止 AI 输出直接写库。

## 🧪 交付前验证
依次运行且 0 错误：`flutter analyze` → `flutter test`（如涉及）→ release 构建。本仓库中文交互为主，改动保持与现有风格一致。

## 🤝 协作约定（用户偏好）
- 中文沟通；大改动先出方案，用户确认后再实施。
- 常规节奏：改代码→验证→commit→push→升版本→打包→发布（用户会明确下令，不要擅自发布）。
- 本环境 `apply_patch` 不可用，文件读写用 Node REPL；Dart 模板字符串 `${...}` 在 JS 模板串中要写成 `\${...}`；JS 替换一律用 `split(old).join(new)`。
- commit 通过临时文件 `git commit -F`；git 只读/写命令需按已批准前缀执行（组合命令会被沙箱拦截，需拆开单独跑）。
