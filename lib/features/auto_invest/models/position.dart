import 'package:equatable/equatable.dart';

import 'execution_mode.dart';

enum PositionAlertType { takeProfit, stopLoss }

extension PositionAlertTypeX on PositionAlertType {
  String get label =>
      this == PositionAlertType.takeProfit ? 'Take profit' : 'Stop loss';
}

class _PositionCopySentinel {
  const _PositionCopySentinel();
}

const _copySentinel = _PositionCopySentinel();

class OpenPosition extends Equatable {
  const OpenPosition({
    required this.mint,
    required this.symbol,
    required this.entrySol,
    required this.entrySignature,
    required this.openedAt,
    required this.executionMode,
    this.tokenAmount,
    this.entryPriceSol,
    this.lastPriceSol,
    this.currentValueSol,
    this.pnlSol,
    this.pnlPercent,
    this.lastCheckedAt,
    this.alertType,
    this.alertTriggeredAt,
    this.isClosing = false,
  });

  final String mint;
  final String symbol;
  final double entrySol;
  final String entrySignature;
  final DateTime openedAt;
  final AutoInvestExecutionMode executionMode;
  final double? tokenAmount;
  final double? entryPriceSol;
  final double? lastPriceSol;
  final double? currentValueSol;
  final double? pnlSol;
  final double? pnlPercent;
  final DateTime? lastCheckedAt;
  final PositionAlertType? alertType;
  final DateTime? alertTriggeredAt;
  final bool isClosing;

  bool get hasTokenAmount => tokenAmount != null && tokenAmount! > 0;

  bool get hasMonitoringSnapshot =>
      lastPriceSol != null && currentValueSol != null && pnlSol != null;

  OpenPosition copyWith({
    double? entrySol,
    Object? tokenAmount = _copySentinel,
    Object? entryPriceSol = _copySentinel,
    Object? lastPriceSol = _copySentinel,
    Object? currentValueSol = _copySentinel,
    Object? pnlSol = _copySentinel,
    Object? pnlPercent = _copySentinel,
    Object? lastCheckedAt = _copySentinel,
    Object? alertType = _copySentinel,
    Object? alertTriggeredAt = _copySentinel,
    Object? isClosing = _copySentinel,
  }) {
    return OpenPosition(
      mint: mint,
      symbol: symbol,
      entrySol: entrySol ?? this.entrySol,
      entrySignature: entrySignature,
      openedAt: openedAt,
      executionMode: executionMode,
      tokenAmount: identical(tokenAmount, _copySentinel)
          ? this.tokenAmount
          : tokenAmount as double?,
      entryPriceSol: identical(entryPriceSol, _copySentinel)
          ? this.entryPriceSol
          : entryPriceSol as double?,
      lastPriceSol: identical(lastPriceSol, _copySentinel)
          ? this.lastPriceSol
          : lastPriceSol as double?,
      currentValueSol: identical(currentValueSol, _copySentinel)
          ? this.currentValueSol
          : currentValueSol as double?,
      pnlSol: identical(pnlSol, _copySentinel)
          ? this.pnlSol
          : pnlSol as double?,
      pnlPercent: identical(pnlPercent, _copySentinel)
          ? this.pnlPercent
          : pnlPercent as double?,
      lastCheckedAt: identical(lastCheckedAt, _copySentinel)
          ? this.lastCheckedAt
          : lastCheckedAt as DateTime?,
      alertType: identical(alertType, _copySentinel)
          ? this.alertType
          : alertType as PositionAlertType?,
      alertTriggeredAt: identical(alertTriggeredAt, _copySentinel)
          ? this.alertTriggeredAt
          : alertTriggeredAt as DateTime?,
      isClosing: identical(isClosing, _copySentinel)
          ? this.isClosing
          : isClosing as bool,
    );
  }

  Map<String, dynamic> toJson() => {
    'mint': mint,
    'symbol': symbol,
    'entrySol': entrySol,
    'entrySignature': entrySignature,
    'openedAt': openedAt.toIso8601String(),
    'executionMode': executionMode.name,
    'tokenAmount': tokenAmount,
    'entryPriceSol': entryPriceSol,
    'lastPriceSol': lastPriceSol,
    'currentValueSol': currentValueSol,
    'pnlSol': pnlSol,
    'pnlPercent': pnlPercent,
    'lastCheckedAt': lastCheckedAt?.toIso8601String(),
    'alertType': alertType?.name,
    'alertTriggeredAt': alertTriggeredAt?.toIso8601String(),
    'isClosing': isClosing,
  };

  factory OpenPosition.fromJson(Map<String, dynamic> json) {
    PositionAlertType? alertFromJson(dynamic raw) {
      final name = raw?.toString();
      if (name == null) return null;
      try {
        return PositionAlertType.values.firstWhere((type) => type.name == name);
      } catch (_) {
        return null;
      }
    }

    DateTime? parseDate(dynamic value) {
      if (value == null) return null;
      return DateTime.tryParse(value.toString());
    }

    return OpenPosition(
      mint: json['mint']?.toString() ?? '',
      symbol: json['symbol']?.toString() ?? '',
      entrySol: (json['entrySol'] as num?)?.toDouble() ?? 0,
      entrySignature: json['entrySignature']?.toString() ?? '',
      openedAt:
          DateTime.tryParse(json['openedAt']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      executionMode: AutoInvestExecutionMode.values.firstWhere(
        (mode) => mode.name == json['executionMode'],
        orElse: () => AutoInvestExecutionMode.jupiter,
      ),
      tokenAmount: (json['tokenAmount'] as num?)?.toDouble(),
      entryPriceSol: (json['entryPriceSol'] as num?)?.toDouble(),
      lastPriceSol: (json['lastPriceSol'] as num?)?.toDouble(),
      currentValueSol: (json['currentValueSol'] as num?)?.toDouble(),
      pnlSol: (json['pnlSol'] as num?)?.toDouble(),
      pnlPercent: (json['pnlPercent'] as num?)?.toDouble(),
      lastCheckedAt: parseDate(json['lastCheckedAt']),
      alertType: alertFromJson(json['alertType']),
      alertTriggeredAt: parseDate(json['alertTriggeredAt']),
      isClosing: json['isClosing'] as bool? ?? false,
    );
  }

  @override
  List<Object?> get props => [
    mint,
    symbol,
    entrySol,
    entrySignature,
    openedAt,
    executionMode,
    tokenAmount,
    entryPriceSol,
    lastPriceSol,
    currentValueSol,
    pnlSol,
    pnlPercent,
    lastCheckedAt,
    alertType,
    alertTriggeredAt,
    isClosing,
  ];
}

class ClosedPosition extends Equatable {
  const ClosedPosition({
    required this.mint,
    required this.symbol,
    required this.executionMode,
    required this.entrySol,
    required this.exitSol,
    required this.tokenAmount,
    required this.entryPriceSol,
    required this.exitPriceSol,
    required this.pnlSol,
    required this.pnlPercent,
    required this.openedAt,
    required this.closedAt,
    required this.buySignature,
    required this.sellSignature,
    this.closeReason,
  });

  final String mint;
  final String symbol;
  final AutoInvestExecutionMode executionMode;
  final double entrySol;
  final double exitSol;
  final double tokenAmount;
  final double entryPriceSol;
  final double exitPriceSol;
  final double pnlSol;
  final double pnlPercent;
  final DateTime openedAt;
  final DateTime closedAt;
  final String buySignature;
  final String sellSignature;
  final PositionAlertType? closeReason;

  Map<String, dynamic> toJson() => {
    'mint': mint,
    'symbol': symbol,
    'executionMode': executionMode.name,
    'entrySol': entrySol,
    'exitSol': exitSol,
    'tokenAmount': tokenAmount,
    'entryPriceSol': entryPriceSol,
    'exitPriceSol': exitPriceSol,
    'pnlSol': pnlSol,
    'pnlPercent': pnlPercent,
    'openedAt': openedAt.toIso8601String(),
    'closedAt': closedAt.toIso8601String(),
    'buySignature': buySignature,
    'sellSignature': sellSignature,
    'closeReason': closeReason?.name,
  };

  factory ClosedPosition.fromJson(Map<String, dynamic> json) {
    PositionAlertType? alertFromJson(dynamic raw) {
      final name = raw?.toString();
      if (name == null) return null;
      try {
        return PositionAlertType.values.firstWhere((type) => type.name == name);
      } catch (_) {
        return null;
      }
    }

    DateTime parseDate(dynamic value) {
      if (value is String) {
        return DateTime.tryParse(value) ??
            DateTime.fromMillisecondsSinceEpoch(0);
      }
      return DateTime.fromMillisecondsSinceEpoch(0);
    }

    return ClosedPosition(
      mint: json['mint']?.toString() ?? '',
      symbol: json['symbol']?.toString() ?? '',
      executionMode: AutoInvestExecutionMode.values.firstWhere(
        (mode) => mode.name == json['executionMode'],
        orElse: () => AutoInvestExecutionMode.jupiter,
      ),
      entrySol: (json['entrySol'] as num?)?.toDouble() ?? 0,
      exitSol: (json['exitSol'] as num?)?.toDouble() ?? 0,
      tokenAmount: (json['tokenAmount'] as num?)?.toDouble() ?? 0,
      entryPriceSol: (json['entryPriceSol'] as num?)?.toDouble() ?? 0,
      exitPriceSol: (json['exitPriceSol'] as num?)?.toDouble() ?? 0,
      pnlSol: (json['pnlSol'] as num?)?.toDouble() ?? 0,
      pnlPercent: (json['pnlPercent'] as num?)?.toDouble() ?? 0,
      openedAt: parseDate(json['openedAt']),
      closedAt: parseDate(json['closedAt']),
      buySignature: json['buySignature']?.toString() ?? '',
      sellSignature: json['sellSignature']?.toString() ?? '',
      closeReason: alertFromJson(json['closeReason']),
    );
  }

  @override
  List<Object?> get props => [
    mint,
    symbol,
    executionMode,
    entrySol,
    exitSol,
    tokenAmount,
    entryPriceSol,
    exitPriceSol,
    pnlSol,
    pnlPercent,
    openedAt,
    closedAt,
    buySignature,
    sellSignature,
    closeReason,
  ];
}
