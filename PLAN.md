# Side-View Colony Plan

- [ ] World & Physics Foundation
  - [x] Reorient grid to side-view (Y up), add surface layer that connects to outside world
  - [x] Add tile support tracking + gravity so unsupported dirt falls as rubble
  - [x] Ensure world generation carves grounded rooms/tunnels, including a main shaft to the surface
  - [x] Clamp all spawn locations (ants, food) to existing open air cells
- [ ] Ant Locomotion Rewrite
  - [x] Replace free-flight steering with platformer-style walking, gravity, and collision
  - [x] Implement digging that respects support checks and produces rubble
  - [x] Update pathfinding to grid-based walkable routes
- [ ] Rendering & Performance
  - [ ] Flip camera/rendering to side view with parallax background
  - [ ] Visualize rubble/falling debris efficiently
  - [ ] Validate performance (profiling, caps on falling tile updates)
