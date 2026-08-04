import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:steplife/core/export_import/bill_parser.dart';
import 'package:steplife/core/export_import/import_draft.dart';
import 'package:steplife/core/export_import/store_importer.dart';

void main() {
  group('StoreImporter.parseJson', () {
    test('合法导出 JSON → 草稿结构正确', () {
      final content = jsonEncode({
        'schemaVersion': 1,
        'exportType': 'full',
        'categories': [
          {
            'id': 1,
            'name': '餐厅',
            'iconName': 'storefront',
            'templateKey': 'dining',
            'extraFieldsJson': '[]',
            'items': [
              {
                'id': 101,
                'name': '老街小馆',
                'category': '餐厅',
                'rating': 4.5,
                'images': <String>[],
                'extrasJson': '{}',
                'createdAt': '2026-06-01 10:00',
              },
            ],
          },
        ],
        'logs': [
          {
            'id': 9001,
            'storeId': 101,
            'cost': 128.5,
            'visitorNamesJson': '["我"]',
            'memo': '不错',
            'extrasJson': '{}',
            'menuNamesJson': '["红烧肉"]',
            'menuSpecsJson': '["大份"]',
            'timestamp': '2026-07-28 12:30',
          },
        ],
        'menuItems': [
          {
            'id': 501,
            'storeId': 101,
            'name': '红烧肉',
            'price': 68.0,
            'specs': '[]',
            'rating': 1,
            'sortOrder': 0,
          },
        ],
      });
      final draft = StoreImporter.parseJson(content);
      expect(draft.categories, hasLength(1));
      expect(draft.totalItems, 1);
      expect(draft.totalLogs, 1);
      final item = draft.categories.first.items.single;
      expect(item.logs.single.cost, 128.5);
      expect(item.logs.single.timestamp, DateTime(2026, 7, 28, 12, 30));
      expect(item.logs.single.menuNames, ['红烧肉']);
      expect(item.menuItems, hasLength(1));
      expect(item.menuItems.single.price, 68.0);
    });

    test('未知 schemaVersion → FormatException', () {
      expect(
        () => StoreImporter.parseJson('{"schemaVersion": 99, "categories": []}'),
        throwsFormatException,
      );
    });

    test('logs 引用不存在的项目 → FormatException', () {
      final content = jsonEncode({
        'schemaVersion': 1,
        'categories': [
          {'name': '餐厅', 'items': [
            {'id': 1, 'name': 'A'},
          ]},
        ],
        'logs': [
          {'storeId': 999, 'timestamp': '2026-01-01 10:00'},
        ],
      });
      expect(() => StoreImporter.parseJson(content), throwsFormatException);
    });

    test('非法时间 → FormatException', () {
      final content = jsonEncode({
        'schemaVersion': 1,
        'categories': [
          {'name': '餐厅', 'items': [
            {'id': 1, 'name': 'A', 'createdAt': 'not-a-time'},
          ]},
        ],
      });
      expect(() => StoreImporter.parseJson(content), throwsFormatException);
    });

    test('空 categories → FormatException', () {
      expect(
        () => StoreImporter.parseJson('{"schemaVersion": 1, "categories": []}'),
        throwsFormatException,
      );
    });
  });

  group('StoreImporter.parseLogsOnly', () {
    test('纯打卡 JSON → 归属到已有项目（L1）', () {
      final draft = StoreImporter.parseLogsOnly(
        '{"logs": [{"cost": 12.5, "timestamp": "2026-08-01 09:00", "memo": "早餐"}]}',
        targetStoreId: 7,
        targetStoreName: '早点铺',
        targetCategory: '餐饮美食',
      );
      final item = draft.categories.single.items.single;
      expect(item.strategy, ImportStrategy.merge);
      expect(item.targetItemId, 7);
      expect(item.logs.single.memo, '早餐');
      expect(item.logs.single.timestamp, DateTime(2026, 8, 1, 9, 0));
    });
  });

  group('BillParser.parseBillJson', () {
    test('解析 AI 返回的记录与店铺猜测', () {
      final result = BillParser.parseBillJson(
        '{"records":[{"amount":12.5,"time":"2026-07-28 12:30","memo":"牛肉面"}],'
        '"storeGuess":{"name":"兰州拉面","category":"餐饮美食"}}',
      );
      expect(result.records, hasLength(1));
      expect(result.records.single.amount, 12.5);
      expect(result.records.single.memo, '牛肉面');
      expect(result.records.single.time, DateTime(2026, 7, 28, 12, 30));
      expect(result.storeGuess?.name, '兰州拉面');
    });

    test('容忍 markdown 代码块包裹', () {
      final result = BillParser.parseBillJson('```json\n{"records":[{"amount":3.5}]}\n```');
      expect(result.records.single.amount, 3.5);
    });

    test('缺失日期回退为 null', () {
      final result = BillParser.parseBillJson('{"records":[{"amount":3.5}]}');
      expect(result.records.single.time, isNull);
    });

    test('识别带负号的金额字符串（如 -8.00）', () {
      final result = BillParser.parseBillJson('{"records":[{"amount":"-8.00","time":"2026-08-03 16:16","memo":"糖灶"}]}');
      expect(result.records.single.amount, -8.0);
      expect(result.records.single.memo, '糖灶');
    });

    test('解析中文日期时间格式', () {
      final result = BillParser.parseBillJson('{"records":[{"amount":8.0,"time":"2026年8月3日 16:16:12"}]}');
      expect(result.records.single.time, DateTime(2026, 8, 3, 16, 16));
    });

    test('redactSensitive 删除默认敏感词及其后数字串', () {
      final r = BillParser.redactSensitive(
        '交易单号 4200000120240803\n商户单号：123456789012345\n糖灶 -8.00',
        BillParser.defaultSensitiveKeywords,
      );
      expect(r.removed, 2);
      expect(r.text.contains('交易单号'), isFalse);
      expect(r.text.contains('商户单号'), isFalse);
      expect(r.text.contains('糖灶'), isTrue);
    });

    test('redactSensitive 支持自定义敏感词', () {
      final r = BillParser.redactSensitive('会员卡号：88888888 消费 20 元', ['会员卡号']);
      expect(r.removed, 1);
      expect(r.text.contains('88888888'), isFalse);
    });
  });
}
