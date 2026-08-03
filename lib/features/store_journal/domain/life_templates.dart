import 'dart:convert';

/// 模板字段类型
enum TemplateFieldType {
  text, // 单行文本
  multiline, // 多行文本
  number, // 数字
  rating, // 星级评分（1-5）
  choice, // 单选
  date, // 日期
  image, // 单张图片
  images, // 图片集（最多 3 张）
  switchField, // 开关（是/否）
  tags, // 标签列表
  multiChoice, // 多选列表（如观看平台，可多选）
}

/// 影视一级分类：媒体类型
const List<String> kMovieMediaTypeOptions = [
  '电影', '电视剧', '动漫', '纪录片', '综艺',
];

/// 影视二级分类：题材（TMDB 常用题材，导入时自动落选）
const List<String> kMovieGenreOptions = [
  '动作', '冒险', '动画', '喜剧', '犯罪', '剧情', '家庭', '奇幻', '恐怖',
  '悬疑', '音乐', '爱情', '科幻', '惊悚', '战争', '西部', '真人秀', '脱口秀',
];

/// 影视观看状态：快捷标记 + 筛选
const List<String> kMovieStatusOptions = [
  '想看', '在追', '看完', '搁置', '抛弃',
];

/// 菜篮子：常用计量单位
const List<String> kUnitOptions = ['斤', '500g', '个', '盒', '袋', '把', '瓶', '包', '份'];

/// 菜篮子：购买渠道（多选 + 可自定义新增）
const List<String> kBasketChannelOptions = ['菜市场', '超市', '生鲜电商', '社区团购', '批发市场', '其他'];

/// 从店铺 extras 解析媒体类型（兼容旧字段 type）
String resolveMediaType(Map<String, dynamic> extras) {
  final direct = extras['mediaType']?.toString() ?? '';
  if (direct.isNotEmpty) return direct;
  final legacy = extras['type']?.toString() ?? '';
  if (kMovieMediaTypeOptions.contains(legacy)) return legacy;
  return '电影';
}

/// 从店铺 extras 解析题材（兼容旧字段 type）
String resolveGenre(Map<String, dynamic> extras) {
  final direct = extras['genre']?.toString() ?? '';
  if (direct.isNotEmpty) return direct;
  final legacy = extras['type']?.toString() ?? '';
  if (kMovieGenreOptions.contains(legacy)) return legacy;
  return '';
}

/// 模板字段定义（内建模板字段 + 用户自定义字段共用）
class TemplateField {
  final String key; // 'director' / 'custom_1'
  final String label; // 显示名
  final TemplateFieldType type;
  final String hint;
  final bool required;
  final List<String>? options; // choice 类型用
  final String? defaultValue;
  final List<String>? suggestions; // 历史建议选项（multiChoice 与 options 合并展示，动态生成）

  const TemplateField({
    required this.key,
    required this.label,
    required this.type,
    this.hint = '',
    this.required = false,
    this.options,
    this.defaultValue,
    this.suggestions,
  });

  Map<String, dynamic> toJson() => {
        'key': key,
        'label': label,
        'type': type.name,
        'hint': hint,
        'required': required,
        'options': options,
        'defaultValue': defaultValue,
        'suggestions': suggestions,
      };

  factory TemplateField.fromJson(Map<String, dynamic> json) {
    return TemplateField(
      key: json['key'] as String? ?? '',
      label: json['label'] as String? ?? '',
      type: TemplateFieldType.values.firstWhere(
        (t) => t.name == json['type'],
        orElse: () => TemplateFieldType.text,
      ),
      hint: json['hint'] as String? ?? '',
      required: json['required'] as bool? ?? false,
      options: (json['options'] as List?)?.map((e) => e.toString()).toList(),
      defaultValue: json['defaultValue'] as String?,
      suggestions: (json['suggestions'] as List?)?.map((e) => e.toString()).toList(),
    );
  }
}

/// 生活模板定义：新建项目表单字段 + 打卡表单字段
class LifeTemplate {
  final String key; // 'movie'
  final String name; // '影视观影'
  final String iconName; // 用于模板画廊展示
  final String description;
  final String itemNameLabel; // '片名'
  final String itemNameHint;
  final List<TemplateField> itemFields; // 新建项目字段
  final List<TemplateField> checkinFields; // 打卡字段
  final String imageFieldLabel; // 图片选择区标题（模板专用文案）
  final String notesFieldLabel; // 备注/长评输入框标题（模板专用文案）

  const LifeTemplate({
    required this.key,
    required this.name,
    required this.iconName,
    required this.description,
    required this.itemNameLabel,
    required this.itemNameHint,
    this.itemFields = const [],
    this.checkinFields = const [],
    this.imageFieldLabel = '相关图片',
    this.notesFieldLabel = '备注 / 备忘',
  });
}

/// 内置模板注册表
class LifeTemplates {
  static const List<LifeTemplate> all = [
    LifeTemplate(
      key: 'movie',
      name: '影视观影',
      iconName: 'movie',
      description: '电影 / 电视剧 / 动漫 / 纪录片，支持 TMDB 导入',
      itemNameLabel: '片名',
      itemNameHint: '例: 《流浪地球2》',
      imageFieldLabel: '相关图片/剧照',
      notesFieldLabel: '长评',
      itemFields: [
        TemplateField(key: 'mediaType', label: '媒体类型', type: TemplateFieldType.choice, options: kMovieMediaTypeOptions, defaultValue: '电影'),
        TemplateField(key: 'genre', label: '题材', type: TemplateFieldType.choice, options: kMovieGenreOptions, hint: '可选：科幻 / 动作 / 喜剧…'),
        TemplateField(key: 'year', label: '年份', type: TemplateFieldType.text, hint: '例: 2023'),
        TemplateField(key: 'director', label: '导演 / 主演', type: TemplateFieldType.text, hint: '例: 郭帆 / 吴京'),
        TemplateField(key: 'duration', label: '片长（分钟）', type: TemplateFieldType.number, hint: '例: 173'),
        TemplateField(key: 'status', label: '观看状态', type: TemplateFieldType.choice, options: kMovieStatusOptions, defaultValue: '想看'),
        TemplateField(key: 'platform', label: '观看平台', type: TemplateFieldType.multiChoice, options: ['电影院', '爱奇艺', '腾讯视频', '优酷', 'B站', '芒果TV', 'Netflix', 'Disney+', '其他']),
        TemplateField(key: 'synopsis', label: '剧情简介', type: TemplateFieldType.multiline, hint: '影片剧情梗概（TMDB 导入自动填充）'),
        TemplateField(key: 'reason', label: '一句话点评', type: TemplateFieldType.text, hint: '一句话点评，快速展示在卡片上'),
      ],
      checkinFields: [
        TemplateField(key: 'episodesWatched', label: '本次观看集数', type: TemplateFieldType.number, hint: '电视剧/动漫填本次看了几集，自动累计进度'),
        TemplateField(key: 'channel', label: '观影渠道', type: TemplateFieldType.choice, options: ['影院', '线上平台', 'DVD/下载', '其他']),
        TemplateField(key: 'rewatch', label: '是否二刷', type: TemplateFieldType.switchField),
        TemplateField(key: 'review', label: '观后感', type: TemplateFieldType.multiline, hint: '值得看吗？最打动你的点'),
      ],
    ),
    LifeTemplate(
      key: 'dining',
      name: '餐饮探店',
      iconName: 'restaurant',
      description: '餐厅 / 小吃 / 咖啡甜品 / 日常小店',
      itemNameLabel: '店名',
      itemNameHint: '例: 川湘阁',
      imageFieldLabel: '美食图片',
      notesFieldLabel: '特色说明 / 推荐好菜 / 备忘',
      itemFields: [
        TemplateField(key: 'cuisine', label: '品类', type: TemplateFieldType.choice, options: ['中餐', '西餐', '日料', '火锅', '烧烤', '小吃', '咖啡甜品', '奶茶', '其他']),
        TemplateField(key: 'avgCost', label: '人均参考（元）', type: TemplateFieldType.number, hint: '例: 80'),
        // 招牌推荐菜已改为菜单联动「菜品打分」（菜单项 👍/👎，浏览卡片小字展示）
        TemplateField(key: 'queueTip', label: '排队提示', type: TemplateFieldType.text, hint: '例: 晚饭需等位 40 分钟'),
        TemplateField(key: 'bestTime', label: '最佳时段', type: TemplateFieldType.text, hint: '例: 周二晚 7 点人少'),
        TemplateField(key: 'platform', label: '结算平台', type: TemplateFieldType.multiChoice, options: ['到店堂食', '到店自提', '外卖-美团', '外卖-饿了么', '外卖-京东到家', '外卖-其他', '其他']),
      ],
      checkinFields: [
        TemplateField(key: 'taste', label: '口味评价', type: TemplateFieldType.rating),
        TemplateField(key: 'ambience', label: '环境服务', type: TemplateFieldType.rating),
        TemplateField(key: 'recommend', label: '推荐指数', type: TemplateFieldType.rating),
      ],
    ),
    LifeTemplate(
      key: 'book',
      name: '书籍阅读',
      iconName: 'menu_book',
      description: '小说 / 社科 / 工具书阅读记录',
      itemNameLabel: '书名',
      itemNameHint: '例: 《三体》',
      imageFieldLabel: '书影 / 插图',
      notesFieldLabel: '读书笔记 / 备忘',
      itemFields: [
        TemplateField(key: 'author', label: '作者', type: TemplateFieldType.text, hint: '例: 刘慈欣'),
        TemplateField(key: 'publisher', label: '出版社', type: TemplateFieldType.text),
        TemplateField(key: 'pages', label: '页数', type: TemplateFieldType.number),
        TemplateField(key: 'status', label: '阅读状态', type: TemplateFieldType.choice, options: ['想读', '在读', '读完', '弃读'], defaultValue: '想读'),
        TemplateField(key: 'summary', label: '简介', type: TemplateFieldType.multiline, hint: '一句话介绍这本书'),
      ],
      checkinFields: [
        TemplateField(key: 'progress', label: '阅读进度', type: TemplateFieldType.text, hint: '例: 读到第 180 页 / 43%'),
        TemplateField(key: 'duration', label: '本次阅读时长（分钟）', type: TemplateFieldType.number),
        TemplateField(key: 'note', label: '摘抄 / 感想', type: TemplateFieldType.multiline),
      ],
    ),
    LifeTemplate(
      key: 'place',
      name: '景点游玩',
      iconName: 'landscape',
      description: '景点 / 公园 / 展馆 / 演出',
      itemNameLabel: '地点名称',
      itemNameHint: '例: 西湖',
      imageFieldLabel: '景点照片',
      notesFieldLabel: '游览备忘',
      itemFields: [
        TemplateField(key: 'ticket', label: '门票参考（元）', type: TemplateFieldType.number, hint: '例: 0 免费'),
        TemplateField(key: 'suggestDuration', label: '建议游玩时长', type: TemplateFieldType.text, hint: '例: 半天'),
        TemplateField(key: 'transport', label: '交通方式', type: TemplateFieldType.text, hint: '例: 地铁 1 号线'),
        TemplateField(key: 'bestSeason', label: '最佳季节', type: TemplateFieldType.text, hint: '例: 秋季'),
        TemplateField(key: 'tips', label: '游玩攻略', type: TemplateFieldType.multiline, hint: '注意事项 / 必打卡点'),
      ],
      checkinFields: [
        TemplateField(key: 'hours', label: '游玩时长（小时）', type: TemplateFieldType.number),
        TemplateField(key: 'highlights', label: '亮点项目', type: TemplateFieldType.multiline),
        TemplateField(key: 'feeling', label: '游玩感受', type: TemplateFieldType.multiline),
      ],
    ),
    LifeTemplate(
      key: 'shopping',
      name: '购物好物',
      iconName: 'shopping_bag',
      description: '百货 / 数码 / 生鲜 / 服饰好物',
      itemNameLabel: '商品名称',
      itemNameHint: '例: 无线降噪耳机',
      imageFieldLabel: '商品照片',
      notesFieldLabel: '购物备忘',
      itemFields: [
        TemplateField(key: 'brand', label: '品牌', type: TemplateFieldType.text),
        TemplateField(key: 'sku', label: '规格型号', type: TemplateFieldType.text, hint: '例: 256G 黑色'),
        TemplateField(key: 'refPrice', label: '参考价（元）', type: TemplateFieldType.number),
        TemplateField(key: 'buyReason', label: '购买理由', type: TemplateFieldType.multiline, hint: '为什么想买'),
      ],
      checkinFields: [
        TemplateField(key: 'actualCost', label: '实付金额（元）', type: TemplateFieldType.number),
        TemplateField(key: 'detail', label: '购买明细', type: TemplateFieldType.multiline, hint: '渠道 / 优惠 / 赠品'),
        TemplateField(key: 'experience', label: '使用体验', type: TemplateFieldType.multiline),
      ],
    ),
    LifeTemplate(
      key: 'basket',
      name: '菜篮子',
      iconName: 'basket',
      description: '买菜 / 水果 / 生鲜价格记录，自动生成价格趋势与涨跌对比',
      itemNameLabel: '商品名称',
      itemNameHint: '例: 土豆 / 红富士苹果 / 五花肉',
      imageFieldLabel: '商品图片',
      notesFieldLabel: '备忘',
      itemFields: [
        TemplateField(key: 'basketTag', label: '果蔬分类', type: TemplateFieldType.choice, hint: '自定义下拉，历史值自动成为选项，用于筛选与总表'),
        TemplateField(key: 'unit', label: '单位', type: TemplateFieldType.choice, options: kUnitOptions, hint: '例: 斤 / 500g / 个 / 盒 / 袋'),
        TemplateField(key: 'origin', label: '产地/品牌', type: TemplateFieldType.text, hint: '例: 山东烟台红富士'),
      ],
      checkinFields: [
        TemplateField(key: 'price', label: '单价（元/单位）', type: TemplateFieldType.number, hint: '例: 3.5', required: true),
        TemplateField(key: 'brand', label: '品牌（可自定义）', type: TemplateFieldType.choice, hint: '例: 佳农 / 辉众 / 散装，留空视为通用；同一商品可混记多品牌'),
        TemplateField(key: 'qty', label: '数量', type: TemplateFieldType.number, hint: '例: 2'),
        TemplateField(key: 'channel', label: '购买渠道', type: TemplateFieldType.multiChoice, options: kBasketChannelOptions, hint: '菜市场 / 超市 / 生鲜电商等'),
        TemplateField(key: 'quality', label: '新鲜度/品质', type: TemplateFieldType.rating),
        TemplateField(key: 'note', label: '备注', type: TemplateFieldType.multiline, hint: '新鲜程度 / 大小 / 回购提醒'),
      ],
    ),
    LifeTemplate(
      key: 'snack',
      name: '零食干货',
      iconName: 'snack',
      description: '方便面 / 薯片 / 辣条 / 坚果 / 速食干货',
      itemNameLabel: '零食名称',
      itemNameHint: '例: 康师傅红烧牛肉面',
      imageFieldLabel: '零食图片',
      notesFieldLabel: '备忘 / 点评',
      itemFields: [
        TemplateField(key: 'brand', label: '品牌', type: TemplateFieldType.text, hint: '例: 康师傅 / 卫龙 / 三只松鼠'),
        TemplateField(key: 'snackTag', label: '零食分类', type: TemplateFieldType.choice, hint: '自定义下拉，历史值自动成为选项，可手动新增'),
        TemplateField(key: 'priceTb', label: '淘宝参考价（元）', type: TemplateFieldType.number, hint: '例: 12.9'),
        TemplateField(key: 'priceJd', label: '京东参考价（元）', type: TemplateFieldType.number, hint: '例: 15.5'),
        TemplateField(key: 'priceStore', label: '实体店参考价（元）', type: TemplateFieldType.number, hint: '例: 18'),
        TemplateField(key: 'comment', label: '试吃点评', type: TemplateFieldType.multiline, hint: '口感 / 回购意愿 / 避雷提醒'),
      ],
      checkinFields: [
        TemplateField(key: 'qty', label: '本次购买数量', type: TemplateFieldType.number, hint: '例: 5'),
        TemplateField(key: 'channel', label: '本次购买渠道', type: TemplateFieldType.choice, options: ['淘宝/天猫', '京东', '拼多多', '实体店/超市', '便利店', '其他']),
        TemplateField(key: 'review', label: '本次食用感受', type: TemplateFieldType.multiline, hint: '这次吃的感受 / 囤货备注'),
      ],
    ),
        LifeTemplate(
      key: 'generic',
      name: '通用（自定义）',
      iconName: 'dashboard_customize',
      description: '通用骨架，支持自由追加自定义字段',
      itemNameLabel: '名称',
      itemNameHint: '例: 任何想记录的事',
      itemFields: [],
      checkinFields: [],
    ),
  ];

  static LifeTemplate byKey(String key) {
    return all.firstWhere(
      (t) => t.key == key,
      orElse: () => all.last,
    );
  }

  /// 根据分类名称智能匹配模板（关键词命中，不区分大小写）
  static String matchTemplateKey(String categoryName) {
    final name = categoryName.toLowerCase();
    const rules = <String, List<String>>{
      'movie': ['电影', '影视', '剧', '动漫', '纪录', 'movie', 'film'],
      'dining': ['餐厅', '小吃', '咖啡', '甜品', '小店', '奶茶', '美食', '餐饮', '饭店', '馆', '食堂'],
      'book': ['书', '阅读', '小说', '工具书', 'book'],
      'place': ['景点', '公园', '展馆', '演出', '旅行', '游玩', '旅游', '博物馆'],
      'basket': ['菜篮子', '买菜', '菜价', '果蔬', '蔬菜', '水果', '菜市场', '菜园', 'basket'],
      'shopping': ['购物', '百货', '数码', '生鲜', '服饰', '好物', '家电'],
      'snack': ['零食', '干货', '速食', '方便面', '零嘴', '膨化', '辣条', '坚果', '薯片', 'snack'],
    };
    for (final entry in rules.entries) {
      for (final kw in entry.value) {
        if (name.contains(kw.toLowerCase())) {
          return entry.key;
        }
      }
    }
    return 'generic';
  }

  /// 将 TemplateField 列表编码为 JSON 字符串
  static String encodeFields(List<TemplateField> fields) {
    return jsonEncode(fields.map((f) => f.toJson()).toList());
  }

  /// 解析分类自定义字段 JSON 字符串
  static List<TemplateField> decodeFields(String? jsonStr) {
    if (jsonStr == null || jsonStr.isEmpty) return [];
    try {
      final decoded = jsonDecode(jsonStr);
      if (decoded is List) {
        return decoded
            .whereType<Map>()
            .map((e) => TemplateField.fromJson(Map<String, dynamic>.from(e)))
            .toList();
      }
    } catch (_) {}
    return [];
  }

  /// 合并模板内建字段 + 分类自定义字段（内建在前，自定义在后）
  static List<TemplateField> mergedItemFields(LifeTemplate tpl, List<TemplateField> custom) {
    return [...tpl.itemFields, ...custom];
  }

  static List<TemplateField> mergedCheckinFields(LifeTemplate tpl, List<TemplateField> custom) {
    return [...tpl.checkinFields, ...custom];
  }
}
