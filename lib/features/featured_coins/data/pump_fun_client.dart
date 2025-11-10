import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/featured_coin.dart';

class PumpFunApiException implements Exception {
  PumpFunApiException(this.message, [this.statusCode]);

  final String message;
  final int? statusCode;

  @override
  String toString() =>
      'PumpFunApiException(statusCode: $statusCode, message: $message)';
}

class PumpFunClient {
  PumpFunClient({
    http.Client? httpClient,
    this.host = 'frontend-api-v3.pump.fun',
  }) : _httpClient = httpClient ?? http.Client();

  final http.Client _httpClient;
  final String host;

  Future<List<FeaturedCoin>> fetchFeaturedCoins({
    int offset = 0,
    int limit = 60,
    bool includeNsfw = false,
    double? marketCapMin,
    double? marketCapMax,
    double? volume24hMin,
    double? volume24hMax,
  }) async {
    final query = <String, String>{
      'offset': offset.toString(),
      'limit': limit.toString(),
      'includeNsfw': includeNsfw.toString(),
    };

    void maybeAdd(String key, double? value) {
      if (value != null) {
        query[key] = value.toString();
      }
    }

    maybeAdd('marketCapMin', marketCapMin);
    maybeAdd('marketCapMax', marketCapMax);
    maybeAdd('volume24hMin', volume24hMin);
    maybeAdd('volume24hMax', volume24hMax);

    final uri = Uri.https(host, '/coins/for-you', query);
    final response = await _httpClient.get(uri, headers: {
      'accept': 'application/json',
    });

    if (response.statusCode != 200) {
      throw PumpFunApiException(
        'Pump.fun devolvio ${response.statusCode}',
        response.statusCode,
      );
    }

    try {
      return FeaturedCoin.listFromJson(utf8.decode(response.bodyBytes));
    } catch (error) {
      throw PumpFunApiException('No se pudo leer la respuesta: $error');
    }
  }

  void close() {
    _httpClient.close();
  }
}
