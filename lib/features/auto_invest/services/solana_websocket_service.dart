import 'dart:async';
import 'dart:convert';

import 'package:web_socket_channel/web_socket_channel.dart';

/// ⚡ Servicio WebSocket para confirmaciones y eventos en tiempo real
/// Usa WebSockets para todo lo crítico en latencia del bot
class SolanaWebSocketService {
  SolanaWebSocketService({
    String? apiKey,
  })  : _wsUrl = _buildWebSocketUrl(apiKey);

  final String _wsUrl;

  // ⚡ WebSocket connections (uno por tipo de suscripción)
  WebSocketChannel? _signatureSubscription;
  WebSocketChannel? _logsSubscription;
  WebSocketChannel? _accountSubscription;

  // ⚡ Callbacks para eventos
  final Map<String, Completer<void>> _pendingConfirmations = {};
  final Map<String, Function(Map<String, dynamic>)> _signatureCallbacks = {};
  final Map<String, Function(Map<String, dynamic>)> _logsCallbacks = {};
  final Map<String, Function(Map<String, dynamic>)> _accountCallbacks = {};

  // ⚡ Construir URL de WebSocket de Helius
  static String _buildWebSocketUrl(String? apiKey) {
    const baseUrl = 'wss://mainnet.helius-rpc.com';
    if (apiKey != null && apiKey.isNotEmpty) {
      return '$baseUrl/?api-key=$apiKey';
    }
    // Fallback sin API key (puede tener rate limits)
    return baseUrl;
  }

  /// ⚡ Suscribirse a confirmación de transacción (reemplaza polling)
  /// Retorna inmediatamente cuando la tx es confirmada
  Future<void> subscribeToSignature(
    String signature, {
    String? commitment,
  }) async {
    if (_pendingConfirmations.containsKey(signature)) {
      return _pendingConfirmations[signature]!.future;
    }

    final completer = Completer<void>();
    _pendingConfirmations[signature] = completer;

    // Si no hay conexión WebSocket activa, crear una
    if (_signatureSubscription == null) {
      await _connectSignatureSubscription();
    }

    // Enviar suscripción
    final subscriptionId = _generateSubscriptionId();
    final message = {
      'jsonrpc': '2.0',
      'id': subscriptionId,
      'method': 'signatureSubscribe',
      'params': [
        signature,
        {
          'commitment': commitment ?? 'confirmed',
        }
      ],
    };

    _signatureCallbacks[subscriptionId] = (result) {
      final value = result['value'];
      if (value != null) {
        final err = value['err'];
        if (err == null) {
          // ⚡ Confirmación exitosa - resolver inmediatamente
          completer.complete();
          _pendingConfirmations.remove(signature);
          _signatureCallbacks.remove(subscriptionId);
        } else {
          // Error en la transacción
          completer.completeError(Exception('Transacción falló: $err'));
          _pendingConfirmations.remove(signature);
          _signatureCallbacks.remove(subscriptionId);
        }
      }
    };

    try {
      _signatureSubscription?.sink.add(jsonEncode(message));
    } catch (e) {
      _pendingConfirmations.remove(signature);
      _signatureCallbacks.remove(subscriptionId);
      rethrow;
    }

    return completer.future;
  }

  /// ⚡ Suscribirse a logs de un programa (pump.fun, Jupiter, etc.)
  /// Detecta eventos antes que polling HTTP
  Stream<Map<String, dynamic>> subscribeToProgramLogs(
    String programId, {
    String? commitment,
  }) async* {
    if (_logsSubscription == null) {
      await _connectLogsSubscription();
    }

    final subscriptionId = _generateSubscriptionId();
    final message = {
      'jsonrpc': '2.0',
      'id': subscriptionId,
      'method': 'logsSubscribe',
      'params': [
        {
          'mentions': [programId],
        },
        {
          'commitment': commitment ?? 'confirmed',
        }
      ],
    };

    final controller = StreamController<Map<String, dynamic>>();

    _logsCallbacks[subscriptionId] = (result) {
      controller.add(result);
    };

    try {
      _logsSubscription?.sink.add(jsonEncode(message));
      yield* controller.stream;
    } finally {
      _logsCallbacks.remove(subscriptionId);
      await controller.close();
    }
  }

  /// ⚡ Suscribirse a cambios en una cuenta (pool, wallet, etc.)
  /// Permite reaccionar rápido a cambios de precio/liquidez
  Stream<Map<String, dynamic>> subscribeToAccount(
    String accountPubkey, {
    String? commitment,
  }) async* {
    if (_accountSubscription == null) {
      await _connectAccountSubscription();
    }

    final subscriptionId = _generateSubscriptionId();
    final message = {
      'jsonrpc': '2.0',
      'id': subscriptionId,
      'method': 'accountSubscribe',
      'params': [
        accountPubkey,
        {
          'encoding': 'jsonParsed',
          'commitment': commitment ?? 'confirmed',
        }
      ],
    };

    final controller = StreamController<Map<String, dynamic>>();

    _accountCallbacks[subscriptionId] = (result) {
      controller.add(result);
    };

    try {
      _accountSubscription?.sink.add(jsonEncode(message));
      yield* controller.stream;
    } finally {
      _accountCallbacks.remove(subscriptionId);
      await controller.close();
    }
  }

  // ⚡ Conectar WebSocket para suscripciones de firmas
  Future<void> _connectSignatureSubscription() async {
    try {
      _signatureSubscription = WebSocketChannel.connect(Uri.parse(_wsUrl));
      _signatureSubscription!.stream.listen(
        (data) {
          final decoded = jsonDecode(data as String) as Map<String, dynamic>;
          final id = decoded['id']?.toString();
          if (id != null && _signatureCallbacks.containsKey(id)) {
            _signatureCallbacks[id]!(decoded);
          }
        },
        onError: (error) {
          // Reconectar en caso de error
          _signatureSubscription = null;
        },
      );
    } catch (e) {
      throw Exception('Error conectando WebSocket para firmas: $e');
    }
  }

  // ⚡ Conectar WebSocket para suscripciones de logs
  Future<void> _connectLogsSubscription() async {
    try {
      _logsSubscription = WebSocketChannel.connect(Uri.parse(_wsUrl));
      _logsSubscription!.stream.listen(
        (data) {
          final decoded = jsonDecode(data as String) as Map<String, dynamic>;
          final id = decoded['id']?.toString();
          if (id != null && _logsCallbacks.containsKey(id)) {
            _logsCallbacks[id]!(decoded);
          }
        },
        onError: (error) {
          _logsSubscription = null;
        },
      );
    } catch (e) {
      throw Exception('Error conectando WebSocket para logs: $e');
    }
  }

  // ⚡ Conectar WebSocket para suscripciones de cuentas
  Future<void> _connectAccountSubscription() async {
    try {
      _accountSubscription = WebSocketChannel.connect(Uri.parse(_wsUrl));
      _accountSubscription!.stream.listen(
        (data) {
          final decoded = jsonDecode(data as String) as Map<String, dynamic>;
          final id = decoded['id']?.toString();
          if (id != null && _accountCallbacks.containsKey(id)) {
            _accountCallbacks[id]!(decoded);
          }
        },
        onError: (error) {
          _accountSubscription = null;
        },
      );
    } catch (e) {
      throw Exception('Error conectando WebSocket para cuentas: $e');
    }
  }

  int _subscriptionIdCounter = 0;
  String _generateSubscriptionId() {
    return 'sub_${++_subscriptionIdCounter}_${DateTime.now().millisecondsSinceEpoch}';
  }

  void dispose() {
    _signatureSubscription?.sink.close();
    _logsSubscription?.sink.close();
    _accountSubscription?.sink.close();
    _pendingConfirmations.clear();
    _signatureCallbacks.clear();
    _logsCallbacks.clear();
    _accountCallbacks.clear();
  }
}

