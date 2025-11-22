# Side-View Pathfinding Plan

## Goals
- Replace pheromone-based floating steering with deterministic, grid-aware crawling so ants respect tunnels and gravity.
- Keep updates lightweight (tile-based A* or BFS scoped to visible region). Avoid per-ant heavy searches every frame.
- Support both law-abiding workers (for food/home routes) and aggressive enemies (short-term pursuit).

## Approach
1. **Navigation Graph**
   - Represent walkable cells (air/rubble/food) as nodes.
   - Each node connects to orthogonal neighbors if there is ground beneath to stand on (or wall for vertical crawl).
   - Precompute distances or run on-demand BFS (limited radius) using frontier queue stored per-ant or globally cached.

2. **Ant States**
   - Foraging ants: target nearest known food (via pheromone hints). Request path from current tile to target tile.
   - Return-home ants: path back to nest tile (precomputed BFS from nest outward updated when terrain changes).
   - Enemies: chase nearest worker using short BFS toward target tile.

3. **Caching/Invalidation**
   - Maintain world `terrainVersion`. Paths store a version; invalidate when terrain changes (dig/rubble) by comparing versions.
   - Keep shared BFS maps (e.g., nest BFS) computed lazily when requested and stale when terrainVersion changes.

4. **Implementation Steps**
   - Add path request API to `WorldGrid` returning `List<Vector2>` using BFS limited by max distance.
   - Extend `Ant` to store `_path`, `_pathIndex`, recompute when target changes or path stale.
   - Movement uses `_path` direction vector rather than random steering; fall back to exploratory wiggle when no path.

