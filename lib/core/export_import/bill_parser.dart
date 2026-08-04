import 'dart:convert';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart' show MissingPluginException;
import 'package:intl/intl.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import '../../features/assistant/services/deepseek_service.dart';
import 'import_draft.dart';

/// 账单解析结果：一笔消费记录
class BillRecord {
  BillRecord({this.amount, this.time, this.memo});

  final double? amount;
  final DateTime? time;
  final String? memo;
}

/// AI 识别的店铺建议（当账单店铺与当前项目不一致时）
class BillStoreGuess {
  BillStoreGuess({this.name = '', this.category = ''});

  final String name;
  final String category;

  bool get isNotEmpty => name.trim().isNotEmpty;
}

class BillParseResult {
  BillParseResult({this.records = const [], this.storeGuess});

  final List<BillRecord> records;
  final BillStoreGuess? storeGuess;
}

/// 账单智能导入：离线 OCR + DeepSeek 结构化 → 打卡草稿。
class BillOcrUnavailableException implements Exception {
  const BillOcrUnavailableException();

  @override
  String toString() => '当前设备不支持离线 OCR（仅安卓/苹果可用）';
}

class BillParser {
  /// 当前平台是否支持 ML Kit 离线 OCR（仅 Android/iOS）。
  static bool get isOcrSupported =>
      !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  /// 默认敏感词：OCR 账单送 AI 前自动删除其后的数字串（可在设置中心增删）。
  static const List<String> defaultSensitiveKeywords = [
    '交易单号',
    '商户单号',
    '商户号',
    '订单号',
    '流水号',
    '支付单号',
    '参考号',
  ];

  /// 删除文本中的敏感词及其后的数字串，返回清理后的文本与删除处数。
  static ({String text, int removed}) redactSensitive(
    String text,
    List<String> keywords,
  ) {
    var result = text;
    var removed = 0;
    for (final k in keywords) {
      if (k.trim().isEmpty) continue;
      final re = RegExp('${RegExp.escape(k.trim())}(?:[:：]?${r'\s*[A-Za-z0-9\-]{4,40}'})?');
      result = result.replaceAllMapped(re, (m) {
        removed++;
        return '';
      });
    }
    return (text: result, removed: removed);
  }

  /// 用 ML Kit 离线识别图片中的文字（仅 Android/iOS；桌面端抛异常由调用方兜底）。
  static Future<String> ocrImage(String imagePath) async {
    if (!isOcrSupported) {
      throw const BillOcrUnavailableException();
    }
    final recognizer = TextRecognizer(
      script: TextRecognitionScript.chinese,
    );
    try {
      final input = InputImage.fromFilePath(imagePath);
      final result = await recognizer.processImage(input);
      final buffer = StringBuffer();
      for (final block in result.blocks) {
        buffer.writeln(block.text);
      }
      final text = buffer.toString().trim();
      if (text.isEmpty) {
        throw const FormatException('未能从图片中识别出文字，请换一张更清晰的图片');
      }
      return text;
    } on MissingPluginException {
      throw const BillOcrUnavailableException();
    } finally {
      try {
        recognizer.close();
      } catch (_) {
        // 平台不支持时忽略关闭异常
      }
    }
  }

  /// 将 OCR/粘贴文本交给 DeepSeek 整理为结构化记录（只返回 JSON）。
  static Future<BillParseResult> structure({
    required String rawText,
    required String storeName,
    required String category,
    required String apiKey,
  }) async {
    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final instruction = '''
你是生活记账整理助手。下面是用户某次消费的账单文字（OCR 或手动粘贴），请提取其中的每一笔消费记录。
账单可能包含多笔消费（一张截图/一段文字可有多笔），必须逐笔拆分为独立记录、按出现顺序排列，严禁合并、遗漏或凭空捏造。OCR 文字常为分行键值结构（标签与值各占一行，金额也可能在标签之前），请结合上下文把数值对号入座。
只返回 JSON，不输出任何解释。
字段规则：
- records: 数组。每项含 amount(数字，单位元，去掉 ¥ ￥ 等货币符号；金额可能带负号如 -8.00，表示扣款/支出，一律取绝对值)、time(格式 yyyy-MM-dd HH:mm；中文日期如「2026年8月3日 16:16:12」需转换为「2026-08-03 16:16」；账单未写日期按今天 $today 推断，未写具体时间默认 12:00)、memo(该笔消费内容/菜名，如「商品」标签后的名称，没有则省略该字段)。
- storeGuess: 仅当账单中出现与当前店铺「$storeName」不同的店铺名时给出 {"name":"店铺名","category":"建议分类"}，否则省略。
输出格式：{"records":[{"amount":12.5,"time":"$today 12:30","memo":"微信支付-餐饮"},{"amount":8.0,"time":"$today 12:35","memo":"奶茶"}],"storeGuess":{...}}''';
    final content = await DeepSeekService.chat(
      apiKey: apiKey,
      messages: [
        {'role': 'system', 'content': '你是生活记账整理助手，只输出 JSON。'},
        {'role': 'user', 'content': '$instruction\n\n账单文字：\n$rawText'},
      ],
    );
    return parseBillJson(content);
  }

  /// 解析 DeepSeek 返回的 JSON（容忍 markdown 代码块包裹）。
  static BillParseResult parseBillJson(String content) {
    var text = content.trim();
    if (text.startsWith('```')) {
      final first = text.indexOf('\n');
      final last = text.lastIndexOf('```');
      text = text.substring(first + 1, last < 0 ? text.length : last).trim();
    }
    Object? decoded;
    try {
      decoded = jsonDecode(text);
    } catch (e) {
      throw FormatException('AI 返回内容无法解析：$e');
    }
    if (decoded is! Map) {
      throw const FormatException('AI 返回内容不是 JSON 对象');
    }
    final root = Map<String, dynamic>.from(decoded);
    final records = <BillRecord>[];
    final rawRecords = root['records'];
    if (rawRecords is List) {
      for (final r in rawRecords) {
        if (r is! Map) continue;
        final rm = Map<String, dynamic>.from(r);
        final amount = rm['amount'];
        records.add(BillRecord(
          amount: amount is num ? amount.toDouble() : double.tryParse(amount?.toString() ?? ''),
          time: _parseBillTime(rm['time']),
          memo: rm['memo']?.toString(),
        ));
      }
    }
    BillStoreGuess? guess;
    final rawGuess = root['storeGuess'];
    if (rawGuess is Map) {
      final gm = Map<String, dynamic>.from(rawGuess);
      guess = BillStoreGuess(
        name: gm['name']?.toString() ?? '',
        category: gm['category']?.toString() ?? '',
      );
    }
    return BillParseResult(records: records, storeGuess: guess);
  }

  /// 结构化记录 → 归属到指定项目的打卡草稿（L1 纯打卡导入）。
  static ImportDraft toDraft(
    BillParseResult result, {
    required int storeId,
    required String storeName,
    required String category,
  }) {
    final cat = ImportCategoryDraft(name: category);
    cat.strategy = ImportStrategy.merge;
    cat.lockToTarget = storeId != 0;
    final item = ImportItemDraft(name: storeName, category: category);
    item.strategy = ImportStrategy.merge;
    item.targetItemId = storeId == 0 ? null : storeId;
    item.lockToTarget = storeId != 0;
    for (final r in result.records) {
      item.logs.add(ImportLogDraft(
        cost: r.amount,
        timestamp: r.time,
        memo: r.memo,
      ));
    }
    cat.items.add(item);
    return ImportDraft(categories: [cat]);
  }

  static DateTime? _parseBillTime(Object? raw) {
    if (raw == null) return null;
    final s = raw.toString().trim();
    if (s.isEmpty) return null;
    for (final fmt in [
      'yyyy-MM-dd HH:mm:ss',
      'yyyy-MM-dd HH:mm',
      'yyyy年M月d日 HH:mm:ss',
      'yyyy年M月d日 HH:mm',
      'yyyy年M月d日',
    ]) {
      try {
        final dt = DateFormat(fmt).parse(s);
        // 打卡时间统一精确到秒，用于与已有打卡按秒判定同一张卡
        return DateTime(dt.year, dt.month, dt.day, dt.hour, dt.minute, dt.second);
      } catch (_) {}
    }
    final dt = DateTime.tryParse(s);
    if (dt != null) {
      return DateTime(dt.year, dt.month, dt.day, dt.hour, dt.minute, dt.second);
    }
    return null;
  }
}
