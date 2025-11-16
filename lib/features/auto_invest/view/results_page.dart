import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../controller/auto_invest_executor.dart';
import '../controller/auto_invest_notifier.dart';
import '../controller/compat_shims.dart';
import '../models/execution_record.dart';
import '../models/position.dart';
import '../models/simulation_models.dart';
import '../../../core/widgets/soft_surface.dart';
import 'widgets/analysis_drawer_panel.dart';

class SimulationResultsPage extends ConsumerStatefulWidget {
  const SimulationResultsPage({super.key});

  @override
  ConsumerState<SimulationResultsPage> createState() =>
      _SimulationResultsPageState();
}

class _SimulationResultsPageState extends ConsumerState<SimulationResultsPage> {
  bool _analysisCollapsed = false;

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(autoInvestProvider);
    final notifier = ref.read(autoInvestProvider.notifier);
    final executor = ref.read(autoInvestExecutorProvider);
    final hasExecutions = state.executions.isNotEmpty;
    final hasSimulations = state.simulations.isNotEmpty;
    final hasPositions = state.positions.isNotEmpty;
    final hasClosedPositions = state.closedPositions.isNotEmpty;

    if (!hasExecutions &&
        !hasSimulations &&
        !hasPositions &&
        !hasClosedPositions) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Text(
            'Aún no hay simulaciones, órdenes ni posiciones guardadas.\n'
            'Usa la pestaña Auto invest para lanzar una simulación o activar el bot.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    final analysisPanel = AnalysisDrawerPanel(
      summary: state.analysisSummary,
      isLoading: state.isAnalyzingResults,
      onAnalyze: notifier.analyzeClosedPositions,
      collapsed: _analysisCollapsed,
      onToggle: () {
        setState(() {
          _analysisCollapsed = !_analysisCollapsed;
        });
      },
    );

    Widget buildMainList({required bool includeAnalysis}) {
      final children = <Widget>[];
      children
        ..add(
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFEF5350),
                foregroundColor: Colors.white,
              ),
              icon: const Icon(Icons.warning_amber_rounded),
              label: const Text('Reset resultados'),
              onPressed: () async {
                final confirmed =
                    await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: const Text('Resetear resultados'),
                        content: const Text(
                          'Esto limpia simulaciones, ejecuciones y cerradas solo en la app.\nEl archivo CSV no se toca.',
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.of(ctx).pop(false),
                            child: const Text('Cancelar'),
                          ),
                          FilledButton(
                            onPressed: () => Navigator.of(ctx).pop(true),
                            child: const Text('Resetear'),
                          ),
                        ],
                      ),
                    ) ??
                    false;
                if (confirmed) {
                  notifier.resetResults();
                }
              },
            ),
          ),
        )
        ..add(const SizedBox(height: 12))
        ..add(_ResultsOverview(state: state))
        ..add(const SizedBox(height: 24));
      if (hasPositions) {
        children
          ..add(
            Text(
              'Posiciones abiertas',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          )
          ..add(const SizedBox(height: 8))
          ..addAll(
            state.positions.reversed.map(
              (position) => _PositionTile(
                position: position,
                solPriceUsd: state.solPriceUsd,
                onSell: () => executor.sellPosition(position),
                onRemove: () => notifier.removePosition(
                  position.entrySignature,
                  refundBudget: true,
                  message: 'Posición ${position.symbol} eliminada manualmente.',
                ),
              ),
            ),
          )
          ..add(const SizedBox(height: 24));
      }
      if (hasClosedPositions) {
        children.add(
          _SectionDrawer(
            title: 'Posiciones cerradas (${state.closedPositions.length})',
            children: state.closedPositions.reversed
                .take(50)
                .map(
                  (position) => _ClosedPositionTile(
                    position: position,
                    solPriceUsd: state.solPriceUsd,
                  ),
                )
                .toList(),
          ),
        );
        children.add(const SizedBox(height: 16));
      }
      if (hasExecutions) {
        children.add(
          _SectionDrawer(
            title: 'Ordenes reales (${state.executions.length})',
            children: state.executions.reversed
                .map((record) => _ExecutionTile(record: record))
                .toList(),
          ),
        );
        children.add(const SizedBox(height: 16));
      }
      if (hasSimulations) {
        children
          ..add(
            Text(
              'Simulaciones',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          )
          ..add(const SizedBox(height: 8))
          ..addAll(
            state.simulations.reversed.map(
              (run) => _SimulationRunTile(run: run),
            ),
          );
      }
      if (includeAnalysis) {
        children
          ..add(const SizedBox(height: 16))
          ..add(analysisPanel);
      }
      return ListView(
        padding: const EdgeInsets.all(16),
        physics: const BouncingScrollPhysics(),
        children: children,
      );
    }

    return SafeArea(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isWide = constraints.maxWidth > 1100;
          if (!isWide) {
            return buildMainList(includeAnalysis: true);
          }
          final drawerWidth = math.max(320.0, constraints.maxWidth * 0.28);
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: buildMainList(includeAnalysis: false)),
              const SizedBox(width: 16),
              SizedBox(
                width: drawerWidth,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.only(right: 16, top: 16),
                  child: analysisPanel,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _ResultsOverview extends StatelessWidget {
  const _ResultsOverview({required this.state});

  final AutoInvestState state;

  @override
  Widget build(BuildContext context) {
    final solPrice = state.solPriceUsd;
    final theme = Theme.of(context);
    final openExposure = state.positions.fold<double>(
      0,
      (sum, p) => sum + p.entrySol,
    );
    final unrealized = state.positions.fold<double>(
      0,
      (sum, p) => sum + (p.pnlSol ?? 0),
    );
    final closedCount = state.closedPositions.length;
    final grossRealized = state.closedPositions.fold<double>(
      0,
      (sum, p) => sum + p.pnlSol,
    );
    final netRealized = state.closedPositions.fold<double>(
      0,
      (sum, p) =>
          sum +
          (p.netPnlSol ??
              (p.pnlSol - (p.entryFeeSol ?? 0) - (p.exitFeeSol ?? 0))),
    );
    final entryFees = state.closedPositions.fold<double>(
      0,
      (sum, p) => sum + (p.entryFeeSol ?? 0),
    );
    final exitFees = state.closedPositions.fold<double>(
      0,
      (sum, p) => sum + (p.exitFeeSol ?? 0),
    );
    final wins = state.closedPositions
        .where((p) => p.pnlSol >= 0)
        .length
        .toDouble();
    final winRate = closedCount == 0 ? 0.0 : (wins / closedCount) * 100;
    final avgHoldMinutes = closedCount == 0
        ? 0.0
        : state.closedPositions.fold<double>(
                0,
                (sum, p) =>
                    sum +
                    p.closedAt
                        .difference(p.openedAt)
                        .inMinutes
                        .abs()
                        .toDouble(),
              ) /
              closedCount;
    const cardBlue = Color(0xFF102552);
    const cardPurple = Color(0xFF1A1F4B);
    const cardGreen = Color(0xFF0C2B2B);
    const cardGray = Color(0xFF1B2338);

    final metrics = [
      _MetricData(
        icon: Icons.account_balance_wallet_outlined,
        label: 'Presupuesto disponible',
        value: _formatSol(state.availableBudgetSol, solPrice),
        caption: 'Total ${_formatSol(state.totalBudgetSol, solPrice)}',
        accent: theme.colorScheme.primary,
        tone: cardBlue,
      ),
      _MetricData(
        icon: Icons.layers_outlined,
        label: 'Exposición abierta',
        value: _formatSol(openExposure, solPrice),
        caption:
            '${state.positions.length} posiciones | ${_formatSigned(unrealized, solPrice)} sin realizar',
        accent: theme.colorScheme.secondary,
        tone: cardPurple,
      ),
      _MetricData(
        icon: Icons.trending_up,
        label: 'PnL bruto realizado',
        value: _formatSigned(grossRealized, solPrice),
        caption: 'Net ${_formatSigned(netRealized, solPrice)}',
        accent: grossRealized >= 0 ? Colors.greenAccent : Colors.redAccent,
        tone: cardGreen,
      ),
      _MetricData(
        icon: Icons.receipt_long,
        label: 'Fees pagadas',
        value: _formatSol(entryFees + exitFees, solPrice),
        caption:
            'Entrada ${_formatSol(entryFees, solPrice)} | Salida ${_formatSol(exitFees, solPrice)}',
        accent: theme.colorScheme.tertiary,
        tone: cardGray,
        valueColor: Colors.white,
      ),
      _MetricData(
        icon: Icons.wifi_tethering,
        label: 'Win rate',
        value: '${winRate.toStringAsFixed(1)}%',
        caption:
            'Hold promedio ${_formatMinutes(avgHoldMinutes)} | $closedCount cerradas',
        accent: Colors.blueAccent,
        tone: cardBlue,
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.maxWidth;
        final columns = maxWidth > 1000
            ? 3
            : maxWidth > 640
            ? 2
            : 1;
        final itemWidth = columns == 1
            ? maxWidth
            : (maxWidth - (columns - 1) * 16) / columns;
        return SoftSurface(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Salud del portafolio', style: theme.textTheme.titleLarge),
              const SizedBox(height: 4),
              Text(
                'Resumen rápido de presupuesto, exposición y resultados netos.',
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 16,
                runSpacing: 12,
                children: metrics
                    .map(
                      (metric) => SizedBox(
                        width: columns == 1 ? maxWidth : itemWidth,
                        child: _MetricCard(data: metric),
                      ),
                    )
                    .toList(),
              ),
            ],
          ),
        );
      },
    );
  }

  String _formatSol(double value, double solPrice) {
    final base = value.toStringAsFixed(2);
    if (solPrice <= 0) return '$base SOL';
    return '$base SOL (\$${(value * solPrice).toStringAsFixed(2)})';
  }

  String _formatSigned(double value, double solPrice) {
    final prefix = value >= 0 ? '+' : '';
    return '$prefix${_formatSol(value, solPrice)}';
  }

  String _formatMinutes(double minutes) {
    if (minutes == 0) return '0 min';
    if (minutes >= 60) {
      final hours = minutes ~/ 60;
      final remaining = (minutes % 60).round();
      return '${hours}h ${remaining}m';
    }
    return '${minutes.toStringAsFixed(0)} min';
  }
}

class _MetricData {
  const _MetricData({
    required this.icon,
    required this.label,
    required this.value,
    this.caption,
    this.accent,
    this.tone,
    this.valueColor,
  });

  final IconData icon;
  final String label;
  final String value;
  final String? caption;
  final Color? accent;
  final Color? tone;
  final Color? valueColor;
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({required this.data});

  final _MetricData data;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = data.accent ?? theme.colorScheme.primary;
    final baseTone = data.tone ?? theme.colorScheme.surface;
    return SoftSurface(
      color: baseTone,
      gradient: LinearGradient(
        colors: [
          baseTone.withValues(alpha: 0.95),
          baseTone.withValues(alpha: 0.7),
        ],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(data.icon, color: accent),
              const SizedBox(width: 8),
              Text(data.label, style: theme.textTheme.titleSmall),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            data.value,
            style: theme.textTheme.headlineSmall?.copyWith(
              color: data.valueColor ?? accent,
            ),
          ),
          if (data.caption != null) ...[
            const SizedBox(height: 4),
            Text(data.caption!, style: theme.textTheme.bodySmall),
          ],
        ],
      ),
    );
  }
}

class _SectionDrawer extends StatefulWidget {
  const _SectionDrawer({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  State<_SectionDrawer> createState() => _SectionDrawerState();
}

class _SectionDrawerState extends State<_SectionDrawer> {
  bool _expanded = true;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SoftSurface(
      margin: const EdgeInsets.only(bottom: 16),
      padding: EdgeInsets.zero,
      child: Theme(
        data: theme.copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: _expanded,
          onExpansionChanged: (value) => setState(() => _expanded = value),
          tilePadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          iconColor: theme.colorScheme.primary,
          collapsedIconColor: theme.colorScheme.primary,
          title: Text(widget.title, style: theme.textTheme.titleMedium),
          childrenPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 12,
          ),
          children: [...widget.children, const SizedBox(height: 4)],
        ),
      ),
    );
  }
}

class _PositionTile extends StatelessWidget {
  const _PositionTile({
    required this.position,
    required this.solPriceUsd,
    this.onSell,
    this.onRemove,
  });

  final OpenPosition position;
  final double solPriceUsd;
  final VoidCallback? onSell;
  final VoidCallback? onRemove;

  String _shorten(String value) {
    if (value.length <= 12) {
      return value;
    }
    return '${value.substring(0, 6)}...${value.substring(value.length - 4)}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokenAmount = position.tokenAmount;
    final tokenLabel = tokenAmount == null
        ? 'Fill pendiente'
        : '${tokenAmount.toStringAsFixed(4)} tokens';
    final opened = DateFormat('dd/MM HH:mm').format(position.openedAt);
    final signatureShort = _shorten(position.entrySignature);
    final mintShort = _shorten(position.mint);
    final lastPrice = position.lastPriceSol;
    final currentValue = position.currentValueSol;
    final pnlSol = position.pnlSol;
    final pnlPercent = position.pnlPercent;
    final pnlColor = pnlSol == null
        ? theme.textTheme.bodyMedium?.color ?? Colors.white
        : pnlSol >= 0
        ? Colors.greenAccent
        : Colors.redAccent;
    final lastCheckedAt = position.lastCheckedAt;
    final checkedLabel = lastCheckedAt == null
        ? 'Sin monitoreo reciente'
        : 'Ultima lectura ${DateFormat('HH:mm:ss').format(lastCheckedAt)}';
    final entryFee = position.entryFeeSol;

    String solWithUsd(double value) {
      final base = '${value.toStringAsFixed(3)} SOL';
      if (solPriceUsd <= 0) return base;
      return '$base (\$${(value * solPriceUsd).toStringAsFixed(2)})';
    }

    String priceWithUsd(double? value) {
      if (value == null) return 'Precio pendiente';
      final base = '${value.toStringAsFixed(6)} SOL';
      if (solPriceUsd <= 0) return base;
      return '$base (\$${(value * solPriceUsd).toStringAsFixed(4)})';
    }

    final priceText = priceWithUsd(lastPrice ?? position.entryPriceSol);
    final valueText = currentValue == null
        ? 'Valor pendiente'
        : solWithUsd(currentValue);
    final pnlText = pnlSol == null
        ? 'PnL pendiente'
        : '${pnlSol >= 0 ? '+' : ''}${solWithUsd(pnlSol)}'
              '${pnlPercent == null ? '' : ' (${pnlPercent.toStringAsFixed(2)}%)'}';
    final iconColor = pnlSol == null
        ? theme.colorScheme.primary
        : pnlSol >= 0
        ? Colors.greenAccent
        : Colors.redAccent;

    return SoftSurface(
      margin: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _SoftIconCircle(icon: Icons.ssid_chart, color: iconColor),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(position.symbol, style: theme.textTheme.titleMedium),
                    const SizedBox(height: 4),
                    Text(
                      'Entrada ${solWithUsd(position.entrySol)} | ${position.executionMode.name}',
                      style: theme.textTheme.bodyMedium,
                    ),
                    Text(
                      'Mint $mintShort | Tx $signatureShort',
                      style: theme.textTheme.bodySmall,
                    ),
                    Text(
                      'Apertura $opened | $checkedLabel',
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(valueText, style: theme.textTheme.labelMedium),
                  Text(
                    pnlText,
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: pnlColor,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 12,
            runSpacing: 10,
            children: [
              _InfoBadge(icon: Icons.token, label: 'Tokens', value: tokenLabel),
              _InfoBadge(
                icon: Icons.price_check,
                label: 'Precio',
                value: priceText,
              ),
              _InfoBadge(
                icon: Icons.shield,
                label: 'Fee entrada',
                value: entryFee == null ? 'Pendiente' : solWithUsd(entryFee),
              ),
              _InfoBadge(
                icon: Icons.alarm,
                label: 'Alerta',
                value: position.alertType?.label ?? 'Ninguna',
                color: position.alertType == PositionAlertType.takeProfit
                    ? Colors.greenAccent
                    : position.alertType == PositionAlertType.stopLoss
                    ? Colors.redAccent
                    : theme.colorScheme.primary,
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              if (onSell != null)
                FilledButton.tonalIcon(
                  onPressed: position.isClosing ? null : onSell,
                  icon: position.isClosing
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.sell),
                  label: Text(
                    position.isClosing ? 'Vendiendo...' : 'Vender ahora',
                  ),
                ),
              const Spacer(),
              Wrap(
                spacing: 6,
                children: [
                  _CircleIconButton(
                    tooltip: 'Copiar signature',
                    icon: Icons.copy,
                    onPressed: () async {
                      await Clipboard.setData(
                        ClipboardData(text: position.entrySignature),
                      );
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Signature copiada')),
                        );
                      }
                    },
                  ),
                  _CircleIconButton(
                    tooltip: 'Abrir en pump.fun',
                    icon: Icons.rocket_launch,
                    onPressed: () async {
                      final uri = Uri.parse(
                        'https://pump.fun/${position.mint}',
                      );
                      if (await canLaunchUrl(uri)) {
                        await launchUrl(
                          uri,
                          mode: LaunchMode.externalApplication,
                        );
                      }
                    },
                  ),
                  _CircleIconButton(
                    tooltip: 'Abrir en Solscan',
                    icon: Icons.open_in_new,
                    onPressed: () async {
                      final uri = Uri.parse(
                        'https://solscan.io/tx/${position.entrySignature}',
                      );
                      if (await canLaunchUrl(uri)) {
                        await launchUrl(
                          uri,
                          mode: LaunchMode.externalApplication,
                        );
                      }
                    },
                  ),
                  if (onRemove != null)
                    _CircleIconButton(
                      tooltip: 'Eliminar posición',
                      icon: Icons.delete_outline,
                      onPressed: position.isClosing ? null : onRemove,
                    ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ClosedPositionTile extends StatelessWidget {
  const _ClosedPositionTile({
    required this.position,
    required this.solPriceUsd,
  });

  final ClosedPosition position;
  final double solPriceUsd;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final opened = DateFormat('dd/MM HH:mm').format(position.openedAt);
    final closed = DateFormat('dd/MM HH:mm').format(position.closedAt);
    final pnlColor = position.pnlSol >= 0
        ? Colors.greenAccent
        : Colors.redAccent;
    final reason = position.closeReason?.label ?? 'Manual';
    final entryFee = position.entryFeeSol ?? 0;
    final exitFee = position.exitFeeSol ?? 0;
    final netPnl = position.netPnlSol ?? (position.pnlSol - entryFee - exitFee);
    final holdMinutes = position.closedAt
        .difference(position.openedAt)
        .inMinutes
        .abs();

    String solWithUsd(double value) {
      final base = '${value.toStringAsFixed(3)} SOL';
      if (solPriceUsd <= 0) return base;
      return '$base (\$${(value * solPriceUsd).toStringAsFixed(2)})';
    }

    String priceWithUsd(double value) {
      final base = '${value.toStringAsFixed(6)} SOL';
      if (solPriceUsd <= 0) return base;
      return '$base (\$${(value * solPriceUsd).toStringAsFixed(4)})';
    }

    String holdLabel() {
      if (holdMinutes >= 60) {
        final hours = holdMinutes ~/ 60;
        final minutes = holdMinutes % 60;
        return '${hours}h ${minutes}m';
      }
      return '${holdMinutes}m';
    }

    return SoftSurface(
      margin: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _SoftIconCircle(icon: Icons.done_all, color: pnlColor),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${position.symbol} | ${position.pnlSol >= 0 ? '+' : ''}${solWithUsd(position.pnlSol)} '
                      '(${position.pnlPercent.toStringAsFixed(2)}%)',
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: pnlColor,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Apertura $opened | Cierre $closed',
                      style: theme.textTheme.bodySmall,
                    ),
                    Text('Motivo: $reason', style: theme.textTheme.bodySmall),
                  ],
                ),
              ),
              Text(
                'PnL neto ${netPnl >= 0 ? '+' : ''}${solWithUsd(netPnl)}',
                style: theme.textTheme.titleSmall?.copyWith(
                  color: netPnl >= 0 ? Colors.greenAccent : Colors.redAccent,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 12,
            runSpacing: 10,
            children: [
              _InfoBadge(
                icon: Icons.login,
                label: 'Entrada',
                value: solWithUsd(position.entrySol),
              ),
              _InfoBadge(
                icon: Icons.price_change,
                label: 'Precio entrada',
                value: priceWithUsd(position.entryPriceSol),
              ),
              _InfoBadge(
                icon: Icons.logout,
                label: 'Salida',
                value: solWithUsd(position.exitSol),
              ),
              _InfoBadge(
                icon: Icons.attach_money,
                label: 'Precio salida',
                value: priceWithUsd(position.exitPriceSol),
              ),
              _InfoBadge(icon: Icons.timer, label: 'Hold', value: holdLabel()),
              _InfoBadge(
                icon: Icons.receipt_long,
                label: 'Fees',
                value:
                    'Entrada ${solWithUsd(entryFee)} | Salida ${solWithUsd(exitFee)}',
              ),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 6,
            children: [
              _CircleIconButton(
                tooltip: 'Copiar tx venta',
                icon: Icons.copy,
                onPressed: () async {
                  await Clipboard.setData(
                    ClipboardData(text: position.sellSignature),
                  );
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Signature copiada')),
                    );
                  }
                },
              ),
              _CircleIconButton(
                tooltip: 'Venta en Solscan',
                icon: Icons.open_in_new,
                onPressed: () async {
                  final uri = Uri.parse(
                    'https://solscan.io/tx/${position.sellSignature}',
                  );
                  if (await canLaunchUrl(uri)) {
                    await launchUrl(uri, mode: LaunchMode.externalApplication);
                  }
                },
              ),
              _CircleIconButton(
                tooltip: 'Abrir en pump.fun',
                icon: Icons.rocket_launch,
                onPressed: () async {
                  final uri = Uri.parse('https://pump.fun/${position.mint}');
                  if (await canLaunchUrl(uri)) {
                    await launchUrl(uri, mode: LaunchMode.externalApplication);
                  }
                },
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ExecutionTile extends StatelessWidget {
  const _ExecutionTile({required this.record});

  final ExecutionRecord record;

  String _shorten(String value) {
    if (value.length <= 12) {
      return value;
    }
    return '${value.substring(0, 6)}...${value.substring(value.length - 4)}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sigShort = _shorten(record.txSignature);
    final isBuy = record.side == 'buy';
    final accent = isBuy ? Colors.greenAccent : Colors.redAccent;

    return SoftSurface(
      margin: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _SoftIconCircle(
                icon: isBuy ? Icons.trending_up : Icons.trending_down,
                color: accent,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${record.symbol} (${record.solAmount.toStringAsFixed(2)} SOL)',
                      style: theme.textTheme.titleMedium,
                    ),
                    Text(
                      'Tx $sigShort | ${record.formattedTime}',
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              Text(
                record.status,
                style: theme.textTheme.bodyMedium?.copyWith(color: accent),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 6,
            children: [
              _CircleIconButton(
                tooltip: 'Copiar signature',
                icon: Icons.copy,
                onPressed: () async {
                  await Clipboard.setData(
                    ClipboardData(text: record.txSignature),
                  );
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Signature copiada')),
                    );
                  }
                },
              ),
              _CircleIconButton(
                tooltip: 'Abrir en pump.fun',
                icon: Icons.rocket_launch,
                onPressed: () async {
                  final uri = Uri.parse('https://pump.fun/${record.mint}');
                  if (await canLaunchUrl(uri)) {
                    await launchUrl(uri, mode: LaunchMode.externalApplication);
                  }
                },
              ),
              _CircleIconButton(
                tooltip: 'Abrir en Solscan',
                icon: Icons.open_in_new,
                onPressed: () async {
                  final uri = Uri.parse(
                    'https://solscan.io/tx/${record.txSignature}',
                  );
                  if (await canLaunchUrl(uri)) {
                    await launchUrl(uri, mode: LaunchMode.externalApplication);
                  }
                },
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _InfoBadge extends StatelessWidget {
  const _InfoBadge({
    required this.icon,
    required this.label,
    required this.value,
    this.color,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = color ?? theme.colorScheme.primary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: accent.withValues(alpha: 0.08),
        border: Border.all(color: accent.withValues(alpha: 0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: accent),
          const SizedBox(width: 6),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: theme.textTheme.labelSmall),
              Text(
                value,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SoftIconCircle extends StatelessWidget {
  const _SoftIconCircle({required this.icon, required this.color});

  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color.withValues(alpha: 0.18),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.25),
            offset: const Offset(0, 4),
            blurRadius: 18,
          ),
        ],
      ),
      child: Icon(icon, color: color),
    );
  }
}

class _CircleIconButton extends StatelessWidget {
  const _CircleIconButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final baseColor = theme.colorScheme.surfaceContainerHighest.withValues(
      alpha: 0.4,
    );
    final glow = theme.colorScheme.primary;
    final style =
        IconButton.styleFrom(
          backgroundColor: baseColor,
          shape: const CircleBorder(),
        ).copyWith(
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.disabled)) {
              return baseColor.withValues(alpha: 0.2);
            }
            if (states.contains(WidgetState.pressed)) {
              return baseColor.withValues(alpha: 0.65);
            }
            if (states.contains(WidgetState.hovered)) {
              return baseColor.withValues(alpha: 0.5);
            }
            return baseColor;
          }),
          shadowColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.disabled)) {
              return Colors.transparent;
            }
            if (states.contains(WidgetState.pressed)) {
              return glow.withValues(alpha: 0.55);
            }
            if (states.contains(WidgetState.hovered)) {
              return glow.withValues(alpha: 0.4);
            }
            return glow.withValues(alpha: 0.25);
          }),
          elevation: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.disabled)) return 0;
            if (states.contains(WidgetState.pressed)) return 5;
            if (states.contains(WidgetState.hovered)) return 9;
            return 0;
          }),
        );
    return IconButton(
      tooltip: tooltip,
      icon: Icon(icon, size: 18),
      onPressed: onPressed,
      style: style,
    );
  }
}

class _SimulationRunTile extends StatelessWidget {
  const _SimulationRunTile({required this.run});

  final SimulationRun run;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final date = DateFormat('dd/MM HH:mm').format(run.timestamp);
    final pnl = run.totalPnlSol;

    return SoftSurface(
      margin: const EdgeInsets.only(bottom: 12),
      child: ExpansionTile(
        tilePadding: EdgeInsets.zero,
        title: Text('Simulacion $date'),
        subtitle: Text(
          '${run.trades.length} operaciones | PnL ${pnl.toStringAsFixed(2)} SOL | ${run.criteriaDescription}',
          style: theme.textTheme.bodySmall,
        ),
        childrenPadding: const EdgeInsets.only(top: 8, bottom: 12),
        children: run.trades
            .map(
              (trade) => ListTile(
                dense: true,
                title: Text(
                  '${trade.symbol} (${trade.mint.substring(0, 4)}...)',
                ),
                subtitle: Text(
                  'Entrada ${trade.entrySol.toStringAsFixed(2)} SOL | '
                  'Salida ${trade.exitSol.toStringAsFixed(2)} SOL | '
                  'PnL ${trade.pnlSol.toStringAsFixed(2)} SOL',
                ),
                trailing: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(trade.formattedTime),
                    Text(
                      trade.hitTakeProfit
                          ? 'Take profit'
                          : trade.hitStopLoss
                          ? 'Stop loss'
                          : 'Neutral',
                      style: theme.textTheme.labelSmall,
                    ),
                  ],
                ),
              ),
            )
            .toList(),
      ),
    );
  }
}
