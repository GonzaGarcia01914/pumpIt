import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../models/ai_insight.dart';
import '../models/featured_coin.dart';

abstract class AiInsightService {
  Future<AiInsight> buildInsight(List<FeaturedCoin> coins);
}

class RuleBasedInsightService implements AiInsightService {
  const RuleBasedInsightService();

  @override
  Future<AiInsight> buildInsight(List<FeaturedCoin> coins) async {
    final buffer = StringBuffer();
    if (coins.isEmpty) {
      buffer.writeln(
          'No hay memecoins destacadas con MC mayor al umbral configurado.');
    } else {
      final leaders = coins.take(3).toList();
      buffer.writeln(
          'Top ${leaders.length} en USD MC: ${leaders.map((c) => c.symbol).join(', ')}.');

      final avg = leaders.map((c) => c.usdMarketCap).fold<double>(
            0,
            (prev, element) => prev + element,
          ) /
          leaders.length;
      buffer.writeln(
          'Promedio de MC USD en el podio: ${avg.toStringAsFixed(0)} USD.');

      final fresh = coins
          .where((coin) =>
              DateTime.now().difference(coin.createdAt).inHours < 1)
          .length;
      if (fresh > 0) {
        buffer.writeln('$fresh tokens aparecieron en la ultima hora.');
      }
    }

    return AiInsight(
      summary: buffer.toString().trim(),
      generatedAt: DateTime.now(),
      usedGenerativeModel: false,
    );
  }
}

class OpenAiInsightService implements AiInsightService {
  OpenAiInsightService({
    required this.apiKey,
    this.model = 'gpt-4o-mini',
    http.Client? httpClient,
    Uri? endpoint,
  })  : _httpClient = httpClient ?? http.Client(),
        _endpoint = endpoint ?? Uri.https('api.openai.com', '/v1/chat/completions');

  final String apiKey;
  final String model;
  final http.Client _httpClient;
  final Uri _endpoint;

  @override
  Future<AiInsight> buildInsight(List<FeaturedCoin> coins) async {
    if (coins.isEmpty) {
      return AiInsight(
        summary:
            'No hay datos suficientes para que la IA genere un resumen en este momento.',
        generatedAt: DateTime.now(),
        usedGenerativeModel: true,
        provider: 'OpenAI',
      );
    }

    final payload = {
      'model': model,
      'temperature': 0.3,
      'messages': [
        {
          'role': 'system',
          'content':
              'Eres un analista cripto que lee datos sin procesar y devuelve conclusiones accionables y concretas en espanol.'
        },
        {
          'role': 'user',
          'content':
              'Resume en 3 vinetas lo mas relevante de estas memecoins featured de pump.fun con market cap mayor a 15k USD. Incluye tendencias de momentum, actividad social y alertas de riesgo cuando apliquen.\n${_serializeCoins(coins)}'
        }
      ]
    };

    final response = await _httpClient.post(
      _endpoint,
      headers: {
        HttpHeaders.contentTypeHeader: 'application/json',
        HttpHeaders.authorizationHeader: 'Bearer $apiKey',
      },
      body: jsonEncode(payload),
    );

    if (response.statusCode >= 400) {
      throw Exception(
          'OpenAI respondio ${response.statusCode}: ${response.body}');
    }

    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    final choices = decoded['choices'] as List<dynamic>? ?? [];
    String? content;
    if (choices.isNotEmpty) {
      final choice = choices.first;
      if (choice is Map<String, dynamic>) {
        final message = choice['message'];
        if (message is Map<String, dynamic>) {
          content = message['content']?.toString();
        } else if (message is String) {
          content = message;
        }
      }
    }

    if (content == null || content.trim().isEmpty) {
      throw Exception('OpenAI no devolvio texto utilizable.');
    }

    return AiInsight(
      summary: content.trim(),
      generatedAt: DateTime.now(),
      usedGenerativeModel: true,
      provider: 'OpenAI',
    );
  }

  static String _serializeCoins(List<FeaturedCoin> coins) {
    final buffer = StringBuffer();
    for (final coin in coins) {
      buffer.writeln(
          '${coin.symbol}: ${coin.usdMarketCap.toStringAsFixed(0)} USD MC, creado ${coin.createdAt.toIso8601String()}, replies=${coin.replyCount}, live=${coin.isCurrentlyLive}');
    }
    return buffer.toString();
  }

  void close() {
    _httpClient.close();
  }
}
