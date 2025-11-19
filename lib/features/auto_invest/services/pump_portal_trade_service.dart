import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

class PumpPortalApiException implements Exception {
  PumpPortalApiException(this.message, [this.statusCode, this.responseBody]);

  final String message;
  final int? statusCode;
  final String? responseBody;

  @override
  String toString() =>
      'PumpPortalApiException($statusCode): $message${responseBody == null ? '' : ' -> $responseBody'}';
}

class PumpPortalTradeService {
  PumpPortalTradeService({
    http.Client? client,
    String? baseUrl,
  })  : _client = client ?? http.Client(),
        _baseUrl = baseUrl ?? _defaultBaseUrl;

  final http.Client _client;
  final String _baseUrl;
  // ⚡ Cache de transacciones pre-construidas (evita regenerar en cada ejecución)
  final Map<String, _CachedTx> _txCache = {};

  static const _defaultBaseUrl =
      String.fromEnvironment('PUMP_PORTAL_BASE_URL', defaultValue: 'https://pumpportal.fun');
  // ⚡ Cache válido por 2 segundos (blockhash de Solana expira en ~60s, pero mejor no cachear mucho)
  static const _cacheValidity = Duration(seconds: 2);

  Uri get _tradeLocalUri => Uri.parse('$_baseUrl/api/trade-local');

  Future<String> buildTradeTransaction({
    required String action,
    required String publicKey,
    required String mint,
    required String amount,
    required bool denominatedInSol,
    required double slippagePercent,
    required double priorityFeeSol,
    String pool = 'pump',
    bool? skipPreflight,
    bool? jitoOnly,
  }) async {
    // ⚡ PRECONSTRUCCIÓN: Generar clave única para cache
    final cacheKey = _buildCacheKey(
      action: action,
      publicKey: publicKey,
      mint: mint,
      amount: amount,
      denominatedInSol: denominatedInSol,
      slippagePercent: slippagePercent,
      priorityFeeSol: priorityFeeSol,
      pool: pool,
      skipPreflight: skipPreflight,
      jitoOnly: jitoOnly,
    );

    // ⚡ CACHE DESHABILITADO: Los blockhashes expiran rápido y causan fallos
    // Siempre construir transacciones frescas para asegurar blockhashes válidos
    // final cached = _txCache[cacheKey];
    // if (cached != null && !cached.isExpired) {
    //   return cached.transactionBase64;
    // }

    // Construir transacción fresca (siempre)
    final payload = <String, String>{
      'publicKey': publicKey,
      'action': action,
      'mint': mint,
      'amount': amount,
      'denominatedInSol': denominatedInSol ? 'true' : 'false',
      'slippage': slippagePercent.toString(),
      'priorityFee': priorityFeeSol.toString(),
      'pool': pool,
    };
    if (skipPreflight != null) {
      payload['skipPreflight'] = skipPreflight ? 'true' : 'false';
    }
    if (jitoOnly != null) {
      payload['jitoOnly'] = jitoOnly ? 'true' : 'false';
    }

    http.Response response;
    try {
      response = await _client
          .post(
            _tradeLocalUri,
            body: payload,
          )
          .timeout(
            const Duration(seconds: 15), // ⚡ Timeout para evitar bloqueos
            onTimeout: () {
              throw TimeoutException('Timeout contactando PumpPortal después de 15s');
            },
          );
    } on TimeoutException {
      rethrow;
    } catch (error) {
      throw PumpPortalApiException('No fue posible contactar PumpPortal: $error');
    }

    if (response.statusCode >= 400) {
      final bodySnippet = response.body.isEmpty
          ? null
          : response.body.length > 280
              ? '${response.body.substring(0, 280)}...'
              : response.body;
      throw PumpPortalApiException(
        'PumpPortal devolvió ${response.statusCode}',
        response.statusCode,
        bodySnippet,
      );
    }
    if (response.bodyBytes.isEmpty) {
      throw PumpPortalApiException('PumpPortal devolvió una transacción vacía.');
    }
    
    final transactionBase64 = base64Encode(response.bodyBytes);
    
    // ⚡ Guardar en cache para reutilización
    _txCache[cacheKey] = _CachedTx(
      transactionBase64: transactionBase64,
      cachedAt: DateTime.now(),
    );
    
    // Limpiar cache expirado periódicamente
    _cleanExpiredCache();
    
    return transactionBase64;
  }

  // ⚡ Generar clave única para cache basada en parámetros
  String _buildCacheKey({
    required String action,
    required String publicKey,
    required String mint,
    required String amount,
    required bool denominatedInSol,
    required double slippagePercent,
    required double priorityFeeSol,
    required String pool,
    bool? skipPreflight,
    bool? jitoOnly,
  }) {
    return '$action|$publicKey|$mint|$amount|$denominatedInSol|'
        '${slippagePercent.toStringAsFixed(2)}|'
        '${priorityFeeSol.toStringAsFixed(6)}|$pool|'
        '${skipPreflight ?? false}|${jitoOnly ?? false}';
  }

  // ⚡ Limpiar entradas expiradas del cache
  void _cleanExpiredCache() {
    _txCache.removeWhere((key, value) => value.isExpired);
  }

  void dispose() {
    _client.close();
    _txCache.clear();
  }
}

// ⚡ Cache para transacciones pre-construidas
class _CachedTx {
  _CachedTx({
    required this.transactionBase64,
    required this.cachedAt,
  });

  final String transactionBase64;
  final DateTime cachedAt;

  bool get isExpired =>
      DateTime.now().difference(cachedAt) > PumpPortalTradeService._cacheValidity;
}

final pumpPortalTradeServiceProvider = Provider<PumpPortalTradeService>((ref) {
  final service = PumpPortalTradeService();
  ref.onDispose(service.dispose);
  return service;
});
