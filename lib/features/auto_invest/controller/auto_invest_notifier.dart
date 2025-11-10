import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../featured_coins/models/featured_coin.dart';
import '../models/execution_record.dart';
import '../models/simulation_models.dart';
import '../services/phantom_wallet_service.dart';
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
    required this.perCoinBudgetSol,
    required this.withdrawOnGain,
    required this.walletAddress,
    required this.isConnecting,
    required this.isSimulationRunning,
    required this.simulations,
    required this.isAnalyzingResults,
    required this.analysisSummary,
    required this.executions,
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
      statusMessage: clearMessage ? null : statusMessage ?? this.statusMessage,
    );
  }
}

class AutoInvestNotifier extends Notifier<AutoInvestState> {
  late final PhantomWalletService walletService;
  late final SimulationAnalysisService analysisService;

  @override
  AutoInvestState build() {
    walletService = ref.watch(phantomWalletServiceProvider);
    analysisService = ref.watch(simulationAnalysisServiceProvider);
    return AutoInvestState.initial();
  }

  void toggleEnabled(bool value) {
    state = state.copyWith(isEnabled: value);
  }

  void updateMinMarketCap(double value) {
    state = state.copyWith(minMarketCap: value);
  }

  void updateMaxMarketCap(double value) {
    state = state.copyWith(maxMarketCap: value);
  }

  void updateMinVolume(double value) {
    state = state.copyWith(minVolume24h: value);
  }

  void updateMaxVolume(double value) {
    state = state.copyWith(maxVolume24h: value);
  }

  void updateStopLoss(double value) {
    state = state.copyWith(stopLossPercent: value);
  }

  void updateTakeProfit(double value) {
    state = state.copyWith(takeProfitPercent: value);
  }

  void updateTotalBudget(double value) {
    state = state.copyWith(totalBudgetSol: value);
  }

  void updatePerCoinBudget(double value) {
    state = state.copyWith(perCoinBudgetSol: value);
  }

  void updateWithdrawOnGain(bool value) {
    state = state.copyWith(withdrawOnGain: value);
  }

  void setStatus(String message) {
    state = state.copyWith(statusMessage: message);
  }

  Future<void> connectWallet() async {
    if (!walletService.isAvailable) {
      state = state.copyWith(
        statusMessage: 'Phantom no está disponible en este entorno.',
      );
      return;
    }
    state = state.copyWith(isConnecting: true, clearMessage: true);
    try {
      final address = await walletService.connect();
      state = state.copyWith(
        walletAddress: address,
        isConnecting: false,
        statusMessage: 'Wallet conectada.',
      );
    } catch (error) {
      state = state.copyWith(
        isConnecting: false,
        statusMessage: 'Error al conectar: $error',
      );
    }
  }

  Future<void> disconnectWallet() async {
    await walletService.disconnect();
    state = state.copyWith(walletAddress: null, statusMessage: 'Wallet desconectada.');
  }

  Future<void> simulate(List<FeaturedCoin> coins) async {
    if (state.isSimulationRunning) return;
    state = state.copyWith(isSimulationRunning: true, clearMessage: true);
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
        state = state.copyWith(
          isSimulationRunning: false,
          statusMessage: 'No se encontraron tokens que cumplan criterios actuales.',
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
      state = state.copyWith(
        simulations: updated,
        isSimulationRunning: false,
        statusMessage:
            'Simulación creada (${trades.length} operaciones, PnL total ${run.totalPnlSol.toStringAsFixed(2)} SOL).',
      );
    } catch (error) {
      state = state.copyWith(
        isSimulationRunning: false,
        statusMessage: 'Error simulando: $error',
      );
    }
  }

  Future<void> analyzeSimulations() async {
    if (state.simulations.isEmpty) {
      state = state.copyWith(
        statusMessage: 'No hay simulaciones para analizar.',
      );
      return;
    }
    if (!analysisService.isEnabled) {
      state = state.copyWith(
        statusMessage:
            'Define OPENAI_API_KEY via --dart-define para habilitar el análisis IA.',
      );
      return;
    }
    state = state.copyWith(isAnalyzingResults: true, clearMessage: true);
    try {
      final summary = await analysisService.summarize(state.simulations);
      state = state.copyWith(
        isAnalyzingResults: false,
        analysisSummary: summary,
        statusMessage: 'Análisis IA actualizado.',
      );
    } catch (error) {
      state = state.copyWith(
        isAnalyzingResults: false,
        statusMessage: 'Error analizando: $error',
      );
    }
  }

  void recordExecution(ExecutionRecord record) {
    final updated = [...state.executions, record];
    state = state.copyWith(
      executions: updated,
      statusMessage: 'Orden ${record.side} enviada (${record.symbol}).',
    );
  }

  void recordExecutionError(String symbol, String error) {
    state = state.copyWith(
      statusMessage: 'Error en orden ($symbol): $error',
    );
  }
}

final autoInvestProvider =
    NotifierProvider<AutoInvestNotifier, AutoInvestState>(AutoInvestNotifier.new);
