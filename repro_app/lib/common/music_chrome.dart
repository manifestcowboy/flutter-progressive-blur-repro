import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'constants.dart';
import 'music_data.dart';
import 'music_widgets.dart';

/// Animated equalizer bars, repainted by [animation] without rebuilding.
class EqualizerBars extends StatelessWidget {
  const EqualizerBars({super.key, required this.animation, this.size = 20});

  final Animation<double> animation;
  final double size;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.square(size),
      painter: _EqualizerPainter(animation, Theme.of(context).colorScheme.primary),
    );
  }
}

class _EqualizerPainter extends CustomPainter {
  _EqualizerPainter(this.animation, this.color) : super(repaint: animation);

  final Animation<double> animation;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()..color = color;
    final double barWidth = size.width / 7;
    for (int i = 0; i < 4; i++) {
      final double phase = animation.value * 2 * math.pi * (2 + i) + i * 1.3;
      final double h = size.height * (0.25 + 0.75 * (0.5 + 0.5 * math.sin(phase)));
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(i * 2 * barWidth, size.height - h, barWidth, h),
          Radius.circular(barWidth / 2),
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_EqualizerPainter old) => old.color != color;
}

/// The song row for the track that is playing: highlighted, with animated
/// equalizer bars over its cover art. When [animate] is true the bars repaint
/// every frame, which keeps whatever blur covers this row permanently dirty.
class PlayingSongTile extends StatefulWidget {
  const PlayingSongTile({super.key, required this.song, this.animate = true});

  final Song song;
  final bool animate;

  @override
  State<PlayingSongTile> createState() => _PlayingSongTileState();
}

class _PlayingSongTileState extends State<PlayingSongTile>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 3),
  );

  @override
  void initState() {
    super.initState();
    if (widget.animate) _controller.repeat();
  }

  @override
  void didUpdateWidget(PlayingSongTile old) {
    super.didUpdateWidget(old);
    if (widget.animate && !_controller.isAnimating) {
      _controller.repeat();
    } else if (!widget.animate) {
      _controller.stop();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: SongTile(
        song: widget.song,
        highlighted: true,
        leadingOverlay: DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.45),
            borderRadius: BorderRadius.circular(8),
          ),
          child: SizedBox.square(
            dimension: 56,
            child: Center(child: EqualizerBars(animation: _controller)),
          ),
        ),
      ),
    );
  }
}

/// The mini player above the navigation bar. With [animated] it shows a
/// moving progress bar and equalizer, so it repaints every frame.
class NowPlayingBar extends StatefulWidget {
  const NowPlayingBar({super.key, this.animated = false});

  final bool animated;

  @override
  State<NowPlayingBar> createState() => _NowPlayingBarState();
}

class _NowPlayingBarState extends State<NowPlayingBar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 8),
  );

  @override
  void initState() {
    super.initState();
    if (widget.animated) _controller.repeat();
  }

  @override
  void didUpdateWidget(NowPlayingBar old) {
    super.didUpdateWidget(old);
    if (widget.animated && !_controller.isAnimating) {
      _controller.repeat();
    } else if (!widget.animated) {
      _controller.stop();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final Song song = songAt(4);
    return Material(
      color: scheme.surfaceContainerHigh.withValues(alpha: 0.78),
      child: SizedBox(
        height: 64,
        child: Stack(
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: <Widget>[
                  CoverArt(seed: song.id, size: 44, radius: 6),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(song.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleSmall),
                        Text(song.artist,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                                color: scheme.onSurfaceVariant)),
                      ],
                    ),
                  ),
                  EqualizerBars(animation: _controller),
                  const SizedBox(width: 8),
                  const Icon(Icons.pause),
                  const SizedBox(width: 4),
                  const Icon(Icons.skip_next),
                ],
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: AnimatedBuilder(
                animation: _controller,
                builder: (BuildContext context, Widget? _) =>
                    LinearProgressIndicator(
                  value: _controller.value,
                  minHeight: 2,
                  backgroundColor: Colors.transparent,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The translucent top bar drawn over the blurred list: a soft tint, a title
/// row and an optional second row ([bottom], 48 px).
class MusicAppBar extends StatelessWidget {
  const MusicAppBar({
    super.key,
    required this.title,
    this.bottom,
    this.leading,
    this.actions,
  });

  final String title;
  final Widget? bottom;
  final Widget? leading;
  final List<Widget>? actions;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color surface = theme.colorScheme.surface;
    return SizedBox(
      height: kZoneHeight,
      child: Stack(
        children: <Widget>[
          Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: <Color>[
                      surface.withValues(alpha: 0.7),
                      surface.withValues(alpha: 0),
                    ],
                  ),
                ),
              ),
            ),
          ),
          Column(
            children: <Widget>[
              SizedBox(
                height: 56,
                child: Row(
                  children: <Widget>[
                    if (leading != null)
                      leading!
                    else
                      const SizedBox(width: 16),
                    Expanded(
                      child: Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleLarge
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                    ),
                    ...(actions ??
                        <Widget>[
                          IconButton(
                            onPressed: () {},
                            icon: const Icon(Icons.search),
                          ),
                          IconButton(
                            onPressed: () {},
                            icon: const Icon(Icons.more_vert),
                          ),
                        ]),
                  ],
                ),
              ),
              SizedBox(height: 48, child: bottom),
            ],
          ),
        ],
      ),
    );
  }
}

/// The "All / Songs / Albums / Artists" chips under the title.
class LibraryChips extends StatelessWidget {
  const LibraryChips({super.key});

  @override
  Widget build(BuildContext context) {
    const List<String> labels = <String>['All', 'Songs', 'Albums', 'Artists'];
    return ListView.separated(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: labels.length,
      separatorBuilder: (BuildContext context, int i) =>
          const SizedBox(width: 8),
      itemBuilder: (BuildContext context, int i) => Center(
        child: ChoiceChip(
          label: Text(labels[i]),
          selected: i == 0,
          showCheckmark: false,
          onSelected: (_) {},
        ),
      ),
    );
  }
}

/// The mini player stacked on the navigation bar.
class MusicBottomBars extends StatelessWidget {
  const MusicBottomBars({super.key, this.nowPlayingAnimated = false});

  final bool nowPlayingAnimated;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        NowPlayingBar(animated: nowPlayingAnimated),
        NavigationBar(
          backgroundColor: scheme.surface.withValues(alpha: 0.78),
          elevation: 0,
          selectedIndex: 2,
          onDestinationSelected: (_) {},
          destinations: const <NavigationDestination>[
            NavigationDestination(icon: Icon(Icons.home_outlined), label: 'Home'),
            NavigationDestination(icon: Icon(Icons.search), label: 'Search'),
            NavigationDestination(
              icon: Icon(Icons.library_music_outlined),
              label: 'Library',
            ),
          ],
        ),
      ],
    );
  }
}

/// The screen chrome around a music list: [body] fills the area, the
/// translucent top bar sits over it and, with [bottomBars], so do the mini
/// player and navigation bar. None of the chrome is part of the blurred child.
class MusicFrame extends StatelessWidget {
  const MusicFrame({
    super.key,
    required this.title,
    required this.body,
    this.bottom,
    this.leading,
    this.actions,
    this.bottomBars = false,
    this.nowPlayingAnimated = false,
  });

  final String title;
  final Widget body;
  final Widget? bottom;
  final Widget? leading;
  final List<Widget>? actions;
  final bool bottomBars;
  final bool nowPlayingAnimated;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Theme.of(context).colorScheme.surface,
      child: Stack(
        children: <Widget>[
          Positioned.fill(child: body),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: MusicAppBar(
              title: title,
              bottom: bottom,
              leading: leading,
              actions: actions,
            ),
          ),
          if (bottomBars)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: MusicBottomBars(nowPlayingAnimated: nowPlayingAnimated),
            ),
        ],
      ),
    );
  }
}
