import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

const _defaultJupiterBase =
    String.fromEnvironment('JUPITER_BASE_URL', defaultValue: 'https://quote-api.jup.ag');
const _fallbackJupiterBase = 'https://api.jup.ag/api';
const _defaultSlippageBps =
    int.fromEnvironment('JUPITER_DEFAULT_SLIPPAGE_BPS', defaultValue: 300);
const _defaultPriorityFeeLamports =
    int.fromEnvironment('JUPITER_PRIORITY_FEE_LAMPORTS', defaultValue: 0);
const _defaultConcurrency =
    int.fromEnvironment('JUPITER_MAX_CONCURRENCY', defaultValue: 4);
const _maxRetries =
    int.fromEnvironment('JUPITER_MAX_RETRIES', defaultValue: 3);
const _baseRetryDelay = Duration(milliseconds: 250);

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
  JupiterSwapService({
    http.Client? client,
    String? baseUrl,
    int? maxConcurrentRequests,
  })  : _client = client ?? http.Client(),
        _primaryBase = baseUrl ?? _defaultJupiterBase,
        _limiter = _AsyncLimiter(maxConcurrentRequests ?? _defaultConcurrency);

  final http.Client _client;
  final String _primaryBase;
  final _AsyncLimiter _limiter;
  final _random = Random();

  List<String> get _baseCandidates {
    if (_primaryBase == _fallbackJupiterBase) {
      return [_primaryBase];
    }
    return [_primaryBase, _fallbackJupiterBase];
  }

  static const solMint = 'So11111111111111111111111111111111111111112';

  Future<JupiterQuote> fetchQuote({
    required String inputMint,
    required String outputMint,
    required int amountLamports,
    int? slippageBps,
    int? priorityFeeLamports,
  }) {
    return _runWithFallback((baseUrl) async {
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

      final uri = Uri.parse('$baseUrl/v6/quote').replace(queryParameters: params);
      final response = await _limiter.run(
        () => _withRetries(
          () => _client.get(
            uri,
            headers: const {
              'accept': 'application/json',
              'origin': 'https://jup.ag',
              'user-agent': 'pump-it-baby/1.0',
            },
          ),
        ),
      );
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
    });
  }

  Future<JupiterSwapResponse> swap({
    required Map<String, dynamic> route,
    required String userPublicKey,
    bool wrapAndUnwrapSol = true,
    int? priorityFeeLamports,
  }) {
    return _runWithFallback((baseUrl) async {
      final uri = Uri.parse('$baseUrl/v6/swap');
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
      final response = await _limiter.run(
        () => _withRetries(
          () => _client.post(
            uri,
            headers: const {
              'Content-Type': 'application/json',
              'accept': 'application/json',
              'origin': 'https://jup.ag',
              'user-agent': 'pump-it-baby/1.0',
            },
            body: jsonEncode(body),
          ),
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
    });
  }

  Future<T> _runWithFallback<T>(
    Future<T> Function(String baseUrl) operation,
  ) async {
    Object? lastError;
    for (final base in _baseCandidates) {
      try {
        return await operation(base);
      } on SocketException catch (error) {
        lastError = error;
        if (!_isHostLookupError(error)) {
          rethrow;
        }
      } on http.ClientException catch (error) {
        if (_isClientHostLookupError(error)) {
          lastError = error;
        } else {
          rethrow;
        }
      }
    }
    throw Exception('Jupiter no disponible: $lastError');
  }

  Future<http.Response> _withRetries(
    Future<http.Response> Function() task,
  ) async {
    for (var attempt = 0; attempt <= _maxRetries; attempt++) {
      try {
        return await task();
      } on SocketException catch (error) {
        if (attempt == _maxRetries) {
          rethrow;
        }
        await Future.delayed(_computeDelay(attempt));
        if (!_isHostLookupError(error)) {
          continue;
        }
      } on http.ClientException catch (error) {
        if (!_isClientHostLookupError(error) || attempt == _maxRetries) {
          rethrow;
        }
        await Future.delayed(_computeDelay(attempt));
      }
    }
    throw Exception('Error comunicando con Jupiter.');
  }

  Duration _computeDelay(int attempt) {
    final multiplier = 1 << attempt;
    final jitterMs = _random.nextInt(_baseRetryDelay.inMilliseconds + 1);
    final totalMs = (_baseRetryDelay.inMilliseconds * multiplier) + jitterMs;
    return Duration(milliseconds: totalMs);
  }

  bool _isHostLookupError(SocketException error) {
    final message = error.message.toLowerCase();
    final osMessage = error.osError?.message.toLowerCase() ?? '';
    return message.contains('failed host lookup') ||
        osMessage.contains('failed host lookup') ||
        osMessage.contains('unknown host');
  }

  bool _isClientHostLookupError(http.ClientException error) {
    final message = error.message.toLowerCase();
    return message.contains('failed host lookup') ||
        message.contains('host lookup');
  }

  void dispose() {
    _client.close();
  }
}

class _AsyncLimiter {
  _AsyncLimiter(this._maxConcurrent);

  final int _maxConcurrent;
  int _active = 0;
  final Queue<Completer<void>> _queue = Queue();

  Future<T> run<T>(Future<T> Function() action) async {
    await _acquire();
    try {
      return await action();
    } finally {
      _release();
    }
  }

  Future<void> _acquire() {
    if (_active < _maxConcurrent) {
      _active++;
      return Future.value();
    }
    final completer = Completer<void>();
    _queue.add(completer);
    return completer.future;
  }

  void _release() {
    if (_queue.isNotEmpty) {
      final next = _queue.removeFirst();
      next.complete();
    } else {
      if (_active > 0) {
        _active--;
      }
    }
  }
}

final jupiterSwapServiceProvider = Provider<JupiterSwapService>((ref) {
  final service = JupiterSwapService();
  ref.onDispose(service.dispose);
  return service;
});
