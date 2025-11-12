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

  ExecutionRecord copyWith({
    String? status,
    String? errorMessage,
  }) {
    return ExecutionRecord(
      mint: mint,
      symbol: symbol,
      solAmount: solAmount,
      side: side,
      txSignature: txSignature,
      executedAt: executedAt,
      status: status ?? this.status,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }

  Map<String, dynamic> toJson() => {
        'mint': mint,
        'symbol': symbol,
        'solAmount': solAmount,
        'side': side,
        'txSignature': txSignature,
        'executedAt': executedAt.toIso8601String(),
        'status': status,
        'errorMessage': errorMessage,
      };

  factory ExecutionRecord.fromJson(Map<String, dynamic> json) {
    DateTime parseDate(dynamic value) {
      if (value is String) {
        return DateTime.tryParse(value) ?? DateTime.now();
      }
      return DateTime.now();
    }

    return ExecutionRecord(
      mint: json['mint']?.toString() ?? '',
      symbol: json['symbol']?.toString() ?? '',
      solAmount: (json['solAmount'] as num?)?.toDouble() ?? 0,
      side: json['side']?.toString() ?? 'buy',
      txSignature: json['txSignature']?.toString() ?? '',
      executedAt: parseDate(json['executedAt']),
      status: json['status']?.toString() ?? 'submitted',
      errorMessage: json['errorMessage']?.toString(),
    );
  }
}
