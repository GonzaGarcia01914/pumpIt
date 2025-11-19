import 'dart:async';
import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'dynamic_slippage_service.dart';
import 'pump_fun_price_service.dart';

/// 📊 Resultado del análisis de timing de entrada
class EntryTimingAnalysis {
  EntryTimingAnalysis({
    required this.mint,
    required this.shouldEnter,
    required this.entryScore,
    required this.reason,
    this.momentum,
    this.isRealPump,
    this.volumeSpike,
    this.isDipInUptrend,
    this.recommendedWaitTime,
  });

  final String mint;
  final bool shouldEnter; // true si es buen momento para entrar
  final double entryScore; // 0-100, donde 100 es el mejor momento
  final String reason; // Razón de la decisión
  final double? momentum; // Momentum del precio (0-1, donde 1 es muy alcista)
  final bool? isRealPump; // true si es un pump real (no fake)
  final bool? volumeSpike; // true si hay spike de volumen
  final bool? isDipInUptrend; // true si es un dip controlado en uptrend
  final Duration? recommendedWaitTime; // Tiempo recomendado para esperar antes de entrar

  @override
  String toString() {
    final buffer = StringBuffer();
    buffer.writeln('Entry Timing Score: ${entryScore.toStringAsFixed(1)}/100');
    buffer.writeln('Should Enter: ${shouldEnter ? "✅" : "❌"}');
    buffer.writeln('Reason: $reason');
    if (momentum != null) {
      buffer.writeln('Momentum: ${(momentum! * 100).toStringAsFixed(1)}%');
    }
    if (isRealPump != null) {
      buffer.writeln('Real Pump: ${isRealPump! ? "✅" : "❌"}');
    }
    if (volumeSpike != null) {
      buffer.writeln('Volume Spike: ${volumeSpike! ? "✅" : "❌"}');
    }
    if (isDipInUptrend != null) {
      buffer.writeln('Dip in Uptrend: ${isDipInUptrend! ? "✅" : "❌"}');
    }
    if (recommendedWaitTime != null) {
      buffer.writeln('Wait Time: ${recommendedWaitTime!.inSeconds}s');
    }
    return buffer.toString();
  }
}

/// 📊 Servicio para analizar el mejor timing de entrada
class EntryTimingAnalyzer {
  EntryTimingAnalyzer({
    required DynamicSlippageService slippageService,
  }) : _slippageService = slippageService;

  final DynamicSlippageService _slippageService;

  // Cache de análisis (válido por 10 segundos)
  final Map<String, EntryTimingAnalysis> _analysisCache = {};
  final Map<String, DateTime> _analysisCacheTime = {};
  static const _cacheValidity = Duration(seconds: 10);

  // Cache de volumen reciente (para detectar spikes)
  final Map<String, List<_VolumePoint>> _volumeHistory = {};
  static const _volumeHistoryWindow = Duration(minutes: 10);

  /// 📊 Analizar timing de entrada para un token
  Future<EntryTimingAnalysis> analyzeEntryTiming({
    required String mint,
    required double currentPrice,
    double? currentVolume,
    PumpFunQuote? currentQuote,
  }) async {
    final normalizedMint = mint.trim();
    final now = DateTime.now();

    // Verificar cache
    final cached = _analysisCache[normalizedMint];
    final cachedAt = _analysisCacheTime[normalizedMint];
    if (cached != null &&
        cachedAt != null &&
        now.difference(cachedAt) < _cacheValidity) {
      return cached;
    }

    double entryScore = 50.0; // Score base (neutral)
    final reasons = <String>[];
    double? momentum;
    bool? isRealPump;
    bool? volumeSpike;
    bool? isDipInUptrend;
    Duration? recommendedWaitTime;

    // 1. Analizar momentum (precio subiendo)
    momentum = await _calculateMomentum(normalizedMint, currentPrice);
    if (momentum > 0.6) {
      // Momentum alcista fuerte
      entryScore += 20.0;
      reasons.add('Momentum alcista fuerte (${(momentum * 100).toStringAsFixed(1)}%)');
    } else if (momentum > 0.4) {
      // Momentum alcista moderado
      entryScore += 10.0;
      reasons.add('Momentum alcista moderado');
    } else if (momentum < 0.2) {
      // Momentum bajista
      entryScore -= 15.0;
      reasons.add('Momentum bajista - esperar confirmación');
      recommendedWaitTime = const Duration(seconds: 30);
    }

    // 2. Detectar pumps reales vs fake pumps
    isRealPump = await _detectRealPump(normalizedMint, currentPrice, currentVolume);
    if (isRealPump == true) {
      entryScore += 15.0;
      reasons.add('Pump real detectado (volumen sostenido)');
    } else if (isRealPump == false) {
      entryScore -= 20.0;
      reasons.add('Posible fake pump - esperar confirmación');
      recommendedWaitTime = const Duration(minutes: 2);
    }

    // 3. Analizar volumen en tiempo real
    if (currentVolume != null) {
      volumeSpike = await _detectVolumeSpike(normalizedMint, currentVolume);
      if (volumeSpike == true) {
        entryScore += 10.0;
        reasons.add('Spike de volumen detectado');
      }
    }

    // 4. Detectar dips controlados en uptrend
    isDipInUptrend = await _detectDipInUptrend(normalizedMint, currentPrice);
    if (isDipInUptrend == true) {
      entryScore += 15.0;
      reasons.add('Dip controlado en uptrend - buen momento para entrar');
    }

    // 5. Verificar estabilidad del precio (evitar entrar en picos extremos)
    final priceStability = await _checkPriceStability(normalizedMint, currentPrice);
    if (priceStability < 0.3) {
      // Precio muy volátil/inestable
      entryScore -= 10.0;
      reasons.add('Precio muy volátil - considerar esperar');
      if (recommendedWaitTime == null) {
        recommendedWaitTime = const Duration(seconds: 15);
      }
    }

    // Asegurar que el score esté en rango 0-100
    entryScore = entryScore.clamp(0.0, 100.0);

    // Decidir si debe entrar
    final shouldEnter = entryScore >= 60.0; // Umbral mínimo de 60/100

    final reason = reasons.isEmpty
        ? 'Análisis neutral'
        : reasons.join('; ');

    final analysis = EntryTimingAnalysis(
      mint: normalizedMint,
      shouldEnter: shouldEnter,
      entryScore: entryScore,
      reason: reason,
      momentum: momentum,
      isRealPump: isRealPump,
      volumeSpike: volumeSpike,
      isDipInUptrend: isDipInUptrend,
      recommendedWaitTime: recommendedWaitTime,
    );

    // Guardar en cache
    _analysisCache[normalizedMint] = analysis;
    _analysisCacheTime[normalizedMint] = now;

    return analysis;
  }

  /// 📈 Calcular momentum del precio (0-1, donde 1 es muy alcista)
  Future<double> _calculateMomentum(String mint, double currentPrice) async {
    final priceHistory = _slippageService.getPriceHistory(mint);
    if (priceHistory == null || priceHistory.length < 3) {
      return 0.5; // Sin historial, momentum neutral
    }

    // Calcular tendencia de los últimos puntos
    final recentPrices = priceHistory.take(10).toList();
    if (recentPrices.length < 3) return 0.5;

    // Calcular promedio de cambios porcentuales
    final changes = <double>[];
    for (var i = 1; i < recentPrices.length; i++) {
      if (recentPrices[i - 1] > 0) {
        final change = (recentPrices[i] - recentPrices[i - 1]) / recentPrices[i - 1];
        changes.add(change);
      }
    }

    if (changes.isEmpty) return 0.5;

    // Calcular promedio de cambios (positivo = alcista, negativo = bajista)
    final avgChange = changes.reduce((a, b) => a + b) / changes.length;

    // Normalizar a 0-1 (donde 1 es muy alcista)
    // Consideramos >5% de cambio promedio como muy alcista
    final normalized = ((avgChange / 0.05) + 1.0) / 2.0;
    return normalized.clamp(0.0, 1.0);
  }

  /// 🔍 Detectar si es un pump real (volumen sostenido) vs fake pump (sin volumen)
  Future<bool?> _detectRealPump(
    String mint,
    double currentPrice,
    double? currentVolume,
  ) async {
    if (currentVolume == null) return null; // Sin datos de volumen

    // Obtener historial de volumen
    final volumeHistory = _volumeHistory[mint];
    if (volumeHistory == null || volumeHistory.length < 3) {
      // Registrar volumen actual
      _recordVolume(mint, currentVolume);
      return null; // Necesitamos más datos
    }

    // Calcular promedio de volumen reciente
    final recentVolumes = volumeHistory
        .where((v) =>
            DateTime.now().difference(v.timestamp) < const Duration(minutes: 5))
        .map((v) => v.volume)
        .toList();

    if (recentVolumes.isEmpty) {
      _recordVolume(mint, currentVolume);
      return null;
    }

    final avgVolume = recentVolumes.reduce((a, b) => a + b) / recentVolumes.length;

    // Si el volumen actual es >2x el promedio, es un pump real
    // Si el volumen es bajo pero el precio sube, es un fake pump
    final volumeRatio = currentVolume / avgVolume;
    final priceHistory = _slippageService.getPriceHistory(mint);
    final priceChange = priceHistory != null && priceHistory.length >= 2
        ? (currentPrice - priceHistory[priceHistory.length - 2]) / priceHistory[priceHistory.length - 2]
        : 0.0;

    _recordVolume(mint, currentVolume);

    if (volumeRatio > 2.0 && priceChange > 0.05) {
      // Volumen alto + precio subiendo = pump real
      return true;
    } else if (volumeRatio < 0.5 && priceChange > 0.1) {
      // Volumen bajo + precio subiendo mucho = fake pump
      return false;
    }

    return null; // Inconcluso
  }

  /// 📊 Detectar spike de volumen
  Future<bool> _detectVolumeSpike(String mint, double currentVolume) async {
    final volumeHistory = _volumeHistory[mint];
    if (volumeHistory == null || volumeHistory.length < 5) {
      _recordVolume(mint, currentVolume);
      return false; // Necesitamos más datos
    }

    final recentVolumes = volumeHistory
        .where((v) =>
            DateTime.now().difference(v.timestamp) < const Duration(minutes: 5))
        .map((v) => v.volume)
        .toList();

    if (recentVolumes.length < 3) {
      _recordVolume(mint, currentVolume);
      return false;
    }

    final avgVolume = recentVolumes.reduce((a, b) => a + b) / recentVolumes.length;
    final volumeRatio = currentVolume / avgVolume;

    _recordVolume(mint, currentVolume);

    // Spike si volumen actual es >3x el promedio
    return volumeRatio > 3.0;
  }

  /// 📉 Detectar dips controlados en uptrend
  Future<bool> _detectDipInUptrend(String mint, double currentPrice) async {
    final priceHistory = _slippageService.getPriceHistory(mint);
    if (priceHistory == null || priceHistory.length < 5) {
      return false; // Necesitamos más datos
    }

    // Verificar que hay una tendencia alcista general
    final oldestPrice = priceHistory.first;
    final trendChange = oldestPrice > 0
        ? (currentPrice - oldestPrice) / oldestPrice
        : 0.0;

    if (trendChange < 0.1) {
      // No hay uptrend claro
      return false;
    }

    // Verificar que el precio actual es un dip (menor que el máximo reciente)
    final recentMax = priceHistory.reduce((a, b) => a > b ? a : b);
    final dipPercent = recentMax > 0
        ? (recentMax - currentPrice) / recentMax
        : 0.0;

    // Dip controlado: precio bajó 5-15% desde el máximo, pero está en uptrend
    return dipPercent >= 0.05 && dipPercent <= 0.15;
  }

  /// 📊 Verificar estabilidad del precio
  Future<double> _checkPriceStability(String mint, double currentPrice) async {
    final priceHistory = _slippageService.getPriceHistory(mint);
    if (priceHistory == null || priceHistory.length < 3) {
      return 0.5; // Sin historial, estabilidad neutral
    }

    // Calcular desviación estándar de los cambios porcentuales
    final changes = <double>[];
    for (var i = 1; i < priceHistory.length; i++) {
      if (priceHistory[i - 1] > 0) {
        final change = (priceHistory[i] - priceHistory[i - 1]) / priceHistory[i - 1];
        changes.add(change.abs());
      }
    }

    if (changes.isEmpty) return 0.5;

    final avgChange = changes.reduce((a, b) => a + b) / changes.length;
    final variance = changes
        .map((c) => math.pow(c - avgChange, 2))
        .reduce((a, b) => a + b) / changes.length;
    final stdDev = math.sqrt(variance);

    // Estabilidad = 1 - (stdDev / 0.2), donde 0.2 es considerado muy volátil
    final stability = 1.0 - (stdDev / 0.2).clamp(0.0, 1.0);
    return stability;
  }

  /// 📊 Registrar volumen para tracking
  void _recordVolume(String mint, double volume) {
    final now = DateTime.now();
    final history = _volumeHistory.putIfAbsent(mint, () => <_VolumePoint>[]);

    history.add(_VolumePoint(volume: volume, timestamp: now));

    // Limpiar puntos antiguos
    final cutoff = now.subtract(_volumeHistoryWindow);
    history.removeWhere((point) => point.timestamp.isBefore(cutoff));

    // Limitar tamaño
    if (history.length > 50) {
      history.removeRange(0, history.length - 50);
    }
  }

  /// 📊 Registrar volumen desde una quote de pump.fun
  void recordVolumeFromQuote(String mint, PumpFunQuote quote) {
    // Usar market cap como proxy de volumen (si está disponible)
    if (quote.marketCapSol != null) {
      _recordVolume(mint, quote.marketCapSol!);
    }
  }
}

/// 📊 Punto de volumen con timestamp
class _VolumePoint {
  _VolumePoint({
    required this.volume,
    required this.timestamp,
  });

  final double volume;
  final DateTime timestamp;
}

final entryTimingAnalyzerProvider = Provider<EntryTimingAnalyzer>((ref) {
  return EntryTimingAnalyzer(
    slippageService: ref.read(dynamicSlippageServiceProvider),
  );
});

