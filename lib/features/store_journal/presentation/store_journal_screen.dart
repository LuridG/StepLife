import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../domain/store_models.dart';
import '../providers/store_provider.dart';
import '../../chore_tracker/domain/chore_models.dart';
import '../../chore_tracker/providers/chore_provider.dart';
import 'store_detail_screen.dart';

class StoreJournalScreen extends StatefulWidget {
  const StoreJournalScreen({super.key});

  @override
  State<StoreJournalScreen> createState() => _StoreJournalScreenState();
}

class _StoreJournalScreenState extends State<StoreJournalScreen>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  final ImagePicker _picker = ImagePicker();

  void _showAddCategoryDialog() {
    final catController = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('添加自定义分类'),
        content: TextField(
          controller: catController,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: '分类名称 (如: 电影 / 电视剧 / 书籍 / 饭店 / 景点)',
            prefixIcon: Icon(Icons.category),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              catController.dispose();
              Navigator.of(ctx).pop();
            },
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () {
              final name = catController.text.trim();
              if (name.isNotEmpty) {
                context.read<StoreProvider>().addCategory(name);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('已添加分类: $name'), backgroundColor: const Color(0xFF10B981)),
                );
              }
              catController.dispose();
              Navigator.of(ctx).pop();
            },
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF10B981), foregroundColor: Colors.white),
            child: const Text('添加'),
          ),
        ],
      ),
    );
  }

  void _showEditCategoryDialog(StoreCategory category) {
    final catController = TextEditingController(text: category.name);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('编辑分类: ${category.name}'),
        content: TextField(
          controller: catController,
          decoration: const InputDecoration(labelText: '新分类名称'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('取消')),
          ElevatedButton(
            onPressed: () {
              final newName = catController.text.trim();
              if (newName.isNotEmpty) {
                context.read<StoreProvider>().updateCategory(category.id!, newName, category.name);
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('已更新分类: $newName')));
              }
              Navigator.of(ctx).pop();
            },
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF10B981), foregroundColor: Colors.white),
            child: const Text('保存修改'),
          ),
        ],
      ),
    );
  }

  void _confirmDeleteCategory(StoreCategory category) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('删除分类: ${category.name}?'),
        content: const Text('删除分类后，原属于该分类的条目将自动安全重定向归类到“通用未分类”。'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('取消')),
          ElevatedButton(
            onPressed: () {
              context.read<StoreProvider>().deleteCategory(category.id!, category.name);
              Navigator.of(ctx).pop();
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('已删除分类: ${category.name}')));
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            child: const Text('确认删除', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  // 客观资产登记表单 (只登记客观信息，初次登记无消费)
  void _showStoreFormDialog({StoreItem? storeToEdit}) {
    final isEditing = storeToEdit != null;
    final nameController = TextEditingController(text: storeToEdit?.name ?? '');
    final addressController = TextEditingController(text: storeToEdit?.address ?? '');
    final notesController = TextEditingController(text: storeToEdit?.notes ?? '');

    double rating = storeToEdit?.rating ?? 5.0;
    final List<String> images = List.from(storeToEdit?.images ?? []);

    final categories = context.read<StoreProvider>().categories;
    String selectedCategory = storeToEdit?.category ?? (categories.isNotEmpty ? categories.first.name : '餐饮美食');

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (dialogCtx, setModalState) {
          Future<void> pickImage() async {
            if (images.length >= 3) {
              ScaffoldMessenger.of(dialogCtx).showSnackBar(
                const SnackBar(content: Text('至多上传 3 张照片/剧照/海报')),
              );
              return;
            }
            try {
              final XFile? image = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 85);
              if (!dialogCtx.mounted) return;
              if (image != null) {
                setModalState(() {
                  images.add(image.path);
                });
              }
            } catch (e) {
              if (!dialogCtx.mounted) return;
              ScaffoldMessenger.of(dialogCtx).showSnackBar(
                SnackBar(content: Text('选择图片失败: $e')),
              );
            }
          }

          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: Row(
              children: [
                Icon(isEditing ? Icons.edit_note : Icons.auto_awesome, color: const Color(0xFF10B981)),
                const SizedBox(width: 8),
                Text(isEditing ? '编辑客观项目' : '新建客观项目'),
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
                      labelText: '名称 / 标题 / 目标 (必填)',
                      hintText: '例: 《流浪地球2》/ 边城 / 川湘阁',
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('分类:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                      InkWell(
                        onTap: _showAddCategoryDialog,
                        child: const Text('+ 自定义分类', style: TextStyle(color: Color(0xFF10B981), fontSize: 12, fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  DropdownButtonFormField<String>(
                    initialValue: selectedCategory,
                    decoration: const InputDecoration(border: OutlineInputBorder()),
                    items: categories.map((c) => DropdownMenuItem(value: c.name, child: Text(c.name))).toList(),
                    onChanged: (val) {
                      if (val != null) setModalState(() => selectedCategory = val);
                    },
                  ),
                  const SizedBox(height: 14),

                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('星级评分 (1-5分):', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                          Text('⭐ ${rating.toStringAsFixed(1)} 分', style: const TextStyle(color: Colors.amber, fontWeight: FontWeight.bold, fontSize: 14)),
                        ],
                      ),
                      Slider(
                        value: rating,
                        min: 1.0,
                        max: 5.0,
                        divisions: 8,
                        activeColor: Colors.amber,
                        inactiveColor: Colors.amber.withAlpha(50),
                        label: '${rating.toStringAsFixed(1)}分',
                        onChanged: (val) {
                          setModalState(() => rating = val);
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),

                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('相关图片/剧照 (已选 ${images.length}/3 张):', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                      if (images.length < 3)
                        TextButton.icon(
                          onPressed: pickImage,
                          icon: const Icon(Icons.add_a_photo, size: 16),
                          label: const Text('添加照片'),
                          style: TextButton.styleFrom(foregroundColor: const Color(0xFF10B981)),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (images.isNotEmpty)
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: images.map((path) {
                        return Stack(
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(10),
                              child: Image.file(
                                File(path),
                                width: 70,
                                height: 70,
                                fit: BoxFit.cover,
                                errorBuilder: (ctx, err, stack) => Container(
                                  width: 70,
                                  height: 70,
                                  color: Colors.white10,
                                  child: const Icon(Icons.broken_image, color: Colors.grey),
                                ),
                              ),
                            ),
                            Positioned(
                              top: 2,
                              right: 2,
                              child: GestureDetector(
                                onTap: () {
                                  setModalState(() => images.remove(path));
                                },
                                child: Container(
                                  decoration: const BoxDecoration(color: Colors.black87, shape: BoxShape.circle),
                                  child: const Icon(Icons.close, color: Colors.white, size: 16),
                                ),
                              ),
                            ),
                          ],
                        );
                      }).toList(),
                    ),
                  const SizedBox(height: 14),

                  TextField(
                    controller: addressController,
                    decoration: const InputDecoration(labelText: '位置 / 平台 / 来源说明'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: notesController,
                    decoration: const InputDecoration(labelText: '特色说明 / 推荐好菜 / 备忘'),
                    maxLines: 2,
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () {
                  nameController.dispose();
                  addressController.dispose();
                  notesController.dispose();
                  Navigator.of(dialogCtx).pop();
                },
                child: const Text('取消'),
              ),
              ElevatedButton(
                onPressed: () {
                  final name = nameController.text.trim();
                  if (name.isEmpty) {
                    ScaffoldMessenger.of(dialogCtx).showSnackBar(
                      const SnackBar(content: Text('名称不能为空')),
                    );
                    return;
                  }

                  if (isEditing) {
                    final updated = storeToEdit.copyWith(
                      name: name,
                      category: selectedCategory,
                      rating: rating,
                      images: images,
                      address: addressController.text.trim(),
                      notes: notesController.text.trim(),
                    );
                    context.read<StoreProvider>().updateStoreItem(updated);
                  } else {
                    context.read<StoreProvider>().addStoreItem(
                          name: name,
                          category: selectedCategory,
                          rating: rating,
                          images: images,
                          address: addressController.text.trim(),
                          notes: notesController.text.trim(),
                        );
                  }

                  nameController.dispose();
                  addressController.dispose();
                  notesController.dispose();
                  Navigator.of(dialogCtx).pop();
                },
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF10B981), foregroundColor: Colors.white),
                child: Text(isEditing ? '保存修改' : '创建项目'),
              ),
            ],
          );
        },
      ),
    );
  }

  // ⚡ 分钟级打卡履约弹窗 (录入消费金额 + 多选参与成员 + 精确到分钟时刻)
  void _showCheckinDialog(StoreItem store) {
    final costController = TextEditingController();
    final memoController = TextEditingController();
    final members = context.read<ChoreProvider>().members;

    DateTime selectedDateTime = DateTime.now(); // 默认精准当前时刻 yyyy-MM-dd HH:mm
    final List<Member> selectedMembers = [];
    if (members.isNotEmpty) {
      selectedMembers.add(members.first);
    }

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (dialogCtx, setModalState) {
          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: Row(
              children: [
                const Icon(Icons.flash_on, color: Color(0xFF10B981)),
                const SizedBox(width: 8),
                Text('打卡: ${store.name}'),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: costController,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      labelText: '本次打卡消费金额',
                      hintText: '例: 45 元 (不涉及消费可留空或填 0)',
                      prefixIcon: Icon(Icons.attach_money),
                      border: OutlineInputBorder(),
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

                  TextField(
                    controller: memoController,
                    decoration: const InputDecoration(
                      labelText: '打卡心得 / 体验感受 / 点的菜品',
                      border: OutlineInputBorder(),
                    ),
                    maxLines: 2,
                  ),
                  const SizedBox(height: 12),

                  // 分钟级时间选择器 (默认当前时刻 yyyy-MM-dd HH:mm)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.access_time_filled, color: Color(0xFF10B981)),
                    title: Text(
                      '打卡时刻: ${DateFormat('yyyy-MM-dd HH:mm').format(selectedDateTime)}',
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                    ),
                    subtitle: const Text('默认当前时刻，可选历史时刻', style: TextStyle(fontSize: 11, color: Colors.white54)),
                    trailing: TextButton(
                      child: const Text('更改时刻'),
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
                  final cost = double.tryParse(costController.text);
                  final vIds = selectedMembers.map((m) => m.id ?? 0).toList();
                  final vNames = selectedMembers.map((m) => m.name).toList();

                  context.read<StoreProvider>().recordStoreCheckin(
                        storeId: store.id!,
                        storeName: store.name,
                        cost: cost,
                        visitorIds: vIds,
                        visitorNames: vNames.isNotEmpty ? vNames : ['自己'],
                        memo: memoController.text.trim(),
                        targetDate: selectedDateTime,
                      );

                  costController.dispose();
                  memoController.dispose();
                  Navigator.of(dialogCtx).pop();

                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('已完成【${store.name}】打卡记录！'), backgroundColor: const Color(0xFF10B981)),
                  );
                },
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF10B981), foregroundColor: Colors.white),
                child: const Text('提交打卡'),
              ),
            ],
          );
        },
      ),
    );
  }

  void _confirmDeleteStore(StoreItem store) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('确认删除记录: ${store.name}?'),
        content: const Text('删除后该条打卡历史及照片关联将被安全移除。'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('取消')),
          ElevatedButton(
            onPressed: () {
              context.read<StoreProvider>().deleteStoreItem(store.id!);
              Navigator.of(ctx).pop();
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('已删除: ${store.name}')));
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
    final storeProvider = context.watch<StoreProvider>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('生活记录'),
        actions: [
          IconButton(
            icon: Icon(storeProvider.isCardView ? Icons.view_headline : Icons.grid_view),
            tooltip: storeProvider.isCardView ? '切换为紧凑列表模式' : '切换为 Card 卡片模式',
            onPressed: () => storeProvider.toggleViewMode(),
          ),
          IconButton(
            icon: const Icon(Icons.add_circle_outline),
            tooltip: '新建打卡记录',
            onPressed: () => _showStoreFormDialog(),
          ),
        ],
      ),
      drawer: Drawer(
        backgroundColor: const Color(0xFF0F172A),
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white.withAlpha(10),
                  border: const Border(bottom: BorderSide(color: Colors.white12)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.category, color: Color(0xFF10B981), size: 24),
                    const SizedBox(width: 10),
                    const Text('生活分类管理', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.add, color: Color(0xFF10B981)),
                      tooltip: '添加分类',
                      onPressed: _showAddCategoryDialog,
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  children: [
                    ListTile(
                      leading: const Icon(Icons.grid_view, color: Colors.white70),
                      title: const Text('全部分类', style: TextStyle(color: Colors.white)),
                      selected: storeProvider.selectedCategory == '全部分类',
                      selectedTileColor: const Color(0xFF10B981).withAlpha(40),
                      onTap: () {
                        storeProvider.selectCategory('全部分类');
                        Navigator.of(context).pop();
                      },
                    ),
                    ...storeProvider.categories.map((c) {
                      final isSelected = storeProvider.selectedCategory == c.name;
                      return ListTile(
                        leading: const Icon(Icons.label_outline, color: Color(0xFF10B981)),
                        title: Text(c.name, style: const TextStyle(color: Colors.white)),
                        selected: isSelected,
                        selectedTileColor: const Color(0xFF10B981).withAlpha(40),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.edit_outlined, color: Colors.white54, size: 18),
                              onPressed: () => _showEditCategoryDialog(c),
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 18),
                              onPressed: () => _confirmDeleteCategory(c),
                            ),
                          ],
                        ),
                        onTap: () {
                          storeProvider.selectCategory(c.name);
                          Navigator.of(context).pop();
                        },
                      );
                    }),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      body: SafeArea(
        child: Stack(
          children: [
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
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        FilterChip(
                          label: const Text('全部分类'),
                          selected: storeProvider.selectedCategory == '全部分类',
                          onSelected: (_) => storeProvider.selectCategory('全部分类'),
                        ),
                        const SizedBox(width: 8),
                        ...storeProvider.categories.map((c) {
                          final isSelected = storeProvider.selectedCategory == c.name;
                          return Padding(
                            padding: const EdgeInsets.only(right: 8.0),
                            child: FilterChip(
                              label: Text(c.name),
                              selected: isSelected,
                              selectedColor: const Color(0xFF10B981).withAlpha(80),
                              onSelected: (_) => storeProvider.selectCategory(c.name),
                            ),
                          );
                        }),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  storeProvider.filteredStoreItems.isEmpty
                      ? _buildEmptyStoreCard()
                      : ListView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: storeProvider.filteredStoreItems.length,
                          itemBuilder: (context, index) {
                            final store = storeProvider.filteredStoreItems[index];
                            final checkinCount = storeProvider.getCheckinCountForStore(store.id!);
                            final totalCost = storeProvider.getTotalCostForStore(store.id!);

                            return storeProvider.isCardView
                                ? _buildStoreGlassCard(store, checkinCount, totalCost)
                                : _buildStoreCompactListItem(store, checkinCount, totalCost);
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

  // Card 模式 (支持点击翻转/跳转至独立 StoreDetailScreen 详情页)
  Widget _buildStoreGlassCard(StoreItem store, int checkinCount, double totalCost) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14.0),
      child: _buildGlassCard(
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => StoreDetailScreen(storeItem: store)),
            );
          },
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF10B981).withAlpha(40),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(store.category, style: const TextStyle(fontSize: 11, color: Color(0xFF10B981), fontWeight: FontWeight.bold)),
                              ),
                              const SizedBox(width: 8),
                              Flexible(
                                child: Text(
                                  store.name,
                                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Row(
                                children: List.generate(5, (sIdx) {
                                  return Icon(
                                    sIdx < store.rating.floor() ? Icons.star : Icons.star_border,
                                    color: Colors.amber,
                                    size: 16,
                                  );
                                }),
                              ),
                              const SizedBox(width: 6),
                              Text(store.rating.toStringAsFixed(1), style: const TextStyle(color: Colors.amber, fontWeight: FontWeight.bold, fontSize: 13)),
                            ],
                          ),
                        ],
                      ),
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.edit_outlined, color: Colors.lightBlueAccent, size: 18),
                          onPressed: () => _showStoreFormDialog(storeToEdit: store),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 18),
                          onPressed: () => _confirmDeleteStore(store),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 10),

                if (store.images.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10.0),
                    child: SizedBox(
                      height: 80,
                      child: ListView.builder(
                        scrollDirection: Axis.horizontal,
                        itemCount: store.images.length,
                        itemBuilder: (ctx, iIdx) {
                          return Padding(
                            padding: const EdgeInsets.only(right: 8.0),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(10),
                              child: Image.file(
                                File(store.images[iIdx]),
                                width: 100,
                                height: 80,
                                fit: BoxFit.cover,
                                errorBuilder: (c, e, s) => Container(
                                  width: 100,
                                  height: 80,
                                  color: Colors.white10,
                                  child: const Icon(Icons.image, color: Colors.white38),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),

                if (store.address != null && store.address!.isNotEmpty)
                  Text('📍 ${store.address}', style: const TextStyle(fontSize: 12, color: Colors.white70)),
                if (store.notes != null && store.notes!.isNotEmpty)
                  Text('📝 ${store.notes}', style: const TextStyle(fontSize: 12, color: Colors.white54, fontStyle: FontStyle.italic)),

                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('累计打卡: $checkinCount 次', style: const TextStyle(fontSize: 12, color: Colors.white54)),
                        Text('累计消费: ¥${totalCost.toStringAsFixed(1)}', style: const TextStyle(fontSize: 12, color: Color(0xFF10B981), fontWeight: FontWeight.bold)),
                      ],
                    ),
                    ElevatedButton.icon(
                      onPressed: () => _showCheckinDialog(store),
                      icon: const Icon(Icons.flash_on, size: 14),
                      label: const Text('记一次打卡', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF10B981),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // 紧凑列表模式项 (支持点击跳转至独立 StoreDetailScreen 详情页)
  Widget _buildStoreCompactListItem(StoreItem store, int checkinCount, double totalCost) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: _buildGlassCard(
        child: ListTile(
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => StoreDetailScreen(storeItem: store)),
            );
          },
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          leading: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.amber.withAlpha(30),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.amber.withAlpha(80)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.star, color: Colors.amber, size: 14),
                const SizedBox(width: 2),
                Text(store.rating.toStringAsFixed(1), style: const TextStyle(color: Colors.amber, fontSize: 11, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(color: const Color(0xFF10B981).withAlpha(40), borderRadius: BorderRadius.circular(6)),
                child: Text(store.category, style: const TextStyle(fontSize: 10, color: Color(0xFF10B981), fontWeight: FontWeight.bold)),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  store.name,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.white),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          subtitle: Text(
            '累计 $checkinCount 次 · 总消费 ¥${totalCost.toStringAsFixed(1)}',
            style: const TextStyle(fontSize: 11, color: Colors.white54),
            overflow: TextOverflow.ellipsis,
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                padding: const EdgeInsets.all(4),
                constraints: const BoxConstraints(),
                icon: const Icon(Icons.flash_on, color: Color(0xFF10B981), size: 20),
                tooltip: '一键打卡',
                onPressed: () => _showCheckinDialog(store),
              ),
              IconButton(
                padding: const EdgeInsets.all(4),
                constraints: const BoxConstraints(),
                icon: const Icon(Icons.edit_outlined, color: Colors.lightBlueAccent, size: 18),
                onPressed: () => _showStoreFormDialog(storeToEdit: store),
              ),
              IconButton(
                padding: const EdgeInsets.all(4),
                constraints: const BoxConstraints(),
                icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 18),
                onPressed: () => _confirmDeleteStore(store),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyStoreCard() {
    return _buildGlassCard(
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Row(
          children: [
            const Icon(Icons.auto_awesome, color: Colors.white38, size: 36),
            const SizedBox(width: 12),
            const Expanded(
              child: Text('暂无生活打卡记录，点击右上角【+】新建第一个打卡项目吧！', style: TextStyle(color: Colors.white70, fontSize: 13)),
            ),
            ElevatedButton(
              onPressed: () => _showStoreFormDialog(),
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF10B981), foregroundColor: Colors.white),
              child: const Text('新建打卡'),
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
