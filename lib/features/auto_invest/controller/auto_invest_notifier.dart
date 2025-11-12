import 'dart:async';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../featured_coins/models/featured_coin.dart';
import '../models/execution_record.dart';
import '../models/simulation_models.dart';
import '../services/auto_invest_storage.dart';
import '../services/wallet_execution_service.dart';
import '../services/simulation_analysis_service.dart';

enum AutoInvestExecutionMode { jupiter, pumpPortal }

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
    required this.perCoinBudgetSol,
    required this.withdrawOnGain,
    required this.walletAddress,
    required this.isConnecting,
    required this.isSimulationRunning,
    required this.simulations,
    required this.isAnalyzingResults,
    required this.analysisSummary,
    required this.executions,
    required this.executionMode,
    required this.pumpSlippagePercent,
    required this.pumpPriorityFeeSol,
    required this.pumpPool,
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
        perCoinBudgetSol: 0.5,
        withdrawOnGain: true,
        walletAddress: null,
        isConnecting: false,
        isSimulationRunning: false,
        simulations: const [],
        isAnalyzingResults: false,
        analysisSummary: null,
        executions: const [],
        executionMode: AutoInvestExecutionMode.jupiter,
        pumpSlippagePercent: 10,
        pumpPriorityFeeSol: 0.001,
        pumpPool: 'pump',
      );

  final bool isEnabled;
  final double minMarketCap;
  final double maxMarketCap;
  final double minVolume24h;
  final double maxVolume24h;
  final double stopLossPercent;
  final double takeProfitPercent;
  final double totalBudgetSol;
  final double perCoinBudgetSol;
  final bool withdrawOnGain;
  final String? walletAddress;
  final bool isConnecting;
  final bool isSimulationRunning;
  final List<SimulationRun> simulations;
  final bool isAnalyzingResults;
  final String? analysisSummary;
  final List<ExecutionRecord> executions;
  final AutoInvestExecutionMode executionMode;
  final double pumpSlippagePercent;
  final double pumpPriorityFeeSol;
  final String pumpPool;
  final String? statusMessage;

  AutoInvestState copyWith({
    bool? isEnabled,
    double? minMarketCap,
    double? maxMarketCap,
    double? minVolume24h,
    double? maxVolume24h,
    double? stopLossPercent,
    double? takeProfitPercent,
    double? totalBudgetSol,
    double? perCoinBudgetSol,
    bool? withdrawOnGain,
    String? walletAddress,
    bool? isConnecting,
    bool? isSimulationRunning,
    List<SimulationRun>? simulations,
    bool? isAnalyzingResults,
    String? analysisSummary,
    List<ExecutionRecord>? executions,
    AutoInvestExecutionMode? executionMode,
    double? pumpSlippagePercent,
    double? pumpPriorityFeeSol,
    String? pumpPool,
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
      perCoinBudgetSol: perCoinBudgetSol ?? this.perCoinBudgetSol,
      withdrawOnGain: withdrawOnGain ?? this.withdrawOnGain,
      walletAddress: walletAddress ?? this.walletAddress,
      isConnecting: isConnecting ?? this.isConnecting,
      isSimulationRunning: isSimulationRunning ?? this.isSimulationRunning,
      simulations: simulations ?? this.simulations,
      isAnalyzingResults: isAnalyzingResults ?? this.isAnalyzingResults,
      analysisSummary: analysisSummary ?? this.analysisSummary,
      executions: executions ?? this.executions,
      executionMode: executionMode ?? this.executionMode,
      pumpSlippagePercent: pumpSlippagePercent ?? this.pumpSlippagePercent,
      pumpPriorityFeeSol: pumpPriorityFeeSol ?? this.pumpPriorityFeeSol,
      pumpPool: pumpPool ?? this.pumpPool,
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
        'perCoinBudgetSol': perCoinBudgetSol,
        'withdrawOnGain': withdrawOnGain,
        'walletAddress': walletAddress,
        'executionMode': executionMode.name,
        'pumpSlippagePercent': pumpSlippagePercent,
        'pumpPriorityFeeSol': pumpPriorityFeeSol,
        'pumpPool': pumpPool,
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

    return AutoInvestState(
      isEnabled: json['isEnabled'] as bool? ?? initial.isEnabled,
      minMarketCap: readDouble('minMarketCap', initial.minMarketCap),
      maxMarketCap: readDouble('maxMarketCap', initial.maxMarketCap),
      minVolume24h: readDouble('minVolume24h', initial.minVolume24h),
      maxVolume24h: readDouble('maxVolume24h', initial.maxVolume24h),
      stopLossPercent: readDouble('stopLossPercent', initial.stopLossPercent),
      takeProfitPercent:
          readDouble('takeProfitPercent', initial.takeProfitPercent),
      totalBudgetSol: readDouble('totalBudgetSol', initial.totalBudgetSol),
      perCoinBudgetSol:
          readDouble('perCoinBudgetSol', initial.perCoinBudgetSol),
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
      pumpSlippagePercent:
          readDouble('pumpSlippagePercent', initial.pumpSlippagePercent),
      pumpPriorityFeeSol:
          readDouble('pumpPriorityFeeSol', initial.pumpPriorityFeeSol),
      pumpPool: json['pumpPool']?.toString() ?? initial.pumpPool,
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
    final walletAddress = walletService.currentPublicKey;
    if (walletAddress != null) {
      initial = initial.copyWith(walletAddress: walletAddress);
      Future.microtask(() {
        _setState(state.copyWith(walletAddress: walletAddress));
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
    _setState(state.copyWith(totalBudgetSol: value));
  }

  void updatePerCoinBudget(double value) {
    _setState(state.copyWith(perCoinBudgetSol: value));
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
    _setState(state.copyWith(isConnecting: true, clearMessage: true), persist: false);
    try {
      final address = await walletService.connect();
      _setState(
        state.copyWith(
          walletAddress: address,
          isConnecting: false,
          statusMessage: 'Wallet conectada.',
        ),
      );
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
      state.copyWith(walletAddress: null, statusMessage: 'Wallet desconectada.'),
    );
  }

  Future<void> simulate(List<FeaturedCoin> coins) async {
    if (state.isSimulationRunning) return;
    _setState(state.copyWith(isSimulationRunning: true, clearMessage: true), persist: false);
    try {
      final trades = <SimulationTrade>[];
      final rand = Random();
      for (final coin in coins) {
        if (coin.usdMarketCap < state.minMarketCap ||
            coin.usdMarketCap > state.maxMarketCap) {
          continue;
        }
        final entry = state.perCoinBudgetSol.clamp(0.1, state.totalBudgetSol);
        final range = state.takeProfitPercent + state.stopLossPercent;
        final deltaPercent = (rand.nextDouble() * range) - state.stopLossPercent;
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
            statusMessage: 'No se encontraron tokens que cumplan criterios actuales.',
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
        state.copyWith(
          statusMessage: 'No hay simulaciones para analizar.',
        ),
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
    _setState(state.copyWith(isAnalyzingResults: true, clearMessage: true), persist: false);
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

  void recordExecutionError(String symbol, String error) {
    _setState(
      state.copyWith(
        statusMessage: 'Error en orden ($symbol): $error',
      ),
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
    NotifierProvider<AutoInvestNotifier, AutoInvestState>(AutoInvestNotifier.new);
