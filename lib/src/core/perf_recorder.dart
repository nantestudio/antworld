import 'dart:io';

import 'package:flutter/foundation.dart';

import '../game/ant_world_game.dart';

/// Writes perf samples to a temporary log so we can inspect sessions after the fact.
class PerfRecorder {
  PerfRecorder({String? filename})
    : _file = File(
        '${Directory.systemTemp.path}/${filename ?? 'antworld_perf.log'}',
      );

  final File _file;
  VoidCallback? _listener;

  /// Attach to a perf ValueListenable and start logging once per update.
  void attach(ValueListenable<PerfSample> perf) {
    _listener = () {
      final sample = perf.value;
      final now = DateTime.now().toIso8601String();
      final line =
          '$now fps=${sample.fps.toStringAsFixed(1)} updateMs=${sample.updateMs.toStringAsFixed(2)}';
      try {
        _file.writeAsStringSync('$line\n', mode: FileMode.append);
      } catch (_) {
        // Ignore logging errors to avoid impacting runtime.
      }
    };
    perf.addListener(_listener!);
  }

  void dispose(ValueListenable<PerfSample> perf) {
    final listener = _listener;
    if (listener != null) {
      perf.removeListener(listener);
    }
  }

  String get logPath => _file.path;
}
