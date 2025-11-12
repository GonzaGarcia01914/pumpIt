import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:solana_web3/solana_web3.dart' as solana;
import 'package:solana_web3/src/crypto/nacl.dart' as nacl;

const _localKeyPath = String.fromEnvironment('LOCAL_KEY_PATH', defaultValue: '');
const _rpcUrl = String.fromEnvironment(
  'RPC_URL',
  defaultValue: 'https://api.mainnet-beta.solana.com',
);

class WalletExecutionService {
  WalletExecutionService() {
    final cluster = _clusterFromRpc(_rpcUrl);
    _connection = solana.Connection(
      cluster,
      commitment: solana.Commitment.confirmed,
    );
    if (_localKeyPath.isNotEmpty) {
      _loadKeypairSync();
    }
  }

  late final solana.Connection _connection;
  solana.Keypair? _keypair;

  bool get isAvailable => _keypair != null;

  String? get currentPublicKey => _keypair?.pubkey.toBase58();

  Future<String> connect() async {
    if (_keypair == null) {
      _loadKeypairSync();
    }
    final pubkey = currentPublicKey;
    if (pubkey == null) {
      throw Exception(
        'LOCAL_KEY_PATH no definido o invalido. Usa --dart-define=LOCAL_KEY_PATH=C:/Keys/auto_bot.json',
      );
    }
    return pubkey;
  }

  Future<void> disconnect() async {}

  Future<String> signAndSendBase64(String swapTxBase64) async {
    final keypair = _keypair;
    if (keypair == null) {
      throw Exception('Wallet local no cargada.');
    }
    try {
      final signedBytes = _signRawTransaction(
        base64Decode(swapTxBase64),
        keypair,
      );
      final signature = await _connection.sendSignedTransaction(
        base64Encode(signedBytes),
        config: const solana.SendTransactionConfig(
          skipPreflight: false,
          maxRetries: 3,
          preflightCommitment: solana.Commitment.confirmed,
        ),
      );
      return signature;
    } on solana.JsonRpcException catch (error) {
      final code = error.code;
      final message = error.message;
      final details = error.data;
      throw Exception(
        'RPC rechazó la transacción (code $code): $message ${details == null ? '' : details.toString()}',
      );
    }
  }

  Future<void> waitForConfirmation(String signature) async {
    // Use `confirmed` to reduce timeouts during congestion. Finalization can take long
    // and trigger TimeoutException even when the tx eventually lands.
    final notification = await _connection.confirmTransaction(
      signature,
      config: const solana.ConfirmTransactionConfig(
        commitment: solana.Commitment.confirmed,
      ),
    );
    final err = notification.err;
    if (err != null) {
      throw Exception('Confirmación falló: $err');
    }
  }

  void _loadKeypairSync() {
    if (_localKeyPath.isEmpty) {
      return;
    }
    final file = File(_localKeyPath);
    if (!file.existsSync()) {
      throw Exception('No existe LOCAL_KEY_PATH: $_localKeyPath');
    }
    final content = file.readAsStringSync();
    final data = jsonDecode(content) as List<dynamic>;
    final secretKey = Uint8List.fromList(data.cast<int>());
    _keypair = solana.Keypair.fromSeckeySync(secretKey);
  }

  static solana.Cluster _clusterFromRpc(String rawUrl) {
    final uri = Uri.tryParse(rawUrl);
    if (uri == null || uri.scheme.isEmpty) {
      throw Exception('RPC_URL invalida: $rawUrl');
    }
    return solana.Cluster(uri);
  }

  Uint8List _signRawTransaction(Uint8List txBytes, solana.Keypair keypair) {
    final reader = _ShortVecReader(txBytes);
    final sigCount = reader.readLength();
    final signaturesOffset = reader.offset;
    final signaturesLen = sigCount * nacl.signatureLength;
    final messageOffset = signaturesOffset + signaturesLen;
    if (messageOffset >= txBytes.length) {
      throw Exception('Transacción inválida: sin sección de mensaje.');
    }
    final messageBytes = Uint8List.sublistView(txBytes, messageOffset);
    final signature = nacl.sign.detached.sync(messageBytes, keypair.seckey);
    final signed = Uint8List.fromList(txBytes);
    signed.setRange(
      signaturesOffset,
      signaturesOffset + nacl.signatureLength,
      signature,
    );
    return signed;
  }

  void dispose() {
    _connection.dispose();
  }
}

class _ShortVecReader {
  _ShortVecReader(this.data);

  final Uint8List data;
  int offset = 0;

  int readLength() {
    int len = 0;
    int size = 0;
    while (true) {
      if (offset >= data.length) {
        throw Exception('Transacción incompleta (shortvec).');
      }
      final byte = data[offset++];
      len |= (byte & 0x7f) << (7 * size);
      size += 1;
      if ((byte & 0x80) == 0) {
        break;
      }
    }
    return len;
  }
}
