import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../featured_coins/controller/featured_coin_notifier.dart';
import '../../featured_coins/models/featured_coin.dart';
import '../models/execution_record.dart';
import '../services/jupiter_swap_service.dart';
import '../services/phantom_wallet_service.dart';
import 'auto_invest_notifier.dart';

const _lamportsPerSol = 1000000000;

class AutoInvestExecutor {
  AutoInvestExecutor(this.ref, this.jupiter, this.wallet);

  final Ref ref;
  final JupiterSwapService jupiter;
  final PhantomWalletService wallet;

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
      ref.read(autoInvestProvider.notifier).setStatus('Phantom no disponible en este entorno.');
      return;
    }

    final coins = ref.read(featuredCoinProvider).coins;
    if (coins.isEmpty) return;

    _cleanupRecent();
    final candidate = _pickCandidate(coins, autoState);
    if (candidate == null) return;

    final lamports =
        (autoState.perCoinBudgetSol * _lamportsPerSol).round().clamp(1, 5000000000);
    ref.read(autoInvestProvider.notifier).setStatus(
          'Preparando compra automática de ${candidate.symbol} (${autoState.perCoinBudgetSol} SOL).',
        );
    try {
      final quote = await jupiter.fetchQuote(
        inputMint: JupiterSwapService.solMint,
        outputMint: candidate.mint,
        amountLamports: lamports,
      );
      final swap = await jupiter.swap(
        route: quote.route,
        userPublicKey: autoState.walletAddress!,
      );
      final signature = await wallet.signAndSendBase64(swap.swapTransaction);
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
      if (_recentMints.containsKey(coin.mint)) {
        continue;
      }
      return coin;
    }
    return null;
  }

  void _cleanupRecent() {
    final cutoff = DateTime.now().subtract(const Duration(minutes: 15));
    _recentMints.removeWhere((_, time) => time.isBefore(cutoff));
  }
}

final autoInvestExecutorProvider = Provider<AutoInvestExecutor>((ref) {
  final executor = AutoInvestExecutor(
    ref,
    ref.watch(jupiterSwapServiceProvider),
    ref.watch(phantomWalletServiceProvider),
  );
  executor.init();
  return executor;
});
