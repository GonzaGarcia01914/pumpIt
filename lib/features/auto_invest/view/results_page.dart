import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../controller/auto_invest_executor.dart';
import '../controller/auto_invest_notifier.dart';
import '../models/execution_record.dart';
import '../models/position.dart';
import '../models/simulation_models.dart';

class SimulationResultsPage extends ConsumerWidget {
  const SimulationResultsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(autoInvestProvider);
    final notifier = ref.read(autoInvestProvider.notifier);
    final executor = ref.read(autoInvestExecutorProvider);
    final hasExecutions = state.executions.isNotEmpty;
    final hasSimulations = state.simulations.isNotEmpty;
    final hasPositions = state.positions.isNotEmpty;

    if (!hasExecutions && !hasSimulations && !hasPositions) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Text(
            'Aun no hay simulaciones, ordenes ni posiciones guardadas.\n'
            'Usa la pestana Auto invest para lanzar una simulacion o activar el bot.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (hasPositions) ...[
            Text(
              'Posiciones abiertas',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            for (final position in state.positions.reversed)
              _PositionTile(
                position: position,
                onSell: () => executor.sellPosition(position),
              ),
            const SizedBox(height: 24),
          ],
          if (hasExecutions) ...[
            Text(
              'Ordenes reales',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            for (final record in state.executions.reversed)
              _ExecutionTile(record: record),
            const SizedBox(height: 24),
          ],
          Row(
            children: [
              ElevatedButton.icon(
                onPressed: state.isAnalyzingResults
                    ? null
                    : () => notifier.analyzeSimulations(),
                icon: state.isAnalyzingResults
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.auto_fix_high),
                label: const Text('Analizar resultados con IA'),
              ),
              const SizedBox(width: 12),
              if (state.analysisSummary != null)
                const Icon(Icons.check_circle, color: Colors.greenAccent),
            ],
          ),
          if (state.analysisSummary != null) ...[
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  state.analysisSummary!,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
            ),
          ],
          if (hasSimulations) ...[
            const SizedBox(height: 16),
            for (final run in state.simulations.reversed)
              _SimulationRunTile(run: run),
          ],
        ],
      ),
    );
  }
}

class _PositionTile extends StatelessWidget {
  const _PositionTile({required this.position, this.onSell});

  final OpenPosition position;
  final VoidCallback? onSell;

  String _shorten(String value) {
    if (value.length <= 12) {
      return value;
    }
    return '${value.substring(0, 6)}...${value.substring(value.length - 4)}';
  }

  @override
  Widget build(BuildContext context) {
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
    final priceText = lastPrice == null
        ? 'Precio pendiente'
        : '${lastPrice.toStringAsFixed(6)} SOL';
    final valueText = currentValue == null
        ? null
        : '${currentValue.toStringAsFixed(3)} SOL';
    final pnlText = pnlSol == null
        ? 'PnL pendiente'
        : '${pnlSol >= 0 ? '+' : ''}${pnlSol.toStringAsFixed(3)} SOL'
              '${pnlPercent == null ? '' : ' (${pnlPercent.toStringAsFixed(2)}%)'}';
    final pnlColor = pnlSol == null
        ? Theme.of(context).textTheme.bodySmall?.color
        : pnlSol >= 0
        ? Colors.greenAccent
        : Colors.redAccent;
    final lastCheckedAt = position.lastCheckedAt;
    final checkedLabel = lastCheckedAt == null
        ? 'Sin monitoreo reciente'
        : 'Actualizado ${DateFormat('HH:mm:ss').format(lastCheckedAt)}';

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        leading: const Icon(Icons.account_balance_wallet_outlined),
        title: Text(
          '${position.symbol} - ${position.entrySol.toStringAsFixed(2)} SOL',
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Mint $mintShort - Tx $signatureShort'),
            Text(
              '$tokenLabel - Apertura $opened - ${position.executionMode.name}',
            ),
            Text('Precio $priceText'),
            Text(checkedLabel, style: Theme.of(context).textTheme.labelSmall),
            if (position.alertType != null) ...[
              const SizedBox(height: 6),
              Chip(
                label: Text(position.alertType!.label),
                backgroundColor:
                    (position.alertType == PositionAlertType.takeProfit
                            ? Colors.greenAccent
                            : Colors.redAccent)
                        .withValues(alpha: 0.2),
              ),
            ],
            if (onSell != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: FilledButton.tonalIcon(
                  onPressed: position.isClosing ? null : onSell,
                  icon: position.isClosing
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.sell),
                  label: Text(
                    position.isClosing ? 'Vendiendo...' : 'Vender posición',
                  ),
                ),
              ),
          ],
        ),
        trailing: Wrap(
          spacing: 8,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (valueText != null)
                  Text(
                    'Valor $valueText',
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                Text(
                  pnlText,
                  style: Theme.of(
                    context,
                  ).textTheme.labelMedium?.copyWith(color: pnlColor),
                ),
              ],
            ),
            IconButton(
              tooltip: 'Copiar signature',
              icon: const Icon(Icons.copy, size: 18),
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
            IconButton(
              tooltip: 'Abrir en pump.fun',
              icon: const Icon(Icons.rocket_launch, size: 18),
              onPressed: () async {
                final uri = Uri.parse('https://pump.fun/${position.mint}');
                if (await canLaunchUrl(uri)) {
                  await launchUrl(uri, mode: LaunchMode.externalApplication);
                }
              },
            ),
            IconButton(
              tooltip: 'Abrir en Solscan',
              icon: const Icon(Icons.open_in_new, size: 18),
              onPressed: () async {
                final uri = Uri.parse(
                  'https://solscan.io/tx/${position.entrySignature}',
                );
                if (await canLaunchUrl(uri)) {
                  await launchUrl(uri, mode: LaunchMode.externalApplication);
                }
              },
            ),
          ],
        ),
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
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        leading: Icon(
          record.side == 'buy' ? Icons.trending_up : Icons.trending_down,
          color: record.side == 'buy' ? Colors.greenAccent : Colors.redAccent,
        ),
        title: Text(
          '${record.symbol} (${record.solAmount.toStringAsFixed(2)} SOL)',
        ),
        subtitle: Text(
          'Tx $sigShort - ${record.formattedTime}',
          style: theme.textTheme.bodySmall,
        ),
        trailing: Wrap(
          spacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            IconButton(
              tooltip: 'Copiar signature',
              icon: const Icon(Icons.copy, size: 18),
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
            IconButton(
              tooltip: 'Abrir en pump.fun',
              icon: const Icon(Icons.rocket_launch, size: 18),
              onPressed: () async {
                final uri = Uri.parse('https://pump.fun/${record.mint}');
                if (await canLaunchUrl(uri)) {
                  await launchUrl(uri, mode: LaunchMode.externalApplication);
                }
              },
            ),
            IconButton(
              tooltip: 'Abrir en Solscan',
              icon: const Icon(Icons.open_in_new, size: 18),
              onPressed: () async {
                final uri = Uri.parse(
                  'https://solscan.io/tx/${record.txSignature}',
                );
                if (await canLaunchUrl(uri)) {
                  await launchUrl(uri, mode: LaunchMode.externalApplication);
                }
              },
            ),
            Text(record.status),
          ],
        ),
      ),
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

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ExpansionTile(
        title: Text('Simulacion $date'),
        subtitle: Text(
          '${run.trades.length} operaciones - PnL ${pnl.toStringAsFixed(2)} SOL - ${run.criteriaDescription}',
          style: theme.textTheme.bodySmall,
        ),
        children: run.trades
            .map(
              (trade) => ListTile(
                dense: true,
                title: Text(
                  '${trade.symbol} (${trade.mint.substring(0, 4)}...)',
                ),
                subtitle: Text(
                  'Entrada ${trade.entrySol.toStringAsFixed(2)} SOL - '
                  'Salida ${trade.exitSol.toStringAsFixed(2)} SOL - '
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
