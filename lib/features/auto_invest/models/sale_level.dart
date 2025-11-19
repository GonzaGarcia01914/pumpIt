class SaleLevel {
  const SaleLevel({
    required this.pnlPercent,
    required this.sellPercent,
  });

  final double pnlPercent; // PnL % que activa este nivel
  final double sellPercent; // % del restante a vender en este nivel

  SaleLevel copyWith({
    double? pnlPercent,
    double? sellPercent,
  }) {
    return SaleLevel(
      pnlPercent: pnlPercent ?? this.pnlPercent,
      sellPercent: sellPercent ?? this.sellPercent,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'pnlPercent': pnlPercent,
      'sellPercent': sellPercent,
    };
  }

  factory SaleLevel.fromJson(Map<String, dynamic> json) {
    return SaleLevel(
      pnlPercent: (json['pnlPercent'] as num).toDouble(),
      sellPercent: (json['sellPercent'] as num).toDouble(),
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is SaleLevel &&
        other.pnlPercent == pnlPercent &&
        other.sellPercent == sellPercent;
  }

  @override
  int get hashCode => Object.hash(pnlPercent, sellPercent);
}

