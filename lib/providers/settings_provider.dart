import 'package:flutter/foundation.dart';
import '../models/settings_model.dart';
import '../services/hive_service.dart';

class SettingsProvider extends ChangeNotifier {
  late SettingsModel _settings;

  SettingsModel get settings => _settings;

  void loadSettings() {
    _settings = HiveService.getSettings();
    notifyListeners();
  }

  Future<void> updateBusinessName(String name) async {
    _settings.businessName = name.trim();
    await HiveService.saveSettings(_settings);
    notifyListeners();
  }
}
