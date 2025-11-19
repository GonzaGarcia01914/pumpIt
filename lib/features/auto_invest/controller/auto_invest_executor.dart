import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../featured_coins/controller/featured_coin_notifier.dart';
import '../../featured_coins/models/featured_coin.dart';
import '../models/execution_record.dart';
import '../models/execution_mode.dart';
import '../models/position.dart';
import '../models/sale_level.dart';
import '../services/jupiter_swap_service.dart';
import '../services/pump_fun_price_service.dart';
import '../services/pump_portal_trade_service.dart';
import '../services/wallet_execution_service.dart';
import '../services/transaction_audit_logger.dart';
import '../services/helius_enhanced_api_service.dart';
import '../services/dynamic_priority_fee_service.dart';
import '../services/dynamic_slippage_service.dart';
import '../services/entry_timing_analyzer.dart';
import '../services/error_handler_service.dart';
import '../services/token_security_analyzer.dart';
import '../services/whale_tracker_service.dart';
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

    // ⚡ Verificar límites diarios antes de comprar
    if (!_checkDailyLimits(autoState, entrySolUsed, isBuy: true)) {
      return;
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

    // 🛡️ Verificar seguridad del token ANTES de comprar
    notifier.setStatus('Analizando seguridad de ${candidate.symbol}...');
    final isSafe = await _verifyTokenSecurityAsync(candidate);
    if (!isSafe) {
      // Token no es seguro, cancelar compra
      return;
    }

    // 🐋 Analizar actividad de whales/insiders ANTES de comprar
    final securityService = ref.read(tokenSecurityAnalyzerProvider);
    TokenSecurityScore? securityScore;
    try {
      securityScore = await securityService
          .analyzeToken(candidate.mint)
          .timeout(const Duration(seconds: 2));
    } catch (e) {
      // Si falla o timeout, continuar sin análisis de seguridad
      securityScore = null;
    }
    final creatorAddress = securityScore?.creatorAddress;

    notifier.setStatus(
      'Analizando actividad de whales en ${candidate.symbol}...',
    );
    final whaleAnalysis = await _analyzeWhaleActivity(
      mint: candidate.mint,
      creatorAddress: creatorAddress,
    );

    // 🐋 DECISIÓN BASADA EN ACTIVIDAD DE WHALES
    if (whaleAnalysis.recommendation == WhaleRecommendation.strongSell) {
      // Creator vendiendo o muchas ventas de whales grandes - NO COMPRAR
      final reason = whaleAnalysis.hasCreatorSells
          ? 'Creator está vendiendo'
          : 'Muchas ventas de whales grandes detectadas';
      notifier.setStatus(
        '⚠️ Cancelando compra de ${candidate.symbol}: $reason',
      );
      _recentMints[candidate.mint] = DateTime.now();
      return;
    }

    if (whaleAnalysis.recommendation == WhaleRecommendation.sell) {
      // Algunas ventas de whales - ADVERTENCIA pero continuar
      notifier.setStatus(
        '⚠️ Advertencia: Algunas ventas de whales detectadas en ${candidate.symbol}, pero continuando...',
      );
    }

    if (whaleAnalysis.recommendation == WhaleRecommendation.strongBuy) {
      // Whales grandes comprando - SEÑAL POSITIVA
      notifier.setStatus(
        '🐋 Señal positiva: Whales grandes comprando ${candidate.symbol}',
      );
    }

    // ⚡ CRÍTICO: Marcar mint como "en proceso" ANTES de intentar comprar
    // Esto evita que se intente comprar el mismo token múltiples veces simultáneamente
    _recentMints[candidate.mint] = DateTime.now();
    _pendingMints.add(candidate.mint);

    var budgetReserved = false;
    String? pendingSignature;
    try {
      notifier.reserveBudgetForEntry(entrySolUsed);
      budgetReserved = true;

      // ⚡ Precio de referencia con timeout para evitar bloqueos
      PumpFunQuote? pumpQuote;
      try {
        notifier.setStatus('Obteniendo precio para ${candidate.symbol}...');
        pumpQuote = await priceService
            .fetchQuote(candidate.mint)
            .timeout(
              const Duration(seconds: 10),
              onTimeout: () {
                throw TimeoutException(
                  'Timeout obteniendo precio para ${candidate!.symbol}',
                );
              },
            );
      } catch (e) {
        // Si falla obtener precio, continuar de todas formas (no es crítico)
        notifier.setStatus('Advertencia: No se pudo obtener precio: $e');
        pumpQuote = null;
      }

      // 📊 ANÁLISIS DE TIMING DE ENTRADA: Verificar si es buen momento para entrar
      if (pumpQuote != null) {
        final timingAnalyzer = ref.read(entryTimingAnalyzerProvider);
        final dynamicSlippageService = ref.read(dynamicSlippageServiceProvider);

        // Registrar precio actual para tracking de volatilidad
        dynamicSlippageService.recordPricePoint(
          candidate.mint,
          pumpQuote.priceSol,
        );

        // Registrar volumen desde la quote
        timingAnalyzer.recordVolumeFromQuote(candidate.mint, pumpQuote);

        notifier.setStatus(
          'Analizando timing de entrada para ${candidate.symbol}...',
        );
        EntryTimingAnalysis? timingAnalysis;
        try {
          timingAnalysis = await timingAnalyzer
              .analyzeEntryTiming(
                mint: candidate.mint,
                currentPrice: pumpQuote.priceSol,
                currentVolume: pumpQuote
                    .marketCapSol, // Usar market cap como proxy de volumen
                currentQuote: pumpQuote,
              )
              .timeout(const Duration(seconds: 3));
        } catch (e) {
          // Si falla o timeout, continuar sin análisis de timing
          timingAnalysis = null;
        }

        if (timingAnalysis != null) {
          if (!timingAnalysis.shouldEnter) {
            // No es buen momento para entrar
            final waitTime = timingAnalysis.recommendedWaitTime;
            if (waitTime != null && waitTime.inSeconds < 60) {
              // Esperar un poco y reintentar
              notifier.setStatus(
                '⏳ Esperando mejor timing para ${candidate.symbol}: ${timingAnalysis.reason} (esperando ${waitTime.inSeconds}s)',
              );
              await Future.delayed(waitTime);

              // Re-analizar después de esperar
              EntryTimingAnalysis? retryAnalysis;
              try {
                retryAnalysis = await timingAnalyzer
                    .analyzeEntryTiming(
                      mint: candidate.mint,
                      currentPrice: pumpQuote.priceSol,
                      currentVolume: pumpQuote.marketCapSol,
                      currentQuote: pumpQuote,
                    )
                    .timeout(const Duration(seconds: 2));
              } catch (e) {
                // Si falla, continuar con la compra
                retryAnalysis = null;
              }

              if (retryAnalysis != null && !retryAnalysis.shouldEnter) {
                // Aún no es buen momento, cancelar
                notifier.setStatus(
                  '❌ Cancelando compra de ${candidate.symbol}: ${retryAnalysis.reason}',
                );
                _recentMints[candidate.mint] = DateTime.now();
                return;
              }
            } else {
              // Espera muy larga o no recomendada, cancelar
              notifier.setStatus(
                '❌ Cancelando compra de ${candidate.symbol}: ${timingAnalysis.reason}',
              );
              _recentMints[candidate.mint] = DateTime.now();
              return;
            }
          } else {
            // Es buen momento para entrar
            notifier.setStatus(
              '✅ Buen timing para ${candidate.symbol} (score: ${timingAnalysis.entryScore.toStringAsFixed(1)}/100): ${timingAnalysis.reason}',
            );
          }
        }
      }

      notifier.setStatus(
        autoState.executionMode == AutoInvestExecutionMode.jupiter
            ? 'Preparando compra automática de ${candidate.symbol} (${entrySolUsed.toStringAsFixed(4)} SOL) vía Jupiter.'
            : 'Preparando compra automática de ${candidate.symbol} (${entrySolUsed.toStringAsFixed(4)} SOL) vía PumpPortal.',
      );

      // ⚡ Obtener blockhash fresco con timeout (opcional, no crítico)
      // Nota: PumpPortal/Jupiter obtienen el blockhash ellos mismos, así que esto es solo
      // para pre-calentar la conexión RPC. Si falla, no es crítico.
      try {
        // ignore: avoid_dynamic_calls
        await (wallet as dynamic).getLatestBlockhash().timeout(
          const Duration(seconds: 3), // ⚡ Reducido a 3s, no es crítico
          onTimeout: () {
            throw TimeoutException('Timeout obteniendo blockhash');
          },
        );
      } catch (e) {
        // Si falla obtener blockhash, continuar de todas formas
        // (PumpPortal/Jupiter pueden obtenerlo ellos mismos)
        // No mostrar advertencia para no spamear logs
      }

      // ⚡ Ejecutar compra con timeout total y logging detallado
      notifier.setStatus(
        'Construyendo transacción para ${candidate.symbol}...',
      );
      final signature =
          await (switch (autoState.executionMode) {
            AutoInvestExecutionMode.jupiter => _executeViaJupiter(
              autoState,
              candidate,
              lamports,
            ),
            AutoInvestExecutionMode.pumpPortal => _executeViaPumpPortal(
              autoState,
              candidate,
            ),
          }).timeout(
            const Duration(
              seconds: 30,
            ), // ⚡ Timeout total de 30s para toda la operación
            onTimeout: () {
              throw TimeoutException(
                'Timeout ejecutando compra de ${candidate!.symbol} después de 30s',
              );
            },
          );
      pendingSignature = signature;

      // ⚡ Log de éxito en envío
      notifier.setStatus(
        'Transacción de compra enviada para ${candidate.symbol} (sig: ${signature.substring(0, 8)}...)',
      );
      final pending = _PendingBuy(
        mint: candidate.mint,
        symbol: candidate.symbol,
        solAmount: entrySolUsed,
        executionMode: autoState.executionMode,
      );
      _pendingBuys[signature] = pending;
      // ⚡ _pendingMints ya fue agregado al inicio del proceso

      // ⚡ ACTUALIZACIÓN INMEDIATA: Agregar a posiciones abiertas inmediatamente
      // No esperar confirmación - la UI se actualiza instantáneamente
      notifier.recordPositionEntry(
        mint: candidate.mint,
        symbol: candidate.symbol,
        solAmount: entrySolUsed,
        txSignature: signature,
        executionMode: autoState.executionMode,
        subtractBudget: false, // Ya se reservó con reserveBudgetForEntry
      );

      // Registro de auditoría (CSV) para compras
      unawaited(
        ref
            .read(transactionAuditLoggerProvider)
            .logBuyFromFeatured(
              coin: candidate,
              signature: signature,
              entrySol: entrySolUsed,
              mode: autoState.executionMode,
              state: autoState,
              entryPriceSol: pumpQuote!.priceSol,
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
      // ⚡ En background: Actualizar con datos reales cuando se confirme
      unawaited(
        _trackConfirmation(signature, candidate.symbol, candidate.mint),
      );
    } catch (error) {
      // ⚡ Si la compra falla después de actualización inmediata, revertir
      if (pendingSignature != null) {
        // Remover posición agregada inmediatamente
        notifier.removePosition(pendingSignature, refundBudget: true);
        final pending = _consumePendingBuy(pendingSignature);
        if (pending != null) {
          notifier.releaseBudgetReservation(pending.solAmount);
        }
      } else if (budgetReserved) {
        notifier.releaseBudgetReservation(entrySolUsed);
      }

      // ⚡ Si falla antes de enviar la transacción, remover del tracking
      // para que pueda reintentarse después del cooldown (no inmediatamente)
      _pendingMints.remove(candidate.mint);

      // 📊 MANEJO INTELIGENTE DE ERRORES: Analizar error y obtener recomendación
      final errorHandler = ref.read(errorHandlerServiceProvider);
      final context = 'buy_${candidate.mint}';
      final analysis = errorHandler.analyzeError(error, context: context);

      // Aplicar recomendación según el análisis
      switch (analysis.action) {
        case ErrorAction.retryFast:
          // Cooldown corto para errores temporales
          _recentMints[candidate.mint] = DateTime.now().subtract(
            const Duration(minutes: 14, seconds: 30),
          );
          notifier.setStatus('⏳ ${analysis.message} Reintentará en ~30s.');
          break;

        case ErrorAction.retryWithHigherFee:
          // Cooldown corto pero con fee más alto en el siguiente intento
          _recentMints[candidate.mint] = DateTime.now().subtract(
            const Duration(minutes: 14, seconds: 30),
          );
          notifier.setStatus(
            '💰 ${analysis.message} Reintentará con fee ${analysis.feeMultiplier?.toStringAsFixed(1)}x más alto.',
          );
          break;

        case ErrorAction.retrySlow:
          // Cooldown normal
          notifier.setStatus(
            '⚠️ ${analysis.message} Reintentará después del cooldown.',
          );
          break;

        case ErrorAction.doNotRetry:
          // No reintentar - error permanente
          _recentMints[candidate.mint] = DateTime.now();
          notifier.setStatus('❌ ${analysis.message}');
          break;

        case ErrorAction.pauseTemporarily:
          // Circuit breaker activado - pausar
          final pauseDuration =
              analysis.pauseDuration ?? const Duration(minutes: 5);
          _recentMints[candidate.mint] = DateTime.now();
          notifier.setStatus(
            '🛑 Circuit breaker activado para ${candidate.symbol}. Pausando por ${pauseDuration.inMinutes} minutos.',
          );
          break;
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

  /// ⚡ Verificar límites diarios (max loss y max earning)
  bool _checkDailyLimits(
    AutoInvestState state,
    double solAmount, {
    required bool isBuy,
  }) {
    if (state.maxLossPerDay <= 0 && state.maxEarningPerDay <= 0) {
      return true; // Sin límites configurados
    }

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    // Calcular PnL diario desde posiciones cerradas hoy
    double dailyPnL = 0.0;
    for (final closed in state.closedPositions) {
      if (closed.closedAt.isAfter(today) ||
          closed.closedAt.isAtSameMomentAs(today)) {
        dailyPnL += closed.pnlSol;
      }
    }

    // Si es venta, estimar el PnL que generaría
    if (!isBuy) {
      // El PnL de la venta se calculará después, pero podemos estimar
      // basándonos en el expectedSol vs entrySol
      // Por ahora, solo verificamos el PnL acumulado hasta ahora
    }

    // Verificar límite de pérdidas diarias
    if (state.maxLossPerDay > 0 && dailyPnL < 0) {
      final loss = -dailyPnL;
      if (loss >= state.maxLossPerDay) {
        final notifier = ref.read(autoInvestProvider.notifier);
        notifier.setStatus(
          'Límite de pérdidas diarias alcanzado (${loss.toStringAsFixed(3)} SOL >= ${state.maxLossPerDay.toStringAsFixed(3)} SOL).',
        );
        return false;
      }
    }

    // Verificar límite de ganancias diarias
    if (state.maxEarningPerDay > 0 && dailyPnL > 0) {
      if (dailyPnL >= state.maxEarningPerDay) {
        final notifier = ref.read(autoInvestProvider.notifier);
        notifier.setStatus(
          'Límite de ganancias diarias alcanzado (${dailyPnL.toStringAsFixed(3)} SOL >= ${state.maxEarningPerDay.toStringAsFixed(3)} SOL).',
        );
        return false;
      }
    }

    return true;
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
    var filteredByMaxTokens = 0;
    var filteredBySecurity = 0;
    final heldMints = {
      for (final position in autoState.positions) position.mint,
    };

    // ⚡ Límite de tokens simultáneos
    if (autoState.maxTokensSimultaneous > 0 &&
        autoState.positions.length >= autoState.maxTokensSimultaneous) {
      return _ScanReport(
        total: coins.length,
        eligible: 0,
        filteredByMarketCap: 0,
        filteredByReplies: 0,
        filteredByAge: 0,
        filteredByHeld: 0,
        filteredByCooldown: 0,
        filteredByMaxTokens: coins.length,
        filteredBySecurity: 0,
        candidate: null,
      );
    }

    FeaturedCoin? candidate;
    for (final coin in coins) {
      // ⚡ FILTRO 1: Market Cap
      if (coin.usdMarketCap < autoState.minMarketCap ||
          coin.usdMarketCap > autoState.maxMarketCap) {
        filteredByMarketCap++;
        continue;
      }

      // ⚡ FILTRO 2: Replies
      if (autoState.minReplies > 0 &&
          coin.replyCount.toDouble() < autoState.minReplies) {
        filteredByReplies++;
        continue;
      }

      // ⚡ FILTRO 3: Edad con unidad configurable (min/h) y rango min/max
      // ⚡ CORREGIDO: Asegurar que el cálculo de edad sea correcto
      final ageInMinutes = now.difference(coin.createdAt).inMinutes;
      // Si la edad es negativa (fecha futura), usar 0
      final safeAgeInMinutes = ageInMinutes < 0 ? 0 : ageInMinutes;
      double ageInSelectedUnit;
      if (autoState.ageTimeUnit == TimeUnit.minutes) {
        ageInSelectedUnit = safeAgeInMinutes.toDouble();
      } else {
        ageInSelectedUnit = safeAgeInMinutes / 60.0;
      }

      // ⚡ CORREGIDO: Aplicar filtros de edad correctamente
      // Si minAgeValue > 0, la edad debe ser >= minAgeValue
      if (autoState.minAgeValue > 0 &&
          ageInSelectedUnit < autoState.minAgeValue) {
        filteredByAge++;
        continue;
      }
      // Si maxAgeValue > 0, la edad debe ser <= maxAgeValue
      if (autoState.maxAgeValue > 0 &&
          ageInSelectedUnit > autoState.maxAgeValue) {
        filteredByAge++;
        continue;
      }

      // ⚡ FILTRO 4: Ya tiene posición abierta
      if (heldMints.contains(coin.mint)) {
        filteredByHeld++;
        continue;
      }

      // ⚡ FILTRO 5: Cooldown (intentos recientes)
      if (_isMintBlocked(coin.mint)) {
        filteredByCooldown++;
        continue;
      }

      // 🛡️ FILTRO 6: Análisis de seguridad (rug pulls/honeypots)
      // ⚡ Por ahora, el análisis se hace de forma asíncrona antes de comprar
      // No bloqueamos aquí para mantener el proceso rápido

      // ⚡ Si pasa todos los filtros, es elegible
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
      filteredByMaxTokens: filteredByMaxTokens,
      filteredBySecurity: filteredBySecurity,
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
    // ⚡ CORREGIDO: Usar los nuevos campos de edad (minAgeValue, maxAgeValue, ageTimeUnit)
    if (autoState.minAgeValue > 0 || autoState.maxAgeValue > 0) {
      final unitLabel = autoState.ageTimeUnit == TimeUnit.minutes ? 'min' : 'h';
      final minLabel = autoState.minAgeValue > 0
          ? ' >= ${autoState.minAgeValue.toStringAsFixed(0)}$unitLabel'
          : '';
      final maxLabel = autoState.maxAgeValue > 0
          ? ' <= ${autoState.maxAgeValue.toStringAsFixed(0)}$unitLabel'
          : '';
      buffer.write(' | edad$minLabel$maxLabel');
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
    if (report.filteredByAge > 0) {
      final unitLabel = autoState.ageTimeUnit == TimeUnit.minutes ? 'min' : 'h';
      final minLabel = autoState.minAgeValue > 0
          ? ' >= ${autoState.minAgeValue.toStringAsFixed(0)}$unitLabel'
          : '';
      final maxLabel = autoState.maxAgeValue > 0
          ? ' <= ${autoState.maxAgeValue.toStringAsFixed(0)}$unitLabel'
          : '';
      reasons.add(
        '${report.filteredByAge} fuera del rango de edad$minLabel$maxLabel.',
      );
    }
    if (report.filteredByMaxTokens > 0) {
      reasons.add(
        'Límite de tokens simultáneos alcanzado (${autoState.maxTokensSimultaneous}).',
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
    // ⚡ Timeouts para evitar bloqueos
    final quote = await jupiter
        .fetchQuote(
          inputMint: JupiterSwapService.solMint,
          outputMint: candidate.mint,
          amountLamports: lamports,
        )
        .timeout(
          const Duration(seconds: 15),
          onTimeout: () {
            throw TimeoutException(
              'Timeout obteniendo quote de Jupiter para ${candidate.symbol}',
            );
          },
        );

    final swap = await jupiter
        .swap(route: quote.route, userPublicKey: autoState.walletAddress!)
        .timeout(
          const Duration(seconds: 15),
          onTimeout: () {
            throw TimeoutException(
              'Timeout construyendo swap de Jupiter para ${candidate.symbol}',
            );
          },
        );

    return await wallet
        .signAndSendBase64(swap.swapTransaction)
        .timeout(
          const Duration(seconds: 10),
          onTimeout: () {
            throw TimeoutException(
              'Timeout enviando transacción de ${candidate.symbol}',
            );
          },
        );
  }

  Future<String> _executeViaPumpPortal(
    AutoInvestState autoState,
    FeaturedCoin candidate, {
    bool isRetry = false,
    bool previousFailure = false,
  }) async {
    // 🚀 PRIORITY FEES DINÁMICOS: Calcular fee óptimo basado en red y competencia
    final dynamicFeeService = ref.read(dynamicPriorityFeeServiceProvider);
    final optimalFee = await dynamicFeeService
        .calculateOptimalFee(
          baseFee: autoState.pumpPriorityFeeSol,
          mint: candidate.mint,
          isRetry: isRetry,
          previousFailure: previousFailure,
        )
        .timeout(
          const Duration(seconds: 2),
          onTimeout: () =>
              autoState.pumpPriorityFeeSol, // Fallback a fee base si timeout
        );

    // 📊 SLIPPAGE DINÁMICO: Calcular slippage óptimo basado en condiciones del mercado
    final dynamicSlippageService = ref.read(dynamicSlippageServiceProvider);

    // Obtener precio actual y liquidez para calcular slippage
    PumpFunQuote? currentQuote;
    try {
      currentQuote = await priceService
          .fetchQuote(candidate.mint)
          .timeout(const Duration(seconds: 3));
    } catch (e) {
      // Si falla, usar slippage base
    }

    final optimalSlippage = await dynamicSlippageService
        .calculateOptimalSlippage(
          SlippageCalculationParams(
            baseSlippagePercent: autoState.pumpSlippagePercent,
            orderSizeSol: autoState.perCoinBudgetSol,
            currentPriceSol: currentQuote?.priceSol ?? 0,
            liquiditySol: currentQuote?.liquiditySol,
            priceHistory: dynamicSlippageService.getPriceHistory(
              candidate.mint,
            ),
          ),
        )
        .timeout(
          const Duration(seconds: 2),
          onTimeout: () =>
              autoState.pumpSlippagePercent, // Fallback a slippage base
        );

    // Registrar precio actual para tracking de volatilidad
    if (currentQuote != null) {
      dynamicSlippageService.recordPricePoint(
        candidate.mint,
        currentQuote.priceSol,
      );
    }

    // ⚡ OPTIMIZACIÓN: Jito bundles para saltar al frente del bloque
    // ⚡ Timeouts para evitar bloqueos
    final base64Tx = await pumpPortal
        .buildTradeTransaction(
          action: 'buy',
          publicKey: autoState.walletAddress!,
          mint: candidate.mint,
          amount: _formatAmount(autoState.perCoinBudgetSol),
          denominatedInSol: true,
          slippagePercent:
              optimalSlippage, // ⚡ Usar slippage dinámico calculado
          priorityFeeSol: optimalFee, // ⚡ Usar fee dinámico calculado
          pool: autoState.pumpPool,
          skipPreflight: true, // ⚡ Skip preflight para velocidad
          jitoOnly: true, // ⚡ Jito bundles para prioridad en el bloque
        )
        .timeout(
          const Duration(seconds: 15),
          onTimeout: () {
            throw TimeoutException(
              'Timeout construyendo transacción en PumpPortal para ${candidate.symbol}',
            );
          },
        );

    final signature = await wallet
        .signAndSendBase64(base64Tx)
        .timeout(
          const Duration(seconds: 10),
          onTimeout: () {
            throw TimeoutException(
              'Timeout enviando transacción de ${candidate.symbol}',
            );
          },
        );

    // 📝 Registrar intento de transacción (para detectar gas wars)
    dynamicFeeService.recordTxAttempt(candidate.mint, optimalFee);

    return signature;
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

    // ⚡ VENTAS ESCALONADAS: Calcular cuánto vender según el nivel alcanzado
    final autoState = ref.read(autoInvestProvider);
    double salePercent = 100.0;
    SaleLevel? triggeredLevel;

    // Obtener PnL actual para determinar qué nivel se alcanzó
    final currentPnlPercent = activePosition.pnlPercent;
    if (currentPnlPercent == null) {
      notifier.setStatus(
        'No se puede calcular PnL para ${activePosition.symbol}',
      );
      return;
    }

    if (reason == PositionAlertType.takeProfit) {
      if (autoState.takeProfitLevels.isNotEmpty) {
        // Buscar el nivel más alto alcanzado
        // Los niveles están ordenados de menor a mayor PnL
        for (final level in autoState.takeProfitLevels.reversed) {
          if (currentPnlPercent >= level.pnlPercent) {
            // Verificar que este nivel no haya sido activado antes
            if (!activePosition.triggeredSaleLevels.contains(
              level.pnlPercent,
            )) {
              triggeredLevel = level;
              salePercent = level.sellPercent;
              break;
            }
          }
        }
        // Si no se encontró nivel, usar 100% (vender todo)
        if (triggeredLevel == null) {
          salePercent = 100.0;
        }
      } else {
        // Fallback al comportamiento antiguo
        if (autoState.takeProfitPartialPercent < 100) {
          salePercent = autoState.takeProfitPartialPercent;
        }
      }
    } else if (reason == PositionAlertType.stopLoss) {
      if (autoState.stopLossLevels.isNotEmpty) {
        // Buscar el nivel más bajo alcanzado
        // Los niveles están ordenados de mayor a menor PnL (más negativo primero)
        for (final level in autoState.stopLossLevels.reversed) {
          if (currentPnlPercent <= level.pnlPercent) {
            // Verificar que este nivel no haya sido activado antes
            if (!activePosition.triggeredSaleLevels.contains(
              level.pnlPercent,
            )) {
              triggeredLevel = level;
              salePercent = level.sellPercent;
              break;
            }
          }
        }
        // Si no se encontró nivel, usar 100% (vender todo)
        if (triggeredLevel == null) {
          salePercent = 100.0;
        }
      } else {
        // Fallback al comportamiento antiguo
        if (autoState.stopLossPartialPercent < 100) {
          salePercent = autoState.stopLossPartialPercent;
        }
      }
    }

    // ⚡ VENTAS ESCALONADAS: El porcentaje del nivel es del restante actual
    // El tokenAmount ya refleja las ventas anteriores, así que aplicar el porcentaje directamente

    // Calcular la cantidad de tokens a vender
    final tokensToSell = tokenAmount * (salePercent / 100.0);
    if (_positionsSelling.contains(activePosition.entrySignature) ||
        activePosition.isClosing) {
      notifier.setStatus(
        'La posici?n ${activePosition.symbol} ya est? en proceso de venta.',
      );
      return;
    }

    // ⚡ Verificar límites diarios antes de vender
    final expectedSolFromSale = activePosition.currentValueSol != null
        ? activePosition.currentValueSol! * (salePercent / 100.0)
        : activePosition.entrySol * (salePercent / 100.0);
    if (!_checkDailyLimits(autoState, expectedSolFromSale, isBuy: false)) {
      return;
    }

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

      // ⚡ MEJORADA: Obtener quote con mejor manejo de errores y detección de graduación
      PumpFunQuote? pumpQuote;
      bool isGraduated = false;
      try {
        pumpQuote = await priceService
            .fetchQuote(activePosition.mint)
            .timeout(
              const Duration(seconds: 10),
              onTimeout: () {
                throw TimeoutException(
                  'Timeout obteniendo precio para ${activePosition.symbol}',
                );
              },
            );
        isGraduated = pumpQuote.isGraduated;
      } catch (e) {
        // Si fetchQuote falla, intentar detectar si está graduado
        // Los tokens graduados a menudo retornan 404 o errores específicos
        final errorStr = e.toString().toLowerCase();
        if (errorStr.contains('404') ||
            errorStr.contains('not found') ||
            errorStr.contains('complete') ||
            errorStr.contains('graduated')) {
          isGraduated = true;
          notifier.setStatus(
            'Token ${activePosition.symbol} parece estar graduado, usando Jupiter para venta.',
          );
        }
        pumpQuote = null;
      }

      // ⚡ VENTA CON FALLBACK: Intentar PumpPortal primero, si falla y parece graduado, usar Jupiter
      String signature;

      if (_shouldSellViaJupiter(position: activePosition, quote: pumpQuote) ||
          isGraduated) {
        // Usar Jupiter directamente si está graduado o si el modo es Jupiter
        signature =
            await _executeSellViaJupiter(
              autoState,
              activePosition,
              tokensToSell,
            ).timeout(
              const Duration(seconds: 30),
              onTimeout: () {
                throw TimeoutException(
                  'Timeout ejecutando venta vía Jupiter para ${activePosition.symbol}',
                );
              },
            );
      } else {
        // Intentar PumpPortal primero
        try {
          signature =
              await _executeSellViaPumpPortal(
                autoState,
                activePosition,
                tokensToSell,
              ).timeout(
                const Duration(seconds: 30),
                onTimeout: () {
                  throw TimeoutException(
                    'Timeout ejecutando venta vía PumpPortal para ${activePosition.symbol}',
                  );
                },
              );
        } catch (pumpPortalError) {
          // ⚡ FALLBACK: Si PumpPortal falla, puede ser que el token se graduó
          // Intentar con Jupiter como fallback
          final errorStr = pumpPortalError.toString().toLowerCase();
          final mightBeGraduated =
              errorStr.contains('404') ||
              errorStr.contains('not found') ||
              errorStr.contains('complete') ||
              errorStr.contains('graduated') ||
              errorStr.contains('invalid') ||
              (pumpPortalError is PumpPortalApiException &&
                  (pumpPortalError.statusCode == 404 ||
                      pumpPortalError.statusCode == 400));

          if (mightBeGraduated) {
            notifier.setStatus(
              'PumpPortal falló para ${activePosition.symbol}, intentando con Jupiter (token puede estar graduado)...',
            );
            try {
              signature =
                  await _executeSellViaJupiter(
                    autoState,
                    activePosition,
                    tokensToSell,
                  ).timeout(
                    const Duration(seconds: 30),
                    onTimeout: () {
                      throw TimeoutException(
                        'Timeout ejecutando venta vía Jupiter (fallback) para ${activePosition.symbol}',
                      );
                    },
                  );
            } catch (jupiterError) {
              // Si Jupiter también falla, lanzar el error original de PumpPortal
              throw pumpPortalError;
            }
          } else {
            // Si no parece ser un error de graduación, lanzar el error original
            rethrow;
          }
        }
      }
      double expectedSol = pumpQuote != null
          ? tokensToSell * pumpQuote.priceSol
          : (activePosition.currentValueSol ?? activePosition.entrySol) *
                (salePercent / 100.0);
      double? preBalance;
      if (preBalanceFuture != null) {
        try {
          preBalance = await preBalanceFuture;
        } catch (_) {
          preBalance = null;
        }
      }

      // ⚡ ACTUALIZACIÓN INMEDIATA: Remover de posiciones abiertas y liberar fondos
      // No esperar confirmación - la UI se actualiza instantáneamente
      final isPartialSale = salePercent < 100.0;
      // ⚡ Marcar nivel como activado si es una venta escalonada
      final triggeredLevelPnl = triggeredLevel?.pnlPercent;
      notifier.completePositionSaleImmediate(
        position: activePosition,
        sellSignature: signature,
        expectedSol: expectedSol > 0 ? expectedSol : activePosition.entrySol,
        isPartialSale: isPartialSale,
        salePercent: salePercent,
        tokensSold: tokensToSell,
        triggeredLevelPnl: triggeredLevelPnl,
      );

      // ⚡ CRÍTICO PARA VENTAS ESCALONADAS: Liberar bloqueo inmediatamente para ventas parciales
      // Esto permite que la siguiente venta escalonada se ejecute sin esperar confirmación
      if (isPartialSale) {
        // Para ventas parciales, liberar el bloqueo inmediatamente
        // La confirmación se procesará en background sin bloquear nuevas ventas
        _positionsSelling.remove(activePosition.entrySignature);
        notifier.setPositionClosing(activePosition.entrySignature, false);
      }
      // Para ventas completas, el bloqueo se libera en _trackSellConfirmation.finally

      // ⚡ COOLDOWN: Si es una venta completa (no parcial), agregar cooldown inmediatamente
      // Esto previene que se compre el mismo token inmediatamente después de venderlo
      if (!isPartialSale) {
        _recentMints[activePosition.mint] = DateTime.now();
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
      // Obtener coin si está disponible
      FeaturedCoin? coin;
      try {
        final featured = ref.read(featuredCoinProvider);
        coin = featured.coins.firstWhere((c) => c.mint == activePosition.mint);
      } catch (_) {
        coin = null;
      }

      // Registro de auditoría preliminar de venta (esperado)
      unawaited(
        ref
            .read(transactionAuditLoggerProvider)
            .logSellFromPosition(
              position: activePosition,
              signature: signature,
              expectedExitSol: expectedSol,
              state: autoState,
              reason: reason,
              coin: coin,
            ),
      );
      // ⚡ En background: Actualizar con datos reales cuando se confirme
      // ⚡ IMPORTANTE: Para ventas parciales, esto NO debe bloquear nuevas ventas
      unawaited(
        _trackSellConfirmation(
          signature: signature,
          position: activePosition,
          expectedSol: expectedSol > 0 ? expectedSol : activePosition.entrySol,
          preBalanceSol: preBalance,
          isPartialSale:
              isPartialSale, // ⚡ Pasar flag para no limpiar bloqueo si ya se limpió
        ),
      );
    } catch (error) {
      // ⚡ Si la venta falla después de actualización inmediata, revertir
      // Buscar la última signature enviada para revertir
      final state = ref.read(autoInvestProvider);
      final lastExecution = state.executions
          .where((e) => e.mint == activePosition.mint && e.side == 'sell')
          .toList();

      if (lastExecution.isNotEmpty) {
        final lastSignature = lastExecution.last.txSignature;
        // Revertir la actualización inmediata
        notifier.revertFailedSale(
          position: activePosition,
          sellSignature: lastSignature,
        );
      }

      // 📊 MANEJO INTELIGENTE DE ERRORES: Analizar error y obtener recomendación
      final errorHandler = ref.read(errorHandlerServiceProvider);
      final context = 'sell_${activePosition.mint}';
      final analysis = errorHandler.analyzeError(error, context: context);

      // Aplicar recomendación según el análisis
      switch (analysis.action) {
        case ErrorAction.retryFast:
          notifier.setStatus('⏳ ${analysis.message} Reintentará en breve.');
          break;

        case ErrorAction.retryWithHigherFee:
          notifier.setStatus(
            '💰 ${analysis.message} Reintentará con fee ${analysis.feeMultiplier?.toStringAsFixed(1)}x más alto.',
          );
          break;

        case ErrorAction.retrySlow:
          notifier.setStatus(
            '⚠️ ${analysis.message} Reintentará después del cooldown.',
          );
          break;

        case ErrorAction.doNotRetry:
          notifier.setStatus('❌ ${analysis.message}');
          break;

        case ErrorAction.pauseTemporarily:
          final pauseDuration =
              analysis.pauseDuration ?? const Duration(minutes: 5);
          notifier.setStatus(
            '🛑 Circuit breaker activado para venta de ${activePosition.symbol}. Pausando por ${pauseDuration.inMinutes} minutos.',
          );
          break;
      }

      notifier.recordExecutionError(activePosition.symbol, error.toString());

      // ⚡ CRÍTICO: Limpiar bloqueo siempre en caso de error
      // Esto permite reintentar la venta si falla
      // Si es venta parcial y ya se limpió, remove() no hace nada (es idempotente)
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
    double tokenAmount, {
    bool isRetry = false,
    bool previousFailure = false,
  }) async {
    // 🚀 PRIORITY FEES DINÁMICOS: Calcular fee óptimo basado en red y competencia
    final dynamicFeeService = ref.read(dynamicPriorityFeeServiceProvider);
    final optimalFee = await dynamicFeeService
        .calculateOptimalFee(
          baseFee: autoState.pumpPriorityFeeSol,
          mint: position.mint,
          isRetry: isRetry,
          previousFailure: previousFailure,
        )
        .timeout(
          const Duration(seconds: 2),
          onTimeout: () =>
              autoState.pumpPriorityFeeSol, // Fallback a fee base si timeout
        );

    // 📊 SLIPPAGE DINÁMICO: Calcular slippage óptimo basado en condiciones del mercado
    final dynamicSlippageService = ref.read(dynamicSlippageServiceProvider);

    // Obtener precio actual y liquidez para calcular slippage
    PumpFunQuote? currentQuote;
    try {
      currentQuote = await priceService
          .fetchQuote(position.mint)
          .timeout(const Duration(seconds: 3));
    } catch (e) {
      // Si falla, usar slippage base
    }

    // Calcular tamaño de orden en SOL (aproximado)
    final orderSizeSol = currentQuote != null
        ? tokenAmount * currentQuote.priceSol
        : position.entrySol; // Fallback a entry SOL

    final optimalSlippage = await dynamicSlippageService
        .calculateOptimalSlippage(
          SlippageCalculationParams(
            baseSlippagePercent: autoState.pumpSlippagePercent,
            orderSizeSol: orderSizeSol,
            currentPriceSol: currentQuote?.priceSol ?? 0,
            liquiditySol: currentQuote?.liquiditySol,
            priceHistory: dynamicSlippageService.getPriceHistory(position.mint),
          ),
        )
        .timeout(
          const Duration(seconds: 2),
          onTimeout: () =>
              autoState.pumpSlippagePercent, // Fallback a slippage base
        );

    // Registrar precio actual para tracking de volatilidad
    if (currentQuote != null) {
      dynamicSlippageService.recordPricePoint(
        position.mint,
        currentQuote.priceSol,
      );
    }

    // ⚡ OPTIMIZACIÓN: Jito bundles + skip preflight para ventas rápidas
    final base64Tx = await pumpPortal
        .buildTradeTransaction(
          action: 'sell',
          publicKey: autoState.walletAddress!,
          mint: position.mint,
          amount: _formatAmount(tokenAmount),
          denominatedInSol: false,
          slippagePercent:
              optimalSlippage, // ⚡ Usar slippage dinámico calculado
          priorityFeeSol: optimalFee, // ⚡ Usar fee dinámico calculado
          pool: autoState.pumpPool,
          skipPreflight: true, // ⚡ Skip preflight para velocidad
          jitoOnly: true, // ⚡ Jito bundles para prioridad en el bloque
        )
        .timeout(
          const Duration(seconds: 15),
          onTimeout: () {
            throw TimeoutException(
              'Timeout construyendo transacción de venta en PumpPortal para ${position.symbol}',
            );
          },
        );
    final signature = await wallet
        .signAndSendBase64(base64Tx)
        .timeout(
          const Duration(seconds: 10),
          onTimeout: () {
            throw TimeoutException(
              'Timeout enviando transacción de venta de ${position.symbol}',
            );
          },
        );

    // 📝 Registrar intento de transacción (para detectar gas wars)
    dynamicFeeService.recordTxAttempt(position.mint, optimalFee);

    return signature;
  }

  Future<String> _executeSellViaJupiter(
    AutoInvestState autoState,
    OpenPosition position,
    double tokenAmount,
  ) async {
    int decimals;
    try {
      decimals = await wallet
          .getMintDecimals(position.mint)
          .timeout(
            const Duration(seconds: 5),
            onTimeout: () {
              throw TimeoutException(
                'Timeout obteniendo decimals para ${position.symbol}',
              );
            },
          );
    } catch (_) {
      decimals = 6; // Fallback a 6 decimals
    }
    final amountLamports = math.max(
      1,
      (tokenAmount * math.pow(10, decimals)).floor(),
    );
    final quote = await jupiter
        .fetchQuote(
          inputMint: position.mint,
          outputMint: JupiterSwapService.solMint,
          amountLamports: amountLamports,
        )
        .timeout(
          const Duration(seconds: 15),
          onTimeout: () {
            throw TimeoutException(
              'Timeout obteniendo quote de Jupiter para ${position.symbol}',
            );
          },
        );
    final swap = await jupiter
        .swap(route: quote.route, userPublicKey: autoState.walletAddress!)
        .timeout(
          const Duration(seconds: 15),
          onTimeout: () {
            throw TimeoutException(
              'Timeout construyendo swap de Jupiter para ${position.symbol}',
            );
          },
        );
    return await wallet
        .signAndSendBase64(swap.swapTransaction)
        .timeout(
          const Duration(seconds: 10),
          onTimeout: () {
            throw TimeoutException(
              'Timeout enviando transacción de venta vía Jupiter de ${position.symbol}',
            );
          },
        );
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

      // ✅ Registrar éxito en el servicio de fees dinámicos
      final dynamicFeeService = ref.read(dynamicPriorityFeeServiceProvider);
      dynamicFeeService.recordSuccess(mint);

      // 📊 REGISTRAR ÉXITO: Resetear circuit breaker para este mint
      final errorHandler = ref.read(errorHandlerServiceProvider);
      errorHandler.recordSuccess('buy_$mint');

      // ⚡ OBTENER FEES EXACTOS POST-COMPRA (asíncrono, no bloquea)
      // Intentar obtener fees exactos desde Helius Enhanced API
      double? exactEntryFee;

      try {
        final heliusService = ref.read(heliusEnhancedApiServiceProvider);
        if (heliusService != null) {
          final txDetails = await heliusService
              .getTransactionDetails(signature: signature)
              .timeout(const Duration(seconds: 5), onTimeout: () => null);

          if (txDetails != null) {
            exactEntryFee = txDetails.totalFee;
            // Actualizar entryFeeSol en la posición si existe
            if (exactEntryFee > 0) {
              final state = ref.read(autoInvestProvider);
              final positionExists = state.positions.any(
                (p) => p.entrySignature == signature,
              );
              if (positionExists) {
                // Actualizar entryFeeSol usando método público
                notifier.updatePositionEntryFee(signature, exactEntryFee);
              }
            }
          }
        }
      } catch (_) {
        // Si falla obtener fees exactos, no es crítico
        // Solo mejora la precisión del tracking
      }

      final consumed = _consumePendingBuy(signature);
      final pending =
          consumed ??
          _fallbackPendingBuyFromExecutions(
            signature: signature,
            mint: mint,
            symbol: symbol,
          );
      // ⚡ La posición ya fue agregada inmediatamente después de enviar la tx
      // Solo actualizamos datos si es necesario (ej: tokenAmount real)
      if (pending != null) {
        // Verificar si la posición ya existe (fue agregada inmediatamente)
        final existingPosition = ref
            .read(autoInvestProvider)
            .positions
            .where((p) => p.entrySignature == signature)
            .isNotEmpty;
        if (!existingPosition && consumed == null) {
          // Solo agregar si no existe (fallback por si acaso)
          notifier.recordPositionEntry(
            mint: pending.mint,
            symbol: pending.symbol,
            solAmount: pending.solAmount,
            txSignature: signature,
            executionMode: pending.executionMode,
            subtractBudget: false, // Ya se reservó
          );
        }
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

      // ⚡ Verificar si la transacción realmente falló o solo no se confirmó a tiempo
      final isTimeout =
          error.toString().contains('timeout') ||
          error.toString().contains('Timeout');

      if (isTimeout) {
        // ⚡ Timeout: La transacción puede estar pendiente, verificar manualmente
        notifier.setStatus(
          'Confirmación timeout para $symbol. Verificando estado...',
        );

        // Verificar si la transacción realmente existe y está confirmada
        try {
          final owner = ref.read(autoInvestProvider).walletAddress;
          if (owner != null) {
            // Intentar leer el balance para ver si la compra se completó
            final balance = await wallet.readTokenBalance(
              owner: owner,
              mint: mint,
            );
            if (balance != null && balance > 0) {
              // ⚡ La compra se completó aunque el timeout ocurrió
              notifier.setStatus(
                'Compra de $symbol completada (verificada por balance)',
              );
              final pending = _consumePendingBuy(signature);
              if (pending != null) {
                _recentMints[pending.mint] = DateTime.now();
                // Actualizar tokenAmount si la posición existe
                try {
                  final positionExists = ref
                      .read(autoInvestProvider)
                      .positions
                      .any((p) => p.entrySignature == signature);
                  if (positionExists) {
                    notifier.updatePositionAmount(signature, balance);
                  }
                } catch (_) {
                  // Error verificando posición, continuar
                }
              }
              return; // ⚡ Salir - la compra fue exitosa
            }
          }
        } catch (_) {
          // Si la verificación falla, continuar con el manejo de error normal
        }
      }

      // ⚡ Error real o timeout sin confirmación
      // 🚀 Detectar si el error es por low priority
      final errorStr = error.toString().toLowerCase();
      final isLowPriorityError =
          errorStr.contains('insufficient') &&
          (errorStr.contains('priority') ||
              errorStr.contains('fee') ||
              errorStr.contains('prioritization'));

      if (isLowPriorityError) {
        // Registrar fallo por low priority
        final dynamicFeeService = ref.read(dynamicPriorityFeeServiceProvider);
        dynamicFeeService.recordLowPriorityFailure(mint);
      }

      notifier.updateExecutionStatus(
        signature,
        status: 'failed',
        errorMessage: error.toString(),
      );
      notifier.setStatus('Orden falló ($symbol): $error');
      final pending = _consumePendingBuy(signature);
      if (pending != null) {
        notifier.releaseBudgetReservation(pending.solAmount);
        notifier.removePosition(signature, refundBudget: true);
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
    bool isPartialSale = false, // ⚡ Flag para ventas parciales
  }) async {
    try {
      await wallet.waitForConfirmation(signature);
      final notifier = ref.read(autoInvestProvider.notifier);
      notifier.updateExecutionStatus(signature, status: 'confirmed');

      // ✅ Registrar éxito en el servicio de fees dinámicos
      final dynamicFeeService = ref.read(dynamicPriorityFeeServiceProvider);
      dynamicFeeService.recordSuccess(position.mint);

      // 📊 REGISTRAR ÉXITO: Resetear circuit breaker para este mint
      final errorHandler = ref.read(errorHandlerServiceProvider);
      errorHandler.recordSuccess('sell_${position.mint}');

      final realizedSol = await _determineRealizedSol(
        signature: signature,
        expectedSol: expectedSol,
        preBalanceSol: preBalanceSol,
      );

      // ⚡ OBTENER FEES EXACTOS POST-VENTA (asíncrono, no bloquea)
      // Intentar obtener fees exactos desde Helius Enhanced API
      double? exactExitFee;
      double? exactBaseFee;
      double? exactPriorityFee;

      try {
        final heliusService = ref.read(heliusEnhancedApiServiceProvider);
        if (heliusService != null) {
          final txDetails = await heliusService
              .getTransactionDetails(signature: signature)
              .timeout(const Duration(seconds: 5), onTimeout: () => null);

          if (txDetails != null) {
            exactExitFee = txDetails.totalFee;
            exactBaseFee = txDetails.baseFee;
            exactPriorityFee = txDetails.priorityFee;
          }
        }
      } catch (_) {
        // Si falla obtener fees exactos, usar estimación
        // No es crítico, solo mejora la precisión
      }

      // Si no se pudieron obtener fees exactos, usar estimación
      final exitFeeSol =
          exactExitFee ??
          (realizedSol < expectedSol ? (expectedSol - realizedSol) : null);

      notifier.completePositionSale(
        position: position,
        sellSignature: signature,
        realizedSol: realizedSol,
        exitFeeSol: exitFeeSol,
        baseFeeSol: exactBaseFee,
        priorityFeeSol: exactPriorityFee,
      );

      // ⚡ COOLDOWN: Agregar mint a _recentMints para evitar comprar de nuevo inmediatamente
      // Solo si es una venta completa (no parcial)
      final currentState = ref.read(autoInvestProvider);
      final stillHasPosition = currentState.positions.any(
        (p) => p.mint == position.mint,
      );
      if (!stillHasPosition) {
        // Es una venta completa, agregar cooldown de 15 minutos
        _recentMints[position.mint] = DateTime.now();
      }

      // Registro de auditor�a confirmado con PnL cuando sea posible
      final pnl = realizedSol - position.entrySol;
      final pnlPct = position.entrySol == 0
          ? null
          : (pnl / position.entrySol) * 100.0;

      // Obtener coin si está disponible
      FeaturedCoin? coin;
      try {
        final featured = ref.read(featuredCoinProvider);
        coin = featured.coins.firstWhere((c) => c.mint == position.mint);
      } catch (_) {
        coin = null;
      }

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
              state: ref.read(autoInvestProvider),
              coin: coin,
            ),
      );
    } catch (error) {
      // 🚀 Detectar si el error es por low priority
      final errorStr = error.toString().toLowerCase();
      final isLowPriorityError =
          errorStr.contains('insufficient') &&
          (errorStr.contains('priority') ||
              errorStr.contains('fee') ||
              errorStr.contains('prioritization'));

      if (isLowPriorityError) {
        // Registrar fallo por low priority
        final dynamicFeeService = ref.read(dynamicPriorityFeeServiceProvider);
        dynamicFeeService.recordLowPriorityFailure(position.mint);
      }

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
      // ⚡ CRÍTICO: Solo limpiar bloqueo si es venta completa
      // Para ventas parciales, el bloqueo ya se limpió inmediatamente después de enviar
      if (!isPartialSale) {
        _positionsSelling.remove(position.entrySignature);
        final notifier = ref.read(autoInvestProvider.notifier);
        notifier.setPositionClosing(position.entrySignature, false);
      }
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

  /// 🐋 Analizar actividad de whales/insiders en un token
  Future<WhaleAnalysis> _analyzeWhaleActivity({
    required String mint,
    String? creatorAddress,
  }) async {
    try {
      final whaleService = ref.read(whaleTrackerServiceProvider);
      final analysis = await whaleService
          .analyzeTokenActivity(
            mint: mint,
            creatorAddress: creatorAddress,
            lookbackWindow: const Duration(minutes: 5),
          )
          .timeout(
            const Duration(seconds: 3),
            onTimeout: () => WhaleAnalysis(
              mint: mint,
              recentWhaleBuys: [],
              recentWhaleSells: [],
              creatorSells: [],
              totalWhaleVolume: 0.0,
              whaleBuyPressure: 0.0,
              whaleSellPressure: 0.0,
            ),
          );
      return analysis;
    } catch (e) {
      // Si falla, retornar análisis vacío (neutral)
      return WhaleAnalysis(
        mint: mint,
        recentWhaleBuys: [],
        recentWhaleSells: [],
        creatorSells: [],
        totalWhaleVolume: 0.0,
        whaleBuyPressure: 0.0,
        whaleSellPressure: 0.0,
      );
    }
  }

  /// 🛡️ Verificar seguridad del token de forma asíncrona antes de comprar
  /// Retorna true si el token es seguro, false si no lo es
  Future<bool> _verifyTokenSecurityAsync(FeaturedCoin candidate) async {
    try {
      final securityService = ref.read(tokenSecurityAnalyzerProvider);
      TokenSecurityScore? securityScore;
      try {
        securityScore = await securityService
            .analyzeToken(candidate.mint)
            .timeout(const Duration(seconds: 3));
      } catch (e) {
        // Si timeout o error, asumir seguro y continuar
        securityScore = null;
      }

      if (securityScore != null && !securityScore.isSafe) {
        // Token no es seguro, cancelar compra
        final notifier = ref.read(autoInvestProvider.notifier);
        notifier.setStatus(
          '⚠️ Token ${candidate.symbol} no es seguro (score: ${securityScore.overallScore.toStringAsFixed(1)}/100). '
          'Riesgos: ${securityScore.risks.join(", ")}',
        );
        // Agregar a cooldown para evitar reintentos inmediatos
        _recentMints[candidate.mint] = DateTime.now();
        return false;
      }

      return true; // Token es seguro o análisis no disponible
    } catch (e) {
      // Si falla el análisis, asumir seguro (no bloquear por análisis de seguridad)
      return true;
    }
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
    this.filteredByMaxTokens = 0,
    this.filteredBySecurity = 0,
    this.candidate,
  });

  final int total;
  final int eligible;
  final int filteredByMarketCap;
  final int filteredByReplies;
  final int filteredByAge;
  final int filteredByHeld;
  final int filteredByCooldown;
  final int filteredByMaxTokens;
  final int filteredBySecurity;
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
