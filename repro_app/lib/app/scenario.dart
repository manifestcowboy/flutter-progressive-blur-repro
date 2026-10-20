import 'package:flutter/widgets.dart';

/// Which API surface a scenario needs.
enum ScenarioKind {
  /// Compiles and runs against pristine 0.4.1.
  stock('STOCK'),

  /// A stock scenario that also offers the band sampler as an A/B toggle.
  stockWithBand('STOCK + BAND A/B');

  const ScenarioKind(this.badge);

  final String badge;
}

/// One entry on the home menu.
class Scenario {
  const Scenario({
    required this.id,
    required this.title,
    required this.screen,
    required this.subtitle,
    required this.kind,
    required this.builder,
  });

  /// `S1` .. `S3`.
  final String id;
  final String title;

  /// The music screen it is shown as, e.g. "Library > Songs".
  final String screen;
  final String subtitle;
  final ScenarioKind kind;
  final WidgetBuilder builder;
}
