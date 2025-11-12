class WalletExecutionService {
  bool get isAvailable => false;
  String? get currentPublicKey => null;

  Future<String> connect() async {
    throw UnsupportedError('Wallet no disponible en esta plataforma.');
  }

  Future<void> disconnect() async {}

  Future<String> signAndSendBase64(String swapTxBase64) async {
    throw UnsupportedError('Wallet no disponible en esta plataforma.');
  }

  Future<void> waitForConfirmation(String signature) async {}

  void dispose() {}
}
