import 'dart:async';
import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../featured_coins/models/featured_coin.dart';
import '../models/execution_record.dart';
import '../models/execution_mode.dart';
import '../models/position.dart';
import '../models/simulation_models.dart';
import '../services/auto_invest_storage.dart';
import '../services/wallet_execution_service.dart';
import '../services/simulation_analysis_service.dart';

class AutoInvestState {
  const AutoInvestState({
    required this.isEnabled,
    required this.minMarketCap,
    required this.maxMarketCap,
    required this.minVolume24h,
    required this.maxVolume24h,
    required this.stopLossPercent,
    required this.takeProfitPercent,
    required this.totalBudgetSol,
    required this.availableBudgetSol,
    required this.perCoinBudgetSol,
    required this.withdrawOnGain,
    required this.walletAddress,
    required this.isConnecting,
    required this.isSimulationRunning,
    required this.simulations,
    required this.isAnalyzingResults,
    required this.analysisSummary,
    required this.executions,
    required this.positions,
    required this.closedPositions,
    required this.executionMode,
    required this.pumpSlippagePercent,
    required this.pumpPriorityFeeSol,
    required this.pumpPool,
    required this.realizedProfitSol,
    required this.withdrawnProfitSol,
    required this.walletBalanceSol,
    this.walletBalanceUpdatedAt,
    required this.solPriceUsd,
    this.solPriceUpdatedAt,
    this.statusMessage,
  });

  factory AutoInvestState.initial() => AutoInvestState(
    isEnabled: false,
    minMarketCap: 15000,
    maxMarketCap: 250000,
    minVolume24h: 0,
    maxVolume24h: 500000,
    stopLossPercent: 20,
    takeProfitPercent: 60,
    totalBudgetSol: 10,
    availableBudgetSol: 10,
    perCoinBudgetSol: 0.5,
    withdrawOnGain: true,
    walletAddress: null,
    isConnecting: false,
    isSimulationRunning: false,
    simulations: const [],
    isAnalyzingResults: false,
    analysisSummary: null,
    executions: const [],
    positions: const [],
    closedPositions: const [],
    executionMode: AutoInvestExecutionMode.jupiter,
    pumpSlippagePercent: 10,
    pumpPriorityFeeSol: 0.001,
    pumpPool: 'pump',
    realizedProfitSol: 0,
    withdrawnProfitSol: 0,
    walletBalanceSol: 0,
    walletBalanceUpdatedAt: null,
    solPriceUsd: 0,
    solPriceUpdatedAt: null,
  );

  final bool isEnabled;
  final double minMarketCap;
  final double maxMarketCap;
  final double minVolume24h;
  final double maxVolume24h;
  final double stopLossPercent;
  final double takeProfitPercent;
  final double totalBudgetSol;
  final double availableBudgetSol;
  final double perCoinBudgetSol;
  final bool withdrawOnGain;
  final String? walletAddress;
  final bool isConnecting;
  final bool isSimulationRunning;
  final List<SimulationRun> simulations;
  final bool isAnalyzingResults;
  final String? analysisSummary;
  final List<ExecutionRecord> executions;
  final List<OpenPosition> positions;
  final List<ClosedPosition> closedPositions;
  final AutoInvestExecutionMode executionMode;
  final double pumpSlippagePercent;
  final double pumpPriorityFeeSol;
  final String pumpPool;
  final double realizedProfitSol;
  final double withdrawnProfitSol;
  final double walletBalanceSol;
  final DateTime? walletBalanceUpdatedAt;
  final double solPriceUsd;
  final DateTime? solPriceUpdatedAt;
  final String? statusMessage;

  double get deployedBudgetSol =>
      (totalBudgetSol - availableBudgetSol).clamp(0, double.infinity);

  AutoInvestState copyWith({
    bool? isEnabled,
    double? minMarketCap,
    double? maxMarketCap,
    double? minVolume24h,
    double? maxVolume24h,
    double? stopLossPercent,
    double? takeProfitPercent,
    double? totalBudgetSol,
    double? availableBudgetSol,
    double? perCoinBudgetSol,
    bool? withdrawOnGain,
    String? walletAddress,
    bool? isConnecting,
    bool? isSimulationRunning,
    List<SimulationRun>? simulations,
    bool? isAnalyzingResults,
    String? analysisSummary,
    List<ExecutionRecord>? executions,
    List<OpenPosition>? positions,
    List<ClosedPosition>? closedPositions,
    AutoInvestExecutionMode? executionMode,
    double? pumpSlippagePercent,
    double? pumpPriorityFeeSol,
    String? pumpPool,
    double? realizedProfitSol,
    double? withdrawnProfitSol,
    double? walletBalanceSol,
    DateTime? walletBalanceUpdatedAt,
    double? solPriceUsd,
    DateTime? solPriceUpdatedAt,
    String? statusMessage,
    bool clearMessage = false,
  }) {
    return AutoInvestState(
      isEnabled: isEnabled ?? this.isEnabled,
      minMarketCap: minMarketCap ?? this.minMarketCap,
      maxMarketCap: maxMarketCap ?? this.maxMarketCap,
      minVolume24h: minVolume24h ?? this.minVolume24h,
      maxVolume24h: maxVolume24h ?? this.maxVolume24h,
      stopLossPercent: stopLossPercent ?? this.stopLossPercent,
      takeProfitPercent: takeProfitPercent ?? this.takeProfitPercent,
      totalBudgetSol: totalBudgetSol ?? this.totalBudgetSol,
      availableBudgetSol: availableBudgetSol ?? this.availableBudgetSol,
      perCoinBudgetSol: perCoinBudgetSol ?? this.perCoinBudgetSol,
      withdrawOnGain: withdrawOnGain ?? this.withdrawOnGain,
      walletAddress: walletAddress ?? this.walletAddress,
      isConnecting: isConnecting ?? this.isConnecting,
      isSimulationRunning: isSimulationRunning ?? this.isSimulationRunning,
      simulations: simulations ?? this.simulations,
      isAnalyzingResults: isAnalyzingResults ?? this.isAnalyzingResults,
      analysisSummary: analysisSummary ?? this.analysisSummary,
      executions: executions ?? this.executions,
      positions: positions ?? this.positions,
      closedPositions: closedPositions ?? this.closedPositions,
      executionMode: executionMode ?? this.executionMode,
      pumpSlippagePercent: pumpSlippagePercent ?? this.pumpSlippagePercent,
      pumpPriorityFeeSol: pumpPriorityFeeSol ?? this.pumpPriorityFeeSol,
      pumpPool: pumpPool ?? this.pumpPool,
      realizedProfitSol: realizedProfitSol ?? this.realizedProfitSol,
      withdrawnProfitSol: withdrawnProfitSol ?? this.withdrawnProfitSol,
      walletBalanceSol: walletBalanceSol ?? this.walletBalanceSol,
      walletBalanceUpdatedAt:
          walletBalanceUpdatedAt ?? this.walletBalanceUpdatedAt,
      solPriceUsd: solPriceUsd ?? this.solPriceUsd,
      solPriceUpdatedAt: solPriceUpdatedAt ?? this.solPriceUpdatedAt,
      statusMessage: clearMessage ? null : statusMessage ?? this.statusMessage,
    );
  }

  Map<String, dynamic> toJson() => {
    'isEnabled': isEnabled,
    'minMarketCap': minMarketCap,
    'maxMarketCap': maxMarketCap,
    'minVolume24h': minVolume24h,
    'maxVolume24h': maxVolume24h,
    'stopLossPercent': stopLossPercent,
    'takeProfitPercent': takeProfitPercent,
    'totalBudgetSol': totalBudgetSol,
    'availableBudgetSol': availableBudgetSol,
    'perCoinBudgetSol': perCoinBudgetSol,
    'withdrawOnGain': withdrawOnGain,
    'walletAddress': walletAddress,
    'executionMode': executionMode.name,
    'pumpSlippagePercent': pumpSlippagePercent,
    'pumpPriorityFeeSol': pumpPriorityFeeSol,
    'pumpPool': pumpPool,
    'realizedProfitSol': realizedProfitSol,
    'withdrawnProfitSol': withdrawnProfitSol,
    'walletBalanceSol': walletBalanceSol,
    'walletBalanceUpdatedAt': walletBalanceUpdatedAt?.toIso8601String(),
    'solPriceUsd': solPriceUsd,
    'solPriceUpdatedAt': solPriceUpdatedAt?.toIso8601String(),
    'positions': positions.map((p) => p.toJson()).toList(growable: false),
    'closedPositions': closedPositions
        .map((p) => p.toJson())
        .toList(growable: false),
  };

  static AutoInvestState fromJson(Map<String, dynamic> json) {
    final initial = AutoInvestState.initial();
    AutoInvestExecutionMode parseMode(String? raw) {
      return AutoInvestExecutionMode.values.firstWhere(
        (mode) => mode.name == raw,
        orElse: () => AutoInvestExecutionMode.jupiter,
      );
    }

    double readDouble(String key, double fallback) {
      final value = json[key];
      if (value is num) return value.toDouble();
      return double.tryParse(value?.toString() ?? '') ?? fallback;
    }

    final positions =
        (json['positions'] as List<dynamic>?)
            ?.whereType<Map<String, dynamic>>()
            .map(OpenPosition.fromJson)
            .toList() ??
        initial.positions;
    final closedPositions =
        (json['closedPositions'] as List<dynamic>?)
            ?.whereType<Map<String, dynamic>>()
            .map(ClosedPosition.fromJson)
            .toList() ??
        initial.closedPositions;
    final deployedFromPositions = positions.fold<double>(
      0,
      (sum, position) => sum + position.entrySol,
    );
    final totalBudget = readDouble('totalBudgetSol', initial.totalBudgetSol);
    final availableBudgetRaw = json['availableBudgetSol'];
    double derivedAvailable = totalBudget - deployedFromPositions;
    if (derivedAvailable < 0) {
      derivedAvailable = 0;
    } else if (derivedAvailable > totalBudget) {
      derivedAvailable = totalBudget;
    }
    final availableBudget = availableBudgetRaw == null
        ? derivedAvailable
        : readDouble('availableBudgetSol', totalBudget);

    return AutoInvestState(
      isEnabled: json['isEnabled'] as bool? ?? initial.isEnabled,
      minMarketCap: readDouble('minMarketCap', initial.minMarketCap),
      maxMarketCap: readDouble('maxMarketCap', initial.maxMarketCap),
      minVolume24h: readDouble('minVolume24h', initial.minVolume24h),
      maxVolume24h: readDouble('maxVolume24h', initial.maxVolume24h),
      stopLossPercent: readDouble('stopLossPercent', initial.stopLossPercent),
      takeProfitPercent: readDouble(
        'takeProfitPercent',
        initial.takeProfitPercent,
      ),
      totalBudgetSol: readDouble('totalBudgetSol', initial.totalBudgetSol),
      availableBudgetSol: availableBudget,
      perCoinBudgetSol: readDouble(
        'perCoinBudgetSol',
        initial.perCoinBudgetSol,
      ),
      withdrawOnGain: json['withdrawOnGain'] as bool? ?? initial.withdrawOnGain,
      walletAddress: json['walletAddress'] as String?,
      isConnecting: false,
      isSimulationRunning: false,
      simulations: initial.simulations,
      isAnalyzingResults: false,
      analysisSummary: null,
      executions: const [],
      statusMessage: null,
      executionMode: parseMode(json['executionMode']?.toString()),
      pumpSlippagePercent: readDouble(
        'pumpSlippagePercent',
        initial.pumpSlippagePercent,
      ),
      pumpPriorityFeeSol: readDouble(
        'pumpPriorityFeeSol',
        initial.pumpPriorityFeeSol,
      ),
      pumpPool: json['pumpPool']?.toString() ?? initial.pumpPool,
      positions: positions,
      closedPositions: closedPositions,
      realizedProfitSol: readDouble(
        'realizedProfitSol',
        initial.realizedProfitSol,
      ),
      withdrawnProfitSol: readDouble(
        'withdrawnProfitSol',
        initial.withdrawnProfitSol,
      ),
      walletBalanceSol: readDouble(
        'walletBalanceSol',
        initial.walletBalanceSol,
      ),
      walletBalanceUpdatedAt: json['walletBalanceUpdatedAt'] is String
          ? DateTime.tryParse(json['walletBalanceUpdatedAt'] as String)
          : null,
      solPriceUsd: readDouble('solPriceUsd', initial.solPriceUsd),
      solPriceUpdatedAt: json['solPriceUpdatedAt'] is String
          ? DateTime.tryParse(json['solPriceUpdatedAt'] as String)
          : null,
    );
  }
}

class AutoInvestNotifier extends Notifier<AutoInvestState> {
  late final WalletExecutionService walletService;
  late final SimulationAnalysisService analysisService;
  late final AutoInvestStorage storage;

  @override
  AutoInvestState build() {
    walletService = ref.watch(walletExecutionServiceProvider);
    analysisService = ref.watch(simulationAnalysisServiceProvider);
    storage = ref.watch(autoInvestStorageProvider);

    var initial = storage.loadState() ?? AutoInvestState.initial();
    final savedExecutions = storage.loadExecutions();
    if (savedExecutions.isNotEmpty) {
      initial = initial.copyWith(executions: savedExecutions);
    }
    final savedPositions = storage.loadPositions();
    if (savedPositions.isNotEmpty) {
      initial = initial.copyWith(positions: savedPositions);
    }
    final savedClosedPositions = storage.loadClosedPositions();
    if (savedClosedPositions.isNotEmpty) {
      initial = initial.copyWith(closedPositions: savedClosedPositions);
    }
    final walletAddress = walletService.currentPublicKey;
    if (walletAddress != null) {
      initial = initial.copyWith(walletAddress: walletAddress);
      Future.microtask(() {
        _setState(state.copyWith(walletAddress: walletAddress));
        refreshWalletBalance();
      });
    }
    return initial;
  }

  void toggleEnabled(bool value) {
    _setState(state.copyWith(isEnabled: value));
  }

  void updateMinMarketCap(double value) {
    _setState(state.copyWith(minMarketCap: value));
  }

  void updateMaxMarketCap(double value) {
    _setState(state.copyWith(maxMarketCap: value));
  }

  void updateMinVolume(double value) {
    _setState(state.copyWith(minVolume24h: value));
  }

  void updateMaxVolume(double value) {
    _setState(state.copyWith(maxVolume24h: value));
  }

  void updateStopLoss(double value) {
    _setState(state.copyWith(stopLossPercent: value));
  }

  void updateTakeProfit(double value) {
    _setState(state.copyWith(takeProfitPercent: value));
  }

  void updateTotalBudget(double value) {
    final deployed = state.deployedBudgetSol;
    var adjustedAvailable = value - deployed;
    if (adjustedAvailable < 0) {
      adjustedAvailable = 0;
    } else if (adjustedAvailable > value) {
      adjustedAvailable = value;
    }
    _setState(
      state.copyWith(
        totalBudgetSol: value,
        availableBudgetSol: adjustedAvailable,
      ),
    );
  }

  void updatePerCoinBudget(double value) {
    _setState(state.copyWith(perCoinBudgetSol: value));
  }

  void applyTotalBudgetPercent(double percent) {
    final balance = state.walletBalanceSol;
    if (balance <= 0) {
      setStatus('Balance de wallet no disponible.');
      return;
    }
    updateTotalBudget(balance * percent);
  }

  void applyPerCoinPercent(double percent) {
    final total = state.totalBudgetSol;
    if (total <= 0) {
      setStatus('Define un presupuesto total antes de ajustar por porcentaje.');
      return;
    }
    updatePerCoinBudget(total * percent);
  }

  void updateWithdrawOnGain(bool value) {
    _setState(state.copyWith(withdrawOnGain: value));
  }

  void setExecutionMode(AutoInvestExecutionMode mode) {
    if (state.executionMode == mode) return;
    _setState(state.copyWith(executionMode: mode, clearMessage: true));
  }

  void updatePumpSlippage(double value) {
    final normalized = value.clamp(0, 99.9);
    _setState(
      state.copyWith(
        pumpSlippagePercent: normalized.toDouble(),
        clearMessage: true,
      ),
    );
  }

  void updatePumpPriorityFee(double value) {
    final normalized = value.clamp(0, 1);
    _setState(
      state.copyWith(
        pumpPriorityFeeSol: normalized.toDouble(),
        clearMessage: true,
      ),
    );
  }

  void updatePumpPool(String value) {
    _setState(state.copyWith(pumpPool: value, clearMessage: true));
  }

  void setStatus(String message) {
    _setState(state.copyWith(statusMessage: message), persist: false);
  }

  void updateSolPrice(double price) {
    _setState(
      state.copyWith(solPriceUsd: price, solPriceUpdatedAt: DateTime.now()),
    );
  }

  Future<void> refreshWalletBalance() async {
    final address = state.walletAddress;
    if (address == null) return;
    try {
      final balance = await walletService.getWalletBalance(address);
      if (balance == null) {
        setStatus('No se pudo obtener balance de wallet.');
        return;
      }
      _setState(
        state.copyWith(
          walletBalanceSol: balance,
          walletBalanceUpdatedAt: DateTime.now(),
        ),
      );
    } catch (error) {
      setStatus('Error leyendo balance: $error');
    }
  }

  Future<void> connectWallet() async {
    if (!walletService.isAvailable) {
      _setState(
        state.copyWith(
          statusMessage:
              'Wallet no disponible. En web conecta Phantom; en desktop define LOCAL_KEY_PATH.',
        ),
        persist: false,
      );
      return;
    }
    _setState(
      state.copyWith(isConnecting: true, clearMessage: true),
      persist: false,
    );
    try {
      final address = await walletService.connect();
      _setState(
        state.copyWith(
          walletAddress: address,
          isConnecting: false,
          statusMessage: 'Wallet conectada.',
        ),
      );
      await refreshWalletBalance();
    } catch (error) {
      _setState(
        state.copyWith(
          isConnecting: false,
          statusMessage: 'Error al conectar: $error',
        ),
        persist: false,
      );
    }
  }

  Future<void> disconnectWallet() async {
    await walletService.disconnect();
    _setState(
      state.copyWith(
        walletAddress: null,
        walletBalanceSol: 0,
        walletBalanceUpdatedAt: null,
        statusMessage: 'Wallet desconectada.',
      ),
    );
  }

  Future<void> simulate(List<FeaturedCoin> coins) async {
    if (state.isSimulationRunning) return;
    _setState(
      state.copyWith(isSimulationRunning: true, clearMessage: true),
      persist: false,
    );
    try {
      final trades = <SimulationTrade>[];
      final rand = math.Random();
      for (final coin in coins) {
        if (coin.usdMarketCap < state.minMarketCap ||
            coin.usdMarketCap > state.maxMarketCap) {
          continue;
        }
        final entry = state.perCoinBudgetSol.clamp(0.1, state.totalBudgetSol);
        final range = state.takeProfitPercent + state.stopLossPercent;
        final deltaPercent =
            (rand.nextDouble() * range) - state.stopLossPercent;
        final pnl = entry * deltaPercent / 100;
        trades.add(
          SimulationTrade(
            mint: coin.mint,
            symbol: coin.symbol,
            entrySol: entry,
            exitSol: entry + pnl,
            pnlSol: pnl,
            executedAt: DateTime.now(),
            hitTakeProfit: deltaPercent >= state.takeProfitPercent,
            hitStopLoss: deltaPercent <= -state.stopLossPercent,
          ),
        );
      }
      if (trades.isEmpty) {
        _setState(
          state.copyWith(
            isSimulationRunning: false,
            statusMessage:
                'No se encontraron tokens que cumplan criterios actuales.',
          ),
          persist: false,
        );
        return;
      }

      final run = SimulationRun(
        timestamp: DateTime.now(),
        criteriaDescription:
            'MC ${state.minMarketCap}-${state.maxMarketCap} USD | presupuesto ${state.perCoinBudgetSol} SOL | stop ${state.stopLossPercent}% / take ${state.takeProfitPercent}%',
        trades: trades,
      );
      final updated = [...state.simulations, run];
      _setState(
        state.copyWith(
          simulations: updated,
          isSimulationRunning: false,
          statusMessage:
              'Simulación creada (${trades.length} operaciones, PnL total ${run.totalPnlSol.toStringAsFixed(2)} SOL).',
        ),
        persist: false,
      );
    } catch (error) {
      _setState(
        state.copyWith(
          isSimulationRunning: false,
          statusMessage: 'Error simulando: $error',
        ),
        persist: false,
      );
    }
  }

  Future<void> analyzeSimulations() async {
    if (state.simulations.isEmpty) {
      _setState(
        state.copyWith(statusMessage: 'No hay simulaciones para analizar.'),
        persist: false,
      );
      return;
    }
    if (!analysisService.isEnabled) {
      _setState(
        state.copyWith(
          statusMessage:
              'Define OPENAI_API_KEY via --dart-define para habilitar el análisis IA.',
        ),
        persist: false,
      );
      return;
    }
    _setState(
      state.copyWith(isAnalyzingResults: true, clearMessage: true),
      persist: false,
    );
    try {
      final summary = await analysisService.summarize(state.simulations);
      _setState(
        state.copyWith(
          isAnalyzingResults: false,
          analysisSummary: summary,
          statusMessage: 'Análisis IA actualizado.',
        ),
        persist: false,
      );
    } catch (error) {
      _setState(
        state.copyWith(
          isAnalyzingResults: false,
          statusMessage: 'Error analizando: $error',
        ),
        persist: false,
      );
    }
  }

  void _setState(AutoInvestState newState, {bool persist = true}) {
    state = newState;
    if (persist) {
      _persistState();
    }
  }

  void _persistState() {
    unawaited(storage.saveState(state));
    unawaited(storage.saveExecutions(state.executions));
    unawaited(storage.savePositions(state.positions));
    unawaited(storage.saveClosedPositions(state.closedPositions));
  }

  void recordExecution(ExecutionRecord record) {
    final updated = [...state.executions, record];
    _setState(
      state.copyWith(
        executions: updated,
        statusMessage: 'Orden ${record.side} enviada (${record.symbol}).',
      ),
    );
  }

  void recordPositionEntry({
    required String mint,
    required String symbol,
    required double solAmount,
    required String txSignature,
    required AutoInvestExecutionMode executionMode,
  }) {
    final existing = state.positions
        .where((position) => position.entrySignature != txSignature)
        .toList(growable: true);
    existing.add(
      OpenPosition(
        mint: mint,
        symbol: symbol,
        entrySol: solAmount,
        entrySignature: txSignature,
        openedAt: DateTime.now(),
        executionMode: executionMode,
      ),
    );
    var nextAvailable = state.availableBudgetSol - solAmount;
    if (nextAvailable < 0) {
      nextAvailable = 0;
    } else if (nextAvailable > state.totalBudgetSol) {
      nextAvailable = state.totalBudgetSol;
    }
    _setState(
      state.copyWith(positions: existing, availableBudgetSol: nextAvailable),
    );
  }

  void updatePositionAmount(String txSignature, double tokenAmount) {
    final updated = state.positions
        .map(
          (position) => position.entrySignature == txSignature
              ? position.copyWith(
                  tokenAmount: tokenAmount,
                  entryPriceSol: tokenAmount > 0
                      ? position.entrySol / tokenAmount
                      : position.entryPriceSol,
                )
              : position,
        )
        .toList();
    _setState(state.copyWith(positions: updated));
  }

  void setPositionClosing(String txSignature, bool isClosing) {
    final updated = state.positions
        .map(
          (position) => position.entrySignature == txSignature
              ? position.copyWith(isClosing: isClosing)
              : position,
        )
        .toList(growable: false);
    _setState(state.copyWith(positions: updated));
  }

  void removePosition(
    String signature, {
    bool refundBudget = false,
    String? message,
  }) {
    OpenPosition? removed;
    final remaining = <OpenPosition>[];
    for (final position in state.positions) {
      if (position.entrySignature == signature && removed == null) {
        removed = position;
        continue;
      }
      remaining.add(position);
    }
    if (removed == null) {
      return;
    }
    var available = state.availableBudgetSol;
    if (refundBudget) {
      available += removed.entrySol;
      if (available > state.totalBudgetSol) {
        available = state.totalBudgetSol;
      }
    }
    var appliedMessage = message;
    if (appliedMessage == null && refundBudget) {
      appliedMessage = 'Fondos liberados (${removed.symbol}).';
    }
    _setState(
      state.copyWith(
        positions: remaining,
        availableBudgetSol: available,
        statusMessage: appliedMessage,
        clearMessage: false,
      ),
    );
  }

  void releaseFailedPosition(String signature) {
    removePosition(signature, refundBudget: true, message: null);
  }

  void completePositionSale({
    required OpenPosition position,
    required String sellSignature,
    required double realizedSol,
    PositionAlertType? closeReason,
  }) {
    final entry = position.entrySol;
    final pnl = realizedSol - entry;
    final remaining = state.positions
        .where((p) => p.entrySignature != position.entrySignature)
        .toList(growable: false);
    var nextTotal = state.totalBudgetSol + pnl;
    if (nextTotal < 0) {
      nextTotal = 0;
    }
    var nextAvailable = state.availableBudgetSol + realizedSol;
    if (nextAvailable < 0) {
      nextAvailable = 0;
    } else if (nextAvailable > nextTotal) {
      nextAvailable = nextTotal;
    }
    var withdrawn = state.withdrawnProfitSol;
    if (state.withdrawOnGain && pnl > 0) {
      nextTotal -= pnl;
      if (nextTotal < 0) {
        nextTotal = 0;
      }
      nextAvailable -= pnl;
      if (nextAvailable < 0) {
        nextAvailable = 0;
      } else if (nextAvailable > nextTotal) {
        nextAvailable = nextTotal;
      }
      withdrawn += pnl;
    }
    final tokenAmount = position.tokenAmount ?? 0;
    final entryPrice =
        position.entryPriceSol ?? (tokenAmount > 0 ? entry / tokenAmount : 0.0);
    final exitPrice = tokenAmount > 0 ? realizedSol / tokenAmount : 0.0;
    final pnlPercent = entry <= 0 ? 0.0 : (pnl / entry) * 100;
    final closed = ClosedPosition(
      mint: position.mint,
      symbol: position.symbol,
      executionMode: position.executionMode,
      entrySol: entry,
      exitSol: realizedSol,
      tokenAmount: tokenAmount,
      entryPriceSol: entryPrice,
      exitPriceSol: exitPrice,
      pnlSol: pnl,
      pnlPercent: pnlPercent,
      openedAt: position.openedAt,
      closedAt: DateTime.now(),
      buySignature: position.entrySignature,
      sellSignature: sellSignature,
      closeReason: closeReason ?? position.alertType,
    );
    _setState(
      state.copyWith(
        positions: remaining,
        closedPositions: [...state.closedPositions, closed],
        totalBudgetSol: nextTotal,
        availableBudgetSol: nextAvailable,
        realizedProfitSol: state.realizedProfitSol + pnl,
        withdrawnProfitSol: withdrawn,
        statusMessage:
            'Posición ${position.symbol} cerrada (${pnl >= 0 ? '+' : ''}${pnl.toStringAsFixed(3)} SOL).',
      ),
    );
  }

  void updatePositionMonitoring(
    String txSignature, {
    required double priceSol,
    required double currentValueSol,
    required double pnlSol,
    double? pnlPercent,
    required DateTime checkedAt,
    PositionAlertType? alertType,
    DateTime? alertTriggeredAt,
    bool updateAlert = false,
  }) {
    final updated = state.positions
        .map((position) {
          if (position.entrySignature != txSignature) {
            return position;
          }
          var next = position.copyWith(
            lastPriceSol: priceSol,
            currentValueSol: currentValueSol,
            pnlSol: pnlSol,
            pnlPercent: pnlPercent,
            lastCheckedAt: checkedAt,
          );
          if (updateAlert) {
            next = next.copyWith(
              alertType: alertType,
              alertTriggeredAt: alertTriggeredAt,
            );
          }
          return next;
        })
        .toList(growable: false);
    _setState(state.copyWith(positions: updated));
  }

  void recordExecutionError(String symbol, String error) {
    _setState(
      state.copyWith(statusMessage: 'Error en orden ($symbol): $error'),
      persist: false,
    );
  }

  void updateExecutionStatus(
    String signature, {
    required String status,
    String? errorMessage,
  }) {
    final updated = state.executions
        .map(
          (record) => record.txSignature == signature
              ? record.copyWith(status: status, errorMessage: errorMessage)
              : record,
        )
        .toList();
    _setState(
      state.copyWith(
        executions: updated,
        statusMessage: errorMessage == null
            ? 'Orden $status ($signature).'
            : 'Orden $status ($signature): $errorMessage',
      ),
    );
  }
}

final autoInvestProvider =
    NotifierProvider<AutoInvestNotifier, AutoInvestState>(
      AutoInvestNotifier.new,
    );
