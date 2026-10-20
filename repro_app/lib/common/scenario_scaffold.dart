import 'package:flutter/material.dart';

import '../hud/frame_stats.dart';
import '../hud/hud_counter.dart';
import '../hud/hud_overlay.dart';

/// The text of a scenario's top card.
class ScenarioInfo {
  const ScenarioInfo({
    required this.finger,
    required this.watch,
    required this.saw,
    this.warning,
  });

  /// What to do with your finger.
  final String finger;

  /// What to watch.
  final String watch;

  /// What the app team saw on device (as reported; this demo does not
  /// reproduce the numbers by itself).
  final String saw;

  /// Optional caution, e.g. that the scenario can kill the app.
  final String? warning;
}

/// Whether the info cards are open. Shared so that collapsing the card once
/// keeps it collapsed on the next scenario.
final ValueNotifier<bool> infoCardExpanded = ValueNotifier<bool>(true);

/// A collapsible card with the finger steps, what to watch and what was seen.
class InfoCard extends StatelessWidget {
  const InfoCard({super.key, required this.info});

  final ScenarioInfo info;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final TextTheme text = theme.textTheme;
    final double maxHeight = MediaQuery.sizeOf(context).height * 0.38;

    Widget section(String heading, String body) => Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                heading,
                style: text.labelMedium?.copyWith(
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(body, style: text.bodySmall),
            ],
          ),
        );

    return Card.filled(
      margin: const EdgeInsets.fromLTRB(12, 4, 12, 6),
      child: ValueListenableBuilder<bool>(
        valueListenable: infoCardExpanded,
        builder: (BuildContext context, bool expanded, Widget? _) {
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => infoCardExpanded.value = !expanded,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  child: Row(
                    children: <Widget>[
                      const Icon(Icons.info_outline, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'What to do, what to watch, what we saw',
                          style: text.labelLarge,
                        ),
                      ),
                      Icon(expanded ? Icons.expand_less : Icons.expand_more),
                    ],
                  ),
                ),
              ),
              if (expanded)
                ConstrainedBox(
                  constraints: BoxConstraints(maxHeight: maxHeight),
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        if (info.warning != null)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Text(
                              info.warning!,
                              style: text.bodySmall?.copyWith(
                                color: theme.colorScheme.error,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        section('With your finger', info.finger),
                        section('Watch', info.watch),
                        section('What we saw on device (reported)', info.saw),
                      ],
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

/// The frame every scenario sits in: app bar, collapsible [info] card,
/// [controls], then the [body] with the frame-timing HUD floating over it.
class ScenarioScaffold extends StatefulWidget {
  const ScenarioScaffold({
    super.key,
    required this.title,
    required this.info,
    required this.body,
    this.controls,
    this.counters = const <HudCounter>[],
    this.onReset,
  });

  final String title;
  final ScenarioInfo info;
  final Widget body;
  final Widget? controls;
  final List<HudCounter> counters;

  /// Called when "Reset stats" is pressed.
  final VoidCallback? onReset;

  @override
  State<ScenarioScaffold> createState() => _ScenarioScaffoldState();
}

class _ScenarioScaffoldState extends State<ScenarioScaffold> {
  final FrameStatsCollector _collector = FrameStatsCollector();

  @override
  void dispose() {
    _collector.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title, style: Theme.of(context).textTheme.titleMedium),
        toolbarHeight: 48,
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: <Widget>[
            InfoCard(info: widget.info),
            if (widget.controls != null) widget.controls!,
            Expanded(
              child: ClipRect(
                child: Stack(
                  children: <Widget>[
                    Positioned.fill(child: widget.body),
                    Positioned.fill(
                      child: HudOverlay(
                        collector: _collector,
                        counters: widget.counters,
                        onReset: widget.onReset ?? () {},
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
