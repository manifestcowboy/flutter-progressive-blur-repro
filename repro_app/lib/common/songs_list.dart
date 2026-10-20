import 'package:flutter/material.dart';

import 'constants.dart';
import 'load.dart';
import 'music_data.dart';
import 'music_widgets.dart';
import 'real_app_content.dart';

/// The default songs list used by the blur scenarios.
///
/// Under [AppLoad.light]: songs, with a row of albums every sixth item. Under
/// [AppLoad.realApp] (see `real_app_content.dart`): a "Recently played" glass
/// row, then songs interleaved with 2-column grids of large covers and glass
/// cards.
///
/// [overrides] replaces individual rows (the animated ones in S2).
class SongsListView extends StatelessWidget {
  const SongsListView({
    super.key,
    required this.controller,
    this.topPadding = kHeaderHeight,
    this.bottomPadding = 24,
    this.itemCount = 400,
    this.overrides = const <int, WidgetBuilder>{},
    this.physics,
  });

  final ScrollController controller;
  final double topPadding;
  final double bottomPadding;
  final int itemCount;
  final Map<int, WidgetBuilder> overrides;
  final ScrollPhysics? physics;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AppLoad>(
      valueListenable: appLoad,
      builder: (BuildContext context, AppLoad load, Widget? _) {
        final bool real = load == AppLoad.realApp;
        return ListView.builder(
          controller: controller,
          physics: physics,
          padding: EdgeInsets.only(top: topPadding, bottom: bottomPadding),
          itemCount: itemCount,
          itemBuilder: (BuildContext context, int i) {
            final WidgetBuilder? custom = overrides[i];
            if (custom != null) return custom(context);
            if (real) {
              final RealAppSlot slot = realAppSlotAt(i);
              if (slot != RealAppSlot.song) return realAppDecor(slot, i);
            } else if (i % 6 == 5) {
              return AlbumRow(index: i);
            }
            return SongTile(song: songAt(i));
          },
        );
      },
    );
  }
}
