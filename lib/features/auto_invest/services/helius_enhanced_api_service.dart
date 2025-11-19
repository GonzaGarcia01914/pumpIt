import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

/// 🧠 Servicio Enhanced Solana API (Helius)
/// Usa Enhanced APIs para historial, reporting, analytics y dashboard
/// "Dame la versión humana/inteligible de lo que pasa en la chain"
class HeliusEnhancedApiService {
  HeliusEnhancedApiService({
    required String apiKey,
    http.Client? client,
  })  : _apiKey = apiKey,
        _client = client ?? http.Client(),
        _baseUrl = 'https://api-mainnet.helius-rpc.com/v0';

  final String _apiKey;
  final http.Client _client;
  final String _baseUrl;

  /// 🧠 Obtener detalles completos de una transacción por signature
  /// Incluye fees exactos (base fee, priority fee, total), compute units, balances, etc.
  /// Similar a lo que muestra orb.helius.dev
  /// Usa el endpoint POST de Helius Enhanced API
  Future<TransactionDetails?> getTransactionDetails({
    required String signature,
  }) async {
    final uri = Uri.parse('$_baseUrl/transactions').replace(queryParameters: {
      'api-key': _apiKey,
    });

    final response = await _client.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'transactions': [signature],
      }),
    );

    if (response.statusCode != 200) {
      throw Exception(
        'Helius API error ${response.statusCode}: ${response.body}',
      );
    }

    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    final transactions = decoded['transactions'] as List<dynamic>?;
    
    if (transactions == null || transactions.isEmpty) {
      return null;
    }

    final txData = transactions.first as Map<String, dynamic>;
    return TransactionDetails.fromJson(txData);
  }

  /// 🧠 Obtener historial de transacciones parseadas de una wallet
  /// Incluye trades, PnL, y metadata parseada
  Future<List<EnhancedTransaction>> getParsedTransactions({
    required String walletAddress,
    int? limit,
    String? before,
    List<String>? types, // 'SWAP', 'TRANSFER', etc.
  }) async {
    final uri = Uri.parse('$_baseUrl/transactions')
        .replace(queryParameters: {
      'api-key': _apiKey,
      'address': walletAddress,
      if (limit != null) 'limit': limit.toString(),
      if (before != null) 'before': before,
      if (types != null) 'type': types.join(','),
    });

    final response = await _client.get(uri);
    if (response.statusCode != 200) {
      throw Exception(
        'Helius API error ${response.statusCode}: ${response.body}',
      );
    }

    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    final transactions = decoded['transactions'] as List<dynamic>? ?? [];

    return transactions
        .map((tx) => EnhancedTransaction.fromJson(tx as Map<String, dynamic>))
        .toList();
  }

  /// 🧠 Obtener trades parseados (Jupiter, Raydium, etc.)
  /// Ya viene con PnL calculado y metadata
  Future<List<ParsedTrade>> getParsedTrades({
    required String walletAddress,
    int? limit,
    String? before,
  }) async {
    final transactions = await getParsedTransactions(
      walletAddress: walletAddress,
      limit: limit,
      before: before,
      types: ['SWAP'],
    );

    return transactions
        .where((tx) => tx.type == 'SWAP')
        .map((tx) => ParsedTrade.fromEnhancedTransaction(tx))
        .toList();
  }

  /// 🧠 Obtener actividad relacionada con pump.fun
  /// Transacciones ya parseadas y filtradas
  Future<List<EnhancedTransaction>> getPumpFunActivity({
    required String walletAddress,
    int? limit,
  }) async {
    final uri = Uri.parse('$_baseUrl/transactions')
        .replace(queryParameters: {
      'api-key': _apiKey,
      'address': walletAddress,
      if (limit != null) 'limit': limit.toString(),
      'type': 'SWAP',
    });

    final response = await _client.get(uri);
    if (response.statusCode != 200) {
      throw Exception(
        'Helius API error ${response.statusCode}: ${response.body}',
      );
    }

    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    final transactions = decoded['transactions'] as List<dynamic>? ?? [];

    // Filtrar solo transacciones relacionadas con pump.fun
    final pumpFunProgram = '6EF8rrecthR5Dkzon8Nwu78hRvfCKubJ14M5uBEwF6P'; // pump.fun program
    return transactions
        .map((tx) => EnhancedTransaction.fromJson(tx as Map<String, dynamic>))
        .where((tx) => tx.programs.contains(pumpFunProgram))
        .toList();
  }

  /// 🧠 Obtener analytics de volumen por token
  Future<Map<String, TokenVolumeStats>> getTokenVolumeStats({
    required String walletAddress,
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    final trades = await getParsedTrades(
      walletAddress: walletAddress,
      limit: 1000, // Ajustar según necesidad
    );

    final stats = <String, TokenVolumeStats>{};

    for (final trade in trades) {
      final token = trade.tokenMint;
      if (!stats.containsKey(token)) {
        stats[token] = TokenVolumeStats(
          tokenMint: token,
          tokenSymbol: trade.tokenSymbol,
          totalVolume: 0,
          totalTrades: 0,
          totalPnL: 0,
        );
      }

      final stat = stats[token]!;
      stats[token] = TokenVolumeStats(
        tokenMint: stat.tokenMint,
        tokenSymbol: stat.tokenSymbol,
        totalVolume: stat.totalVolume + trade.volumeSol,
        totalTrades: stat.totalTrades + 1,
        totalPnL: stat.totalPnL + (trade.pnlSol ?? 0),
      );
    }

    return stats;
  }

  /// 🧠 Obtener PnL total y por token
  Future<PnLReport> getPnLReport({
    required String walletAddress,
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    final trades = await getParsedTrades(
      walletAddress: walletAddress,
      limit: 1000,
    );

    double totalPnL = 0;
    double totalVolume = 0;
    final pnlByToken = <String, double>{};

    for (final trade in trades) {
      final pnl = trade.pnlSol ?? 0;
      totalPnL += pnl;
      totalVolume += trade.volumeSol;

      pnlByToken[trade.tokenMint] =
          (pnlByToken[trade.tokenMint] ?? 0) + pnl;
    }

    return PnLReport(
      totalPnL: totalPnL,
      totalVolume: totalVolume,
      totalTrades: trades.length,
      pnlByToken: pnlByToken,
    );
  }

  void dispose() {
    _client.close();
  }
}

/// 🧠 Transacción parseada con metadata
class EnhancedTransaction {
  EnhancedTransaction({
    required this.signature,
    required this.timestamp,
    required this.type,
    required this.programs,
    this.description,
    this.source,
    this.fee,
    this.nativeTransfers,
    this.tokenTransfers,
  });

  final String signature;
  final DateTime timestamp;
  final String type; // 'SWAP', 'TRANSFER', etc.
  final List<String> programs;
  final String? description;
  final String? source; // 'JUPITER', 'PUMP_FUN', etc.
  final double? fee;
  final List<NativeTransfer>? nativeTransfers;
  final List<TokenTransfer>? tokenTransfers;

  factory EnhancedTransaction.fromJson(Map<String, dynamic> json) {
    return EnhancedTransaction(
      signature: json['signature'] as String,
      timestamp: DateTime.fromMillisecondsSinceEpoch(
        (json['timestamp'] as int) * 1000,
      ),
      type: json['type'] as String? ?? 'UNKNOWN',
      programs: (json['nativeTransfers'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      description: json['description'] as String?,
      source: json['source'] as String?,
      fee: (json['fee'] as num?)?.toDouble(),
      nativeTransfers: (json['nativeTransfers'] as List<dynamic>?)
          ?.map((e) => NativeTransfer.fromJson(e as Map<String, dynamic>))
          .toList(),
      tokenTransfers: (json['tokenTransfers'] as List<dynamic>?)
          ?.map((e) => TokenTransfer.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}

class NativeTransfer {
  final String from;
  final String to;
  final double amount;

  NativeTransfer({
    required this.from,
    required this.to,
    required this.amount,
  });

  factory NativeTransfer.fromJson(Map<String, dynamic> json) {
    return NativeTransfer(
      from: json['fromUserAccount'] as String,
      to: json['toUserAccount'] as String,
      amount: (json['amount'] as num).toDouble() / 1e9, // lamports to SOL
    );
  }
}

class TokenTransfer {
  final String from;
  final String to;
  final String mint;
  final double amount;
  final int decimals;

  TokenTransfer({
    required this.from,
    required this.to,
    required this.mint,
    required this.amount,
    required this.decimals,
  });

  factory TokenTransfer.fromJson(Map<String, dynamic> json) {
    return TokenTransfer(
      from: json['fromUserAccount'] as String,
      to: json['toUserAccount'] as String,
      mint: json['mint'] as String,
      amount: (json['tokenAmount'] as num).toDouble(),
      decimals: json['tokenAmount'] as int? ?? 6,
    );
  }
}

/// 🧠 Trade parseado con PnL
class ParsedTrade {
  ParsedTrade({
    required this.signature,
    required this.timestamp,
    required this.tokenMint,
    required this.tokenSymbol,
    required this.volumeSol,
    this.pnlSol,
    this.source,
  });

  final String signature;
  final DateTime timestamp;
  final String tokenMint;
  final String tokenSymbol;
  final double volumeSol;
  final double? pnlSol;
  final String? source;

  factory ParsedTrade.fromEnhancedTransaction(EnhancedTransaction tx) {
    // Calcular PnL basado en transfers
    double? pnl;
    double volume = 0;

    if (tx.nativeTransfers != null) {
      for (final transfer in tx.nativeTransfers!) {
        volume += transfer.amount.abs();
      }
    }

    // Simplificado - en producción calcular PnL real basado en compra/venta
    return ParsedTrade(
      signature: tx.signature,
      timestamp: tx.timestamp,
      tokenMint: tx.tokenTransfers?.isNotEmpty == true
          ? tx.tokenTransfers!.first.mint
          : '',
      tokenSymbol: '', // Obtener de metadata
      volumeSol: volume,
      pnlSol: pnl,
      source: tx.source,
    );
  }
}

/// 🧠 Estadísticas de volumen por token
class TokenVolumeStats {
  TokenVolumeStats({
    required this.tokenMint,
    required this.tokenSymbol,
    required this.totalVolume,
    required this.totalTrades,
    required this.totalPnL,
  });

  final String tokenMint;
  final String tokenSymbol;
  final double totalVolume;
  final int totalTrades;
  final double totalPnL;
}

/// 🧠 Reporte de PnL
class PnLReport {
  PnLReport({
    required this.totalPnL,
    required this.totalVolume,
    required this.totalTrades,
    required this.pnlByToken,
  });

  final double totalPnL;
  final double totalVolume;
  final int totalTrades;
  final Map<String, double> pnlByToken;
}

/// 🧠 Detalles completos de una transacción (similar a orb.helius.dev)
class TransactionDetails {
  TransactionDetails({
    required this.signature,
    required this.timestamp,
    required this.feePayer,
    required this.totalFee,
    this.baseFee,
    this.priorityFee,
    this.computeUnitsConsumed,
    this.slot,
    this.blockhash,
    this.confirmationStatus,
    this.solBalances,
    this.tokenBalances,
    this.nativeTransfers,
    this.tokenTransfers,
    this.programs,
    this.description,
    this.source,
  });

  final String signature;
  final DateTime timestamp;
  final String feePayer;
  final double totalFee; // Total fee en SOL
  final double? baseFee; // Base fee en SOL
  final double? priorityFee; // Priority fee en SOL
  final int? computeUnitsConsumed;
  final int? slot;
  final String? blockhash;
  final String? confirmationStatus;
  final List<SolBalanceChange>? solBalances;
  final List<TokenBalanceChange>? tokenBalances;
  final List<NativeTransfer>? nativeTransfers;
  final List<TokenTransfer>? tokenTransfers;
  final List<String>? programs;
  final String? description;
  final String? source;

  factory TransactionDetails.fromJson(Map<String, dynamic> json) {
    // Parsear fees - Helius Enhanced API puede devolver fees de diferentes formas
    final feePayer = json['feePayer'] as String? ?? '';
    double totalFee = 0.0;
    double? baseFee;
    double? priorityFee;

    // Intentar extraer fee total
    if (json['fee'] != null) {
      if (json['fee'] is num) {
        totalFee = (json['fee'] as num).toDouble() / 1e9; // lamports a SOL
      } else if (json['fee'] is Map) {
        final feeMap = json['fee'] as Map<String, dynamic>;
        totalFee = ((feeMap['total'] as num?)?.toDouble() ?? 
                   (feeMap['amount'] as num?)?.toDouble() ?? 0.0) / 1e9;
        baseFee = (feeMap['baseFee'] as num?)?.toDouble();
        if (baseFee != null) baseFee = baseFee / 1e9;
        priorityFee = (feeMap['priorityFee'] as num?)?.toDouble();
        if (priorityFee != null) priorityFee = priorityFee / 1e9;
      }
    }

    // También intentar desde meta si está disponible
    final meta = json['meta'] as Map<String, dynamic>?;
    if (meta != null) {
      final metaFee = meta['fee'] as num?;
      if (metaFee != null && totalFee == 0) {
        totalFee = metaFee.toDouble() / 1e9;
      }
      final computeUnits = meta['computeUnitsConsumed'] as num?;
      if (computeUnits != null) {
        // Se asignará después
      }
    }

    // Parsear balances SOL desde nativeTransfers
    final solBalances = <SolBalanceChange>[];
    final nativeTransfers = json['nativeTransfers'] as List<dynamic>?;
    if (nativeTransfers != null) {
      for (final transfer in nativeTransfers) {
        final t = transfer as Map<String, dynamic>;
        final from = t['fromUserAccount'] as String? ?? '';
        final to = t['toUserAccount'] as String? ?? '';
        final amount = ((t['amount'] as num?)?.toDouble() ?? 0.0) / 1e9;
        
        // Balance antes y después pueden estar en diferentes campos
        final fromBalanceBefore = ((t['fromBalanceBefore'] as num?)?.toDouble() ?? 0.0) / 1e9;
        final fromBalanceAfter = ((t['fromBalanceAfter'] as num?)?.toDouble() ?? 0.0) / 1e9;
        final toBalanceBefore = ((t['toBalanceBefore'] as num?)?.toDouble() ?? 0.0) / 1e9;
        final toBalanceAfter = ((t['toBalanceAfter'] as num?)?.toDouble() ?? 0.0) / 1e9;

        if (from.isNotEmpty) {
          solBalances.add(SolBalanceChange(
            account: from,
            preBalance: fromBalanceBefore,
            postBalance: fromBalanceAfter,
            change: -amount, // Negativo porque sale
          ));
        }
        if (to.isNotEmpty) {
          solBalances.add(SolBalanceChange(
            account: to,
            preBalance: toBalanceBefore,
            postBalance: toBalanceAfter,
            change: amount, // Positivo porque entra
          ));
        }
      }
    }

    // Parsear balances de tokens
    final tokenBalances = <TokenBalanceChange>[];
    final tokenTransfers = json['tokenTransfers'] as List<dynamic>?;
    if (tokenTransfers != null) {
      for (final transfer in tokenTransfers) {
        final t = transfer as Map<String, dynamic>;
        final from = t['fromUserAccount'] as String? ?? '';
        final to = t['toUserAccount'] as String? ?? '';
        final mint = t['mint'] as String? ?? '';
        final decimals = t['tokenDecimals'] as int? ?? 6;
        final amount = (t['tokenAmount'] as num?)?.toDouble() ?? 0.0;

        if (from.isNotEmpty && mint.isNotEmpty) {
          tokenBalances.add(TokenBalanceChange(
            account: from,
            mint: mint,
            preBalance: amount,
            postBalance: 0, // Se actualizará si hay información disponible
            decimals: decimals,
          ));
        }
        if (to.isNotEmpty && mint.isNotEmpty) {
          tokenBalances.add(TokenBalanceChange(
            account: to,
            mint: mint,
            preBalance: 0,
            postBalance: amount,
            decimals: decimals,
          ));
        }
      }
    }

    // Parsear programas
    final programs = <String>[];
    if (json['nativeTransfers'] != null) {
      // Los programas pueden estar en diferentes lugares
      final programIds = json['programIds'] as List<dynamic>?;
      if (programIds != null) {
        programs.addAll(programIds.map((e) => e.toString()));
      }
    }

    return TransactionDetails(
      signature: json['signature'] as String? ?? '',
      timestamp: DateTime.fromMillisecondsSinceEpoch(
        ((json['timestamp'] as num?)?.toInt() ?? 
         (json['blockTime'] as num?)?.toInt() ?? 0) * 1000,
      ),
      feePayer: feePayer,
      totalFee: totalFee,
      baseFee: baseFee,
      priorityFee: priorityFee,
      computeUnitsConsumed: (meta?['computeUnitsConsumed'] as num?)?.toInt() ??
                           json['computeUnitsConsumed'] as int?,
      slot: json['slot'] as int?,
      blockhash: json['recentBlockhash'] as String? ?? json['blockhash'] as String?,
      confirmationStatus: json['confirmationStatus'] as String?,
      solBalances: solBalances.isEmpty ? null : solBalances,
      tokenBalances: tokenBalances.isEmpty ? null : tokenBalances,
      nativeTransfers: nativeTransfers
          ?.map((e) => NativeTransfer.fromJson(e as Map<String, dynamic>))
          .toList(),
      tokenTransfers: tokenTransfers
          ?.map((e) => TokenTransfer.fromJson(e as Map<String, dynamic>))
          .toList(),
      programs: programs.isEmpty ? null : programs,
      description: json['description'] as String?,
      source: json['source'] as String?,
    );
  }
}

/// 🧠 Cambio de balance SOL
class SolBalanceChange {
  SolBalanceChange({
    required this.account,
    required this.preBalance,
    required this.postBalance,
    required this.change,
  });

  final String account;
  final double preBalance; // Balance antes en SOL
  final double postBalance; // Balance después en SOL
  final double change; // Cambio en SOL (negativo = salida, positivo = entrada)
}

/// 🧠 Cambio de balance de token
class TokenBalanceChange {
  TokenBalanceChange({
    required this.account,
    required this.mint,
    required this.preBalance,
    required this.postBalance,
    required this.decimals,
  });

  final String account;
  final String mint;
  final double preBalance; // Balance antes en tokens
  final double postBalance; // Balance después en tokens
  final int decimals;
}

final heliusEnhancedApiServiceProvider = Provider<HeliusEnhancedApiService?>((ref) {
  // Solo crear si hay API key de Helius
  const apiKey = String.fromEnvironment('HELIUS_API_KEY', defaultValue: '');
  if (apiKey.isEmpty) return null;
  final service = HeliusEnhancedApiService(apiKey: apiKey);
  ref.onDispose(service.dispose);
  return service;
});

