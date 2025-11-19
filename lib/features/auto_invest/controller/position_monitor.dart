import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/position.dart';
import '../services/pump_fun_price_service.dart';
import '../services/pool_monitor_service.dart';
import '../services/whale_tracker_service.dart';
import '../services/token_security_analyzer.dart';
import 'auto_invest_executor.dart';
import 'auto_invest_notifier.dart';
import '../../../core/log/global_log.dart';

class AutoInvestPositionMonitor {
  AutoInvestPositionMonitor(this.ref, this.priceService);

  final Ref ref;
  final PumpFunPriceService priceService;

  Timer? _timer;
  bool _tickInProgress = false;
  final Map<String, DateTime> _errorCooldown = {};
  final Map<String, int> _sellAttempts = {};
  final Map<String, DateTime> _sellLastAttempt = {};

  // ⚡ Monitoreo de pools en tiempo real
  final Map<String, StreamSubscription<PoolChangeEvent>> _poolSubscriptions =
      {};

  static const _interval = Duration(seconds: 1);
  static const _maxMissingPerTick = 2;
  static const _maxPositionsPerTick = 3;
  static const _errorCooldownDuration = Duration(minutes: 2);
  static const _sellRetryDelay = Duration(seconds: 5);
  static const _sellMaxAttempts = 5;
  static const _sellStuckSince = Duration(seconds: 12);

  int _nextPositionIndex = 0;

  void init() {
    ref.listen<AutoInvestState>(
      autoInvestProvider,
      (_, next) => _handleStateChange(next),
      fireImmediately: true,
    );
  }

  void _handleStateChange(AutoInvestState state) {
    if (_shouldMonitor(state)) {
      _start();
      _startPoolMonitoring(state);
    } else {
      _stop();
      _stopPoolMonitoring();
    }
  }

  bool _shouldMonitor(AutoInvestState state) => state.positions.isNotEmpty;

  void _start() {
    _timer ??= Timer.periodic(_interval, (_) => _tick());
    _tick();
  }

  void _stop() {
    _timer?.cancel();
    _timer = null;
  }

  /// ⚡ Iniciar monitoreo de pools en tiempo real para todas las posiciones
  void _startPoolMonitoring(AutoInvestState state) {
    final poolMonitor = ref.read(poolMonitorServiceProvider);

    for (final position in state.positions) {
      // Si ya está monitoreando, continuar
      if (_poolSubscriptions.containsKey(position.mint)) {
        continue;
      }

      // Obtener dirección del pool e iniciar monitoreo
      unawaited(_startMonitoringPoolForPosition(position, poolMonitor));
    }
  }

  /// ⚡ Iniciar monitoreo de pool para una posición específica
  Future<void> _startMonitoringPoolForPosition(
    OpenPosition position,
    PoolMonitorService poolMonitor,
  ) async {
    try {
      // Obtener dirección del pool desde pump.fun API
      final poolAddress = await poolMonitor.getPumpFunPoolAddress(
        position.mint,
      );

      if (poolAddress == null) {
        // Si no podemos obtener la dirección, no monitorear
        // (el polling normal seguirá funcionando)
        return;
      }

      // Iniciar monitoreo y suscribirse a eventos
      final eventStream = poolMonitor.startMonitoring(
        mint: position.mint,
        poolAddress: poolAddress,
      );

      final subscription = eventStream.listen(
        (event) {
          _handlePoolChangeEvent(position, event);
        },
        onError: (error) {
          // Si hay error, continuar con polling normal
        },
      );

      _poolSubscriptions[position.mint] = subscription;
    } catch (e) {
      // Si falla, continuar con polling normal
    }
  }

  /// ⚡ Manejar evento de cambio en el pool
  void _handlePoolChangeEvent(OpenPosition position, PoolChangeEvent event) {
    try {
      // ⚡ REACCIÓN RÁPIDA (<100ms) a cambios críticos
      if (event.changeType == PoolChangeType.criticalChange ||
          event.changeType == PoolChangeType.graduation) {
        final executor = ref.read(autoInvestExecutorProvider);
        final notifier = ref.read(autoInvestProvider.notifier);

        if (event.changeType == PoolChangeType.graduation &&
            event.isGraduating == true) {
          // Token está graduando - vender inmediatamente si es necesario
          notifier.setStatus(
            '🚨 ALERTA: ${position.symbol} está graduando - verificando posición...',
          );
          // El executor ya maneja tokens graduados, pero podemos acelerar el proceso
        } else if (event.changeType == PoolChangeType.criticalChange) {
          // Cambio crítico detectado - actualizar precio inmediatamente
          if (event.newPrice != null) {
            // Actualizar precio en tiempo real sin esperar polling
            final tokenAmount = position.tokenAmount ?? 0;
            final currentValue = tokenAmount * event.newPrice!;
            final pnlSol = currentValue - position.entrySol;
            final pnlPercent = position.entrySol > 0
                ? (pnlSol / position.entrySol) * 100
                : null;

            notifier.updatePositionMonitoring(
              position.entrySignature,
              priceSol: event.newPrice!,
              currentValueSol: currentValue,
              pnlSol: pnlSol,
              pnlPercent: pnlPercent,
              checkedAt: DateTime.now(),
              updateAlert: true,
            );

            // Si hay cambio crítico de liquidez, considerar salir
            if (event.newLiquidity != null &&
                event.oldLiquidity != null &&
                event.newLiquidity! < event.oldLiquidity! * 0.5) {
              // Liquidez cayó >50% - posible rug pull
              notifier.setStatus(
                '⚠️ ALERTA: Liquidez de ${position.symbol} cayó >50% - considerando salida',
              );
              unawaited(
                executor.sellPosition(
                  position,
                  reason: PositionAlertType.stopLoss,
                ),
              );
            }
          }
        }
      }
    } catch (e) {
      // Si falla, continuar normalmente
    }
  }

  /// ⚡ Detener monitoreo de pools
  void _stopPoolMonitoring() {
    for (final subscription in _poolSubscriptions.values) {
      subscription.cancel();
    }
    _poolSubscriptions.clear();
  }

  Future<void> _tick() async {
    if (_tickInProgress) return;
    var state = ref.read(autoInvestProvider);
    final missing = state.positions
        .where((position) => !position.hasTokenAmount)
        .toList(growable: false);
    if (missing.isNotEmpty) {
      final executor = ref.read(autoInvestExecutorProvider);
      for (final position in missing.take(_maxMissingPerTick)) {
        try {
          await executor.ensurePositionTokenAmount(position);
        } catch (_) {
          // Ignore, se reintenta en el siguiente ciclo.
        }
      }
      state = ref.read(autoInvestProvider);
    }
    final positions = state.positions
        .where((position) => position.hasTokenAmount)
        .toList(growable: false);
    if (positions.isEmpty) {
      if (state.positions.isEmpty) {
        _stop();
      }
      return;
    }
    // Limpia intentos antiguos de posiciones ya cerradas
    final sigs = positions.map((p) => p.entrySignature).toSet();
    _sellAttempts.removeWhere((k, v) => !sigs.contains(k));
    _sellLastAttempt.removeWhere((k, v) => !sigs.contains(k));

    // ⚡ Asegurar que todas las posiciones activas tengan monitoreo de pool
    final poolMonitor = ref.read(poolMonitorServiceProvider);
    final monitoredMints = _poolSubscriptions.keys.toSet();
    final activeMints = positions.map((p) => p.mint).toSet();

    // Iniciar monitoreo para posiciones nuevas
    for (final position in positions) {
      if (!monitoredMints.contains(position.mint)) {
        unawaited(_startMonitoringPoolForPosition(position, poolMonitor));
      }
    }

    // Detener monitoreo para posiciones cerradas
    for (final mint in monitoredMints) {
      if (!activeMints.contains(mint)) {
        _poolSubscriptions[mint]?.cancel();
        _poolSubscriptions.remove(mint);
        poolMonitor.stopMonitoring(mint);
      }
    }
    _tickInProgress = true;
    try {
      final total = positions.length;
      final count = total <= _maxPositionsPerTick
          ? total
          : _maxPositionsPerTick;
      for (var i = 0; i < count; i++) {
        final index = (_nextPositionIndex + i) % total;
        await _updatePosition(positions[index], state);
      }
      _nextPositionIndex = (_nextPositionIndex + count) % total;
    } finally {
      _tickInProgress = false;
    }
  }

  Future<void> _updatePosition(
    OpenPosition position,
    AutoInvestState state,
  ) async {
    final tokenAmount = position.tokenAmount;
    if (tokenAmount == null || tokenAmount <= 0) return;
    try {
      final quote = await priceService.fetchQuote(position.mint);
      if (quote.priceSol <= 0) {
        return;
      }
      final currentValue = tokenAmount * quote.priceSol;
      final pnlSol = currentValue - position.entrySol;
      final pnlPercent = position.entrySol <= 0
          ? null
          : (pnlSol / position.entrySol) * 100;

      // ⚡ Actualizar maxPnlPercentReached para trailing stop
      final maxPnlPercentReached =
          pnlPercent != null &&
              (position.maxPnlPercentReached == null ||
                  pnlPercent > position.maxPnlPercentReached!)
          ? pnlPercent
          : position.maxPnlPercentReached;

      final alertUpdate = _evaluateAlert(
        position,
        state,
        pnlPercent,
        maxPnlPercentReached,
      );

      // ⚡ CORREGIDO: Limpiar alerta si el precio ya no cumple las condiciones
      // Esto es importante para trailing stop y ventas escalonadas
      PositionAlertType? finalAlertType = alertUpdate?.type;
      DateTime? finalAlertTriggeredAt = alertUpdate?.timestamp;

      // Si hay trailing stop activo y el precio subió por encima del threshold, limpiar alerta
      if (state.trailingStopEnabled &&
          maxPnlPercentReached != null &&
          maxPnlPercentReached > 0 &&
          position.alertType == PositionAlertType.stopLoss) {
        final trailingStopThreshold =
            maxPnlPercentReached - state.trailingStopPercent;
        if (pnlPercent != null && pnlPercent >= trailingStopThreshold) {
          // El precio volvió a subir por encima del trailing stop, limpiar alerta
          finalAlertType = null;
          finalAlertTriggeredAt = null;
        }
      }

      ref
          .read(autoInvestProvider.notifier)
          .updatePositionMonitoring(
            position.entrySignature,
            priceSol: quote.priceSol,
            currentValueSol: currentValue,
            pnlSol: pnlSol,
            pnlPercent: pnlPercent,
            checkedAt: quote.fetchedAt,
            alertType: finalAlertType,
            alertTriggeredAt: finalAlertTriggeredAt,
            updateAlert:
                true, // ⚡ Siempre actualizar para limpiar alertas cuando corresponda
            maxPnlPercentReached: maxPnlPercentReached,
          );

      // 🐋 MONITOREO DE WHALES: Detectar si el creator está vendiendo
      // Si el creator vende, salir inmediatamente (no esperar stop loss)
      unawaited(_checkWhaleActivityForPosition(position));

      // Intento de venta inicial + reintentos si la alerta está activa
      final activeAlert =
          alertUpdate?.type ??
          ref
              .read(autoInvestProvider)
              .positions
              .firstWhere(
                (p) => p.entrySignature == position.entrySignature,
                orElse: () => position,
              )
              .alertType;
      if (activeAlert != null) {
        await _maybeAttemptSell(position, activeAlert);
      }
    } catch (error) {
      _handleError(position, error);
    }
  }

  Future<void> _maybeAttemptSell(
    OpenPosition position,
    PositionAlertType reason,
  ) async {
    // No duplicar mientras está cerrando
    if (position.isClosing) return;
    final now = DateTime.now();
    final last = _sellLastAttempt[position.entrySignature];
    final attempts = _sellAttempts[position.entrySignature] ?? 0;

    // Si nunca intentamos, o ya pasó el retry delay, o está atascado hace tiempo
    final triggeredAt = position.alertTriggeredAt;
    final stuck =
        triggeredAt != null && now.difference(triggeredAt) >= _sellStuckSince;
    if (last != null && now.difference(last) < _sellRetryDelay && !stuck) {
      return;
    }
    if (attempts >= _sellMaxAttempts && !stuck) {
      return;
    }

    _sellLastAttempt[position.entrySignature] = now;
    _sellAttempts[position.entrySignature] = attempts + 1;

    // ⚡ CORREGIDO: Refrescar posición para obtener datos actualizados después de ventas parciales
    // Esto es crítico para ventas escalonadas - la posición puede haber cambiado
    OpenPosition? refreshed;
    final currentState = ref.read(autoInvestProvider);
    for (final candidate in currentState.positions) {
      if (candidate.entrySignature == position.entrySignature) {
        refreshed = candidate;
        break;
      }
    }
    if (refreshed == null || refreshed.isClosing) return;

    // ⚡ CORREGIDO: Verificar que la posición aún tenga tokens antes de intentar vender
    // Después de una venta parcial, puede que no queden tokens suficientes
    if (refreshed.tokenAmount == null || refreshed.tokenAmount! <= 0) {
      return;
    }

    // ⚡ CORREGIDO: Verificar que haya un nivel válido para activar
    // Esto previene intentos de venta duplicados para el mismo nivel
    final currentPnl = refreshed.pnlPercent;
    if (currentPnl != null) {
      bool hasValidLevel = false;
      if (reason == PositionAlertType.takeProfit) {
        final state = ref.read(autoInvestProvider);
        if (state.takeProfitLevels.isNotEmpty) {
          // Buscar el nivel más alto alcanzado que aún no haya sido activado
          for (final level in state.takeProfitLevels.reversed) {
            if (currentPnl >= level.pnlPercent) {
              if (!refreshed.triggeredSaleLevels.contains(level.pnlPercent)) {
                // Hay un nivel válido para activar
                hasValidLevel = true;
                break;
              }
            }
          }
        } else {
          // Sin niveles escalonados, usar lógica antigua
          hasValidLevel = true;
        }
      } else if (reason == PositionAlertType.stopLoss) {
        final state = ref.read(autoInvestProvider);
        if (state.stopLossLevels.isNotEmpty) {
          // Buscar el nivel más bajo alcanzado que aún no haya sido activado
          for (final level in state.stopLossLevels.reversed) {
            if (currentPnl <= level.pnlPercent) {
              if (!refreshed.triggeredSaleLevels.contains(level.pnlPercent)) {
                // Hay un nivel válido para activar
                hasValidLevel = true;
                break;
              }
            }
          }
        } else {
          // Sin niveles escalonados, usar lógica antigua
          hasValidLevel = true;
        }
      } else {
        // Otros tipos de alerta (no escalonados)
        hasValidLevel = true;
      }

      // Si no hay un nivel válido para activar, no intentar vender
      if (!hasValidLevel) {
        return;
      }
    }

    // Feedback mínimo la primera vez
    if (attempts == 0) {
      final percentSnippet = refreshed.pnlPercent == null
          ? ''
          : ' (${refreshed.pnlPercent!.toStringAsFixed(2)}%)';
      ref
          .read(autoInvestProvider.notifier)
          .setStatus(
            '${reason.label} alcanzado para ${refreshed.symbol}$percentSnippet',
          );
    }

    unawaited(
      ref
          .read(autoInvestExecutorProvider)
          .sellPosition(refreshed, reason: reason),
    );
  }

  _AlertUpdate? _evaluateAlert(
    OpenPosition position,
    AutoInvestState state,
    double? pnlPercent,
    double? maxPnlPercentReached,
  ) {
    if (pnlPercent == null) return null;
    final now = DateTime.now();

    // ⚡ TRAILING STOP: Si está habilitado y hay un máximo alcanzado
    // ⚡ CORREGIDO: El trailing stop tiene prioridad sobre los niveles fijos de stop loss
    // ⚡ PERO: Solo si no hay una venta parcial en progreso (para evitar interferir con ventas escalonadas)
    if (state.trailingStopEnabled &&
        maxPnlPercentReached != null &&
        maxPnlPercentReached > 0) {
      final trailingStopThreshold =
          maxPnlPercentReached - state.trailingStopPercent;
      if (pnlPercent < trailingStopThreshold) {
        // El precio cayó por debajo del trailing stop
        // ⚡ CORREGIDO: Verificar que no haya una venta parcial en progreso
        // Si hay ventas escalonadas activas, el trailing stop puede interferir
        // Solo activar si no hay niveles de stop loss escalonados o si ya se activaron todos
        final hasActiveStopLossLevels = state.stopLossLevels.isNotEmpty;
        final allStopLossLevelsTriggered =
            hasActiveStopLossLevels &&
            state.stopLossLevels.every(
              (level) =>
                  position.triggeredSaleLevels.contains(level.pnlPercent),
            );

        // Solo activar trailing stop si:
        // 1. No hay niveles de stop loss escalonados, O
        // 2. Todos los niveles de stop loss ya fueron activados
        if (!hasActiveStopLossLevels || allStopLossLevelsTriggered) {
          return _AlertUpdate(PositionAlertType.stopLoss, now);
        }
        // Si hay niveles escalonados activos, no activar trailing stop para evitar interferencia
      }
    }

    // ⚡ VENTAS ESCALONADAS - Take Profit
    if (state.takeProfitLevels.isNotEmpty) {
      // Buscar el nivel más alto alcanzado que aún no se haya activado
      for (final level in state.takeProfitLevels.reversed) {
        if (pnlPercent >= level.pnlPercent) {
          // Verificar que este nivel no haya sido activado antes
          if (!position.triggeredSaleLevels.contains(level.pnlPercent)) {
            // ⚡ CORREGIDO: Permitir activar nuevo nivel incluso si ya hay una alerta activa
            // Esto permite que se activen múltiples niveles si el precio sigue subiendo
            return _AlertUpdate(PositionAlertType.takeProfit, now);
          }
        }
      }
    } else {
      // Fallback al comportamiento antiguo
      if (state.takeProfitPercent > 0 &&
          pnlPercent >= state.takeProfitPercent) {
        if (position.alertType == PositionAlertType.takeProfit) {
          return null;
        }
        return _AlertUpdate(PositionAlertType.takeProfit, now);
      }
    }

    // ⚡ VENTAS ESCALONADAS - Stop Loss (solo si no hay trailing stop activo)
    // ⚡ CORREGIDO: El trailing stop solo previene los niveles fijos si está activo Y hay un máximo alcanzado
    // Si el trailing stop está habilitado pero no hay máximo (precio nunca subió), usar niveles fijos
    if (!state.trailingStopEnabled ||
        maxPnlPercentReached == null ||
        maxPnlPercentReached <= 0) {
      if (state.stopLossLevels.isNotEmpty) {
        // Buscar el nivel más bajo alcanzado que aún no se haya activado
        for (final level in state.stopLossLevels.reversed) {
          if (pnlPercent <= level.pnlPercent) {
            // Verificar que este nivel no haya sido activado antes
            if (!position.triggeredSaleLevels.contains(level.pnlPercent)) {
              // ⚡ CORREGIDO: Permitir activar nuevo nivel incluso si ya hay una alerta activa
              // Esto permite que se activen múltiples niveles si el precio sigue bajando
              return _AlertUpdate(PositionAlertType.stopLoss, now);
            }
          }
        }
      } else {
        // Fallback al comportamiento antiguo
        if (state.stopLossPercent > 0 && pnlPercent <= -state.stopLossPercent) {
          if (position.alertType == PositionAlertType.stopLoss) {
            return null;
          }
          return _AlertUpdate(PositionAlertType.stopLoss, now);
        }
      }
    }

    return null;
  }

  void _handleError(OpenPosition position, Object error) {
    final now = DateTime.now();
    final last = _errorCooldown[position.entrySignature];
    if (last != null && now.difference(last) < _errorCooldownDuration) {
      return;
    }
    _errorCooldown[position.entrySignature] = now;
    ref
        .read(autoInvestProvider.notifier)
        .setStatus(
          'Monitoreo falló para ${position.symbol}: $error',
          level: AppLogLevel.error,
        );
  }

  /// 🐋 Verificar actividad de whales para una posición abierta
  /// Si el creator está vendiendo, salir inmediatamente
  Future<void> _checkWhaleActivityForPosition(OpenPosition position) async {
    try {
      // Obtener dirección del creator (si está disponible)
      final securityService = ref.read(tokenSecurityAnalyzerProvider);
      TokenSecurityScore? securityScore;
      try {
        securityScore = await securityService
            .analyzeToken(position.mint)
            .timeout(const Duration(seconds: 2));
      } catch (e) {
        // Si falla, continuar sin security score
        securityScore = null;
      }
      final creatorAddress = securityScore?.creatorAddress;

      // Analizar actividad de whales
      final whaleService = ref.read(whaleTrackerServiceProvider);
      WhaleAnalysis? whaleAnalysis;
      try {
        whaleAnalysis = await whaleService
            .analyzeTokenActivity(
              mint: position.mint,
              creatorAddress: creatorAddress,
              lookbackWindow: const Duration(
                minutes: 2,
              ), // Ventana corta para detección rápida
            )
            .timeout(const Duration(seconds: 2));
      } catch (e) {
        // Si falla, continuar sin whale analysis
        whaleAnalysis = null;
      }

      if (whaleAnalysis == null) return;

      // 🐋 CRÍTICO: Si el creator está vendiendo, salir INMEDIATAMENTE
      if (whaleAnalysis.hasCreatorSells) {
        final executor = ref.read(autoInvestExecutorProvider);
        ref
            .read(autoInvestProvider.notifier)
            .setStatus(
              '🚨 ALERTA: Creator está vendiendo ${position.symbol} - Venta inmediata',
            );
        // Vender inmediatamente (100% de la posición)
        unawaited(
          executor.sellPosition(
            position,
            reason: PositionAlertType.stopLoss, // Usar stop loss como razón
          ),
        );
        return;
      }

      // 🐋 Si hay strong sell de whales, considerar salir también
      if (whaleAnalysis.recommendation == WhaleRecommendation.strongSell) {
        final executor = ref.read(autoInvestExecutorProvider);
        ref
            .read(autoInvestProvider.notifier)
            .setStatus(
              '⚠️ Muchas ventas de whales detectadas en ${position.symbol} - Considerando salida',
            );
        // Vender inmediatamente (100% de la posición)
        unawaited(
          executor.sellPosition(position, reason: PositionAlertType.stopLoss),
        );
        return;
      }
    } catch (e) {
      // Si falla el análisis, continuar normalmente (no bloquear)
    }
  }

  void dispose() {
    _stop();
    _stopPoolMonitoring();
  }
}

class _AlertUpdate {
  _AlertUpdate(this.type, this.timestamp);

  final PositionAlertType type;
  final DateTime timestamp;
}

final autoInvestMonitorProvider = Provider<AutoInvestPositionMonitor>((ref) {
  final monitor = AutoInvestPositionMonitor(
    ref,
    ref.watch(pumpFunPriceServiceProvider),
  );
  monitor.init();
  ref.onDispose(monitor.dispose);
  return monitor;
});
