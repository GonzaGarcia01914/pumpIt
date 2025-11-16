import 'dart:async';
import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../featured_coins/models/featured_coin.dart';
import '../../featured_coins/controller/featured_coin_notifier.dart';
import '../models/execution_record.dart';
import '../models/execution_mode.dart';
import '../models/position.dart';
import '../models/simulation_models.dart';
import '../services/auto_invest_storage.dart';
import '../services/wallet_execution_service.dart';
import '../services/simulation_analysis_service.dart';
import '../../../core/log/global_log.dart';

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
    required this.solPriceUsd,
    required this.syncBudgetToWallet,
    required this.walletBudgetPercent,
    required this.perCoinPercentOfTotal,
    required this.minReplies,
    required this.maxAgeHours,
    required this.onlyLive,
    required this.preferNewest,
    required this.includeManualMints,
    required this.manualMints,
    this.walletBalanceUpdatedAt,
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
    solPriceUsd: 0,
    syncBudgetToWallet: false,
    walletBudgetPercent: 0.5,
    perCoinPercentOfTotal: 0.1,
    minReplies: 0,
    maxAgeHours: 72,
    onlyLive: false,
    preferNewest: false,
    includeManualMints: false,
    manualMints: const [],
    walletBalanceUpdatedAt: null,
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
  final double solPriceUsd;
  final bool syncBudgetToWallet;
  final double walletBudgetPercent;
  final double perCoinPercentOfTotal;
  final double minReplies;
  final double maxAgeHours;
  final bool onlyLive;
  final bool preferNewest;
  final bool includeManualMints;
  final List<String> manualMints;
  final DateTime? walletBalanceUpdatedAt;
  final DateTime? solPriceUpdatedAt;
  final String? statusMessage;

  double get deployedBudgetSol {
    final exposure = positions.fold<double>(0, (sum, position) {
      return sum + position.entrySol;
    });
    return exposure.clamp(0, totalBudgetSol);
  }

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
    double? solPriceUsd,
    bool? syncBudgetToWallet,
    double? walletBudgetPercent,
    double? perCoinPercentOfTotal,
    double? minReplies,
    double? maxAgeHours,
    bool? onlyLive,
    bool? preferNewest,
    bool? includeManualMints,
    List<String>? manualMints,
    DateTime? walletBalanceUpdatedAt,
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
      solPriceUsd: solPriceUsd ?? this.solPriceUsd,
      syncBudgetToWallet: syncBudgetToWallet ?? this.syncBudgetToWallet,
      walletBudgetPercent: walletBudgetPercent ?? this.walletBudgetPercent,
      perCoinPercentOfTotal:
          perCoinPercentOfTotal ?? this.perCoinPercentOfTotal,
      minReplies: minReplies ?? this.minReplies,
      maxAgeHours: maxAgeHours ?? this.maxAgeHours,
      onlyLive: onlyLive ?? this.onlyLive,
      preferNewest: preferNewest ?? this.preferNewest,
      includeManualMints: includeManualMints ?? this.includeManualMints,
      manualMints: manualMints ?? this.manualMints,
      walletBalanceUpdatedAt:
          walletBalanceUpdatedAt ?? this.walletBalanceUpdatedAt,
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
    'solPriceUsd': solPriceUsd,
    'syncBudgetToWallet': syncBudgetToWallet,
    'walletBudgetPercent': walletBudgetPercent,
    'perCoinPercentOfTotal': perCoinPercentOfTotal,
    'minReplies': minReplies,
    'maxAgeHours': maxAgeHours,
    'onlyLive': onlyLive,
    'preferNewest': preferNewest,
    'includeManualMints': includeManualMints,
    'manualMints': manualMints,
    'walletBalanceUpdatedAt': walletBalanceUpdatedAt?.toIso8601String(),
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

    DateTime? parseDate(dynamic raw) {
      if (raw is String) {
        return DateTime.tryParse(raw);
      }
      return null;
    }

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
      solPriceUsd: readDouble('solPriceUsd', initial.solPriceUsd),
      syncBudgetToWallet:
          json['syncBudgetToWallet'] as bool? ?? initial.syncBudgetToWallet,
      walletBudgetPercent: readDouble(
        'walletBudgetPercent',
        initial.walletBudgetPercent,
      ),
      perCoinPercentOfTotal: readDouble(
        'perCoinPercentOfTotal',
        initial.perCoinPercentOfTotal,
      ),
      minReplies: readDouble('minReplies', initial.minReplies),
      maxAgeHours: readDouble('maxAgeHours', initial.maxAgeHours),
      onlyLive: json['onlyLive'] as bool? ?? initial.onlyLive,
      preferNewest: json['preferNewest'] as bool? ?? initial.preferNewest,
      includeManualMints:
          json['includeManualMints'] as bool? ?? initial.includeManualMints,
      manualMints:
          (json['manualMints'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          initial.manualMints,
      walletBalanceUpdatedAt:
          parseDate(json['walletBalanceUpdatedAt']) ??
          initial.walletBalanceUpdatedAt,
      solPriceUpdatedAt:
          parseDate(json['solPriceUpdatedAt']) ?? initial.solPriceUpdatedAt,
    );
  }
}

class AutoInvestNotifier extends Notifier<AutoInvestState> {
  late final WalletExecutionService walletService;
  late final SimulationAnalysisService analysisService;
  late final AutoInvestStorage storage;
  Timer? _walletBalanceTimer;

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
    final savedClosed = storage.loadClosedPositions();
    if (savedClosed.isNotEmpty) {
      initial = initial.copyWith(closedPositions: savedClosed);
    }
    final walletAddress = walletService.currentPublicKey;
    if (walletAddress != null) {
      initial = initial.copyWith(walletAddress: walletAddress);
      Future.microtask(() {
        _setState(state.copyWith(walletAddress: walletAddress));
      });
    }
    _ensureWalletAutoSync();
    ref.onDispose(() {
      _walletBalanceTimer?.cancel();
      _walletBalanceTimer = null;
    });
    return initial;
  }

  void _ensureWalletAutoSync() {
    _walletBalanceTimer ??= Timer.periodic(const Duration(seconds: 30), (_) {
      final address = state.walletAddress;
      if (address != null && address.isNotEmpty) {
        unawaited(refreshWalletBalance());
      }
    });
  }

  void toggleEnabled(bool value) {
    _setState(state.copyWith(isEnabled: value));
  }

  void toggleIncludeManualMints(bool value) {
    _setState(state.copyWith(includeManualMints: value, clearMessage: true));
  }

  void addManualMint(String raw) {
    final mint = raw.trim();
    if (mint.isEmpty) return;
    final list = [...state.manualMints];
    if (list.contains(mint)) return;
    list.add(mint);
    _setState(state.copyWith(manualMints: list, clearMessage: true));
  }

  void removeManualMint(String mint) {
    final list = state.manualMints.where((m) => m != mint).toList();
    _setState(state.copyWith(manualMints: list, clearMessage: true));
  }

  void clearManualMints() {
    if (state.manualMints.isEmpty) return;
    _setState(state.copyWith(manualMints: const [], clearMessage: true));
  }

  void updateMinMarketCap(double value) {
    _setState(state.copyWith(minMarketCap: value));
    // Sincroniza filtros de Featured para que el executor use una lista consistente
    _syncFeaturedFilters(minMarketCap: value.round());
  }

  void updateMaxMarketCap(double value) {
    _setState(state.copyWith(maxMarketCap: value));
  }

  void updateMinVolume(double value) {
    _setState(state.copyWith(minVolume24h: value));
    _syncFeaturedFilters(minVolume: value);
  }

  void updateMaxVolume(double value) {
    _setState(state.copyWith(maxVolume24h: value));
    _syncFeaturedFilters();
  }

  void _syncFeaturedFilters({int? minMarketCap, double? minVolume}) {
    try {
      final featuredState = ref.read(featuredCoinProvider);
      ref
          .read(featuredCoinProvider.notifier)
          .applyFilters(
            minMarketCap: minMarketCap ?? featuredState.minUsdMarketCap,
            minVolume: minVolume ?? featuredState.minVolume24h,
            maxVolume: state.maxVolume24h,
            createdAfter: featuredState.createdAfter,
            sortOption: featuredState.sortOption,
          );
    } catch (_) {
      // Si Featured no está disponible en este contexto, ignoramos silenciosamente.
    }
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

  // Nuevos criterios de selección
  void updateMinReplies(double value) {
    final normalized = value.clamp(0, 100000).toDouble();
    _setState(state.copyWith(minReplies: normalized));
  }

  void updateMaxAgeHours(double value) {
    final normalized = value.clamp(0, 720).toDouble();
    _setState(state.copyWith(maxAgeHours: normalized));
  }

  void updateOnlyLive(bool value) {
    _setState(state.copyWith(onlyLive: value));
  }

  void updatePreferNewest(bool value) {
    _setState(state.copyWith(preferNewest: value));
  }

  Future<void> refreshWalletBalance() async {
    final address = state.walletAddress;
    if (address == null || address.isEmpty) {
      _setState(
        state.copyWith(statusMessage: 'Conecta tu wallet para sincronizar.'),
        persist: false,
      );
      return;
    }
    try {
      final balance = await walletService.getWalletBalance(address);
      if (balance == null) {
        _setState(
          state.copyWith(
            statusMessage: 'No se pudo leer el saldo de la wallet.',
          ),
          persist: false,
        );
        return;
      }
      var next = state.copyWith(
        walletBalanceSol: balance,
        walletBalanceUpdatedAt: DateTime.now(),
        clearMessage: true,
      );
      if (next.syncBudgetToWallet) {
        // Ajustar presupuestos a porcentaje del saldo de wallet
        final deployed = next.deployedBudgetSol;
        final totalFromWallet = (balance * next.walletBudgetPercent)
            .clamp(0, double.infinity)
            .toDouble();
        var available = totalFromWallet - deployed;
        if (available < 0) available = 0;
        if (available > totalFromWallet) available = totalFromWallet;
        next = next.copyWith(
          totalBudgetSol: totalFromWallet,
          availableBudgetSol: available,
          perCoinBudgetSol: (totalFromWallet * next.perCoinPercentOfTotal)
              .clamp(0, totalFromWallet)
              .toDouble(),
        );
      }
      _setState(next);
    } catch (e) {
      _setState(
        state.copyWith(statusMessage: 'Error leyendo saldo: $e'),
        persist: false,
      );
    }
  }

  void updateSolPrice(double price) {
    if (price <= 0) return;
    _setState(
      state.copyWith(solPriceUsd: price, solPriceUpdatedAt: DateTime.now()),
      persist: false,
    );
  }

  void toggleAutoBudgetSync(bool value) {
    var next = state.copyWith(syncBudgetToWallet: value, clearMessage: true);
    if (value && next.walletBalanceSol > 0) {
      final deployed = next.deployedBudgetSol;
      final totalFromWallet = (next.walletBalanceSol * next.walletBudgetPercent)
          .clamp(0, double.infinity)
          .toDouble();
      var available = totalFromWallet - deployed;
      if (available < 0) available = 0;
      if (available > totalFromWallet) available = totalFromWallet;
      next = next.copyWith(
        totalBudgetSol: totalFromWallet,
        availableBudgetSol: available,
        perCoinBudgetSol: (totalFromWallet * next.perCoinPercentOfTotal)
            .toDouble(),
      );
    }
    _setState(next);
  }

  void setAutoBudgetPercent(double percent) {
    final p = percent.clamp(0.0, 1.0).toDouble();
    var next = state.copyWith(walletBudgetPercent: p, clearMessage: true);
    if (next.syncBudgetToWallet && next.walletBalanceSol > 0) {
      final deployed = next.deployedBudgetSol;
      final totalFromWallet = (next.walletBalanceSol * p).toDouble();
      var available = totalFromWallet - deployed;
      if (available < 0) available = 0;
      if (available > totalFromWallet) available = totalFromWallet;
      next = next.copyWith(
        totalBudgetSol: totalFromWallet,
        availableBudgetSol: available,
      );
    }
    _setState(next);
  }

  void setAutoPerCoinPercent(double percent) {
    final p = percent.clamp(0.0, 1.0).toDouble();
    var next = state.copyWith(perCoinPercentOfTotal: p, clearMessage: true);
    if (next.syncBudgetToWallet) {
      next = next.copyWith(
        perCoinBudgetSol: (next.totalBudgetSol * p).toDouble(),
      );
    }
    _setState(next);
  }

  void applyTotalBudgetPercent(double percent) {
    if (state.walletBalanceSol <= 0) return;
    updateTotalBudget((state.walletBalanceSol * percent).toDouble());
  }

  void applyPerCoinPercent(double percent) {
    updatePerCoinBudget((state.totalBudgetSol * percent).toDouble());
  }

  void setStatus(String message, {AppLogLevel level = AppLogLevel.neutral}) {
    _setState(state.copyWith(statusMessage: message), persist: false);
    try {
      ref.read(globalLogProvider.notifier).show(message, level: level);
    } catch (_) {
      // En contextos donde el globalLogProvider no esté disponible, ignorar.
    }
  }

  Future<void> connectWallet() async {
    if (!walletService.isAvailable) {
      setStatus(
        'Wallet no disponible. En web conecta Phantom; en desktop define LOCAL_KEY_PATH.',
        level: AppLogLevel.error,
      );
      return;
    }
    _setState(
      state.copyWith(isConnecting: true, clearMessage: true),
      persist: false,
    );
    try {
      final address = await walletService.connect();
      _setState(state.copyWith(walletAddress: address, isConnecting: false));
      setStatus('Wallet conectada.', level: AppLogLevel.success);
      // Intentar leer saldo inmediatamente si hay soporte
      unawaited(refreshWalletBalance());
    } catch (error) {
      _setState(state.copyWith(isConnecting: false), persist: false);
      setStatus('Error al conectar: $error', level: AppLogLevel.error);
    }
  }

  Future<void> disconnectWallet() async {
    await walletService.disconnect();
    _setState(state.copyWith(walletAddress: null));
    setStatus('Wallet desconectada.');
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
              'SimulaciÃ³n creada (${trades.length} operaciones, PnL total ${run.totalPnlSol.toStringAsFixed(2)} SOL).',
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
              'Define OPENAI_API_KEY via --dart-define para habilitar el anÃ¡lisis IA.',
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
          statusMessage: 'AnÃ¡lisis IA actualizado.',
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

  Future<void> analyzeClosedPositions() async {
    if (state.closedPositions.isEmpty) {
      _setState(
        state.copyWith(statusMessage: 'No hay posiciones cerradas para analizar.'),
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
      final summary = await analysisService.summarizeClosedTrades(
        trades: state.closedPositions,
        state: state,
      );
      _setState(
        state.copyWith(
          isAnalyzingResults: false,
          analysisSummary: summary,
          statusMessage: 'Análisis IA de cerradas actualizado.',
        ),
        persist: false,
      );
    } catch (error) {
      _setState(
        state.copyWith(
          isAnalyzingResults: false,
          statusMessage: 'Error analizando cerradas: $error',
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

  void resetResults() {
    _setState(
      state.copyWith(
        executions: const [],
        simulations: const [],
        closedPositions: const [],
        analysisSummary: null,
        isAnalyzingResults: false,
        clearMessage: true,
      ),
    );
    setStatus('Resultados reiniciados.');
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
              ? position.copyWith(tokenAmount: tokenAmount)
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

  void completePositionSale({
    required OpenPosition position,
    required String sellSignature,
    required double realizedSol,
    double? exitFeeSol,
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
    // Construir y guardar posición cerrada
    final tokenAmount = position.tokenAmount ?? 0;
    final inferredEntryPrice = tokenAmount > 0
        ? (position.entrySol / tokenAmount)
        : (position.entryPriceSol ?? 0);
    final inferredExitPrice = tokenAmount > 0
        ? (realizedSol / tokenAmount)
        : (position.lastPriceSol ?? 0);
    final exitFee = exitFeeSol ?? position.exitFeeSol;
    final entryFee = position.entryFeeSol;
    final netPnl = (entryFee != null && exitFee != null)
        ? (pnl - (entryFee) - (exitFee))
        : null;
    final closed = ClosedPosition(
      mint: position.mint,
      symbol: position.symbol,
      executionMode: position.executionMode,
      entrySol: position.entrySol,
      exitSol: realizedSol,
      tokenAmount: tokenAmount,
      entryPriceSol: position.entryPriceSol ?? inferredEntryPrice,
      exitPriceSol: inferredExitPrice,
      pnlSol: pnl,
      pnlPercent: position.entrySol == 0 ? 0 : (pnl / position.entrySol) * 100,
      openedAt: position.openedAt,
      closedAt: DateTime.now(),
      buySignature: position.entrySignature,
      sellSignature: sellSignature,
      closeReason: position.alertType,
      entryFeeSol: entryFee,
      exitFeeSol: exitFee,
      netPnlSol: netPnl,
    );
    final newClosed = [...state.closedPositions, closed];
    _setState(
      state.copyWith(
        positions: remaining,
        closedPositions: newClosed,
        totalBudgetSol: nextTotal,
        availableBudgetSol: nextAvailable,
        realizedProfitSol: state.realizedProfitSol + pnl,
        withdrawnProfitSol: withdrawn,
      ),
    );
    final msg =
        'Posición ${position.symbol} cerrada (${pnl >= 0 ? '+' : ''}${pnl.toStringAsFixed(3)} SOL).';
    setStatus(msg, level: pnl >= 0 ? AppLogLevel.success : AppLogLevel.neutral);
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
    setStatus('Error en orden ($symbol): $error', level: AppLogLevel.error);
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
