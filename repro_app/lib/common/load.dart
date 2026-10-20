import 'package:flutter/material.dart';

import 'ambient_background.dart';
import 'controls.dart';

/// How much the screens ask of the renderer.
enum AppLoad {
  /// The bare demo: a list of rows on a flat surface, nothing animating
  /// under the blur at rest.
  light('Light'),

  /// What the app under test puts under its blurs: an ambient background that
  /// repaints every frame, glass cards (`BackdropFilter`) and large cover
  /// tiles. The blurred subtree is dirty every frame and expensive to
  /// rasterise, which is the condition the production app was in.
  realApp('Real-app');

  const AppLoad(this.label);

  final String label;
}

/// The load shared by all scenarios, so it stays put when you go back to the
/// menu and open another one. Real-app unless changed.
final ValueNotifier<AppLoad> appLoad = ValueNotifier<AppLoad>(AppLoad.realApp);

/// The "Load" segmented control for a scenario's control panel.
class LoadChoice extends StatelessWidget {
  const LoadChoice({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AppLoad>(
      valueListenable: appLoad,
      builder: (BuildContext context, AppLoad load, Widget? _) =>
          SegmentChoice<AppLoad>(
        label: 'Load',
        value: load,
        options: <AppLoad, String>{
          for (final AppLoad l in AppLoad.values) l: l.label,
        },
        onChanged: (AppLoad v) => appLoad.value = v,
      ),
    );
  }
}

/// The content that goes INSIDE a blur: [child] (the scroll view), with the
/// animated [AmbientBackground] behind it under [AppLoad.realApp].
///
/// [child] stays at the same child index whichever load is on, so a scroll view
/// keeps its State and scroll position when the load is switched.
class LoadStage extends StatelessWidget {
  const LoadStage({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AppLoad>(
      valueListenable: appLoad,
      child: child,
      builder: (BuildContext context, AppLoad load, Widget? child) => Stack(
        fit: StackFit.expand,
        children: <Widget>[
          load == AppLoad.realApp
              ? const AmbientBackground()
              : const SizedBox.shrink(),
          child!,
        ],
      ),
    );
  }
}
