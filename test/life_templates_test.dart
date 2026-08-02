import 'package:flutter_test/flutter_test.dart';
import 'package:steplife/features/store_journal/domain/life_templates.dart';
import 'package:steplife/features/store_journal/domain/store_models.dart';

void main() {
  group('LifeTemplates.matchTemplateKey', () {
    test('关键词映射到对应模板', () {
      expect(LifeTemplates.matchTemplateKey('影视剧集'), 'movie');
      expect(LifeTemplates.matchTemplateKey('电影'), 'movie');
      expect(LifeTemplates.matchTemplateKey('电视剧'), 'movie');
      expect(LifeTemplates.matchTemplateKey('餐饮美食'), 'dining');
      expect(LifeTemplates.matchTemplateKey('日常小店'), 'dining');
      expect(LifeTemplates.matchTemplateKey('咖啡甜品'), 'dining');
      expect(LifeTemplates.matchTemplateKey('书籍阅读'), 'book');
      expect(LifeTemplates.matchTemplateKey('小说'), 'book');
      expect(LifeTemplates.matchTemplateKey('景点场所'), 'place');
      expect(LifeTemplates.matchTemplateKey('演出'), 'place');
      expect(LifeTemplates.matchTemplateKey('购物好物'), 'shopping');
      expect(LifeTemplates.matchTemplateKey('数码'), 'shopping');
    });

    test('未知分类兜底 generic', () {
      expect(LifeTemplates.matchTemplateKey('我的自定义分类'), 'generic');
      expect(LifeTemplates.matchTemplateKey(''), 'generic');
    });
  });

  group('内置模板配置', () {
    test('6 个模板且 key 唯一', () {
      expect(LifeTemplates.all.length, 6);
      final keys = LifeTemplates.all.map((t) => t.key).toSet();
      expect(keys.length, 6);
      expect(LifeTemplates.all.last.key, 'generic');
    });

    test('模板字段 key 在模板内唯一', () {
      for (final tpl in LifeTemplates.all) {
        final keys = [...tpl.itemFields, ...tpl.checkinFields].map((f) => f.key).toList();
        expect(keys.toSet().length, keys.length, reason: '${tpl.key} 存在重复字段 key');
        for (final f in tpl.itemFields) {
          expect(f.label, isNotEmpty);
        }
      }
    });

    test('byKey 未命中回退 generic', () {
      expect(LifeTemplates.byKey('nonexistent').key, 'generic');
      expect(LifeTemplates.byKey('movie').key, 'movie');
    });
  });

  group('TemplateField 序列化', () {
    test('toJson / fromJson 往返一致', () {
      const field = TemplateField(
        key: 'custom_1',
        label: '产地',
        type: TemplateFieldType.choice,
        options: ['国内', '进口'],
        hint: '选择产地',
        required: true,
      );
      final restored = TemplateField.fromJson(field.toJson());
      expect(restored.key, 'custom_1');
      expect(restored.label, '产地');
      expect(restored.type, TemplateFieldType.choice);
      expect(restored.options, ['国内', '进口']);
      expect(restored.required, isTrue);
    });

    test('异常类型回退 text', () {
      final restored = TemplateField.fromJson({'key': 'x', 'label': 'X', 'type': 'unknown'});
      expect(restored.type, TemplateFieldType.text);
    });
  });

  group('模型 extras 序列化与旧数据兼容', () {
    test('StoreItem extras 往返', () {
      final item = StoreItem(
        name: '流浪地球2',
        category: '电影',
        images: const [],
        extras: {'director': '郭帆', 'year': '2023', 'runtime': 173},
      );
      final restored = StoreItem.fromMap(item.toMap());
      expect(restored.extras['director'], '郭帆');
      expect(restored.extras['year'], '2023');
      expect(restored.extras['runtime'], 173);
    });

    test('StoreItem 旧数据无 extrasJson 时默认空', () {
      final legacy = StoreItem.fromMap({
        'id': 1,
        'name': '老条目',
        'category': '餐饮美食',
        'rating': 5.0,
        'imagesJson': '[]',
        'createdAt': DateTime.now().toIso8601String(),
      });
      expect(legacy.extras, isEmpty);
    });

    test('StoreLog extras 往返与旧数据兼容', () {
      final log = StoreLog(
        storeId: 1,
        storeName: '川湘阁',
        cost: 45,
        extras: {'dishes': '毛血旺', 'taste': '惊艳'},
      );
      final restored = StoreLog.fromMap(log.toMap());
      expect(restored.extras['dishes'], '毛血旺');
      expect(restored.extras['taste'], '惊艳');

      final legacy = StoreLog.fromMap({
        'id': 1,
        'storeId': 1,
        'storeName': '旧记录',
        'visitorIdsJson': '[]',
        'visitorNamesJson': '[]',
        'timestamp': DateTime.now().toIso8601String(),
      });
      expect(legacy.extras, isEmpty);
      expect(legacy.visitorNames, ['自己']);
    });

    test('StoreCategory extraFields 往返', () {
      final cat = StoreCategory(
        name: '电影',
        templateKey: 'movie',
        extraFields: const [
          {'key': 'custom_1', 'label': '产地', 'type': 'text'},
        ],
      );
      final restored = StoreCategory.fromMap(cat.toMap());
      expect(restored.templateKey, 'movie');
      expect(restored.extraFields, hasLength(1));
      expect(restored.extraFields.first['label'], '产地');
    });
  });
}
