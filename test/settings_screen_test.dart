import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oneconnect/app_state.dart';
import 'package:oneconnect/models/app_settings.dart';
import 'package:oneconnect/screens/settings_screen.dart';

import 'helpers/fake_store.dart';

void main() {
  late AppState appState;

  setUp(() {
    appState = AppState(FakeStore());
  });

  Widget screen() => MaterialApp(home: SettingsScreen(appState: appState));

  testWidgets('shows the three settings', (tester) async {
    await tester.pumpWidget(screen());

    expect(find.text('Appearance'), findsOneWidget);
    expect(find.text('Text size'), findsOneWidget);
    expect(find.text('Reduce animations'), findsOneWidget);
  });

  testWidgets('shows the developer details', (tester) async {
    await tester.pumpWidget(screen());

    expect(find.text('Developer'), findsOneWidget);
    expect(find.text('Developed by'), findsOneWidget);
    expect(find.text('John Carlo Medina'), findsOneWidget);
    expect(find.text('Contact'), findsOneWidget);
    expect(find.text('dark.803011@gmail.com'), findsOneWidget);
    expect(find.text('Version'), findsOneWidget);
    expect(find.text('1.0.0'), findsOneWidget);
  });

  testWidgets('choosing Dark changes the theme setting', (tester) async {
    await tester.pumpWidget(screen());

    await tester.tap(find.text('Dark'));
    await tester.pumpAndSettle();

    expect(appState.settings.themeChoice, ThemeChoice.dark);
  });

  testWidgets('choosing Large changes the text size', (tester) async {
    await tester.pumpWidget(screen());

    await tester.tap(find.text('Large'));
    await tester.pumpAndSettle();

    expect(appState.settings.textSize, TextSizeChoice.large);
  });

  testWidgets('the switch turns reduce animations on', (tester) async {
    await tester.pumpWidget(screen());

    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();

    expect(appState.settings.reduceAnimations, true);
  });
}
