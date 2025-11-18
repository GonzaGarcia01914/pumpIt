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
const _tokenRefreshCooldown = Duration(seconds: 10);

const _jupiterMaxLamports = 5000000000;
const _jupiterMaxSol = _jupiterMaxLamports / _lamportsPerSol;
const _rentExemptionBufferSol = 0.003;
const _walletBalanceThrottle = Duration(minutes: 1);
const _walletInsufficientRetryDelay = Duration(minutes: 1);
const _autoSellRetryDelay = Duration(seconds: 5);
const _scheduleCheckDebounce = Duration(milliseconds: 200);

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
  bool _rerunPending = false;
  final Map<String, DateTime> _recentMints = {};
  final Map<String, _PendingBuy> _pendingBuys = {};
  final Set<String> _pendingMints = {};
  final Set<String> _positionsSelling = {};
  final Map<String, DateTime> _tokenAmountRequests = {};
  final Set<String> _pendingAutoSellRetries = {};
  Timer? _scheduledCheck;
  Timer? _walletRetryTimer;
  DateTime? _lastWalletBalanceCheck;
  double? _lastWalletBalanceSol;
  DateTime? _walletInsufficientUntil;
  String? _lastWalletWarning;

  void init() {
    ref.listen<AutoInvestState>(autoInvestProvider, (previous, next) {
      final becameEnabled =
          (previous == null || !previous.isEnabled) && next.isEnabled;
      final walletJustConnected =
          previous?.walletAddress == null && next.walletAddress != null;
      if (becameEnabled || walletJustConnected) {
        _resetWalletBalanceCache();
      }
      if (!_isRunnableState(next)) {
        _cancelPendingCheck();
        _cancelWalletRetryTimer();
        return;
      }
      final shouldTrigger = previous == null
          ? true
          : _didRelevantStateChange(previous, next);
      if (!shouldTrigger) {
        return;
      }
      final immediate = becameEnabled || walletJustConnected;
      _scheduleCheck(immediate: immediate);
    }, fireImmediately: true);
    ref.listen<FeaturedCoinState>(featuredCoinProvider, (_, __) {
      if (!_shouldAttemptSchedule()) {
        return;
      }
      _scheduleCheck();
    });
  }

  void _scheduleCheck({bool immediate = false}) {
    if (!_shouldAttemptSchedule()) {
      if (immediate) {
        _cancelPendingCheck();
      }
      return;
    }
    if (_isRunning && !immediate) {
      _rerunPending = true;
      return;
    }
    if (immediate) {
      _cancelPendingCheck();
      _runScheduledCheck();
      return;
    }
    if (_scheduledCheck != null) {
      return;
    }
    _scheduledCheck = Timer(_scheduleCheckDebounce, () {
      _scheduledCheck = null;
      _runScheduledCheck();
    });
  }

  void _runScheduledCheck() {
    final autoState = ref.read(autoInvestProvider);
    _cleanupFailedEntries(autoState);
    if (!autoState.isEnabled || autoState.walletAddress == null) {
      return;
    }
    if (!wallet.isAvailable) {
      return;
    }
    if (_isRunning) {
      _rerunPending = true;
      return;
    }
    _isRunning = true;
    Future(() async {
      try {
        await _evaluate();
      } catch (error, stackTrace) {
        ref
            .read(autoInvestProvider.notifier)
            .setStatus('AutoInvest falló: $error');
        if (kDebugMode) {
          debugPrint('AutoInvestExecutor _evaluate error: $error');
          debugPrintStack(stackTrace: stackTrace);
        }
      } finally {
        _isRunning = false;
        if (_rerunPending) {
          _rerunPending = false;
          _scheduleCheck(immediate: true);
        }
      }
    });
  }

  bool _shouldAttemptSchedule() {
    final state = ref.read(autoInvestProvider);
    if (!_isRunnableState(state)) {
      return false;
    }
    final until = _walletInsufficientUntil;
    if (until != null && DateTime.now().isBefore(until)) {
      return false;
    }
    return true;
  }

  bool _isRunnableState(AutoInvestState state) =>
      state.isEnabled && state.walletAddress != null;

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

    var requestedLamports = (autoState.perCoinBudgetSol * _lamportsPerSol)
        .round();
    if (requestedLamports < 1) {
      requestedLamports = 1;
    }
    if (autoState.executionMode == AutoInvestExecutionMode.jupiter &&
        requestedLamports > _jupiterMaxLamports) {
      ref
          .read(autoInvestProvider.notifier)
          .setStatus(
            'Presupuesto por meme ('
            '${autoState.perCoinBudgetSol.toStringAsFixed(3)} SOL) supera el l�mite de '
            '${_jupiterMaxSol.toStringAsFixed(2)} SOL permitido por Jupiter. '
            'Reduce el presupuesto por meme a ${_jupiterMaxSol.toStringAsFixed(2)} SOL o menos.',
          );
      return;
    }
    final lamports = math.max(1, requestedLamports);
    final entrySolUsed =
        autoState.executionMode == AutoInvestExecutionMode.jupiter
        ? lamports / _lamportsPerSol
        : autoState.perCoinBudgetSol;
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

    final totalRequiredSol = _totalWalletRequirement(autoState, entrySolUsed);
    final hasWalletSol = await _hasEnoughWalletSol(
      autoState: autoState,
      entrySol: entrySolUsed,
      totalRequiredSol: totalRequiredSol,
    );
    if (!hasWalletSol) {
      return;
    }

    notifier.setStatus(
      autoState.executionMode == AutoInvestExecutionMode.jupiter
          ? 'Preparando compra automática de ${candidate.symbol} (${entrySolUsed.toStringAsFixed(4)} SOL) vía Jupiter.'
          : 'Preparando compra automática de ${candidate.symbol} (${entrySolUsed.toStringAsFixed(4)} SOL) vía PumpPortal.',
    );
    var budgetReserved = false;
    String? pendingSignature;
    try {
      notifier.reserveBudgetForEntry(entrySolUsed);
      budgetReserved = true;
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
      pendingSignature = signature;
      final pending = _PendingBuy(
        mint: candidate.mint,
        symbol: candidate.symbol,
        solAmount: entrySolUsed,
        executionMode: autoState.executionMode,
      );
      _pendingBuys[signature] = pending;
      _pendingMints.add(candidate.mint);
      // Registro de auditoría (CSV) para compras
      unawaited(
        ref
            .read(transactionAuditLoggerProvider)
            .logBuyFromFeatured(
              coin: candidate,
              signature: signature,
              entrySol: entrySolUsed,
              mode: autoState.executionMode,
              entryPriceSol: pumpQuote.priceSol,
            ),
      );
      notifier.recordExecution(
        ExecutionRecord(
          mint: candidate.mint,
          symbol: candidate.symbol,
          solAmount: entrySolUsed,
          side: 'buy',
          txSignature: signature,
          executedAt: DateTime.now(),
        ),
      );
      unawaited(
        _trackConfirmation(signature, candidate.symbol, candidate.mint),
      );
    } catch (error) {
      if (pendingSignature != null) {
        final pending = _consumePendingBuy(pendingSignature);
        if (pending != null) {
          notifier.releaseBudgetReservation(pending.solAmount);
          _recentMints.remove(pending.mint);
        }
      } else if (budgetReserved) {
        notifier.releaseBudgetReservation(entrySolUsed);
      }
      notifier.recordExecutionError(candidate.symbol, error.toString());
    }
  }

  FeaturedCoin? _pickManualCandidate(AutoInvestState autoState) {
    // Prefer manual mints that are not recently attempted and not already held
    final heldMints = {for (final p in autoState.positions) p.mint};
    for (final mint in autoState.manualMints) {
      final m = mint.trim();
      if (m.isEmpty) continue;
      if (_isMintBlocked(m)) continue;
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

  bool _isMintBlocked(String mint) =>
      _recentMints.containsKey(mint) || _pendingMints.contains(mint);

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
      if (_isMintBlocked(coin.mint)) {
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

  double _totalWalletRequirement(AutoInvestState autoState, double entrySol) {
    final buffer = autoState.executionMode == AutoInvestExecutionMode.pumpPortal
        ? autoState.pumpPriorityFeeSol + _rentExemptionBufferSol
        : _rentExemptionBufferSol;
    return entrySol + buffer;
  }

  Future<bool> _hasEnoughWalletSol({
    required AutoInvestState autoState,
    required double entrySol,
    required double totalRequiredSol,
  }) async {
    _syncWalletBalanceSnapshot(autoState);
    final walletAddress = autoState.walletAddress;
    if (walletAddress == null) {
      return false;
    }
    final now = DateTime.now();
    final cachedBalance = _lastWalletBalanceSol;
    final lastCheck = _lastWalletBalanceCheck;
    final hasFreshCache =
        cachedBalance != null &&
        lastCheck != null &&
        now.difference(lastCheck) <= _walletBalanceThrottle;
    if (hasFreshCache && cachedBalance >= totalRequiredSol) {
      _lastWalletWarning = null;
      _walletInsufficientUntil = null;
      return true;
    }
    if (_walletInsufficientUntil != null &&
        now.isBefore(_walletInsufficientUntil!)) {
      return false;
    }
    double? balance;
    if (hasFreshCache) {
      balance = cachedBalance;
    } else {
      balance = await _readWalletBalance(walletAddress);
    }
    if (balance == null) {
      _walletInsufficientUntil = now.add(_walletInsufficientRetryDelay);
      _scheduleWalletRetry(_walletInsufficientUntil!);
      final message =
          'No se pudo leer el saldo de la wallet; se cancela la entrada automática.';
      if (_lastWalletWarning != message) {
        ref.read(autoInvestProvider.notifier).setStatus(message);
        _lastWalletWarning = message;
      }
      return false;
    }
    if (balance >= totalRequiredSol) {
      _lastWalletWarning = null;
      _walletInsufficientUntil = null;
      _lastWalletBalanceSol = balance;
      return true;
    }
    return _handleInsufficientWallet(
      balance: balance,
      entrySol: entrySol,
      totalRequiredSol: totalRequiredSol,
      now: now,
    );
  }

  Future<double?> _readWalletBalance(String walletAddress) async {
    _lastWalletBalanceCheck = DateTime.now();
    try {
      final balance = await wallet.getWalletBalance(walletAddress);
      if (balance != null) {
        _lastWalletBalanceSol = balance;
        return balance;
      }
    } catch (_) {
      // Ignorar y reutilizar la instantánea anterior
    }
    return _lastWalletBalanceSol;
  }

  bool _handleInsufficientWallet({
    required double balance,
    required double entrySol,
    required double totalRequiredSol,
    required DateTime now,
  }) {
    _walletInsufficientUntil = now.add(_walletInsufficientRetryDelay);
    _scheduleWalletRetry(_walletInsufficientUntil!);
    _lastWalletBalanceSol = balance;
    final message =
        'Saldo disponible (${balance.toStringAsFixed(4)} SOL) insuficiente para una nueva entrada '
        'de ${entrySol.toStringAsFixed(4)} SOL (se requieren ~${totalRequiredSol.toStringAsFixed(4)} SOL incluyendo fees).';
    if (_lastWalletWarning != message) {
      ref.read(autoInvestProvider.notifier).setStatus(message);
      _lastWalletWarning = message;
    }
    return false;
  }

  void _syncWalletBalanceSnapshot(AutoInvestState state) {
    final updatedAt = state.walletBalanceUpdatedAt;
    if (updatedAt == null) return;
    if (_lastWalletBalanceCheck == null ||
        updatedAt.isAfter(_lastWalletBalanceCheck!)) {
      _lastWalletBalanceCheck = updatedAt;
      _lastWalletBalanceSol = state.walletBalanceSol;
      _walletInsufficientUntil = null;
      _lastWalletWarning = null;
    }
  }

  void _resetWalletBalanceCache() {
    _lastWalletBalanceCheck = null;
    _lastWalletBalanceSol = null;
    _walletInsufficientUntil = null;
    _lastWalletWarning = null;
    _cancelWalletRetryTimer();
  }

  void _cancelPendingCheck() {
    _scheduledCheck?.cancel();
    _scheduledCheck = null;
  }

  void _cancelWalletRetryTimer() {
    _walletRetryTimer?.cancel();
    _walletRetryTimer = null;
  }

  void _scheduleWalletRetry(DateTime until) {
    _walletRetryTimer?.cancel();
    final delay = until.difference(DateTime.now());
    if (delay.isNegative || delay == Duration.zero) {
      _walletRetryTimer = null;
      _scheduleCheck(immediate: true);
      return;
    }
    _walletRetryTimer = Timer(delay, () {
      _walletRetryTimer = null;
      _scheduleCheck(immediate: true);
    });
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

  _PendingBuy? _consumePendingBuy(String signature) {
    final pending = _pendingBuys.remove(signature);
    if (pending != null) {
      _pendingMints.remove(pending.mint);
    }
    return pending;
  }

  _PendingBuy? _fallbackPendingBuyFromExecutions({
    required String signature,
    required String mint,
    required String symbol,
  }) {
    final state = ref.read(autoInvestProvider);
    for (final execution in state.executions) {
      if (execution.txSignature != signature || execution.side != 'buy') {
        continue;
      }
      final resolvedMint = execution.mint.isNotEmpty ? execution.mint : mint;
      final resolvedSymbol = execution.symbol.isNotEmpty
          ? execution.symbol
          : symbol;
      return _PendingBuy(
        mint: resolvedMint,
        symbol: resolvedSymbol,
        solAmount: execution.solAmount,
        executionMode: state.executionMode,
      );
    }
    return null;
  }

  Future<double?> ensurePositionTokenAmount(
    OpenPosition position, {
    bool force = false,
  }) async {
    if (position.tokenAmount != null && position.tokenAmount! > 0) {
      return position.tokenAmount;
    }
    final last = _tokenAmountRequests[position.entrySignature];
    if (!force && last != null) {
      final elapsed = DateTime.now().difference(last);
      if (elapsed < _tokenRefreshCooldown) {
        return null;
      }
    }
    _tokenAmountRequests[position.entrySignature] = DateTime.now();
    final refreshed = await _refreshPositionTokenAmount(position);
    if (refreshed != null && refreshed > 0) {
      _tokenAmountRequests.remove(position.entrySignature);
    }
    return refreshed;
  }

  Future<double?> _refreshPositionTokenAmount(OpenPosition position) async {
    final owner = ref.read(autoInvestProvider).walletAddress;
    if (owner == null) return null;
    double? amount;
    try {
      amount = await wallet.readTokenAmountFromTransaction(
        signature: position.entrySignature,
        owner: owner,
        mint: position.mint,
      );
    } catch (_) {
      amount = null;
    }
    if (amount == null || amount <= 0) {
      try {
        amount = await wallet.readTokenBalance(
          owner: owner,
          mint: position.mint,
        );
      } catch (_) {
        amount = null;
      }
    }
    if (amount != null && amount > 0) {
      ref
          .read(autoInvestProvider.notifier)
          .updatePositionAmount(position.entrySignature, amount);
    }
    return amount;
  }

  Future<double?> _forceReadTokenBalance(OpenPosition position) async {
    final owner = ref.read(autoInvestProvider).walletAddress;
    if (owner == null) return null;
    try {
      return await wallet.readTokenBalance(owner: owner, mint: position.mint);
    } catch (_) {
      return null;
    }
  }

  OpenPosition? _findPosition(String entrySignature) {
    final state = ref.read(autoInvestProvider);
    for (final current in state.positions) {
      if (current.entrySignature == entrySignature) {
        return current;
      }
    }
    return null;
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
    bool ignoreRetryThrottle = false,
  }) async {
    final notifier = ref.read(autoInvestProvider.notifier);
    if (reason != null &&
        !ignoreRetryThrottle &&
        _pendingAutoSellRetries.contains(position.entrySignature)) {
      return;
    }
    var tokenAmount = position.tokenAmount;
    var activePosition = position;
    if (tokenAmount == null || tokenAmount <= 0) {
      tokenAmount = await ensurePositionTokenAmount(position, force: true);
      if (tokenAmount == null || tokenAmount <= 0) {
        tokenAmount = await _forceReadTokenBalance(position);
        if (tokenAmount != null && tokenAmount > 0) {
          ref
              .read(autoInvestProvider.notifier)
              .updatePositionAmount(position.entrySignature, tokenAmount);
        }
      }
      if (tokenAmount == null || tokenAmount <= 0) {
        notifier.setStatus(
          'No hay tokens confirmados para vender en ${position.symbol}.',
        );
        return;
      }
      activePosition =
          _findPosition(position.entrySignature) ??
          position.copyWith(tokenAmount: tokenAmount);
    }
    if (_positionsSelling.contains(activePosition.entrySignature) ||
        activePosition.isClosing) {
      notifier.setStatus(
        'La posici?n ${activePosition.symbol} ya est? en proceso de venta.',
      );
      return;
    }
    final autoState = ref.read(autoInvestProvider);
    final walletAddress = autoState.walletAddress;
    if (walletAddress == null) {
      notifier.setStatus(
        'Wallet no conectada; no se puede vender ${activePosition.symbol}.',
      );
      return;
    }
    if (!wallet.isAvailable) {
      notifier.setStatus(
        'Wallet no disponible para vender ${activePosition.symbol}.',
      );
      return;
    }

    _positionsSelling.add(activePosition.entrySignature);
    notifier.setPositionClosing(activePosition.entrySignature, true);

    try {
      final autoState = ref.read(autoInvestProvider);
      final walletAddress = autoState.walletAddress;
      final preBalanceFuture = walletAddress == null
          ? null
          : wallet.getWalletBalance(walletAddress);
      final priceFuture = priceService.fetchQuote(activePosition.mint);
      PumpFunQuote? pumpQuote;
      try {
        pumpQuote = await priceFuture;
      } catch (_) {
        pumpQuote = null;
      }
      final signature =
          await (_shouldSellViaJupiter(
                position: activePosition,
                quote: pumpQuote,
              )
              ? _executeSellViaJupiter(autoState, activePosition, tokenAmount)
              : _executeSellViaPumpPortal(
                  autoState,
                  activePosition,
                  tokenAmount,
                ));
      double expectedSol = pumpQuote != null
          ? tokenAmount * pumpQuote.priceSol
          : activePosition.currentValueSol ?? activePosition.entrySol;
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
          mint: activePosition.mint,
          symbol: activePosition.symbol,
          solAmount: expectedSol,
          side: 'sell',
          txSignature: signature,
          executedAt: DateTime.now(),
        ),
      );
      if (reason != null) {
        notifier.setStatus(
          'Venta autom?tica de ${activePosition.symbol} por ${reason.label.toLowerCase()}.',
        );
      } else {
        notifier.setStatus('Venta enviada para ${activePosition.symbol}.');
      }
      // Registro de auditor?a preliminar de venta (esperado)
      unawaited(
        ref
            .read(transactionAuditLoggerProvider)
            .logSellFromPosition(
              position: activePosition,
              signature: signature,
              expectedExitSol: expectedSol,
              reason: reason,
            ),
      );
      unawaited(
        _trackSellConfirmation(
          signature: signature,
          position: activePosition,
          expectedSol: expectedSol > 0 ? expectedSol : activePosition.entrySol,
          preBalanceSol: preBalance,
        ),
      );
    } catch (error) {
      _positionsSelling.remove(activePosition.entrySignature);
      notifier.setPositionClosing(activePosition.entrySignature, false);
      notifier.setStatus('Venta falló (${activePosition.symbol}): $error');
      if (reason != null) {
        unawaited(
          _scheduleAutoSellRetry(position: activePosition, reason: reason),
        );
      }
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

  bool _shouldSellViaJupiter({
    required OpenPosition position,
    required PumpFunQuote? quote,
  }) {
    if (position.executionMode == AutoInvestExecutionMode.jupiter) {
      return true;
    }
    if (quote == null) {
      return false;
    }
    return quote.isGraduated;
  }

  Future<void> _scheduleAutoSellRetry({
    required OpenPosition position,
    required PositionAlertType reason,
  }) async {
    if (_pendingAutoSellRetries.contains(position.entrySignature)) {
      return;
    }
    _pendingAutoSellRetries.add(position.entrySignature);
    try {
      await Future.delayed(_autoSellRetryDelay);
    } finally {
      _pendingAutoSellRetries.remove(position.entrySignature);
    }
    final refreshed = _findPosition(position.entrySignature);
    if (refreshed == null || refreshed.isClosing) {
      return;
    }
    final shouldRetry = await _shouldRetryAutoSell(refreshed, reason);
    if (!shouldRetry) {
      ref
          .read(autoInvestProvider.notifier)
          .setStatus(
            'Venta reintentada cancelada en ${refreshed.symbol}; ya no cumple ${reason.label.toLowerCase()}.',
          );
      return;
    }
    await sellPosition(refreshed, reason: reason, ignoreRetryThrottle: true);
  }

  Future<bool> _shouldRetryAutoSell(
    OpenPosition position,
    PositionAlertType reason,
  ) async {
    double? tokenAmount = position.tokenAmount;
    if (tokenAmount == null || tokenAmount <= 0) {
      tokenAmount = await ensurePositionTokenAmount(position, force: true);
      tokenAmount ??= await _forceReadTokenBalance(position);
    }
    if (tokenAmount == null || tokenAmount <= 0) {
      return false;
    }
    try {
      final quote = await priceService.fetchQuote(position.mint);
      if (quote.priceSol <= 0) {
        return false;
      }
      final currentValue = tokenAmount * quote.priceSol;
      if (position.entrySol <= 0) {
        return false;
      }
      final pnlPercent =
          ((currentValue - position.entrySol) / position.entrySol) * 100.0;
      final state = ref.read(autoInvestProvider);
      if (reason == PositionAlertType.takeProfit) {
        return state.takeProfitPercent > 0 &&
            pnlPercent >= state.takeProfitPercent;
      }
      return state.stopLossPercent > 0 && pnlPercent <= -state.stopLossPercent;
    } catch (error) {
      ref
          .read(autoInvestProvider.notifier)
          .setStatus(
            'No se pudo verificar reintento de venta (${position.symbol}): $error',
          );
      return false;
    }
  }

  Future<void> _trackConfirmation(
    String signature,
    String symbol,
    String mint,
  ) async {
    try {
      await wallet.waitForConfirmation(signature);
      final notifier = ref.read(autoInvestProvider.notifier);
      notifier.updateExecutionStatus(signature, status: 'confirmed');
      final consumed = _consumePendingBuy(signature);
      final pending =
          consumed ??
          _fallbackPendingBuyFromExecutions(
            signature: signature,
            mint: mint,
            symbol: symbol,
          );
      if (pending != null) {
        notifier.recordPositionEntry(
          mint: pending.mint,
          symbol: pending.symbol,
          solAmount: pending.solAmount,
          txSignature: signature,
          executionMode: pending.executionMode,
          subtractBudget: consumed == null,
        );
        _recentMints[pending.mint] = DateTime.now();
      } else {
        _recentMints[mint] = DateTime.now();
      }
      final owner = ref.read(autoInvestProvider).walletAddress;
      if (owner != null) {
        double? amount;
        try {
          amount = await wallet.readTokenAmountFromTransaction(
            signature: signature,
            owner: owner,
            mint: mint,
          );
        } catch (error) {
          ref
              .read(autoInvestProvider.notifier)
              .setStatus('No se pudo leer el fill ($symbol): $error');
        }
        if (amount == null || amount <= 0) {
          try {
            amount = await wallet.readTokenBalance(owner: owner, mint: mint);
          } catch (error) {
            ref
                .read(autoInvestProvider.notifier)
                .setStatus(
                  'No se pudo leer el balance actual ($symbol): $error',
                );
          }
        }
        if (amount != null && amount > 0) {
          ref
              .read(autoInvestProvider.notifier)
              .updatePositionAmount(signature, amount);
        }
      }
    } catch (error) {
      final notifier = ref.read(autoInvestProvider.notifier);
      notifier.updateExecutionStatus(
        signature,
        status: 'failed',
        errorMessage: error.toString(),
      );
      notifier.setStatus('Orden fall??? ($symbol): $error');
      final pending = _consumePendingBuy(signature);
      if (pending != null) {
        notifier.releaseBudgetReservation(pending.solAmount);
        _recentMints.remove(pending.mint);
      } else {
        notifier.removePosition(signature, refundBudget: true);
        _recentMints.remove(mint);
      }
    }
  }

  Future<void> _trackSellConfirmation({
    required String signature,
    required OpenPosition position,
    required double expectedSol,
    double? preBalanceSol,
  }) async {
    try {
      await wallet.waitForConfirmation(signature);
      final notifier = ref.read(autoInvestProvider.notifier);
      notifier.updateExecutionStatus(signature, status: 'confirmed');
      final realizedSol = await _determineRealizedSol(
        signature: signature,
        expectedSol: expectedSol,
        preBalanceSol: preBalanceSol,
      );
      final exitFeeSol = realizedSol < expectedSol
          ? (expectedSol - realizedSol)
          : null;
      notifier.completePositionSale(
        position: position,
        sellSignature: signature,
        realizedSol: realizedSol,
        exitFeeSol: exitFeeSol,
      );
      // Registro de auditor�a confirmado con PnL cuando sea posible
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
              expectedExitSol: expectedSol,
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
          .setStatus('Venta fall� (${position.symbol}): $error');
    } finally {
      _positionsSelling.remove(position.entrySignature);
      _resetWalletBalanceCache();
    }
  }

  Future<double> _determineRealizedSol({
    required String signature,
    required double expectedSol,
    double? preBalanceSol,
  }) async {
    final owner = ref.read(autoInvestProvider).walletAddress;
    if (owner == null) {
      throw Exception('Wallet sin propietario para leer salida.');
    }
    final solDelta = await _retryReadSolDelta(
      signature: signature,
      owner: owner,
    );
    if (solDelta != null) {
      return solDelta;
    }
    if (preBalanceSol != null) {
      final balanceDelta = await _retryReadBalanceDelta(
        owner: owner,
        preBalanceSol: preBalanceSol,
      );
      if (balanceDelta != null) {
        return balanceDelta;
      }
    }
    throw Exception(
      'No se pudo determinar la salida real (expected ${expectedSol.toStringAsFixed(4)} SOL).',
    );
  }

  Future<double?> _retryReadSolDelta({
    required String signature,
    required String owner,
    int maxAttempts = 5,
  }) async {
    Object? lastError;
    for (var attempt = 0; attempt < maxAttempts; attempt++) {
      try {
        final delta = await wallet.readSolChangeFromTransaction(
          signature: signature,
          owner: owner,
        );
        if (delta != null) {
          return delta;
        }
      } catch (error) {
        lastError = error;
      }
      await Future.delayed(Duration(milliseconds: 300 * (attempt + 1)));
    }
    if (lastError != null) {
      ref
          .read(autoInvestProvider.notifier)
          .setStatus('No se pudo leer delta real de la venta: $lastError');
    }
    return null;
  }

  Future<double?> _retryReadBalanceDelta({
    required String owner,
    required double preBalanceSol,
    int maxAttempts = 3,
  }) async {
    for (var attempt = 0; attempt < maxAttempts; attempt++) {
      try {
        final post = await wallet.getWalletBalance(owner);
        if (post != null) {
          return post - preBalanceSol;
        }
      } catch (_) {
        // Ignorar y reintentar
      }
      await Future.delayed(const Duration(milliseconds: 400));
    }
    return null;
  }

  void dispose() {
    _cancelPendingCheck();
    _cancelWalletRetryTimer();
  }

  bool _didRelevantStateChange(AutoInvestState previous, AutoInvestState next) {
    if (previous.isEnabled != next.isEnabled) return true;
    if (previous.walletAddress != next.walletAddress) return true;
    if (previous.availableBudgetSol != next.availableBudgetSol) return true;
    if (previous.walletBalanceSol != next.walletBalanceSol) return true;
    if (previous.perCoinBudgetSol != next.perCoinBudgetSol) return true;
    if (previous.executionMode != next.executionMode) return true;
    if (previous.pumpSlippagePercent != next.pumpSlippagePercent) return true;
    if (previous.pumpPriorityFeeSol != next.pumpPriorityFeeSol) return true;
    if (previous.pumpPool != next.pumpPool) return true;
    if (previous.minMarketCap != next.minMarketCap) return true;
    if (previous.maxMarketCap != next.maxMarketCap) return true;
    if (previous.minReplies != next.minReplies) return true;
    if (previous.maxAgeHours != next.maxAgeHours) return true;
    if (previous.includeManualMints != next.includeManualMints) return true;
    if (!_manualMintsEqual(previous.manualMints, next.manualMints)) return true;
    return false;
  }

  bool _manualMintsEqual(List<String> a, List<String> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (_normalizeMint(a[i]) != _normalizeMint(b[i])) {
        return false;
      }
    }
    return true;
  }

  String _normalizeMint(String value) => value.trim().toLowerCase();
}

class _PendingBuy {
  const _PendingBuy({
    required this.mint,
    required this.symbol,
    required this.solAmount,
    required this.executionMode,
  });

  final String mint;
  final String symbol;
  final double solAmount;
  final AutoInvestExecutionMode executionMode;
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
  ref.onDispose(executor.dispose);
  return executor;
});
