// ignore_for_file: deprecated_member_use

import 'dart:convert';

import 'package:js/js.dart';
import 'package:js/js_util.dart' as jsu;

class WalletExecutionService {
  _PhantomProvider? get _provider => _phantomProvider();

  bool get isAvailable => _provider?.isPhantom == true;

  String? _currentPublicKey;

  String? get currentPublicKey => _currentPublicKey;

  Future<String> connect() async {
    final provider = _provider;
    if (provider == null) {
      throw Exception('Phantom no se encuentra disponible en este navegador.');
    }
    await jsu.promiseToFuture(provider.connect());
    final publicKey = _extractPublicKey(provider);
    if (publicKey == null) {
      throw Exception('No se pudo obtener la public key de Phantom.');
    }
    _currentPublicKey = publicKey;
    return publicKey;
  }

  Future<void> disconnect() async {
    final provider = _provider;
    if (provider == null) return;
    await jsu.promiseToFuture(provider.disconnect());
    _currentPublicKey = null;
  }

  Future<String> signAndSendBase64(String swapTxBase64) async {
    final provider = _provider;
    if (provider == null) {
      throw Exception('Phantom no esta disponible.');
    }
    final txBytes = base64Decode(swapTxBase64);
    final result = await jsu.promiseToFuture(
      provider.signAndSendTransaction(txBytes),
    );
    final signature = jsu.hasProperty(result, 'signature')
        ? jsu.getProperty(result, 'signature')?.toString()
        : result.toString();
    if (signature == null || signature.isEmpty) {
      throw Exception('Phantom no devolvio signature.');
    }
    return signature;
  }

  Future<void> waitForConfirmation(String signature) async {
    // Phantom ya maneja el envío; no hay RPC local para confirmar.
    // Dejamos un pequeño delay para evitar marcar la orden inmediatamente.
    await Future.delayed(const Duration(seconds: 1));
  }

  Future<double?> readTokenAmountFromTransaction({
    required String signature,
    required String owner,
    required String mint,
  }) async {
    // No tenemos acceso a un RPC configurable en web, devolvemos null.
    return null;
  }

  Future<int> getMintDecimals(String mint) async => 6;

  Future<double?> getWalletBalance(String address) async => null;

  String? _extractPublicKey(_PhantomProvider provider) {
    final pk = provider.publicKey;
    if (pk == null) return null;
    final value = jsu.callMethod(pk, 'toString', const []);
    return value?.toString();
  }

  void dispose() {}
}

_PhantomProvider? _phantomProvider() {
  if (!jsu.hasProperty(jsu.globalThis, 'solana')) {
    return null;
  }
  final provider = jsu.getProperty(jsu.globalThis, 'solana');
  return provider is _PhantomProvider ? provider : null;
}

@JS()
class _PhantomProvider {
  external bool get isPhantom;
  external dynamic connect();
  external dynamic disconnect();
  external dynamic signAndSendTransaction(dynamic transaction);
  external dynamic get publicKey;
}
