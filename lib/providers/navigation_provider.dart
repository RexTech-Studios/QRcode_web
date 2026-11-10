import 'package:flutter/foundation.dart';

enum DashboardTab { generateQr, myQrCodes, shops, analytics, salesTeam, settings }

class NavigationProvider extends ChangeNotifier {
  DashboardTab _current = DashboardTab.generateQr;

  DashboardTab get current => _current;

  void goTo(DashboardTab tab) {
    if (_current == tab) return;
    _current = tab;
    notifyListeners();
  }

  void reset() {
    _current = DashboardTab.generateQr;
    notifyListeners();
  }
}
