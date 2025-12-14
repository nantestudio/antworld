import 'dart:io';
import 'package:flame/components.dart';
import 'package:flutter/foundation.dart';
import '../simulation/world_grid.dart';
import '../simulation/ant.dart';

/// Game event types for structured logging
enum GameEventType {
  // Lifecycle events
  antBorn,
  antDied,
  eggLaid,
  eggHatched,
  larvaeMatured,

  // Colony events
  roomPlanned,
  roomBuilt,
  tunnelBuilt,
  roomExpansionNeeded,

  // Resource events
  foodCollected,
  foodDelivered,
  foodSpawned,

  // Combat events
  combatStarted,
  combatEnded,
  colonyTakeover,

  // Behavior events
  antStateChanged,
  queenDecision,
  builderTaskAssigned,
  defenseAlert,

  // Mother Nature events
  environmentEvent,

  // Periodic snapshots
  stateSnapshot,
}

/// A single game event for logging
class GameEvent {
  GameEvent({
    required this.type,
    required this.timestamp,
    this.colonyId,
    this.message,
    this.data,
  });

  final GameEventType type;
  final double timestamp; // In-game time (seconds)
  final int? colonyId;
  final String? message;
  final Map<String, dynamic>? data;

  Map<String, dynamic> toJson() => {
    'type': type.name,
    'time': timestamp.toStringAsFixed(1),
    'day': (timestamp / 60).floor() + 1,
    if (colonyId != null) 'colony': colonyId,
    if (message != null) 'msg': message,
    if (data != null) ...data!,
  };

  @override
  String toString() {
    final day = (timestamp / 60).floor() + 1;
    final timeStr = 'D$day ${timestamp.toStringAsFixed(0)}s';
    final colonyStr = colonyId != null ? ' [C$colonyId]' : '';
    final dataStr = data != null ? ' $data' : '';
    return '[$timeStr]$colonyStr ${type.name}: ${message ?? ''}$dataStr';
  }
}

/// Game logger service that writes events to a file for monitoring
class GameLogger {
  GameLogger._();
  static final GameLogger instance = GameLogger._();

  File? _logFile;
  IOSink? _sink;
  bool _enabled = false;
  bool _useConsole = false; // Fallback to console if file access fails
  double _lastSnapshotTime = 0;
  static const double _snapshotInterval = 30.0; // Every 30 seconds of game time

  // Session tracking for correlating logs with code changes
  String _sessionId = '';
  String _sessionNotes = '';

  // Buffered events for batch writing
  final List<GameEvent> _eventBuffer = [];
  static const int _bufferSize = 10; // Small buffer for frequent updates

  /// Initialize the logger with a file path and session info
  Future<void> init({
    String? path,
    String? sessionNotes,
  }) async {
    // Generate session ID from timestamp
    final now = DateTime.now();
    _sessionId = '${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}_${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}';
    _sessionNotes = sessionNotes ?? 'No notes';

    // Use user's home directory for better sandbox compatibility
    final home = Platform.environment['HOME'] ?? '/tmp';
    final logPath = path ?? '$home/antworld_game.log';

    try {
      _logFile = File(logPath);

      // Clear previous log
      if (await _logFile!.exists()) {
        await _logFile!.delete();
      }

      _sink = _logFile!.openWrite(mode: FileMode.append);
      _enabled = true;

      // Write session header
      _sink!.writeln('╔════════════════════════════════════════════════════════════════╗');
      _sink!.writeln('║ ANTWORLD GAME LOG                                              ║');
      _sink!.writeln('║ Session: $_sessionId                                            ║');
      _sink!.writeln('║ Started: ${now.toIso8601String()}                     ║');
      _sink!.writeln('║ Notes: $_sessionNotes');
      _sink!.writeln('╚════════════════════════════════════════════════════════════════╝');
      _sink!.writeln('');
      await _sink!.flush();
      debugPrint('GameLogger: Writing to $logPath (session $_sessionId)');

      _log(GameEvent(
        type: GameEventType.stateSnapshot,
        timestamp: 0,
        message: 'Game logger initialized',
        data: {'logFile': logPath, 'session': _sessionId},
      ));
    } catch (e) {
      // Fallback to console logging if file access fails (common in sandboxed apps)
      _enabled = true;
      _useConsole = true;
      debugPrint('GameLogger: File logging failed ($e), using console output');
      debugPrint('╔════════════════════════════════════════════════════════════════╗');
      debugPrint('║ ANTWORLD GAME LOG (Console Mode)                               ║');
      debugPrint('║ Session: $_sessionId                                            ║');
      debugPrint('║ Notes: $_sessionNotes');
      debugPrint('╚════════════════════════════════════════════════════════════════╝');
    }
  }

  /// Get current session ID
  String get sessionId => _sessionId;

  /// Close the logger
  Future<void> close() async {
    await _flush();
    await _sink?.close();
    _sink = null;
    _enabled = false;
  }

  /// Log a game event
  void _log(GameEvent event) {
    if (!_enabled) return;
    _eventBuffer.add(event);
    if (_eventBuffer.length >= _bufferSize) {
      _flush();
    }
  }

  /// Flush buffered events to file or console
  Future<void> _flush() async {
    if (_eventBuffer.isEmpty) return;

    if (_useConsole) {
      for (final event in _eventBuffer) {
        debugPrint(event.toString());
      }
      _eventBuffer.clear();
    } else if (_sink != null) {
      for (final event in _eventBuffer) {
        _sink!.writeln(event.toString());
      }
      _eventBuffer.clear();
      await _sink!.flush();
    }
  }

  // ============ Lifecycle Events ============

  void logAntBorn(double time, int colonyId, AntCaste caste, Vector2 position) {
    _log(GameEvent(
      type: GameEventType.antBorn,
      timestamp: time,
      colonyId: colonyId,
      message: '${caste.name} born',
      data: {'caste': caste.name, 'pos': '(${position.x.toInt()},${position.y.toInt()})'},
    ));
  }

  void logAntDied(double time, int colonyId, AntCaste caste, String cause) {
    _log(GameEvent(
      type: GameEventType.antDied,
      timestamp: time,
      colonyId: colonyId,
      message: '${caste.name} died: $cause',
      data: {'caste': caste.name, 'cause': cause},
    ));
  }

  void logEggLaid(double time, int colonyId, Vector2 position) {
    _log(GameEvent(
      type: GameEventType.eggLaid,
      timestamp: time,
      colonyId: colonyId,
      message: 'Queen laid egg',
      data: {'pos': '(${position.x.toInt()},${position.y.toInt()})'},
    ));
  }

  void logEggHatched(double time, int colonyId) {
    _log(GameEvent(
      type: GameEventType.eggHatched,
      timestamp: time,
      colonyId: colonyId,
      message: 'Egg hatched into larva',
    ));
  }

  void logLarvaeMatured(double time, int colonyId, AntCaste caste) {
    _log(GameEvent(
      type: GameEventType.larvaeMatured,
      timestamp: time,
      colonyId: colonyId,
      message: 'Larva matured into ${caste.name}',
      data: {'caste': caste.name},
    ));
  }

  // ============ Colony Events ============

  void logRoomPlanned(double time, int colonyId, RoomType type, Vector2 center) {
    _log(GameEvent(
      type: GameEventType.roomPlanned,
      timestamp: time,
      colonyId: colonyId,
      message: '${type.name} room planned',
      data: {'roomType': type.name, 'center': '(${center.x.toInt()},${center.y.toInt()})'},
    ));
  }

  void logRoomBuilt(double time, int colonyId, RoomType type, Vector2 center) {
    _log(GameEvent(
      type: GameEventType.roomBuilt,
      timestamp: time,
      colonyId: colonyId,
      message: '${type.name} room completed',
      data: {'roomType': type.name, 'center': '(${center.x.toInt()},${center.y.toInt()})'},
    ));
  }

  void logTunnelBuilt(double time, int colonyId, int length, int width) {
    _log(GameEvent(
      type: GameEventType.tunnelBuilt,
      timestamp: time,
      colonyId: colonyId,
      message: 'Tunnel built (${length}cells, width $width)',
      data: {'length': length, 'width': width},
    ));
  }

  // ============ Resource Events ============

  void logFoodCollected(double time, int colonyId, Vector2 position) {
    _log(GameEvent(
      type: GameEventType.foodCollected,
      timestamp: time,
      colonyId: colonyId,
      message: 'Food collected',
      data: {'pos': '(${position.x.toInt()},${position.y.toInt()})'},
    ));
  }

  void logFoodDelivered(double time, int colonyId, int totalFood) {
    _log(GameEvent(
      type: GameEventType.foodDelivered,
      timestamp: time,
      colonyId: colonyId,
      message: 'Food delivered (total: $totalFood)',
      data: {'total': totalFood},
    ));
  }

  // ============ Combat Events ============

  void logCombat(double time, int attackerColony, int defenderColony, String result) {
    _log(GameEvent(
      type: GameEventType.combatEnded,
      timestamp: time,
      message: 'Combat: Colony $attackerColony vs $defenderColony - $result',
      data: {'attacker': attackerColony, 'defender': defenderColony, 'result': result},
    ));
  }

  void logDefenseAlert(double time, int colonyId, Vector2 threatPos) {
    _log(GameEvent(
      type: GameEventType.defenseAlert,
      timestamp: time,
      colonyId: colonyId,
      message: 'Defense alert triggered',
      data: {'threat': '(${threatPos.x.toInt()},${threatPos.y.toInt()})'},
    ));
  }

  // ============ Behavior Events ============

  void logQueenDecision(double time, int colonyId, String decision) {
    _log(GameEvent(
      type: GameEventType.queenDecision,
      timestamp: time,
      colonyId: colonyId,
      message: decision,
    ));
  }

  void logBuilderTask(double time, int colonyId, String task, Vector2 target) {
    _log(GameEvent(
      type: GameEventType.builderTaskAssigned,
      timestamp: time,
      colonyId: colonyId,
      message: 'Builder: $task',
      data: {'task': task, 'target': '(${target.x.toInt()},${target.y.toInt()})'},
    ));
  }

  // ============ Mother Nature Events ============

  void logEnvironmentEvent(double time, String eventType, String description) {
    _log(GameEvent(
      type: GameEventType.environmentEvent,
      timestamp: time,
      message: '$eventType: $description',
      data: {'event': eventType},
    ));
  }

  // ============ State Snapshots ============

  /// Log periodic state snapshot - call this from simulation update
  void maybeLogSnapshot(
    double time, {
    required int day,
    required Map<int, int> antCounts,
    required Map<int, int> foodCounts,
    required Map<int, Map<AntCaste, int>> casteCounts,
    required Map<int, int> roomCounts,
    required Map<int, int> tunnelCounts,
  }) {
    if (time - _lastSnapshotTime < _snapshotInterval) return;
    _lastSnapshotTime = time;

    final snapshot = StringBuffer();
    snapshot.writeln('\n========== STATE SNAPSHOT (Day $day, ${time.toStringAsFixed(0)}s) ==========');

    for (final colonyId in antCounts.keys.toList()..sort()) {
      final ants = antCounts[colonyId] ?? 0;
      final food = foodCounts[colonyId] ?? 0;
      final rooms = roomCounts[colonyId] ?? 0;
      final tunnels = tunnelCounts[colonyId] ?? 0;
      final castes = casteCounts[colonyId] ?? {};

      snapshot.writeln('Colony $colonyId: $ants ants, $food food, $rooms rooms, $tunnels tunnels');

      final casteStr = castes.entries
          .where((e) => e.value > 0)
          .map((e) => '${e.key.name}:${e.value}')
          .join(', ');
      if (casteStr.isNotEmpty) {
        snapshot.writeln('  Castes: $casteStr');
      }
    }
    snapshot.writeln('================================================================\n');

    _log(GameEvent(
      type: GameEventType.stateSnapshot,
      timestamp: time,
      message: snapshot.toString(),
    ));

    // Force flush on snapshots
    _flush();
  }

  /// Log a simple message
  void log(double time, String message, {int? colonyId}) {
    _log(GameEvent(
      type: GameEventType.stateSnapshot,
      timestamp: time,
      colonyId: colonyId,
      message: message,
    ));
  }
}
