import 'package:flutter/material.dart';
import '../app_state.dart';
import '../models/app_settings.dart';
import '../widgets/screen_body.dart';

const _developerName = 'John Carlo Medina';
const _developerContact = 'dark.803011@gmail.com';
const _appVersion = '1.0.0';

class SettingsScreen extends StatelessWidget {
  final AppState appState;

  const SettingsScreen({super.key, required this.appState});

  Future<void> _change(BuildContext context, AppSettings newSettings) async {
    final saved = await appState.changeSettings(newSettings);
    if (!context.mounted) {
      return;
    }
    if (!saved) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not save your settings.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final titleStyle = Theme.of(context).textTheme.titleMedium;

    // Listening to appState keeps this screen up to date after each change.
    return ListenableBuilder(
      listenable: appState,
      builder: (context, _) {
        final settings = appState.settings;

        return Scaffold(
          appBar: AppBar(title: const Text('Settings')),
          body: ScreenBody(
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Text('Appearance', style: titleStyle),
                const SizedBox(height: 12),
                SegmentedButton<ThemeChoice>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(
                      value: ThemeChoice.system,
                      label: Text('System'),
                    ),
                    ButtonSegment(
                      value: ThemeChoice.light,
                      label: Text('Light'),
                    ),
                    ButtonSegment(value: ThemeChoice.dark, label: Text('Dark')),
                  ],
                  selected: {settings.themeChoice},
                  onSelectionChanged: (choice) => _change(
                    context,
                    settings.copyWith(themeChoice: choice.first),
                  ),
                ),
                const SizedBox(height: 28),
                Text('Text size', style: titleStyle),
                const SizedBox(height: 12),
                SegmentedButton<TextSizeChoice>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(
                      value: TextSizeChoice.small,
                      label: Text('Small'),
                    ),
                    ButtonSegment(
                      value: TextSizeChoice.normal,
                      label: Text('Normal'),
                    ),
                    ButtonSegment(
                      value: TextSizeChoice.large,
                      label: Text('Large'),
                    ),
                  ],
                  selected: {settings.textSize},
                  onSelectionChanged: (choice) => _change(
                    context,
                    settings.copyWith(textSize: choice.first),
                  ),
                ),
                const SizedBox(height: 12),
                const Text('This is how your messages will look.'),
                const SizedBox(height: 20),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Reduce animations'),
                  subtitle: const Text(
                    'Turns off most movement. It also follows your '
                    "phone's own accessibility setting.",
                  ),
                  value: settings.reduceAnimations,
                  onChanged: (value) => _change(
                    context,
                    settings.copyWith(reduceAnimations: value),
                  ),
                ),
                const SizedBox(height: 28),
                Text(
                  'Your messages and these settings are saved only on '
                  'this phone.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 28),
                Text('Developer', style: titleStyle),
                const SizedBox(height: 8),
                const Card(
                  child: Column(
                    children: [
                      ListTile(
                        leading: Icon(Icons.person_outline),
                        title: Text('Developed by'),
                        subtitle: Text(_developerName),
                      ),
                      ListTile(
                        leading: Icon(Icons.email),
                        title: Text('Contact'),
                        subtitle: Text(_developerContact),
                      ),
                      ListTile(
                        leading: Icon(Icons.info),
                        title: Text('Version'),
                        subtitle: Text(_appVersion),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
