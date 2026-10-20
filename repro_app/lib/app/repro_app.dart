import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'scenario.dart';

/// The app shell: a plain Material 3 music app that follows the system
/// light/dark setting, with a menu of [scenarios] as its home.
class ReproApp extends StatelessWidget {
  const ReproApp({
    super.key,
    required this.scenarios,
    required this.entrypoint,
  });

  final List<Scenario> scenarios;

  /// Shown on the menu, e.g. `main_stock.dart`.
  final String entrypoint;

  @override
  Widget build(BuildContext context) {
    ThemeData theme(Brightness brightness) => ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.indigo,
            brightness: brightness,
          ),
        );
    return MaterialApp(
      title: 'Blur repro',
      debugShowCheckedModeBanner: false,
      theme: theme(Brightness.light),
      darkTheme: theme(Brightness.dark),
      themeMode: ThemeMode.system,
      home: HomePage(scenarios: scenarios, entrypoint: entrypoint),
    );
  }
}

/// The scenario menu.
class HomePage extends StatelessWidget {
  const HomePage({super.key, required this.scenarios, required this.entrypoint});

  final List<Scenario> scenarios;
  final String entrypoint;

  static String get _mode => kReleaseMode
      ? 'release'
      : kProfileMode
          ? 'profile'
          : 'DEBUG';

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Blur repro')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: <Widget>[
          Card.filled(
            color: kDebugMode
                ? scheme.errorContainer
                : scheme.secondaryContainer,
            margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                'Entrypoint: $entrypoint\n'
                'Build mode: $_mode'
                '${kDebugMode ? ' - timings are meaningless in debug. Run with --profile on a real device.' : ''}\n'
                'Each scenario is an ordinary-looking music screen with a test '
                'panel on top. Open the info card first.',
                style: theme.textTheme.bodySmall,
              ),
            ),
          ),
          for (final Scenario s in scenarios)
            ListTile(
              leading: CircleAvatar(child: Text(s.id)),
              title: Text(s.title),
              subtitle: Text('${s.screen}\n${s.subtitle}'),
              isThreeLine: true,
              trailing: Chip(
                label: Text(s.kind.badge),
                labelStyle: theme.textTheme.labelSmall,
                visualDensity: VisualDensity.compact,
              ),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: s.builder),
              ),
            ),
        ],
      ),
    );
  }
}
