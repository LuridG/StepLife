import 'dart:convert';

/// 智能助手动作类型
enum AssistantAction {
  choreLog, // 家务打卡（已有家务项）
  choreNew, // 新建家务项并打卡
  storeCheckin, // 生活记录打卡（项目已存在）
  storeNew, // 新建生活项目（不打卡）
  storeNewCheckin, // 新建生活项目并立即打卡
  ask, // 信息不足，需要追问
  reject, // 无法转换为家务或生活记录
}

/// DeepSeek 解析出的结构化意图
class AssistantIntent {
  final AssistantAction action;
  final Map<String, dynamic> data;

  const AssistantIntent({required this.action, required this.data});

  String get reply => data['reply']?.toString() ?? '';
  String? get name => _str('name');
  String? get title => _str('title');
  String? get choreTitle => _str('choreTitle');
  String? get category => _str('category');
  String? get template => _str('template');
  String? get matchedName => _str('matchedName');
  String? get matchedBrand => _str('matchedBrand');
  String? get date => _str('date');
  String? get memo => _str('memo') ?? _str('notes');
  bool get isNew => _str('match') == 'new';

  String? _str(String key) {
    final v = data[key];
    if (v == null) return null;
    final s = v.toString().trim();
    return s.isEmpty ? null : s;
  }

  List<String> get memberNames {
    final raw = data['members'];
    if (raw is List) return raw.map((e) => e.toString().trim()).where((e) => e.isNotEmpty).toList();
    return const [];
  }

  List<String> get menuSpecs {
    final raw = data['menuSpecs'];
    if (raw is List) return raw.map((e) => e.toString().trim()).where((e) => e.isNotEmpty).toList();
    return const [];
  }

  List<String> get menuNames {
    final raw = data['menuNames'];
    if (raw is List) return raw.map((e) => e.toString().trim()).where((e) => e.isNotEmpty).toList();
    return const [];
  }

  double? get cost => _num('cost');
  double? get rating => _num('rating');
  double? get price => _num('price');
  double? get value => _num('value');
  double? get qty => _num('qty');
  String? get unit => _str('unit');
  String? get brand => _str('brand');
  String? get address => _str('address');

  double? _num(String key) {
    final v = data[key];
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v.trim());
    return null;
  }


  /// 返回动作修正后的副本（确认时依据校验问题自动调整）
  AssistantIntent withAction(AssistantAction a) =>
      AssistantIntent(action: a, data: data);

  /// 返回品牌修正后的副本（菜篮子品牌与本地清单对齐）
  AssistantIntent withBrand(String brand) {
    final m = Map<String, dynamic>.from(data);
    m['brand'] = brand;
    m['matchedBrand'] = brand;
    m['match'] = 'existing';
    return AssistantIntent(action: action, data: m);
  }

  /// 返回名称修正后的副本（名称与本地清单对齐）
  AssistantIntent withName(String name) {
    final m = Map<String, dynamic>.from(data);
    m['name'] = name;
    m['matchedName'] = name;
    m['match'] = 'existing';
    return AssistantIntent(action: action, data: m);
  }

  Map<String, dynamic> get extras {
    final raw = data['extras'];
    if (raw is Map) return Map<String, dynamic>.from(raw);
    return const {};
  }
}

/// 从 DeepSeek 返回文本中提取 JSON 对象（容忍 markdown 代码块包裹）
AssistantIntent parseAssistantIntent(String raw) {
  var text = raw.trim();
  final fence = RegExp(r'```(?:json)?\s*([\s\S]*?)\s*```').firstMatch(text);
  if (fence != null) text = fence.group(1)!.trim();
  final first = text.indexOf('{');
  final last = text.lastIndexOf('}');
  if (first < 0 || last <= first) {
    return const AssistantIntent(
      action: AssistantAction.ask,
      data: {'reply': '我没有理解你说的内容，请再说一次或说得更具体一些。'},
    );
  }
  try {
    final decoded = jsonDecode(text.substring(first, last + 1));
    if (decoded is! Map) {
      return const AssistantIntent(
        action: AssistantAction.ask,
        data: {'reply': '我没有理解你说的内容，请再说一次。'},
      );
    }
    final map = Map<String, dynamic>.from(decoded);
    final actionName = (map['action']?.toString() ?? 'ask').trim();
    final action = _parseAction(actionName);
    return AssistantIntent(action: action, data: map);
  } catch (_) {
    return const AssistantIntent(
      action: AssistantAction.ask,
      data: {'reply': '解析失败，请再说一次或说得更具体一些。'},
    );
  }
}

AssistantAction _parseAction(String name) {
  switch (name) {
    case 'chore_log':
      return AssistantAction.choreLog;
    case 'chore_new':
      return AssistantAction.choreNew;
    case 'store_checkin':
      return AssistantAction.storeCheckin;
    case 'store_new':
      return AssistantAction.storeNew;
    case 'store_new_checkin':
      return AssistantAction.storeNewCheckin;
    case 'reject':
      return AssistantAction.reject;
    default:
      return AssistantAction.ask;
  }
}
