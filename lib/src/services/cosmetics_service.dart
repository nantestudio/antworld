import 'dart:ui';

import 'package:flutter/foundation.dart';

import '../state/unified_storage.dart';

class CosmeticPalette {
  const CosmeticPalette({
    required this.id,
    required this.name,
    required this.body,
    required this.carrying,
    this.description = '',
  });

  final String id;
  final String name;
  final Color body;
  final Color carrying;
  final String description;
}

class CosmeticsService extends ChangeNotifier {
  CosmeticsService._({UnifiedStorage? storage})
    : _storage = storage ?? UnifiedStorage();

  static final CosmeticsService instance = CosmeticsService._();

  final UnifiedStorage _storage;
  final Map<String, CosmeticPalette> _palettes = {
    'default': const CosmeticPalette(
      id: 'default',
      name: 'Colony Red',
      body: Color(0xFFF44336),
      carrying: Color(0xFFEF9A9A),
    ),
    'forest': const CosmeticPalette(
      id: 'forest',
      name: 'Forest Glow',
      body: Color(0xFF66BB6A),
      carrying: Color(0xFFA5D6A7),
      description: 'A lush green palette.',
    ),
    'ember': const CosmeticPalette(
      id: 'ember',
      name: 'Ember',
      body: Color(0xFFFF7043),
      carrying: Color(0xFFFFAB91),
      description: 'Fiery workers show off their speed.',
    ),
    'glacier': const CosmeticPalette(
      id: 'glacier',
      name: 'Glacier',
      body: Color(0xFF81D4FA),
      carrying: Color(0xFFB3E5FC),
      description: 'Cool tones for chilled out runs.',
    ),
  };

  String _selectedPaletteId = 'default';
  bool _loaded = false;

  bool get isLoaded => _loaded;
  String get selectedPaletteId => _selectedPaletteId;
  Iterable<CosmeticPalette> get palettes => _palettes.values;
  CosmeticPalette? get selectedPalette => _palettes[_selectedPaletteId];

  Future<void> load() async {
    if (_loaded) return;
    final raw = await _storage.loadCosmetics();
    if (raw.isNotEmpty && raw['selectedPalette'] != null) {
      _selectedPaletteId = raw['selectedPalette'] as String;
    }
    _loaded = true;
  }

  Future<void> selectPalette(String id) async {
    if (!_palettes.containsKey(id)) return;
    _selectedPaletteId = id;
    await _persist();
    notifyListeners();
  }

  Future<void> _persist() async {
    await _storage.saveCosmetics({'selectedPalette': _selectedPaletteId});
  }
}
