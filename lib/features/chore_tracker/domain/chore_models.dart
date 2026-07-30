import 'dart:convert';

class Member {
  final int? id;
  final String name;
  final String gender;
  final double heightCm;
  final double weightKg;
  final int age;
  final double? customStrideCm;
  final String avatarIcon;
  final int colorValue;

  Member({
    this.id,
    required this.name,
    this.gender = '男',
    this.heightCm = 170.0,
    this.weightKg = 65.0,
    this.age = 25,
    this.customStrideCm,
    this.avatarIcon = 'person',
    this.colorValue = 0xFF6366F1,
  });

  Member copyWith({
    int? id,
    String? name,
    String? gender,
    double? heightCm,
    double? weightKg,
    int? age,
    double? customStrideCm,
    String? avatarIcon,
    int? colorValue,
  }) {
    return Member(
      id: id ?? this.id,
      name: name ?? this.name,
      gender: gender ?? this.gender,
      heightCm: heightCm ?? this.heightCm,
      weightKg: weightKg ?? this.weightKg,
      age: age ?? this.age,
      customStrideCm: customStrideCm ?? this.customStrideCm,
      avatarIcon: avatarIcon ?? this.avatarIcon,
      colorValue: colorValue ?? this.colorValue,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'gender': gender,
      'heightCm': heightCm,
      'weightKg': weightKg,
      'age': age,
      'customStrideCm': customStrideCm,
      'avatarIcon': avatarIcon,
      'colorValue': colorValue,
    };
  }

  factory Member.fromMap(Map<String, dynamic> map) {
    return Member(
      id: map['id'] as int?,
      name: map['name'] as String,
      gender: map['gender'] as String? ?? '男',
      heightCm: (map['heightCm'] as num?)?.toDouble() ?? 170.0,
      weightKg: (map['weightKg'] as num?)?.toDouble() ?? 65.0,
      age: map['age'] as int? ?? 25,
      customStrideCm: (map['customStrideCm'] as num?)?.toDouble(),
      avatarIcon: map['avatarIcon'] as String? ?? 'person',
      colorValue: map['colorValue'] as int? ?? 0xFF6366F1,
    );
  }
}

class ChoreItem {
  final int? id;
  final String title;
  final String category;
  final String iconName;
  final bool isQuantifiable;
  final String unit;

  ChoreItem({
    this.id,
    required this.title,
    this.category = '日常家务',
    this.iconName = 'cleaning_services',
    this.isQuantifiable = false,
    this.unit = '次',
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'category': category,
      'iconName': iconName,
      'isQuantifiable': isQuantifiable ? 1 : 0,
      'unit': unit,
    };
  }

  factory ChoreItem.fromMap(Map<String, dynamic> map) {
    return ChoreItem(
      id: map['id'] as int?,
      title: map['title'] as String,
      category: map['category'] as String? ?? '日常家务',
      iconName: map['iconName'] as String? ?? 'cleaning_services',
      isQuantifiable: (map['isQuantifiable'] as int? ?? 0) == 1,
      unit: map['unit'] as String? ?? '次',
    );
  }
}

class ChoreLog {
  final int? id;
  final int choreId;
  final String choreTitle;
  final List<int> memberIds;
  final List<String> memberNames;
  final String? memo;
  final double? value;
  final DateTime timestamp;

  ChoreLog({
    this.id,
    required this.choreId,
    required this.choreTitle,
    required this.memberIds,
    required this.memberNames,
    this.memo,
    this.value,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'choreId': choreId,
      'choreTitle': choreTitle,
      'memberIdsJson': jsonEncode(memberIds),
      'memberNamesJson': jsonEncode(memberNames),
      'memo': memo,
      'value': value,
      'timestamp': timestamp.toIso8601String(),
    };
  }

  factory ChoreLog.fromMap(Map<String, dynamic> map) {
    List<int> mIds = [];
    if (map['memberIdsJson'] != null) {
      mIds = (jsonDecode(map['memberIdsJson'] as String) as List)
          .map((e) => e as int)
          .toList();
    }

    List<String> mNames = [];
    if (map['memberNamesJson'] != null) {
      mNames = (jsonDecode(map['memberNamesJson'] as String) as List)
          .map((e) => e.toString())
          .toList();
    }

    return ChoreLog(
      id: map['id'] as int?,
      choreId: map['choreId'] as int,
      choreTitle: map['choreTitle'] as String,
      memberIds: mIds,
      memberNames: mNames,
      memo: map['memo'] as String?,
      value: (map['value'] as num?)?.toDouble(),
      timestamp: DateTime.parse(map['timestamp'] as String),
    );
  }
}
