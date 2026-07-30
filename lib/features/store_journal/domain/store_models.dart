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
  final List<String> images; // 至多 3 张照片路径
  final String? address;
  final double? avgCost;
  final String? notes;
  final DateTime createdAt;

  StoreItem({
    this.id,
    required this.name,
    required this.category,
    this.rating = 5.0,
    required this.images,
    this.address,
    this.avgCost,
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
    double? avgCost,
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
      avgCost: avgCost ?? this.avgCost,
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
      'avgCost': avgCost,
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
      category: map['category'] as String? ?? '餐饮美食',
      rating: (map['rating'] as num?)?.toDouble() ?? 5.0,
      images: imgs,
      address: map['address'] as String?,
      avgCost: (map['avgCost'] as num?)?.toDouble(),
      notes: map['notes'] as String?,
      createdAt: DateTime.parse(map['createdAt'] as String),
    );
  }
}

class StoreLog {
  final int? id;
  final int storeId;
  final String storeName;
  final double? cost;
  final String visitorName;
  final String? memo;
  final DateTime timestamp;

  StoreLog({
    this.id,
    required this.storeId,
    required this.storeName,
    this.cost,
    this.visitorName = '自己',
    this.memo,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'storeId': storeId,
      'storeName': storeName,
      'cost': cost,
      'visitorName': visitorName,
      'memo': memo,
      'timestamp': timestamp.toIso8601String(),
    };
  }

  factory StoreLog.fromMap(Map<String, dynamic> map) {
    return StoreLog(
      id: map['id'] as int?,
      storeId: map['storeId'] as int,
      storeName: map['storeName'] as String,
      cost: (map['cost'] as num?)?.toDouble(),
      visitorName: map['visitorName'] as String? ?? '自己',
      memo: map['memo'] as String?,
      timestamp: DateTime.parse(map['timestamp'] as String),
    );
  }
}
