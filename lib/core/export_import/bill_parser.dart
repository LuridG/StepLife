import 'dart:convert';
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
class BillParser {
  /// 用 ML Kit 离线识别图片中的文字（仅 Android/iOS；桌面端抛异常由调用方兜底）。
  static Future<String> ocrImage(String imagePath) async {
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
    } finally {
      recognizer.close();
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
你是生活记账整理助手。下面是用户某次消费的账单文字（OCR 或手动粘贴），请提取每一笔消费记录。
只返回 JSON，不输出任何解释。
字段规则：
- records: 数组，每项含 amount(数字，单位元)、time(格式 yyyy-MM-dd HH:mm，账单未写日期时按今天 $today 推断)、memo(账单中的消费内容/菜名，没有则省略该字段)。
- storeGuess: 仅当账单中出现与当前店铺「$storeName」不同的店铺名时给出 {"name":"店铺名","category":"建议分类"}，否则省略。
输出格式：{"records":[{"amount":12.5,"time":"$today 12:30","memo":"微信支付-餐饮"}],"storeGuess":{...}}''';
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
    final item = ImportItemDraft(name: storeName, category: category);
    item.strategy = ImportStrategy.merge;
    item.targetItemId = storeId == 0 ? null : storeId;
    for (final r in result.records) {
      item.logs.add(ImportLogDraft(
        cost: r.amount,
        timestamp: r.time ?? DateTime.now(),
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
    try {
      return DateFormat('yyyy-MM-dd HH:mm').parse(s);
    } catch (_) {}
    return DateTime.tryParse(s);
  }
}
