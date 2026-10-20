import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'music_data.dart';

/// Generated cover art: a two-colour gradient with a ring and a stripe, so it
/// has hard edges and saturated colour to show blur against.
class CoverArt extends StatelessWidget {
  const CoverArt({
    super.key,
    required this.seed,
    this.size = 56,
    this.radius = 8,
  });

  final int seed;
  final double size;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: size,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: CustomPaint(painter: _CoverPainter(seed)),
      ),
    );
  }
}

class _CoverPainter extends CustomPainter {
  _CoverPainter(this.seed);

  final int seed;

  @override
  void paint(Canvas canvas, Size size) {
    final Rect rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[seedColor(seed), seedColor(seed + 5, value: 0.6)],
        ).createShader(rect),
    );
    final double u = size.shortestSide;
    final Paint white = Paint()..color = Colors.white.withValues(alpha: 0.85);
    canvas.drawCircle(
      Offset(u * (0.3 + 0.1 * (seed % 4)), u * 0.65),
      u * 0.22,
      white
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(2, u * 0.06),
    );
    canvas.drawRect(
      Rect.fromLTWH(0, u * 0.16, u, math.max(3, u * 0.08)),
      Paint()..color = Colors.black.withValues(alpha: 0.28),
    );
  }

  @override
  bool shouldRepaint(_CoverPainter old) => old.seed != seed;
}

/// A song row: cover art, title, artist and album, duration.
class SongTile extends StatelessWidget {
  const SongTile({
    super.key,
    required this.song,
    this.trailing,
    this.leadingOverlay,
    this.highlighted = false,
  });

  final Song song;

  /// Replaces the duration and the overflow icon.
  final Widget? trailing;

  /// Drawn over the cover art, e.g. the playing-now bars.
  final Widget? leadingOverlay;

  final bool highlighted;

  static const double height = 72;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    return SizedBox(
      height: height,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: highlighted ? scheme.secondaryContainer : null,
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: <Widget>[
              Stack(
                alignment: Alignment.center,
                children: <Widget>[
                  CoverArt(seed: song.id),
                  ?leadingOverlay,
                ],
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      song.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium,
                    ),
                    Text(
                      '${song.artist} · ${song.album}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              if (trailing != null)
                trailing!
              else ...<Widget>[
                Text(
                  song.durationLabel,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: scheme.onSurfaceVariant),
                ),
                const SizedBox(width: 4),
                Icon(Icons.more_vert, color: scheme.onSurfaceVariant),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// A square album card: cover art over a title and an artist.
class AlbumCard extends StatelessWidget {
  const AlbumCard({super.key, required this.song, this.size = 108});

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
          CoverArt(seed: song.id + 100, size: size, radius: 12),
          const SizedBox(height: 6),
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

/// A row of three album cards, the "albums grid" in a list.
class AlbumRow extends StatelessWidget {
  const AlbumRow({super.key, required this.index});

  final int index;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints c) {
        // Three cards across 16 px side padding and 12 px gaps; the height is
        // the cover plus room for two lines of text.
        final double w = (c.maxWidth - 32 - 24) / 3;
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: SizedBox(
            height: w + 56,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: <Widget>[
                for (int i = 0; i < 3; i++)
                  AlbumCard(song: songAt(index * 3 + i + 40), size: w),
              ],
            ),
          ),
        );
      },
    );
  }
}
