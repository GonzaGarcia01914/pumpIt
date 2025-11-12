import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../featured_coins/controller/featured_coin_notifier.dart';
import '../../featured_coins/models/featured_coin.dart';
import '../controller/auto_invest_notifier.dart';

class AutoInvestPage extends ConsumerWidget {
  const AutoInvestPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(autoInvestProvider);
    final notifier = ref.read(autoInvestProvider.notifier);
    final featured = ref.watch(featuredCoinProvider);
    final theme = Theme.of(context);

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Auto Invest',
              style: theme.textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Text(
              'Configura los criterios del bot y vincula tu wallet '
              '(Phantom en web o keypair local en desktop).\n'
              'Cuando Auto Invest esté activo, las reglas se usarán para futuras compras/ventas automatizadas.',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            _WalletCard(state: state, notifier: notifier),
            const SizedBox(height: 16),
            _BudgetCard(state: state, notifier: notifier),
            const SizedBox(height: 16),
            _FilterCard(state: state, notifier: notifier),
            const SizedBox(height: 16),
            _SafetyCard(state: state, notifier: notifier),
            const SizedBox(height: 16),
            _ExecutionModeCard(state: state, notifier: notifier),
            const SizedBox(height: 16),
            SwitchListTile.adaptive(
              value: state.isEnabled,
              onChanged: state.walletAddress == null
                  ? null
                  : (value) => notifier.toggleEnabled(value),
              title: const Text('Auto Invest activado'),
              subtitle: Text(
                state.walletAddress == null
                    ? 'Conecta tu wallet para habilitar el bot.'
                    : 'El bot evaluará los criterios en cada refresco.',
              ),
            ),
            const SizedBox(height: 8),
            _SimulationControls(
              notifier: notifier,
              state: state,
              availableCoins: featured.coins,
            ),
            if (state.statusMessage != null) ...[
              const SizedBox(height: 12),
              Text(
                state.statusMessage!,
                style: theme.textTheme.bodySmall,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _WalletCard extends StatelessWidget {
  const _WalletCard({
    required this.state,
    required this.notifier,
  });

  final AutoInvestState state;
  final AutoInvestNotifier notifier;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final connected = state.walletAddress != null;
    final instructions = kIsWeb
        ? 'Conecta Phantom (Chrome/Edge) y autoriza a la app.'
        : 'Define --dart-define=LOCAL_KEY_PATH=/ruta/auto_bot.json y presiona Conectar.';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Wallet', style: theme.textTheme.titleMedium),
            const SizedBox(height: 12),
            if (connected)
              Row(
                children: [
                  Chip(
                    avatar: const Icon(Icons.wallet),
                    label: Text(
                      state.walletAddress!.length > 12
                          ? '${state.walletAddress!.substring(0, 6)}...${state.walletAddress!.substring(state.walletAddress!.length - 6)}'
                          : state.walletAddress!,
                    ),
                  ),
                  const SizedBox(width: 12),
                  TextButton(
                    onPressed: notifier.disconnectWallet,
                    child: const Text('Desconectar'),
                  ),
                ],
              )
            else
              Text(
                instructions,
                style: theme.textTheme.bodySmall,
              ),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: state.isConnecting
                  ? null
                  : connected
                      ? notifier.disconnectWallet
                      : notifier.connectWallet,
              icon: Icon(connected ? Icons.link_off : Icons.link),
              label: Text(connected ? 'Disconnect' : 'Connect wallet'),
            ),
          ],
        ),
      ),
    );
  }
}

class _BudgetCard extends StatelessWidget {
  const _BudgetCard({required this.state, required this.notifier});

  final AutoInvestState state;
  final AutoInvestNotifier notifier;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Presupuestos (SOL)',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _NumberField(
                    label: 'Presupuesto total',
                    value: state.totalBudgetSol,
                    suffix: 'SOL',
                    onChanged: notifier.updateTotalBudget,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _NumberField(
                    label: 'Max por memecoin',
                    value: state.perCoinBudgetSol,
                    suffix: 'SOL',
                    onChanged: notifier.updatePerCoinBudget,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'El bot nunca invertirá más que estos límites. Ajusta según tu apetito de riesgo.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

class _FilterCard extends StatelessWidget {
  const _FilterCard({required this.state, required this.notifier});

  final AutoInvestState state;
  final AutoInvestNotifier notifier;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Criterios de mercado', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _NumberField(
                    label: 'MC mínima USD',
                    value: state.minMarketCap,
                    onChanged: notifier.updateMinMarketCap,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _NumberField(
                    label: 'MC máxima USD',
                    value: state.maxMarketCap,
                    onChanged: notifier.updateMaxMarketCap,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _NumberField(
                    label: 'Volumen 24h mínimo',
                    value: state.minVolume24h,
                    onChanged: notifier.updateMinVolume,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _NumberField(
                    label: 'Volumen 24h máximo',
                    value: state.maxVolume24h,
                    onChanged: notifier.updateMaxVolume,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SafetyCard extends StatelessWidget {
  const _SafetyCard({required this.state, required this.notifier});

  final AutoInvestState state;
  final AutoInvestNotifier notifier;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Riesgo y salida', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Stop loss (${state.stopLossPercent.toStringAsFixed(0)}%)'),
                      Slider(
                        min: 5,
                        max: 90,
                        divisions: 17,
                        value: state.stopLossPercent.clamp(5, 90),
                        onChanged: notifier.updateStopLoss,
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Take profit (${state.takeProfitPercent.toStringAsFixed(0)}%)'),
                      Slider(
                        min: 10,
                        max: 200,
                        divisions: 19,
                        value: state.takeProfitPercent.clamp(10, 200),
                        onChanged: notifier.updateTakeProfit,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            SwitchListTile.adaptive(
              value: state.withdrawOnGain,
              onChanged: notifier.updateWithdrawOnGain,
              title: const Text('Retirar tras ganancia'),
              subtitle: const Text(
                  'Si está activo, el bot moverá las utilidades al presupuesto general antes de reinvertir.'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ExecutionModeCard extends StatelessWidget {
  const _ExecutionModeCard({
    required this.state,
    required this.notifier,
  });

  final AutoInvestState state;
  final AutoInvestNotifier notifier;

  static const _poolOptions = [
    'pump',
    'pump-amm',
    'launchlab',
    'raydium',
    'raydium-cpmm',
    'bonk',
    'auto',
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final usingPumpPortal = state.executionMode == AutoInvestExecutionMode.pumpPortal;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Motor de ejecución', style: theme.textTheme.titleMedium),
            const SizedBox(height: 12),
            DropdownButtonFormField<AutoInvestExecutionMode>(
              initialValue: state.executionMode,
              decoration: const InputDecoration(
                labelText: 'Selecciona el riel de órdenes',
              ),
              items: AutoInvestExecutionMode.values
                  .map(
                    (mode) => DropdownMenuItem(
                      value: mode,
                      child: Text(
                        mode == AutoInvestExecutionMode.jupiter
                            ? 'Jupiter (tokens graduados)'
                            : 'PumpPortal (bonding curve)',
                      ),
                    ),
                  )
                  .toList(),
              onChanged: (mode) {
                if (mode != null) notifier.setExecutionMode(mode);
              },
            ),
            const SizedBox(height: 8),
            Text(
              state.executionMode == AutoInvestExecutionMode.jupiter
                  ? 'Usa quotes de Jupiter, ideal para tokens que ya migraron su liquidez.'
                  : 'Construye transacciones sobre la bonding curve de pump.fun vía PumpPortal.',
              style: theme.textTheme.bodySmall,
            ),
            if (usingPumpPortal) ...[
              const SizedBox(height: 16),
              _NumberField(
                label: 'Slippage permitido',
                value: state.pumpSlippagePercent,
                suffix: '%',
                onChanged: notifier.updatePumpSlippage,
              ),
              const SizedBox(height: 12),
              _NumberField(
                label: 'Priority fee (SOL)',
                value: state.pumpPriorityFeeSol,
                suffix: 'SOL',
                onChanged: notifier.updatePumpPriorityFee,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: state.pumpPool,
                decoration: const InputDecoration(labelText: 'Pool preferido'),
                items: _poolOptions
                    .map(
                      (pool) => DropdownMenuItem(
                        value: pool,
                        child: Text(pool),
                      ),
                    )
                    .toList(),
                onChanged: (value) {
                  if (value != null) notifier.updatePumpPool(value);
                },
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SimulationControls extends StatelessWidget {
  const _SimulationControls({
    required this.notifier,
    required this.state,
    required this.availableCoins,
  });

  final AutoInvestNotifier notifier;
  final AutoInvestState state;
  final List<FeaturedCoin> availableCoins;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Simular auto invest', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              'Ejecuta compras virtuales usando los criterios actuales. '
              'Los resultados aparecerán en la pestaña Resultados.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              children: [
                FilledButton.icon(
                  onPressed: state.isSimulationRunning
                      ? null
                      : () => notifier.simulate(availableCoins),
                  icon: state.isSimulationRunning
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.play_arrow),
                  label: const Text('Simular auto invest'),
                ),
                Text(
                  'Operaciones simuladas: ${state.simulations.length}',
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _NumberField extends StatefulWidget {
  const _NumberField({
    required this.label,
    required this.value,
    required this.onChanged,
    this.suffix,
  });

  final String label;
  final double value;
  final void Function(double value) onChanged;
  final String? suffix;

  @override
  State<_NumberField> createState() => _NumberFieldState();
}

class _NumberFieldState extends State<_NumberField> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: _format(widget.value));
  }

  @override
  void didUpdateWidget(covariant _NumberField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value != oldWidget.value) {
      final text = _format(widget.value);
      if (_controller.text != text) {
        _controller.value = TextEditingValue(
          text: text,
          selection: TextSelection.collapsed(offset: text.length),
        );
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: _controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [
        FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
      ],
      decoration: InputDecoration(
        labelText: widget.label,
        suffixText: widget.suffix,
      ),
      onChanged: (text) {
        final normalized = text.replaceAll(',', '.');
        final parsed = double.tryParse(normalized);
        if (parsed != null) {
          widget.onChanged(parsed);
        }
      },
    );
  }

  String _format(double value) {
    final isInt = value % 1 == 0;
    return isInt ? value.toStringAsFixed(0) : value.toString();
  }
}
