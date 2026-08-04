import 'dart:io';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../domain/store_models.dart';
import '../domain/life_templates.dart';
import '../providers/store_provider.dart';
import '../../chore_tracker/domain/chore_models.dart';
import '../../chore_tracker/providers/chore_provider.dart';
import '../../../core/settings/settings_provider.dart';
import '../../../core/theme/app_theme.dart';
import 'template_field_widget.dart';

/// 生活打卡弹窗：新建 / 修改复用（传入 existingLog 即为编辑模式，预填原记录）
class StoreCheckinDialog extends StatelessWidget {
  final StoreItem store;
  final StoreLog? existingLog;

  const StoreCheckinDialog({super.key, required this.store, this.existingLog});

  /// 金额格式化：整数不带小数，非整数保留 1 位小数
  String _fmtPrice(double v) {
    if (v == v.roundToDouble()) {
      return v.toStringAsFixed(0);
    }
    return v.toStringAsFixed(1);
  }

  /// 从模板字段值解析数字（兼容 num 与字符串）
  double? _numOf(dynamic v) {
    if (v is num) return v.toDouble();
    return double.tryParse(v?.toString() ?? '');
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = existingLog != null;
    final costController = TextEditingController();
    // 总价是否被用户手动编辑（手动编辑后不再被 单价 × 数量 自动覆盖）
    var costEditedByUser = false;
    final memoController = TextEditingController();
    final members = context.read<ChoreProvider>().members;
    final Map<String, dynamic> extrasValues = <String, dynamic>{};

    // 模板打卡字段（分类模板 + 自定义字段）
    final storeProvider = context.read<StoreProvider>();
    StoreCategory? cat;
    for (final c in storeProvider.categories) {
      if (c.name == store.category) {
        cat = c;
        break;
      }
    }
    final tpl = LifeTemplates.byKey(
      cat?.templateKey ?? LifeTemplates.matchTemplateKey(store.category),
    );
    final isBasket = tpl.key == 'basket';
    final customFields = (cat?.extraFields ?? const [])
        .map((m) => TemplateField.fromJson(m))
        .toList();
    final mergedCheckinFields = [...tpl.checkinFields, ...customFields];
    // 集数打卡仅对电视剧/动漫/综艺等剧集展示（电影不显示）
    final isSerialMovie = tpl.key == 'movie' && resolveMediaType(store.extras) != '电影';
    // 菜篮子品牌历史：从打卡记录收集已用品牌，自动成为下拉快捷选项
    final brandHistory = <String>[];
    for (final log in storeProvider.getLogsForStore(store.id ?? 0)) {
      final b = log.extras['brand']?.toString().trim() ?? '';
      if (b.isNotEmpty && !brandHistory.contains(b)) {
        brandHistory.add(b);
      }
    }
    final checkinFields = mergedCheckinFields
        .where((f) => !(f.key == 'episodesWatched' && !isSerialMovie))
        .map((f) {
          if (f.key == 'brand' && brandHistory.isNotEmpty) {
            return TemplateField(
              key: f.key,
              label: f.label,
              type: f.type,
              hint: f.hint,
              required: f.required,
              options: f.options,
              defaultValue: f.defaultValue,
              suggestions: brandHistory,
            );
          }
          return f;
        })
        .toList();

    // 餐饮菜单：打卡时多选菜品，自动合计消费
    final storeMenu = tpl.key == 'dining'
        ? storeProvider.getMenuItemsForStore(store.id ?? 0)
        : const <StoreMenuItem>[];
    final List<_SelectedMenu> selectedMenuItems = [];

    DateTime selectedDateTime = isEdit ? existingLog!.timestamp : DateTime.now();
    final List<Member> selectedMembers = [];
    final checkinSettings = context.read<SettingsProvider>();

    if (isEdit) {
      // ---- 编辑模式：预填原记录 ----
      final oldCost = existingLog!.cost;
      costController.text = (oldCost != null && oldCost > 0) ? _fmtPrice(oldCost) : '';
      memoController.text = existingLog!.memo ?? '';
      extrasValues.addAll(existingLog!.extras);
      // 预选成员：优先按 id，其次按姓名兜底
      final idSet = existingLog!.visitorIds.toSet();
      for (final m in members) {
        if (m.id != null && idSet.contains(m.id)) {
          selectedMembers.add(m);
        }
      }
      if (selectedMembers.isEmpty) {
        for (final n in existingLog!.visitorNames) {
          for (final m in members) {
            if (m.name == n && !selectedMembers.contains(m)) {
              selectedMembers.add(m);
            }
          }
        }
      }
      // 预选菜品（含份量规格，按 menuItemIds / menuSpecs 恢复）
      final menuIdList = existingLog!.menuItemIds;
      final menuSpecList = existingLog!.menuSpecs;
      for (final m in storeMenu) {
        if (m.id == null || !menuIdList.contains(m.id)) continue;
        final idx = menuIdList.indexOf(m.id!);
        final specName = (idx >= 0 && idx < menuSpecList.length) ? menuSpecList[idx] : '';
        MenuItemSpec? spec;
        if (specName.isNotEmpty) {
          for (final s in m.specs) {
            if (s.name == specName) {
              spec = s;
              break;
            }
          }
        }
        selectedMenuItems.add(_SelectedMenu(m, spec));
      }
    } else {
      // ---- 新建模式：默认成员 ----
      // 打卡默认成员设置：last = 复用上次选择；self = 默认自己（首个成员）
      if (checkinSettings.defaultMember == 'last' &&
          checkinSettings.lastCheckinMemberIds.isNotEmpty) {
        final ids = checkinSettings.lastCheckinMemberIds
            .split(',')
            .map(int.tryParse)
            .whereType<int>()
            .toSet();
        for (final m in members) {
          if (m.id != null && ids.contains(m.id)) {
            selectedMembers.add(m);
          }
        }
      }
      if (selectedMembers.isEmpty && members.isNotEmpty) {
        selectedMembers.add(members.first);
      }
    }

    return StatefulBuilder(
      builder: (dialogCtx, setModalState) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Row(
            children: [
              Icon(
                isEdit ? Icons.edit_note : Icons.flash_on,
                color: const Color(0xFF10B981),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  isEdit ? '修改打卡: ${store.name}' : '打卡: ${store.name}',
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 餐饮菜单多选：选菜自动合计消费金额
                if (tpl.key == 'dining' && storeMenu.isNotEmpty) ...[
                  const Text('点菜 (可多选，自动合计):', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: storeMenu.map((m) {
                      final selIndex = selectedMenuItems.indexWhere((s) => s.item.id == m.id);
                      final isSelected = selIndex != -1;
                      final currentSpec = isSelected ? selectedMenuItems[selIndex].spec : null;
                      final label = m.specs.isEmpty
                          ? '${m.name} ¥${_fmtPrice(m.price)}'
                          : (currentSpec != null
                              ? '${m.name}（${currentSpec.name} ¥${_fmtPrice(currentSpec.price)}）'
                              : '${m.name} ¥${_fmtPrice(m.specs.first.price)}起');
                      return FilterChip(
                        avatar: (m.imagePath != null && m.imagePath!.isNotEmpty)
                            ? ClipRRect(
                                borderRadius: BorderRadius.circular(4),
                                child: Image.file(
                                  File(m.imagePath!),
                                  width: 22,
                                  height: 22,
                                  fit: BoxFit.cover,
                                  errorBuilder: (c, e, s) => const Icon(Icons.restaurant, size: 16, color: Colors.white38),
                                ),
                              )
                            : null,
                        label: Text(label, style: const TextStyle(fontSize: 12)),
                        selected: isSelected,
                        selectedColor: const Color(0xFF10B981).withAlpha(90),
                        onSelected: (sel) {
                          if (m.specs.isEmpty) {
                            setModalState(() {
                              if (sel) {
                                selectedMenuItems.add(_SelectedMenu(m, null));
                              } else {
                                selectedMenuItems.removeWhere((s) => s.item.id == m.id);
                              }
                              final sum = selectedMenuItems.fold<double>(
                                0.0,
                                (acc, x) => acc + x.price,
                              );
                              costController.text = sum == 0 ? '' : _fmtPrice(sum);
                            });
                          } else if (sel) {
                            // 有规格：弹出规格选择
                            _showSpecPicker(dialogCtx, m, (spec) {
                              setModalState(() {
                                selectedMenuItems.removeWhere((s) => s.item.id == m.id);
                                selectedMenuItems.add(_SelectedMenu(m, spec));
                                final sum = selectedMenuItems.fold<double>(
                                  0.0,
                                  (acc, x) => acc + x.price,
                                );
                                costController.text = sum == 0 ? '' : _fmtPrice(sum);
                              });
                            });
                          } else {
                            setModalState(() {
                              selectedMenuItems.removeWhere((s) => s.item.id == m.id);
                              final sum = selectedMenuItems.fold<double>(
                                0.0,
                                (acc, x) => acc + x.price,
                              );
                              costController.text = sum == 0 ? '' : _fmtPrice(sum);
                            });
                          }
                        },
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 14),
                ],
                TextField(
                  controller: costController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  onChanged: (_) => setModalState(() => costEditedByUser = true),
                  decoration: InputDecoration(
                    labelText: isBasket ? '总价（可自动计算）' : '本次打卡消费金额',
                    hintText: isBasket ? '留空自动按 单价 × 数量 计算，也可手动填写' : '例: 45 元 (不涉及消费可留空或填 0)',
                    hintStyle: AppTheme.hintStyle,
                    prefixIcon: const Icon(Icons.attach_money),
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 14),

                // 多选同行/参与人员 (复用统一 Member 系统)
                const Text('参与/同行人员 (可多选):', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                const SizedBox(height: 8),
                members.isEmpty
                    ? const Text('暂无成员信息，可先在【家务习惯】顶栏增加成员档案', style: TextStyle(fontSize: 11, color: Colors.white54))
                    : Wrap(
                        spacing: 8,
                        children: members.map((m) {
                          final isSelected = selectedMembers.contains(m);
                          return FilterChip(
                            label: Text(m.name),
                            selected: isSelected,
                            selectedColor: Color(m.colorValue).withAlpha(80),
                            onSelected: (selected) {
                              setModalState(() {
                                if (selected) {
                                  selectedMembers.add(m);
                                } else {
                                  selectedMembers.remove(m);
                                }
                              });
                            },
                          );
                        }).toList(),
                      ),
                const SizedBox(height: 14),

                // 模板专属打卡字段（动态渲染）
                ...checkinFields.map((f) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: TemplateFieldWidget(
                        field: f,
                        value: extrasValues[f.key],
                        onChanged: (v) => setModalState(() {
                          extrasValues[f.key] = v;
                          // 菜篮子：单价/数量变化且总价未被手动编辑时，自动计算总价
                          if (isBasket && !costEditedByUser && (f.key == 'price' || f.key == 'qty')) {
                            final pd = _numOf(extrasValues['price']);
                            final qd = _numOf(extrasValues['qty']);
                            costController.text = (pd != null && qd != null && pd * qd > 0)
                                ? _fmtPrice(pd * qd)
                                : '';
                          }
                        }),
                      ),
                    )),

                TextField(
                  controller: memoController,
                  decoration: const InputDecoration(
                    labelText: '点评 / 体验感受',
                    hintText: '记录本次体验、口味评价等 (选填)',
                    hintStyle: AppTheme.hintStyle,
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 2,
                ),
                const SizedBox(height: 12),

                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.white.withAlpha(10),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white12),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.access_time_filled, color: Color(0xFF10B981), size: 20),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '打卡时刻: ${DateFormat('yyyy-MM-dd HH:mm').format(selectedDateTime)}',
                              style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold, color: Colors.white),
                            ),
                            const SizedBox(height: 2),
                            const Text('默认当前时刻，可选历史时刻', style: TextStyle(fontSize: 10.5, color: Colors.white54)),
                          ],
                        ),
                      ),
                      TextButton(
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        child: const Text('更改时刻', style: TextStyle(fontSize: 12, color: Color(0xFF10B981))),
                        onPressed: () async {
                          final pickedDate = await showDatePicker(
                            context: dialogCtx,
                            initialDate: selectedDateTime,
                            firstDate: DateTime(2020),
                            lastDate: DateTime(2030),
                          );
                          if (pickedDate != null) {
                            if (!dialogCtx.mounted) return;
                            final pickedTime = await showTimePicker(
                              context: dialogCtx,
                              initialTime: TimeOfDay.fromDateTime(selectedDateTime),
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
                    ],
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                costController.dispose();
                memoController.dispose();
                Navigator.of(dialogCtx).pop();
              },
              child: const Text('取消'),
            ),
            ElevatedButton(
              onPressed: () {
                var cost = double.tryParse(costController.text);
                // 菜篮子：总价留空时按 单价 × 数量 自动计算
                if (isBasket && (cost == null || cost <= 0)) {
                  final pd = _numOf(extrasValues['price']);
                  final qd = _numOf(extrasValues['qty']);
                  if (pd != null && qd != null && pd * qd > 0) {
                    cost = pd * qd;
                  }
                }
                final vIds = selectedMembers.map((m) => m.id ?? 0).toList();
                final vNames = selectedMembers.map((m) => m.name).toList();

                if (isEdit) {
                  context.read<StoreProvider>().updateStoreLog(
                        logId: existingLog!.id!,
                        storeId: store.id ?? 0,
                        storeName: store.name,
                        cost: cost,
                        visitorIds: vIds,
                        visitorNames: vNames.isNotEmpty ? vNames : ['自己'],
                        memo: memoController.text.trim(),
                        extras: extrasValues,
                        menuItemIds: selectedMenuItems.map((s) => s.item.id ?? 0).toList(),
                        menuNames: selectedMenuItems.map((s) => s.displayName).toList(),
                        menuSpecs: selectedMenuItems.map((s) => s.spec?.name ?? '').toList(),
                        targetDate: selectedDateTime,
                      );
                } else {
                  if (checkinSettings.defaultMember == 'last') {
                    checkinSettings.setLastCheckinMemberIds(vIds.join(','));
                  }
                  context.read<StoreProvider>().recordStoreCheckin(
                        storeId: store.id ?? 0,
                        storeName: store.name,
                        cost: cost,
                        visitorIds: vIds,
                        visitorNames: vNames.isNotEmpty ? vNames : ['自己'],
                        memo: memoController.text.trim(),
                        extras: extrasValues,
                        menuItemIds: selectedMenuItems.map((s) => s.item.id ?? 0).toList(),
                        menuNames: selectedMenuItems.map((s) => s.displayName).toList(),
                        menuSpecs: selectedMenuItems.map((s) => s.spec?.name ?? '').toList(),
                        targetDate: selectedDateTime,
                      );
                }

                // 影视剧集观看进度累计（编辑时按差值回退/累加）
                if (tpl.key == 'movie' && isSerialMovie) {
                  final watchedNew = extrasValues['episodesWatched'];
                  final newN = (watchedNew is num) ? watchedNew.toInt() : 0;
                  var oldN = 0;
                  if (isEdit) {
                    final oldV = existingLog!.extras['episodesWatched'];
                    oldN = (oldV is num) ? oldV.toInt() : 0;
                  }
                  final delta = newN - oldN;
                  if (delta != 0) {
                    context
                        .read<StoreProvider>()
                        .applyEpisodesProgress(store.id ?? 0, delta);
                  }
                }

                costController.dispose();
                memoController.dispose();
                Navigator.of(dialogCtx).pop();

                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(isEdit ? '已更新【${store.name}】打卡记录！' : '已完成【${store.name}】打卡记录！'),
                    backgroundColor: const Color(0xFF10B981),
                  ),
                );
              },
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF10B981), foregroundColor: Colors.white),
              child: Text(isEdit ? '保存修改' : '提交打卡'),
            ),
          ],
        );
      },
    );
  }

  /// 有规格菜品：弹出规格选择（规格名 + 对应价格）
  Future<void> _showSpecPicker(
    BuildContext dialogCtx,
    StoreMenuItem item,
    void Function(MenuItemSpec spec) onPick,
  ) async {
    await showDialog(
      context: dialogCtx,
      builder: (specCtx) => SimpleDialog(
        title: Text('选择 ${item.name} 份量'),
        children: [
          ...item.specs.map(
            (s) => SimpleDialogOption(
              onPressed: () {
                Navigator.of(specCtx).pop();
                onPick(s);
              },
              child: Row(
                children: [
                  const Icon(Icons.straighten, size: 18, color: Color(0xFF10B981)),
                  const SizedBox(width: 10),
                  Text('${s.name} · ¥${_fmtPrice(s.price)}', style: const TextStyle(fontSize: 14)),
                ],
              ),
            ),
          ),
          const Divider(),
          SimpleDialogOption(
            onPressed: () => Navigator.of(specCtx).pop(),
            child: const Text('取消', style: TextStyle(color: Colors.white54, fontSize: 13)),
          ),
        ],
      ),
    );
  }
}

/// 点菜选中项：菜品 + 可选份量规格（无规格时 spec 为 null，按固定价格计价）
class _SelectedMenu {
  final StoreMenuItem item;
  final MenuItemSpec? spec;

  const _SelectedMenu(this.item, this.spec);

  double get price => spec?.price ?? item.price;

  String get displayName => spec == null ? item.name : '${item.name}（${spec!.name}）';
}
