import 'dart:async';
import 'dart:io' as io;

import 'package:excel/excel.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../featured_coins/models/featured_coin.dart';
import '../controller/auto_invest_notifier.dart';
import '../models/execution_mode.dart';
import '../models/position.dart';

class TransactionAuditLogger {
  TransactionAuditLogger();

  io.File? _cachedFile;
  Excel? _excel;
  Sheet? _sheet;
  int _currentRow = 0;
  final Map<String, int> _criteriaStartRows = {};

  io.File _resolveFile() {
    final dir = io.Directory.current.path;
    final path = '$dir${io.Platform.pathSeparator}results.xlsx';
    return io.File(path);
  }

  Future<Excel> _getOrCreateExcel() async {
    if (_excel != null) return _excel!;

    final file = _cachedFile ??= _resolveFile();
    if (await file.exists()) {
      final bytes = await file.readAsBytes();
      _excel = Excel.decodeBytes(bytes);
    } else {
      _excel = Excel.createExcel();
      _excel!.delete('Sheet1');
    }

    _sheet = _excel!['Trades'];
    if (_sheet == null) {
      _sheet = _excel!['Trades'] =
          _excel!.sheets['Sheet1'] ?? _excel!.sheets.values.first;
    }

    // Encontrar la última fila usada
    _currentRow = _sheet!.maxRows;

    return _excel!;
  }

  String _getCriteriaHash(AutoInvestState state) {
    return '${state.minMarketCap}_${state.maxMarketCap}_${state.minLiquidity}_'
        '${state.minVolume24h}_${state.maxVolume24h}_${state.volumeTimeUnit.name}_${state.volumeTimeValue}_'
        '${state.minAgeValue}_${state.maxAgeValue}_${state.ageTimeUnit.name}_'
        '${state.minReplies}_${state.stopLossPercent}_${state.takeProfitPercent}';
  }

  Future<void> _writeCriteriaHeader(AutoInvestState state) async {
    if (kIsWeb) return;

    try {
      final excel = await _getOrCreateExcel();
      final sheet = _sheet!;

      final criteriaHash = _getCriteriaHash(state);

      // Si ya existe este criterio, no escribir de nuevo
      if (_criteriaStartRows.containsKey(criteriaHash)) {
        _currentRow = _criteriaStartRows[criteriaHash]!;
        return;
      }

      // Si no es el primer criterio, dejar una fila en blanco
      if (_currentRow > 0) {
        _currentRow += 2;
      }

      final criteriaStartRow = _currentRow;
      _criteriaStartRows[criteriaHash] = criteriaStartRow;

      // Título de sección
      sheet
          .cell(
            CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: _currentRow),
          )
          .value = TextCellValue(
        'CRITERIOS DE MERCADO',
      );
      _applyHeaderStyle(
        sheet,
        CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: _currentRow),
      );
      sheet.merge(
        CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: _currentRow),
        CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: _currentRow),
      );
      _currentRow++;

      // Criterios en formato clave-valor
      final criteria = [
        ['MC Mínima (USD)', state.minMarketCap.toStringAsFixed(2)],
        ['MC Máxima (USD)', state.maxMarketCap.toStringAsFixed(2)],
        ['Liquidez Mínima (USD)', state.minLiquidity.toStringAsFixed(2)],
        ['Volumen Mínimo', state.minVolume24h.toStringAsFixed(2)],
        ['Volumen Máximo', state.maxVolume24h.toStringAsFixed(2)],
        ['Unidad Volumen', state.volumeTimeUnit.name],
        ['Tiempo Volumen', state.volumeTimeValue.toStringAsFixed(0)],
        ['Edad Mínima', state.minAgeValue.toStringAsFixed(0)],
        ['Edad Máxima', state.maxAgeValue.toStringAsFixed(0)],
        ['Unidad Edad', state.ageTimeUnit.name],
        ['Mínimo Replies', state.minReplies.toStringAsFixed(0)],
        ['Stop Loss %', state.stopLossPercent.toStringAsFixed(2)],
        ['Take Profit %', state.takeProfitPercent.toStringAsFixed(2)],
      ];

      for (var i = 0; i < criteria.length; i++) {
        sheet
            .cell(
              CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: _currentRow),
            )
            .value = TextCellValue(
          criteria[i][0],
        );
        sheet
            .cell(
              CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: _currentRow),
            )
            .value = TextCellValue(
          criteria[i][1],
        );
        _applyCriteriaStyle(
          sheet,
          CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: _currentRow),
        );
        _applyCriteriaStyle(
          sheet,
          CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: _currentRow),
        );
        _currentRow++;
      }

      // Encabezado de columnas de trades
      _currentRow++;
      final headers = [
        'Timestamp',
        'Side',
        'Symbol',
        'Name',
        'Mint',
        'Mode',
        'Entry SOL',
        'Exit SOL',
        'Token Amount',
        'Entry Price SOL',
        'Exit Price SOL',
        'PnL SOL',
        'PnL %',
        'Buy TX',
        'Buy Solscan',
        'Sell TX',
        'Sell Solscan',
        'MC SOL',
        'MC USD',
        'Created At',
        'Last Reply',
        'Replies',
        'Twitter',
        'Telegram',
        'Website',
        'Close Reason',
        'Entry Fee',
        'Exit Fee',
        'Net PnL',
      ];

      for (var i = 0; i < headers.length; i++) {
        final cell = sheet.cell(
          CellIndex.indexByColumnRow(columnIndex: i, rowIndex: _currentRow),
        );
        cell.value = TextCellValue(headers[i]);
        _applyHeaderStyle(
          sheet,
          CellIndex.indexByColumnRow(columnIndex: i, rowIndex: _currentRow),
        );
      }
      _currentRow++;

      // Guardar asíncronamente (no bloquea)
      unawaited(_saveExcel(excel));
    } catch (e) {
      // Log error pero no bloquear el flujo principal
      debugPrint('Error writing criteria header to Excel: $e');
    }
  }

  void _applyHeaderStyle(Sheet sheet, CellIndex cellIndex) {
    final cell = sheet.cell(cellIndex);
    cell.cellStyle = CellStyle(
      backgroundColorHex: ExcelColor.fromHexString('4472C4'),
      fontColorHex: ExcelColor.fromHexString('FFFFFF'),
      bold: true,
      horizontalAlign: HorizontalAlign.Center,
      verticalAlign: VerticalAlign.Center,
    );
  }

  void _applyCriteriaStyle(Sheet sheet, CellIndex cellIndex) {
    final cell = sheet.cell(cellIndex);
    cell.cellStyle = CellStyle(
      backgroundColorHex: ExcelColor.fromHexString('D9E1F2'),
      bold: true,
    );
  }

  void _applyWinStyle(Sheet sheet, CellIndex cellIndex) {
    final cell = sheet.cell(cellIndex);
    cell.cellStyle = CellStyle(
      backgroundColorHex: ExcelColor.fromHexString('C6EFCE'),
      fontColorHex: ExcelColor.fromHexString('006100'),
    );
  }

  void _applyLossStyle(Sheet sheet, CellIndex cellIndex) {
    final cell = sheet.cell(cellIndex);
    cell.cellStyle = CellStyle(
      backgroundColorHex: ExcelColor.fromHexString('FFC7CE'),
      fontColorHex: ExcelColor.fromHexString('9C0006'),
    );
  }

  Future<void> _saveExcel(Excel excel) async {
    if (kIsWeb) return;
    try {
      final file = _cachedFile ??= _resolveFile();
      final bytes = excel.encode();
      if (bytes != null) {
        await file.writeAsBytes(bytes);
        debugPrint('Excel guardado exitosamente en: ${file.path}');
      } else {
        debugPrint('Error: Excel.encode() retornó null');
      }
    } catch (e) {
      debugPrint('Error guardando Excel: $e');
    }
  }

  Future<void> logBuyFromFeatured({
    required FeaturedCoin coin,
    required String signature,
    required double entrySol,
    required AutoInvestExecutionMode mode,
    required AutoInvestState state,
    double? entryPriceSol,
  }) async {
    if (kIsWeb) return;

    // ⚡ ASÍNCRONO: No esperar, actualizar en background
    unawaited(
      _logBuyFromFeaturedInternal(
        coin: coin,
        signature: signature,
        entrySol: entrySol,
        mode: mode,
        state: state,
        entryPriceSol: entryPriceSol,
      ),
    );
  }

  Future<void> _logBuyFromFeaturedInternal({
    required FeaturedCoin coin,
    required String signature,
    required double entrySol,
    required AutoInvestExecutionMode mode,
    required AutoInvestState state,
    double? entryPriceSol,
  }) async {
    try {
      final excel = await _getOrCreateExcel();
      final sheet = _sheet!;

      await _writeCriteriaHeader(state);

      final buySolscan = 'https://solscan.io/tx/$signature';

      final row = [
        DateTime.now().toIso8601String(),
        'BUY',
        coin.symbol,
        coin.name,
        coin.mint,
        mode.name,
        entrySol.toStringAsFixed(8),
        '',
        '',
        entryPriceSol?.toStringAsFixed(8) ?? '',
        '',
        '',
        '',
        signature,
        buySolscan,
        '',
        '',
        coin.marketCapSol.toStringAsFixed(3),
        coin.usdMarketCap.toStringAsFixed(2),
        coin.createdAt.toIso8601String(),
        coin.lastReplyAt?.toIso8601String() ?? '',
        coin.replyCount.toString(),
        coin.twitterUrl?.toString() ?? '',
        coin.telegramUrl?.toString() ?? '',
        coin.websiteUrl?.toString() ?? '',
        '',
        '',
        '',
        '',
      ];

      for (var i = 0; i < row.length; i++) {
        final cell = sheet.cell(
          CellIndex.indexByColumnRow(columnIndex: i, rowIndex: _currentRow),
        );
        cell.value = TextCellValue(row[i]);
      }
      _currentRow++;

      // Guardar asíncronamente sin esperar
      unawaited(_saveExcel(excel));
    } catch (e) {
      // Log error pero no bloquear el flujo principal
      debugPrint('Error logging buy transaction to Excel: $e');
    }
  }

  Future<void> logSellFromPosition({
    required OpenPosition position,
    required String signature,
    required double expectedExitSol,
    required AutoInvestState state,
    double? realizedExitSol,
    double? pnlSol,
    double? pnlPercent,
    PositionAlertType? reason,
    FeaturedCoin? coin,
  }) async {
    if (kIsWeb) return;

    // ⚡ ASÍNCRONO: No esperar, actualizar en background
    unawaited(
      _logSellFromPositionInternal(
        position: position,
        signature: signature,
        expectedExitSol: expectedExitSol,
        state: state,
        realizedExitSol: realizedExitSol,
        pnlSol: pnlSol,
        pnlPercent: pnlPercent,
        reason: reason,
        coin: coin,
      ),
    );
  }

  Future<void> _logSellFromPositionInternal({
    required OpenPosition position,
    required String signature,
    required double expectedExitSol,
    required AutoInvestState state,
    double? realizedExitSol,
    double? pnlSol,
    double? pnlPercent,
    PositionAlertType? reason,
    FeaturedCoin? coin,
  }) async {
    try {
      final excel = await _getOrCreateExcel();
      final sheet = _sheet!;

      await _writeCriteriaHeader(state);

      final sellSolscan = 'https://solscan.io/tx/$signature';
      final buySolscan = 'https://solscan.io/tx/${position.entrySignature}';

      final exitSol = realizedExitSol ?? expectedExitSol;
      final finalPnlSol =
          pnlSol ??
          (realizedExitSol != null
              ? (realizedExitSol - position.entrySol)
              : null);
      final finalPnlPercent =
          pnlPercent ??
          (position.entrySol > 0 && finalPnlSol != null
              ? (finalPnlSol / position.entrySol) * 100
              : null);

      final row = [
        DateTime.now().toIso8601String(),
        'SELL',
        position.symbol,
        coin?.name ?? '',
        position.mint,
        position.executionMode.name,
        position.entrySol.toStringAsFixed(8),
        exitSol.toStringAsFixed(8),
        position.tokenAmount?.toStringAsFixed(8) ?? '',
        position.entryPriceSol?.toStringAsFixed(8) ?? '',
        position.lastPriceSol?.toStringAsFixed(8) ?? '',
        finalPnlSol?.toStringAsFixed(8) ?? '',
        finalPnlPercent?.toStringAsFixed(4) ?? '',
        position.entrySignature,
        buySolscan,
        signature,
        sellSolscan,
        coin?.marketCapSol.toStringAsFixed(3) ?? '',
        coin?.usdMarketCap.toStringAsFixed(2) ?? '',
        position.openedAt.toIso8601String(),
        coin?.lastReplyAt?.toIso8601String() ?? '',
        coin?.replyCount.toString() ?? '',
        coin?.twitterUrl?.toString() ?? '',
        coin?.telegramUrl?.toString() ?? '',
        coin?.websiteUrl?.toString() ?? '',
        reason?.label ?? '',
        position.entryFeeSol?.toStringAsFixed(8) ?? '',
        position.exitFeeSol?.toStringAsFixed(8) ?? '',
        (finalPnlSol != null &&
                        position.entryFeeSol != null &&
                        position.exitFeeSol != null
                    ? (finalPnlSol -
                          position.entryFeeSol! -
                          position.exitFeeSol!)
                    : null)
                ?.toStringAsFixed(8) ??
            '',
      ];

      for (var i = 0; i < row.length; i++) {
        final cellIndex = CellIndex.indexByColumnRow(
          columnIndex: i,
          rowIndex: _currentRow,
        );
        final cell = sheet.cell(cellIndex);
        cell.value = TextCellValue(row[i]);

        // Aplicar color según win/loss
        if (i == 11 && finalPnlSol != null) {
          // Columna PnL SOL
          if (finalPnlSol >= 0) {
            _applyWinStyle(sheet, cellIndex);
          } else {
            _applyLossStyle(sheet, cellIndex);
          }
        }
        if (i == 12 && finalPnlPercent != null) {
          // Columna PnL %
          if (finalPnlPercent >= 0) {
            _applyWinStyle(sheet, cellIndex);
          } else {
            _applyLossStyle(sheet, cellIndex);
          }
        }
      }
      _currentRow++;

      // Actualizar estadísticas asíncronamente
      unawaited(_updateStatistics(excel, state));

      // Guardar asíncronamente sin esperar
      unawaited(_saveExcel(excel));
    } catch (e) {
      // Log error pero no bloquear el flujo principal
      debugPrint('Error logging sell transaction to Excel: $e');
    }
  }

  Future<void> _updateStatistics(Excel excel, AutoInvestState state) async {
    if (kIsWeb) return;

    // Crear o obtener hoja de estadísticas
    if (!excel.sheets.containsKey('Statistics')) {
      if (excel.sheets.containsKey('Trades')) {
        excel.copy('Trades', 'Statistics');
      } else {
        return; // No hay hoja Trades para copiar
      }
    }
    final statsSheet = excel['Statistics'];

    // Limpiar hoja de estadísticas (eliminar todas las filas)
    final maxRows = statsSheet.maxRows;
    for (var i = maxRows - 1; i >= 0; i--) {
      statsSheet.removeRow(i);
    }

    // Estadísticas generales
    final allTrades = state.closedPositions;
    final totalTrades = allTrades.length;
    final wins = allTrades.where((p) => p.pnlSol >= 0).length;
    final losses = totalTrades - wins;
    final winRate = totalTrades > 0 ? (wins / totalTrades * 100) : 0.0;
    final totalPnl = allTrades.fold<double>(0, (sum, p) => sum + p.pnlSol);
    final totalNetPnl = allTrades.fold<double>(
      0,
      (sum, p) => sum + (p.netPnlSol ?? p.pnlSol),
    );

    int row = 0;

    // Título
    statsSheet
        .cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row))
        .value = TextCellValue(
      'ESTADÍSTICAS GENERALES',
    );
    _applyHeaderStyle(
      statsSheet,
      CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row),
    );
    statsSheet.merge(
      CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row),
      CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: row),
    );
    row++;

    // Headers
    final statHeaders = ['Métrica', 'Valor'];
    for (var i = 0; i < statHeaders.length; i++) {
      statsSheet
          .cell(CellIndex.indexByColumnRow(columnIndex: i, rowIndex: row))
          .value = TextCellValue(
        statHeaders[i],
      );
      _applyHeaderStyle(
        statsSheet,
        CellIndex.indexByColumnRow(columnIndex: i, rowIndex: row),
      );
    }
    row++;

    // Valores
    final generalStats = [
      ['Total Trades', totalTrades.toString()],
      ['Trades Exitosos', wins.toString()],
      ['Trades Perdidos', losses.toString()],
      ['Win Rate %', winRate.toStringAsFixed(2)],
      ['PnL Total SOL', totalPnl.toStringAsFixed(8)],
      ['PnL Neto SOL', totalNetPnl.toStringAsFixed(8)],
    ];

    for (var stat in generalStats) {
      statsSheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row))
          .value = TextCellValue(
        stat[0],
      );
      statsSheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: row))
          .value = TextCellValue(
        stat[1],
      );
      row++;
    }

    // Estadísticas por grupo de criterios
    row += 2;
    statsSheet
        .cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row))
        .value = TextCellValue(
      'ESTADÍSTICAS POR CRITERIOS',
    );
    _applyHeaderStyle(
      statsSheet,
      CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row),
    );
    statsSheet.merge(
      CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row),
      CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: row),
    );
    row++;

    // Agrupar trades por criterios usando el hash actual
    final currentCriteriaHash = _getCriteriaHash(state);
    final criteriaGroups = <String, List<ClosedPosition>>{};

    // Por ahora, agrupar todos los trades bajo el criterio actual
    // En el futuro se puede mejorar para rastrear qué criterios se usaron en cada trade
    criteriaGroups[currentCriteriaHash] = allTrades;

    for (final entry in criteriaGroups.entries) {
      final trades = entry.value;
      final groupTotal = trades.length;
      final groupWins = trades.where((p) => p.pnlSol >= 0).length;
      final groupLosses = groupTotal - groupWins;
      final groupWinRate = groupTotal > 0
          ? (groupWins / groupTotal * 100)
          : 0.0;
      final groupPnl = trades.fold<double>(0, (sum, p) => sum + p.pnlSol);
      final groupNetPnl = trades.fold<double>(
        0,
        (sum, p) => sum + (p.netPnlSol ?? p.pnlSol),
      );

      row++;
      statsSheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row))
          .value = TextCellValue(
        'Grupo de Criterios',
      );
      _applyCriteriaStyle(
        statsSheet,
        CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row),
      );
      statsSheet.merge(
        CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row),
        CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: row),
      );
      row++;

      final groupStats = [
        ['Total Trades', groupTotal.toString()],
        ['Trades Exitosos', groupWins.toString()],
        ['Trades Perdidos', groupLosses.toString()],
        ['Win Rate %', groupWinRate.toStringAsFixed(2)],
        ['PnL Total SOL', groupPnl.toStringAsFixed(8)],
        ['PnL Neto SOL', groupNetPnl.toStringAsFixed(8)],
      ];

      for (var stat in groupStats) {
        statsSheet
            .cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row))
            .value = TextCellValue(
          stat[0],
        );
        statsSheet
            .cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: row))
            .value = TextCellValue(
          stat[1],
        );
        row++;
      }
    }

    // Ajustar ancho de columnas
    statsSheet.setColumnWidth(0, 25.0);
    statsSheet.setColumnWidth(1, 15.0);

    // Guardar estadísticas
    unawaited(_saveExcel(excel));
  }
}

final transactionAuditLoggerProvider = Provider<TransactionAuditLogger>((ref) {
  return TransactionAuditLogger();
});
