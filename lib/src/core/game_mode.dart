enum GameMode { sandbox, zenMode, campaign, dailyChallenge }

extension GameModeDescription on GameMode {
  String get displayName {
    switch (this) {
      case GameMode.sandbox:
        return 'Sandbox';
      case GameMode.zenMode:
        return 'Zen Mode';
      case GameMode.campaign:
        return 'Campaign';
      case GameMode.dailyChallenge:
        return 'Daily Challenge';
    }
  }

  String get description {
    switch (this) {
      case GameMode.sandbox:
        return 'Endless colony building with full creative control.';
      case GameMode.zenMode:
        return 'Relaxed play with milestone tracking and no pressure.';
      case GameMode.campaign:
        return 'Level-driven objectives with structured goals.';
      case GameMode.dailyChallenge:
        return 'Rotating scenarios with time-limited objectives.';
    }
  }
}
