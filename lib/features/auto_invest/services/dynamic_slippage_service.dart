import 'dart:async';
import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 📊 Parámetros para calcular slippage dinámico
class SlippageCalculationParams {
  SlippageCalculationParams({
    required this.baseSlippagePercent,
    required this.orderSizeSol,
    required this.currentPriceSol,
    this.liquiditySol,
    this.priceHistory,
    this.volatility,
  });

  final double baseSlippagePercent; // Slippage base configurado por el usuario
  final double orderSizeSol; // Tamaño de la orden en SOL
  final double currentPriceSol; // Precio actual del token
  final double? liquiditySol; // Liquidez disponible en el pool
  final List<double>? priceHistory; // Historial de precios recientes (para volatilidad)
  final double? volatility; // Volatilidad pre-calculada (0-1, donde 1 es muy volátil)
}

/// 📊 Servicio para calcular slippage dinámico basado en condiciones del mercado
class DynamicSlippageService {
  DynamicSlippageService();

  // Cache de precios recientes para calcular volatilidad
  final Map<String, List<_PricePoint>> _priceHistory = {};
  static const _maxHistorySize = 20; // Mantener últimos 20 puntos de precio
  static const _historyWindow = Duration(minutes: 5); // Ventana de 5 minutos

  /// 📊 Calcular slippage dinámico óptimo
  /// Retorna un porcentaje de slippage ajustado según condiciones del mercado
  Future<double> calculateOptimalSlippage(SlippageCalculationParams params) async {
    double slippage = params.baseSlippagePercent;

    // 1. Ajustar por volatilidad del token
    final volatility = params.volatility ?? await _calculateVolatility(
      params.currentPriceSol,
      params.priceHistory,
    );
    if (volatility > 0.5) {
      // Alta volatilidad: aumentar slippage
      slippage += volatility * 10.0; // Hasta +10% adicional
    } else if (volatility < 0.2) {
      // Baja volatilidad: reducir slippage ligeramente
      slippage -= (0.2 - volatility) * 2.0; // Hasta -2% menos
    }

    // 2. Ajustar por liquidez disponible
    if (params.liquiditySol != null) {
      final liquidityRatio = params.orderSizeSol / params.liquiditySol!;
      if (liquidityRatio > 0.1) {
        // Orden grande relativa a liquidez: aumentar slippage
        slippage += liquidityRatio * 15.0; // Hasta +15% adicional
      } else if (liquidityRatio < 0.01) {
        // Orden pequeña relativa a liquidez: reducir slippage
        slippage -= 1.0; // -1% menos
      }
    }

    // 3. Ajustar por tamaño de orden absoluto
    if (params.orderSizeSol > 5.0) {
      // Ordenes grandes (>5 SOL): aumentar slippage
      slippage += (params.orderSizeSol - 5.0) * 0.5; // +0.5% por SOL adicional
    } else if (params.orderSizeSol < 0.1) {
      // Ordenes muy pequeñas (<0.1 SOL): reducir slippage
      slippage -= 2.0; // -2% menos
    }

    // 4. Ajustar por velocidad de cambio de precio
    final priceChangeSpeed = await _calculatePriceChangeSpeed(
      params.currentPriceSol,
      params.priceHistory,
    );
    if (priceChangeSpeed > 0.05) {
      // Precio cambiando rápido (>5% por minuto): aumentar slippage
      slippage += priceChangeSpeed * 20.0; // Hasta +20% adicional
    }

    // Límites de seguridad
    slippage = slippage.clamp(0.1, 50.0); // Entre 0.1% y 50%

    return slippage;
  }

  /// 📈 Calcular volatilidad del token basada en historial de precios
  Future<double> _calculateVolatility(
    double currentPrice,
    List<double>? priceHistory,
  ) async {
    if (priceHistory == null || priceHistory.length < 3) {
      // Sin historial suficiente, usar volatilidad conservadora
      return 0.3; // 30% de volatilidad asumida
    }

    // Calcular desviación estándar de los cambios porcentuales
    final changes = <double>[];
    for (var i = 1; i < priceHistory.length; i++) {
      if (priceHistory[i - 1] > 0) {
        final change = (priceHistory[i] - priceHistory[i - 1]) / priceHistory[i - 1];
        changes.add(change.abs());
      }
    }

    if (changes.isEmpty) return 0.3;

    // Calcular promedio y desviación estándar
    final avgChange = changes.reduce((a, b) => a + b) / changes.length;
    final variance = changes
        .map((c) => math.pow(c - avgChange, 2))
        .reduce((a, b) => a + b) / changes.length;
    final stdDev = math.sqrt(variance);

    // Normalizar a 0-1 (donde 1 es muy volátil)
    // Consideramos >20% de desviación estándar como muy volátil
    return (stdDev / 0.2).clamp(0.0, 1.0);
  }

  /// ⚡ Calcular velocidad de cambio de precio
  Future<double> _calculatePriceChangeSpeed(
    double currentPrice,
    List<double>? priceHistory,
  ) async {
    if (priceHistory == null || priceHistory.length < 2) {
      return 0.0; // Sin historial, asumir precio estable
    }

    // Calcular cambio porcentual promedio por minuto
    final recentPrices = priceHistory.take(5).toList(); // Últimos 5 puntos
    if (recentPrices.isEmpty) return 0.0;

    final oldestPrice = recentPrices.last;
    if (oldestPrice <= 0) return 0.0;

    final totalChange = (currentPrice - oldestPrice) / oldestPrice;
    // Asumir que los datos cubren ~1 minuto (ajustar según frecuencia de actualización)
    final changePerMinute = totalChange.abs() / recentPrices.length;

    return changePerMinute.clamp(0.0, 0.5); // Máximo 50% por minuto
  }

  /// 📊 Registrar un nuevo punto de precio para tracking de volatilidad
  void recordPricePoint(String mint, double priceSol) {
    final now = DateTime.now();
    final history = _priceHistory.putIfAbsent(mint, () => <_PricePoint>[]);

    // Agregar nuevo punto
    history.add(_PricePoint(price: priceSol, timestamp: now));

    // Limpiar puntos antiguos
    final cutoff = now.subtract(_historyWindow);
    history.removeWhere((point) => point.timestamp.isBefore(cutoff));

    // Limitar tamaño
    if (history.length > _maxHistorySize) {
      history.removeRange(0, history.length - _maxHistorySize);
    }
  }

  /// 📊 Obtener historial de precios para un token
  List<double>? getPriceHistory(String mint) {
    final history = _priceHistory[mint];
    if (history == null || history.isEmpty) return null;

    return history.map((p) => p.price).toList();
  }

  /// 📊 Calcular volatilidad actual de un token (usando cache interno)
  Future<double> getCurrentVolatility(String mint) async {
    final history = _priceHistory[mint];
    if (history == null || history.length < 3) {
      return 0.3; // Volatilidad conservadora por defecto
    }

    final prices = history.map((p) => p.price).toList();
    final currentPrice = prices.last;
    return await _calculateVolatility(currentPrice, prices);
  }

  /// 📊 Calcular velocidad de cambio de precio actual (usando cache interno)
  Future<double> getCurrentPriceChangeSpeed(String mint) async {
    final history = _priceHistory[mint];
    if (history == null || history.length < 2) {
      return 0.0;
    }

    final prices = history.map((p) => p.price).toList();
    final currentPrice = prices.last;
    return await _calculatePriceChangeSpeed(currentPrice, prices);
  }
}

/// 📊 Punto de precio con timestamp
class _PricePoint {
  _PricePoint({
    required this.price,
    required this.timestamp,
  });

  final double price;
  final DateTime timestamp;
}

final dynamicSlippageServiceProvider = Provider<DynamicSlippageService>((ref) {
  return DynamicSlippageService();
});

