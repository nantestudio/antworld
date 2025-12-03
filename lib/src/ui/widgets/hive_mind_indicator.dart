/// Hive Mind AI indicator widget
///
/// Shows a subtle indicator when the AI is processing decisions,
/// integrated into the top bar with a bottom sheet for detailed logs.
library;

import 'package:flutter/material.dart';

import '../../services/hive_mind_service.dart';
import '../../services/hive_mind_models.dart';
import '../../utils/colony_names.dart';

/// Colony colors matching the simulation visuals
const List<Color> _colonyColors = [
  Color(0xFF4ECDC4), // Colony 0: Teal
  Color(0xFFFF6B6B), // Colony 1: Coral Red
  Color(0xFFFFE66D), // Colony 2: Yellow
  Color(0xFFAB83A1), // Colony 3: Mauve
];

/// Small indicator button for the top bar showing AI Hive Mind activity
class HiveMindIndicatorButton extends StatefulWidget {
  const HiveMindIndicatorButton({super.key});

  @override
  State<HiveMindIndicatorButton> createState() => _HiveMindIndicatorButtonState();
}

class _HiveMindIndicatorButtonState extends State<HiveMindIndicatorButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  void _showLogSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.grey.shade900,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.5,
        minChildSize: 0.3,
        maxChildSize: 0.85,
        expand: false,
        builder: (context, scrollController) => _HiveMindLogSheet(
          scrollController: scrollController,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: HiveMindService.instance.enabled,
      builder: (context, enabled, _) {
        if (!enabled) {
          // Disabled state - gray icon, still tappable
          return IconButton(
            icon: Icon(
              Icons.psychology,
              color: Colors.grey.withOpacity(0.5),
              size: 22,
            ),
            onPressed: () => _showLogSheet(context),
            tooltip: 'AI Hive Mind (disabled)',
          );
        }

        return ValueListenableBuilder<bool>(
          valueListenable: HiveMindService.instance.isProcessing,
          builder: (context, isProcessing, _) {
            if (isProcessing) {
              // Processing - animated pulsing purple
              return AnimatedBuilder(
                animation: _pulseController,
                builder: (context, _) {
                  final color = Color.lerp(
                    Colors.purple.shade300,
                    Colors.purple.shade600,
                    _pulseController.value,
                  )!;
                  return IconButton(
                    icon: Icon(Icons.psychology, color: color, size: 22),
                    onPressed: () => _showLogSheet(context),
                    tooltip: 'AI thinking...',
                  );
                },
              );
            }

            // Check for recent decision - show green briefly
            final lastDecision = HiveMindService.instance.lastDecision.value;
            if (lastDecision != null) {
              final age = DateTime.now().difference(lastDecision.timestamp);
              if (age.inSeconds < 5) {
                return IconButton(
                  icon: Icon(
                    Icons.psychology,
                    color: Colors.green.shade400,
                    size: 22,
                  ),
                  onPressed: () => _showLogSheet(context),
                  tooltip: 'AI decision received',
                );
              }
            }

            // Idle state - subtle purple
            return IconButton(
              icon: Icon(
                Icons.psychology,
                color: Colors.purple.shade300.withOpacity(0.7),
                size: 22,
              ),
              onPressed: () => _showLogSheet(context),
              tooltip: 'AI Hive Mind',
            );
          },
        );
      },
    );
  }
}

/// Bottom sheet showing AI decision log
class _HiveMindLogSheet extends StatelessWidget {
  const _HiveMindLogSheet({required this.scrollController});

  final ScrollController scrollController;

  @override
  Widget build(BuildContext context) {
    final log = HiveMindService.instance.decisionLog;

    return SafeArea(
      child: Column(
        children: [
          // Handle bar
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Icon(Icons.psychology, color: Colors.purple.shade300, size: 24),
                const SizedBox(width: 8),
                const Text(
                  'Hive Mind Log',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                // Toggle button
                ValueListenableBuilder<bool>(
                  valueListenable: HiveMindService.instance.enabled,
                  builder: (context, enabled, _) {
                    return Switch(
                      value: enabled,
                      onChanged: (v) => HiveMindService.instance.enabled.value = v,
                      activeColor: Colors.purple.shade300,
                    );
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          const Divider(height: 1),
          // Log entries
          Expanded(
            child: log.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.psychology_outlined,
                          size: 48,
                          color: Colors.white.withOpacity(0.3),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'No decisions yet',
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.5),
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'The AI analyzes the colony every 30 seconds',
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.3),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  )
                : ListView.separated(
                    controller: scrollController,
                    padding: const EdgeInsets.all(16),
                    itemCount: log.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (context, index) {
                      final entry = log[index];
                      return _LogEntryCard(entry: entry);
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _LogEntryCard extends StatelessWidget {
  const _LogEntryCard({required this.entry});

  final HiveMindLogEntry entry;

  String _formatTimeAgo(DateTime timestamp) {
    final diff = DateTime.now().difference(timestamp);
    if (diff.inSeconds < 60) return '${diff.inSeconds}s ago';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    return '${diff.inHours}h ago';
  }

  @override
  Widget build(BuildContext context) {
    final decision = entry.decision;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Colors.purple.shade800.withOpacity(0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header row
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.purple.shade900.withOpacity(0.5),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  _formatTimeAgo(entry.timestamp),
                  style: TextStyle(
                    color: Colors.purple.shade200,
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              const Spacer(),
              if (decision.directives.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.green.shade900.withOpacity(0.5),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '${decision.directives.length} action${decision.directives.length > 1 ? 's' : ''}',
                    style: TextStyle(
                      color: Colors.green.shade300,
                      fontSize: 11,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          // Reasoning
          Text(
            decision.reasoning,
            style: TextStyle(
              color: Colors.white.withOpacity(0.9),
              fontSize: 13,
              height: 1.4,
            ),
          ),
          // Directives
          if (decision.directives.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: decision.directives.map((d) {
                final colonyColor = _colonyColors[d.colonyId.clamp(0, 3)];
                final colonyName = ColonyNameManager.instance.getName(d.colonyId);
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: colonyColor.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: colonyColor.withOpacity(0.4),
                      width: 1,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: colonyColor,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Icon(
                        _iconForDirective(d.type),
                        size: 12,
                        color: colonyColor,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '$colonyName: ${_directiveLabel(d.type)}',
                        style: TextStyle(
                          color: colonyColor,
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ],
        ],
      ),
    );
  }

  IconData _iconForDirective(DirectiveType type) {
    switch (type) {
      case DirectiveType.adjustCasteRatio:
        return Icons.group;
      case DirectiveType.setExplorerRatio:
        return Icons.explore;
      case DirectiveType.prioritizeDefense:
        return Icons.shield;
      case DirectiveType.focusOnFood:
        return Icons.restaurant;
      case DirectiveType.queueRoomConstruction:
        return Icons.construction;
      case DirectiveType.triggerEmergency:
        return Icons.warning;
    }
  }

  String _directiveLabel(DirectiveType type) {
    switch (type) {
      case DirectiveType.adjustCasteRatio:
        return 'Caste Ratio';
      case DirectiveType.setExplorerRatio:
        return 'Explorers';
      case DirectiveType.prioritizeDefense:
        return 'Defense';
      case DirectiveType.focusOnFood:
        return 'Foraging';
      case DirectiveType.queueRoomConstruction:
        return 'Build Room';
      case DirectiveType.triggerEmergency:
        return 'Emergency';
    }
  }
}

/// Legacy floating indicator - kept for backwards compatibility but deprecated
@Deprecated('Use HiveMindIndicatorButton in top bar instead')
class HiveMindIndicator extends StatelessWidget {
  const HiveMindIndicator({super.key});

  @override
  Widget build(BuildContext context) {
    // Return empty widget - the new indicator is integrated into top bar
    return const SizedBox.shrink();
  }
}
