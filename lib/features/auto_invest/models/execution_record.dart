import 'package:intl/intl.dart';

class ExecutionRecord {
  const ExecutionRecord({
    required this.mint,
    required this.symbol,
    required this.solAmount,
    required this.side,
    required this.txSignature,
    required this.executedAt,
    this.status = 'submitted',
    this.errorMessage,
  });

  final String mint;
  final String symbol;
  final double solAmount;
  final String side; // buy / sell
  final String txSignature;
  final DateTime executedAt;
  final String status;
  final String? errorMessage;

  String get formattedTime => DateFormat('dd/MM HH:mm').format(executedAt);
}
