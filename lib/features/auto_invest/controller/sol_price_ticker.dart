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

  static const _interval = Duration(minutes: 20);

  void init() {
    _refresh();
    _timer = Timer.periodic(_interval, (_) => _refresh());
  }

  Future<void> _refresh() async {
    if (_isFetching) return;
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


