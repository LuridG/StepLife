import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;

/// DeepSeek 对话服务（智能助手）
class DeepSeekService {
  static const String endpoint = 'https://api.deepseek.com/chat/completions';
  static const String model = 'deepseek-v4-flash';

  /// 发送对话请求，返回助手文本（预期为 JSON）
  static Future<String> chat({
    required String apiKey,
    required List<Map<String, String>> messages,
  }) async {
    final resp = await http
        .post(
          Uri.parse(endpoint),
          headers: {
            'Authorization': 'Bearer $apiKey',
            'Content-Type': 'application/json',
          },
          body: jsonEncode({
            'model': model,
            'messages': messages,
            'temperature': 0.2,
            'max_tokens': 2000,
            'response_format': {'type': 'json_object'},
          }),
        )
        .timeout(const Duration(seconds: 30));
    if (resp.statusCode != 200) {
      final body = resp.body;
      String reason = 'HTTP ${resp.statusCode}';
      if (resp.statusCode == 401) reason = 'API Key 无效或未配置';
      if (resp.statusCode == 429) reason = '请求过于频繁，请稍后再试';
      throw HttpException('DeepSeek 请求失败: $reason ${body.length > 120 ? body.substring(0, 120) : body}');
    }
    final json = jsonDecode(resp.body) as Map<String, dynamic>;
    final choices = json['choices'] as List? ?? const [];
    if (choices.isEmpty) throw HttpException('DeepSeek 返回为空');
    final msg = (choices.first as Map)['message'] as Map?;
    final content = msg?['content']?.toString() ?? '';
    if (content.trim().isEmpty) throw HttpException('DeepSeek 返回为空');
    return content;
  }
}
