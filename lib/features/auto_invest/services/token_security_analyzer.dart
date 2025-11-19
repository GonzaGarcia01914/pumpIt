import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

/// 🛡️ Resultado del análisis de seguridad de un token
class TokenSecurityScore {
  TokenSecurityScore({
    required this.mint,
    required this.overallScore,
    required this.isSafe,
    required this.risks,
    required this.warnings,
    this.holderCount,
    this.creatorAddress,
    this.hasPauseFunction,
    this.hasBlacklistFunction,
    this.isLiquidityLocked,
    this.isInBlacklist,
    this.creatorRugPullHistory,
  });

  final String mint;
  final double overallScore; // 0-100, donde 100 es completamente seguro
  final bool isSafe; // true si score >= 70
  final List<String> risks; // Lista de riesgos detectados
  final List<String> warnings; // Advertencias menores

  // Detalles del análisis
  final int? holderCount;
  final String? creatorAddress;
  final bool? hasPauseFunction;
  final bool? hasBlacklistFunction;
  final bool? isLiquidityLocked;
  final bool? isInBlacklist;
  final int? creatorRugPullHistory; // Número de rug pulls previos del creator

  @override
  String toString() {
    final buffer = StringBuffer();
    buffer.writeln('Token Security Score: ${overallScore.toStringAsFixed(1)}/100');
    buffer.writeln('Safe: ${isSafe ? "✅" : "❌"}');
    if (risks.isNotEmpty) {
      buffer.writeln('Risks:');
      for (final risk in risks) {
        buffer.writeln('  - $risk');
      }
    }
    if (warnings.isNotEmpty) {
      buffer.writeln('Warnings:');
      for (final warning in warnings) {
        buffer.writeln('  - $warning');
      }
    }
    return buffer.toString();
  }
}

/// 🛡️ Servicio para analizar la seguridad de tokens y detectar rug pulls/honeypots
class TokenSecurityAnalyzer {
  TokenSecurityAnalyzer({
    http.Client? client,
    String? rpcUrl,
    String? heliusApiKey,
  })  : _client = client ?? http.Client(),
        _rpcUrl = rpcUrl ?? _buildRpcUrl(),
        _heliusApiKey = heliusApiKey ?? _getHeliusApiKey();

  final http.Client _client;
  final String _rpcUrl;
  final String? _heliusApiKey;

  // Cache de análisis
  final Map<String, TokenSecurityScore> _analysisCache = <String, TokenSecurityScore>{};
  final Map<String, DateTime> _analysisCacheTime = <String, DateTime>{};
  static const _cacheValidity = Duration(minutes: 5);

  // Blacklists conocidas (pueden expandirse)
  static const _knownBlacklists = <String>[
    // Agregar más blacklists conocidas aquí
  ];

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

  /// 🛡️ Analizar la seguridad de un token
  Future<TokenSecurityScore> analyzeToken(String mint) async {
    final normalizedMint = mint.trim();
    final now = DateTime.now();

    // Verificar cache
    final cached = _analysisCache[normalizedMint];
    final cachedAt = _analysisCacheTime[normalizedMint];
    if (cached != null &&
        cachedAt != null &&
        now.difference(cachedAt) < _cacheValidity) {
      return cached;
    }

    final risks = <String>[];
    final warnings = <String>[];
    double score = 100.0;

    // 1. Verificar distribución de holders
    final holderAnalysis = await _analyzeHolderDistribution(normalizedMint);
    if (holderAnalysis.holderCount != null) {
      if (holderAnalysis.holderCount! < 3) {
        risks.add('Token tiene muy pocos holders (${holderAnalysis.holderCount}) - posible honeypot');
        score -= 40.0;
      } else if (holderAnalysis.holderCount! < 10) {
        warnings.add('Token tiene pocos holders (${holderAnalysis.holderCount})');
        score -= 10.0;
      }
    }

    // 2. Verificar funciones de pausa/blacklist (análisis básico)
    final pauseAnalysis = await _analyzeTokenFunctions(normalizedMint);
    if (pauseAnalysis.hasPauseFunction == true) {
      risks.add('Token tiene función de pausa - puede ser detenido por el creator');
      score -= 30.0;
    }
    if (pauseAnalysis.hasBlacklistFunction == true) {
      risks.add('Token tiene función de blacklist - el creator puede bloquear wallets');
      score -= 30.0;
    }

    // 3. Verificar liquidez bloqueada
    final liquidityAnalysis = await _analyzeLiquidityLock(normalizedMint);
    if (liquidityAnalysis.isLiquidityLocked == false) {
      warnings.add('Liquidez no está bloqueada - el creator puede retirarla');
      score -= 15.0;
    }

    // 4. Verificar blacklists conocidas
    final blacklistCheck = await _checkBlacklists(normalizedMint);
    if (blacklistCheck.isInBlacklist == true) {
      risks.add('Token está en una blacklist conocida');
      score -= 50.0;
    }

    // 5. Analizar historial del creator (si está disponible)
    String? creatorAddress;
    int? creatorRugPullCount;
    if (holderAnalysis.creatorAddress != null) {
      creatorAddress = holderAnalysis.creatorAddress;
      final creatorHistory = await _analyzeCreatorHistory(creatorAddress!);
      creatorRugPullCount = creatorHistory.rugPullCount;
      if (creatorHistory.rugPullCount > 0) {
        risks.add(
          'Creator tiene historial de ${creatorHistory.rugPullCount} rug pull(s) previo(s)',
        );
        score -= 25.0 * creatorHistory.rugPullCount;
      }
    }

    // Asegurar que el score no sea negativo
    score = score.clamp(0.0, 100.0);

    final result = TokenSecurityScore(
      mint: normalizedMint,
      overallScore: score,
      isSafe: score >= 70.0,
      risks: risks,
      warnings: warnings,
      holderCount: holderAnalysis.holderCount,
      creatorAddress: creatorAddress,
      hasPauseFunction: pauseAnalysis.hasPauseFunction,
      hasBlacklistFunction: pauseAnalysis.hasBlacklistFunction,
      isLiquidityLocked: liquidityAnalysis.isLiquidityLocked,
      isInBlacklist: blacklistCheck.isInBlacklist,
      creatorRugPullHistory: creatorRugPullCount,
    );

      // Guardar en cache (los maps son mutables aunque sean final)
      _analysisCache[normalizedMint] = result;
      _analysisCacheTime[normalizedMint] = now;

    return result;
  }

  /// 📊 Analizar distribución de holders
  Future<_HolderAnalysis> _analyzeHolderDistribution(String mint) async {
    try {
      // Usar RPC para obtener token accounts
      final response = await _client
          .post(
            Uri.parse(_rpcUrl),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'jsonrpc': '2.0',
              'id': 1,
              'method': 'getProgramAccounts',
              'params': [
                'TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA', // SPL Token Program
                {
                  'filters': [
                    {
                      'dataSize': 165, // Token account size
                    },
                    {
                      'memcmp': {
                      'offset': 0,
                      'bytes': mint,
                      },
                    },
                  ],
                  'encoding': 'jsonParsed',
                },
              ],
            }),
          )
          .timeout(const Duration(seconds: 5));

      if (response.statusCode != 200) {
        return _HolderAnalysis();
      }

      final decoded = jsonDecode(response.body) as Map<String, dynamic>;
      final result = decoded['result'] as List<dynamic>?;
      if (result == null) {
        return _HolderAnalysis();
      }

      // Contar holders únicos (excluyendo cuentas con balance 0)
      final holders = <String>{};
      String? creatorAddress;

      for (final account in result) {
        if (account is! Map<String, dynamic>) continue;
        final accountData = account['account'] as Map<String, dynamic>?;
        final data = accountData?['data'] as Map<String, dynamic>?;
        final parsed = data?['parsed'] as Map<String, dynamic>?;
        final info = parsed?['info'] as Map<String, dynamic>?;
        final tokenAmount = info?['tokenAmount'] as Map<String, dynamic>?;
        final amount = tokenAmount?['amount'] as String?;
        final owner = info?['owner'] as String?;

        if (amount != null && owner != null) {
          final amountNum = int.tryParse(amount);
          if (amountNum != null && amountNum > 0) {
            holders.add(owner);
            // El primer holder con balance significativo podría ser el creator
            if (creatorAddress == null && amountNum > 1000000) {
              creatorAddress = owner;
            }
          }
        }
      }

      return _HolderAnalysis(
        holderCount: holders.length,
        creatorAddress: creatorAddress,
      );
    } catch (e) {
      // Si falla, retornar análisis vacío
      return _HolderAnalysis();
    }
  }

  /// 🔒 Analizar funciones del token (pausa/blacklist)
  Future<_TokenFunctionsAnalysis> _analyzeTokenFunctions(String mint) async {
    // ⚠️ NOTA: Análisis completo de bytecode requiere herramientas más avanzadas
    // Por ahora, hacemos una verificación básica usando el programa del token
    // En producción, esto debería usar análisis de bytecode o APIs especializadas

    try {
      // Obtener información del mint
      final response = await _client
          .post(
            Uri.parse(_rpcUrl),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'jsonrpc': '2.0',
              'id': 1,
              'method': 'getAccountInfo',
              'params': [
                mint,
                {'encoding': 'jsonParsed'},
              ],
            }),
          )
          .timeout(const Duration(seconds: 3));

      if (response.statusCode != 200) {
        return _TokenFunctionsAnalysis();
      }

      final decoded = jsonDecode(response.body) as Map<String, dynamic>;
      final result = decoded['result'] as Map<String, dynamic>?;
      final value = result?['value'] as Map<String, dynamic>?;
      final owner = value?['owner'] as String?;

      // Si el owner no es el programa estándar de SPL Token, podría tener funciones personalizadas
      const standardTokenProgram = 'TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA';
      final hasCustomProgram = owner != null && owner != standardTokenProgram;

      // ⚠️ Esta es una verificación básica. En producción, se necesita análisis de bytecode
      // Por ahora, asumimos que tokens con programas personalizados podrían tener funciones de pausa/blacklist
      return _TokenFunctionsAnalysis(
        hasPauseFunction: hasCustomProgram ? null : false, // null = desconocido
        hasBlacklistFunction: hasCustomProgram ? null : false,
      );
    } catch (e) {
      return _TokenFunctionsAnalysis();
    }
  }

  /// 💧 Analizar si la liquidez está bloqueada
  Future<_LiquidityAnalysis> _analyzeLiquidityLock(String mint) async {
    try {
      // Para tokens en pump.fun, la liquidez generalmente está bloqueada hasta la graduación
      // Verificar si el token está en la bonding curve o ya graduó
      final response = await _client
          .get(
            Uri.https('frontend-api-v3.pump.fun', '/coins/$mint'),
            headers: const {
              'accept': 'application/json',
              'user-agent': 'pump-it-baby/1.0',
            },
          )
          .timeout(const Duration(seconds: 3));

      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body) as Map<String, dynamic>;
        final isComplete = decoded['complete'] as bool? ?? false;

        // Si está en bonding curve (no completado), la liquidez está "bloqueada" hasta graduar
        // Si ya graduó, necesitaríamos verificar el pool de Raydium
        return _LiquidityAnalysis(
          isLiquidityLocked: !isComplete, // En bonding curve = bloqueada hasta graduar
        );
      }
    } catch (e) {
      // Si falla, asumir desconocido
    }

    return _LiquidityAnalysis();
  }

  /// 🚫 Verificar si el token está en blacklists conocidas
  Future<_BlacklistCheck> _checkBlacklists(String mint) async {
    // Por ahora, solo verificamos blacklists locales
    // En producción, esto debería consultar APIs públicas de blacklists
    final isInBlacklist = _knownBlacklists.contains(mint);

    return _BlacklistCheck(isInBlacklist: isInBlacklist);
  }

  /// 👤 Analizar historial del creator
  Future<_CreatorHistory> _analyzeCreatorHistory(String creatorAddress) async {
    // ⚠️ NOTA: Esto requiere análisis de transacciones del creator
    // Por ahora, retornamos un análisis básico
    // En producción, esto debería:
    // 1. Obtener todos los tokens creados por este address
    // 2. Verificar si alguno tuvo rug pulls (liquidez retirada, precio a 0, etc.)
    // 3. Contar cuántos rug pulls ha hecho

    try {
      if (_heliusApiKey == null) {
        return _CreatorHistory(rugPullCount: 0);
      }

      // Usar Helius Enhanced API para obtener transacciones del creator
      // Buscar patrones de rug pulls (ventas masivas, retiro de liquidez, etc.)
      // Por ahora, retornamos 0 (sin historial conocido)
      // TODO: Implementar análisis completo cuando tengamos más datos

      return _CreatorHistory(rugPullCount: 0);
    } catch (e) {
      return _CreatorHistory(rugPullCount: 0);
    }
  }

  void dispose() {
    _client.close();
  }
}

// Modelos internos para análisis
class _HolderAnalysis {
  _HolderAnalysis({
    this.holderCount,
    this.creatorAddress,
  });

  final int? holderCount;
  final String? creatorAddress;
}

class _TokenFunctionsAnalysis {
  _TokenFunctionsAnalysis({
    this.hasPauseFunction,
    this.hasBlacklistFunction,
  });

  final bool? hasPauseFunction; // null = desconocido
  final bool? hasBlacklistFunction; // null = desconocido
}

class _LiquidityAnalysis {
  _LiquidityAnalysis({
    this.isLiquidityLocked,
  });

  final bool? isLiquidityLocked; // null = desconocido
}

class _BlacklistCheck {
  _BlacklistCheck({
    this.isInBlacklist,
  });

  final bool? isInBlacklist;
}

class _CreatorHistory {
  _CreatorHistory({
    required this.rugPullCount,
  });

  final int rugPullCount;
}

final tokenSecurityAnalyzerProvider = Provider<TokenSecurityAnalyzer>((ref) {
  final service = TokenSecurityAnalyzer();
  ref.onDispose(service.dispose);
  return service;
});

