import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:steplife/features/chore_tracker/domain/chore_models.dart';
import 'package:steplife/features/chore_tracker/providers/chore_provider.dart';
import 'package:steplife/features/profile/presentation/member_screen.dart';

/// 成员管理页面守卫测试：默认成员 A/B/C 应正常渲染（不依赖真实数据库）
class _EmptyChoreProvider extends ChoreProvider {
  @override
  Future<void> loadData() async {}

  @override
  List<Member> get members => <Member>[];
}

class _FakeChoreProvider extends ChoreProvider {
  @override
  Future<void> loadData() async {}

  @override
  List<Member> get members => [
        Member(
          id: 1,
          name: '成员A',
          gender: '男',
          heightCm: 175,
          weightKg: 70,
          birthDate: null,
          age: 28,
          colorValue: 0xFF6366F1,
        ),
        Member(
          id: 2,
          name: '成员B',
          gender: '女',
          heightCm: 162,
          weightKg: 52,
          birthDate: null,
          age: 26,
          colorValue: 0xFF10B981,
        ),
        Member(
          id: 3,
          name: '成员C',
          gender: '男',
          heightCm: 150,
          weightKg: 45,
          birthDate: null,
          age: 14,
          colorValue: 0xFFF43F5E,
        ),
      ];
}

void main() {
  testWidgets('成员管理页面展示默认成员 A/B/C', (tester) async {
    await tester.pumpWidget(
      ChangeNotifierProvider<ChoreProvider>.value(
        value: _FakeChoreProvider(),
        child: const MaterialApp(home: MemberScreen()),
      ),
    );
    await tester.pump();

    expect(find.textContaining('成员A'), findsWidgets);
    expect(find.textContaining('成员B'), findsWidgets);
    expect(find.textContaining('成员C'), findsWidgets);
    expect(find.text('全员共 3 人'), findsOneWidget);
  });

  testWidgets('成员管理页面无成员时显示空状态', (tester) async {
    await tester.pumpWidget(
      ChangeNotifierProvider<ChoreProvider>.value(
        value: _EmptyChoreProvider(),
        child: const MaterialApp(home: MemberScreen()),
      ),
    );
    await tester.pump();

    expect(find.text('暂无成员档案记录'), findsOneWidget);
  });
}
