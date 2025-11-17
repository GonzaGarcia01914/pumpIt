import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../featured_coins/controller/featured_coin_notifier.dart';
import '../../featured_coins/models/featured_coin.dart';
import '../models/execution_record.dart';
import '../models/execution_mode.dart';
import '../models/position.dart';
import '../services/jupiter_swap_service.dart';
import '../services/pump_fun_price_service.dart';
import '../services/pump_portal_trade_service.dart';
import '../services/wallet_execution_service.dart';
import '../services/transaction_audit_logger.dart';
import 'auto_invest_notifier.dart';

const _lamportsPerSol = 1000000000;

class AutoInvestExecutor {
  AutoInvestExecutor(
    this.ref,
    this.jupiter,
    this.wallet,
    this.pumpPortal,
    this.priceService,
  );

  final Ref ref;
  final JupiterSwapService jupiter;
  final WalletExecutionService wallet;
  final PumpPortalTradeService pumpPortal;
  final PumpFunPriceService priceService;

  bool _isRunning = false;
  final Map<String, DateTime> _recentMints = {};
  final Set<String> _positionsSelling = {};

  void init() {
    ref.listen<AutoInvestState>(
      autoInvestProvider,
      (_, __) => _scheduleCheck(),
    );
    ref.listen<FeaturedCoinState>(
      featuredCoinProvider,
      (_, __) => _scheduleCheck(),
    );
  }

  void _scheduleCheck() {
    final autoState = ref.read(autoInvestProvider);
    _cleanupFailedEntries(autoState);
    if (!autoState.isEnabled || autoState.walletAddress == null) {
      return;
    }
    if (!wallet.isAvailable) {
      return;
    }
    if (_isRunning) {
      return;
    }
    _isRunning = true;
    Future(() async {
      try {
        await _evaluate();
      } finally {
        _isRunning = false;
      }
    });
  }

  Future<void> _evaluate() async {
    final autoState = ref.read(autoInvestProvider);
    if (!autoState.isEnabled || autoState.walletAddress == null) {
      return;
    }
    if (!wallet.isAvailable) {
      ref
          .read(autoInvestProvider.notifier)
          .setStatus(
            'Wallet no disponible. Verifica Phantom (web) o LOCAL_KEY_PATH (desktop).',
          );
      return;
    }

    final coins = ref.read(featuredCoinProvider).coins;

    _cleanupRecent();
    final notifier = ref.read(autoInvestProvider.notifier);
    final scanReport = _scanFeaturedCoins(coins, autoState);
    final scanMessage = _scanSummaryMessage(scanReport, autoState);
    if (scanReport.hasCandidate) {
      if (autoState.lastScanFailed ||
          autoState.lastScanMessage != scanMessage) {
        notifier.recordScanReport(message: scanMessage, failed: false);
      }
    } else {
      final reasons = _scanFailureReasons(scanReport, autoState);
      final sameMessage = autoState.lastScanMessage == scanMessage;
      final sameReasons = listEquals(autoState.lastScanReasons, reasons);
      if (!(autoState.lastScanFailed && sameMessage && sameReasons)) {
        notifier.recordScanReport(
          message: scanMessage,
          failed: true,
          reasons: reasons,
        );
      }
    }
    FeaturedCoin? candidate;
    if (autoState.includeManualMints && autoState.manualMints.isNotEmpty) {
      candidate = _pickManualCandidate(autoState);
    }
    candidate ??= scanReport.candidate;
    if (candidate == null) return;
    final alreadyHolding = autoState.positions.any(
      (position) => position.mint == candidate!.mint,
    );
    if (alreadyHolding) {
      notifier.setStatus(
        'Ya existe una posición abierta en ${candidate.symbol}; se omite la entrada.',
      );
      return;
    }
    if (autoState.availableBudgetSol < autoState.perCoinBudgetSol) {
      ref
          .read(autoInvestProvider.notifier)
          .setStatus(
            'Presupuesto disponible (${autoState.availableBudgetSol.toStringAsFixed(2)} SOL) insuficiente para nueva entrada.',
          );
      return;
    }

    final lamports = (autoState.perCoinBudgetSol * _lamportsPerSol)
        .round()
        .clamp(1, 5000000000);
    if (autoState.executionMode == AutoInvestExecutionMode.pumpPortal) {
      final minBudget = math.max(0.01, autoState.pumpPriorityFeeSol + 0.003);
      if (autoState.perCoinBudgetSol < minBudget) {
        ref
            .read(autoInvestProvider.notifier)
            .setStatus(
              'Presupuesto por meme ('
              '${autoState.perCoinBudgetSol.toStringAsFixed(4)} SOL) demasiado bajo. Usa al menos '
              '${minBudget.toStringAsFixed(3)} SOL para cubrir ATA + priority fee.',
            );
        return;
      }
    }

    ref
        .read(autoInvestProvider.notifier)
        .setStatus(
          autoState.executionMode == AutoInvestExecutionMode.jupiter
              ? 'Preparando compra automática de ${candidate.symbol} (${autoState.perCoinBudgetSol} SOL) vía Jupiter.'
              : 'Preparando compra automática de ${candidate.symbol} (${autoState.perCoinBudgetSol} SOL) vía PumpPortal.',
        );
    try {
      // Precio de referencia al momento de la entrada (SOL por token)
      final pumpQuote = await priceService.fetchQuote(candidate.mint);
      final signature = switch (autoState.executionMode) {
        AutoInvestExecutionMode.jupiter => await _executeViaJupiter(
          autoState,
          candidate,
          lamports,
        ),
        AutoInvestExecutionMode.pumpPortal => await _executeViaPumpPortal(
          autoState,
          candidate,
        ),
      };
      // Registro de auditoría (CSV) para compras
      unawaited(
        ref
            .read(transactionAuditLoggerProvider)
            .logBuyFromFeatured(
              coin: candidate,
              signature: signature,
              entrySol: autoState.perCoinBudgetSol,
              mode: autoState.executionMode,
              entryPriceSol: pumpQuote.priceSol,
            ),
      );
      final notifier = ref.read(autoInvestProvider.notifier);
      notifier.recordExecution(
        ExecutionRecord(
          mint: candidate.mint,
          symbol: candidate.symbol,
          solAmount: autoState.perCoinBudgetSol,
          side: 'buy',
          txSignature: signature,
          executedAt: DateTime.now(),
        ),
      );
      notifier.recordPositionEntry(
        mint: candidate.mint,
        symbol: candidate.symbol,
        solAmount: autoState.perCoinBudgetSol,
        txSignature: signature,
        executionMode: autoState.executionMode,
      );
      unawaited(
        _trackConfirmation(signature, candidate.symbol, candidate.mint),
      );
      _recentMints[candidate.mint] = DateTime.now();
    } catch (error) {
      ref
          .read(autoInvestProvider.notifier)
          .recordExecutionError(candidate.symbol, error.toString());
      _recentMints[candidate.mint] = DateTime.now();
    }
  }

  FeaturedCoin? _pickManualCandidate(AutoInvestState autoState) {
    // Prefer manual mints that are not recently attempted and not already held
    final heldMints = {for (final p in autoState.positions) p.mint};
    for (final mint in autoState.manualMints) {
      final m = mint.trim();
      if (m.isEmpty) continue;
      if (_recentMints.containsKey(m)) continue;
      if (heldMints.contains(m)) continue;
      // Build a lightweight candidate; filters will be skipped for manual entries
      return FeaturedCoin(
        mint: m,
        name: 'Manual',
        symbol: m.length >= 4
            ? m.substring(0, 4).toUpperCase()
            : m.toUpperCase(),
        imageUri: '',
        marketCapSol: 0,
        usdMarketCap: 0,
        createdAt: DateTime.now(),
        lastReplyAt: null,
        replyCount: 0,
        isComplete: false,
        isCurrentlyLive: true,
        twitterUrl: null,
        telegramUrl: null,
        websiteUrl: null,
      );
    }
    return null;
  }

  _ScanReport _scanFeaturedCoins(
    List<FeaturedCoin> coins,
    AutoInvestState autoState,
  ) {
    final now = DateTime.now();
    var eligible = 0;
    var filteredByMarketCap = 0;
    var filteredByReplies = 0;
    var filteredByAge = 0;
    var filteredByCooldown = 0;
    var filteredByHeld = 0;
    final heldMints = {
      for (final position in autoState.positions) position.mint,
    };
    FeaturedCoin? candidate;
    for (final coin in coins) {
      if (coin.usdMarketCap < autoState.minMarketCap ||
          coin.usdMarketCap > autoState.maxMarketCap) {
        filteredByMarketCap++;
        continue;
      }
      if (autoState.minReplies > 0 &&
          coin.replyCount.toDouble() < autoState.minReplies) {
        filteredByReplies++;
        continue;
      }
      if (autoState.maxAgeHours > 0) {
        final ageHours = now.difference(coin.createdAt).inMinutes / 60.0;
        if (ageHours > autoState.maxAgeHours) {
          filteredByAge++;
          continue;
        }
      }
      if (heldMints.contains(coin.mint)) {
        filteredByHeld++;
        continue;
      }
      if (_recentMints.containsKey(coin.mint)) {
        filteredByCooldown++;
        continue;
      }
      eligible++;
      candidate ??= coin;
    }
    return _ScanReport(
      total: coins.length,
      eligible: eligible,
      filteredByMarketCap: filteredByMarketCap,
      filteredByReplies: filteredByReplies,
      filteredByAge: filteredByAge,
      filteredByHeld: filteredByHeld,
      filteredByCooldown: filteredByCooldown,
      candidate: candidate,
    );
  }

  String _scanSummaryMessage(_ScanReport report, AutoInvestState autoState) {
    final buffer = StringBuffer()
      ..write(
        'Escaneo memecoins: ${report.eligible}/${report.total} aptas para MC '
        '${autoState.minMarketCap.toStringAsFixed(0)}-'
        '${autoState.maxMarketCap.toStringAsFixed(0)} USD',
      );
    if (autoState.minReplies > 0) {
      buffer.write(' | replies >= ${autoState.minReplies.toStringAsFixed(0)}');
    }
    if (autoState.maxAgeHours > 0) {
      buffer.write(' | edad <= ${autoState.maxAgeHours.toStringAsFixed(0)}h');
    }
    buffer.write(
      report.hasCandidate && report.candidate != null
          ? ' | candidata ${report.candidate!.symbol}.'
          : ' | sin candidatas.',
    );
    return buffer.toString();
  }

  List<String> _scanFailureReasons(
    _ScanReport report,
    AutoInvestState autoState,
  ) {
    if (report.total == 0) {
      return const ['No hay memecoins en featured en este momento.'];
    }
    final reasons = <String>[];
    if (report.filteredByMarketCap > 0) {
      reasons.add(
        '${report.filteredByMarketCap} fuera del rango de market cap '
        '(${autoState.minMarketCap.toStringAsFixed(0)}-'
        '${autoState.maxMarketCap.toStringAsFixed(0)} USD).',
      );
    }
    if (autoState.minReplies > 0 && report.filteredByReplies > 0) {
      reasons.add(
        '${report.filteredByReplies} no alcanzan los replies mínimos '
        '(${autoState.minReplies.toStringAsFixed(0)}).',
      );
    }
    if (autoState.maxAgeHours > 0 && report.filteredByAge > 0) {
      reasons.add(
        '${report.filteredByAge} superan las '
        '${autoState.maxAgeHours.toStringAsFixed(0)}h desde el deploy.',
      );
    }
    if (report.filteredByHeld > 0) {
      reasons.add('${report.filteredByHeld} ya tienen una posición abierta.');
    }
    if (report.filteredByCooldown > 0) {
      reasons.add(
        '${report.filteredByCooldown} están en cooldown por intentos recientes.',
      );
    }
    if (report.eligible == 0 && reasons.isEmpty) {
      reasons.add('Ninguna memecoin cumplió los filtros actuales.');
    }
    return reasons;
  }

  Future<String> _executeViaJupiter(
    AutoInvestState autoState,
    FeaturedCoin candidate,
    int lamports,
  ) async {
    final quote = await jupiter.fetchQuote(
      inputMint: JupiterSwapService.solMint,
      outputMint: candidate.mint,
      amountLamports: lamports,
    );
    final swap = await jupiter.swap(
      route: quote.route,
      userPublicKey: autoState.walletAddress!,
    );
    return wallet.signAndSendBase64(swap.swapTransaction);
  }

  Future<String> _executeViaPumpPortal(
    AutoInvestState autoState,
    FeaturedCoin candidate,
  ) async {
    final base64Tx = await pumpPortal.buildTradeTransaction(
      action: 'buy',
      publicKey: autoState.walletAddress!,
      mint: candidate.mint,
      amount: _formatAmount(autoState.perCoinBudgetSol),
      denominatedInSol: true,
      slippagePercent: autoState.pumpSlippagePercent,
      priorityFeeSol: autoState.pumpPriorityFeeSol,
      pool: autoState.pumpPool,
    );
    return wallet.signAndSendBase64(base64Tx);
  }

  String _formatAmount(double value) {
    if (value == value.roundToDouble()) {
      return value.toStringAsFixed(0);
    }
    return value.toString();
  }

  void _cleanupRecent() {
    final cutoff = DateTime.now().subtract(const Duration(minutes: 15));
    _recentMints.removeWhere((_, time) => time.isBefore(cutoff));
  }


  void _cleanupFailedEntries(AutoInvestState state) {
    if (state.executions.isEmpty || state.positions.isEmpty) {
      return;
    }
    final failedBuys = <String, String>{};
    for (final execution in state.executions) {
      if (execution.side != 'buy') continue;
      if (execution.status != 'failed') continue;
      failedBuys[execution.txSignature] = execution.mint;
    }
    if (failedBuys.isEmpty) return;
    final notifier = ref.read(autoInvestProvider.notifier);
    for (final position in state.positions) {
      final mint = failedBuys[position.entrySignature];
      if (mint == null) continue;
      final removed = notifier.removePosition(
        position.entrySignature,
        refundBudget: true,
      );
      if (removed) {
        _recentMints.remove(mint);
        failedBuys.remove(position.entrySignature);
      }
      if (failedBuys.isEmpty) {
        break;
      }
    }
  }

  void discardPosition(String entrySignature) {
    _positionsSelling.remove(entrySignature);
    final state = ref.read(autoInvestProvider);
    OpenPosition? position;
    for (final current in state.positions) {
      if (current.entrySignature == entrySignature) {
        position = current;
        break;
      }
    }
    if (position != null) {
      _recentMints.remove(position.mint);
    }
  }

  Future<void> sellPosition(
    OpenPosition position, {
    PositionAlertType? reason,
  }) async {
    final tokenAmount = position.tokenAmount;
    final notifier = ref.read(autoInvestProvider.notifier);
    if (tokenAmount == null || tokenAmount <= 0) {
      notifier.setStatus('No hay tokens para vender en ${position.symbol}.');
      return;
    }
    if (_positionsSelling.contains(position.entrySignature) ||
        position.isClosing) {
      notifier.setStatus(
        'La posición ${position.symbol} ya está en proceso de venta.',
      );
      return;
    }
    final autoState = ref.read(autoInvestProvider);
    final walletAddress = autoState.walletAddress;
    if (walletAddress == null) {
      notifier.setStatus(
        'Wallet no conectada; no se puede vender ${position.symbol}.',
      );
      return;
    }
    if (!wallet.isAvailable) {
      notifier.setStatus(
        'Wallet no disponible para vender ${position.symbol}.',
      );
      return;
    }

    _positionsSelling.add(position.entrySignature);
    notifier.setPositionClosing(position.entrySignature, true);

    try {
      final autoState = ref.read(autoInvestProvider);
      final walletAddress = autoState.walletAddress;
      final preBalanceFuture = walletAddress == null
          ? null
          : wallet.getWalletBalance(walletAddress);
      final priceFuture = priceService.fetchQuote(position.mint);
      final signature = switch (position.executionMode) {
        AutoInvestExecutionMode.jupiter => await _executeSellViaJupiter(
          autoState,
          position,
          tokenAmount,
        ),
        AutoInvestExecutionMode.pumpPortal => await _executeSellViaPumpPortal(
          autoState,
          position,
          tokenAmount,
        ),
      };
      double expectedSol = position.currentValueSol ?? position.entrySol;
      try {
        final quote = await priceFuture;
        expectedSol = tokenAmount * quote.priceSol;
      } catch (_) {
        // Mantener el fallback cuando no haya quote disponible al instante.
      }
      double? preBalance;
      if (preBalanceFuture != null) {
        try {
          preBalance = await preBalanceFuture;
        } catch (_) {
          preBalance = null;
        }
      }
      notifier.recordExecution(
        ExecutionRecord(
          mint: position.mint,
          symbol: position.symbol,
          solAmount: expectedSol,
          side: 'sell',
          txSignature: signature,
          executedAt: DateTime.now(),
        ),
      );
      if (reason != null) {
        notifier.setStatus(
          'Venta automática de ${position.symbol} por ${reason.label.toLowerCase()}.',
        );
      } else {
        notifier.setStatus('Venta enviada para ${position.symbol}.');
      }
      // Registro de auditoría preliminar de venta (esperado)
      unawaited(
        ref
            .read(transactionAuditLoggerProvider)
            .logSellFromPosition(
              position: position,
              signature: signature,
              expectedExitSol: expectedSol,
              reason: reason,
            ),
      );
      unawaited(
        _trackSellConfirmation(
          signature: signature,
          position: position,
          realizedSol: expectedSol > 0 ? expectedSol : position.entrySol,
          preBalanceSol: preBalance,
        ),
      );
    } catch (error) {
      _positionsSelling.remove(position.entrySignature);
      notifier.setPositionClosing(position.entrySignature, false);
      notifier.setStatus('Venta falló (${position.symbol}): $error');
    }
  }

  Future<String> _executeSellViaPumpPortal(
    AutoInvestState autoState,
    OpenPosition position,
    double tokenAmount,
  ) async {
    final base64Tx = await pumpPortal.buildTradeTransaction(
      action: 'sell',
      publicKey: autoState.walletAddress!,
      mint: position.mint,
      amount: _formatAmount(tokenAmount),
      denominatedInSol: false,
      slippagePercent: autoState.pumpSlippagePercent,
      priorityFeeSol: autoState.pumpPriorityFeeSol,
      pool: autoState.pumpPool,
    );
    return wallet.signAndSendBase64(base64Tx);
  }

  Future<String> _executeSellViaJupiter(
    AutoInvestState autoState,
    OpenPosition position,
    double tokenAmount,
  ) async {
    int decimals;
    try {
      decimals = await wallet.getMintDecimals(position.mint);
    } catch (_) {
      decimals = 6;
    }
    final amountLamports = math.max(
      1,
      (tokenAmount * math.pow(10, decimals)).floor(),
    );
    final quote = await jupiter.fetchQuote(
      inputMint: position.mint,
      outputMint: JupiterSwapService.solMint,
      amountLamports: amountLamports,
    );
    final swap = await jupiter.swap(
      route: quote.route,
      userPublicKey: autoState.walletAddress!,
    );
    return wallet.signAndSendBase64(swap.swapTransaction);
  }

  Future<void> _trackConfirmation(
    String signature,
    String symbol,
    String mint,
  ) async {
    try {
      await wallet.waitForConfirmation(signature);
      ref
          .read(autoInvestProvider.notifier)
          .updateExecutionStatus(signature, status: 'confirmed');
      final owner = ref.read(autoInvestProvider).walletAddress;
      if (owner != null) {
        try {
          final amount = await wallet.readTokenAmountFromTransaction(
            signature: signature,
            owner: owner,
            mint: mint,
          );
          if (amount != null && amount > 0) {
            ref
                .read(autoInvestProvider.notifier)
                .updatePositionAmount(signature, amount);
          }
        } catch (error) {
          ref
              .read(autoInvestProvider.notifier)
              .setStatus('No se pudo leer el fill ($symbol): $error');
        }
      }
    } catch (error) {
      final notifier = ref.read(autoInvestProvider.notifier);
      notifier.updateExecutionStatus(
        signature,
        status: 'failed',
        errorMessage: error.toString(),
      );
      notifier.setStatus('Orden fall� ($symbol): $error');
      notifier.removePosition(signature, refundBudget: true);
      _recentMints.remove(mint);
    }
  }

  Future<void> _trackSellConfirmation({
    required String signature,
    required OpenPosition position,
    required double realizedSol,
    double? preBalanceSol,
  }) async {
    try {
      await wallet.waitForConfirmation(signature);
      ref
          .read(autoInvestProvider.notifier)
          .updateExecutionStatus(signature, status: 'confirmed');
      double? exitFeeSol;
      final owner = ref.read(autoInvestProvider).walletAddress;
      if (owner != null && preBalanceSol != null) {
        double? post;
        try {
          post = await wallet.getWalletBalance(owner);
        } catch (_) {
          post = null;
        }
        if (post != null) {
          final actualDelta = post - preBalanceSol;
          final expectedDelta = realizedSol;
          exitFeeSol = (expectedDelta - actualDelta).abs();
        }
      }
      ref
          .read(autoInvestProvider.notifier)
          .completePositionSale(
            position: position,
            sellSignature: signature,
            realizedSol: realizedSol,
            exitFeeSol: exitFeeSol,
          );
      // Registro de auditoría confirmado con PnL cuando sea posible
      final pnl = realizedSol - position.entrySol;
      final pnlPct = position.entrySol == 0
          ? null
          : (pnl / position.entrySol) * 100.0;
      unawaited(
        ref
            .read(transactionAuditLoggerProvider)
            .logSellFromPosition(
              position: position,
              signature: signature,
              expectedExitSol: realizedSol,
              realizedExitSol: realizedSol,
              pnlSol: pnl,
              pnlPercent: pnlPct,
            ),
      );
    } catch (error) {
      ref
          .read(autoInvestProvider.notifier)
          .updateExecutionStatus(
            signature,
            status: 'failed',
            errorMessage: error.toString(),
          );
      ref
          .read(autoInvestProvider.notifier)
          .setPositionClosing(position.entrySignature, false);
      ref
          .read(autoInvestProvider.notifier)
          .setStatus('Venta falló (${position.symbol}): $error');
    } finally {
      _positionsSelling.remove(position.entrySignature);
    }
  }
}

class _ScanReport {
  const _ScanReport({
    required this.total,
    required this.eligible,
    required this.filteredByMarketCap,
    required this.filteredByReplies,
    required this.filteredByAge,
    required this.filteredByHeld,
    required this.filteredByCooldown,
    this.candidate,
  });

  final int total;
  final int eligible;
  final int filteredByMarketCap;
  final int filteredByReplies;
  final int filteredByAge;
  final int filteredByHeld;
  final int filteredByCooldown;
  final FeaturedCoin? candidate;

  bool get hasCandidate => candidate != null;
}

final autoInvestExecutorProvider = Provider<AutoInvestExecutor>((ref) {
  final executor = AutoInvestExecutor(
    ref,
    ref.watch(jupiterSwapServiceProvider),
    ref.watch(walletExecutionServiceProvider),
    ref.watch(pumpPortalTradeServiceProvider),
    ref.watch(pumpFunPriceServiceProvider),
  );
  executor.init();
  return executor;
});
