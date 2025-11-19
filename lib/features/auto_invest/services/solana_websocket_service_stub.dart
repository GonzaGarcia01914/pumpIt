// Stub para plataformas que no soportan WebSocket (web)
class SolanaWebSocketService {
  SolanaWebSocketService({required String rpcUrl});
  Future<void> subscribeToSignature(String signature, {String? commitment}) async {
    throw UnimplementedError('WebSocket no disponible en esta plataforma');
  }
  Stream<Map<String, dynamic>> subscribeToProgramLogs(String programId, {String? commitment}) {
    throw UnimplementedError('WebSocket no disponible en esta plataforma');
  }
  Stream<Map<String, dynamic>> subscribeToAccount(String accountPubkey, {String? commitment}) {
    throw UnimplementedError('WebSocket no disponible en esta plataforma');
  }
  void dispose() {}
}

