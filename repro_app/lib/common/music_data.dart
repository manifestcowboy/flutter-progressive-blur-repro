import 'package:flutter/painting.dart';

/// A generated song. Everything derives from [id], so lists are stable.
class Song {
  const Song._({
    required this.id,
    required this.title,
    required this.artist,
    required this.album,
    required this.genre,
    required this.duration,
  });

  final int id;
  final String title;
  final String artist;
  final String album;
  final String genre;
  final Duration duration;

  /// `m:ss`.
  String get durationLabel {
    final int s = duration.inSeconds;
    return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
  }
}

const List<String> _adjectives = <String>[
  'Quiet', 'Golden', 'Slow', 'Paper', 'Open', 'Late', 'Summer', 'Blue', //
  'Wild', 'Easy', 'Long', 'Soft', 'Cold', 'Bright', 'Distant', 'Gentle',
];

const List<String> _nouns = <String>[
  'Morning', 'River', 'Window', 'Train', 'Garden', 'Coast', 'Road', 'Rain', //
  'Harbor', 'Letter', 'Dance', 'Hour', 'Home', 'Light', 'Coffee', 'Orchard',
];

const List<String> _artists = <String>[
  'The Larks', 'Mira Voss', 'North Harbor', 'Juno & Pike', 'Ember Row', //
  'Lena Hart', 'Oak Avenue', 'Sam Okafor', 'Paper Kites Club', 'Ivy Marsh',
  'The Quiet Hours', 'Theo Rinaldi', 'Wren', 'Cedar Lane',
];

const List<String> kGenres = <String>[
  'Pop', 'Rock', 'Jazz', 'Indie', 'Electronic', 'Folk', 'Hip-Hop', //
  'Classical', 'Soul', 'Country',
];

/// The [index]th generated song.
Song songAt(int index) {
  final int a = index % _adjectives.length;
  final int n = (index * 7 + 3) % _nouns.length;
  return Song._(
    id: index,
    title: '${_adjectives[a]} ${_nouns[n]}',
    artist: _artists[(index * 5 + 1) % _artists.length],
    album: '${_nouns[(index ~/ 3 * 5 + 2) % _nouns.length]} '
        '${_adjectives[(index ~/ 3 * 3 + 5) % _adjectives.length]}',
    genre: kGenres[(index * 3) % kGenres.length],
    duration: Duration(seconds: 150 + (index * 37) % 150),
  );
}

/// A saturated colour for [seed], used for cover art, avatars and chips.
Color seedColor(int seed, {double saturation = 0.72, double value = 0.92}) =>
    HSVColor.fromAHSV(1, (seed * 47 + 13) % 360.0, saturation, value).toColor();
