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

  static const _defaultBaseUrl =
      String.fromEnvironment('PUMP_PORTAL_BASE_URL', defaultValue: 'https://pumpportal.fun');

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
      response = await _client.post(
        _tradeLocalUri,
        body: payload,
      );
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
    return base64Encode(response.bodyBytes);
  }

  void dispose() {
    _client.close();
  }
}

final pumpPortalTradeServiceProvider = Provider<PumpPortalTradeService>((ref) {
  final service = PumpPortalTradeService();
  ref.onDispose(service.dispose);
  return service;
});
