import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../domain/store_models.dart';
import '../domain/life_templates.dart';
import '../providers/store_provider.dart';
import '../../../core/cache/cache_manager.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/network/tmdb_client.dart';
import '../../../core/settings/settings_button.dart';
import '../../../core/settings/settings_provider.dart';
import '../../../core/utils/map_launcher.dart';
import '../../../core/utils/location_picker.dart';
import 'store_detail_screen.dart';
import 'store_checkin_dialog.dart';
import 'template_gallery.dart';
import 'template_field_widget.dart';

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
    String selectedTemplateKey = category.templateKey;
    final List<Map<String, dynamic>> extraFields = List.from(category.extraFields);

    const typeLabels = {
      'text': '文本',
      'multiline': '多行文本',
      'number': '数字',
      'choice': '单选',
      'date': '日期',
      'image': '单张图片',
      'images': '图片集',
      'switchField': '开关',
      'tags': '标签',
    };

    Future<void> addField(void Function(void Function()) setModalState) async {
      final labelC = TextEditingController();
      String fieldType = 'text';
      await showDialog(
        context: context,
        builder: (fc) => StatefulBuilder(
          builder: (fctx, fset) => AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: const Text('添加自定义字段'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: labelC,
                  decoration: const InputDecoration(labelText: '字段名称', hintText: '例: 产地 / 口味 / 座次'),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: fieldType,
                  decoration: const InputDecoration(labelText: '字段类型', border: OutlineInputBorder()),
                  items: typeLabels.entries
                      .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value)))
                      .toList(),
                  onChanged: (v) {
                    if (v != null) fset(() => fieldType = v);
                  },
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () {
                  labelC.dispose();
                  Navigator.of(fctx).pop();
                },
                child: const Text('取消'),
              ),
              ElevatedButton(
                onPressed: () {
                  final label = labelC.text.trim();
                  if (label.isEmpty) {
                    ScaffoldMessenger.of(fctx).showSnackBar(
                      const SnackBar(content: Text('字段名称不能为空')),
                    );
                    return;
                  }
                  setModalState(() {
                    extraFields.add({
                      'key': 'custom_${extraFields.length + 1}',
                      'label': label,
                      'type': fieldType,
                      'hint': '',
                      'required': false,
                    });
                  });
                  labelC.dispose();
                  Navigator.of(fctx).pop();
                },
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF10B981), foregroundColor: Colors.white),
                child: const Text('添加'),
              ),
            ],
          ),
        ),
      );
    }

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (dialogCtx, setModalState) {
          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: Text('编辑分类: ${category.name}'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: catController,
                    decoration: const InputDecoration(labelText: '新分类名称'),
                  ),
                  const SizedBox(height: 14),
                  const Text('绑定模板:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  const SizedBox(height: 6),
                  DropdownButtonFormField<String>(
                    initialValue: selectedTemplateKey,
                    decoration: const InputDecoration(border: OutlineInputBorder()),
                    items: LifeTemplates.all
                        .map((t) => DropdownMenuItem(value: t.key, child: Text(t.name)))
                        .toList(),
                    onChanged: (v) {
                      if (v != null) setModalState(() => selectedTemplateKey = v);
                    },
                  ),
                  const SizedBox(height: 14),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '自定义字段 (${extraFields.length}):',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                      TextButton.icon(
                        onPressed: () => addField(setModalState),
                        icon: const Icon(Icons.add, size: 16),
                        label: const Text('添加字段'),
                        style: TextButton.styleFrom(foregroundColor: const Color(0xFF10B981)),
                      ),
                    ],
                  ),
                  if (extraFields.isEmpty)
                    const Text('暂无自定义字段，点"添加字段"为这个分类增加专属字段', style: TextStyle(fontSize: 12, color: Colors.white54)),
                  ...extraFields.map((f) {
                    final key = f['key'] as String? ?? '';
                    final label = f['label'] as String? ?? '';
                    final type = f['type'] as String? ?? 'text';
                    return ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.drag_indicator, color: Colors.white38, size: 18),
                      title: Text(label, style: const TextStyle(fontSize: 13, color: Colors.white)),
                      subtitle: Text(typeLabels[type] ?? type, style: const TextStyle(fontSize: 11, color: Colors.white54)),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 18),
                        onPressed: () => setModalState(() => extraFields.removeWhere((x) => x['key'] == key)),
                      ),
                    );
                  }),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () {
                catController.dispose();
                Navigator.of(dialogCtx).pop();
              }, child: const Text('取消')),
              ElevatedButton(
                onPressed: () {
                  final newName = catController.text.trim();
                  if (newName.isNotEmpty) {
                    context.read<StoreProvider>().updateCategory(
                          category.id!,
                          newName,
                          category.name,
                          templateKey: selectedTemplateKey,
                          extraFields: extraFields,
                        );
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('已更新分类: $newName')),
                    );
                  }
                  catController.dispose();
                  Navigator.of(dialogCtx).pop();
                },
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF10B981), foregroundColor: Colors.white),
                child: const Text('保存修改'),
              ),
            ],
          );
        },
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
  void _showStoreFormDialog({StoreItem? storeToEdit, String? initialTemplateKey}) {
    final isEditing = storeToEdit != null;
    final nameController = TextEditingController(text: storeToEdit?.name ?? '');
    final addressController = TextEditingController(text: storeToEdit?.address ?? '');
    final notesController = TextEditingController(text: storeToEdit?.notes ?? '');

    double rating = storeToEdit?.rating ?? 5.0;
    // 餐饮位置：地图定位选点进行中标志
    var locating = false;
    final List<String> images = List.from(storeToEdit?.images ?? []);
    final Map<String, dynamic> extrasValues = Map<String, dynamic>.from(storeToEdit?.extras ?? {});
    // 通用模板：表单内自由追加的自定义字段（仅本次新建/编辑生效）
    final List<TemplateField> formCustomFields = <TemplateField>[];

    // 餐饮菜单：新建/编辑时维护的本地草稿（新建保存后回填 storeId）
    final List<StoreMenuItem> menuDrafts = <StoreMenuItem>[];
    if (isEditing) {
      final editId = storeToEdit.id;
      if (editId != null) {
        menuDrafts.addAll(
          context.read<StoreProvider>().getMenuItemsForStore(editId),
        );
      }
    }

    final categories = context.read<StoreProvider>().categories;
    String selectedCategory = storeToEdit?.category ?? (categories.isNotEmpty ? categories.first.name : '餐饮美食');

    // 初始模板：编辑按分类模板；新建优先画廊选择，其次按分类名称匹配
    String currentTemplateKey;
    StoreCategory? catOf(String name) {
      for (final c in categories) {
        if (c.name == name) return c;
      }
      return null;
    }
    if (isEditing) {
      currentTemplateKey = catOf(selectedCategory)?.templateKey ?? LifeTemplates.matchTemplateKey(selectedCategory);
    } else if (initialTemplateKey != null) {
      // 画廊选择优先：若存在绑定了该模板的分类则自动选中，保证展示与落库一致
      StoreCategory? match;
      for (final c in categories) {
        if (c.templateKey == initialTemplateKey) {
          match = c;
          break;
        }
      }
      if (match != null) {
        selectedCategory = match.name;
        currentTemplateKey = match.templateKey;
      } else {
        currentTemplateKey = initialTemplateKey;
      }
    } else {
      currentTemplateKey = catOf(selectedCategory)?.templateKey ?? LifeTemplates.matchTemplateKey(selectedCategory);
    }

    // 旧数据迁移：影视模板的 type 字段拆分为 媒体类型(mediaType) + 题材(genre)
    if (currentTemplateKey == 'movie' && isEditing) {
      final legacyType = extrasValues['type']?.toString() ?? '';
      if (legacyType.isNotEmpty) {
        if (extrasValues['mediaType'] == null && kMovieMediaTypeOptions.contains(legacyType)) {
          extrasValues['mediaType'] = legacyType;
        } else if (extrasValues['genre'] == null && kMovieGenreOptions.contains(legacyType)) {
          extrasValues['genre'] = legacyType;
        } else if (extrasValues['mediaType'] == null && extrasValues['genre'] == null) {
          // 未知值兜底：当作题材保留，媒体类型走默认“电影”
          extrasValues['genre'] = legacyType;
        }
        extrasValues.remove('type');
      }
    }

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (dialogCtx, setModalState) {
          // 以 currentTemplateKey 为准：画廊选择优先于分类绑定，切换分类时再同步
          final LifeTemplate tpl = LifeTemplates.byKey(currentTemplateKey);
          List<TemplateField> customFields = [];
          final currentCat = catOf(selectedCategory);
          if (currentCat != null) {
            customFields = currentCat.extraFields
                .map((m) => TemplateField.fromJson(m))
                .toList();
          }
          final mergedFields = [...tpl.itemFields, ...customFields];

    // 观看平台：历史已用值自动成为快捷选项
    final platformHistory = <String>[];
    for (final it in context.read<StoreProvider>().storeItems) {
      final v = it.extras['platform'];
      if (v == null) continue;
      final list = v is List
          ? v.map((e) => e.toString()).toList()
          : [v.toString()];
      for (final s in list) {
        if (s.isNotEmpty && !platformHistory.contains(s)) {
          platformHistory.add(s);
        }
      }
    }
    final formFields = mergedFields
        .map((f) => f.key == 'platform'
            ? TemplateField(
                key: f.key,
                label: f.label,
                type: f.type,
                hint: f.hint,
                required: f.required,
                options: f.options,
                defaultValue: f.defaultValue,
                suggestions: platformHistory,
              )
            : f)
        .toList();
          final nameLabel = tpl.itemNameLabel.isEmpty ? '名称' : tpl.itemNameLabel;

          Future<void> searchTmdbAndFill() async {
            final settings = context.read<SettingsProvider>();
            if (!settings.tmdbEnabled) {
              ScaffoldMessenger.of(dialogCtx).showSnackBar(
                const SnackBar(content: Text('请先在设置中心填入 TMDB API Key')),
              );
              return;
            }
            final query = nameController.text.trim();
            if (query.isEmpty) {
              ScaffoldMessenger.of(dialogCtx).showSnackBar(
                const SnackBar(content: Text('先输入片名再搜索')),
              );
              return;
            }
            final client = TmdbClient(settings.tmdbApiKey);
            try {
              // 电影 + 电视剧/综艺 合并搜索，任一失败不影响另一类
              final results = <TmdbMovie>[];
              String? searchError;
              try {
                results.addAll(await client.searchMovies(query));
              } catch (e) {
                searchError = e.toString();
              }
              try {
                results.addAll(await client.searchTv(query));
              } catch (e) {
                searchError = e.toString();
              }
              if (!dialogCtx.mounted) return;
              if (results.isEmpty) {
                ScaffoldMessenger.of(dialogCtx).showSnackBar(
                  SnackBar(
                    content: Text(searchError == null ? 'TMDB 未找到相关影片/剧集' : 'TMDB 搜索失败: $searchError'),
                    backgroundColor: Colors.redAccent,
                  ),
                );
                return;
              }
              final selected = await showDialog<TmdbMovie>(
                context: dialogCtx,
                builder: (sc) => SimpleDialog(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                  title: const Text('选择影片/剧集（数据来源 TMDB）'),
                  children: results
                      .map((m) => SimpleDialogOption(
                            onPressed: () => Navigator.of(sc).pop(m),
                            child: Text(
                              '${m.isTv ? "📺" : "🎬"} ${m.title}${m.year != null ? ' (${m.year})' : ''}${m.isTv ? ' 电视剧/综艺' : ' 电影'}',
                              style: const TextStyle(fontSize: 14),
                            ),
                          ))
                      .toList(),
                ),
              );
              if (selected == null || !dialogCtx.mounted) return;
              final details = selected.isTv
                  ? await client.tvDetails(selected.id)
                  : await client.movieDetails(selected.id);
              if (!dialogCtx.mounted) return;
              setModalState(() {
                nameController.text = details.title;
                extrasValues['year'] = details.year?.toString() ?? '';
                extrasValues['director'] = (details.directors + details.cast).join(' / ');
                extrasValues['duration'] = details.runtime;
                extrasValues['mediaType'] = details.isTv ? '电视剧' : '电影';
                extrasValues['genre'] = details.genres.isNotEmpty ? details.genres.first : '';
                extrasValues['synopsis'] = details.overview ?? '';
                if (details.totalEpisodes != null) {
                  extrasValues['totalEpisodes'] = details.totalEpisodes;
                }
              });
              if (details.posterFullUrl.isNotEmpty) {
                try {
                  final dir = await CacheManager.instance.tmdbDir();
                  final posterPath = await client.downloadPoster(
                    details.posterFullUrl,
                    cacheDir: dir.path,
                  );
                  if (dialogCtx.mounted) {
                    setModalState(() {
                      if (images.length < 3) images.add(posterPath);
                    });
                  }
                } catch (_) {}
              }
              if (dialogCtx.mounted) {
                ScaffoldMessenger.of(dialogCtx).showSnackBar(
                  SnackBar(content: Text('已从 TMDB 导入: ${details.title}'), backgroundColor: const Color(0xFF10B981)),
                );
              }
            } catch (e) {
              if (!dialogCtx.mounted) return;
              final err = e.toString();
              final isNetIssue = err.contains('SocketException') ||
                  err.contains('ClientException') ||
                  err.contains('Failed host lookup') ||
                  err.contains('Connection');
              ScaffoldMessenger.of(dialogCtx).showSnackBar(
                SnackBar(
                  content: Text(
                    isNetIssue
                        ? '网络无法访问 TMDB 服务：请检查手机网络/代理/VPN（themoviedb.org 部分地区需要代理）'
                        : 'TMDB 导入失败: $e',
                  ),
                  backgroundColor: Colors.redAccent,
                ),
              );
            }
          }

          Future<void> pickImage() async {
            if (images.length >= 3) {
              ScaffoldMessenger.of(dialogCtx).showSnackBar(
                const SnackBar(content: Text('至多上传 3 张照片/剧照/海报')),
              );
              return;
            }
            try {
              final quality = context.read<SettingsProvider>().imageQuality;
              final XFile? image = await _picker.pickImage(source: ImageSource.gallery, imageQuality: quality);
              if (!dialogCtx.mounted) return;
              if (image != null) {
                final saved = await CacheManager.instance.copyToCache(image.path);
                setModalState(() {
                  images.add(saved);
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
                Flexible(
                  child: Text(
                    isEditing ? '编辑项目' : '新建·${tpl.name}',
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
                  TextField(
                    controller: nameController,
                    decoration: InputDecoration(
                      labelText: '$nameLabel (必填)',
                      hintText: tpl.itemNameHint,
                      hintStyle: AppTheme.hintStyle,
                      suffixIcon: (tpl.key == 'movie' && context.read<SettingsProvider>().tmdbEnabled)
                          ? IconButton(
                              icon: const Icon(Icons.search, color: Color(0xFF10B981)),
                              tooltip: '从 TMDB 导入',
                              onPressed: searchTmdbAndFill,
                            )
                          : null,
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
                      if (val != null) {
                        setModalState(() {
                          selectedCategory = val;
                          final cat = catOf(val);
                          if (cat != null) currentTemplateKey = cat.templateKey;
                        });
                      }
                    },
                  ),
                  if (tpl.key != 'generic' || customFields.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: const Color(0xFF10B981).withAlpha(25),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFF10B981).withAlpha(60)),
                      ),
                      child: Text(
                        '模板: ${tpl.name}${tpl.key == 'movie' ? ' · 支持 TMDB 导入' : ''}',
                        style: const TextStyle(fontSize: 11, color: Color(0xFF10B981), fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                  const SizedBox(height: 14),

                  // 模板专属字段（动态渲染）
                  ...formFields.map((f) => Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: TemplateFieldWidget(
                          field: f,
                          value: extrasValues[f.key],
                          onChanged: (v) => setModalState(() => extrasValues[f.key] = v),
                        ),
                      )),

                  // 通用模板：支持在表单内自由追加自定义字段
                  if (tpl.key == 'generic') ...[
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Text(
                          '自定义字段 (${formCustomFields.length})',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                        ),
                        const Spacer(),
                        TextButton.icon(
                          onPressed: () => _addFormCustomField(dialogCtx, setModalState, formCustomFields, extrasValues),
                          icon: const Icon(Icons.add, size: 16),
                          label: const Text('添加字段'),
                          style: TextButton.styleFrom(foregroundColor: const Color(0xFF10B981)),
                        ),
                      ],
                    ),
                    if (formCustomFields.isEmpty)
                      const Padding(
                        padding: EdgeInsets.only(bottom: 10),
                        child: Text(
                          '通用模板暂无固定字段，可点「添加字段」自由记录想记的内容',
                          style: TextStyle(fontSize: 11, color: Colors.white54),
                        ),
                      ),
                    ...formCustomFields.map((f) => Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: TemplateFieldWidget(
                                  field: f,
                                  value: extrasValues[f.key],
                                  onChanged: (v) => setModalState(() => extrasValues[f.key] = v),
                                ),
                              ),
                              IconButton(
                                padding: const EdgeInsets.all(2),
                                constraints: const BoxConstraints(),
                                icon: const Icon(Icons.close, color: Colors.white38, size: 16),
                                tooltip: '移除该字段',
                                onPressed: () => setModalState(() {
                                  formCustomFields.remove(f);
                                  extrasValues.remove(f.key);
                                }),
                              ),
                            ],
                          ),
                        )),
                  ],

                  // 餐饮菜单：新增/维护固定菜品与价格
                  if (tpl.key == 'dining') ...[
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Text(
                          '菜单 (${menuDrafts.length})',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                        ),
                        const Spacer(),
                        TextButton.icon(
                          onPressed: () => _showMenuItemDialog(dialogCtx, setModalState, menuDrafts),
                          icon: const Icon(Icons.add, size: 16),
                          label: const Text('添加菜品'),
                          style: TextButton.styleFrom(foregroundColor: const Color(0xFF10B981)),
                        ),
                      ],
                    ),
                    const Padding(
                      padding: EdgeInsets.only(bottom: 6),
                      child: Text(
                        '菜品打分：👍 推荐招牌菜 · 👎 不推荐 · 未点即一般（浏览卡片小字展示）',
                        style: TextStyle(fontSize: 11, color: Colors.white54),
                      ),
                    ),
                    if (menuDrafts.isEmpty)
                      const Padding(
                        padding: EdgeInsets.only(bottom: 10),
                        child: Text(
                          '还没有菜单，点「添加菜品」录入固定菜品和价格；之后打卡时选菜即可自动统计消费',
                          style: TextStyle(fontSize: 11, color: Colors.white54),
                        ),
                      ),
                    ...menuDrafts.map((item) => Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: Colors.white.withAlpha(10),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.white.withAlpha(20)),
                            ),
                            child: Row(
                              children: [
                                if (item.imagePath != null && item.imagePath!.isNotEmpty)
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(8),
                                    child: Image.file(
                                      File(item.imagePath!),
                                      width: 44,
                                      height: 44,
                                      fit: BoxFit.cover,
                                      errorBuilder: (c, e, s) => Container(
                                        width: 44,
                                        height: 44,
                                        color: Colors.white10,
                                        child: const Icon(Icons.restaurant, color: Colors.white38, size: 20),
                                      ),
                                    ),
                                  )
                                else
                                  Container(
                                    width: 44,
                                    height: 44,
                                    decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(8)),
                                    child: const Icon(Icons.restaurant_menu, color: Colors.white38, size: 20),
                                  ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(item.name, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                                      const SizedBox(height: 2),
                                      if (item.specs.isEmpty)
                                        Text(
                                          '¥${_fmtPrice(item.price)}',
                                          style: const TextStyle(fontSize: 12, color: Color(0xFF10B981), fontWeight: FontWeight.bold),
                                        )
                                      else
                                        Text(
                                          item.specs.map((s) => '${s.name} ¥${_fmtPrice(s.price)}').join(' · '),
                                          style: const TextStyle(fontSize: 11, color: Color(0xFF10B981), fontWeight: FontWeight.bold),
                                        ),
                                    ],
                                  ),
                                ),
                                IconButton(
                                  padding: const EdgeInsets.all(4),
                                  constraints: const BoxConstraints(),
                                  icon: Icon(
                                    item.rating == 1 ? Icons.thumb_up : Icons.thumb_up_outlined,
                                    color: item.rating == 1 ? const Color(0xFF10B981) : Colors.white38,
                                    size: 18,
                                  ),
                                  tooltip: item.rating == 1 ? '取消推荐招牌菜' : '设为推荐招牌菜',
                                  onPressed: () => setModalState(() {
                                    final idx = menuDrafts.indexWhere((x) => identical(x, item) || x.id == item.id);
                                    if (idx != -1) {
                                      menuDrafts[idx] = item.copyWith(rating: item.rating == 1 ? 0 : 1);
                                    }
                                  }),
                                ),
                                IconButton(
                                  padding: const EdgeInsets.all(4),
                                  constraints: const BoxConstraints(),
                                  icon: Icon(
                                    item.rating == -1 ? Icons.thumb_down : Icons.thumb_down_outlined,
                                    color: item.rating == -1 ? Colors.redAccent : Colors.white38,
                                    size: 18,
                                  ),
                                  tooltip: item.rating == -1 ? '取消不推荐' : '设为不推荐',
                                  onPressed: () => setModalState(() {
                                    final idx = menuDrafts.indexWhere((x) => identical(x, item) || x.id == item.id);
                                    if (idx != -1) {
                                      menuDrafts[idx] = item.copyWith(rating: item.rating == -1 ? 0 : -1);
                                    }
                                  }),
                                ),
                                IconButton(
                                  padding: const EdgeInsets.all(4),
                                  constraints: const BoxConstraints(),
                                  icon: const Icon(Icons.edit_outlined, color: Colors.lightBlueAccent, size: 18),
                                  tooltip: '编辑菜品',
                                  onPressed: () => _showMenuItemDialog(dialogCtx, setModalState, menuDrafts, existing: item),
                                ),
                                IconButton(
                                  padding: const EdgeInsets.all(4),
                                  constraints: const BoxConstraints(),
                                  icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 18),
                                  tooltip: '删除菜品',
                                  onPressed: () => setModalState(() {
                                    menuDrafts.removeWhere((x) => identical(x, item) || x.id == item.id);
                                  }),
                                ),
                              ],
                            ),
                          ),
                        )),
                  ],

                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            tpl.key == 'snack' ? '好吃程度 (1-5分):' : '星级评分 (1-5分):',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                          ),
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

                  if (tpl.key != 'movie') ...[
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: TextField(
                            controller: addressController,
                            decoration: InputDecoration(
                              labelText: tpl.key == 'dining' ? '位置' : '位置 / 平台 / 来源说明',
                              hintText: tpl.key == 'dining' ? '例: 解放路 88 号（可手动填写，或点右侧定位自动获取）' : null,
                              hintStyle: AppTheme.hintStyle,
                            ),
                          ),
                        ),
                        if (tpl.key == 'dining') ...[
                          const SizedBox(width: 8),
                          IconButton(
                            onPressed: locating
                                ? null
                                : () async {
                                    setModalState(() => locating = true);
                                    try {
                                      final result = await pickCurrentLocation();
                                      if (!dialogCtx.mounted) return;
                                      if (result == null) {
                                        ScaffoldMessenger.of(dialogCtx).showSnackBar(
                                          const SnackBar(content: Text('定位失败：请检查定位权限或 GPS 开关后重试')),
                                        );
                                      } else {
                                        addressController.text = result;
                                        ScaffoldMessenger.of(dialogCtx).showSnackBar(
                                          const SnackBar(content: Text('已获取当前定位并自动填写，可手动修改')),
                                        );
                                      }
                                    } finally {
                                      if (dialogCtx.mounted) {
                                        setModalState(() => locating = false);
                                      }
                                    }
                                  },
                            icon: locating
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF10B981)),
                                  )
                                : const Icon(Icons.my_location, color: Color(0xFF10B981)),
                            tooltip: '从地图获取当前位置并自动填写',
                            style: IconButton.styleFrom(
                              side: BorderSide(color: const Color(0xFF10B981).withAlpha(80)),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 12),
                  ],
                  TextField(
                    controller: notesController,
                    decoration: InputDecoration(
                      labelText: tpl.key == 'movie' ? '长评 (仅详情页展示)' : '特色说明 / 推荐好菜 / 备忘',
                      hintText: tpl.key == 'movie' ? '写下详细长评，只在详情页展示' : null,
                      hintStyle: AppTheme.hintStyle,
                    ),
                    maxLines: tpl.key == 'movie' ? 4 : 2,
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

                  // 影视默认观看状态（未选择时落库为“想看”）
                  if (tpl.key == 'movie' &&
                      (extrasValues['status']?.toString() ?? '').isEmpty) {
                    extrasValues['status'] = '想看';
                  }

                  if (isEditing) {
                    final updated = storeToEdit.copyWith(
                      name: name,
                      category: selectedCategory,
                      rating: rating,
                      images: images,
                      address: tpl.key == 'movie'
                          ? (storeToEdit.address ?? '')
                          : addressController.text.trim(),
                      notes: notesController.text.trim(),
                      extras: extrasValues,
                    );
                    context.read<StoreProvider>()
                        .updateStoreItem(updated, menuItems: menuDrafts);
                  } else {
                    context.read<StoreProvider>().addStoreItem(
                          name: name,
                          category: selectedCategory,
                          rating: rating,
                          images: images,
                          address: tpl.key == 'movie'
                              ? ''
                              : addressController.text.trim(),
                          notes: notesController.text.trim(),
                          extras: extrasValues,
                          menuItems: menuDrafts,
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

  /// 通用模板：在表单内追加一个自定义字段（字段名 + 类型）
  Future<void> _addFormCustomField(
    BuildContext dialogCtx,
    void Function(void Function()) setModalState,
    List<TemplateField> formCustomFields,
    Map<String, dynamic> extrasValues,
  ) async {
    final labelC = TextEditingController();
    String fieldType = 'text';
    await showDialog(
      context: dialogCtx,
      builder: (fc) => StatefulBuilder(
        builder: (fctx, fset) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text('添加自定义字段'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: labelC,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: '字段名称',
                  hintText: '例如: 产地 / 口味 / 座位号',
                  hintStyle: AppTheme.hintStyle,
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: fieldType,
                decoration: const InputDecoration(labelText: '字段类型', border: OutlineInputBorder()),
                items: const [
                  DropdownMenuItem(value: 'text', child: Text('文本')),
                  DropdownMenuItem(value: 'multiline', child: Text('多行文本')),
                  DropdownMenuItem(value: 'number', child: Text('数字')),
                  DropdownMenuItem(value: 'date', child: Text('日期')),
                  DropdownMenuItem(value: 'tags', child: Text('标签')),
                ],
                onChanged: (v) {
                  if (v != null) fset(() => fieldType = v);
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                labelC.dispose();
                Navigator.of(fc).pop();
              },
              child: const Text('取消'),
            ),
            ElevatedButton(
              onPressed: () {
                final label = labelC.text.trim();
                if (label.isEmpty) {
                  ScaffoldMessenger.of(fc).showSnackBar(
                    const SnackBar(content: Text('字段名称不能为空')),
                  );
                  return;
                }
                final key = 'custom_${DateTime.now().millisecondsSinceEpoch}';
                setModalState(() {
                  formCustomFields.add(TemplateField(
                    key: key,
                    label: label,
                    type: TemplateFieldType.values.firstWhere(
                      (t) => t.name == fieldType,
                      orElse: () => TemplateFieldType.text,
                    ),
                  ));
                  extrasValues[key] = '';
                });
                labelC.dispose();
                Navigator.of(fc).pop();
              },
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF10B981), foregroundColor: Colors.white),
              child: const Text('添加'),
            ),
          ],
        ),
      ),
    );
  }

  /// 金额格式化：整数不带小数，非整数保留 1 位小数
  String _fmtPrice(double v) {
    if (v == v.roundToDouble()) {
      return v.toStringAsFixed(0);
    }
    return v.toStringAsFixed(1);
  }

  /// 餐饮菜单：添加 / 编辑菜品弹窗（菜名 + 固定价格 + 可选份量规格 + 可选图片，图片写入应用缓存）
  Future<void> _showMenuItemDialog(
    BuildContext dialogCtx,
    void Function(void Function()) setModalState,
    List<StoreMenuItem> menuDrafts, {
    StoreMenuItem? existing,
  }) async {
    final nameController = TextEditingController(text: existing?.name ?? '');
    final priceController = TextEditingController(
      text: existing == null ? '' : _fmtPrice(existing.price),
    );
    String? imagePath = existing?.imagePath;
    // 份量规格：规格名 + 价格 成对编辑，可自由添加/删除
    final List<TextEditingController> specNameControllers = [];
    final List<TextEditingController> specPriceControllers = [];
    for (final s in existing?.specs ?? const <MenuItemSpec>[]) {
      specNameControllers.add(TextEditingController(text: s.name));
      specPriceControllers.add(TextEditingController(text: _fmtPrice(s.price)));
    }

    await showDialog(
      context: dialogCtx,
      builder: (menuCtx) => StatefulBuilder(
        builder: (mctx, mset) {
          Future<void> pickMenuImage() async {
            try {
              final quality = context.read<SettingsProvider>().imageQuality;
              final XFile? image = await _picker.pickImage(
                source: ImageSource.gallery,
                imageQuality: quality,
              );
              if (!mctx.mounted) return;
              if (image != null) {
                final saved = await CacheManager.instance.copyToCache(image.path);
                mset(() => imagePath = saved);
              }
            } catch (e) {
              if (!mctx.mounted) return;
              ScaffoldMessenger.of(mctx).showSnackBar(
                SnackBar(content: Text('选择图片失败: $e')),
              );
            }
          }

          void removeSpecRow(int index) {
            mset(() {
              specNameControllers[index].dispose();
              specPriceControllers[index].dispose();
              specNameControllers.removeAt(index);
              specPriceControllers.removeAt(index);
            });
          }

          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: Text(existing == null ? '添加菜品' : '编辑菜品'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: nameController,
                    autofocus: true,
                    decoration: const InputDecoration(
                      labelText: '菜名',
                      hintText: '例如: 招牌红烧肉 / 冰美式',
                      hintStyle: AppTheme.hintStyle,
                      prefixIcon: Icon(Icons.restaurant_menu),
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: priceController,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      labelText: '固定价格 (元)',
                      hintText: '例如: 38',
                      hintStyle: AppTheme.hintStyle,
                      prefixIcon: Icon(Icons.attach_money),
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      const Text('份量规格 (可选)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                      const Spacer(),
                      TextButton.icon(
                        onPressed: () => mset(() {
                          specNameControllers.add(TextEditingController());
                          specPriceControllers.add(TextEditingController());
                        }),
                        icon: const Icon(Icons.add, size: 16),
                        label: const Text('添加规格'),
                        style: TextButton.styleFrom(foregroundColor: const Color(0xFF10B981)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  const Text('例如: 大份 / 小份、一两 / 二两 / 三两，各对应不同价格', style: TextStyle(fontSize: 11, color: Colors.white54)),
                  const SizedBox(height: 8),
                  if (specNameControllers.isEmpty)
                    const Padding(
                      padding: EdgeInsets.only(bottom: 8),
                      child: Text('未添加规格时，打卡按固定价格计价', style: TextStyle(fontSize: 11, color: Colors.white38)),
                    ),
                  ...List.generate(specNameControllers.length, (i) => Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(
                          children: [
                            Expanded(
                              flex: 3,
                              child: TextField(
                                controller: specNameControllers[i],
                                decoration: const InputDecoration(
                                  labelText: '规格名',
                                  hintText: '例如: 大份 / 二两',
                                  hintStyle: AppTheme.hintStyle,
                                  isDense: true,
                                  border: OutlineInputBorder(),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              flex: 2,
                              child: TextField(
                                controller: specPriceControllers[i],
                                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                decoration: const InputDecoration(
                                  labelText: '价格 (元)',
                                  hintText: '例如: 42',
                                  hintStyle: AppTheme.hintStyle,
                                  isDense: true,
                                  border: OutlineInputBorder(),
                                ),
                              ),
                            ),
                            IconButton(
                              onPressed: () => removeSpecRow(i),
                              icon: const Icon(Icons.remove_circle_outline, color: Colors.redAccent, size: 18),
                              tooltip: '删除该规格',
                            ),
                          ],
                        ),
                      )),
                  const SizedBox(height: 16),
                  const Text('菜品图片 (可选，计入缓存):', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      if (imagePath != null && imagePath!.isNotEmpty)
                        ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: Image.file(
                            File(imagePath!),
                            width: 64,
                            height: 64,
                            fit: BoxFit.cover,
                            errorBuilder: (c, e, s) => Container(
                              width: 64,
                              height: 64,
                              color: Colors.white10,
                              child: const Icon(Icons.broken_image, color: Colors.grey),
                            ),
                          ),
                        )
                      else
                        Container(
                          width: 64,
                          height: 64,
                          decoration: BoxDecoration(
                            color: Colors.white10,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(Icons.restaurant_menu, color: Colors.grey, size: 28),
                        ),
                      const SizedBox(width: 12),
                      TextButton.icon(
                        onPressed: pickMenuImage,
                        icon: const Icon(Icons.add_a_photo, size: 16),
                        label: Text(imagePath == null ? '上传图片' : '更换图片'),
                        style: TextButton.styleFrom(foregroundColor: const Color(0xFF10B981)),
                      ),
                      if (imagePath != null && imagePath!.isNotEmpty)
                        TextButton.icon(
                          onPressed: () => mset(() => imagePath = null),
                          icon: const Icon(Icons.delete_outline, size: 16),
                          label: const Text('移除'),
                          style: TextButton.styleFrom(foregroundColor: Colors.redAccent),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () {
                  nameController.dispose();
                  priceController.dispose();
                  for (final c in specNameControllers) {
                    c.dispose();
                  }
                  for (final c in specPriceControllers) {
                    c.dispose();
                  }
                  Navigator.of(mctx).pop();
                },
                child: const Text('取消'),
              ),
              ElevatedButton(
                onPressed: () {
                  final name = nameController.text.trim();
                  final priceText = priceController.text.trim();
                  final price = double.tryParse(priceText);
                  if (name.isEmpty) {
                    ScaffoldMessenger.of(mctx).showSnackBar(
                      const SnackBar(content: Text('菜名不能为空')),
                    );
                    return;
                  }
                  if (priceText.isEmpty || price == null || price < 0) {
                    ScaffoldMessenger.of(mctx).showSnackBar(
                      const SnackBar(content: Text('请输入有效的价格 (大于等于 0)')),
                    );
                    return;
                  }
                  // 收集份量规格并校验
                  final specs = <MenuItemSpec>[];
                  for (var i = 0; i < specNameControllers.length; i++) {
                    final sName = specNameControllers[i].text.trim();
                    final sPrice = double.tryParse(specPriceControllers[i].text.trim());
                    if (sName.isEmpty || sPrice == null || sPrice < 0) {
                      ScaffoldMessenger.of(mctx).showSnackBar(
                        const SnackBar(content: Text('请完整填写每个规格的名称与价格 (大于等于 0)，或删除空行')),
                      );
                      return;
                    }
                    specs.add(MenuItemSpec(name: sName, price: sPrice));
                  }
                  setModalState(() {
                    if (existing == null) {
                      menuDrafts.add(StoreMenuItem(
                        name: name,
                        price: price,
                        imagePath: imagePath,
                        specs: specs,
                        sortOrder: menuDrafts.length,
                      ));
                    } else {
                      final idx = menuDrafts
                          .indexWhere((x) => identical(x, existing) || x.id == existing.id);
                      if (idx != -1) {
                        menuDrafts[idx] = StoreMenuItem(
                          id: existing.id,
                          storeId: existing.storeId,
                          name: name,
                          price: price,
                          imagePath: imagePath,
                          specs: specs,
                          sortOrder: existing.sortOrder,
                          createdAt: existing.createdAt,
                        );
                      }
                    }
                  });
                  nameController.dispose();
                  priceController.dispose();
                  for (final c in specNameControllers) {
                    c.dispose();
                  }
                  for (final c in specPriceControllers) {
                    c.dispose();
                  }
                  Navigator.of(mctx).pop();
                },
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF10B981), foregroundColor: Colors.white),
                child: const Text('保存'),
              ),
            ],
          );
        },
      ),
    );
  }

  // ⚡ 分钟级打卡履约弹窗 (录入消费金额 + 多选参与成员 + 精确到分钟时刻)
  void _showCheckinDialog(StoreItem store) {
    showDialog(
      context: context,
      builder: (ctx) => StoreCheckinDialog(store: store),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final storeProvider = context.watch<StoreProvider>();
    // 当前分类对应的模板 key（用于影视状态筛选显示）
    String? currentTplKey;
    if (storeProvider.selectedCategory != '全部分类') {
      for (final c in storeProvider.categories) {
        if (c.name == storeProvider.selectedCategory) {
          currentTplKey = c.templateKey;
          break;
        }
      }
    }

    // 影视二级筛选选项（媒体类型 / 题材 / 上映年份，按现有数据动态生成）
    final mediaTypeOptions = <String>[];
    final genreOptions = <String>[];
    final yearOptions = <String>[];
    for (final it in storeProvider.storeItems) {
      if (LifeTemplates.matchTemplateKey(it.category) != 'movie') continue;
      final mt = resolveMediaType(it.extras);
      if (!mediaTypeOptions.contains(mt)) mediaTypeOptions.add(mt);
      final g = it.extras['genre']?.toString() ?? '';
      if (g.isNotEmpty && !genreOptions.contains(g)) genreOptions.add(g);
      final y = it.extras['year']?.toString() ?? '';
      if (y.isNotEmpty && int.tryParse(y) != null && !yearOptions.contains(y)) {
        yearOptions.add(y);
      }
    }
    mediaTypeOptions.sort(
      (a, b) => kMovieMediaTypeOptions.indexOf(a).compareTo(kMovieMediaTypeOptions.indexOf(b)),
    );
    genreOptions.sort(
      (a, b) => kMovieGenreOptions.indexOf(a).compareTo(kMovieGenreOptions.indexOf(b)),
    );
    yearOptions.sort((a, b) => int.parse(b).compareTo(int.parse(a)));
    final shownYears = yearOptions.take(4).toList();
    // 零食二级筛选选项（预设分类兜底 + 数据中实际使用过的分类）
    final snackTagOptions = <String>[];
    for (final it in storeProvider.storeItems) {
      if (LifeTemplates.matchTemplateKey(it.category) != 'snack') continue;
      final t = it.extras['snackTag']?.toString() ?? '';
      if (t.isNotEmpty && !snackTagOptions.contains(t)) snackTagOptions.add(t);
    }
    snackTagOptions.sort((a, b) {
      final ia = kSnackTagOptions.indexOf(a);
      final ib = kSnackTagOptions.indexOf(b);
      if (ia == -1 && ib == -1) return a.compareTo(b);
      if (ia == -1) return 1;
      if (ib == -1) return -1;
      return ia.compareTo(ib);
    });
    final hasOlderYears = yearOptions.length > shownYears.length;
    if (shownYears.isNotEmpty) {
      storeProvider.setEarliestShownYear(int.parse(shownYears.last));
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('生活记录'),
        actions: [
          const SettingsButton(),
          IconButton(
            icon: Icon(storeProvider.isCardView ? Icons.view_headline : Icons.grid_view),
            tooltip: storeProvider.isCardView ? '切换为紧凑列表模式' : '切换为 Card 卡片模式',
            onPressed: () => storeProvider.toggleViewMode(),
          ),
          IconButton(
            icon: const Icon(Icons.add_circle_outline),
            tooltip: '新建打卡记录',
            onPressed: () async {
              final key = await TemplateGallerySheet.show(context);
              if (key != null) _showStoreFormDialog(initialTemplateKey: key);
            },
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
                  if (currentTplKey == 'movie') ...[
                    const SizedBox(height: 8),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          FilterChip(
                            label: const Text('全部状态'),
                            selected: storeProvider.selectedStatus == '全部状态',
                            onSelected: (_) => storeProvider.selectStatus('全部状态'),
                          ),
                          ...kMovieStatusOptions.map((s) => Padding(
                                padding: const EdgeInsets.only(left: 6),
                                child: FilterChip(
                                  label: Text(s),
                                  selected: storeProvider.selectedStatus == s,
                                  selectedColor: const Color(0xFF6366F1).withAlpha(90),
                                  onSelected: (_) => storeProvider.selectStatus(s),
                                ),
                              )),
                        ],
                      ),
                    ),
                  ],
                  if (currentTplKey == 'movie') ...[
                    // 媒体类型筛选
                    const SizedBox(height: 8),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          FilterChip(
                            label: const Text('全部媒体类型'),
                            selected: storeProvider.selectedMediaType == '全部媒体类型',
                            onSelected: (_) => storeProvider.selectMediaType('全部媒体类型'),
                          ),
                          ...mediaTypeOptions.map((t) => Padding(
                                padding: const EdgeInsets.only(left: 6),
                                child: FilterChip(
                                  label: Text(t),
                                  selected: storeProvider.selectedMediaType == t,
                                  selectedColor: const Color(0xFF10B981).withAlpha(90),
                                  onSelected: (_) => storeProvider.selectMediaType(t),
                                ),
                              )),
                        ],
                      ),
                    ),
                    // 题材筛选
                    const SizedBox(height: 8),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          FilterChip(
                            label: const Text('全部题材'),
                            selected: storeProvider.selectedGenre == '全部题材',
                            onSelected: (_) => storeProvider.selectGenre('全部题材'),
                          ),
                          ...genreOptions.map((t) => Padding(
                                padding: const EdgeInsets.only(left: 6),
                                child: FilterChip(
                                  label: Text(t),
                                  selected: storeProvider.selectedGenre == t,
                                  selectedColor: const Color(0xFF6366F1).withAlpha(90),
                                  onSelected: (_) => storeProvider.selectGenre(t),
                                ),
                              )),
                        ],
                      ),
                    ),
                    // 上映年份筛选
                    const SizedBox(height: 8),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          FilterChip(
                            label: const Text('全部年份'),
                            selected: storeProvider.selectedYear == '全部年份',
                            onSelected: (_) => storeProvider.selectYear('全部年份'),
                          ),
                          ...shownYears.map((y) => Padding(
                                padding: const EdgeInsets.only(left: 6),
                                child: FilterChip(
                                  label: Text(y),
                                  selected: storeProvider.selectedYear == y,
                                  selectedColor: Colors.amber.withAlpha(70),
                                  onSelected: (_) => storeProvider.selectYear(y),
                                ),
                              )),
                          if (hasOlderYears)
                            Padding(
                              padding: const EdgeInsets.only(left: 6),
                              child: FilterChip(
                                label: const Text('更早'),
                                selected: storeProvider.selectedYear == '更早',
                                selectedColor: Colors.amber.withAlpha(70),
                                onSelected: (_) => storeProvider.selectYear('更早'),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                  if (currentTplKey == 'snack') ...[
                    // 零食分类二级筛选
                    const SizedBox(height: 8),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          FilterChip(
                            label: const Text('全部零食分类'),
                            selected: storeProvider.selectedSnackTag == '全部零食分类',
                            onSelected: (_) => storeProvider.selectSnackTag('全部零食分类'),
                          ),
                          ...snackTagOptions.map((t) => Padding(
                                padding: const EdgeInsets.only(left: 6),
                                child: FilterChip(
                                  label: Text(t),
                                  selected: storeProvider.selectedSnackTag == t,
                                  selectedColor: const Color(0xFFF59E0B).withAlpha(80),
                                  onSelected: (_) => storeProvider.selectSnackTag(t),
                                ),
                              )),
                        ],
                      ),
                    ),
                  ],
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
    final moviePlatforms = _platformsOf(store);
    final snackTag = store.extras['snackTag']?.toString() ?? '';
    final snackPrices = _snackPricesOf(store);
    final snackComment = store.extras['comment']?.toString() ?? '';
    return Padding(
      padding: const EdgeInsets.only(bottom: 14.0),
      child: _buildGlassCard(
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () async {
            final result = await Navigator.of(context).push<String>(
              MaterialPageRoute(builder: (_) => StoreDetailScreen(storeItem: store)),
            );
            if (result == 'edit' && context.mounted) {
              _showStoreFormDialog(storeToEdit: store);
            }
          },
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (LifeTemplates.matchTemplateKey(store.category) == 'movie' && store.images.isNotEmpty) ...[
                  // 影视：海报左（2:3 竖版）+ 文字右
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.file(
                          File(store.images.first),
                          width: 60,
                          height: 90,
                          fit: BoxFit.cover,
                          errorBuilder: (c, e, s) => Container(
                            width: 60,
                            height: 90,
                            color: Colors.white10,
                            child: const Icon(Icons.movie_outlined, color: Colors.white38),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF10B981).withAlpha(40),
                                    borderRadius: BorderRadius.circular(7),
                                  ),
                                  child: Text(store.category, style: const TextStyle(fontSize: 10, color: Color(0xFF10B981), fontWeight: FontWeight.bold)),
                                ),
                                const SizedBox(width: 5),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: Colors.indigo.withAlpha(50),
                                    borderRadius: BorderRadius.circular(7),
                                  ),
                                  child: Text(
                                    resolveMediaType(store.extras) == '电影'
                                        ? '🎬 电影'
                                        : '📺 ${resolveMediaType(store.extras)}',
                                    style: const TextStyle(fontSize: 9, color: Colors.lightBlueAccent, fontWeight: FontWeight.bold),
                                  ),
                                ),
                                if ((store.extras['status']?.toString() ?? '').isNotEmpty) ...[
                                  const SizedBox(width: 5),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: _movieStatusColor(store.extras['status'].toString()).withAlpha(45),
                                      borderRadius: BorderRadius.circular(7),
                                      border: Border.all(color: _movieStatusColor(store.extras['status'].toString()).withAlpha(110)),
                                    ),
                                    child: Text(
                                      store.extras['status'].toString(),
                                      style: TextStyle(fontSize: 9, color: _movieStatusColor(store.extras['status'].toString()), fontWeight: FontWeight.bold),
                                    ),
                                  ),
                                ],
                                if (resolveGenre(store.extras).isNotEmpty) ...[
                                  const SizedBox(width: 5),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: Colors.purple.withAlpha(50),
                                      borderRadius: BorderRadius.circular(7),
                                      border: Border.all(color: Colors.purpleAccent.withAlpha(90)),
                                    ),
                                    child: Text(
                                      resolveGenre(store.extras),
                                      style: const TextStyle(fontSize: 9, color: Colors.purpleAccent, fontWeight: FontWeight.bold),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                            const SizedBox(height: 6),
                            Text(
                              store.name,
                              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 6),
                            Row(
                              children: [
                                Row(
                                  children: List.generate(5, (sIdx) {
                                    return Icon(
                                      sIdx < store.rating.floor() ? Icons.star : Icons.star_border,
                                      color: Colors.amber,
                                      size: 14,
                                    );
                                  }),
                                ),
                                const SizedBox(width: 5),
                                Text(store.rating.toStringAsFixed(1), style: const TextStyle(color: Colors.amber, fontWeight: FontWeight.bold, fontSize: 12)),
                              ],
                            ),
                            if (_isSerialItem(store)) ...[
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  Text(
                                    '📺 观看进度 ${_watchedEpisodesOf(store)}/${_totalEpisodesOf(store) ?? '?'} 集',
                                    style: const TextStyle(fontSize: 11, color: Colors.lightBlueAccent, fontWeight: FontWeight.bold),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 5),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(3),
                                child: LinearProgressIndicator(
                                  value: (_totalEpisodesOf(store) ?? 0) > 0
                                      ? (_watchedEpisodesOf(store) / _totalEpisodesOf(store)!).clamp(0.0, 1.0)
                                      : 0,
                                  minHeight: 5,
                                  backgroundColor: Colors.white12,
                                  valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF06B6D4)),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ] else ...[
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
                                if (LifeTemplates.matchTemplateKey(store.category) == 'movie') ...[
                                  const SizedBox(width: 6),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: Colors.indigo.withAlpha(50),
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(color: Colors.indigoAccent.withAlpha(90)),
                                    ),
                                    child: Text(
                                      resolveMediaType(store.extras) == '电影'
                                          ? '🎬 电影'
                                          : '📺 ${resolveMediaType(store.extras)}',
                                      style: const TextStyle(fontSize: 10, color: Colors.lightBlueAccent, fontWeight: FontWeight.bold),
                                    ),
                                  ),
                                  if (resolveGenre(store.extras).isNotEmpty) ...[
                                    const SizedBox(width: 6),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: Colors.purple.withAlpha(50),
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(color: Colors.purpleAccent.withAlpha(90)),
                                      ),
                                      child: Text(
                                        resolveGenre(store.extras),
                                        style: const TextStyle(fontSize: 10, color: Colors.purpleAccent, fontWeight: FontWeight.bold),
                                      ),
                                    ),
                                  ],
                                ],
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
                ],

                if (_storeExtraSummary(store).isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(
                      _storeExtraSummary(store),
                      style: const TextStyle(fontSize: 12, color: Color(0xFF06B6D4), fontWeight: FontWeight.w600),
                    ),
                  ),
                if (_isMovieItem(store)) ...[
                  // 影视：卡片展示观看平台 + 一句话点评（短评），长评只在详情页
                  if (moviePlatforms.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text(
                        '▶ ${moviePlatforms.join(' · ')}',
                        style: const TextStyle(fontSize: 12, color: Colors.lightBlueAccent, fontWeight: FontWeight.w600),
                      ),
                    ),
                  if ((store.extras['reason']?.toString() ?? '').isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text(
                        '💬 ${store.extras['reason']}',
                        style: const TextStyle(fontSize: 12, color: Colors.white70),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ] else if (_isSnackItem(store)) ...[
                  // 零食：分类标签 + 多平台参考价 + 试吃点评
                  if (snackTag.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: Text(
                        '🏷️ $snackTag',
                        style: const TextStyle(fontSize: 12, color: Color(0xFFF59E0B), fontWeight: FontWeight.w600),
                      ),
                    ),
                  if (snackPrices.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: Text(
                        '💰 ${snackPrices.join(' · ')}',
                        style: const TextStyle(fontSize: 12, color: Colors.white70, fontWeight: FontWeight.w500),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  if (snackComment.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: Text(
                        '💬 $snackComment',
                        style: const TextStyle(fontSize: 12, color: Colors.white54, fontStyle: FontStyle.italic),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ] else if (_isDiningItem(store)) ...[
                  // 餐饮：位置（点击打开地图）+ 结算平台
                  if (store.address != null && store.address!.isNotEmpty)
                    GestureDetector(
                      onTap: () => launchMapForPlace(context, store.address!),
                      child: Row(
                        children: [
                          const Icon(Icons.place_outlined, color: Color(0xFF10B981), size: 15),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              '${store.address}',
                              style: const TextStyle(fontSize: 12, color: Colors.white70),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const Icon(Icons.open_in_new, color: Colors.white38, size: 12),
                        ],
                      ),
                    ),
                  if (_platformsOf(store).isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: Text(
                        '🛵 ${_platformsOf(store).join(' · ')}',
                        style: const TextStyle(fontSize: 12, color: Colors.lightBlueAccent, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ..._dishPickWidgets(store),
                  if (store.notes != null && store.notes!.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: Text(
                        '📝 ${store.notes}',
                        style: const TextStyle(fontSize: 12, color: Colors.white54, fontStyle: FontStyle.italic),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ] else ...[
                  if (store.address != null && store.address!.isNotEmpty)
                    Text('📍 ${store.address}', style: const TextStyle(fontSize: 12, color: Colors.white70)),
                  if (store.notes != null && store.notes!.isNotEmpty)
                    Text('📝 ${store.notes}', style: const TextStyle(fontSize: 12, color: Colors.white54, fontStyle: FontStyle.italic)),
                ],

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
          onTap: () async {
            final result = await Navigator.of(context).push<String>(
              MaterialPageRoute(builder: (_) => StoreDetailScreen(storeItem: store)),
            );
            if (result == 'edit' && context.mounted) {
              _showStoreFormDialog(storeToEdit: store);
            }
          },
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          leading: LifeTemplates.matchTemplateKey(store.category) == 'movie' && store.images.isNotEmpty
              ? ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Image.file(
                    File(store.images.first),
                    width: 44,
                    height: 66,
                    fit: BoxFit.cover,
                    errorBuilder: (c, e, s) => Container(
                      width: 44,
                      height: 66,
                      color: Colors.white10,
                      child: const Icon(Icons.movie_outlined, color: Colors.white38, size: 20),
                    ),
                  ),
                )
              : Container(
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
              if (LifeTemplates.matchTemplateKey(store.category) == 'movie') ...[
                const SizedBox(width: 5),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  decoration: BoxDecoration(
                    color: Colors.indigo.withAlpha(50),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    resolveMediaType(store.extras) == '电影' ? '🎬 电影' : '📺 ${resolveMediaType(store.extras)}',
                    style: const TextStyle(fontSize: 9, color: Colors.lightBlueAccent, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
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
          subtitle: _isMovieItem(store)
              ? Text(
                  _isSerialItem(store)
                      ? '${store.extras['status'] ?? '想看'} · 📺 $_watchedEpisodesOf(store)/${_totalEpisodesOf(store) ?? '?'} 集 · 打卡 $checkinCount 次'
                      : '${store.extras['status'] ?? '想看'} · 打卡 $checkinCount 次',
                  style: const TextStyle(fontSize: 11, color: Colors.white54),
                  overflow: TextOverflow.ellipsis,
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '累计 $checkinCount 次 · 总消费 ¥${totalCost.toStringAsFixed(1)}',
                      style: const TextStyle(fontSize: 11, color: Colors.white54),
                      overflow: TextOverflow.ellipsis,
                    ),
                    ..._dishPickWidgets(store),
                  ],
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
              onPressed: () async {
                final key = await TemplateGallerySheet.show(context);
                if (key != null) _showStoreFormDialog(initialTemplateKey: key);
              },
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF10B981), foregroundColor: Colors.white),
              child: const Text('新建打卡'),
            ),
          ],
        ),
      ),
    );
  }

  /// 卡片上的模板字段摘要（导演/年份、招牌菜、作者等）
  String _storeExtraSummary(StoreItem store) {
    if (store.extras.isEmpty) return '';
    final tpl = LifeTemplates.byKey(LifeTemplates.matchTemplateKey(store.category));
    const priority = ['director', 'year', 'genre', 'signature', 'author', 'bestSeason', 'brand', 'sku'];
    final parts = <String>[];
    for (final k in priority) {
      final v = store.extras[k];
      if (v != null && v.toString().isNotEmpty) {
        parts.add(v.toString());
      }
    }
    if (parts.isEmpty) {
      for (final f in tpl.itemFields) {
        final v = store.extras[f.key];
        if (v != null && v.toString().isNotEmpty) {
          parts.add('${f.label}: $v');
          break;
        }
      }
    }
    return parts.take(2).join(' · ');
  }

  /// 影视观看进度与状态辅助
  bool _isMovieItem(StoreItem store) =>
      LifeTemplates.matchTemplateKey(store.category) == 'movie';

  bool _isDiningItem(StoreItem store) =>
      LifeTemplates.matchTemplateKey(store.category) == 'dining';

  bool _isSnackItem(StoreItem store) =>
      LifeTemplates.matchTemplateKey(store.category) == 'snack';

  /// 零食多平台参考价（仅展示已填写的平台）
  List<String> _snackPricesOf(StoreItem store) {
    final parts = <String>[];
    void add(String label, String key) {
      final v = store.extras[key];
      if (v != null && v.toString().trim().isNotEmpty) {
        parts.add('$label ¥${v.toString().trim()}');
      }
    }

    add('淘宝', 'priceTb');
    add('京东', 'priceJd');
    add('实体店', 'priceStore');
    return parts;
  }

  /// 观看平台：兼容多选 List 与旧版单值 String
  List<String> _platformsOf(StoreItem store) {
    final v = store.extras['platform'];
    if (v == null) return const [];
    final list = v is List
        ? v.map((e) => e.toString()).where((e) => e.isNotEmpty).toList()
        : [v.toString()];
    return list;
  }

  /// 餐饮卡片小字：👍 推荐招牌菜 / 👎 不推荐（未点即一般）
  List<Widget> _dishPickWidgets(StoreItem store) {
    final menus = context.read<StoreProvider>().getMenuItemsForStore(store.id ?? 0);
    final liked = menus.where((m) => m.rating == 1).map((m) => m.name).toList();
    final disliked = menus.where((m) => m.rating == -1).map((m) => m.name).toList();
    return [
      if (liked.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 3),
          child: Text(
            '👍 ${liked.join(' · ')}',
            style: const TextStyle(fontSize: 12, color: Color(0xFF10B981), fontWeight: FontWeight.w600),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      if (disliked.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 3),
          child: Text(
            '👎 ${disliked.join(' · ')}',
            style: const TextStyle(fontSize: 12, color: Colors.redAccent, fontWeight: FontWeight.w500),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
    ];
  }

  int _watchedEpisodesOf(StoreItem store) {
    final v = store.extras['watchedEpisodes'];
    return (v is num) ? v.toInt() : 0;
  }

  int? _totalEpisodesOf(StoreItem store) {
    final v = store.extras['totalEpisodes'];
    return (v is num) ? v.toInt() : null;
  }

  bool _isSerialItem(StoreItem store) =>
      _isMovieItem(store) && resolveMediaType(store.extras) != '电影';

  Color _movieStatusColor(String status) {
    switch (status) {
      case '在追':
        return const Color(0xFF10B981);
      case '看完':
        return Colors.amber;
      case '搁置':
        return Colors.grey;
      case '抛弃':
        return Colors.redAccent;
      default:
        return Colors.lightBlueAccent;
    }
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
