import 'dart:async';

import 'game_event.dart';

class GameEventBus {
  GameEventBus();

  final StreamController<GameEvent> _controller =
      StreamController<GameEvent>.broadcast();

  Stream<GameEvent> get events => _controller.stream;

  Stream<T> on<T extends GameEvent>() {
    return _controller.stream.where((event) => event is T).cast<T>();
  }

  void emit(GameEvent event) {
    if (_controller.isClosed) {
      return;
    }
    _controller.add(event);
  }

  Future<void> dispose() async {
    await _controller.close();
  }
}
