import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../controller/auto_invest_notifier.dart';
import '../models/execution_record.dart';
import '../models/simulation_models.dart';

class SimulationResultsPage extends ConsumerWidget {
  const SimulationResultsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(autoInvestProvider);
    final notifier = ref.read(autoInvestProvider.notifier);
    final hasExecutions = state.executions.isNotEmpty;
    final hasSimulations = state.simulations.isNotEmpty;

    if (!hasExecutions && !hasSimulations) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Text(
            'Aún no hay simulaciones ni órdenes reales.\n'
            'Usa la pestaña Auto invest para lanzar una simulación o activar el bot.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (hasExecutions) ...[
            Text(
              'Órdenes reales',
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

class _ExecutionTile extends StatelessWidget {
  const _ExecutionTile({required this.record});

  final ExecutionRecord record;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sig = record.txSignature;
    final sigShort =
        sig.length <= 12 ? sig : '${sig.substring(0, 6)}...${sig.substring(sig.length - 6)}';
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        leading: Icon(
          record.side == 'buy' ? Icons.trending_up : Icons.trending_down,
          color: record.side == 'buy' ? Colors.greenAccent : Colors.redAccent,
        ),
        title: Text('${record.symbol} (${record.solAmount.toStringAsFixed(2)} SOL)'),
        subtitle: Text(
          'Tx $sigShort · ${record.formattedTime}',
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
                await Clipboard.setData(ClipboardData(text: sig));
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Signature copiada')),
                  );
                }
              },
            ),
            IconButton(
              tooltip: 'Abrir en Solscan',
              icon: const Icon(Icons.open_in_new, size: 18),
              onPressed: () async {
                final uri = Uri.parse('https://solscan.io/tx/$sig');
                if (await canLaunchUrl(uri)) {
                  await launchUrl(uri, mode: LaunchMode.externalApplication);
                }
              },
            ),
            Text(record.status),
          ],
        )
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
        title: Text('Simulación $date'),
        subtitle: Text(
          '${run.trades.length} operaciones · PnL ${pnl.toStringAsFixed(2)} SOL · ${run.criteriaDescription}',
          style: theme.textTheme.bodySmall,
        ),
        children: run.trades
            .map(
              (trade) => ListTile(
                dense: true,
                title: Text('${trade.symbol} (${trade.mint.substring(0, 4)}...)'),
                subtitle: Text(
                  'Entrada ${trade.entrySol.toStringAsFixed(2)} SOL · '
                  'Salida ${trade.exitSol.toStringAsFixed(2)} SOL · '
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
