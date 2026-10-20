import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// Counts element rebuilds inside a blur using the framework's
/// `debugOnRebuildDirtyWidget` hook. DEBUG BUILDS ONLY: the hook is compiled
/// out of profile and release, so the counts stay zero there.
///
/// The blur is wrapped in a [KeyedSubtree] with [blurKey] and its child in one
/// with [appKey]. An element rebuilt under [blurKey] but not under [appKey] is
/// owned by the package (the blur wrapper and its passes).
class RebuildTracker {
  static const ValueKey<String> blurKey = ValueKey<String>('blur-root');
  static const ValueKey<String> appKey = ValueKey<String>('app-child');

  /// Package-owned elements rebuilt since the last reset.
  int blurOwned = 0;

  /// App-owned elements (inside the blurred child) rebuilt since the last reset.
  int appOwned = 0;

  RebuildDirtyWidgetCallback? _previous;

  void attach() {
    if (!kDebugMode) return;
    _previous = debugOnRebuildDirtyWidget;
    debugOnRebuildDirtyWidget = _onRebuild;
  }

  void detach() {
    if (!kDebugMode) return;
    debugOnRebuildDirtyWidget = _previous;
  }

  void reset() {
    blurOwned = 0;
    appOwned = 0;
  }

  void _onRebuild(Element element, bool builtOnce) {
    _previous?.call(element, builtOnce);
    if (!builtOnce) return;
    final Key? own = element.widget.key;
    if (own == appKey) {
      appOwned++;
      return;
    }
    if (own == blurKey) {
      blurOwned++;
      return;
    }
    element.visitAncestorElements((Element ancestor) {
      final Key? key = ancestor.widget.key;
      if (key == appKey) {
        appOwned++;
        return false;
      }
      if (key == blurKey) {
        blurOwned++;
        return false;
      }
      return true;
    });
  }
}
