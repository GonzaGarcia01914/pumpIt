import '../controller/auto_invest_notifier.dart';
import '../models/position.dart';

extension AutoInvestStateCompat on AutoInvestState {
  List<ClosedPosition> get closedPositions => const <ClosedPosition>[];
  double get solPriceUsd => 0;
}

extension AutoInvestNotifierCompat on AutoInvestNotifier {
  void updateSolPrice(double price) {
    // no-op shim
  }
}
