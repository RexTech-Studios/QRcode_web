import 'package:hive/hive.dart';

part 'settings_model.g.dart';

@HiveType(typeId: 3)
class SettingsModel extends HiveObject {
  @HiveField(0)
  String businessName;

  @HiveField(1)
  String selectedTheme;

  @HiveField(2)
  bool cloudSyncEnabled;

  @HiveField(3)
  String defaultQrStyleName;

  SettingsModel({
    this.businessName = '',
    this.selectedTheme = 'light',
    this.cloudSyncEnabled = true,
    this.defaultQrStyleName = 'classic',
  });
}
