import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:solana_web3/solana_web3.dart' as solana;
// ignore: implementation_imports
import 'package:solana_web3/src/crypto/nacl.dart' as nacl;

const _lamportsPerSol = 1000000000;

const _localKeyPath = String.fromEnvironment(
  'LOCAL_KEY_PATH',
  defaultValue: '',
);
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
  final Map<String, int> _mintDecimalsCache = {};

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

  Future<double?> readTokenAmountFromTransaction({
    required String signature,
    required String owner,
    required String mint,
  }) async {
    try {
      return await _tryReadTokenAmount(signature, owner, mint);
    } catch (error) {
      throw Exception('Lectura de fill falló: $error');
    }
  }

  Future<double?> readTokenBalance({
    required String owner,
    required String mint,
  }) async {
    try {
      return await _fetchTokenBalance(owner: owner, mint: mint);
    } catch (error) {
      throw Exception('Lectura de balance SPL fall�: $error');
    }
  }

  Future<double?> readSolChangeFromTransaction({
    required String signature,
    required String owner,
  }) async {
    try {
      final result = await _fetchTransactionResult(signature);
      if (result == null) return null;
      return _readSolChangeFromResult(result, owner);
    } catch (error) {
      throw Exception('Lectura de delta de SOL fall�: $error');
    }
  }

  Future<int> getMintDecimals(String mint) async {
    final cached = _mintDecimalsCache[mint];
    if (cached != null) return cached;
    try {
      final supply = await _connection.getTokenSupply(
        solana.Pubkey.fromBase58(mint),
      );
      final decimals = supply.decimals;
      _mintDecimalsCache[mint] = decimals;
      return decimals;
    } catch (_) {
      return 6;
    }
  }

  Future<double?> getWalletBalance(String address) async {
    try {
      final pubkey = solana.Pubkey.fromBase58(address);
      final lamports = await _connection.getBalance(pubkey);
      return lamports / _lamportsPerSol;
    } catch (_) {
      return null;
    }
  }

  Future<double?> getTransactionFee(String signature) async {
    try {
      final tx = await _connection.getTransaction(
        signature,
        config: solana.GetTransactionConfig(
          encoding: solana.TransactionEncoding.jsonParsed,
          commitment: solana.Commitment.confirmed,
          maxSupportedTransactionVersion: 0,
        ),
      );
      final feeLamports = tx?.meta?.fee;
      if (feeLamports == null) return null;
      return feeLamports / _lamportsPerSol;
    } catch (_) {
      return null;
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

  double? _findBalance(
    List<solana.TokenBalance>? balances,
    String owner,
    String mint,
  ) {
    if (balances == null || balances.isEmpty) return null;
    solana.TokenBalance? match;
    for (final entry in balances) {
      if (entry.owner == owner && entry.mint == mint) {
        match = entry;
        break;
      }
    }
    if (match == null) return null;
    final uiString = match.uiTokenAmount.uiAmountString;
    final maybeUi = double.tryParse(uiString);
    if (maybeUi != null) {
      return maybeUi;
    }
    final raw = double.tryParse(match.uiTokenAmount.amount);
    if (raw == null) {
      return null;
    }
    final decimals = match.uiTokenAmount.decimals.toDouble();
    return raw / math.pow(10, decimals);
  }

  Future<double?> _tryReadTokenAmount(
    String signature,
    String owner,
    String mint,
  ) async {
    try {
      return await _readTokenAmountWithClient(signature, owner, mint);
    } on TypeError catch (_) {
      return await _readTokenAmountFromRpc(signature, owner, mint);
    }
  }

  Future<double?> _readTokenAmountWithClient(
    String signature,
    String owner,
    String mint,
  ) async {
    final tx = await _connection.getTransaction(
      signature,
      config: solana.GetTransactionConfig(
        encoding: solana.TransactionEncoding.jsonParsed,
        commitment: solana.Commitment.confirmed,
        maxSupportedTransactionVersion: 0,
      ),
    );
    final meta = tx?.meta;
    if (meta == null) return null;
    final pre = _findBalance(meta.preTokenBalances, owner, mint);
    final post = _findBalance(meta.postTokenBalances, owner, mint);
    return _computeTokenDelta(pre, post);
  }

  Future<double?> _readTokenAmountFromRpc(
    String signature,
    String owner,
    String mint,
  ) async {
    final result = await _fetchTransactionResult(signature);
    if (result == null) return null;
    final meta = result['meta'] as Map<String, dynamic>?;
    if (meta == null) return null;
    final accountKeys = _extractAccountKeys(result);
    final pre = _findDynamicBalance(
      meta['preTokenBalances'] as List<dynamic>?,
      owner,
      mint,
      accountKeys,
    );
    final post = _findDynamicBalance(
      meta['postTokenBalances'] as List<dynamic>?,
      owner,
      mint,
      accountKeys,
    );
    return _computeTokenDelta(pre, post);
  }

  Future<double?> _fetchTokenBalance({
    required String owner,
    required String mint,
  }) async {
    final response = await http.post(
      Uri.parse(_rpcUrl),
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode({
        'jsonrpc': '2.0',
        'id': 'auto-invest-balance',
        'method': 'getTokenAccountsByOwner',
        'params': [
          owner,
          {'mint': mint},
          {
            'encoding': 'jsonParsed',
            'commitment': 'confirmed',
          },
        ],
      }),
    );
    if (response.statusCode != 200) {
      throw Exception('RPC respondi? ${response.statusCode}: ${response.body}');
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw Exception('Respuesta RPC inv?lida.');
    }
    final value = decoded['result'];
    if (value is! Map<String, dynamic>) {
      return null;
    }
    final accounts = value['value'];
    if (accounts is! List) return null;
    for (final entry in accounts) {
      if (entry is! Map<String, dynamic>) continue;
      final account = entry['account'] as Map<String, dynamic>?;
      final data = account?['data'] as Map<String, dynamic>?;
      final parsed = data?['parsed'] as Map<String, dynamic>?;
      final info = parsed?['info'] as Map<String, dynamic>?;
      final tokenAmount = info?['tokenAmount'];
      final amount = _parseTokenAccountAmount(tokenAmount);
      if (amount != null) {
        return amount;
      }
    }
    return null;
  }

  Future<Map<String, dynamic>?> _fetchTransactionResult(
    String signature,
  ) async {
    final response = await http.post(
      Uri.parse(_rpcUrl),
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode({
        'jsonrpc': '2.0',
        'id': 'auto-invest-fill',
        'method': 'getTransaction',
        'params': [
          signature,
          {
            'encoding': 'jsonParsed',
            'commitment': 'confirmed',
            'maxSupportedTransactionVersion': 0,
          },
        ],
      }),
    );
    if (response.statusCode != 200) {
      throw Exception('RPC respondió ${response.statusCode}: ${response.body}');
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw Exception('Respuesta RPC inválida.');
    }
    final error = decoded['error'];
    if (error != null) {
      throw Exception('RPC error: $error');
    }
    final result = decoded['result'];
    if (result == null) return null;
    if (result is Map<String, dynamic>) {
      return result;
    }
    throw Exception('Formato de transacción desconocido.');
  }

  double? _readSolChangeFromResult(
    Map<String, dynamic> result,
    String owner,
  ) {
    final meta = result['meta'] as Map<String, dynamic>?;
    final transaction = result['transaction'] as Map<String, dynamic>?;
    if (meta == null || transaction == null) {
      return null;
    }
    final accountKeys = _extractAccountKeys(result);
    if (accountKeys == null) {
      return null;
    }
    final ownerIndex = _accountIndex(owner, accountKeys);
    if (ownerIndex == null) {
      return null;
    }
    final preBalances = meta['preBalances'] as List<dynamic>?;
    final postBalances = meta['postBalances'] as List<dynamic>?;
    if (preBalances == null ||
        postBalances == null ||
        ownerIndex >= preBalances.length ||
        ownerIndex >= postBalances.length) {
      return null;
    }
    final preLamports = _lamportsFromDynamic(preBalances[ownerIndex]);
    final postLamports = _lamportsFromDynamic(postBalances[ownerIndex]);
    if (preLamports == null || postLamports == null) {
      return null;
    }
    return (postLamports - preLamports) / _lamportsPerSol;
  }

  List<dynamic>? _extractAccountKeys(Map<String, dynamic>? txResult) {
    final transaction = txResult?['transaction'];
    if (transaction is Map<String, dynamic>) {
      final message = transaction['message'];
      if (message is Map<String, dynamic>) {
        final keys = message['accountKeys'];
        if (keys is List<dynamic>) {
          return keys;
        }
      }
    }
    return null;
  }

  double? _findDynamicBalance(
    List<dynamic>? balances,
    String owner,
    String mint,
    List<dynamic>? accountKeys,
  ) {
    if (balances == null || balances.isEmpty) return null;
    for (final entry in balances) {
      if (entry is! Map<String, dynamic>) continue;
      final entryMint = entry['mint']?.toString();
      if (entryMint != mint) continue;
      final rawOwner =
          entry['owner'] ??
          _ownerFromAccountIndex(entry['accountIndex'], accountKeys);
      final entryOwner = rawOwner?.toString();
      if (entryOwner != owner) continue;
      return _parseDynamicUiAmount(entry['uiTokenAmount']);
    }
    return null;
  }

  String? _ownerFromAccountIndex(dynamic index, List<dynamic>? accountKeys) {
    if (accountKeys == null) return null;
    int? resolved;
    if (index is int) {
      resolved = index;
    } else if (index is num) {
      resolved = index.toInt();
    } else if (index != null) {
      resolved = int.tryParse(index.toString());
    }
    if (resolved == null || resolved < 0 || resolved >= accountKeys.length) {
      return null;
    }
    final entry = accountKeys[resolved];
    if (entry is Map<String, dynamic>) {
      final pubkey = entry['pubkey'];
      if (pubkey is String && pubkey.isNotEmpty) {
        return pubkey;
      }
    } else if (entry is String && entry.isNotEmpty) {
      return entry;
    }
    return null;
  }

  int? _accountIndex(String owner, List<dynamic>? accountKeys) {
    if (accountKeys == null) return null;
    for (var i = 0; i < accountKeys.length; i++) {
      final entry = accountKeys[i];
      String? pubkey;
      if (entry is Map<String, dynamic>) {
        final raw = entry['pubkey'];
        if (raw is String && raw.isNotEmpty) {
          pubkey = raw;
        }
      } else if (entry is String && entry.isNotEmpty) {
        pubkey = entry;
      }
      if (pubkey == owner) {
        return i;
      }
    }
    return null;
  }

  double? _lamportsFromDynamic(dynamic value) {
    if (value == null) return null;
    if (value is int) {
      return value.toDouble();
    }
    if (value is num) {
      return value.toDouble();
    }
    return double.tryParse(value.toString());
  }

  double? _parseTokenAccountAmount(dynamic raw) {
    if (raw is! Map<String, dynamic>) return null;
    final uiString = raw['uiAmountString']?.toString();
    if (uiString != null) {
      final maybeUi = double.tryParse(uiString);
      if (maybeUi != null) {
        return maybeUi;
      }
    }
    final amountString = raw['amount']?.toString();
    if (amountString == null) return null;
    final rawAmount = double.tryParse(amountString);
    if (rawAmount == null) return null;
    final decimals = (raw['decimals'] as num?)?.toDouble() ?? 0;
    return rawAmount / math.pow(10, decimals);
  }

  double? _parseDynamicUiAmount(dynamic raw) {
    if (raw is! Map<String, dynamic>) return null;
    final uiString = raw['uiAmountString']?.toString();
    if (uiString != null) {
      final maybeUi = double.tryParse(uiString);
      if (maybeUi != null) {
        return maybeUi;
      }
    }
    final amountString = raw['amount']?.toString();
    final rawAmount = amountString == null
        ? null
        : double.tryParse(amountString);
    if (rawAmount == null) return null;
    final decimals = (raw['decimals'] as num?)?.toDouble() ?? 0;
    return rawAmount / math.pow(10, decimals);
  }

  double? _computeTokenDelta(double? pre, double? post) {
    if (post == null) return null;
    final delta = post - (pre ?? 0);
    if (delta <= 0) {
      return null;
    }
    return delta;
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
