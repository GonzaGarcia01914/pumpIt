import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/simulation_models.dart';
import '../models/position.dart';
import '../controller/auto_invest_notifier.dart';

class SimulationAnalysisService {
  SimulationAnalysisService({http.Client? client})
    : _client = client ?? http.Client();

  final http.Client _client;
  static const _apiKey = String.fromEnvironment(
    'OPENAI_API_KEY',
    defaultValue: '',
  );

  bool get isEnabled => _apiKey.isNotEmpty;

  Future<String> summarize(List<SimulationRun> runs) async {
    if (!isEnabled) {
      throw Exception('OPENAI_API_KEY no definido (usar --dart-define).');
    }
    final summary = jsonEncode(runs.map((r) => r.toSummaryJson()).toList());
    return _postCompletion(
      systemPrompt:
          'Eres un analista cuantitativo que revisa simulaciones de trading y sugiere mejoras claras y accionables. Siempre responde usando secciones POSITIVAS:, NEGATIVAS:, OPORTUNIDADES:, cada una con viñetas. Sin texto fuera de esas secciones.',
      userPrompt:
          'Analiza estas simulaciones de auto-invest y resume tendencias, riesgos y ajustes sugeridos. Usa SOLO el formato requerido.\n$summary',
    );
  }

  Future<String> summarizeClosedTrades({
    required List<ClosedPosition> trades,
    required AutoInvestState state,
  }) async {
    if (!isEnabled) {
      throw Exception('OPENAI_API_KEY no definido (usar --dart-define).');
    }
    final payload = trades.take(50).map((trade) {
      return {
        'symbol': trade.symbol,
        'executionMode': trade.executionMode.name,
        'entrySol': trade.entrySol,
        'exitSol': trade.exitSol,
        'pnlSol': trade.pnlSol,
        'pnlPercent': trade.pnlPercent,
        'openedAt': trade.openedAt.toIso8601String(),
        'closedAt': trade.closedAt.toIso8601String(),
        'reason': trade.closeReason?.name ?? 'manual',
        'entryFeeSol': trade.entryFeeSol,
        'exitFeeSol': trade.exitFeeSol,
        'netPnlSol': trade.netPnlSol,
      };
    }).toList();
    final summaryJson = jsonEncode(payload);
    final aggregateJson = jsonEncode({
      'totalPositions': payload.length,
      'grossPnlSol': trades.fold<double>(0, (sum, trade) => sum + trade.pnlSol),
      'netPnlSol': trades.fold<double>(
        0,
        (sum, trade) =>
            sum +
            (trade.netPnlSol ??
                (trade.pnlSol -
                    (trade.entryFeeSol ?? 0) -
                    (trade.exitFeeSol ?? 0))),
      ),
      'entryFeesSol': trades.fold<double>(
        0,
        (sum, trade) => sum + (trade.entryFeeSol ?? 0),
      ),
      'exitFeesSol': trades.fold<double>(
        0,
        (sum, trade) => sum + (trade.exitFeeSol ?? 0),
      ),
      'winRatePercent': trades.isEmpty
          ? 0
          : (trades.where((trade) => trade.pnlSol >= 0).length /
                    trades.length) *
                100,
      'avgHoldMinutes': trades.isEmpty
          ? 0
          : trades.fold<double>(
                  0,
                  (sum, trade) =>
                      sum +
                      trade.closedAt
                          .difference(trade.openedAt)
                          .inMinutes
                          .abs()
                          .toDouble(),
                ) /
                trades.length,
    });
    final stateJson = jsonEncode({
      'minMarketCap': state.minMarketCap,
      'maxMarketCap': state.maxMarketCap,
      'minVolume24h': state.minVolume24h,
      'maxVolume24h': state.maxVolume24h,
      'stopLossPercent': state.stopLossPercent,
      'takeProfitPercent': state.takeProfitPercent,
      'totalBudgetSol': state.totalBudgetSol,
      'perCoinBudgetSol': state.perCoinBudgetSol,
      'executionMode': state.executionMode.name,
      'pumpSlippagePercent': state.pumpSlippagePercent,
      'pumpPriorityFeeSol': state.pumpPriorityFeeSol,
      'pumpPool': state.pumpPool,
    });
    final userPrompt =
        '''Analiza estas posiciones reales cerradas del bot de auto-invest (hasta 50 mas recientes) y encuentra patrones de mercado o parametricos que expliquen ganancias o perdidas. Usa solo el formato indicado y referencia los parametros actuales del bot para proponer ajustes.\nPOSITIVAS:\nNEGATIVAS:\nOPORTUNIDADES:\nDatos de posiciones:\n$summaryJson\nMetricas agregadas:\n$aggregateJson\nParametros actuales:\n$stateJson''';
    return _postCompletion(
      systemPrompt:
          'Eres un analista cuantitativo que evalua resultados reales de trading, buscando patrones comunes entre operaciones ganadoras y perdedoras y proponiendo ajustes claros a la configuracion del bot. RESPONDE SIEMPRE con secciones: POSITIVAS:, NEGATIVAS:, OPORTUNIDADES:, cada una con vinetas breves. No anadas texto fuera de esas secciones. Siempre menciona insights concretos (por ejemplo, market cap, volumen, ejecucion, etc.) y sugiere ajustes especificos sobre los parametros actuales del bot cuando corresponda.',
      userPrompt: userPrompt,
    );
  }

  Future<String> _postCompletion({
    required String systemPrompt,
    required String userPrompt,
  }) async {
    final body = jsonEncode({
      'model': 'gpt-4o-mini',
      'temperature': 0.2,
      'messages': [
        {'role': 'system', 'content': systemPrompt},
        {'role': 'user', 'content': userPrompt},
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
      throw Exception(
        'OpenAI respondió ${response.statusCode}: ${response.body}',
      );
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

final simulationAnalysisServiceProvider = Provider<SimulationAnalysisService>((
  ref,
) {
  final service = SimulationAnalysisService();
  ref.onDispose(service.dispose);
  return service;
});
