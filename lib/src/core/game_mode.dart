enum GameMode { sandbox }

extension GameModeDescription on GameMode {
  String get displayName => 'Sandbox';
  String get description => 'Endless colony building with full creative control.';
}
