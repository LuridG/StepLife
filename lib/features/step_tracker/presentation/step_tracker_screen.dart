import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../domain/step_models.dart';
import '../providers/step_provider.dart';
import '../../chore_tracker/domain/chore_models.dart';
import '../../chore_tracker/providers/chore_provider.dart';
import '../../chore_tracker/presentation/member_dialog.dart';
import '../../profile/providers/profile_provider.dart';
import '../../../core/utils/fitness_calculator.dart';

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
    showDialog(
      context: context,
      builder: (ctx) => const MemberDialog(),
    );
  }

  void _showEditMemberDialog(Member member) {
    showDialog(
      context: context,
      builder: (ctx) => MemberDialog(memberToEdit: member),
    );
  }

  void _showAddRouteAssetDialog() {
    final nameController = TextEditingController();
    final refStepsController = TextEditingController(text: '2500');
    final descController = TextEditingController();

    final members = context.read<ChoreProvider>().members;
    String selectedMeasurer = members.isNotEmpty ? members.first.name : '自己';

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) {
          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
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
                      const Text('3. 测量人 (谁测量的此路线):', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                      InkWell(
                        onTap: () {
                          Navigator.of(ctx).pop();
                          _showAddMemberDialog();
                        },
                        child: const Text('+ 新增成员档案', style: TextStyle(color: Color(0xFF10B981), fontSize: 12, fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  DropdownButtonFormField<String>(
                    initialValue: selectedMeasurer,
                    decoration: const InputDecoration(border: OutlineInputBorder()),
                    items: [
                      const DropdownMenuItem(value: '自己', child: Text('自己')),
                      ...members.map((m) => DropdownMenuItem(value: m.name, child: Text('${m.name} (${m.heightCm.toInt()}cm/${m.weightKg.toInt()}kg)'))),
                    ],
                    onChanged: (val) {
                      if (val != null) setModalState(() => selectedMeasurer = val);
                    },
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: refStepsController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: '4. 测量人走的步数 (步)',
                      hintText: '例: 2500 步',
                    ),
                  ),
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
                onPressed: () {
                  final name = nameController.text.trim();
                  final refSteps = int.tryParse(refStepsController.text) ?? 2000;

                  if (name.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('路线名称不能为空')),
                    );
                    return;
                  }

                  context.read<StepProvider>().addRoute(
                        name,
                        refSteps: refSteps,
                        measuredBy: selectedMeasurer,
                        description: descController.text.trim(),
                      );

                  nameController.dispose();
                  refStepsController.dispose();
                  descController.dispose();
                  Navigator.of(ctx).pop();

                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('已成功建立路线资产: $name'), backgroundColor: const Color(0xFF10B981)),
                  );
                },
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
    final refStepsController = TextEditingController(text: route.refSteps.toString());
    final descController = TextEditingController(text: route.description ?? '');

    final members = context.read<ChoreProvider>().members;
    String selectedMeasurer = route.measuredBy;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) {
          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
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
                  const Text('测量人:', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  DropdownButtonFormField<String>(
                    initialValue: selectedMeasurer,
                    decoration: const InputDecoration(border: OutlineInputBorder()),
                    items: [
                      const DropdownMenuItem(value: '自己', child: Text('自己')),
                      ...members.map((m) => DropdownMenuItem(value: m.name, child: Text('${m.name} (${m.heightCm.toInt()}cm/${m.weightKg.toInt()}kg)'))),
                    ],
                    onChanged: (val) {
                      if (val != null) setModalState(() => selectedMeasurer = val);
                    },
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: refStepsController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: '测量人步数 (步)'),
                  ),
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
                onPressed: () {
                  final name = nameController.text.trim();
                  final refSteps = int.tryParse(refStepsController.text) ?? route.refSteps;

                  if (name.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('路线名称不能为空')),
                    );
                    return;
                  }

                  final updatedRoute = route.copyWith(
                    name: name,
                    description: descController.text.trim(),
                    measuredBy: selectedMeasurer,
                    refSteps: refSteps,
                  );

                  context.read<StepProvider>().updateRoute(updatedRoute);

                  nameController.dispose();
                  refStepsController.dispose();
                  descController.dispose();
                  Navigator.of(ctx).pop();

                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('已更新路线: $name'), backgroundColor: const Color(0xFF10B981)),
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先新建一条客观路线资产')),
      );
      _showAddRouteAssetDialog();
      return;
    }

    RouteItem selectedRoute = preselectedRoute ?? routes.first;
    final timesController = TextEditingController(text: '1');
    final stepsController = TextEditingController(text: selectedRoute.refSteps.toString());
    final durationController = TextEditingController(text: '30');

    final choreProvider = context.read<ChoreProvider>();
    final members = choreProvider.members;
    String selectedWalker = members.isNotEmpty ? members.first.name : '自己';
    DateTime selectedDate = DateTime.now();

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
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
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
                  const Text('选择客观路线:', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  DropdownButtonFormField<RouteItem>(
                    initialValue: selectedRoute,
                    decoration: const InputDecoration(border: OutlineInputBorder()),
                    items: routes.map((r) => DropdownMenuItem(value: r, child: Text('${r.name} (${r.refSteps}步)'))).toList(),
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
                            const DropdownMenuItem(value: '自己', child: Text('自己')),
                            ...members.map((m) => DropdownMenuItem(value: m.name, child: Text(m.name))),
                          ],
                          onChanged: (val) {
                            if (val != null) setModalState(() => selectedWalker = val);
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
                        style: const TextStyle(fontSize: 11, color: Color(0xFF10B981)),
                      ),
                    ),
                  const SizedBox(height: 12),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.calendar_today, color: Color(0xFF10B981)),
                    title: Text('打卡日期: ${DateFormat('yyyy-MM-dd').format(selectedDate)}'),
                    trailing: TextButton(
                      child: const Text('更改日期'),
                      onPressed: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: selectedDate,
                          firstDate: DateTime(2020),
                          lastDate: DateTime(2030),
                        );
                        if (picked != null) {
                          setModalState(() => selectedDate = picked);
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
                  final steps = int.tryParse(stepsController.text) ?? selectedRoute.refSteps;
                  final duration = int.tryParse(durationController.text) ?? 30;

                  final fallbackProfile = context.read<ProfileProvider>().profile;

                  context.read<StepProvider>().recordStepLog(
                        routeId: selectedRoute.id,
                        routeName: selectedRoute.name,
                        walkerName: selectedWalker,
                        timesCount: times,
                        steps: steps,
                        durationMinutes: duration,
                        targetDate: selectedDate,
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
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('已删除路线: ${route.name}')),
              );
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            child: const Text('确认删除', style: TextStyle(color: Colors.white)),
          ),
        ],
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
          IconButton(
            icon: const Icon(Icons.person_add_outlined),
            tooltip: '新增成员档案',
            onPressed: _showAddMemberDialog,
          ),
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
                  colors: [Color(0xFF090D16), Color(0xFF111C38), Color(0xFF0F172A)],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
            ),
            SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 14.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 1. 顶部成员档案 Pill 控件
                  Row(
                    children: [
                      const Text('成员档案:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.white70)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: choreProvider.members.map((m) {
                              return Padding(
                                padding: const EdgeInsets.only(right: 8.0),
                                child: ActionChip(
                                  backgroundColor: Colors.white.withAlpha(15),
                                  side: BorderSide(color: Color(m.colorValue).withAlpha(100)),
                                  avatar: CircleAvatar(
                                    backgroundColor: Color(m.colorValue),
                                    child: Text(m.name[0], style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                                  ),
                                  label: Text('${m.name} (${m.heightCm.toInt()}cm/${m.weightKg.toInt()}kg)', style: const TextStyle(fontSize: 11, color: Colors.white)),
                                  onPressed: () => _showEditMemberDialog(m),
                                ),
                              );
                            }).toList(),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // 2. 客观路线资产库 (纵向列表)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('客观路线资产库 (列表)', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
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
                            final stats = stepProvider.getRouteStats(route.name);

                            final measurerMember = choreProvider.getMemberByName(route.measuredBy);
                            final double mHeight = measurerMember?.heightCm ?? profile.heightCm;
                            final String mGender = measurerMember?.gender ?? profile.gender;
                            final double? mCustomStride = measurerMember?.customStrideCm ?? profile.customStrideCm;

                            final mStrideCm = mCustomStride ??
                                FitnessCalculator.estimateStrideLength(
                                  heightCm: mHeight,
                                  gender: mGender,
                                );

                            final calculatedKm = FitnessCalculator.stepsToKilometers(route.refSteps, mStrideCm);

                            return Padding(
                              padding: const EdgeInsets.only(bottom: 14.0),
                              child: _buildGlassCard(
                                child: Padding(
                                  padding: const EdgeInsets.all(16.0),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      // 路线名称 & 管理按钮
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          Expanded(
                                            child: Row(
                                              children: [
                                                Container(
                                                  padding: const EdgeInsets.all(8),
                                                  decoration: BoxDecoration(
                                                    color: const Color(0xFF10B981).withAlpha(40),
                                                    borderRadius: BorderRadius.circular(12),
                                                    border: Border.all(color: const Color(0xFF10B981).withAlpha(80)),
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
                                                      fontWeight: FontWeight.bold,
                                                      color: Colors.white,
                                                    ),
                                                    overflow: TextOverflow.ellipsis,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              IconButton(
                                                constraints: const BoxConstraints(),
                                                padding: const EdgeInsets.all(6),
                                                icon: Icon(
                                                  Icons.edit_outlined,
                                                  color: route.isLocked ? Colors.white24 : Colors.lightBlueAccent,
                                                  size: 18,
                                                ),
                                                tooltip: '编辑路线',
                                                onPressed: () => _showEditRouteAssetDialog(route),
                                              ),
                                              IconButton(
                                                constraints: const BoxConstraints(),
                                                padding: const EdgeInsets.all(6),
                                                icon: Icon(
                                                  route.isLocked ? Icons.lock : Icons.lock_open,
                                                  color: route.isLocked ? Colors.amber : Colors.white54,
                                                  size: 18,
                                                ),
                                                tooltip: route.isLocked ? '点击解锁路线' : '点击锁定保护路线',
                                                onPressed: () => stepProvider.toggleLockRoute(route.id!),
                                              ),
                                              IconButton(
                                                constraints: const BoxConstraints(),
                                                padding: const EdgeInsets.all(6),
                                                icon: Icon(
                                                  Icons.delete_outline,
                                                  color: route.isLocked ? Colors.white24 : Colors.redAccent,
                                                  size: 18,
                                                ),
                                                tooltip: '删除路线',
                                                onPressed: () => _confirmDeleteRoute(route),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 8),

                                      if (route.description != null && route.description!.isNotEmpty)
                                        Padding(
                                          padding: const EdgeInsets.only(bottom: 10.0),
                                          child: Text(
                                            '路线描述: ${route.description}',
                                            style: const TextStyle(fontSize: 12, color: Colors.white70, fontStyle: FontStyle.italic),
                                          ),
                                        ),

                                      // 依次排布：测量人 | 测量步数 | 自动换算距离
                                      Container(
                                        padding: const EdgeInsets.all(10),
                                        decoration: BoxDecoration(
                                          color: Colors.black.withAlpha(30),
                                          borderRadius: BorderRadius.circular(12),
                                          border: Border.all(color: Colors.white.withAlpha(15)),
                                        ),
                                        child: Row(
                                          mainAxisAlignment: MainAxisAlignment.spaceAround,
                                          children: [
                                            _buildDetailField('测量人', route.measuredBy, const Color(0xFF818CF8)),
                                            _buildDetailField('测量步数', '${route.refSteps} 步', const Color(0xFF60A5FA)),
                                            _buildDetailField('自动换算距离', '${calculatedKm.toStringAsFixed(2)} km', const Color(0xFF34D399)),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(height: 12),

                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          Text(
                                            '累计完成: ${stats['count']} 次',
                                            style: const TextStyle(fontSize: 12, color: Colors.white54),
                                          ),
                                          Container(
                                            decoration: BoxDecoration(
                                              gradient: const LinearGradient(
                                                colors: [Color(0xFF10B981), Color(0xFF059669)],
                                              ),
                                              borderRadius: BorderRadius.circular(14),
                                              boxShadow: [
                                                BoxShadow(
                                                  color: const Color(0xFF10B981).withAlpha(80),
                                                  blurRadius: 10,
                                                  spreadRadius: 1,
                                                ),
                                              ],
                                            ),
                                            child: ElevatedButton.icon(
                                              onPressed: () => _showRecordLogDialog(preselectedRoute: route),
                                              icon: const Icon(Icons.flash_on, size: 14),
                                              label: const Text('⚡ 记一次', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                                              style: ElevatedButton.styleFrom(
                                                backgroundColor: Colors.transparent,
                                                shadowColor: Colors.transparent,
                                                foregroundColor: Colors.white,
                                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
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
                      const Text('路线打卡履约日志', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
                      ElevatedButton.icon(
                        onPressed: () => _showRecordLogDialog(),
                        icon: const Icon(Icons.directions_walk, size: 14),
                        label: const Text('记录打卡', style: TextStyle(fontSize: 12)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF10B981),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  stepProvider.stepLogs.isEmpty
                      ? const Padding(
                          padding: EdgeInsets.all(24),
                          child: Center(child: Text('暂无路线打卡记录', style: TextStyle(color: Colors.grey))),
                        )
                      : ListView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: stepProvider.stepLogs.length,
                          itemBuilder: (context, index) {
                            final log = stepProvider.stepLogs[index];
                            final timeStr = DateFormat('yyyy-MM-dd').format(log.timestamp);

                            return Padding(
                              padding: const EdgeInsets.only(bottom: 10.0),
                              child: _buildGlassCard(
                                child: ListTile(
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                                  leading: CircleAvatar(
                                    radius: 18,
                                    backgroundColor: const Color(0xFF10B981).withAlpha(40),
                                    child: const Icon(Icons.directions_walk, color: Color(0xFF10B981), size: 18),
                                  ),
                                  title: Row(
                                    children: [
                                      Text(log.routeName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.white)),
                                      const SizedBox(width: 6),
                                      Text('(${log.timesCount}次)', style: const TextStyle(fontSize: 11, color: Colors.white70)),
                                    ],
                                  ),
                                  subtitle: Text('$timeStr · 行走人: ${log.walkerName} · ${log.durationMinutes}分钟', style: const TextStyle(fontSize: 11, color: Colors.white54)),
                                  trailing: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Column(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        crossAxisAlignment: CrossAxisAlignment.end,
                                        children: [
                                          Text('${log.distanceKm.toStringAsFixed(2)} km',
                                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF34D399))),
                                          Text('${log.caloriesKcal.toStringAsFixed(1)} kcal',
                                              style: const TextStyle(fontSize: 11, color: Color(0xFFFB7185))),
                                        ],
                                      ),
                                      IconButton(
                                        padding: const EdgeInsets.all(6),
                                        constraints: const BoxConstraints(),
                                        icon: const Icon(Icons.delete_outline, size: 18, color: Colors.redAccent),
                                        onPressed: () => stepProvider.deleteStepLog(log.id!),
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
        Text(title, style: const TextStyle(color: Colors.white54, fontSize: 10)),
        const SizedBox(height: 2),
        Text(val, style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.bold)),
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
              child: Text('还没有客观路线资产，点击新建第一个路线吧！', style: TextStyle(color: Colors.white70, fontSize: 12)),
            ),
            ElevatedButton(
              onPressed: _showAddRouteAssetDialog,
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF10B981), foregroundColor: Colors.white),
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
