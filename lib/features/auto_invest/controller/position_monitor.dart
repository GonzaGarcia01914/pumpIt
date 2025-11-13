import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/position.dart';
import '../services/pump_fun_price_service.dart';
import 'auto_invest_executor.dart';
import 'auto_invest_notifier.dart';

class AutoInvestPositionMonitor {
  AutoInvestPositionMonitor(this.ref, this.priceService);

  final Ref ref;
  final PumpFunPriceService priceService;

  Timer? _timer;
  bool _tickInProgress = false;
  final Map<String, DateTime> _errorCooldown = {};

  static const _interval = Duration(seconds: 45);
  static const _errorCooldownDuration = Duration(minutes: 2);

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
    _tickInProgress = true;
    try {
      for (final position in positions) {
        await _updatePosition(position, state);
        await Future<void>.delayed(const Duration(milliseconds: 200));
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

      if (alertUpdate != null) {
        final percentSnippet = pnlPercent == null
            ? ''
            : ' (${pnlPercent.toStringAsFixed(2)}%)';
        ref
            .read(autoInvestProvider.notifier)
            .setStatus(
              '${alertUpdate.type.label} alcanzado para ${position.symbol}$percentSnippet',
            );
        OpenPosition? refreshed;
        for (final candidate in ref.read(autoInvestProvider).positions) {
          if (candidate.entrySignature == position.entrySignature) {
            refreshed = candidate;
            break;
          }
        }
        if (refreshed != null && !refreshed.isClosing) {
          unawaited(
            ref
                .read(autoInvestExecutorProvider)
                .sellPosition(refreshed, reason: alertUpdate.type),
          );
        }
      }
    } catch (error) {
      _handleError(position, error);
    }
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
        .setStatus('Monitoreo falló para ${position.symbol}: $error');
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
