import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../../core/settings/settings_button.dart';
import '../domain/step_models.dart';
import '../providers/step_provider.dart';
import '../utils/step_counter_service.dart';
import '../../chore_tracker/providers/chore_provider.dart';
import '../../chore_tracker/presentation/member_dialog.dart';
import '../../profile/providers/profile_provider.dart';
import '../../../core/utils/fitness_calculator.dart';
import '../../../core/theme/app_theme.dart';

/// 一次计步测量结算结果：实际总步数 × 倍数 → 单程步数
class _MeasureResult {
  final int steps;
  final double multiplier;
  final int computed;
  const _MeasureResult(this.steps, this.multiplier, this.computed);
}

/// 倍数输入格式化器：只允许 0-9 与一个小数点后一位（如 1.5 / 1.8 / 2）
class _DecimalOneFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final t = newValue.text;
    if (RegExp(r'^\d{0,3}(\.\d{0,1})?$').hasMatch(t)) return newValue;
    return oldValue;
  }
}

class StepTrackerScreen extends StatefulWidget {
  const StepTrackerScreen({super.key});

  @override
  State<StepTrackerScreen> createState() => _StepTrackerScreenState();
}

class _StepTrackerScreenState extends State<StepTrackerScreen>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  void _showAddMemberDialog() {
    showDialog(context: context, builder: (ctx) => const MemberDialog());
  }

  void _showAddRouteAssetDialog() {
    final nameController = TextEditingController();
    final refStepsController = TextEditingController(text: '2500');
    final descController = TextEditingController();

    final members = context.read<ChoreProvider>().members;
    String selectedMeasurer = members.isNotEmpty ? members.first.name : '自己';
    String measureMode = 'manual'; // manual 手动登记 | sensor 计步测量
    _MeasureResult? sensorResult;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) {
          Future<void> doSave() async {
            final messenger = ScaffoldMessenger.of(context);
            final navigator = Navigator.of(ctx);
            final name = nameController.text.trim();
            if (name.isEmpty) {
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(const SnackBar(content: Text('路线名称不能为空')));
              return;
            }
            final stepProvider = context.read<StepProvider>();
            int? routeId;
            int initSteps;
            double initMult;
            if (measureMode == 'sensor') {
              if (sensorResult == null) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('请先完成一次计步测量（结束并结算）')),
                );
                return;
              }
              initSteps = sensorResult!.steps;
              initMult = sensorResult!.multiplier;
              routeId = await stepProvider.addRoute(
                name,
                refSteps: sensorResult!.computed,
                measuredBy: selectedMeasurer,
                description: descController.text.trim(),
              );
            } else {
              initSteps = int.tryParse(refStepsController.text) ?? 2000;
              initMult = 1.0;
              routeId = await stepProvider.addRoute(
                name,
                refSteps: initSteps,
                measuredBy: selectedMeasurer,
                description: descController.text.trim(),
              );
            }
            // 无论哪种方式都写入首条测量记录，保证平均值语义完整
            if (routeId != null) {
              await stepProvider.addMeasurement(
                routeId: routeId,
                steps: initSteps,
                multiplier: initMult,
                measuredBy: selectedMeasurer,
              );
            }
            nameController.dispose();
            refStepsController.dispose();
            descController.dispose();
            navigator.pop();
            messenger.showSnackBar(
              SnackBar(
                content: Text('已成功建立路线资产: $name'),
                backgroundColor: const Color(0xFF10B981),
              ),
            );
          }

          return AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            title: const Row(
              children: [
                Icon(Icons.map, color: Color(0xFF10B981)),
                SizedBox(width: 8),
                Text('新建客观路线资产'),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: nameController,
                    decoration: const InputDecoration(
                      labelText: '1. 路线名称 (必填)',
                      hintText: '例: 小区公园慢跑圈 / 下班通勤',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: descController,
                    decoration: const InputDecoration(
                      labelText: '2. 路线描述 / 起点终点 (可选)',
                      hintText: '例: 起点南门大门，终点东门公园环线',
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        '3. 测量人(谁测量的此路线):',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      InkWell(
                        onTap: () {
                          Navigator.of(ctx).pop();
                          _showAddMemberDialog();
                        },
                        child: const Text(
                          '+ 新增成员档案',
                          style: TextStyle(
                            color: Color(0xFF10B981),
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  DropdownButtonFormField<String>(
                    initialValue: selectedMeasurer,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      const DropdownMenuItem(value: '自己', child: Text('自己')),
                      ...members.map(
                        (m) => DropdownMenuItem(
                          value: m.name,
                          child: Text(
                            '${m.name} (${m.heightCm.toInt()}cm/${m.weightKg.toInt()}kg)',
                          ),
                        ),
                      ),
                    ],
                    onChanged: (val) {
                      if (val != null) {
                        setModalState(() => selectedMeasurer = val);
                      }
                    },
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    '4. 测量方式',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 6),
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(
                        value: 'manual',
                        icon: Icon(Icons.edit_note, size: 16),
                        label: Text('手动登记'),
                      ),
                      ButtonSegment(
                        value: 'sensor',
                        icon: Icon(Icons.directions_walk, size: 16),
                        label: Text('计步测量'),
                      ),
                    ],
                    selected: {measureMode},
                    showSelectedIcon: false,
                    style: SegmentedButton.styleFrom(
                      backgroundColor: Colors.white.withAlpha(8),
                      selectedBackgroundColor: const Color(
                        0xFF10B981,
                      ).withAlpha(60),
                      selectedForegroundColor: Colors.white,
                      side: BorderSide(color: Colors.white.withAlpha(25)),
                    ),
                    onSelectionChanged: (s) => setModalState(() {
                      measureMode = s.first;
                      sensorResult = null;
                    }),
                  ),
                  const SizedBox(height: 10),
                  if (measureMode == 'manual')
                    TextField(
                      controller: refStepsController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: '4. 单程步数 (手动登记)',
                        hintText: '例: 2500 步（将作为一条测量记录）',
                      ),
                    )
                  else
                    _MeasureSection(
                      onResult: (r) {
                        if (mounted) setModalState(() => sensorResult = r);
                      },
                    ),
                  if (measureMode == 'sensor' && sensorResult != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      '单程步数: ${sensorResult!.computed} 步（保存后写入第一条测量记录）',
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF10B981),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () {
                  nameController.dispose();
                  refStepsController.dispose();
                  descController.dispose();
                  Navigator.of(ctx).pop();
                },
                child: const Text('取消'),
              ),
              ElevatedButton(
                onPressed: doSave,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF10B981),
                  foregroundColor: Colors.white,
                ),
                child: const Text('保存路线资产'),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showEditRouteAssetDialog(RouteItem route) {
    if (route.isLocked) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('路线【${route.name}】处于锁定保护状态，请先解除锁定后再编辑'),
          backgroundColor: Colors.amber[900],
        ),
      );
      return;
    }

    final nameController = TextEditingController(text: route.name);
    final descController = TextEditingController(text: route.description ?? '');

    final members = context.read<ChoreProvider>().members;
    String selectedMeasurer = route.measuredBy;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) {
          final measurements = context.read<StepProvider>().measurementsOf(
            route.id!,
          );
          final avg = measurements.isEmpty
              ? route.refSteps
              : (measurements
                            .map((m) => m.computedSteps)
                            .reduce((a, b) => a + b) /
                        measurements.length)
                    .round();

          return AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            title: Text('编辑路线资产: ${route.name}'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: nameController,
                    decoration: const InputDecoration(labelText: '路线名称'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: descController,
                    decoration: const InputDecoration(labelText: '路线描述 / 起点终点'),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    '测量人:',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  DropdownButtonFormField<String>(
                    initialValue: selectedMeasurer,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      const DropdownMenuItem(value: '自己', child: Text('自己')),
                      ...members.map(
                        (m) => DropdownMenuItem(
                          value: m.name,
                          child: Text(
                            '${m.name} (${m.heightCm.toInt()}cm/${m.weightKg.toInt()}kg)',
                          ),
                        ),
                      ),
                    ],
                    onChanged: (val) {
                      if (val != null) {
                        setModalState(() => selectedMeasurer = val);
                      }
                    },
                  ),
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFF10B981).withAlpha(20),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: const Color(0xFF10B981).withAlpha(60),
                      ),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.straighten,
                          color: Color(0xFF10B981),
                          size: 18,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '平均单程步数: $avg 步 · $measurements.length 次测量',
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF10B981),
                            ),
                          ),
                        ),
                        TextButton(
                          onPressed: () {
                            Navigator.of(ctx).pop();
                            _showRouteMeasurementsDialog(route);
                          },
                          child: const Text(
                            '管理测量记录',
                            style: TextStyle(fontSize: 12),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    '单程步数由多次测量记录的平均值决定，在「测量记录」中新增/删除测量会自动重算。',
                    style: TextStyle(fontSize: 11, color: Colors.white54),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () {
                  nameController.dispose();
                  descController.dispose();
                  Navigator.of(ctx).pop();
                },
                child: const Text('取消'),
              ),
              ElevatedButton(
                onPressed: () {
                  final name = nameController.text.trim();
                  if (name.isEmpty) {
                    ScaffoldMessenger.of(
                      context,
                    ).showSnackBar(const SnackBar(content: Text('路线名称不能为空')));
                    return;
                  }
                  final updatedRoute = route.copyWith(
                    name: name,
                    description: descController.text.trim(),
                    measuredBy: selectedMeasurer,
                  );
                  context.read<StepProvider>().updateRoute(updatedRoute);
                  nameController.dispose();
                  descController.dispose();
                  Navigator.of(ctx).pop();
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('已更新路线: $name'),
                      backgroundColor: const Color(0xFF10B981),
                    ),
                  );
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF10B981),
                  foregroundColor: Colors.white,
                ),
                child: const Text('保存修改'),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showRecordLogDialog({RouteItem? preselectedRoute}) {
    final routes = context.read<StepProvider>().routes;
    if (routes.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请先新建一条客观路线资产')));
      _showAddRouteAssetDialog();
      return;
    }

    RouteItem selectedRoute = preselectedRoute ?? routes.first;
    final timesController = TextEditingController(text: '1');
    final stepsController = TextEditingController(
      text: selectedRoute.refSteps.toString(),
    );
    final durationController = TextEditingController(text: '30');

    final choreProvider = context.read<ChoreProvider>();
    final members = choreProvider.members;
    String selectedWalker = members.isNotEmpty ? members.first.name : '自己';
    DateTime selectedDateTime = DateTime.now();

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) {
          void updateSuggestedSteps() {
            final times = int.tryParse(timesController.text) ?? 1;
            stepsController.text = (selectedRoute.refSteps * times).toString();
          }

          final walkerMember = choreProvider.getMemberByName(selectedWalker);

          return AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            title: const Row(
              children: [
                Icon(Icons.directions_walk, color: Color(0xFF10B981)),
                SizedBox(width: 8),
                Text('路线行走打卡'),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '选择客观路线:',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  DropdownButtonFormField<RouteItem>(
                    initialValue: selectedRoute,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                    ),
                    items: routes
                        .map(
                          (r) => DropdownMenuItem(
                            value: r,
                            child: Text('${r.name} (${r.refSteps}步)'),
                          ),
                        )
                        .toList(),
                    onChanged: (val) {
                      if (val != null) {
                        setModalState(() {
                          selectedRoute = val;
                          updateSuggestedSteps();
                        });
                      }
                    },
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: timesController,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: '完成圈数/次数',
                            suffixText: '次',
                          ),
                          onChanged: (_) => updateSuggestedSteps(),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: stepsController,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: '实测步数',
                            suffixText: '步',
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: durationController,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: '实际耗时',
                            suffixText: '分钟',
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          initialValue: selectedWalker,
                          decoration: const InputDecoration(labelText: '行走人'),
                          items: [
                            const DropdownMenuItem(
                              value: '自己',
                              child: Text('自己'),
                            ),
                            ...members.map(
                              (m) => DropdownMenuItem(
                                value: m.name,
                                child: Text(m.name),
                              ),
                            ),
                          ],
                          onChanged: (val) {
                            if (val != null) {
                              setModalState(() => selectedWalker = val);
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                  if (walkerMember != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8.0),
                      child: Text(
                        '💡 将采用【${walkerMember.name}】的生理数据 (${walkerMember.heightCm.toInt()}cm / ${walkerMember.weightKg.toInt()}kg) 计算真实里程与千卡',
                        style: const TextStyle(
                          fontSize: 11,
                          color: Color(0xFF10B981),
                        ),
                      ),
                    ),
                  const SizedBox(height: 12),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(
                      Icons.access_time_filled,
                      color: Color(0xFF10B981),
                    ),
                    title: Text(
                      '打卡时刻: ${DateFormat('yyyy-MM-dd HH:mm').format(selectedDateTime)}',
                    ),
                    subtitle: const Text(
                      '支持精确到分钟的时间登记',
                      style: TextStyle(fontSize: 11, color: Colors.white54),
                    ),
                    trailing: TextButton(
                      child: const Text('更改时刻'),
                      onPressed: () async {
                        final pickedDate = await showDatePicker(
                          context: ctx,
                          initialDate: selectedDateTime,
                          firstDate: DateTime(2020),
                          lastDate: DateTime(2030),
                        );
                        if (pickedDate != null) {
                          if (!ctx.mounted) return;
                          final pickedTime = await showTimePicker(
                            context: ctx,
                            initialTime: TimeOfDay.fromDateTime(
                              selectedDateTime,
                            ),
                          );
                          if (pickedTime != null) {
                            setModalState(() {
                              selectedDateTime = DateTime(
                                pickedDate.year,
                                pickedDate.month,
                                pickedDate.day,
                                pickedTime.hour,
                                pickedTime.minute,
                              );
                            });
                          }
                        }
                      },
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () {
                  timesController.dispose();
                  stepsController.dispose();
                  durationController.dispose();
                  Navigator.of(ctx).pop();
                },
                child: const Text('取消'),
              ),
              ElevatedButton(
                onPressed: () {
                  final times = int.tryParse(timesController.text) ?? 1;
                  final steps =
                      int.tryParse(stepsController.text) ??
                      selectedRoute.refSteps;
                  final duration = int.tryParse(durationController.text) ?? 30;

                  final fallbackProfile = context
                      .read<ProfileProvider>()
                      .profile;

                  context.read<StepProvider>().recordStepLog(
                    routeId: selectedRoute.id,
                    routeName: selectedRoute.name,
                    walkerName: selectedWalker,
                    timesCount: times,
                    steps: steps,
                    durationMinutes: duration,
                    targetDate: selectedDateTime,
                    walkerMember: walkerMember,
                    fallbackProfile: fallbackProfile,
                  );

                  timesController.dispose();
                  stepsController.dispose();
                  durationController.dispose();
                  Navigator.of(ctx).pop();

                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('路线【${selectedRoute.name}】打卡成功！'),
                      backgroundColor: const Color(0xFF10B981),
                    ),
                  );
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF10B981),
                  foregroundColor: Colors.white,
                ),
                child: const Text('提交打卡'),
              ),
            ],
          );
        },
      ),
    );
  }

  void _confirmDeleteRoute(RouteItem route) {
    if (route.isLocked) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('路线【${route.name}】处于锁定保护状态，请先解除锁定后再删除'),
          backgroundColor: Colors.amber[900],
        ),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('确认删除路线: ${route.name}?'),
        content: const Text('删除后该路线资产将从列表中移除。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () {
              context.read<StepProvider>().deleteRoute(route.id!);
              Navigator.of(ctx).pop();
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(SnackBar(content: Text('已删除路线: ${route.name}')));
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            child: const Text('确认删除', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  /// 路线测量记录管理弹窗：平均步数 + 记录列表 + 手动登记 / 计步测量 / 删除
  Future<void> _showRouteMeasurementsDialog(RouteItem route) async {
    final members = context.read<ChoreProvider>().members;
    String selectedMeasurer = members.isNotEmpty ? members.first.name : '自己';

    await showDialog<void>(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (ctx, setModalState) {
          bool showSensor = false;
          // 通过函数读取，避免分析器将「读取先于回调内写入」误判为恒 false
          bool sensorMode() => showSensor;

          Future<void> addManual() async {
            final controller = TextEditingController();
            final stepProvider = context.read<StepProvider>();
            final confirmed = await showDialog<bool>(
              context: ctx,
              builder: (sub) => AlertDialog(
                title: const Text('手动登记单程步数'),
                content: TextField(
                  controller: controller,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: '单程步数',
                    hintText: '例如: 2500（自己数的数据）',
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(sub).pop(false),
                    child: const Text('取消'),
                  ),
                  ElevatedButton(
                    onPressed: () => Navigator.of(sub).pop(true),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF10B981),
                      foregroundColor: Colors.white,
                    ),
                    child: const Text('登记'),
                  ),
                ],
              ),
            );
            final steps = int.tryParse(controller.text.trim());
            if (confirmed == true && steps != null && steps > 0) {
              await stepProvider.addMeasurement(
                routeId: route.id!,
                steps: steps,
                multiplier: 1.0,
                measuredBy: selectedMeasurer,
              );
              if (mounted) setModalState(() {});
            }
            controller.dispose();
          }

          final ms = context.read<StepProvider>().measurementsOf(route.id!);
          final avg = ms.isEmpty
              ? route.refSteps
              : (ms.map((m) => m.computedSteps).reduce((a, b) => a + b) /
                        ms.length)
                    .round();

          return AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            title: Text('测量记录 · ${route.name}'),
            content: SizedBox(
              width: double.maxFinite,
              child: sensorMode()
                  ? _MeasureSection(
                      onResult: (r) {
                        if (r != null) {
                          context.read<StepProvider>().addMeasurement(
                            routeId: route.id!,
                            steps: r.steps,
                            multiplier: r.multiplier,
                            measuredBy: selectedMeasurer,
                          );
                          Navigator.of(dialogCtx).pop();
                        } else {
                          setModalState(() => showSensor = false);
                        }
                      },
                    )
                  : Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                '平均单程步数: $avg 步（$ms.length 次测量）',
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF10B981),
                                ),
                              ),
                            ),
                            IconButton(
                              constraints: const BoxConstraints(),
                              padding: const EdgeInsets.all(4),
                              icon: const Icon(
                                Icons.add,
                                color: Color(0xFF10B981),
                                size: 20,
                              ),
                              tooltip: '手动登记',
                              onPressed: addManual,
                            ),
                            IconButton(
                              constraints: const BoxConstraints(),
                              padding: const EdgeInsets.all(4),
                              icon: const Icon(
                                Icons.directions_walk,
                                color: Colors.amber,
                                size: 20,
                              ),
                              tooltip: '计步测量',
                              onPressed: () =>
                                  setModalState(() => showSensor = true),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        if (ms.isEmpty)
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 10),
                            child: Text(
                              '暂无测量记录',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.white38,
                              ),
                            ),
                          )
                        else
                          Flexible(
                            child: ListView.builder(
                              shrinkWrap: true,
                              itemCount: ms.length,
                              itemBuilder: (bctx, index) {
                                final m = ms[index];
                                return Padding(
                                  padding: const EdgeInsets.only(bottom: 6),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 8,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.white.withAlpha(8),
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(
                                        color: Colors.white.withAlpha(15),
                                      ),
                                    ),
                                    child: Row(
                                      children: [
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                '${m.createdAt.year}-${m.createdAt.month.toString().padLeft(2, '0')}-${m.createdAt.day.toString().padLeft(2, '0')} ${m.createdAt.hour.toString().padLeft(2, '0')}:${m.createdAt.minute.toString().padLeft(2, '0')} · ${m.measuredBy}',
                                                style: const TextStyle(
                                                  fontSize: 11,
                                                  color: Colors.white54,
                                                ),
                                              ),
                                              const SizedBox(height: 2),
                                              Text(
                                                '${m.steps} 步 × ${m.multiplier.toStringAsFixed(1)} 倍 → ${m.computedSteps} 步',
                                                style: const TextStyle(
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        IconButton(
                                          constraints: const BoxConstraints(),
                                          padding: const EdgeInsets.all(4),
                                          icon: const Icon(
                                            Icons.delete_outline,
                                            color: Colors.redAccent,
                                            size: 17,
                                          ),
                                          tooltip: '删除该次测量',
                                          onPressed: () async {
                                            await context
                                                .read<StepProvider>()
                                                .deleteMeasurement(m.id!);
                                            if (mounted) setModalState(() {});
                                          },
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                      ],
                    ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogCtx).pop(),
                child: const Text('关闭'),
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final stepProvider = context.watch<StepProvider>();
    final choreProvider = context.watch<ChoreProvider>();
    final profile = context.watch<ProfileProvider>().profile;

    return Scaffold(
      appBar: AppBar(
        title: const Text('路线资产与步量打卡'),
        actions: [
          const SettingsButton(),
          IconButton(
            icon: const Icon(Icons.add_location_alt_outlined),
            tooltip: '新建客观路线资产',
            onPressed: _showAddRouteAssetDialog,
          ),
        ],
      ),
      body: SafeArea(
        child: Stack(
          children: [
            // 深光暗夜多重渐变背景
            Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Color(0xFF090D16),
                    Color(0xFF111C38),
                    Color(0xFF0F172A),
                  ],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
            ),
            SingleChildScrollView(
              padding: const EdgeInsets.symmetric(
                horizontal: 16.0,
                vertical: 14.0,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 2. 客观路线资产库 (纵向列表)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        '客观路线资产库 (列表)',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      TextButton.icon(
                        onPressed: _showAddRouteAssetDialog,
                        icon: const Icon(Icons.add, size: 16),
                        label: const Text('新建路线'),
                        style: TextButton.styleFrom(
                          foregroundColor: const Color(0xFF10B981),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),

                  stepProvider.routes.isEmpty
                      ? _buildEmptyRouteCard()
                      : ListView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: stepProvider.routes.length,
                          itemBuilder: (context, index) {
                            final route = stepProvider.routes[index];
                            final stats = stepProvider.getRouteStats(
                              route.name,
                            );

                            final measurerMember = choreProvider
                                .getMemberByName(route.measuredBy);
                            final double mHeight =
                                measurerMember?.heightCm ?? profile.heightCm;
                            final String mGender =
                                measurerMember?.gender ?? profile.gender;
                            final double? mCustomStride =
                                measurerMember?.customStrideCm ??
                                profile.customStrideCm;

                            final mStrideCm =
                                mCustomStride ??
                                FitnessCalculator.estimateStrideLength(
                                  heightCm: mHeight,
                                  gender: mGender,
                                );

                            final calculatedKm =
                                FitnessCalculator.stepsToKilometers(
                                  route.refSteps,
                                  mStrideCm,
                                );

                            return Padding(
                              padding: const EdgeInsets.only(bottom: 14.0),
                              child: _buildGlassCard(
                                child: Padding(
                                  padding: const EdgeInsets.all(16.0),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      // 路线名称 & 管理按钮
                                      Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.spaceBetween,
                                        children: [
                                          Expanded(
                                            child: Row(
                                              children: [
                                                Container(
                                                  padding: const EdgeInsets.all(
                                                    8,
                                                  ),
                                                  decoration: BoxDecoration(
                                                    color: const Color(
                                                      0xFF10B981,
                                                    ).withAlpha(40),
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          12,
                                                        ),
                                                    border: Border.all(
                                                      color: const Color(
                                                        0xFF10B981,
                                                      ).withAlpha(80),
                                                    ),
                                                  ),
                                                  child: const Icon(
                                                    Icons.directions_walk,
                                                    color: Color(0xFF10B981),
                                                    size: 18,
                                                  ),
                                                ),
                                                const SizedBox(width: 10),
                                                Flexible(
                                                  child: Text(
                                                    route.name,
                                                    style: const TextStyle(
                                                      fontSize: 16,
                                                      fontWeight:
                                                          FontWeight.bold,
                                                      color: Colors.white,
                                                    ),
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              IconButton(
                                                constraints:
                                                    const BoxConstraints(),
                                                padding: const EdgeInsets.all(
                                                  6,
                                                ),
                                                icon: Icon(
                                                  Icons.edit_outlined,
                                                  color: route.isLocked
                                                      ? Colors.white24
                                                      : Colors.lightBlueAccent,
                                                  size: 18,
                                                ),
                                                tooltip: '编辑路线',
                                                onPressed: () =>
                                                    _showEditRouteAssetDialog(
                                                      route,
                                                    ),
                                              ),
                                              IconButton(
                                                constraints:
                                                    const BoxConstraints(),
                                                padding: const EdgeInsets.all(
                                                  6,
                                                ),
                                                icon: Icon(
                                                  route.isLocked
                                                      ? Icons.lock
                                                      : Icons.lock_open,
                                                  color: route.isLocked
                                                      ? Colors.amber
                                                      : Colors.white54,
                                                  size: 18,
                                                ),
                                                tooltip: route.isLocked
                                                    ? '点击解锁路线'
                                                    : '点击锁定保护路线',
                                                onPressed: () => stepProvider
                                                    .toggleLockRoute(route.id!),
                                              ),
                                              IconButton(
                                                constraints:
                                                    const BoxConstraints(),
                                                padding: const EdgeInsets.all(
                                                  6,
                                                ),
                                                icon: Icon(
                                                  Icons.delete_outline,
                                                  color: route.isLocked
                                                      ? Colors.white24
                                                      : Colors.redAccent,
                                                  size: 18,
                                                ),
                                                tooltip: '删除路线',
                                                onPressed: () =>
                                                    _confirmDeleteRoute(route),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 8),

                                      if (route.description != null &&
                                          route.description!.isNotEmpty)
                                        Padding(
                                          padding: const EdgeInsets.only(
                                            bottom: 10.0,
                                          ),
                                          child: Text(
                                            '路线描述: ${route.description}',
                                            style: const TextStyle(
                                              fontSize: 12,
                                              color: Colors.white70,
                                              fontStyle: FontStyle.italic,
                                            ),
                                          ),
                                        ),

                                      // 依次排布：测量人 | 测量步数 | 自动换算距离
                                      Container(
                                        padding: const EdgeInsets.all(10),
                                        decoration: BoxDecoration(
                                          color: Colors.black.withAlpha(30),
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                          border: Border.all(
                                            color: Colors.white.withAlpha(15),
                                          ),
                                        ),
                                        child: Column(
                                          children: [
                                            Row(
                                              mainAxisAlignment:
                                                  MainAxisAlignment.spaceAround,
                                              children: [
                                                _buildDetailField(
                                                  '测量人',
                                                  route.measuredBy,
                                                  const Color(0xFF818CF8),
                                                ),
                                                _buildDetailField(
                                                  '平均单程步数',
                                                  '${route.refSteps} 步',
                                                  const Color(0xFF60A5FA),
                                                ),
                                                _buildDetailField(
                                                  '自动换算距离',
                                                  '${calculatedKm.toStringAsFixed(2)} km',
                                                  const Color(0xFF34D399),
                                                ),
                                              ],
                                            ),
                                            const SizedBox(height: 4),
                                            Row(
                                              mainAxisAlignment:
                                                  MainAxisAlignment
                                                      .spaceBetween,
                                              children: [
                                                TextButton.icon(
                                                  onPressed: () =>
                                                      _showRouteMeasurementsDialog(
                                                        route,
                                                      ),
                                                  icon: const Icon(
                                                    Icons.straighten,
                                                    size: 14,
                                                    color: Color(0xFF34D399),
                                                  ),
                                                  label: Text(
                                                    '测量记录 (${stepProvider.measurementCountOf(route.id!)} 次)',
                                                    style: const TextStyle(
                                                      fontSize: 11,
                                                      color: Color(0xFF34D399),
                                                    ),
                                                  ),
                                                  style: TextButton.styleFrom(
                                                    padding:
                                                        const EdgeInsets.symmetric(
                                                          horizontal: 8,
                                                        ),
                                                    minimumSize: const Size(
                                                      0,
                                                      32,
                                                    ),
                                                    tapTargetSize:
                                                        MaterialTapTargetSize
                                                            .shrinkWrap,
                                                  ),
                                                ),
                                                Text(
                                                  '累计完成: ${stats['count']} 次',
                                                  style: const TextStyle(
                                                    fontSize: 11,
                                                    color: Colors.white54,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(height: 12),

                                      Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.end,
                                        children: [
                                          Container(
                                            decoration: BoxDecoration(
                                              gradient: const LinearGradient(
                                                colors: [
                                                  Color(0xFF10B981),
                                                  Color(0xFF059669),
                                                ],
                                              ),
                                              borderRadius:
                                                  BorderRadius.circular(14),
                                              boxShadow: [
                                                BoxShadow(
                                                  color: const Color(
                                                    0xFF10B981,
                                                  ).withAlpha(80),
                                                  blurRadius: 10,
                                                  spreadRadius: 1,
                                                ),
                                              ],
                                            ),
                                            child: ElevatedButton.icon(
                                              onPressed: () =>
                                                  _showRecordLogDialog(
                                                    preselectedRoute: route,
                                                  ),
                                              icon: const Icon(
                                                Icons.flash_on,
                                                size: 14,
                                              ),
                                              label: const Text(
                                                '记一次',
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                              style: ElevatedButton.styleFrom(
                                                backgroundColor:
                                                    Colors.transparent,
                                                shadowColor: Colors.transparent,
                                                foregroundColor: Colors.white,
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 14,
                                                      vertical: 8,
                                                    ),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                  const SizedBox(height: 22),

                  // 3. 路线打卡履约日志
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        '路线打卡履约日志',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      ElevatedButton.icon(
                        onPressed: () => _showRecordLogDialog(),
                        icon: const Icon(Icons.directions_walk, size: 14),
                        label: const Text(
                          '记录打卡',
                          style: TextStyle(fontSize: 12),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF10B981),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  stepProvider.stepLogs.isEmpty
                      ? const Padding(
                          padding: EdgeInsets.all(24),
                          child: Center(
                            child: Text(
                              '暂无路线打卡记录',
                              style: TextStyle(color: Colors.grey),
                            ),
                          ),
                        )
                      : ListView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: stepProvider.stepLogs.length,
                          itemBuilder: (context, index) {
                            final log = stepProvider.stepLogs[index];
                            final timeStr = DateFormat(
                              'yyyy-MM-dd',
                            ).format(log.timestamp);

                            return Padding(
                              padding: const EdgeInsets.only(bottom: 10.0),
                              child: _buildGlassCard(
                                child: ListTile(
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                    vertical: 4,
                                  ),
                                  leading: CircleAvatar(
                                    radius: 18,
                                    backgroundColor: const Color(
                                      0xFF10B981,
                                    ).withAlpha(40),
                                    child: const Icon(
                                      Icons.directions_walk,
                                      color: Color(0xFF10B981),
                                      size: 18,
                                    ),
                                  ),
                                  title: Row(
                                    children: [
                                      Text(
                                        log.routeName,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 14,
                                          color: Colors.white,
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      Text(
                                        '(${log.timesCount}次)',
                                        style: const TextStyle(
                                          fontSize: 11,
                                          color: Colors.white70,
                                        ),
                                      ),
                                    ],
                                  ),
                                  subtitle: Text(
                                    '$timeStr · 行走人: ${log.walkerName} · ${log.durationMinutes}分钟',
                                    style: const TextStyle(
                                      fontSize: 11,
                                      color: Colors.white54,
                                    ),
                                  ),
                                  trailing: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Column(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        crossAxisAlignment:
                                            CrossAxisAlignment.end,
                                        children: [
                                          Text(
                                            '${log.distanceKm.toStringAsFixed(2)} km',
                                            style: const TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 14,
                                              color: Color(0xFF34D399),
                                            ),
                                          ),
                                          Text(
                                            '${log.caloriesKcal.toStringAsFixed(1)} kcal',
                                            style: const TextStyle(
                                              fontSize: 11,
                                              color: Color(0xFFFB7185),
                                            ),
                                          ),
                                        ],
                                      ),
                                      IconButton(
                                        padding: const EdgeInsets.all(6),
                                        constraints: const BoxConstraints(),
                                        icon: const Icon(
                                          Icons.delete_outline,
                                          size: 18,
                                          color: Colors.redAccent,
                                        ),
                                        onPressed: () =>
                                            stepProvider.deleteStepLog(log.id!),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailField(String title, String val, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(color: Colors.white54, fontSize: 10),
        ),
        const SizedBox(height: 2),
        Text(
          val,
          style: TextStyle(
            color: color,
            fontSize: 13,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyRouteCard() {
    return _buildGlassCard(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Row(
          children: [
            const Icon(Icons.map_outlined, color: Colors.white38, size: 32),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                '还没有客观路线资产，点击新建第一个路线吧！',
                style: TextStyle(color: Colors.white70, fontSize: 12),
              ),
            ),
            ElevatedButton(
              onPressed: _showAddRouteAssetDialog,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF10B981),
                foregroundColor: Colors.white,
              ),
              child: const Text('新建路线', style: TextStyle(fontSize: 12)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGlassCard({required Widget child}) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white.withAlpha(16),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white.withAlpha(35), width: 1.2),
          ),
          child: child,
        ),
      ),
    );
  }
}

/// 计步测量结算弹窗：显示本次总步数（可修正）、倍数（一位小数）、单程步数预览
Future<_MeasureResult?> _showMeasureSettleDialog(
  BuildContext context, {
  required int autoSteps,
  required bool canAutoSteps,
}) {
  final stepsController = TextEditingController(
    text: autoSteps > 0 ? '$autoSteps' : '',
  );
  final multController = TextEditingController(text: '1.0');
  return showDialog<_MeasureResult>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (dialogCtx, setModalState) {
        int getComputed() {
          final s = int.tryParse(stepsController.text.trim()) ?? 0;
          final m = double.tryParse(multController.text.trim()) ?? 1.0;
          return RouteMeasurement.computeSingleSteps(s, m);
        }

        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: const Row(
            children: [
              Icon(Icons.straighten, color: Color(0xFF10B981)),
              SizedBox(width: 8),
              Text('测量结算'),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '这次走的总距离是「单程」的几倍？（支持一位小数，如 1.5 / 1.8 / 2.0）',
                  style: TextStyle(fontSize: 12, color: Colors.white70),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: stepsController,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: '本次实际总步数',
                    hintText: canAutoSteps ? '已自动带出计步器读数，可修正' : '桌面无计步器，请手动填写',
                    hintStyle: AppTheme.hintStyle,
                  ),
                  onChanged: (_) => setModalState(() {}),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: multController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  inputFormatters: [_DecimalOneFormatter()],
                  decoration: const InputDecoration(
                    labelText: '倍数（一位小数）',
                    hintText: '例: 1.5 / 1.8 / 2.0',
                    hintStyle: AppTheme.hintStyle,
                  ),
                  onChanged: (_) => setModalState(() {}),
                ),
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF10B981).withAlpha(25),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.flag_circle,
                        color: Color(0xFF10B981),
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '单程步数 = ${getComputed()} 步',
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF10B981),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                stepsController.dispose();
                multController.dispose();
                Navigator.of(dialogCtx).pop();
              },
              child: const Text('取消'),
            ),
            ElevatedButton(
              onPressed: () {
                final steps = int.tryParse(stepsController.text.trim());
                final multText = multController.text.trim();
                if (steps == null || steps <= 0) {
                  ScaffoldMessenger.of(
                    dialogCtx,
                  ).showSnackBar(const SnackBar(content: Text('请填写本次实际总步数')));
                  return;
                }
                if (!RegExp(r'^\d+(\.\d)?$').hasMatch(multText)) {
                  ScaffoldMessenger.of(dialogCtx).showSnackBar(
                    const SnackBar(
                      content: Text('倍数格式不正确，仅支持一位小数，如 1.5 / 1.8 / 2.0'),
                    ),
                  );
                  return;
                }
                final mult = double.tryParse(multText) ?? 1.0;
                if (mult <= 0) {
                  ScaffoldMessenger.of(
                    dialogCtx,
                  ).showSnackBar(const SnackBar(content: Text('倍数需大于 0')));
                  return;
                }
                final computed = RouteMeasurement.computeSingleSteps(
                  steps,
                  mult,
                );
                stepsController.dispose();
                multController.dispose();
                Navigator.of(
                  dialogCtx,
                ).pop(_MeasureResult(steps, mult, computed));
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF10B981),
                foregroundColor: Colors.white,
              ),
              child: const Text('确认结算'),
            ),
          ],
        );
      },
    ),
  );
}

class _MeasureSection extends StatefulWidget {
  final void Function(_MeasureResult? result) onResult;
  const _MeasureSection({required this.onResult});

  @override
  State<_MeasureSection> createState() => _MeasureSectionState();
}

class _MeasureSectionState extends State<_MeasureSection> {
  bool _measuring = false;
  bool _sensorOk = false;
  int _elapsed = 0;
  int _startCounter = 0;
  Timer? _timer;
  _MeasureResult? _lastResult;

  @override
  void dispose() {
    _timer?.cancel();
    StepCounterService.stop();
    super.dispose();
  }

  String _fmtTime(int s) {
    final m = (s ~/ 60).toString().padLeft(2, '0');
    final sec = (s % 60).toString().padLeft(2, '0');
    return '$m:$sec';
  }

  Future<void> _start() async {
    _sensorOk = await StepCounterService.start();
    if (!mounted) return;
    if (!_sensorOk) {
      // 桌面无计步器：直接进入结算（手动填总步数）
      final r = await _showMeasureSettleDialog(
        context,
        autoSteps: 0,
        canAutoSteps: false,
      );
      if (r != null && mounted) {
        setState(() => _lastResult = r);
        widget.onResult(r);
      }
      return;
    }
    await Future.delayed(const Duration(milliseconds: 600));
    _startCounter = StepCounterService.currentSteps;
    if (!mounted) return;
    setState(() {
      _measuring = true;
      _elapsed = 0;
    });
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (mounted) setState(() => _elapsed++);
    });
  }

  Future<void> _end() async {
    await Future.delayed(const Duration(milliseconds: 400));
    final endCounter = StepCounterService.currentSteps;
    await StepCounterService.stop();
    _timer?.cancel();
    _timer = null;
    final auto = (endCounter - _startCounter).clamp(0, 1 << 30).toInt();
    if (!mounted) return;
    final r = await _showMeasureSettleDialog(
      context,
      autoSteps: auto,
      canAutoSteps: true,
    );
    if (!mounted) return;
    setState(() {
      _measuring = false;
      if (r != null) _lastResult = r;
    });
    widget.onResult(r);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withAlpha(8),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withAlpha(20)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_lastResult != null) ...[
            Row(
              children: [
                const Icon(
                  Icons.check_circle,
                  color: Color(0xFF10B981),
                  size: 18,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '本次实测 ${_lastResult!.steps} 步 × ${_lastResult!.multiplier.toStringAsFixed(1)} 倍 → 单程 ${_lastResult!.computed} 步',
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF10B981),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () {
                  setState(() {
                    _lastResult = null;
                    _measuring = false;
                  });
                  widget.onResult(null);
                },
                icon: const Icon(Icons.replay, size: 15),
                label: const Text('重新测量'),
              ),
            ),
          ] else if (_measuring) ...[
            Row(
              children: [
                const Icon(Icons.timer_outlined, color: Colors.amber, size: 18),
                const SizedBox(width: 8),
                Text(
                  '测量中 ${_fmtTime(_elapsed)}',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: Colors.amber,
                  ),
                ),
                const Spacer(),
                TextButton.icon(
                  onPressed: _end,
                  icon: const Icon(Icons.stop_circle_outlined, size: 16),
                  label: const Text('结束并结算'),
                ),
              ],
            ),
            const Padding(
              padding: EdgeInsets.only(top: 6),
              child: Text(
                '正在监听系统计步器，走到终点后点「结束并结算」',
                style: TextStyle(fontSize: 11, color: Colors.white54),
              ),
            ),
          ] else ...[
            Row(
              children: [
                Expanded(
                  child: Text(
                    _sensorOk
                        ? '计步测量：点开始后系统自动记录步数，结束时换算单程步数'
                        : '计步测量：当前设备无计步器，将手动填写本次总步数与倍数',
                    style: const TextStyle(fontSize: 11, color: Colors.white54),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: _start,
                  icon: const Icon(Icons.play_arrow, size: 16),
                  label: const Text('开始测量'),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF10B981),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
