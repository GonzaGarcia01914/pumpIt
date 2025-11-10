// ignore_for_file: deprecated_member_use, depend_on_referenced_packages

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:js/js.dart';
import 'package:js/js_util.dart' as jsu;

class PhantomWalletService {
  _PhantomProvider? get _provider => _phantomProvider();

  bool get isAvailable =>
      kIsWeb && _provider != null && (_provider!.isPhantom == true);

  String? _currentPublicKey;

  String? get currentPublicKey => _currentPublicKey;

  Future<String> connect() async {
    final provider = _provider;
    if (provider == null) {
      throw Exception(
          'Phantom no se encuentra disponible en esta plataforma/navegador.');
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
      throw Exception('Phantom no está disponible.');
    }
    final txBytes = Uint8List.fromList(base64Decode(swapTxBase64));
    final result =
        await jsu.promiseToFuture(provider.signAndSendTransaction(txBytes));
    if (result == null) {
      throw Exception('Phantom no devolvió respuesta.');
    }
    final signature = jsu.hasProperty(result, 'signature')
        ? jsu.getProperty(result, 'signature')?.toString()
        : result.toString();
    if (signature == null || signature.isEmpty) {
      throw Exception('Phantom no devolvió signature.');
    }
    return signature;
  }

  String? _extractPublicKey(_PhantomProvider provider) {
    final pk = provider.publicKey;
    if (pk == null) return null;
    final value = jsu.callMethod(pk, 'toString', const []);
    return value?.toString();
  }
}

_PhantomProvider? _phantomProvider() {
  if (!kIsWeb) return null;
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
