import 'dart:io' as io;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../featured_coins/models/featured_coin.dart';
import '../models/execution_mode.dart';
import '../models/position.dart';

class TransactionAuditLogger {
  TransactionAuditLogger();

  static const List<String> _headerColumns = [
    'timestamp',
    'side',
    'symbol',
    'name',
    'mint',
    'mode',
    'entry_sol',
    'exit_sol',
    'token_amount',
    'entry_price_sol',
    'exit_price_sol',
    'pnl_sol',
    'pnl_percent',
    'tx_signature',
    'solscan_url',
    'marketcap_sol',
    'usd_market_cap',
    'created_at',
    'last_reply_at',
    'reply_count',
    'twitter',
    'telegram',
    'website',
  ];

  io.File? _cachedFile;
  Future<void>? _headerReady;

  io.File _resolveFile() {
    // Same folder as the running process (best-effort on desktop/dev runs)
    final dir = io.Directory.current.path;
    final path = '$dir${io.Platform.pathSeparator}results.csv';
    return io.File(path);
  }

  Future<io.File> _prepareFile() async {
    final file = _cachedFile ??= _resolveFile();
    _headerReady ??= _ensureHeader(file);
    try {
      await _headerReady;
    } catch (_) {
      _headerReady = null;
      rethrow;
    }
    return file;
  }

  String get _delimiter => io.Platform.isWindows ? ';' : ',';

  Future<void> _ensureHeader(io.File file) async {
    if (!await file.exists()) {
      await file.create(recursive: true);
      await _writeRow(file, _headerColumns, append: false);
    }
  }

  String _csv(String? value) {
    final v = value ?? '';
    if (v.contains(',') || v.contains('"') || v.contains('\n')) {
      return '"${v.replaceAll('"', '""')}"';
    }
    return v;
  }

  Future<void> _writeRow(
    io.File file,
    List<String?> values, {
    bool append = true,
  }) async {
    final joined = values.map(_csv).join(_delimiter);
    await file.writeAsString(
      '$joined\n',
      mode: append ? io.FileMode.append : io.FileMode.write,
      flush: true,
    );
  }

  Future<void> logBuyFromFeatured({
    required FeaturedCoin coin,
    required String signature,
    required double entrySol,
    required AutoInvestExecutionMode mode,
    double? entryPriceSol,
  }) async {
    if (kIsWeb) return; // No filesystem on web
    final file = await _prepareFile();
    final solscan = 'https://solscan.io/tx/$signature';
    final row = [
      DateTime.now().toIso8601String(),
      'buy',
      coin.symbol,
      coin.name,
      coin.mint,
      mode.name,
      entrySol.toStringAsFixed(8),
      '',
      '',
      entryPriceSol?.toStringAsFixed(8) ?? '',
      '',
      '',
      '',
      signature,
      solscan,
      coin.marketCapSol.toStringAsFixed(3),
      coin.usdMarketCap.toStringAsFixed(2),
      coin.createdAt.toIso8601String(),
      coin.lastReplyAt?.toIso8601String() ?? '',
      coin.replyCount.toString(),
      coin.twitterUrl?.toString() ?? '',
      coin.telegramUrl?.toString() ?? '',
      coin.websiteUrl?.toString() ?? '',
    ];
    await _writeRow(file, row);
  }

  Future<void> logSellFromPosition({
    required OpenPosition position,
    required String signature,
    required double expectedExitSol,
    double? realizedExitSol,
    double? pnlSol,
    double? pnlPercent,
    PositionAlertType? reason,
  }) async {
    if (kIsWeb) return;
    final file = await _prepareFile();
    final solscan = 'https://solscan.io/tx/$signature';
    final row = [
      DateTime.now().toIso8601String(),
      'sell',
      position.symbol,
      '',
      position.mint,
      position.executionMode.name,
      position.entrySol.toStringAsFixed(8),
      (realizedExitSol ?? expectedExitSol).toStringAsFixed(8),
      position.tokenAmount?.toStringAsFixed(8) ?? '',
      position.entryPriceSol?.toStringAsFixed(8) ?? '',
      position.lastPriceSol?.toStringAsFixed(8) ?? '',
      (pnlSol ??
                  (realizedExitSol == null
                      ? null
                      : (realizedExitSol - position.entrySol)))
              ?.toStringAsFixed(8) ??
          '',
      pnlPercent?.toStringAsFixed(4) ?? '',
      signature,
      solscan,
      '',
      '',
      position.openedAt.toIso8601String(),
      '',
      '',
      reason?.label ?? '',
      '',
      '',
    ];
    await _writeRow(file, row);
  }
}

final transactionAuditLoggerProvider = Provider<TransactionAuditLogger>((ref) {
  return TransactionAuditLogger();
});
