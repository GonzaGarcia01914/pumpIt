import 'package:intl/intl.dart';

class SimulationTrade {
  const SimulationTrade({
    required this.mint,
    required this.symbol,
    required this.entrySol,
    required this.exitSol,
    required this.pnlSol,
    required this.executedAt,
    required this.hitTakeProfit,
    required this.hitStopLoss,
  });

  final String mint;
  final String symbol;
  final double entrySol;
  final double exitSol;
  final double pnlSol;
  final DateTime executedAt;
  final bool hitTakeProfit;
  final bool hitStopLoss;

  String get formattedTime => DateFormat.Hm().format(executedAt);
}

class SimulationRun {
  const SimulationRun({
    required this.timestamp,
    required this.criteriaDescription,
    required this.trades,
  });

  final DateTime timestamp;
  final String criteriaDescription;
  final List<SimulationTrade> trades;

  double get totalSpentSol =>
      trades.fold(0, (previousValue, element) => previousValue + element.entrySol);

  double get totalPnlSol =>
      trades.fold(0, (previousValue, element) => previousValue + element.pnlSol);

  Map<String, dynamic> toSummaryJson() => {
        'timestamp': timestamp.toIso8601String(),
        'criteria': criteriaDescription,
        'trades': trades
            .map((t) => {
                  'mint': t.mint,
                  'symbol': t.symbol,
                  'entrySol': t.entrySol,
                  'exitSol': t.exitSol,
                  'pnlSol': t.pnlSol,
                  'executedAt': t.executedAt.toIso8601String(),
                  'takeProfit': t.hitTakeProfit,
                  'stopLoss': t.hitStopLoss,
                })
            .toList(),
      };
}
