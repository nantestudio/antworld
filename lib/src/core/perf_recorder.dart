import 'package:flutter/foundation.dart';

import '../game/ant_world_game.dart';

// Conditional import for file I/O (not available on web)
import 'perf_recorder_io.dart' if (dart.library.html) 'perf_recorder_stub.dart'
    as io;

/// Writes perf samples to a temporary log so we can inspect sessions after the fact.
/// On web, this is a no-op since file system access isn't available.
class PerfRecorder {
  PerfRecorder({String? filename}) : _filename = filename ?? 'antworld_perf.log';

  final String _filename;
  VoidCallback? _listener;

  /// Attach to a perf ValueListenable and start logging once per update.
  void attach(ValueListenable<PerfSample> perf) {
    // Skip file logging on web
    if (kIsWeb) return;

    _listener = () {
      final sample = perf.value;
      final now = DateTime.now().toIso8601String();
      final line =
          '$now fps=${sample.fps.toStringAsFixed(1)} updateMs=${sample.updateMs.toStringAsFixed(2)}';
      try {
        io.writeToLogFile(_filename, line);
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

  String get logPath => kIsWeb ? '' : io.getLogPath(_filename);
}
