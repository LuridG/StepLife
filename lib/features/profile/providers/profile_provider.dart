import 'package:flutter/foundation.dart';
import '../domain/user_profile.dart';
import '../../../core/db/database_service.dart';

class ProfileProvider extends ChangeNotifier {
  UserProfile _profile = const UserProfile();
  bool _isLoading = true;

  UserProfile get profile => _profile;
  bool get isLoading => _isLoading;

  ProfileProvider() {
    loadProfile();
  }

  Future<void> loadProfile() async {
    _isLoading = true;
    notifyListeners();
    _profile = await DatabaseService.instance.getUserProfile();
    _isLoading = false;
    notifyListeners();
  }

  Future<void> updateProfile({
    required double heightCm,
    required double weightKg,
    required String gender,
    required int age,
    double? customStrideCm,
  }) async {
    _profile = UserProfile(
      heightCm: heightCm,
      weightKg: weightKg,
      gender: gender,
      age: age,
      customStrideCm: customStrideCm,
    );
    await DatabaseService.instance.saveUserProfile(_profile);
    notifyListeners();
  }
}
