import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'labels.dart';

/// User settings, saved on the phone so they survive app restarts.
class AppSettings extends ChangeNotifier {
  AppSettings._(this._prefs);

  final SharedPreferences _prefs;

  static Future<AppSettings> load() async =>
      AppSettings._(await SharedPreferences.getInstance());

  double get confidence => _prefs.getDouble('confidence') ?? 0.40;
  set confidence(double v) {
    _prefs.setDouble('confidence', v);
    notifyListeners();
  }

  Set<int> get classes {
    final saved = _prefs.getStringList('classes');
    return saved == null ? {...kDefaultClasses} : saved.map(int.parse).toSet();
  }

  set classes(Set<int> v) {
    _prefs.setStringList('classes', v.map((e) => '$e').toList());
    notifyListeners();
  }

  List<String> get recentUrls => _prefs.getStringList('recentUrls') ?? [];

  void addRecentUrl(String url) {
    final list = recentUrls..remove(url);
    list.insert(0, url);
    _prefs.setStringList('recentUrls', list.take(5).toList());
    notifyListeners();
  }

  void removeRecentUrl(String url) {
    _prefs.setStringList('recentUrls', recentUrls..remove(url));
    notifyListeners();
  }
}
