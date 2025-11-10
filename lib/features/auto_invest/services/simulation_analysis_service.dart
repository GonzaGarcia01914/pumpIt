import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/simulation_models.dart';

class SimulationAnalysisService {
  SimulationAnalysisService({http.Client? client})
      : _client = client ?? http.Client();

  final http.Client _client;
  static const _apiKey = String.fromEnvironment('OPENAI_API_KEY', defaultValue: '');

  bool get isEnabled => _apiKey.isNotEmpty;

  Future<String> summarize(List<SimulationRun> runs) async {
    if (!isEnabled) {
      throw Exception('OPENAI_API_KEY no definido (usar --dart-define).');
    }
    final summary = jsonEncode(runs.map((r) => r.toSummaryJson()).toList());
    final body = jsonEncode({
      'model': 'gpt-4o-mini',
      'temperature': 0.2,
      'messages': [
        {
          'role': 'system',
          'content':
              'Eres un analista cuantitativo que revisa simulaciones de trading y sugiere mejoras claras y accionables.',
        },
        {
          'role': 'user',
          'content':
              'Analiza estas simulaciones de auto-invest y resume tendencias, riesgos y ajustes sugeridos:\n$summary',
        },
      ],
    });

    final response = await _client.post(
      Uri.https('api.openai.com', '/v1/chat/completions'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $_apiKey',
      },
      body: body,
    );

    if (response.statusCode >= 400) {
      throw Exception('OpenAI respondió ${response.statusCode}: ${response.body}');
    }

    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    final choices = decoded['choices'] as List<dynamic>? ?? [];
    if (choices.isEmpty) {
      throw Exception('OpenAI no devolvió contenido.');
    }
    final message = choices.first['message']?['content']?.toString();
    if (message == null) {
      throw Exception('OpenAI devolvió una respuesta vacía.');
    }
    return message.trim();
  }

  void dispose() {
    _client.close();
  }
}

final simulationAnalysisServiceProvider =
    Provider<SimulationAnalysisService>((ref) {
  final service = SimulationAnalysisService();
  ref.onDispose(service.dispose);
  return service;
});
