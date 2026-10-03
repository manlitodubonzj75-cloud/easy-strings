import 'package:shared_preferences/shared_preferences.dart';

class SettingsService {
  static const String _keyConcertA4 = 'easy_violin_concert_a4';
  static const String _keyLastTab = 'easy_violin_last_tab';

  final SharedPreferences _prefs;

  SettingsService(this._prefs);

  static Future<SettingsService> init([SharedPreferences? preferences]) async {
    if (preferences != null) {
      return SettingsService(preferences);
    }
    final prefs = await SharedPreferences.getInstance();
    return SettingsService(prefs);
  }

  double get concertA4Hz {
    return _prefs.getDouble(_keyConcertA4) ?? 440.0;
  }

  Future<bool> setConcertA4Hz(double hz) async {
    final clamped = hz.clamp(415.0, 446.0);
    return _prefs.setDouble(_keyConcertA4, clamped);
  }

  int get lastTab {
    return _prefs.getInt(_keyLastTab) ?? 0;
  }

  Future<bool> setLastTab(int index) async {
    return _prefs.setInt(_keyLastTab, index);
  }
}
