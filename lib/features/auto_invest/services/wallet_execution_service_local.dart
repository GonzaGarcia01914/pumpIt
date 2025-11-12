import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:solana_web3/solana_web3.dart' as solana;

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
    final txBytes = base64Decode(swapTxBase64);
    final transaction = solana.Transaction.deserialize(txBytes);
    transaction.sign([keypair]);

    final signature = await _connection.sendTransaction(
      transaction,
      config: const solana.SendTransactionConfig(
        skipPreflight: true,
        preflightCommitment: solana.Commitment.confirmed,
      ),
    );
    return signature;
  }

  Future<void> waitForConfirmation(String signature) async {
    final notification = await _connection.confirmTransaction(
      signature,
      config: const solana.ConfirmTransactionConfig(
        commitment: solana.Commitment.finalized,
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

  void dispose() {
    _connection.dispose();
  }
}
