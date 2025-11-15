import '../controller/auto_invest_notifier.dart';
import '../models/position.dart';
import '../models/execution_mode.dart';

extension AutoInvestStateCompat on AutoInvestState {
  List<ClosedPosition> get closedPositions => const <ClosedPosition>[];
  double get solPriceUsd => 0;
}

extension AutoInvestNotifierCompat on AutoInvestNotifier {
  void updateSolPrice(double price) {
    // no-op shim
  }
  void removePosition(
    String entrySignature, {
    bool refundBudget = false,
    String? message,
  }) {
    final current = state;
    final remaining = current.positions
        .where((p) => p.entrySignature != entrySignature)
        .toList(growable: false);
    var available = current.availableBudgetSol;
    if (refundBudget) {
      final removed = current.positions.firstWhere(
        (p) => p.entrySignature == entrySignature,
        orElse: () => OpenPosition(
          mint: '',
          symbol: '',
          entrySol: 0,
          entrySignature: '',
          openedAt: DateTime.fromMillisecondsSinceEpoch(0),
          executionMode: AutoInvestExecutionMode.jupiter,
        ),
      );
      available = (available + removed.entrySol)
          .clamp(0, current.totalBudgetSol)
          .toDouble();
    }
    state = current.copyWith(
      positions: remaining,
      availableBudgetSol: available,
      statusMessage: message,
    );
  }
}

