import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

class SolPriceService {
  SolPriceService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  Future<double> fetchUsdPrice() async {
    final uri = Uri.https('api.coingecko.com', '/api/v3/simple/price', {
      'ids': 'solana',
      'vs_currencies': 'usd',
    });
    final response = await _client.get(
      uri,
      headers: const {
        'accept': 'application/json',
        'user-agent': 'pump-it-baby/1.0',
      },
    );
    if (response.statusCode != 200) {
      throw Exception('Coingecko error ${response.statusCode}');
    }
    final decoded = jsonDecode(response.body);
    if (decoded is Map &&
        decoded['solana'] is Map &&
        (decoded['solana'] as Map)['usd'] != null) {
      final value = (decoded['solana'] as Map)['usd'];
      if (value is num) {
        return value.toDouble();
      }
      return double.tryParse(value.toString()) ?? 0;
    }
    throw Exception('Respuesta inválida de Coingecko');
  }

  void dispose() {
    _client.close();
  }
}

final solPriceServiceProvider = Provider<SolPriceService>((ref) {
  final service = SolPriceService();
  ref.onDispose(service.dispose);
  return service;
});
