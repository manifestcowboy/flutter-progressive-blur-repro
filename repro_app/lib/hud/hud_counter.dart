/// One extra line on the HUD, read on every HUD refresh.
///
/// Numeric counters (`HudCounter.count`) are shown as the total, the change
/// since the last "Reset stats" and the rate per second. Text counters
/// (`HudCounter.text`) are shown verbatim.
class HudCounter {
  HudCounter.count(this.label, num Function() read, {this.debugOnly = false})
      : readCount = read,
        readText = null;

  HudCounter.text(this.label, String Function() read, {this.debugOnly = false})
      : readText = read,
        readCount = null;

  final String label;
  final num Function()? readCount;
  final String Function()? readText;

  /// The value only moves in debug builds (the package gates its counters on
  /// `kDebugMode`). In profile or release the HUD says so instead of showing a
  /// misleading zero.
  final bool debugOnly;
}
