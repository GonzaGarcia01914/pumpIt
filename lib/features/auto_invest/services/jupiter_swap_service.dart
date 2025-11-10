import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

const _defaultJupiterBase =
    String.fromEnvironment('JUPITER_BASE_URL', defaultValue: 'https://quote-api.jup.ag');
const _defaultSlippageBps =
    int.fromEnvironment('JUPITER_DEFAULT_SLIPPAGE_BPS', defaultValue: 300);
const _defaultPriorityFeeLamports =
    int.fromEnvironment('JUPITER_PRIORITY_FEE_LAMPORTS', defaultValue: 0);

class JupiterQuote {
  const JupiterQuote({
    required this.route,
    required this.inAmountLamports,
    required this.outAmount,
  });

  final Map<String, dynamic> route;
  final int inAmountLamports;
  final String outAmount;
}

class JupiterSwapResponse {
  const JupiterSwapResponse({
    required this.swapTransaction,
    this.lastValidBlockHeight,
  });

  final String swapTransaction;
  final int? lastValidBlockHeight;
}

class JupiterSwapService {
  JupiterSwapService({http.Client? client, String? baseUrl})
      : _client = client ?? http.Client(),
        _baseUrl = baseUrl ?? _defaultJupiterBase;

  final http.Client _client;
  final String _baseUrl;

  static const solMint = 'So11111111111111111111111111111111111111112';

  Future<JupiterQuote> fetchQuote({
    required String inputMint,
    required String outputMint,
    required int amountLamports,
    int? slippageBps,
    int? priorityFeeLamports,
  }) async {
    final params = {
      'inputMint': inputMint,
      'outputMint': outputMint,
      'amount': amountLamports.toString(),
      'slippageBps': (slippageBps ?? _defaultSlippageBps).toString(),
      'onlyDirectRoutes': 'false',
    };
    if ((priorityFeeLamports ?? _defaultPriorityFeeLamports) > 0) {
      params['prioritizationFeeLamports'] =
          (priorityFeeLamports ?? _defaultPriorityFeeLamports).toString();
    }

    final uri = Uri.parse('$_baseUrl/v6/quote').replace(queryParameters: params);
    final response = await _withRetries(() => _client.get(uri));
    if (response.statusCode != 200) {
      throw Exception('Jupiter quote error ${response.statusCode}: ${response.body}');
    }
    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    final routes = decoded['data'] as List<dynamic>? ?? [];
    if (routes.isEmpty) {
      throw Exception('Jupiter no encontró rutas para el par solicitado.');
    }
    final route = routes.first as Map<String, dynamic>;
    return JupiterQuote(
      route: route,
      inAmountLamports: amountLamports,
      outAmount: route['outAmount']?.toString() ?? '0',
    );
  }

  Future<JupiterSwapResponse> swap({
    required Map<String, dynamic> route,
    required String userPublicKey,
    bool wrapAndUnwrapSol = true,
    int? priorityFeeLamports,
  }) async {
    final uri = Uri.parse('$_baseUrl/v6/swap');
    final body = {
      'userPublicKey': userPublicKey,
      'wrapAndUnwrapSol': wrapAndUnwrapSol,
      'route': route,
      'useSharedAccounts': true,
    };
    if ((priorityFeeLamports ?? _defaultPriorityFeeLamports) > 0) {
      body['prioritizationFeeLamports'] =
          priorityFeeLamports ?? _defaultPriorityFeeLamports;
    }
    final response = await _withRetries(
      () => _client.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(body),
      ),
    );
    if (response.statusCode != 200) {
      throw Exception('Jupiter swap error ${response.statusCode}: ${response.body}');
    }
    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    final swapTx = decoded['swapTransaction']?.toString();
    if (swapTx == null || swapTx.isEmpty) {
      throw Exception('Jupiter no devolvió la transacción a firmar.');
    }
    return JupiterSwapResponse(
      swapTransaction: swapTx,
      lastValidBlockHeight: decoded['lastValidBlockHeight'] as int?,
    );
  }

  Future<http.Response> _withRetries(
    Future<http.Response> Function() task, {
    int retries = 2,
    Duration delay = const Duration(milliseconds: 250),
  }) async {
    Object? lastError;
    for (var attempt = 0; attempt <= retries; attempt++) {
      try {
        return await task();
      } catch (error) {
        lastError = error;
        await Future.delayed(delay * (attempt + 1));
      }
    }
    throw Exception('Error comunicando con Jupiter: $lastError');
  }

  void dispose() {
    _client.close();
  }
}

final jupiterSwapServiceProvider = Provider<JupiterSwapService>((ref) {
  final service = JupiterSwapService();
  ref.onDispose(service.dispose);
  return service;
});
