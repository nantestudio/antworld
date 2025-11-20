import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../simulation/colony_simulation.dart';

class SimulationStorage {
  static const _key = 'antworld.simulation-state';

  Future<bool> save(ColonySimulation simulation) async {
    final prefs = await SharedPreferences.getInstance();
    final payload = jsonEncode(simulation.toSnapshot());
    return prefs.setString(_key, payload);
  }

  Future<bool> restore(ColonySimulation simulation) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) {
      return false;
    }
    final data = jsonDecode(raw) as Map<String, dynamic>;
    simulation.restoreFromSnapshot(data);
    return true;
  }

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}
