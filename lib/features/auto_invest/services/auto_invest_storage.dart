import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/storage/shared_prefs_provider.dart';
import '../controller/auto_invest_notifier.dart';
import '../models/execution_record.dart';

class AutoInvestStorage {
  AutoInvestStorage(this._prefs);

  final SharedPreferences _prefs;

  static const _stateKey = 'auto_invest_state_v1';
  static const _executionsKey = 'auto_invest_exec_v1';

  AutoInvestState? loadState() {
    final raw = _prefs.getString(_stateKey);
    if (raw == null) return null;
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      return AutoInvestState.fromJson(decoded);
    } catch (_) {
      return null;
    }
  }

  List<ExecutionRecord> loadExecutions() {
    final raw = _prefs.getString(_executionsKey);
    if (raw == null) return [];
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list
          .whereType<Map<String, dynamic>>()
          .map(ExecutionRecord.fromJson)
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> saveState(AutoInvestState state) async {
    await _prefs.setString(_stateKey, jsonEncode(state.toJson()));
  }

  Future<void> saveExecutions(List<ExecutionRecord> executions) async {
    await _prefs.setString(
      _executionsKey,
      jsonEncode(executions.map((e) => e.toJson()).toList(growable: false)),
    );
  }
}

final autoInvestStorageProvider = Provider<AutoInvestStorage>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  return AutoInvestStorage(prefs);
});
