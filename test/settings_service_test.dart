import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:easy_violin/services/settings_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('SettingsService loads defaults, clamps values, and persists changes', () async {
    SharedPreferences.setMockInitialValues({});
    final settings = await SettingsService.init();

    // Default concert pitch
    expect(settings.concertA4Hz, 440.0);
    expect(settings.lastTab, 0);

    // Persist new pitch
    await settings.setConcertA4Hz(442.0);
    expect(settings.concertA4Hz, 442.0);

    // Clamping to valid orchestra tuning range
    await settings.setConcertA4Hz(500.0);
    expect(settings.concertA4Hz, 446.0);

    await settings.setConcertA4Hz(300.0);
    expect(settings.concertA4Hz, 415.0);

    // Persist last tab
    await settings.setLastTab(2);
    expect(settings.lastTab, 2);
  });
}
