import 'dart:io';
import 'dart:math' as math;

import 'package:image/image.dart' as img;

const fullDiffVisualNames = <String>[
  '00-overview-hunk',
  '01-diff-inline',
  '02-diff-split',
  '04-blame-view',
  '05-history-view',
  '06-focus-mode',
  '07-ignore-whitespace',
  '08-wrap-lines',
  '09-next-change',
  '10-algorithm-histogram',
  '11-responsive-650',
  '12-responsive-480',
  '13-font-and-back',
  '14-algorithm-tooltip',
  '15-unavailable-panel',
  '16-history-detail',
  '17-history-detail-split',
];

class VisualDiffMetrics {
  const VisualDiffMetrics({
    required this.width,
    required this.height,
    required this.totalPixels,
    required this.changedPixels,
    required this.meanAbsoluteChannelDifference,
    required this.maxChannelDifference,
  });

  final int width;
  final int height;
  final int totalPixels;
  final int changedPixels;
  final double meanAbsoluteChannelDifference;
  final int maxChannelDifference;

  double get changedPercent =>
      totalPixels == 0 ? 0 : changedPixels * 100 / totalPixels;
}

VisualDiffMetrics writeVisualDiff({
  required File referenceFile,
  required File actualFile,
  required File differenceFile,
  required File sideBySideFile,
}) {
  // The approved assets use .png names but currently contain JPEG bytes.
  // Decode from the signature so both the references and captured PNGs work.
  final reference = img.decodeImage(referenceFile.readAsBytesSync());
  final actual = img.decodeImage(actualFile.readAsBytesSync());
  if (reference == null) {
    throw FormatException('Cannot decode ${referenceFile.path}');
  }
  if (actual == null) {
    throw FormatException('Cannot decode ${actualFile.path}');
  }
  if (reference.width != actual.width || reference.height != actual.height) {
    throw StateError(
      '${actualFile.path} size ${actual.width}x${actual.height} != '
      '${reference.width}x${reference.height}',
    );
  }

  final difference = img.Image(
    width: reference.width,
    height: reference.height,
  );
  var changedPixels = 0;
  var channelDifferenceTotal = 0;
  var maxChannelDifference = 0;
  for (var y = 0; y < reference.height; y++) {
    for (var x = 0; x < reference.width; x++) {
      final expected = reference.getPixel(x, y);
      final observed = actual.getPixel(x, y);
      final red = (expected.r - observed.r).abs().toInt();
      final green = (expected.g - observed.g).abs().toInt();
      final blue = (expected.b - observed.b).abs().toInt();
      if (red != 0 || green != 0 || blue != 0) changedPixels++;
      channelDifferenceTotal += red + green + blue;
      maxChannelDifference = math.max(
        maxChannelDifference,
        math.max(red, math.max(green, blue)),
      );
      difference.setPixelRgba(x, y, red, green, blue, 255);
    }
  }

  final sideBySide = img.Image(
    width: reference.width * 2,
    height: reference.height,
  );
  img.compositeImage(sideBySide, reference);
  img.compositeImage(sideBySide, actual, dstX: reference.width);
  differenceFile.parent.createSync(recursive: true);
  sideBySideFile.parent.createSync(recursive: true);
  differenceFile.writeAsBytesSync(img.encodePng(difference));
  sideBySideFile.writeAsBytesSync(img.encodePng(sideBySide));

  final totalPixels = reference.width * reference.height;
  return VisualDiffMetrics(
    width: reference.width,
    height: reference.height,
    totalPixels: totalPixels,
    changedPixels: changedPixels,
    meanAbsoluteChannelDifference: totalPixels == 0
        ? 0
        : channelDifferenceTotal / (totalPixels * 3),
    maxChannelDifference: maxChannelDifference,
  );
}

void main() {
  final referenceRoot = Directory('docs/superpowers/specs/assets/full-diff-qa');
  final actualRoot = Directory(
    'docs/superpowers/verification/full-diff-qa/actual',
  );
  final outputRoot = Directory(
    'docs/superpowers/verification/full-diff-qa/diff',
  )..createSync(recursive: true);

  stdout.writeln(
    'name,width,height,changed_pixels,total_pixels,changed_percent,'
    'mean_abs_rgb,max_rgb',
  );
  for (final name in fullDiffVisualNames) {
    final metrics = writeVisualDiff(
      referenceFile: File('${referenceRoot.path}/$name.png'),
      actualFile: File('${actualRoot.path}/$name.png'),
      differenceFile: File('${outputRoot.path}/$name.png'),
      sideBySideFile: File('${outputRoot.path}/$name-side-by-side.png'),
    );
    stdout.writeln(
      '$name,${metrics.width},${metrics.height},${metrics.changedPixels},'
      '${metrics.totalPixels},${metrics.changedPercent.toStringAsFixed(4)},'
      '${metrics.meanAbsoluteChannelDifference.toStringAsFixed(4)},'
      '${metrics.maxChannelDifference}',
    );
  }
}
