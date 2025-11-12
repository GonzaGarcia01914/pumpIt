import 'dart:async';
import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../featured_coins/controller/featured_coin_notifier.dart';
import '../../featured_coins/models/featured_coin.dart';
import '../models/execution_record.dart';
import '../services/jupiter_swap_service.dart';
import '../services/pump_portal_trade_service.dart';
import '../services/wallet_execution_service.dart';
import 'auto_invest_notifier.dart';

const _lamportsPerSol = 1000000000;

class AutoInvestExecutor {
  AutoInvestExecutor(this.ref, this.jupiter, this.wallet, this.pumpPortal);

  final Ref ref;
  final JupiterSwapService jupiter;
  final WalletExecutionService wallet;
  final PumpPortalTradeService pumpPortal;

  bool _isRunning = false;
  final Map<String, DateTime> _recentMints = {};

  void init() {
    ref.listen<AutoInvestState>(autoInvestProvider, (_, __) => _scheduleCheck());
    ref.listen<FeaturedCoinState>(featuredCoinProvider, (_, __) => _scheduleCheck());
  }

  void _scheduleCheck() {
    final autoState = ref.read(autoInvestProvider);
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
      ref.read(autoInvestProvider.notifier).setStatus(
            'Wallet no disponible. Verifica Phantom (web) o LOCAL_KEY_PATH (desktop).',
          );
      return;
    }

    final coins = ref.read(featuredCoinProvider).coins;
    if (coins.isEmpty) return;

    _cleanupRecent();
    final candidate = _pickCandidate(coins, autoState);
    if (candidate == null) return;

    final lamports =
        (autoState.perCoinBudgetSol * _lamportsPerSol).round().clamp(1, 5000000000);
    if (autoState.executionMode == AutoInvestExecutionMode.pumpPortal) {
      final minBudget = math.max(0.01, autoState.pumpPriorityFeeSol + 0.003);
      if (autoState.perCoinBudgetSol < minBudget) {
        ref.read(autoInvestProvider.notifier).setStatus(
          'Presupuesto por meme ('
          '${autoState.perCoinBudgetSol.toStringAsFixed(4)} SOL) demasiado bajo. Usa al menos '
          '${minBudget.toStringAsFixed(3)} SOL para cubrir ATA + priority fee.',
        );
        return;
      }
    }

    ref.read(autoInvestProvider.notifier).setStatus(
          autoState.executionMode == AutoInvestExecutionMode.jupiter
              ? 'Preparando compra automatica de ${candidate.symbol} (${autoState.perCoinBudgetSol} SOL) via Jupiter.'
              : 'Preparando compra automatica de ${candidate.symbol} (${autoState.perCoinBudgetSol} SOL) via PumpPortal.',
        );
    try {
      final signature = switch (autoState.executionMode) {
        AutoInvestExecutionMode.jupiter =>
            await _executeViaJupiter(autoState, candidate, lamports),
        AutoInvestExecutionMode.pumpPortal =>
            await _executeViaPumpPortal(autoState, candidate),
      };
      ref.read(autoInvestProvider.notifier).recordExecution(
            ExecutionRecord(
              mint: candidate.mint,
              symbol: candidate.symbol,
              solAmount: autoState.perCoinBudgetSol,
              side: 'buy',
              txSignature: signature,
              executedAt: DateTime.now(),
            ),
          );
      unawaited(_trackConfirmation(signature, candidate.symbol));
      _recentMints[candidate.mint] = DateTime.now();
    } catch (error) {
      ref.read(autoInvestProvider.notifier).recordExecutionError(
            candidate.symbol,
            error.toString(),
          );
      _recentMints[candidate.mint] = DateTime.now();
    }
  }

  FeaturedCoin? _pickCandidate(
    List<FeaturedCoin> coins,
    AutoInvestState autoState,
  ) {
    for (final coin in coins) {
      if (coin.usdMarketCap < autoState.minMarketCap ||
          coin.usdMarketCap > autoState.maxMarketCap) {
        continue;
      }
      if (autoState.executionMode == AutoInvestExecutionMode.pumpPortal) {
        if (!coin.isCurrentlyLive || coin.isComplete) {
          continue;
        }
      }
      if (_recentMints.containsKey(coin.mint)) {
        continue;
      }
      return coin;
    }
    return null;
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

  Future<void> _trackConfirmation(String signature, String symbol) async {
    try {
      await wallet.waitForConfirmation(signature);
      ref
          .read(autoInvestProvider.notifier)
          .updateExecutionStatus(signature, status: 'confirmed');
    } catch (error) {
      ref.read(autoInvestProvider.notifier).updateExecutionStatus(
            signature,
            status: 'failed',
            errorMessage: error.toString(),
          );
      ref.read(autoInvestProvider.notifier).setStatus(
            'Orden falló ($symbol): $error',
          );
    }
  }
}

final autoInvestExecutorProvider = Provider<AutoInvestExecutor>((ref) {
  final executor = AutoInvestExecutor(
    ref,
    ref.watch(jupiterSwapServiceProvider),
    ref.watch(walletExecutionServiceProvider),
    ref.watch(pumpPortalTradeServiceProvider),
  );
  executor.init();
  return executor;
});
