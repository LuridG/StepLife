import 'dart:convert';

class StoreCategory {
  final int? id;
  final String name;
  final String iconName;

  StoreCategory({
    this.id,
    required this.name,
    this.iconName = 'storefront',
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'iconName': iconName,
    };
  }

  factory StoreCategory.fromMap(Map<String, dynamic> map) {
    return StoreCategory(
      id: map['id'] as int?,
      name: map['name'] as String,
      iconName: map['iconName'] as String? ?? 'storefront',
    );
  }
}

class StoreItem {
  final int? id;
  final String name;
  final String category;
  final double rating;
  final List<String> images; // 至多 3 张照片/剧照路径
  final String? address; // 位置/来源/平台
  final String? notes; // 特色/说明/备忘
  final DateTime createdAt;

  StoreItem({
    this.id,
    required this.name,
    required this.category,
    this.rating = 5.0,
    required this.images,
    this.address,
    this.notes,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  StoreItem copyWith({
    int? id,
    String? name,
    String? category,
    double? rating,
    List<String>? images,
    String? address,
    String? notes,
    DateTime? createdAt,
  }) {
    return StoreItem(
      id: id ?? this.id,
      name: name ?? this.name,
      category: category ?? this.category,
      rating: rating ?? this.rating,
      images: images ?? this.images,
      address: address ?? this.address,
      notes: notes ?? this.notes,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'category': category,
      'rating': rating,
      'imagesJson': jsonEncode(images),
      'address': address,
      'notes': notes,
      'createdAt': createdAt.toIso8601String(),
    };
  }

  factory StoreItem.fromMap(Map<String, dynamic> map) {
    List<String> imgs = [];
    if (map['imagesJson'] != null) {
      imgs = (jsonDecode(map['imagesJson'] as String) as List)
          .map((e) => e.toString())
          .toList();
    }

    return StoreItem(
      id: map['id'] as int?,
      name: map['name'] as String,
      category: map['category'] as String? ?? '通用未分类',
      rating: (map['rating'] as num?)?.toDouble() ?? 5.0,
      images: imgs,
      address: map['address'] as String?,
      notes: map['notes'] as String?,
      createdAt: DateTime.parse(map['createdAt'] as String),
    );
  }
}

class StoreLog {
  final int? id;
  final int storeId;
  final String storeName;
  final double? cost; // 本次打卡消费
  final List<int> visitorIds; // 参与/同行成员 ID 列表
  final List<String> visitorNames; // 参与/同行成员 姓名 列表
  final String? memo; // 打卡体验心得
  final DateTime timestamp; // 分钟级打卡时刻 (yyyy-MM-dd HH:mm)

  StoreLog({
    this.id,
    required this.storeId,
    required this.storeName,
    this.cost,
    this.visitorIds = const [],
    this.visitorNames = const ['自己'],
    this.memo,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'storeId': storeId,
      'storeName': storeName,
      'cost': cost,
      'visitorIdsJson': jsonEncode(visitorIds),
      'visitorNamesJson': jsonEncode(visitorNames),
      'memo': memo,
      'timestamp': timestamp.toIso8601String(),
    };
  }

  factory StoreLog.fromMap(Map<String, dynamic> map) {
    List<int> vIds = [];
    List<String> vNames = [];
    if (map['visitorIdsJson'] != null) {
      vIds = (jsonDecode(map['visitorIdsJson'] as String) as List)
          .map((e) => (e as num).toInt())
          .toList();
    }
    if (map['visitorNamesJson'] != null) {
      vNames = (jsonDecode(map['visitorNamesJson'] as String) as List)
          .map((e) => e.toString())
          .toList();
    }
    if (vNames.isEmpty && map['visitorName'] != null) {
      vNames = [map['visitorName'] as String];
    }

    return StoreLog(
      id: map['id'] as int?,
      storeId: map['storeId'] as int,
      storeName: map['storeName'] as String,
      cost: (map['cost'] as num?)?.toDouble(),
      visitorIds: vIds,
      visitorNames: vNames.isNotEmpty ? vNames : ['自己'],
      memo: map['memo'] as String?,
      timestamp: DateTime.parse(map['timestamp'] as String),
    );
  }
}
