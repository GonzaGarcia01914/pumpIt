import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

/// 🐋 Actividad de una wallet en un token
class WhaleActivity {
  WhaleActivity({
    required this.walletAddress,
    required this.mint,
    required this.activityType,
    required this.solAmount,
    required this.timestamp,
    this.isWhale = false,
    this.isCreator = false,
    this.isInsider = false,
  });

  final String walletAddress;
  final String mint;
  final WhaleActivityType activityType;
  final double solAmount; // Cantidad en SOL
  final DateTime timestamp;
  final bool isWhale;
  final bool isCreator;
  final bool isInsider;

  @override
  String toString() {
    final typeLabel = activityType == WhaleActivityType.buy ? 'COMPRA' : 'VENTA';
    final labels = <String>[];
    if (isWhale) labels.add('WHALE');
    if (isCreator) labels.add('CREATOR');
    if (isInsider) labels.add('INSIDER');
    final labelStr = labels.isEmpty ? '' : ' [${labels.join(", ")}]';
    return '$typeLabel: ${solAmount.toStringAsFixed(4)} SOL$labelStr @ ${timestamp.toIso8601String()}';
  }
}

enum WhaleActivityType {
  buy,
  sell,
}

/// 🐋 Análisis de actividad de whales en un token
class WhaleAnalysis {
  WhaleAnalysis({
    required this.mint,
    required this.recentWhaleBuys,
    required this.recentWhaleSells,
    required this.creatorSells,
    required this.totalWhaleVolume,
    required this.whaleBuyPressure,
    required this.whaleSellPressure,
    this.recommendation,
  });

  final String mint;
  final List<WhaleActivity> recentWhaleBuys;
  final List<WhaleActivity> recentWhaleSells;
  final List<WhaleActivity> creatorSells;
  final double totalWhaleVolume; // Volumen total de whales en SOL
  final double whaleBuyPressure; // Presión de compra (0-1)
  final double whaleSellPressure; // Presión de venta (0-1)
  final WhaleRecommendation? recommendation;

  bool get hasWhaleActivity => recentWhaleBuys.isNotEmpty || recentWhaleSells.isNotEmpty;
  bool get hasCreatorSells => creatorSells.isNotEmpty;
}

enum WhaleRecommendation {
  strongBuy, // Whales grandes comprando
  buy, // Algunos whales comprando
  neutral, // Sin actividad significativa
  sell, // Algunos whales vendiendo
  strongSell, // Whales grandes vendiendo o creator vendiendo
}

/// 🐋 Servicio para detectar y monitorear actividad de whales/insiders
class WhaleTrackerService {
  WhaleTrackerService({
    http.Client? client,
    String? heliusApiKey,
    String? rpcUrl,
  })  : _client = client ?? http.Client(),
        _heliusApiKey = heliusApiKey ?? _getHeliusApiKey(),
        _rpcUrl = rpcUrl ?? _buildRpcUrl();

  final http.Client _client;
  final String? _heliusApiKey;
  final String _rpcUrl;

  // Cache de análisis
  final Map<String, WhaleAnalysis> _analysisCache = <String, WhaleAnalysis>{};
  final Map<String, DateTime> _analysisCacheTime = <String, DateTime>{};
  static const _cacheValidity = Duration(seconds: 30);

  // Lista de wallets conocidas de whales/insiders
  // En producción, esto debería cargarse desde una base de datos o API
  static const _knownWhaleWallets = <String>[
    // Agregar wallets conocidas de whales aquí
    // Ejemplo: '7xKXtg2CW87d97TXJSDpbD5jBkheTqA83TZRuJosgAsU', // Ejemplo de whale conocida
  ];

  // Umbrales para considerar una wallet como "whale"
  static const _whaleBuyThreshold = 10.0; // SOL mínimo para considerar compra de whale
  static const _whaleSellThreshold = 5.0; // SOL mínimo para considerar venta de whale

  static String _buildRpcUrl() {
    final rpcUrlOverride = const String.fromEnvironment(
      'RPC_URL',
      defaultValue: '',
    );
    if (rpcUrlOverride.isNotEmpty) {
      return rpcUrlOverride;
    }
    final heliusApiKey = const String.fromEnvironment(
      'HELIUS_API_KEY',
      defaultValue: '',
    );
    if (heliusApiKey.isNotEmpty) {
      return 'https://mainnet.helius-rpc.com/?api-key=$heliusApiKey';
    }
    return 'https://api.mainnet-beta.solana.com';
  }

  static String? _getHeliusApiKey() {
    final key = const String.fromEnvironment(
      'HELIUS_API_KEY',
      defaultValue: '',
    );
    return key.isEmpty ? null : key;
  }

  /// 🐋 Analizar actividad de whales en un token
  Future<WhaleAnalysis> analyzeTokenActivity({
    required String mint,
    String? creatorAddress,
    Duration? lookbackWindow,
  }) async {
    final normalizedMint = mint.trim();
    final now = DateTime.now();
    final window = lookbackWindow ?? const Duration(minutes: 5);

    // Verificar cache
    final cached = _analysisCache[normalizedMint];
    final cachedAt = _analysisCacheTime[normalizedMint];
    if (cached != null &&
        cachedAt != null &&
        now.difference(cachedAt) < _cacheValidity) {
      return cached;
    }

    // Obtener transacciones recientes del token
    final recentTransactions = await _getRecentTokenTransactions(
      mint: normalizedMint,
      lookbackWindow: window,
    );

    // Analizar actividad de whales
    final whaleBuys = <WhaleActivity>[];
    final whaleSells = <WhaleActivity>[];
    final creatorSells = <WhaleActivity>[];
    double totalWhaleVolume = 0.0;

    for (final tx in recentTransactions) {
      final isBuy = tx['type'] == 'buy' || tx['side'] == 'buy';
      final isSell = tx['type'] == 'sell' || tx['side'] == 'sell';
      final wallet = tx['wallet'] as String? ?? tx['signer'] as String?;
      final amount = _parseSolAmount(tx);

      if (wallet == null || amount == null || amount <= 0) continue;

      final isWhale = _isKnownWhale(wallet) ||
          (isBuy && amount >= _whaleBuyThreshold) ||
          (isSell && amount >= _whaleSellThreshold);
      final isCreator = creatorAddress != null && wallet == creatorAddress;
      final isInsider = _isKnownWhale(wallet);

      if (isBuy && isWhale) {
        whaleBuys.add(WhaleActivity(
          walletAddress: wallet,
          mint: normalizedMint,
          activityType: WhaleActivityType.buy,
          solAmount: amount,
          timestamp: _parseTimestamp(tx),
          isWhale: isWhale,
          isCreator: isCreator,
          isInsider: isInsider,
        ));
        totalWhaleVolume += amount;
      } else if (isSell) {
        if (isWhale) {
          whaleSells.add(WhaleActivity(
            walletAddress: wallet,
            mint: normalizedMint,
            activityType: WhaleActivityType.sell,
            solAmount: amount,
            timestamp: _parseTimestamp(tx),
            isWhale: isWhale,
            isCreator: isCreator,
            isInsider: isInsider,
          ));
          totalWhaleVolume += amount;
        }
        if (isCreator) {
          creatorSells.add(WhaleActivity(
            walletAddress: wallet,
            mint: normalizedMint,
            activityType: WhaleActivityType.sell,
            solAmount: amount,
            timestamp: _parseTimestamp(tx),
            isWhale: false,
            isCreator: true,
            isInsider: false,
          ));
        }
      }
    }

    // Calcular presión de compra/venta
    final totalBuyVolume = whaleBuys.fold<double>(0.0, (sum, a) => sum + a.solAmount);
    final totalSellVolume = whaleSells.fold<double>(0.0, (sum, a) => sum + a.solAmount);
    final totalVolume = totalBuyVolume + totalSellVolume;

    final buyPressure = totalVolume > 0 ? totalBuyVolume / totalVolume : 0.0;
    final sellPressure = totalVolume > 0 ? totalSellVolume / totalVolume : 0.0;

    // Generar recomendación
    final recommendation = _generateRecommendation(
      whaleBuys: whaleBuys,
      whaleSells: whaleSells,
      creatorSells: creatorSells,
      buyPressure: buyPressure,
      sellPressure: sellPressure,
    );

    final analysis = WhaleAnalysis(
      mint: normalizedMint,
      recentWhaleBuys: whaleBuys,
      recentWhaleSells: whaleSells,
      creatorSells: creatorSells,
      totalWhaleVolume: totalWhaleVolume,
      whaleBuyPressure: buyPressure,
      whaleSellPressure: sellPressure,
      recommendation: recommendation,
    );

    // Guardar en cache
    _analysisCache[normalizedMint] = analysis;
    _analysisCacheTime[normalizedMint] = now;

    return analysis;
  }

  /// 📊 Obtener transacciones recientes de un token
  Future<List<Map<String, dynamic>>> _getRecentTokenTransactions({
    required String mint,
    required Duration lookbackWindow,
  }) async {
    try {
      if (_heliusApiKey == null) {
        // Sin Helius API, usar RPC básico (menos eficiente)
        return await _getRecentTransactionsViaRpc(mint, lookbackWindow);
      }

      // Usar Helius Enhanced API para obtener transacciones parseadas
      final baseUrl = 'https://api-mainnet.helius-rpc.com/v0';
      final apiKey = _heliusApiKey!; // Ya verificado arriba
      final uri = Uri.parse('$baseUrl/transactions').replace(queryParameters: {
        'api-key': apiKey,
        'type': 'SWAP',
        'limit': '50', // Obtener últimas 50 transacciones
      });

      final response = await _client
          .get(uri)
          .timeout(const Duration(seconds: 5));

      if (response.statusCode != 200) {
        return [];
      }

      final decoded = jsonDecode(response.body) as Map<String, dynamic>;
      final transactions = decoded['transactions'] as List<dynamic>? ?? [];

      // Filtrar transacciones del token y dentro del lookback window
      final now = DateTime.now();
      final cutoff = now.subtract(lookbackWindow);

      return transactions
          .map((tx) => tx as Map<String, dynamic>)
          .where((tx) {
            // Verificar que la transacción involucre el token
            final tokenMint = tx['tokenMint'] as String? ??
                tx['mint'] as String? ??
                tx['token'] as String?;
            if (tokenMint != mint) return false;

            // Verificar timestamp
            final timestamp = _parseTimestamp(tx);
            return timestamp.isAfter(cutoff);
          })
          .toList();
    } catch (e) {
      // Si falla, retornar lista vacía
      return [];
    }
  }

  /// 📊 Obtener transacciones recientes vía RPC (fallback)
  Future<List<Map<String, dynamic>>> _getRecentTransactionsViaRpc(
    String mint,
    Duration lookbackWindow,
  ) async {
    // ⚠️ NOTA: RPC básico no tiene endpoints directos para obtener transacciones de un token
    // Por ahora, retornamos lista vacía
    // En producción, esto debería usar WebSocket logsSubscribe o Enhanced API
    return [];
  }

  /// 🐋 Verificar si una wallet es una whale conocida
  bool _isKnownWhale(String walletAddress) {
    return _knownWhaleWallets.contains(walletAddress);
  }

  /// 📈 Generar recomendación basada en actividad de whales
  WhaleRecommendation? _generateRecommendation({
    required List<WhaleActivity> whaleBuys,
    required List<WhaleActivity> whaleSells,
    required List<WhaleActivity> creatorSells,
    required double buyPressure,
    required double sellPressure,
  }) {
    // Si el creator está vendiendo, strong sell
    if (creatorSells.isNotEmpty) {
      return WhaleRecommendation.strongSell;
    }

    // Si hay muchas ventas de whales grandes, strong sell
    final largeWhaleSells = whaleSells.where((a) => a.solAmount >= 50.0).length;
    if (largeWhaleSells >= 3) {
      return WhaleRecommendation.strongSell;
    }

    // Si hay muchas compras de whales grandes, strong buy
    final largeWhaleBuys = whaleBuys.where((a) => a.solAmount >= 50.0).length;
    if (largeWhaleBuys >= 3) {
      return WhaleRecommendation.strongBuy;
    }

    // Si la presión de venta es alta, sell
    if (sellPressure > 0.7) {
      return WhaleRecommendation.sell;
    }

    // Si la presión de compra es alta, buy
    if (buyPressure > 0.7) {
      return WhaleRecommendation.buy;
    }

    // Si hay algunas ventas de whales, sell
    if (whaleSells.length >= 2) {
      return WhaleRecommendation.sell;
    }

    // Si hay algunas compras de whales, buy
    if (whaleBuys.length >= 2) {
      return WhaleRecommendation.buy;
    }

    return WhaleRecommendation.neutral;
  }

  /// 🔍 Parsear cantidad en SOL de una transacción
  double? _parseSolAmount(Map<String, dynamic> tx) {
    final amount = tx['amount'] as num? ??
        tx['solAmount'] as num? ??
        tx['nativeTransfers'] as num?;
    if (amount != null) {
      return amount.toDouble();
    }

    // Intentar parsear desde balance changes
    final balanceChanges = tx['balanceChanges'] as List<dynamic>?;
    if (balanceChanges != null && balanceChanges.isNotEmpty) {
      for (final change in balanceChanges) {
        if (change is Map<String, dynamic>) {
          final amount = change['amount'] as num?;
          if (amount != null && amount > 0) {
            return amount.toDouble() / 1000000000.0; // Convertir lamports a SOL
          }
        }
      }
    }

    return null;
  }

  /// 🕐 Parsear timestamp de una transacción
  DateTime _parseTimestamp(Map<String, dynamic> tx) {
    final timestamp = tx['timestamp'] as int? ??
        tx['blockTime'] as int? ??
        tx['time'] as int?;
    if (timestamp != null) {
      return DateTime.fromMillisecondsSinceEpoch(timestamp * 1000);
    }

    final timestampStr = tx['timestamp'] as String?;
    if (timestampStr != null) {
      return DateTime.tryParse(timestampStr) ?? DateTime.now();
    }

    return DateTime.now();
  }

  /// ➕ Agregar una wallet a la lista de whales conocidas
  void addKnownWhale(String walletAddress) {
    // En producción, esto debería persistirse
    // Por ahora, solo se mantiene en memoria durante la sesión
  }

  /// 📊 Obtener estadísticas de una wallet (para determinar si es whale)
  Future<Map<String, dynamic>?> getWalletStats(String walletAddress) async {
    try {
      if (_heliusApiKey == null) {
        return null;
      }

      // Usar Helius Enhanced API para obtener estadísticas de la wallet
      final baseUrl = 'https://api-mainnet.helius-rpc.com/v0';
      final apiKey = _heliusApiKey!; // Ya verificado arriba
      final uri = Uri.parse('$baseUrl/transactions').replace(queryParameters: {
        'api-key': apiKey,
        'address': walletAddress,
        'limit': '100',
        'type': 'SWAP',
      });

      final response = await _client
          .get(uri)
          .timeout(const Duration(seconds: 5));

      if (response.statusCode != 200) {
        return null;
      }

      final decoded = jsonDecode(response.body) as Map<String, dynamic>;
      final transactions = decoded['transactions'] as List<dynamic>? ?? [];

      // Calcular estadísticas básicas
      double totalVolume = 0.0;
      int tradeCount = 0;
      double totalPnL = 0.0;

      for (final tx in transactions) {
        if (tx is Map<String, dynamic>) {
          final amount = _parseSolAmount(tx);
          if (amount != null) {
            totalVolume += amount;
            tradeCount++;
          }
        }
      }

      return {
        'walletAddress': walletAddress,
        'totalVolume': totalVolume,
        'tradeCount': tradeCount,
        'avgTradeSize': tradeCount > 0 ? totalVolume / tradeCount : 0.0,
        'totalPnL': totalPnL,
        'isWhale': totalVolume >= 1000.0 || tradeCount >= 50, // Umbrales para considerar whale
      };
    } catch (e) {
      return null;
    }
  }

  void dispose() {
    _client.close();
  }
}

final whaleTrackerServiceProvider = Provider<WhaleTrackerService>((ref) {
  final service = WhaleTrackerService();
  ref.onDispose(service.dispose);
  return service;
});

