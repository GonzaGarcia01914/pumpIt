import 'wallet_execution_service_stub.dart'
    if (dart.library.html) 'wallet_execution_service_phantom.dart'
    if (dart.library.io) 'wallet_execution_service_local.dart'
    as impl;

export 'wallet_execution_service_stub.dart'
    if (dart.library.html) 'wallet_execution_service_phantom.dart'
    if (dart.library.io) 'wallet_execution_service_local.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

// ⚡ Importar WebSocket service solo en desktop
import 'solana_websocket_service.dart'
    if (dart.library.html) 'solana_websocket_service_stub.dart'
    as ws;

typedef WalletExecutionService = impl.WalletExecutionService;

final walletExecutionServiceProvider = Provider<WalletExecutionService>((ref) {
  // ⚡ Crear WebSocket service solo en desktop (dart:io)
  ws.SolanaWebSocketService? websocketService;
  try {
    websocketService = ref.watch(solanaWebSocketServiceProvider);
  } catch (e) {
    // WebSocket no disponible en esta plataforma
    websocketService = null;
  }

  // Crear servicio - solo desktop acepta websocketService
  final service = impl.WalletExecutionService(
    websocketService: websocketService,
  );
  ref.onDispose(service.dispose);
  return service;
});

// ⚡ Provider para WebSocket service (solo en desktop)
final solanaWebSocketServiceProvider = Provider<ws.SolanaWebSocketService?>((
  ref,
) {
  const apiKey = String.fromEnvironment('HELIUS_API_KEY', defaultValue: '');
  try {
    final service = ws.SolanaWebSocketService(
      apiKey: apiKey.isNotEmpty ? apiKey : null,
    );
    ref.onDispose(service.dispose);
    return service;
  } catch (e) {
    // Si WebSocket no está disponible, retornar null (fallback a RPC HTTP)
    return null;
  }
});
