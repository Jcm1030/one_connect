import 'package:flutter_test/flutter_test.dart';
import 'package:oneconnect/models/app_settings.dart';

void main() {
  test('the default settings follow the phone and change nothing', () {
    const settings = AppSettings();
    expect(settings.themeChoice, ThemeChoice.system);
    expect(settings.textSize, TextSizeChoice.normal);
    expect(settings.reduceAnimations, false);
  });

  test(
    'copyWith changes only what is given, and each text size has a scale',
    () {
      const original = AppSettings(
        themeChoice: ThemeChoice.dark,
        textSize: TextSizeChoice.large,
      );
      final changed = original.copyWith(reduceAnimations: true);

      expect(changed.themeChoice, ThemeChoice.dark);
      expect(changed.textSize, TextSizeChoice.large);
      expect(changed.reduceAnimations, true);

      expect(const AppSettings(textSize: TextSizeChoice.small).textScale, 0.9);
      expect(const AppSettings().textScale, 1.0);
      expect(original.textScale, 1.2);
    },
  );
}
