import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'music_data.dart';
import 'music_widgets.dart';

/// Backdrop blur of the glass cards, in logical px.
const double kGlassSigma = 20;

/// What a slot of a real-app list holds.
enum RealAppSlot {
  /// The "Recently played" glass row, first in the list.
  recentlyPlayed,
  song,

  /// A 2-column section of large cover tiles.
  coverGrid,

  /// A glass feature card.
  glassCard,
}

/// The slot at [item] of a real-app list whose songs are numbered by item
/// (S1, S2): the recently-played row, then a repeating pattern of song, song,
/// song, cover grid, song, song, glass card.
RealAppSlot realAppSlotAt(int item) {
  if (item == 0) return RealAppSlot.recentlyPlayed;
  switch ((item - 1) % 7) {
    case 3:
      return RealAppSlot.coverGrid;
    case 6:
      return RealAppSlot.glassCard;
    default:
      return RealAppSlot.song;
  }
}

/// The same pattern for a list that numbers its songs itself and removes some
/// (S3): the decoration that follows song number [n] (0-based), or null. The
/// decoration stays when its song is removed, so nothing hops around.
RealAppSlot? realAppDecorAfterSong(int n) {
  switch (n % 5) {
    case 2:
      return RealAppSlot.coverGrid;
    case 4:
      return RealAppSlot.glassCard;
    default:
      return null;
  }
}

/// The non-song slots. [seed] picks the songs shown, so neighbours differ.
/// [gridRows] is how many rows of two large covers a cover grid has.
Widget realAppDecor(RealAppSlot slot, int seed, {int gridRows = 2}) {
  switch (slot) {
    case RealAppSlot.recentlyPlayed:
      return const RecentlyPlayedRow();
    case RealAppSlot.coverGrid:
      return CoverGridSection(seed: seed, rows: gridRows);
    case RealAppSlot.glassCard:
      return GlassFeatureCard(seed: seed);
    case RealAppSlot.song:
      throw ArgumentError.value(slot, 'slot', 'is a song, not a decoration');
  }
}

/// A translucent panel: a rounded clip, a [BackdropFilter] blurring whatever
/// is behind it at [kGlassSigma], and a faint tint and outline.
class GlassPanel extends StatelessWidget {
  const GlassPanel({
    super.key,
    required this.child,
    this.radius = 20,
    this.padding = const EdgeInsets.all(12),
  });

  final Widget child;
  final double radius;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final BorderRadius corners = BorderRadius.circular(radius);
    return ClipRRect(
      borderRadius: corners,
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: kGlassSigma, sigmaY: kGlassSigma),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: scheme.surface.withValues(alpha: 0.34),
            borderRadius: corners,
            border: Border.all(
              color: scheme.onSurface.withValues(alpha: 0.12),
            ),
          ),
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}

/// "Recently played": a glass card with four album covers in a row.
class RecentlyPlayedRow extends StatelessWidget {
  const RecentlyPlayedRow({super.key});

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: GlassPanel(
        child: LayoutBuilder(
          builder: (BuildContext context, BoxConstraints c) {
            const double gap = 10;
            final double w = (c.maxWidth - 3 * gap) / 4;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'Recently played',
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: <Widget>[
                    for (int i = 0; i < 4; i++)
                      AlbumCard(song: songAt(60 + i), size: w),
                  ],
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// A glass card for a "mix": a cover, a title, who is in it and a play icon.
class GlassFeatureCard extends StatelessWidget {
  const GlassFeatureCard({super.key, required this.seed});

  final int seed;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final Song a = songAt(seed * 3);
    final Song b = songAt(seed * 3 + 1);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: GlassPanel(
        child: Row(
          children: <Widget>[
            CoverArt(seed: seed + 200, size: 88, radius: 14),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    'Daily mix ${1 + seed % 6}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${a.artist}, ${b.artist} and more',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(Icons.play_circle_fill, size: 40, color: scheme.primary),
          ],
        ),
      ),
    );
  }
}

/// A "Made for you" section: a title and a 2-column grid of large cover tiles,
/// [rows] rows of them.
class CoverGridSection extends StatelessWidget {
  const CoverGridSection({super.key, required this.seed, this.rows = 2});

  final int seed;
  final int rows;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Text(
              'Made for you',
              style: theme.textTheme.titleLarge
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
          LayoutBuilder(
            builder: (BuildContext context, BoxConstraints c) {
              const double gap = 14;
              final double w = (c.maxWidth - gap) / 2;
              return Column(
                children: <Widget>[
                  for (int row = 0; row < rows; row++)
                    Padding(
                      padding: EdgeInsets.only(top: row == 0 ? 0 : 14),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: <Widget>[
                          for (int col = 0; col < 2; col++)
                            _LargeTile(
                              song: songAt(seed * 4 + row * 2 + col + 100),
                              size: w,
                            ),
                        ],
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _LargeTile extends StatelessWidget {
  const _LargeTile({required this.song, required this.size});

  final Song song;
  final double size;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return SizedBox(
      width: size,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              boxShadow: <BoxShadow>[
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.28),
                  blurRadius: 18,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: CoverArt(seed: song.id + 100, size: size, radius: 16),
          ),
          const SizedBox(height: 8),
          Text(
            song.album,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.titleSmall,
          ),
          Text(
            song.artist,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}
