import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/pump_fun_client.dart';
import '../models/ai_insight.dart';
import '../models/featured_coin.dart';
import '../services/ai_insight_service.dart';

enum FeaturedSortOption { newest, highestCap, mostReplies }

class FeaturedCoinState {
  const FeaturedCoinState({
    required this.coins,
    required this.isFetching,
    required this.isInsightLoading,
    required this.minUsdMarketCap,
    required this.minVolume24h,
    required this.createdAfter,
    required this.sortOption,
    this.insight,
    this.lastUpdated,
    this.errorMessage,
  });

  factory FeaturedCoinState.initial() => FeaturedCoinState(
        coins: const [],
        isFetching: false,
        isInsightLoading: false,
        minUsdMarketCap: 15000,
        minVolume24h: 0,
        createdAfter: null,
        sortOption: FeaturedSortOption.highestCap,
      );

  final List<FeaturedCoin> coins;
  final bool isFetching;
  final bool isInsightLoading;
  final int minUsdMarketCap;
  final double minVolume24h;
  final DateTime? createdAfter;
  final FeaturedSortOption sortOption;
  final AiInsight? insight;
  final DateTime? lastUpdated;
  final String? errorMessage;

  FeaturedCoinState copyWith({
    List<FeaturedCoin>? coins,
    bool? isFetching,
    bool? isInsightLoading,
    int? minUsdMarketCap,
    double? minVolume24h,
    DateTime? createdAfter,
    FeaturedSortOption? sortOption,
    AiInsight? insight,
    DateTime? lastUpdated,
    String? errorMessage,
    bool clearError = false,
    bool resetCreatedAfter = false,
  }) {
    return FeaturedCoinState(
      coins: coins ?? this.coins,
      isFetching: isFetching ?? this.isFetching,
      isInsightLoading: isInsightLoading ?? this.isInsightLoading,
      minUsdMarketCap: minUsdMarketCap ?? this.minUsdMarketCap,
      minVolume24h: minVolume24h ?? this.minVolume24h,
      createdAfter: resetCreatedAfter ? null : createdAfter ?? this.createdAfter,
      sortOption: sortOption ?? this.sortOption,
      insight: insight ?? this.insight,
      lastUpdated: lastUpdated ?? this.lastUpdated,
      errorMessage: clearError ? null : errorMessage ?? this.errorMessage,
    );
  }
}

class FeaturedCoinNotifier extends Notifier<FeaturedCoinState> {
  FeaturedCoinNotifier({this.refreshInterval = const Duration(seconds: 25)});

  late final PumpFunClient client;
  late final AiInsightService ruleBasedService;
  late final AiInsightService? generativeService;
  final Duration refreshInterval;
  Timer? _ticker;

  @override
  FeaturedCoinState build() {
    client = ref.watch(pumpFunClientProvider);
    ruleBasedService = ref.watch(_ruleBasedAiProvider);
    generativeService = ref.watch(_openAiServiceProvider);
    _ticker = Timer.periodic(refreshInterval, (_) => refresh(silent: true));
    ref.onDispose(() => _ticker?.cancel());
    Future.microtask(() => refresh());
    return FeaturedCoinState.initial();
  }

  bool get hasGenerativeAi => generativeService != null;

  Future<void> refresh({bool silent = false}) async {
    if (!silent) {
      state = state.copyWith(isFetching: true, clearError: true);
    }

    try {
      final coins = await client.fetchFeaturedCoins(
        limit: 80,
        marketCapMin: state.minUsdMarketCap.toDouble(),
        volume24hMin: state.minVolume24h <= 0 ? null : state.minVolume24h,
      );

      final filtered = coins.where((coin) {
        final meetsMarketCap = coin.usdMarketCap >= state.minUsdMarketCap;
        final meetsDate = state.createdAfter == null ||
            coin.createdAt.isAfter(state.createdAfter!);
        return meetsMarketCap && meetsDate;
      }).toList()
        ..sort((a, b) {
          switch (state.sortOption) {
            case FeaturedSortOption.highestCap:
              return b.usdMarketCap.compareTo(a.usdMarketCap);
            case FeaturedSortOption.newest:
              return b.createdAt.compareTo(a.createdAt);
            case FeaturedSortOption.mostReplies:
              return b.replyCount.compareTo(a.replyCount);
          }
        });

      state = state.copyWith(
        coins: filtered,
        isFetching: false,
        lastUpdated: DateTime.now(),
        clearError: true,
      );
    } catch (error) {
      state = state.copyWith(
        isFetching: false,
        errorMessage: error.toString(),
      );
    }
  }

  Future<void> generateInsight({bool silent = false}) async {
    if (state.coins.isEmpty) {
      if (!silent) {
        state = state.copyWith(
          errorMessage: 'No hay memecoins para analizar.',
        );
      }
      return;
    }
    await _generateInsight(state.coins);
  }

  Future<void> _generateInsight(List<FeaturedCoin> coins) async {
    state = state.copyWith(isInsightLoading: true);
    try {
      AiInsight insight;
      try {
        if (generativeService != null) {
          insight = await generativeService!.buildInsight(coins);
        } else {
          throw Exception('Generative AI no disponible');
        }
      } catch (_) {
        insight = await ruleBasedService.buildInsight(coins);
      }

      state = state.copyWith(
        insight: insight,
        isInsightLoading: false,
      );
    } catch (error) {
      state = state.copyWith(
        isInsightLoading: false,
        errorMessage: error.toString(),
      );
    }
  }

  void setMinMarketCap(int value) {
    final normalized = value.clamp(1000, 500000);
    state = state.copyWith(minUsdMarketCap: normalized.toInt());
    refresh(silent: true);
  }

  void setMinVolume(double value) {
    final normalized = value.clamp(0, 500000).toDouble();
    state = state.copyWith(minVolume24h: normalized);
    refresh(silent: true);
  }

  void setCreatedAfter(DateTime? date) {
    if (date == null) {
      state = state.copyWith(resetCreatedAfter: true);
    } else {
      state = state.copyWith(createdAfter: date);
    }
    refresh(silent: true);
  }

  void applyFilters({
    required int minMarketCap,
    required double minVolume,
    DateTime? createdAfter,
    FeaturedSortOption? sortOption,
  }) {
    state = state.copyWith(
      minUsdMarketCap: minMarketCap,
      minVolume24h: minVolume,
      createdAfter: createdAfter,
      resetCreatedAfter: createdAfter == null,
      sortOption: sortOption ?? state.sortOption,
    );
    refresh(silent: true);
  }
}

final pumpFunClientProvider = Provider<PumpFunClient>((ref) {
  final client = PumpFunClient();
  ref.onDispose(client.close);
  return client;
});

final _ruleBasedAiProvider = Provider<RuleBasedInsightService>((ref) {
  return const RuleBasedInsightService();
});

const _openAiApiKey = String.fromEnvironment('OPENAI_API_KEY', defaultValue: '');
const _openAiModel = String.fromEnvironment('OPENAI_MODEL', defaultValue: 'gpt-4o-mini');

final _openAiServiceProvider = Provider<OpenAiInsightService?>((ref) {
  if (_openAiApiKey.isEmpty) {
    return null;
  }
  final service = OpenAiInsightService(
    apiKey: _openAiApiKey,
    model: _openAiModel.isEmpty ? 'gpt-4o-mini' : _openAiModel,
  );
  ref.onDispose(service.close);
  return service;
});

final featuredCoinProvider =
    NotifierProvider<FeaturedCoinNotifier, FeaturedCoinState>(
  FeaturedCoinNotifier.new,
);
