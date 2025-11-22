import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/trailing_config.dart';
import 'whale_tracker_service.dart';
import 'token_security_analyzer.dart';

/// 📊 Parámetros para calcular trailing stop dinámico
class DynamicTrailingParams {
  DynamicTrailingParams({
    required this.baseTrailingPercent,
    required this.mint,
    required this.config,
    this.currentPrice,
    this.priceHistory,
    this.whaleAnalysis,
    this.securityScore,
  });

  final double baseTrailingPercent; // Trailing base configurado por el usuario
  final String mint;
  final TrailingConfig config; // Configuración seleccionada
  final double? currentPrice;
  final List<double>?
  priceHistory; // Historial de precios para calcular volatilidad
  final WhaleAnalysis? whaleAnalysis; // Análisis de whales (opcional)
  final TokenSecurityScore? securityScore; // Score de seguridad (opcional)
}

/// 📊 Resultado del cálculo de trailing stop dinámico
class DynamicTrailingResult {
  DynamicTrailingResult({
    required this.optimalTrailingPercent,
    required this.volatilityFactor,
    required this.whaleFactor,
    required this.warningFactor,
    this.recommendedHardStop,
  });

  final double optimalTrailingPercent; // Trailing stop óptimo calculado
  final double volatilityFactor; // Factor de volatilidad (0-1)
  final double whaleFactor; // Factor de whales (0-1)
  final double warningFactor; // Factor de warnings (0-1)
  final double? recommendedHardStop; // Hard stop recomendado (opcional)
}

/// 📊 Servicio para calcular trailing stop dinámico basado en condiciones del mercado
class DynamicTrailingStopService {
  DynamicTrailingStopService();

  // Cache de cálculos (válido por 10 segundos)
  final Map<String, DynamicTrailingResult> _calculationCache = {};
  final Map<String, DateTime> _cacheTime = {};
  static const _cacheValidity = Duration(seconds: 10);

  // Hard stop de seguridad por defecto
  static const _defaultHardStop = 0.20; // -20%

  /// 📊 Calcular trailing stop dinámico óptimo
  Future<DynamicTrailingResult> calculateOptimalTrailing(
    DynamicTrailingParams params,
  ) async {
    final normalizedMint = params.mint.trim();
    final now = DateTime.now();

    // Verificar cache
    final cached = _calculationCache[normalizedMint];
    final cachedAt = _cacheTime[normalizedMint];
    if (cached != null &&
        cachedAt != null &&
        now.difference(cachedAt) < _cacheValidity) {
      return cached;
    }

    // 1. Calcular factor de volatilidad basado en velas de precio
    final volatilityFactor = await _calculateVolatilityFactor(
      params.priceHistory,
      params.currentPrice,
    );

    // 2. Calcular factor de whales (smart money)
    final whaleFactor = _calculateWhaleFactor(params.whaleAnalysis);

    // 3. Calcular factor de warnings (creator vende, volumen cae, etc.)
    final warningFactor = _calculateWarningFactor(
      params.securityScore,
      params.whaleAnalysis,
    );

    // 4. Calcular trailing stop dinámico
    // Fórmula: DynamicTrailing = base * (1 + volatilityFactor + whaleFactor - warningFactor)
    final dynamicTrailing =
        params.baseTrailingPercent *
        (1.0 + volatilityFactor + whaleFactor - warningFactor);

    // 5. Ajustar según volatilidad instantánea (velas) usando la configuración
    final volatilityAdjustedTrailing = _adjustByInstantVolatility(
      dynamicTrailing,
      params.priceHistory,
      params.config,
    );

    // Asegurar que el trailing esté en un rango razonable (1% - 50%)
    final optimalTrailing = volatilityAdjustedTrailing.clamp(1.0, 50.0);

    // 6. Calcular hard stop recomendado
    final recommendedHardStop = _calculateHardStop(
      optimalTrailing,
      volatilityFactor,
      warningFactor,
    );

    final result = DynamicTrailingResult(
      optimalTrailingPercent: optimalTrailing,
      volatilityFactor: volatilityFactor,
      whaleFactor: whaleFactor,
      warningFactor: warningFactor,
      recommendedHardStop: recommendedHardStop,
    );

    // Guardar en cache
    _calculationCache[normalizedMint] = result;
    _cacheTime[normalizedMint] = now;

    return result;
  }

  /// 📊 Calcular factor de volatilidad (0-1)
  /// Basado en la amplitud promedio de las velas recientes
  Future<double> _calculateVolatilityFactor(
    List<double>? priceHistory,
    double? currentPrice,
  ) async {
    if (priceHistory == null || priceHistory.length < 3) {
      return 0.0; // Sin historial, sin ajuste por volatilidad
    }

    // Calcular cambios porcentuales
    final changes = <double>[];
    for (var i = 1; i < priceHistory.length; i++) {
      if (priceHistory[i - 1] > 0) {
        final change =
            (priceHistory[i] - priceHistory[i - 1]) / priceHistory[i - 1];
        changes.add(change.abs());
      }
    }

    if (changes.isEmpty) return 0.0;

    // Calcular promedio de amplitud de velas
    final avgCandleSize = changes.reduce((a, b) => a + b) / changes.length;

    // Normalizar volatilidad a factor 0-1 usando los umbrales de la configuración
    // Se usa una configuración por defecto para el cálculo del factor
    // (los umbrales reales se usan en _adjustByInstantVolatility)
    final defaultHighThreshold = 0.20;
    final defaultMediumThreshold = 0.10;

    if (avgCandleSize > defaultHighThreshold) {
      return 0.5 +
          ((avgCandleSize - defaultHighThreshold) / 0.3).clamp(
            0.0,
            0.5,
          ); // 0.5-1.0
    } else if (avgCandleSize > defaultMediumThreshold) {
      return 0.2 +
          ((avgCandleSize - defaultMediumThreshold) / 0.1).clamp(
            0.0,
            0.3,
          ); // 0.2-0.5
    } else {
      return (avgCandleSize / defaultMediumThreshold).clamp(
        0.0,
        0.2,
      ); // 0.0-0.2
    }
  }

  /// 📊 Calcular factor de whales (0-1)
  /// Si hay smart money comprando, aumentar trailing
  double _calculateWhaleFactor(WhaleAnalysis? whaleAnalysis) {
    if (whaleAnalysis == null) {
      return 0.0; // Sin datos, sin ajuste
    }

    switch (whaleAnalysis.recommendation) {
      case WhaleRecommendation.strongBuy:
        return 0.3; // Smart money comprando fuerte → aumentar trailing
      case WhaleRecommendation.buy:
        return 0.15; // Smart money comprando → aumentar trailing moderadamente
      case WhaleRecommendation.neutral:
        return 0.0; // Sin señal clara
      case WhaleRecommendation.sell:
        return -0.1; // Smart money vendiendo → reducir trailing
      case WhaleRecommendation.strongSell:
        return -0.2; // Smart money vendiendo fuerte → reducir trailing
      default:
        return 0.0; // Caso por defecto (null o desconocido)
    }
  }

  /// 📊 Calcular factor de warnings (0-1)
  /// Si creator vende o hay warnings, reducir trailing
  double _calculateWarningFactor(
    TokenSecurityScore? securityScore,
    WhaleAnalysis? whaleAnalysis,
  ) {
    double warningFactor = 0.0;

    // Si el creator está vendiendo, aumentar warning factor
    if (whaleAnalysis?.hasCreatorSells == true) {
      warningFactor += 0.4; // Creator vendiendo es muy malo
    }

    // Si hay riesgos de seguridad, aumentar warning factor
    if (securityScore != null) {
      if (securityScore.risks.isNotEmpty) {
        warningFactor += 0.2 * securityScore.risks.length; // 0.2 por riesgo
      }
      if (securityScore.warnings.isNotEmpty) {
        warningFactor += 0.1 * securityScore.warnings.length; // 0.1 por warning
      }
    }

    // Si hay mucha presión de venta de whales, aumentar warning
    if (whaleAnalysis != null) {
      final sellPressure = whaleAnalysis.whaleSellPressure;
      if (sellPressure > 0.7) {
        warningFactor += 0.3; // Mucha presión de venta
      } else if (sellPressure > 0.5) {
        warningFactor += 0.15; // Presión de venta moderada
      }
    }

    return warningFactor.clamp(0.0, 1.0);
  }

  /// 📊 Ajustar trailing por volatilidad instantánea (velas)
  /// Si hay velas grandes, aumentar trailing; si se aplana, reducir
  double _adjustByInstantVolatility(
    double baseTrailing,
    List<double>? priceHistory,
    TrailingConfig config,
  ) {
    if (priceHistory == null || priceHistory.length < 5) {
      return baseTrailing; // Sin suficientes datos, usar base
    }

    // Calcular cambios porcentuales recientes (últimas 5 velas)
    final recentChanges = <double>[];
    for (var i = priceHistory.length - 5; i < priceHistory.length - 1; i++) {
      if (i >= 0 && priceHistory[i] > 0) {
        final change =
            (priceHistory[i + 1] - priceHistory[i]) / priceHistory[i];
        recentChanges.add(change.abs());
      }
    }

    if (recentChanges.isEmpty) {
      return baseTrailing;
    }

    // Calcular promedio de amplitud de velas
    final avgCandleSize =
        recentChanges.reduce((a, b) => a + b) / recentChanges.length;

    // Ajustar trailing según tamaño de velas usando la configuración seleccionada
    if (avgCandleSize >= config.highVolatilityThreshold) {
      // Velas grandes → trailing alto
      return config.highVolatilityTrailing;
    } else if (avgCandleSize >= config.mediumVolatilityThreshold) {
      // Velas medianas → trailing medio
      return config.mediumVolatilityTrailing;
    } else if (avgCandleSize >= 0.02) {
      // Velas pequeñas → trailing bajo
      return config.lowVolatilityTrailing;
    } else {
      // Velas muy pequeñas (<2%) → momentum se aplana, usar trailing conservador
      return baseTrailing * 0.7; // Reducir 30%
    }
  }

  /// 📊 Calcular hard stop recomendado
  /// Hard stop adicional de seguridad para evitar dumps grandes
  double _calculateHardStop(
    double optimalTrailing,
    double volatilityFactor,
    double warningFactor,
  ) {
    // Base: -20%
    double hardStop = _defaultHardStop;

    // Si hay muchos warnings, hard stop más agresivo
    if (warningFactor > 0.5) {
      hardStop = 0.15; // -15% si hay muchos warnings
    }

    // Si la volatilidad es muy alta, hard stop más agresivo
    if (volatilityFactor > 0.7) {
      hardStop = 0.15; // -15% si volatilidad muy alta
    }

    return hardStop;
  }

  /// 📊 Limpiar cache (útil para testing o reset)
  void clearCache() {
    _calculationCache.clear();
    _cacheTime.clear();
  }
}

final dynamicTrailingStopServiceProvider = Provider<DynamicTrailingStopService>(
  (ref) {
    return DynamicTrailingStopService();
  },
);
