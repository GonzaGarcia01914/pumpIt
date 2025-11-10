class PhantomWalletService {
  bool get isAvailable => false;
  String? get currentPublicKey => null;

  Future<String> connect() async {
    throw UnsupportedError('Phantom solo está disponible en Flutter Web.');
  }

  Future<void> disconnect() async {}

  Future<String> signAndSendBase64(String swapTxBase64) async {
    throw UnsupportedError('Solo disponible en Flutter Web.');
  }
}
