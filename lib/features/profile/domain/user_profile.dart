class UserProfile {
  final double heightCm;
  final double weightKg;
  final String gender;
  final int age;
  final double? customStrideCm;

  const UserProfile({
    this.heightCm = 170.0,
    this.weightKg = 65.0,
    this.gender = '男',
    this.age = 25,
    this.customStrideCm,
  });

  UserProfile copyWith({
    double? heightCm,
    double? weightKg,
    String? gender,
    int? age,
    double? customStrideCm,
  }) {
    return UserProfile(
      heightCm: heightCm ?? this.heightCm,
      weightKg: weightKg ?? this.weightKg,
      gender: gender ?? this.gender,
      age: age ?? this.age,
      customStrideCm: customStrideCm ?? this.customStrideCm,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'heightCm': heightCm,
      'weightKg': weightKg,
      'gender': gender,
      'age': age,
      'customStrideCm': customStrideCm,
    };
  }

  factory UserProfile.fromMap(Map<String, dynamic> map) {
    return UserProfile(
      heightCm: (map['heightCm'] as num?)?.toDouble() ?? 170.0,
      weightKg: (map['weightKg'] as num?)?.toDouble() ?? 65.0,
      gender: map['gender'] as String? ?? '男',
      age: map['age'] as int? ?? 25,
      customStrideCm: (map['customStrideCm'] as num?)?.toDouble(),
    );
  }
}
