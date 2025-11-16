import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/position.dart';
import '../services/pump_fun_price_service.dart';
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

  static const _interval = Duration(seconds: 1);
  static const _errorCooldownDuration = Duration(minutes: 2);
  static const _sellRetryDelay = Duration(seconds: 3);
  static const _sellMaxAttempts = 5;
  static const _sellStuckSince = Duration(seconds: 12);

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
    } else {
      _stop();
    }
  }

  bool _shouldMonitor(AutoInvestState state) =>
      state.positions.any((position) => position.hasTokenAmount);

  void _start() {
    _timer ??= Timer.periodic(_interval, (_) => _tick());
    _tick();
  }

  void _stop() {
    _timer?.cancel();
    _timer = null;
  }

  Future<void> _tick() async {
    if (_tickInProgress) return;
    final state = ref.read(autoInvestProvider);
    final positions = state.positions
        .where((position) => position.hasTokenAmount)
        .toList(growable: false);
    if (positions.isEmpty) {
      _stop();
      return;
    }
    // Limpia intentos antiguos de posiciones ya cerradas
    final sigs = positions.map((p) => p.entrySignature).toSet();
    _sellAttempts.removeWhere((k, v) => !sigs.contains(k));
    _sellLastAttempt.removeWhere((k, v) => !sigs.contains(k));
    _tickInProgress = true;
    try {
      for (final position in positions) {
        await _updatePosition(position, state);
      }
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

      final alertUpdate = _evaluateAlert(position, state, pnlPercent);
      ref
          .read(autoInvestProvider.notifier)
          .updatePositionMonitoring(
            position.entrySignature,
            priceSol: quote.priceSol,
            currentValueSol: currentValue,
            pnlSol: pnlSol,
            pnlPercent: pnlPercent,
            checkedAt: quote.fetchedAt,
            alertType: alertUpdate?.type,
            alertTriggeredAt: alertUpdate?.timestamp,
            updateAlert: alertUpdate != null,
          );

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

    // Refresca posición en caso de que haya cambiado flags
    OpenPosition? refreshed;
    for (final candidate in ref.read(autoInvestProvider).positions) {
      if (candidate.entrySignature == position.entrySignature) {
        refreshed = candidate;
        break;
      }
    }
    if (refreshed == null || refreshed.isClosing) return;

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
  ) {
    if (pnlPercent == null) return null;
    final now = DateTime.now();
    if (state.takeProfitPercent > 0 && pnlPercent >= state.takeProfitPercent) {
      if (position.alertType == PositionAlertType.takeProfit) {
        return null;
      }
      return _AlertUpdate(PositionAlertType.takeProfit, now);
    }
    if (state.stopLossPercent > 0 && pnlPercent <= -state.stopLossPercent) {
      if (position.alertType == PositionAlertType.stopLoss) {
        return null;
      }
      return _AlertUpdate(PositionAlertType.stopLoss, now);
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

  void dispose() {
    _stop();
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
