// Pure Dart, no package under test: the slot pattern of the Real-app lists.
import 'package:flutter_test/flutter_test.dart';
import 'package:inspire_blur_repro/common/real_app_content.dart';

void main() {
  test('slots: recently played first, then a repeating 7-item cycle', () {
    expect(realAppSlotAt(0), RealAppSlot.recentlyPlayed);
    final List<RealAppSlot> cycle = <RealAppSlot>[
      for (int i = 1; i <= 7; i++) realAppSlotAt(i),
    ];
    expect(cycle, <RealAppSlot>[
      RealAppSlot.song,
      RealAppSlot.song,
      RealAppSlot.song,
      RealAppSlot.coverGrid,
      RealAppSlot.song,
      RealAppSlot.song,
      RealAppSlot.glassCard,
    ]);
    for (int i = 1; i < 100; i++) {
      expect(realAppSlotAt(i + 7), realAppSlotAt(i));
    }
  });

  test('the S3 pattern (decor after song n) matches the S1/S2 pattern', () {
    // Walk the S1/S2 slots; whenever a decoration follows a song, that song's
    // number must say so in realAppDecorAfterSong.
    int song = -1;
    for (int item = 1; item < 200; item++) {
      final RealAppSlot slot = realAppSlotAt(item);
      if (slot == RealAppSlot.song) {
        song++;
      } else {
        expect(realAppDecorAfterSong(song), slot, reason: 'item $item');
      }
    }
    // And the converse: no decoration where the slots have none.
    final Set<int> withDecor = <int>{};
    song = -1;
    for (int item = 1; item < 200; item++) {
      if (realAppSlotAt(item) == RealAppSlot.song) {
        song++;
      } else {
        withDecor.add(song);
      }
    }
    for (int n = 0; n < song; n++) {
      expect(realAppDecorAfterSong(n) != null, withDecor.contains(n));
    }
  });
}
