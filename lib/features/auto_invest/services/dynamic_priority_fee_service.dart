import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

/// 🚀 Servicio para calcular priority fees dinámicos basado en:
/// - Congestión de red (slots pendientes)
/// - Competencia en el mismo token (gas wars)
/// - Historial de éxito de transacciones
class DynamicPriorityFeeService {
  DynamicPriorityFeeService({
    http.Client? client,
    String? rpcUrl,
  })  : _client = client ?? http.Client(),
        _rpcUrl = rpcUrl ?? _buildRpcUrl() {
    // Cache de fees recientes (válido por 5 segundos)
    _recentFeesCache = null;
    _recentFeesCacheTime = null;
  }

  final http.Client _client;
  final String _rpcUrl;

  // Cache de fees recientes de la red
  List<Map<String, dynamic>>? _recentFeesCache;
  DateTime? _recentFeesCacheTime;
  static const _cacheValidity = Duration(seconds: 5);

  // Historial de transacciones por mint (para detectar gas wars)
  final Map<String, List<_TxAttempt>> _mintTxHistory = {};
  static const _maxHistoryPerMint = 10;
  static const _historyValidity = Duration(minutes: 5);

  // Historial de fallos por low priority
  final Map<String, int> _lowPriorityFailures = {};

  static String _buildRpcUrl() {
    final rpcUrlOverride = const String.fromEnvironment(
      'RPC_URL',
      defaultValue: '',
    );
    if (rpcUrlOverride.isNotEmpty) {
      return rpcUrlOverride;
    }
    final heliusApiKey = const String.fromEnvironment(
      'HELIUS_API_KEY',
      defaultValue: '',
    );
    if (heliusApiKey.isNotEmpty) {
      return 'https://mainnet.helius-rpc.com/?api-key=$heliusApiKey';
    }
    return 'https://api.mainnet-beta.solana.com';
  }

  /// 🧠 Calcular priority fee dinámico para una transacción
  /// 
  /// [baseFee] - Fee base configurado por el usuario (ej: 0.001 SOL)
  /// [mint] - Mint del token (opcional, para detectar gas wars)
  /// [isRetry] - Si es un reintento después de un fallo
  /// [previousFailure] - Si la transacción anterior falló por low priority
  Future<double> calculateOptimalFee({
    required double baseFee,
    String? mint,
    bool isRetry = false,
    bool previousFailure = false,
  }) async {
    // 1. Obtener fees recientes de la red (con cache)
    final recentFees = await _getRecentPrioritizationFees();

    // 2. Calcular fee basado en congestión de red
    final networkFee = _calculateNetworkFee(recentFees);

    // 3. Calcular fee basado en competencia del token (gas wars)
    final competitionFee = mint != null
        ? await _calculateCompetitionFee(mint, recentFees)
        : 0.0;

    // 4. Ajustar por historial de fallos
    final failureMultiplier = _calculateFailureMultiplier(
      mint: mint,
      isRetry: isRetry,
      previousFailure: previousFailure,
    );

    // 5. Calcular fee final
    // Fórmula: max(baseFee, networkFee, competitionFee) * failureMultiplier
    final calculatedFee = math.max(
      baseFee,
      math.max(networkFee, competitionFee),
    ) * failureMultiplier;

    // 6. Limitar a un máximo razonable (0.1 SOL)
    return calculatedFee.clamp(0.0001, 0.1);
  }

  /// 📊 Obtener fees recientes de priorización desde el RPC
  Future<List<Map<String, dynamic>>> _getRecentPrioritizationFees() async {
    final now = DateTime.now();
    if (_recentFeesCache != null &&
        _recentFeesCacheTime != null &&
        now.difference(_recentFeesCacheTime!) < _cacheValidity) {
      return _recentFeesCache!;
    }

    try {
      final uri = Uri.parse(_rpcUrl);
      final response = await _client
          .post(
            uri,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'jsonrpc': '2.0',
              'id': 1,
              'method': 'getRecentPrioritizationFees',
              'params': [],
            }),
          )
          .timeout(const Duration(seconds: 3));

      if (response.statusCode != 200) {
        // Si falla, retornar lista vacía (usar fee base)
        return [];
      }

      final decoded = jsonDecode(response.body) as Map<String, dynamic>;
      final result = decoded['result'] as List<dynamic>?;
      if (result == null || result.isEmpty) {
        return [];
      }

      // Parsear resultado: array de objetos con "prioritizationFee" en lamports
      final fees = result
          .map((e) => e as Map<String, dynamic>)
          .where((e) => e.containsKey('prioritizationFee'))
          .toList();

      _recentFeesCache = fees;
      _recentFeesCacheTime = now;
      return fees;
    } catch (e) {
      // Si falla obtener fees, retornar lista vacía (usar fee base)
      return [];
    }
  }

  /// 🌐 Calcular fee basado en congestión de red
  double _calculateNetworkFee(List<Map<String, dynamic>> recentFees) {
    if (recentFees.isEmpty) {
      // Sin datos, usar fee mínimo
      return 0.0001;
    }

    // Convertir fees de lamports a SOL
    final feesInSol = recentFees
        .map((e) {
          final feeLamports = e['prioritizationFee'] as int?;
          if (feeLamports == null) return null;
          return feeLamports / 1000000000.0; // lamports to SOL
        })
        .where((e) => e != null)
        .cast<double>()
        .toList();

    if (feesInSol.isEmpty) {
      return 0.0001;
    }

    // Calcular percentil 75 (más agresivo que la mediana)
    // Esto asegura que estemos en el top 25% de fees
    feesInSol.sort();
    final p75Index = (feesInSol.length * 0.75).floor();
    final p75Fee = feesInSol[math.min(p75Index, feesInSol.length - 1)];

    // Usar el percentil 75 como base, con un pequeño buffer
    return p75Fee * 1.2; // 20% de buffer sobre el P75
  }

  /// ⚔️ Calcular fee basado en competencia (gas wars) para un token específico
  Future<double> _calculateCompetitionFee(
    String mint,
    List<Map<String, dynamic>> recentFees,
  ) async {
    // Limpiar historial antiguo
    _cleanupOldHistory();

    // Obtener historial de transacciones recientes para este mint
    final mintHistory = _mintTxHistory[mint] ?? [];
    if (mintHistory.isEmpty) {
      // Sin historial, no hay competencia detectada
      return 0.0;
    }

    // Contar transacciones en los últimos 30 segundos
    final now = DateTime.now();
    final recentTxs = mintHistory.where((tx) {
      return now.difference(tx.timestamp) < const Duration(seconds: 30);
    }).toList();

    if (recentTxs.length < 3) {
      // Pocas transacciones, competencia baja
      return 0.0;
    }

    // Si hay muchas transacciones recientes, hay gas war
    // Aumentar fee proporcionalmente
    final competitionMultiplier = math.min(recentTxs.length / 5.0, 3.0);
    final baseNetworkFee = _calculateNetworkFee(recentFees);
    return baseNetworkFee * competitionMultiplier;
  }

  /// 📈 Calcular multiplicador basado en historial de fallos
  double _calculateFailureMultiplier({
    String? mint,
    bool isRetry = false,
    bool previousFailure = false,
  }) {
    // Limpiar fallos antiguos
    _cleanupOldFailures();

    if (previousFailure || isRetry) {
      // Si es un reintento o hubo un fallo previo, aumentar fee
      return 2.0; // Doblar el fee
    }

    if (mint != null) {
      final failures = _lowPriorityFailures[mint] ?? 0;
      if (failures > 0) {
        // Aumentar fee proporcionalmente a los fallos
        return 1.0 + (failures * 0.5);
      }
    }

    return 1.0; // Sin ajuste
  }

  /// 📝 Registrar un intento de transacción (para detectar gas wars)
  void recordTxAttempt(String mint, double feeUsed) {
    final now = DateTime.now();
    final history = _mintTxHistory.putIfAbsent(mint, () => []);
    history.add(_TxAttempt(timestamp: now, feeUsed: feeUsed));

    // Limitar tamaño del historial
    if (history.length > _maxHistoryPerMint) {
      history.removeAt(0);
    }
  }

  /// ❌ Registrar un fallo por low priority
  void recordLowPriorityFailure(String mint) {
    _lowPriorityFailures[mint] = (_lowPriorityFailures[mint] ?? 0) + 1;
  }

  /// ✅ Registrar un éxito (reduce el contador de fallos)
  void recordSuccess(String mint) {
    final failures = _lowPriorityFailures[mint];
    if (failures != null && failures > 0) {
      _lowPriorityFailures[mint] = failures - 1;
    }
  }

  /// 🧹 Limpiar historial antiguo
  void _cleanupOldHistory() {
    final now = DateTime.now();
    _mintTxHistory.removeWhere((mint, history) {
      history.removeWhere((tx) {
        return now.difference(tx.timestamp) > _historyValidity;
      });
      return history.isEmpty;
    });
  }

  /// 🧹 Limpiar fallos antiguos
  void _cleanupOldFailures() {
    // Los fallos se limpian automáticamente después de _failureDecay
    // Por simplicidad, los mantenemos con un contador que se reduce con éxitos
  }

  void dispose() {
    _client.close();
  }
}

/// Modelo para tracking de intentos de transacción
class _TxAttempt {
  _TxAttempt({
    required this.timestamp,
    required this.feeUsed,
  });

  final DateTime timestamp;
  final double feeUsed;
}

final dynamicPriorityFeeServiceProvider =
    Provider<DynamicPriorityFeeService>((ref) {
  final service = DynamicPriorityFeeService();
  ref.onDispose(service.dispose);
  return service;
});

