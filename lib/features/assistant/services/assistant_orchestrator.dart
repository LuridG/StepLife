import '../../store_journal/providers/store_provider.dart';
import '../../chore_tracker/providers/chore_provider.dart';
import '../../chore_tracker/domain/chore_models.dart';
import '../../store_journal/domain/store_models.dart';
import '../domain/assistant_models.dart';
import 'deepseek_service.dart';

/// 智能助手编排：组装上下文 → 调 DeepSeek → 解析/校验 → 确认后执行
class AssistantOrchestrator {
  /// 组装系统提示词（含家庭当前数据，供 AI 精确匹配）
  static String buildSystemPrompt({
    required ChoreProvider chore,
    required StoreProvider store,
  }) {
    final b = StringBuffer();
    b.writeln('你是「步履生活」家庭生活智能助手。用户会用一句话描述一件事，你要把它解析成「家务打卡」或「生活记录」动作。');
    b.writeln('只输出一个 JSON 对象，不要输出任何其他文字。字段如下（用不到的字段不要填）：');
    b.writeln('action（必填）: "chore_log" 家务打卡(已存在) | "chore_new" 新建家务并打卡(不存在) | "store_checkin" 生活记录打卡(项目已存在) | "store_new" 仅新建生活项目 | "store_new_checkin" 新建并立即打卡 | "ask" 信息不足需追问(reply 写自然中文问题) | "reject" 无法转换');
    b.writeln('通用字段: date(yyyy-MM-dd HH:mm, 支持"昨天/今天早上"换算, 默认当前时间), members(参与成员姓名数组, 必须取自下方成员列表, 识别不出填空数组表示默认), memo(备注), cost(消费金额数字)');
    b.writeln('家务字段: choreTitle(家务名), category(家务分类默认"日常家务"), value(数量), unit(单位), quantifiable(是否可量化 bool)');
    b.writeln('生活字段: name(项目名: 店铺/片名/书名/景点/商品/菜篮子品类), category(分类名, 必须取自下方分类列表), template(movie/dining/book/place/shopping/basket/snack/generic), rating(1-5), address(位置/平台), menuNames(餐饮点的菜名数组, 必须取自下方菜单列表), menuSpecs(与菜名一一对应的份量规格数组如 大份/小份/二两, 必须取自菜品规格), extras(模板专属字段对象: 影视 director/genre/status/platform/episodesWatched, 餐饮 taste/ambience/recommend, 菜篮子 unit/price/qty/brand/channel/quality/note, 零食 brand/snackTag/priceTb/priceJd/priceStore/comment, 购物 brand/sku/refPrice, 书籍 author/pages/status)');
    b.writeln('匹配字段: match("existing"=已存在 / "new"=不存在), matchedName(match=existing 时必须给, 且必须与下方列表中的名称一字不差), matchedBrand(菜篮子品牌)');
    b.writeln('【铁律】');
    b.writeln('1. matchedName 必须与提供列表中的现有名称完全一致，不确定一律 match=new。');
    b.writeln('2. 菜篮子先匹配品类(如"香蕉")再匹配品牌(佳农/辉众/散装)，两者都要判断。');
    b.writeln('3. 餐饮"去XX吃了YY"：项目=店铺名，menuNames=菜单里的菜名。');
    b.writeln('4. 名称能匹配现有项目时默认打卡不新建；用户明确说"记一下XX""新建XX"才新建。');
    b.writeln('5. 金额/数量/时间从用户的话里提取，提不到用默认。');
    b.writeln('6. 理解不了就用 ask 并给出自然中文追问。');

    b.writeln('\n[当前家庭数据 - 用于匹配]');
    b.writeln('【成员】');
    if (chore.members.isEmpty) {
      b.writeln('- (无，默认"自己")');
    } else {
      for (final m in chore.members) {
        b.writeln('- ${m.name}');
      }
    }
    b.writeln('【家务项】');
    if (chore.choreItems.isEmpty) {
      b.writeln('- (暂无)');
    } else {
      for (final c in chore.choreItems) {
        final q = c.isQuantifiable ? '，可量化，单位:${c.unit}' : '';
        b.writeln('- ${c.title}（分类:${c.category}$q）');
      }
    }
    b.writeln('【生活分类】');
    for (final c in store.categories) {
      b.writeln('- ${c.name}（模板:${c.templateKey}）');
    }
    b.writeln('【生活项目】');
    if (store.storeItems.isEmpty) {
      b.writeln('- (暂无)');
    } else {
      for (final s in store.storeItems) {
        final extra = s.extras['brand']?.toString();
        final brand = (extra != null && extra.isNotEmpty) ? '，品牌:$extra' : '';
        b.writeln('- ${s.name}（分类:${s.category}，模板:${_templateOf(store, s.category)}$brand）');
      }
    }
    final menuByStore = <String, List<String>>{};
    final storeNameById = <int, String>{};
    for (final s in store.storeItems) {
      if (s.id != null) storeNameById[s.id!] = s.name;
    }
    for (final m in store.menuItems) {
      final sn = storeNameById[m.storeId] ?? '店铺#${m.storeId}';
      final specTxt = m.specs.isEmpty ? '' : '(${m.specs.map((s) => s.name).join('/')})';
        menuByStore.putIfAbsent(sn, () => []).add('${m.name}$specTxt');
    }
    b.writeln('【餐饮菜单】');
    if (menuByStore.isEmpty) {
      b.writeln('- (暂无)');
    } else {
      menuByStore.forEach((sn, items) {
        b.writeln('- $sn: ${items.join(" / ")}');
      });
    }
    final basketBrands = <String, Set<String>>{};
    for (final log in store.storeLogs) {
      final brand = log.extras['brand']?.toString();
      if (brand == null || brand.isEmpty) continue;
      basketBrands.putIfAbsent(log.storeName, () => {}).add(brand);
    }
    b.writeln('【菜篮子已用品牌】');
    if (basketBrands.isEmpty) {
      b.writeln('- (暂无登记品牌，可默认"散装/通用")');
    } else {
      basketBrands.forEach((name, brands) {
        b.writeln('- $name: ${brands.join(" / ")}');
      });
    }
    return b.toString();
  }

  static String _templateOf(StoreProvider store, String categoryName) {
    for (final c in store.categories) {
      if (c.name == categoryName) return c.templateKey;
    }
    return 'generic';
  }

  /// 调 DeepSeek 并解析为意图
  static Future<AssistantIntent> askDeepSeek({
    required String apiKey,
    required String userText,
    required ChoreProvider chore,
    required StoreProvider store,
  }) async {
    final messages = [
      {'role': 'system', 'content': buildSystemPrompt(chore: chore, store: store)},
      {'role': 'user', 'content': userText},
    ];
    final raw = await DeepSeekService.chat(apiKey: apiKey, messages: messages);
    return parseAssistantIntent(raw);
  }

  /// 存在性二次校验：AI 匹配值必须命中本地清单；返回问题文案（null = 通过）
  static String? validateMatch(
    AssistantIntent intent, {
    required ChoreProvider chore,
    required StoreProvider store,
  }) {
    switch (intent.action) {
      case AssistantAction.choreLog:
        final title = intent.choreTitle ?? intent.title;
        if (title == null) return '家务项缺失，请确认';
        if (!chore.choreItems.any((c) => c.title == title)) {
          return '家务「$title」不存在，是否改为新建？';
        }
        return null;
      case AssistantAction.storeCheckin:
      case AssistantAction.storeNewCheckin:
        final name = intent.name ?? intent.matchedName;
        if (name == null || name.isEmpty) return '项目名称缺失，请确认';
        final exists = store.storeItems.any((s) => s.name == name);
        if (intent.isNew && exists) {
          return '「$name」已存在，是否改为直接打卡？';
        }
        if (!intent.isNew && !exists) {
          return '「$name」不存在，是否改为新建？';
        }
        if (!intent.isNew && intent.matchedName != null && intent.matchedName != name) {
          return '「$name」与现有项目名称不完全一致，请确认';
        }
        if (intent.template == 'basket') {
          final b = intent.brand;
          final mb = intent.matchedBrand;
          if (mb != null && mb.isNotEmpty && b != null && b.isNotEmpty && b != mb) {
            return '「$name」已登记品牌「$mb」，确认后将以「$mb」记录';
          }
        }
        return null;
      case AssistantAction.choreNew:
        final title = intent.choreTitle ?? intent.title;
        if (title == null || title.isEmpty) return '家务名缺失，请确认';
        if (chore.choreItems.any((c) => c.title == title)) {
          return '家务「$title」已存在，是否改为直接打卡？';
        }
        return null;
      case AssistantAction.storeNew:
      case AssistantAction.ask:
      case AssistantAction.reject:
        return null;
    }
  }

  /// 确认后执行动作，返回结果文案
  static Future<String> execute(
    AssistantIntent intent, {
    required ChoreProvider chore,
    required StoreProvider store,
    DateTime? now,
  }) async {
    final t = now ?? DateTime.now();
    final date = _parseDate(intent.date, t);

    switch (intent.action) {
      case AssistantAction.ask:
      case AssistantAction.reject:
        return intent.reply.isEmpty ? '已取消' : intent.reply;

      case AssistantAction.choreLog:
      case AssistantAction.choreNew: {
        final title = (intent.choreTitle ?? intent.title ?? '').trim();
        if (title.isEmpty) return '缺少家务名称';
        ChoreItem item = chore.choreItems.firstWhere(
          (c) => c.title == title,
          orElse: () => ChoreItem(
            title: title,
            category: intent.category ?? '日常家务',
            isQuantifiable: intent.data['quantifiable'] == true,
            unit: intent.unit ?? '次',
          ),
        );
        if (intent.action == AssistantAction.choreNew || item.id == null) {
          await chore.addChoreItem(
            title,
            category: intent.category ?? '日常家务',
            isQuantifiable: intent.data['quantifiable'] == true,
            unit: intent.unit ?? '次',
          );
          item = chore.choreItems.firstWhere((c) => c.title == title);
        }
        final members = _resolveMembers(intent, chore);
        await chore.logChore(
          choreItem: item,
          selectedMembers: members,
          memo: intent.memo,
          value: intent.value,
          targetDate: date,
        );
        final who = members.isEmpty ? '自己' : members.map((m) => m.name).join('、');
        final val = intent.value != null ? ' ×${intent.value}${intent.unit ?? ''}' : '';
        return '已打卡家务「${item.title}」$val（$who）';
      }

      case AssistantAction.storeCheckin:
      case AssistantAction.storeNew:
      case AssistantAction.storeNewCheckin: {
        final name = (intent.name ?? intent.matchedName ?? '').trim();
        if (name.isEmpty) return '缺少项目名称';
        final category = _pickCategory(intent, store);
        StoreItem? item;
        for (final s in store.storeItems) {
          if (s.name == name) item = s;
        }
        final needCreate = (intent.action != AssistantAction.storeCheckin) && item == null;
        if (needCreate) {
          await store.addStoreItem(
            name: name,
            category: category,
            rating: intent.rating ?? 5.0,
            images: const [],
            address: intent.address,
            notes: intent.memo,
            extras: intent.extras,
          );
          item = store.storeItems.firstWhere((s) => s.name == name);
        }
        if (intent.action == AssistantAction.storeNew && item != null) {
          return '已新建生活项目「${item.name}」（分类:${item.category}）';
        }
        final itemForLog = item!;
        final visitors = _resolveVisitors(intent, chore);
        final menu = _resolveMenu(intent, store, itemForLog.id);
        final extras = Map<String, dynamic>.from(intent.extras);
        if (intent.menuNames.isNotEmpty) {
          extras['dishes'] = intent.menuNames;
        }
        await store.recordStoreCheckin(
          storeId: itemForLog.id!,
          storeName: itemForLog.name,
          cost: intent.cost,
          visitorIds: visitors.map((m) => m.id!).toList(),
          visitorNames: visitors.map((m) => m.name).toList(),
          memo: intent.memo,
          extras: extras,
          menuItemIds: menu.$1,
          menuNames: menu.$2,
          menuSpecs: menu.$3,
          targetDate: date,
        );
        final costTxt = intent.cost != null ? '，消费 ¥${intent.cost!.toStringAsFixed(2)}' : '';
        final dishTxt = menu.$2.isEmpty ? '' : '，点了 ${menu.$2.join("、")}';
        return '已打卡「${itemForLog.name}」$costTxt$dishTxt';
      }
    }
  }

  static DateTime _parseDate(String? raw, DateTime fallback) {
    if (raw == null || raw.trim().isEmpty) return fallback;
    final dt = DateTime.tryParse(raw.trim());
    return dt ?? fallback;
  }

  static List<Member> _resolveMembers(AssistantIntent intent, ChoreProvider chore) {
    final names = intent.memberNames;
    if (names.isEmpty) {
      for (final m in chore.members) {
        if (m.name == '自己') return [m];
      }
      return chore.members.isEmpty ? const [] : [chore.members.first];
    }
    final result = <Member>[];
    for (final n in names) {
      for (final m in chore.members) {
        if (m.name == n) {
          result.add(m);
          break;
        }
      }
    }
    return result.isEmpty
        ? _resolveMembers(AssistantIntent(action: intent.action, data: const {}), chore)
        : result;
  }

  static List<Member> _resolveVisitors(AssistantIntent intent, ChoreProvider chore) {
    return _resolveMembers(intent, chore);
  }

  static String _pickCategory(AssistantIntent intent, StoreProvider store) {
    final cat = intent.category;
    if (cat != null) {
      for (final c in store.categories) {
        if (c.name == cat) return cat;
      }
    }
    final template = intent.template;
    if (template != null) {
      for (final c in store.categories) {
        if (c.templateKey == template) return c.name;
      }
    }
    if (store.categories.isNotEmpty) return store.categories.first.name;
    return '通用分类';
  }

  static (List<int>, List<String>, List<String>) _resolveMenu(
    AssistantIntent intent,
    StoreProvider store,
    int? storeId,
  ) {
    if (intent.menuNames.isEmpty || storeId == null) return (const [], const [], const []);
    final ids = <int>[];
    final names = <String>[];
    final specs = <String>[];
    final aiSpecs = intent.menuSpecs;
    for (var i = 0; i < intent.menuNames.length; i++) {
      final n = intent.menuNames[i];
      for (final m in store.menuItems) {
        if (m.storeId == storeId && m.name == n) {
          ids.add(m.id!);
          names.add(m.name);
          final spec = i < aiSpecs.length ? aiSpecs[i] : '';
          final specOk = m.specs.any((s) => s.name == spec);
          specs.add(specOk ? spec : '');
          break;
        }
      }
    }
    return (ids, names, specs);
  }
}