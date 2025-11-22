/// 📊 Configuraciones predefinidas para trailing stop dinámico
enum TrailingConfigPreset {
  safe, // Opción A - Segura
  aggressive, // Opción B - Agresiva optimizada
  balanced, // Opción C - Equilibrada
}

/// 📊 Parámetros de configuración para trailing stop dinámico
class TrailingConfig {
  const TrailingConfig({
    required this.lowVolatilityTrailing,
    required this.mediumVolatilityTrailing,
    required this.highVolatilityTrailing,
    required this.mediumVolatilityThreshold,
    required this.highVolatilityThreshold,
    required this.name,
    required this.description,
  });

  final double lowVolatilityTrailing;
  final double mediumVolatilityTrailing;
  final double highVolatilityTrailing;
  final double mediumVolatilityThreshold;
  final double highVolatilityThreshold;
  final String name;
  final String description;

  /// Opción A - Segura
  /// Para reducir las pérdidas grandes pero mantener buenos pumps
  static const TrailingConfig safe = TrailingConfig(
    lowVolatilityTrailing: 0.10, // 10%
    mediumVolatilityTrailing: 0.18, // 18%
    highVolatilityTrailing: 0.25, // 25%
    mediumVolatilityThreshold: 0.15, // 15%
    highVolatilityThreshold: 0.30, // 30%
    name: 'Segura',
    description: 'Reduce pérdidas grandes pero mantiene buenos pumps',
  );

  /// Opción B - Agresiva optimizada
  /// Para capturar más x2, x3, x5 sin morir en el intento
  static const TrailingConfig aggressive = TrailingConfig(
    lowVolatilityTrailing: 0.12, // 12%
    mediumVolatilityTrailing: 0.22, // 22%
    highVolatilityTrailing: 0.30, // 30%
    mediumVolatilityThreshold: 0.20, // 20%
    highVolatilityThreshold: 0.40, // 40%
    name: 'Agresiva',
    description: 'Captura más x2, x3, x5 sin morir en el intento',
  );

  /// Opción C - Equilibrada
  /// Recomendada para uso general
  static const TrailingConfig balanced = TrailingConfig(
    lowVolatilityTrailing: 0.10, // 10%
    mediumVolatilityTrailing: 0.18, // 18%
    highVolatilityTrailing: 0.25, // 25%
    mediumVolatilityThreshold: 0.15, // 15%
    highVolatilityThreshold: 0.30, // 30%
    name: 'Equilibrada',
    description: 'Balance entre seguridad y captura de ganancias',
  );

  /// Obtener configuración por preset
  static TrailingConfig fromPreset(TrailingConfigPreset preset) {
    switch (preset) {
      case TrailingConfigPreset.safe:
        return safe;
      case TrailingConfigPreset.aggressive:
        return aggressive;
      case TrailingConfigPreset.balanced:
        return balanced;
    }
  }

  /// Convertir a string para serialización
  String toJson() {
    if (this == safe) return 'safe';
    if (this == aggressive) return 'aggressive';
    if (this == balanced) return 'balanced';
    return 'balanced';
  }

  /// Crear desde string
  static TrailingConfigPreset fromJson(String? json) {
    if (json == null) return TrailingConfigPreset.balanced;
    return TrailingConfigPreset.values.firstWhere(
      (e) => e.name == json,
      orElse: () => TrailingConfigPreset.balanced,
    );
  }

  TrailingConfigPreset get preset {
    if (this == safe) return TrailingConfigPreset.safe;
    if (this == aggressive) return TrailingConfigPreset.aggressive;
    if (this == balanced) return TrailingConfigPreset.balanced;
    return TrailingConfigPreset.balanced; // Default
  }
}
