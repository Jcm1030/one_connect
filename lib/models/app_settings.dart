// The choices a person can make on the Settings screen.
// They belong to this phone, not to a profile.

enum ThemeChoice { system, light, dark }

enum TextSizeChoice { small, normal, large }

class AppSettings {
  final ThemeChoice themeChoice;
  final TextSizeChoice textSize;
  final bool reduceAnimations;

  const AppSettings({
    this.themeChoice = ThemeChoice.system,
    this.textSize = TextSizeChoice.normal,
    this.reduceAnimations = false,
  });

  AppSettings copyWith({
    ThemeChoice? themeChoice,
    TextSizeChoice? textSize,
    bool? reduceAnimations,
  }) {
    return AppSettings(
      themeChoice: themeChoice ?? this.themeChoice,
      textSize: textSize ?? this.textSize,
      reduceAnimations: reduceAnimations ?? this.reduceAnimations,
    );
  }

  // How much bigger or smaller all text becomes.
  double get textScale {
    switch (textSize) {
      case TextSizeChoice.small:
        return 0.9;
      case TextSizeChoice.normal:
        return 1.0;
      case TextSizeChoice.large:
        return 1.2;
    }
  }
}
