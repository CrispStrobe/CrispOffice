#!/usr/bin/env python3
"""Prepare a diagnostic copy without changing any original test assertion."""
from pathlib import Path
import hashlib
import json
import subprocess

folder = Path(__file__).resolve().parent
repo = folder.parents[4]
commit = "596430dcb816dd418204d62e78f4dc518afdc0e1"
path = "packages/quds_office_editor/test/office_dark_slide_test.dart"
source = subprocess.check_output(["git", "show", f"{commit}:{path}"], cwd=repo).decode()
instrumented = source.replace("import 'dart:ui' as ui;", "import 'dart:ui' as ui;\nimport 'dart:convert';\nimport 'dart:io';")
instrumented = instrumented.replace("const _boundary = ValueKey('dark-slide');", r"""const _boundary = ValueKey('dark-slide');
var _captureIndex = 0;
final _diagnosticFolder = Directory(Platform.environment['QUDS_REVIEW_RASTER_DIR']!);

void _reportRaster(String name, _Raster raster) {
  final areas = <String, ui.Rect>{
    'whiteCell': const ui.Rect.fromLTWH(384, 33, 290, 25),
    'darkCell': const ui.Rect.fromLTWH(384, 93, 290, 25),
    'firstShape': const ui.Rect.fromLTWH(38, 28, 280, 28),
  };
  final output = <String, Object?>{'name': name, 'width': raster.width, 'height': raster.height};
  for (final entry in areas.entries) {
    final histogram = <int, int>{};
    final area = entry.value;
    for (var y = area.top.floor(); y < area.bottom.ceil(); y++) {
      for (var x = area.left.floor(); x < area.right.ceil(); x++) {
        final offset = (y * raster.width + x) * 4;
        final rgb = (raster.bytes[offset] << 16) | (raster.bytes[offset + 1] << 8) | raster.bytes[offset + 2];
        histogram[rgb] = (histogram[rgb] ?? 0) + 1;
      }
    }
    final ranked = histogram.entries.toList()..sort((a,b) => b.value.compareTo(a.value));
    final counts = <String, Object?>{};
    for (final target in [0x000000, 0xF2F2F2, 0xFFFFFF]) {
      counts[target.toRadixString(16).padLeft(6, '0')] = {
        for (final tolerance in [3, 8, 16, 24, 32, 48, 64]) '$tolerance': histogram.entries.where((pixel) {
          for (final shift in [16, 8, 0]) {
            if ((((pixel.key >> shift) & 255) - ((target >> shift) & 255)).abs() > tolerance) return false;
          }
          return true;
        }).fold<int>(0, (sum, pixel) => sum + pixel.value),
      };
    }
    output[entry.key] = {
      'countsByRgbAndTolerance': counts,
      'topColors': ranked.take(25).map((e) => {'rgb': e.key.toRadixString(16).padLeft(6,'0'), 'pixels': e.value}).toList(),
    };
  }
  File('${_diagnosticFolder.path}/$name.json').writeAsStringSync(const JsonEncoder.withIndent('  ').convert(output));
  print(jsonEncode({'diagnostic': name, 'areas': output}));
}
""")
instrumented = instrumented.replace("final pixels = (await image.toByteData(", r"""final png = await image.toByteData(format: ui.ImageByteFormat.png);
      await File('${_diagnosticFolder.path}/capture-${_captureIndex++}.png').writeAsBytes(png!.buffer.asUint8List());
      final pixels = (await image.toByteData(""")
instrumented = instrumented.replace("final dark = await _paint(tester, slide);", r"""final dark = await _paint(tester, slide);
      _reportRaster('dark-adapted', dark);
      final unadapted = await _paint(tester, slide, theme: OfficeTheme.dark.copyWith(adaptDocumentColors: false));
      _reportRaster('dark-unadapted-control', unadapted);
      for (final area in <String, ui.Rect>{
        'whiteCell': const ui.Rect.fromLTWH(384, 33, 290, 25),
        'darkCell': const ui.Rect.fromLTWH(384, 93, 290, 25),
      }.entries) {
        var changed = 0;
        for (var y = area.value.top.floor(); y < area.value.bottom.ceil(); y++) {
          for (var x = area.value.left.floor(); x < area.value.right.ceil(); x++) {
            final offset = (y * dark.width + x) * 4;
            if (List.generate(4, (index) => dark.bytes[offset+index]).join(',') !=
                List.generate(4, (index) => unadapted.bytes[offset+index]).join(',')) changed++;
          }
        }
        print(jsonEncode({'diagnostic': 'control-comparison', 'area': area.key, 'changedPixels': changed}));
      }""")
diagnostic = folder / "dark_slide_raster_diagnostic_test.dart"
diagnostic.write_text(instrumented)
(folder / "dark-slide-diagnostic-source.json").write_text(json.dumps({
    "source_commit": commit, "source_path": path,
    "original_sha256": hashlib.sha256(source.encode()).hexdigest(),
    "instrumented_sha256": hashlib.sha256(instrumented.encode()).hexdigest(),
    "method": "Copy exact committed test; add PNG/JSON captures and a disabled-adaptation control before the original unchanged assertions. Original test source is never changed.",
    "qualification_counts_added": 0,
}, indent=2) + "\n")
print(diagnostic)
