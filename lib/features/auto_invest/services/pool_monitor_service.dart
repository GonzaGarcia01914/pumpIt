import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import 'solana_websocket_service.dart';

/// 📊 Cambio detectado en un pool
class PoolChangeEvent {
  PoolChangeEvent({
    required this.mint,
    required this.changeType,
    required this.timestamp,
    this.newPrice,
    this.oldPrice,
    this.newLiquidity,
    this.oldLiquidity,
    this.isGraduating,
    this.graduationPool,
  });

  final String mint;
  final PoolChangeType changeType;
  final DateTime timestamp;
  final double? newPrice;
  final double? oldPrice;
  final double? newLiquidity;
  final double? oldLiquidity;
  final bool? isGraduating; // true si el token está por graduar o graduó
  final String? graduationPool; // Dirección del pool de Raydium si graduó

  @override
  String toString() {
    final buffer = StringBuffer();
    buffer.writeln('Pool Change: $mint');
    buffer.writeln('Type: $changeType');
    if (newPrice != null && oldPrice != null) {
      final changePercent = oldPrice! > 0
          ? ((newPrice! - oldPrice!) / oldPrice!) * 100
          : 0.0;
      buffer.writeln(
        'Price: ${oldPrice!.toStringAsFixed(8)} → ${newPrice!.toStringAsFixed(8)} (${changePercent > 0 ? "+" : ""}${changePercent.toStringAsFixed(2)}%)',
      );
    }
    if (newLiquidity != null && oldLiquidity != null) {
      final changePercent = oldLiquidity! > 0
          ? ((newLiquidity! - oldLiquidity!) / oldLiquidity!) * 100
          : 0.0;
      buffer.writeln(
        'Liquidity: ${oldLiquidity!.toStringAsFixed(4)} → ${newLiquidity!.toStringAsFixed(4)} SOL (${changePercent > 0 ? "+" : ""}${changePercent.toStringAsFixed(2)}%)',
      );
    }
    if (isGraduating == true) {
      buffer.writeln('⚠️ Token está graduando/graduó');
      if (graduationPool != null) {
        buffer.writeln('Raydium Pool: $graduationPool');
      }
    }
    return buffer.toString();
  }
}

enum PoolChangeType {
  priceChange,
  liquidityChange,
  graduation,
  criticalChange, // Cambio crítico que requiere acción inmediata
}

/// 📊 Estado actual de un pool monitoreado
class PoolState {
  PoolState({
    required this.mint,
    required this.poolAddress,
    this.currentPrice,
    this.currentLiquidity,
    this.lastUpdate,
    this.isGraduated,
    this.raydiumPool,
  });

  final String mint;
  final String poolAddress;
  final double? currentPrice;
  final double? currentLiquidity;
  final DateTime? lastUpdate;
  final bool? isGraduated;
  final String? raydiumPool;
}

/// 📊 Servicio para monitorear pools en tiempo real usando WebSockets
class PoolMonitorService {
  PoolMonitorService({
    required SolanaWebSocketService websocketService,
  }) : _websocketService = websocketService;

  final SolanaWebSocketService _websocketService;

  // Suscripciones activas por mint
  final Map<String, StreamSubscription<Map<String, dynamic>>> _activeSubscriptions = {};
  final Map<String, PoolState> _poolStates = {};
  final Map<String, StreamController<PoolChangeEvent>> _eventControllers = {};

  // Umbrales para detectar cambios críticos
  static const _criticalPriceChangePercent = 10.0; // 10% de cambio de precio
  static const _criticalLiquidityChangePercent = 20.0; // 20% de cambio de liquidez

  /// 📊 Iniciar monitoreo de un pool
  /// Retorna un stream de eventos de cambios en el pool
  Stream<PoolChangeEvent> startMonitoring({
    required String mint,
    required String poolAddress,
  }) {
    final normalizedMint = mint.trim();
    
    // Si ya está monitoreando, retornar el stream existente
    if (_eventControllers.containsKey(normalizedMint)) {
      return _eventControllers[normalizedMint]!.stream;
    }

    // Crear nuevo stream controller
    final controller = StreamController<PoolChangeEvent>.broadcast();
    _eventControllers[normalizedMint] = controller;

    // Inicializar estado del pool
    _poolStates[normalizedMint] = PoolState(
      mint: normalizedMint,
      poolAddress: poolAddress,
    );

    // Suscribirse a cambios en la cuenta del pool
    _subscribeToPoolAccount(normalizedMint, poolAddress, controller);

    return controller.stream;
  }

  /// 📊 Detener monitoreo de un pool
  void stopMonitoring(String mint) {
    final normalizedMint = mint.trim();
    
    _activeSubscriptions[normalizedMint]?.cancel();
    _activeSubscriptions.remove(normalizedMint);
    
    _eventControllers[normalizedMint]?.close();
    _eventControllers.remove(normalizedMint);
    
    _poolStates.remove(normalizedMint);
  }

  /// 📊 Obtener estado actual de un pool
  PoolState? getPoolState(String mint) {
    return _poolStates[mint.trim()];
  }

  /// 📊 Suscribirse a cambios en la cuenta del pool
  void _subscribeToPoolAccount(
    String mint,
    String poolAddress,
    StreamController<PoolChangeEvent> controller,
  ) {
    try {
      final subscription = _websocketService
          .subscribeToAccount(poolAddress)
          .listen(
            (data) {
              _handleAccountUpdate(mint, data, controller);
            },
            onError: (error) {
              // Reconectar en caso de error
              _reconnectPoolSubscription(mint, poolAddress, controller);
            },
          );

      _activeSubscriptions[mint] = subscription;
    } catch (e) {
      // Si falla, cerrar el controller
      controller.addError(Exception('Error suscribiéndose al pool: $e'));
    }
  }

  /// 📊 Manejar actualización de cuenta del pool
  void _handleAccountUpdate(
    String mint,
    Map<String, dynamic> data,
    StreamController<PoolChangeEvent> controller,
  ) {
    try {
      final result = data['result'] as Map<String, dynamic>?;
      if (result == null) return;

      final value = result['value'] as Map<String, dynamic>?;
      if (value == null) return;

      final account = value['account'] as Map<String, dynamic>?;
      if (account == null) return;

      final accountData = account['data'] as Map<String, dynamic>?;
      if (accountData == null) return;

      // Parsear datos de la cuenta del pool
      final parsed = accountData['parsed'] as Map<String, dynamic>?;
      if (parsed == null) return;

      final currentState = _poolStates[mint];
      if (currentState == null) return;

      // Extraer precio y liquidez del pool
      final newPrice = _extractPrice(parsed);
      final newLiquidity = _extractLiquidity(parsed);
      final isGraduated = _checkGraduation(parsed);
      final raydiumPool = _extractRaydiumPool(parsed);

      // Detectar cambios
      final changes = <PoolChangeEvent>[];

      // Cambio de precio
      if (newPrice != null &&
          currentState.currentPrice != null &&
          newPrice != currentState.currentPrice) {
        final changePercent = currentState.currentPrice! > 0
            ? ((newPrice - currentState.currentPrice!) / currentState.currentPrice!).abs() * 100
            : 0.0;

        changes.add(PoolChangeEvent(
          mint: mint,
          changeType: changePercent >= _criticalPriceChangePercent
              ? PoolChangeType.criticalChange
              : PoolChangeType.priceChange,
          timestamp: DateTime.now(),
          newPrice: newPrice,
          oldPrice: currentState.currentPrice,
        ));
      }

      // Cambio de liquidez
      if (newLiquidity != null &&
          currentState.currentLiquidity != null &&
          newLiquidity != currentState.currentLiquidity) {
        final changePercent = currentState.currentLiquidity! > 0
            ? ((newLiquidity - currentState.currentLiquidity!) / currentState.currentLiquidity!).abs() * 100
            : 0.0;

        changes.add(PoolChangeEvent(
          mint: mint,
          changeType: changePercent >= _criticalLiquidityChangePercent
              ? PoolChangeType.criticalChange
              : PoolChangeType.liquidityChange,
          timestamp: DateTime.now(),
          newLiquidity: newLiquidity,
          oldLiquidity: currentState.currentLiquidity,
        ));
      }

      // Graduación
      if (isGraduated == true && currentState.isGraduated != true) {
        changes.add(PoolChangeEvent(
          mint: mint,
          changeType: PoolChangeType.graduation,
          timestamp: DateTime.now(),
          isGraduating: true,
          graduationPool: raydiumPool,
        ));
      }

      // Actualizar estado
      _poolStates[mint] = PoolState(
        mint: mint,
        poolAddress: currentState.poolAddress,
        currentPrice: newPrice ?? currentState.currentPrice,
        currentLiquidity: newLiquidity ?? currentState.currentLiquidity,
        lastUpdate: DateTime.now(),
        isGraduated: isGraduated ?? currentState.isGraduated,
        raydiumPool: raydiumPool ?? currentState.raydiumPool,
      );

      // Emitir eventos
      for (final change in changes) {
        controller.add(change);
      }
    } catch (e) {
      // Ignorar errores de parsing (pueden ser actualizaciones parciales)
    }
  }

  /// 📊 Extraer precio del pool desde los datos parseados
  double? _extractPrice(Map<String, dynamic> parsed) {
    // Intentar diferentes estructuras de datos de pump.fun
    final priceCandidates = <double?>[
      _maybeDouble(parsed['price']),
      _maybeDouble(parsed['priceSol']),
      _maybeDouble(parsed['price_sol']),
    ];

    final bondingCurve = parsed['bonding_curve'] ?? parsed['bondingCurve'];
    if (bondingCurve is Map<String, dynamic>) {
      priceCandidates.addAll([
        _maybeDouble(bondingCurve['price']),
        _maybeDouble(bondingCurve['priceSol']),
        _maybeDouble(bondingCurve['price_sol']),
      ]);
    }

    return priceCandidates.firstWhere(
      (p) => p != null && p > 0,
      orElse: () => null,
    );
  }

  /// 📊 Extraer liquidez del pool desde los datos parseados
  double? _extractLiquidity(Map<String, dynamic> parsed) {
    final liquidityCandidates = <double?>[
      _maybeDouble(parsed['liquidity']),
      _maybeDouble(parsed['liquiditySol']),
      _maybeDouble(parsed['liquidity_sol']),
      _maybeDouble(parsed['sol_reserves']),
      _maybeDouble(parsed['solReserves']),
    ];

    return liquidityCandidates.firstWhere(
      (l) => l != null && l > 0,
      orElse: () => null,
    );
  }

  /// 📊 Verificar si el token ha graduado
  bool? _checkGraduation(Map<String, dynamic> parsed) {
    final complete = parsed['complete'] as bool?;
    final raydiumPool = parsed['raydium_pool'] ?? parsed['raydiumPool'];
    return complete == true || (raydiumPool != null && raydiumPool.toString().isNotEmpty);
  }

  /// 📊 Extraer dirección del pool de Raydium
  String? _extractRaydiumPool(Map<String, dynamic> parsed) {
    final raydiumPool = parsed['raydium_pool'] ?? parsed['raydiumPool'];
    if (raydiumPool != null) {
      return raydiumPool.toString();
    }
    return null;
  }

  /// 📊 Reconectar suscripción en caso de error
  void _reconnectPoolSubscription(
    String mint,
    String poolAddress,
    StreamController<PoolChangeEvent> controller,
  ) {
    // Cancelar suscripción anterior
    _activeSubscriptions[mint]?.cancel();
    _activeSubscriptions.remove(mint);

    // Reintentar después de un breve delay
    Future.delayed(const Duration(seconds: 2), () {
      if (_eventControllers.containsKey(mint)) {
        _subscribeToPoolAccount(mint, poolAddress, controller);
      }
    });
  }

  /// 📊 Helper para parsear doubles
  double? _maybeDouble(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString());
  }

  /// 📊 Obtener dirección del pool de bonding curve de pump.fun desde la API
  /// Para pump.fun, necesitamos obtener la dirección del bonding curve desde la API
  Future<String?> getPumpFunPoolAddress(String mint) async {
    try {
      // Intentar obtener desde la API de pump.fun
      final response = await http.get(
        Uri.https('frontend-api-v3.pump.fun', '/coins/$mint'),
        headers: const {
          'accept': 'application/json',
          'user-agent': 'pump-it-baby/1.0',
        },
      ).timeout(const Duration(seconds: 3));

      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body) as Map<String, dynamic>;
        
        // Intentar obtener la dirección del bonding curve
        final bondingCurve = decoded['bonding_curve'] ?? decoded['bondingCurve'];
        if (bondingCurve is Map<String, dynamic>) {
          final address = bondingCurve['address'] ??
              bondingCurve['pubkey'] ??
              bondingCurve['publicKey'];
          if (address != null) {
            return address.toString();
          }
        }
        
        // Si no está en bonding_curve, intentar directamente
        final address = decoded['bonding_curve_address'] ??
            decoded['bondingCurveAddress'] ??
            decoded['pool_address'] ??
            decoded['poolAddress'];
        if (address != null) {
          return address.toString();
        }
      }
    } catch (e) {
      // Si falla, retornar null
    }

    // ⚠️ FALLBACK: Si no podemos obtener la dirección desde la API,
    // podríamos calcularla usando el programa de pump.fun (PDA)
    // Por ahora, retornamos null y el caller debe proporcionar la dirección
    return null;
  }

  void dispose() {
    // Cancelar todas las suscripciones
    for (final subscription in _activeSubscriptions.values) {
      subscription.cancel();
    }
    _activeSubscriptions.clear();

    // Cerrar todos los controllers
    for (final controller in _eventControllers.values) {
      controller.close();
    }
    _eventControllers.clear();

    _poolStates.clear();
  }
}

final poolMonitorServiceProvider = Provider<PoolMonitorService>((ref) {
  // Obtener websocket service usando el provider existente
  // Importar condicionalmente para evitar errores en web
  final heliusApiKey = const String.fromEnvironment('HELIUS_API_KEY', defaultValue: '');
  final websocketService = SolanaWebSocketService(apiKey: heliusApiKey.isEmpty ? null : heliusApiKey);
  final service = PoolMonitorService(websocketService: websocketService);
  ref.onDispose(service.dispose);
  return service;
});

