# StepLife 生活记录 导入/导出与打卡逻辑 实现现状

> 版本：2026-08 实现说明（对应归档方案 [history/store-import-export-plan.md](history/store-import-export-plan.md)）
> 范围：生活记录（Store Journal）导入 / 导出 / 账单 OCR + AI 导入的当前落地行为，供后续迭代对齐

## 1. 打卡时间语义（核心约定）

- 打卡时间统一按**秒**归一化：格式 `yyyy-MM-dd HH:mm:ss`，入库用 ISO8601（秒级，毫秒清零）。
- 账单 / AI 导入的支付时间必须**保留秒**（AI 提示词强制 `yyyy-MM-dd HH:mm:ss`，解析层 `_parseBillTime` / `_optTime` / `_parseTsLoose` 均归一化到秒）。
- 手动打卡仍按分钟输入（秒 = 00），与秒级导入互不冲突。
- **合并判定**：同一项目（餐厅/影片等）下，**同一秒**视为同一张卡 → 合并增补；否则插入新打卡。
- 展示（打卡履约 / 删除确认 / 导入预览）一律到秒；导出 JSON 时间戳也是秒级。
- 排序仍按时间倒序（新 → 旧），与插入先后无关。

## 2. 入口与层级

| 层级 | 入口 | 解析器 | 行为 |
| --- | --- | --- | --- |
| L1 纯打卡导入 | 项目详情页「导入打卡记录」（JSON 片段） | `StoreImporter.parseLogsOnly` | 锁定当前餐厅，仅追加/合并打卡 |
| L1 账单导入 | 项目详情页「导入账单」（截图 OCR 或粘贴文字 + AI） | `BillParser.structure` → `toDraft` | 同上，AI 结构化后预览确认 |
| L3 模板全量导入 | 顶栏「导入」选标准 JSON | `StoreImporter.parseJson` | 校验 → 预览 → 可新建/合并分类与项目 |
| 导出 | 分类页菜单（单分类）/ 顶栏（全量） | `StoreExporter.buildExportData` | JSON v1，图片字段位预留（本期不导出图） |

## 3. 三套「新建/合并」策略（互不混淆）

1. **分类策略**：详情页导入时分类锁定（`lockToTarget`），禁止新建；全量导入可单独切换新建/合并。
2. **项目（餐厅/影片等）策略**：详情页导入时项目锁定为当前餐厅（按 id 定位，定位失败直接报错，绝不降级新建）；全量导入可切换；新建时重名自动追加 `(导入2)`、`(导入3)`… 后缀防 UNIQUE 冲突。
3. **打卡策略**（`ImportLogDraft.strategy`，默认 `merge`）：
   - `merge`：同秒已有打卡 → 合并增补缺失字段；无同秒 → 自动新建。
   - `create`：强制新建一条（即使同秒已有）。
   - 预览页每条打卡标签显示**实际行为**（`willMerge`：同秒已有才标「合并」，否则标「新建」），点击可切换策略，切换后自动重算；顶部有「全部合并 / 全部新建」批量按钮。

## 4. 落库流程与合并语义

```
解析（JSON 校验 或 OCR+AI）→ ImportDraft（纯内存）
  → 模拟导入预览（勾选/编辑/切策略/补时间）
  → 用户确认
  → vacuumInto 快照备份（保留最近 3 份）
  → 单事务落库（失败回滚）
  → 结果：createdCategories / createdItems / createdLogs / createdMenus / mergedLogs / skippedLogs
```

- **合并增补**（`_mergeIntoLog`）：已有记录缺失才补——cost 为空补金额、memo 为空补心得、visitors/menu/extras 缺则补，不覆盖已有值。
- **缺时间禁止落库**：每条打卡必须至少 `yyyy-MM-dd HH:mm`（建议到秒），确认前校验，缺时间在预览中红字标记。
- 计数按实际行为：真正合并记 `mergedLogs`，插入新记录记 `createdLogs`。

## 5. 账单智能导入（OCR + AI）

- 离线 OCR：`google_mlkit_text_recognition`（中文），仅 Android / iOS（`BillParser.isOcrSupported`）；桌面端自动降级为「粘贴 OCR 文字」。
- **敏感词脱敏**：OCR 文本送 AI 前先按 `app_settings['bill_sensitive_keywords']`（默认交易单号/商户单号/商户号/订单号/流水号/支付单号/参考号）删除「关键词+后续数字串」，再弹窗人工复核，确认后才送 AI；敏感词列表可在设置中心增删。
- AI：`deepseek-v4-flash`，只返回 JSON；提示词要求逐笔拆分、时间 `yyyy-MM-dd HH:mm:ss` 保留秒、金额取绝对值、memo 取账单「商品」内容。
- 红线：AI 输出仅作建议，**必须经模拟导入页用户确认后才落库**。

## 6. 关键代码位置

```
lib/core/export_import/store_exporter.dart        // 导出：单分类/全量 JSON v1（秒级时间，图片位预留）
lib/core/export_import/store_importer.dart        // parseJson / parseLogsOnly / resolve / apply（锁定+防撞名+合并）
lib/core/export_import/import_draft.dart          // ImportDraft / Category / Item / Log（strategy / willMerge / lockToTarget）
lib/core/export_import/import_preview_screen.dart // 模拟导入预览（编辑/策略标签/批量切换/缺时间校验）
lib/core/export_import/bill_parser.dart           // OCR / 敏感词脱敏 / DeepSeek 结构化 / toDraft
lib/features/store_journal/presentation/store_detail_screen.dart // 详情页导入入口与履约展示
```

## 7. 回归要点

- 详情页导入**绝不新建分类/餐厅**；预览若出现「新建分类/项目」即回归错误。
- 同一秒重复导入 → 合并（不产生重复卡）；不同秒 → 新建。
- AI 识别时间必须保留秒；敏感词脱敏后人工复核流程不可跳过。
- 导入前自动备份、单事务回滚不可移除。
