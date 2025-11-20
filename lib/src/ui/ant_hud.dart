import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../game/ant_world_game.dart';
import '../simulation/colony_simulation.dart';
import '../state/simulation_storage.dart';

class AntHud extends StatefulWidget {
  const AntHud({
    super.key,
    required this.simulation,
    required this.game,
    required this.storage,
  });

  final ColonySimulation simulation;
  final AntWorldGame game;
  final SimulationStorage storage;

  @override
  State<AntHud> createState() => _AntHudState();
}

class _AntHudState extends State<AntHud> {
  bool _showSettings = false;
  late int _pendingCols;
  late int _pendingRows;
  bool _saving = false;
  bool _generatingMap = false;

  @override
  void initState() {
    super.initState();
    _pendingCols = widget.simulation.config.cols;
    _pendingRows = widget.simulation.config.rows;
  }

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                _buildTopBar(context),
                const Spacer(),
                _buildControls(context),
              ],
            ),
          ),
          _buildSettingsPanel(context),
        ],
      ),
    );
  }

  Widget _buildTopBar(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: _buildStatsRow(context)),
        const SizedBox(width: 12),
        FilledButton.tonalIcon(
          onPressed: () => setState(() => _showSettings = !_showSettings),
          icon: Icon(_showSettings ? Icons.close : Icons.tune),
          label: Text(_showSettings ? 'Close' : 'Settings'),
        ),
      ],
    );
  }

  Widget _buildStatsRow(BuildContext context) {
    return Align(
      alignment: Alignment.topLeft,
      child: Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          _StatCard(label: 'Day', listenable: widget.simulation.daysPassed),
          _StatCard(label: 'Ants', listenable: widget.simulation.antCount),
          _StatCard(label: 'Food', listenable: widget.simulation.foodCollected),
        ],
      ),
    );
  }

  Widget _buildControls(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Align(
      alignment: Alignment.bottomCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640),
        child: Card(
          color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.8),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    ValueListenableBuilder<BrushMode>(
                      valueListenable: widget.game.brushMode,
                      builder: (context, mode, _) {
                        return SegmentedButton<BrushMode>(
                          segments: const [
                            ButtonSegment(
                              value: BrushMode.dig,
                              label: Text('Dig'),
                              icon: Icon(Icons.construction),
                            ),
                            ButtonSegment(
                              value: BrushMode.food,
                              label: Text('Food'),
                              icon: Icon(Icons.fastfood_outlined),
                            ),
                            ButtonSegment(
                              value: BrushMode.rock,
                              label: Text('Rock'),
                              icon: Icon(Icons.landscape_outlined),
                            ),
                          ],
                          selected: {mode},
                          onSelectionChanged: (selection) {
                            if (selection.isNotEmpty) {
                              widget.game.setBrushMode(selection.first);
                            }
                          },
                        );
                      },
                    ),
                    ValueListenableBuilder<bool>(
                      valueListenable: widget.simulation.pheromonesVisible,
                      builder: (context, visible, _) {
                        return FilledButton.icon(
                          onPressed: widget.simulation.togglePheromones,
                          icon: Icon(visible ? Icons.visibility : Icons.visibility_off),
                          label: Text(visible ? 'Hide Pheromones' : 'Show Pheromones'),
                        );
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                const Text(
                  'Controls: Left Click = active brush | Right Click/Shift = Food | Press P to toggle pheromones.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 4),
                const Text(
                  'Use the settings panel to manage ant count, speed, map size, and quick food drops.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, color: Colors.white70),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSettingsPanel(BuildContext context) {
    final theme = Theme.of(context);
    final screenHeight = MediaQuery.of(context).size.height;
    return AnimatedPositioned(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
      top: 16,
      bottom: 16,
      right: _showSettings ? 16 : -360,
      child: SizedBox(
        width: 320,
        child: Card(
          color: theme.colorScheme.surface.withValues(alpha: 0.95),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.tune),
                      const SizedBox(width: 8),
                      const Text(
                        'Settings',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      const Spacer(),
                      IconButton(
                        onPressed: () => setState(() => _showSettings = false),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                  const Divider(),
                  _buildPopulationControls(theme),
                  const Divider(),
                  _buildSpeedControls(theme),
                  const Divider(),
                  _buildViewControls(theme),
                  const Divider(),
                  _buildGenerationControls(theme),
                  const Divider(),
                  _buildFoodControls(),
                  const Divider(),
                  _buildPersistenceControls(),
                  const Divider(),
                  _buildGridControls(theme),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPopulationControls(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Ant Population', style: theme.textTheme.titleSmall),
        const SizedBox(height: 4),
        ValueListenableBuilder<int>(
          valueListenable: widget.simulation.antCount,
          builder: (context, count, _) => Text('Current: $count'),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _PopulationButton(label: '-10', onPressed: () => widget.simulation.removeAnts(10)),
            _PopulationButton(label: '-1', onPressed: () => widget.simulation.removeAnts(1)),
            _PopulationButton(label: '+1', onPressed: () => widget.simulation.addAnts(1)),
            _PopulationButton(label: '+10', onPressed: () => widget.simulation.addAnts(10)),
          ],
        ),
      ],
    );
  }

  Widget _buildSpeedControls(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Ant Speed', style: theme.textTheme.titleSmall),
        const SizedBox(height: 4),
        ValueListenableBuilder<double>(
          valueListenable: widget.simulation.antSpeedMultiplier,
          builder: (context, multiplier, _) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Multiplier: ${multiplier.toStringAsFixed(1)}x'),
                Slider(
                  value: multiplier,
                  min: 0.2,
                  max: 3.0,
                  divisions: 28,
                  label: '${multiplier.toStringAsFixed(1)}x',
                  onChanged: widget.simulation.setAntSpeedMultiplier,
                ),
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _buildFoodControls() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Food Utilities', style: TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        FilledButton.icon(
          onPressed: () => widget.simulation.scatterFood(clusters: 8, radius: 3),
          icon: const Icon(Icons.local_florist_outlined),
          label: const Text('Scatter Random Food'),
        ),
      ],
    );
  }

  Widget _buildGenerationControls(ThemeData theme) {
    final seed = widget.simulation.lastSeed;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Map Generation', style: theme.textTheme.titleSmall),
        const SizedBox(height: 4),
        Text(seed == null ? 'Seed: --' : 'Seed: $seed'),
        const SizedBox(height: 8),
        FilledButton.icon(
          onPressed: _generatingMap ? null : _randomizeMap,
          icon: _generatingMap
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.auto_awesome),
          label: Text(_generatingMap ? 'Generating...' : 'Random Map'),
        ),
      ],
    );
  }

  Widget _buildPersistenceControls() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Persistence', style: TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        FilledButton.icon(
          onPressed: _saving ? null : _saveWorld,
          icon: _saving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.save),
          label: Text(_saving ? 'Saving...' : 'Save World'),
        ),
      ],
    );
  }

  Widget _buildGridControls(ThemeData theme) {
    final current = widget.simulation.config;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Grid Size', style: theme.textTheme.titleSmall),
        const SizedBox(height: 4),
        Text('Current: ${current.cols} × ${current.rows}'),
        const SizedBox(height: 12),
        Text('Columns ($_pendingCols)'),
        Slider(
          min: 40,
          max: 160,
          divisions: 12,
          value: _pendingCols.toDouble().clamp(40, 160),
          onChanged: (value) => setState(() => _pendingCols = value.round()),
        ),
        Text('Rows ($_pendingRows)'),
        Slider(
          min: 30,
          max: 140,
          divisions: 11,
          value: _pendingRows.toDouble().clamp(30, 140),
          onChanged: (value) => setState(() => _pendingRows = value.round()),
        ),
        const SizedBox(height: 8),
        FilledButton.icon(
          onPressed: _applyGridSize,
          icon: const Icon(Icons.map),
          label: const Text('Apply Grid Size'),
        ),
      ],
    );
  }

  Widget _buildViewControls(ThemeData theme) {
    final zoom = widget.game.zoomFactor;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('View', style: theme.textTheme.titleSmall),
        Text('Zoom: ${zoom.toStringAsFixed(1)}x'),
        Slider(
          min: 0.5,
          max: 3.0,
          divisions: 25,
          value: zoom,
          onChanged: (value) {
            widget.game.setZoom(value);
            setState(() {});
          },
        ),
        const Text(
          'Use the slider to zoom the world view.',
          style: TextStyle(fontSize: 12, color: Colors.white70),
        ),
      ],
    );
  }

  void _applyGridSize() {
    if (_pendingCols == widget.simulation.config.cols &&
        _pendingRows == widget.simulation.config.rows) {
      return;
    }
    widget.simulation.resizeWorld(cols: _pendingCols, rows: _pendingRows);
    widget.game.refreshViewport();
    setState(() {
      _pendingCols = widget.simulation.config.cols;
      _pendingRows = widget.simulation.config.rows;
    });
  }

  Future<void> _saveWorld() async {
    setState(() => _saving = true);
    final success = await widget.storage.save(widget.simulation);
    if (!mounted) return;
    setState(() => _saving = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(success ? 'World saved' : 'Failed to save world'),
      ),
    );
  }

  Future<void> _randomizeMap() async {
    setState(() => _generatingMap = true);
    final seed = math.Random().nextInt(0x7fffffff);
    widget.simulation.generateRandomWorld(seed: seed);
    widget.game.invalidateTerrainLayer();
    widget.game.refreshViewport();
    setState(() {
      _generatingMap = false;
      _pendingCols = widget.simulation.config.cols;
      _pendingRows = widget.simulation.config.rows;
    });
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Generated new world (seed $seed)')),
    );
  }
}

class _PopulationButton extends StatelessWidget {
  const _PopulationButton({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: onPressed,
      child: Text(label),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({required this.label, required this.listenable});

  final String label;
  final ValueListenable<int> listenable;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        child: ValueListenableBuilder<int>(
          valueListenable: listenable,
          builder: (context, value, _) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(label, style: theme.textTheme.labelLarge),
                const SizedBox(height: 4),
                Text(
                  '$value',
                  style: theme.textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
