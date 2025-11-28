import 'package:flame/components.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:antworld/src/simulation/room_blueprint.dart';
import 'package:antworld/src/simulation/simulation_config.dart';
import 'package:antworld/src/simulation/world_grid.dart';

void main() {
  group('RoomBlueprintManager', () {
    test('rejects blueprints that are too small', () {
      final world = _buildTestWorld();
      final manager = RoomBlueprintManager();

      manager.startPainting(RoomType.nursery, 0);
      manager.addPaintCell(5, 5, world);

      final result = manager.finishPainting(world);
      expect(result.success, isFalse);
      expect(result.error, contains('too small'));
      expect(manager.blueprints, isEmpty);
    });

    test('creates blueprint that queues connection path', () {
      final world = _buildTestWorld();
      final manager = RoomBlueprintManager();

      manager.startPainting(RoomType.foodStorage, 0);
      for (var x = 10; x < 16; x++) {
        for (var y = 10; y < 18; y++) {
          manager.addPaintCell(x, y, world);
        }
      }

      final result = manager.finishPainting(world);
      expect(result.success, isTrue);
      expect(manager.blueprints, hasLength(1));
      final blueprint = manager.blueprints.first;
      expect(blueprint.cells.length, greaterThanOrEqualTo(32));
      // Connection path should either be empty (adjacent) or a list of cells.
      expect(blueprint.connectionPath, isNotNull);
      // Dig progress should be zero in a fresh world.
      expect(blueprint.buildProgress(world), equals(0));
    });

    test('prevents overlapping blueprints', () {
      final world = _buildTestWorld();
      final manager = RoomBlueprintManager();

      manager.startPainting(RoomType.barracks, 0);
      for (var x = 6; x < 13; x++) {
        for (var y = 6; y < 12; y++) {
          manager.addPaintCell(x, y, world);
        }
      }
      expect(manager.finishPainting(world).success, isTrue);

      manager.startPainting(RoomType.barracks, 0);
      for (var x = 8; x < 15; x++) {
        for (var y = 8; y < 14; y++) {
          manager.addPaintCell(x, y, world);
        }
      }
      final overlap = manager.finishPainting(world);
      expect(overlap.success, isFalse);
      expect(overlap.error, contains('overlap'));
    });
  });
}

WorldGrid _buildTestWorld() {
  final config = const SimulationConfig(cols: 40, rows: 40);
  final world = WorldGrid(
    config,
    nestOverride: Vector2(5, 5),
    nest1Override: Vector2(30, 30),
  );
  for (var i = 0; i < world.cells.length; i++) {
    world.cells[i] = CellType.dirt.index;
  }
  return world;
}
