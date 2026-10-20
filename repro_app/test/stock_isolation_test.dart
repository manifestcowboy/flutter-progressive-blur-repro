import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// `lib/main_stock.dart` must compile against pristine inspire_blur 0.4.1, so
/// nothing it imports, directly or not, may reach `lib/patched` or use API
/// that only the patched package has.
void main() {
  test('main_stock.dart never reaches lib/patched or patched-only API', () {
    final Directory lib = Directory('lib');
    final Set<String> seen = <String>{};
    final List<File> queue = <File>[File('lib/main_stock.dart')];
    final RegExp importLine = RegExp(r'''^\s*(?:import|export)\s+['"]([^'"]+)['"]''', multiLine: true);

    while (queue.isNotEmpty) {
      final File file = queue.removeLast();
      if (!seen.add(file.path)) continue;
      final String text = file.readAsStringSync();
      for (final RegExpMatch m in importLine.allMatches(text)) {
        final String target = m.group(1)!;
        if (target.startsWith('package:inspire_blur_repro/')) {
          queue.add(File('lib/${target.substring('package:inspire_blur_repro/'.length)}'));
        } else if (!target.contains(':')) {
          queue.add(File.fromUri(file.uri.resolve(target)));
        }
      }
    }

    expect(seen.length, greaterThan(10));
    expect(
      seen.where((String p) => p.contains('/patched/') || p.endsWith('/main.dart')),
      isEmpty,
    );

    // API that exists only in the patched package.
    final RegExp patchedOnly = RegExp(
      r'Inspire\.childBlurBand\(|InspireChildBlurBandSampler|'
      r'InspireKernelSampling|realUnderlap:|debugInspire|kInspire|'
      r'InspireBandBackground|InspireBoundedSampler|sampling:',
    );
    for (final String path in seen) {
      final String text = File(path).readAsStringSync();
      expect(
        patchedOnly.hasMatch(text),
        isFalse,
        reason: '$path uses patched-only API',
      );
    }
    expect(lib.existsSync(), isTrue);
  });
}
