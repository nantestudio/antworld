# Repository Guidelines

## Project Structure & Module Organization
AntWorld is a Flutter + Flame simulation.
- `lib/main.dart` wires Flutter widgets to the Flame game.
- `lib/src/game/ant_world_game.dart` hosts the Flame loop and orchestrates overlays.
- `lib/src/simulation/{ant.dart,colony_simulation.dart,world_grid.dart,...}` encapsulate domain physics, sensors, and world generation. Keep new simulation logic here so it stays platform agnostic.
- `lib/src/ui/ant_hud.dart` and `assets/fonts|icons` contain HUD widgets and art.
- `lib/src/services/analytics_service.dart` centralizes telemetry hookups (Firebase options live in `lib/firebase_options.dart`).
- Tests belong in `test/`, mirroring the lib path (e.g., `test/simulation/world_grid_test.dart`).

## Build, Test, and Development Commands
- `flutter pub get` – install packages after editing `pubspec.yaml`.
- `flutter run -d macos` or desired device – hot-reload simulator.
- `flutter analyze` – static analysis with `flutter_lints`.
- `dart format lib test` – enforce canonical formatting before review.
- `flutter test --coverage` – execute unit/widget tests; produces `coverage/lcov.info`.
- `flutter build web` or `flutter build macos` – release builds; run before tagging a release.

## Coding Style & Naming Conventions
Follow `flutter_lints` (see `analysis_options.yaml`). Use 2-space indentation, `lower_snake_case.dart` files, PascalCase classes, camelCase members, SCREAMING_SNAKE_CASE constants. Keep Flame components pure-Dart (no platform imports). Prefer small, testable methods that mutate state through `ColonySimulation` APIs. Run `flutter analyze` until clean instead of sprinkling `ignore` comments.

## Testing Guidelines
Extend `test/widget_test.dart` and create focused files mirroring `lib/src`. Name tests `group('worldGrid', ...)` / `test('returns pheromone gradient')`. Mock I/O-free classes; deterministic seeds belong in `simulation_config.dart`. Add regression tests for every colony rule or HUD control you ship. Pull requests should keep coverage stable or higher; justify gaps in the PR description.

## Commit & Pull Request Guidelines
Commits in history use concise, imperative summaries (e.g., “Fix ConcurrentModificationError in ant iteration loops”). Limit body lines to 72 chars and reference issues (`Fixes #123`). For PRs include: TL;DR, screenshots/gifs for UI, reproduction steps, and `flutter test` output. Link to PLAN.md items when closing large tasks. Request review once CI (analyze + test) is green and conflicts resolved.

## Security & Configuration Tips
Keep secrets out of source control; Firebase credentials auto-load from `firebase_options.dart`, so avoid sprinkling keys elsewhere. Use Flutter’s `--dart-define` for experimental toggles. Assets added under `assets/` must be declared in `pubspec.yaml`.
