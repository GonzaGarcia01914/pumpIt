import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/sol_price_service.dart';
import 'auto_invest_notifier.dart';

class SolPriceTicker {
  SolPriceTicker(this.ref, this.service);

  final Ref ref;
  final SolPriceService service;

  Timer? _timer;
  bool _isFetching = false;
  bool _isActive = false;

  static const _interval = Duration(minutes: 20);

  void init() {
    ref.listen<AutoInvestState>(
      autoInvestProvider,
      (_, next) => _handleAutoInvestState(next),
      fireImmediately: true,
    );
  }

  void _handleAutoInvestState(AutoInvestState state) {
    final shouldRun = _shouldTrack(state);
    if (shouldRun == _isActive) {
      return;
    }
    _isActive = shouldRun;
    if (shouldRun) {
      _refresh();
      _timer ??= Timer.periodic(_interval, (_) => _refresh());
    } else {
      _timer?.cancel();
      _timer = null;
    }
  }

  bool _shouldTrack(AutoInvestState state) {
    return state.isEnabled ||
        state.positions.isNotEmpty ||
        state.closedPositions.isNotEmpty ||
        state.walletAddress != null;
  }

  Future<void> _refresh() async {
    if (_isFetching || !_isActive) return;
    _isFetching = true;
    try {
      final price = await service.fetchUsdPrice();
      if (price > 0) {
        ref.read(autoInvestProvider.notifier).updateSolPrice(price);
      }
    } catch (_) {
      // ignore fetch errors silently
    } finally {
      _isFetching = false;
    }
  }

  void dispose() {
    _timer?.cancel();
  }
}

final solPriceTickerProvider = Provider<SolPriceTicker>((ref) {
  final ticker = SolPriceTicker(ref, ref.watch(solPriceServiceProvider));
  ticker.init();
  ref.onDispose(ticker.dispose);
  return ticker;
});


