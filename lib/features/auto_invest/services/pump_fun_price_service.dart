import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

class PumpFunPriceException implements Exception {
  PumpFunPriceException(this.message, [this.statusCode, this.responseSnippet]);

  final String message;
  final int? statusCode;
  final String? responseSnippet;

  @override
  String toString() {
    final codePart = statusCode == null ? '' : ' (status $statusCode)';
    final bodyPart = responseSnippet == null ? '' : ' -> $responseSnippet';
    return 'PumpFunPriceException$codePart: $message$bodyPart';
  }
}

class PumpFunQuote {
  const PumpFunQuote({
    required this.priceSol,
    required this.marketCapSol,
    required this.liquiditySol,
    required this.fetchedAt,
  });

  final double priceSol;
  final double? marketCapSol;
  final double? liquiditySol;
  final DateTime fetchedAt;

  static double? _maybeDouble(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString());
  }

  factory PumpFunQuote.fromJson(
    Map<String, dynamic> json, {
    required DateTime fetchedAt,
  }) {
    final priceCandidates = <double?>[
      _maybeDouble(json['price_sol']),
      _maybeDouble(json['priceSol']),
      _maybeDouble(json['price']),
    ];

    final bondingCurve = json['bonding_curve'] ?? json['bondingCurve'];
    if (bondingCurve is Map<String, dynamic>) {
      priceCandidates.addAll([
        _maybeDouble(bondingCurve['price_sol']),
        _maybeDouble(bondingCurve['priceSol']),
        _maybeDouble(bondingCurve['price']),
      ]);
    }

    final marketCapCandidates = <double?>[
      _maybeDouble(json['market_cap_sol']),
      _maybeDouble(json['marketCapSol']),
      _maybeDouble(json['market_cap']),
      _maybeDouble(json['marketCap']),
    ];

    final liquidityCandidates = <double?>[
      _maybeDouble(json['liquidity_sol']),
      _maybeDouble(json['liquiditySol']),
      _maybeDouble(json['liquidity']),
    ];

    final resolvedMarketCap = marketCapCandidates.firstWhere(
      (value) => value != null,
      orElse: () => null,
    );
    var resolvedPrice = priceCandidates.firstWhere(
      (value) => value != null && value > 0,
      orElse: () => null,
    );

    const totalSupply = 1000000000; // 1B tokens on pump.fun bonding curve
    if ((resolvedPrice == null || resolvedPrice <= 0) &&
        resolvedMarketCap != null &&
        resolvedMarketCap > 0) {
      resolvedPrice = resolvedMarketCap / totalSupply;
    }

    return PumpFunQuote(
      priceSol: resolvedPrice ?? 0,
      marketCapSol: resolvedMarketCap,
      liquiditySol: liquidityCandidates.firstWhere(
        (value) => value != null,
        orElse: () => null,
      ),
      fetchedAt: fetchedAt,
    );
  }
}

class PumpFunPriceService {
  PumpFunPriceService({http.Client? client, String? host, Duration? cacheTtl})
    : _client = client ?? http.Client(),
      _host = host ?? 'frontend-api-v3.pump.fun',
      _cacheTtl = cacheTtl ?? const Duration(seconds: 45);

  final http.Client _client;
  final String _host;
  final Duration _cacheTtl;
  final Map<String, PumpFunQuote> _cache = {};
  final Map<String, DateTime> _cacheHit = {};

  Future<PumpFunQuote> fetchQuote(String mint) async {
    final normalizedMint = mint.trim();
    final now = DateTime.now();
    final cached = _cache[normalizedMint];
    final cachedAt = _cacheHit[normalizedMint];
    if (cached != null &&
        cachedAt != null &&
        now.difference(cachedAt) <= _cacheTtl) {
      return cached;
    }

    final uri = Uri.https(_host, '/coins/$normalizedMint');
    http.Response response;
    try {
      response = await _client.get(
        uri,
        headers: {
          'accept': 'application/json',
          'user-agent': 'pump-it-baby/1.0',
        },
      );
    } catch (error) {
      throw PumpFunPriceException('No se pudo contactar pump.fun: $error');
    }

    if (response.statusCode >= 400) {
      final body = response.body;
      final snippet = body.isEmpty
          ? null
          : body.length > 280
          ? '${body.substring(0, 280)}...'
          : body;
      throw PumpFunPriceException(
        'pump.fun devolvió ${response.statusCode}',
        response.statusCode,
        snippet,
      );
    }

    if (response.bodyBytes.isEmpty) {
      throw PumpFunPriceException('pump.fun respondió sin contenido.');
    }

    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    if (decoded is! Map<String, dynamic>) {
      throw PumpFunPriceException('Respuesta inválida de pump.fun.');
    }

    final quote = PumpFunQuote.fromJson(decoded, fetchedAt: now);
    _cache[normalizedMint] = quote;
    _cacheHit[normalizedMint] = now;
    return quote;
  }

  void dispose() {
    _client.close();
  }
}

final pumpFunPriceServiceProvider = Provider<PumpFunPriceService>((ref) {
  final service = PumpFunPriceService();
  ref.onDispose(service.dispose);
  return service;
});
