import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../featured_coins/controller/featured_coin_notifier.dart';
import '../../featured_coins/models/featured_coin.dart';
import '../controller/auto_invest_notifier.dart';
import '../models/execution_mode.dart';
import '../../../core/widgets/soft_surface.dart';
import 'widgets/analysis_drawer_panel.dart';

class AutoInvestPage extends ConsumerWidget {
  const AutoInvestPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(autoInvestProvider);
    final notifier = ref.read(autoInvestProvider.notifier);
    final featured = ref.watch(featuredCoinProvider);

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 120),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _PageHeader(state: state),
            const SizedBox(height: 20),
            _WalletPanel(state: state, notifier: notifier),
            const SizedBox(height: 16),
            _ActionShortcuts(
              state: state,
              notifier: notifier,
              availableCoins: featured.coins,
            ),
            const SizedBox(height: 16),
            _BudgetSection(state: state, notifier: notifier),
            const SizedBox(height: 16),
            _FilterSection(state: state, notifier: notifier),
            const SizedBox(height: 16),
            _RiskSection(state: state, notifier: notifier),
            const SizedBox(height: 16),
            _ExecutionModeSection(state: state, notifier: notifier),
            const SizedBox(height: 16),
            _BotToggleCard(state: state, notifier: notifier),
            const SizedBox(height: 16),
            _SimulationControls(
              notifier: notifier,
              state: state,
              availableCoins: featured.coins,
            ),
            const SizedBox(height: 16),
            AnalysisDrawerPanel(
              summary: state.analysisSummary,
              isLoading: state.isAnalyzingResults,
              onAnalyze: notifier.analyzeSimulations,
              collapsed: true,
            ),
            if (state.statusMessage != null) ...[
              const SizedBox(height: 12),
              Text(state.statusMessage!, style: Theme.of(context).textTheme.bodySmall),
            ],
          ],
        ),
      ),
    );
  }
}

class _BudgetSection extends StatelessWidget {
  const _BudgetSection({required this.state, required this.notifier});
  final AutoInvestState state;
  final AutoInvestNotifier notifier;
  @override
  Widget build(BuildContext context) {
    final deployed = state.deployedBudgetSol;
    final total = state.totalBudgetSol;
    final available = state.availableBudgetSol;
    final progress = total <= 0 ? 0.0 : (deployed / total).clamp(0, 1).toDouble();
    return SoftSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionHeader(
            icon: Icons.savings_outlined,
            title: 'Presupuestos (SOL)',
            subtitle: 'Define lÃ­mites globales y por token',
          ),
          const SizedBox(height: 18),
          _BudgetProgressBar(
            progress: progress,
            availableLabel: '${available.toStringAsFixed(2)} SOL libres',
            deployedLabel: '${deployed.toStringAsFixed(2)} SOL usados',
          ),
          const SizedBox(height: 18),
          SwitchListTile.adaptive(
            value: state.syncBudgetToWallet,
            onChanged: state.walletBalanceSol > 0 ? notifier.toggleAutoBudgetSync : null,
            title: const Text('Ajustar al saldo de la wallet'),
            subtitle: Text(
              state.walletBalanceSol > 0
                  ? 'Mantén el presupuesto como un porcentaje del balance.'
                  : 'Conecta y sincroniza tu wallet para habilitarlo.',
            ),
          ),
          const SizedBox(height: 8),
          Text('Presupuesto total (% de la wallet)', style: Theme.of(context).textTheme.labelMedium),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final p in [0.1,0.2,0.3,0.4,0.5,0.6,0.7,0.8,0.9,1.0])
                _PercentChip(
                  label: '${(p*100).toInt()}%',
                  selected: (state.walletBudgetPercent - p).abs() < 0.001,
                  onPressed: state.walletBalanceSol <= 0
                      ? null
                      : () {
                          if (state.syncBudgetToWallet) {
                            notifier.setAutoBudgetPercent(p);
                          } else {
                            notifier.applyTotalBudgetPercent(p);
                          }
                        },
                ),
            ],
          ),
          const SizedBox(height: 10),
          _RRow(
            children: [
              _NumberField(
                label: 'Presupuesto total',
                value: state.totalBudgetSol,
                suffix: 'SOL',
                onChanged: notifier.updateTotalBudget,
              ),
              _NumberField(
                label: 'MÃ¡ximo por memecoin',
                value: state.perCoinBudgetSol,
                suffix: 'SOL',
                onChanged: notifier.updatePerCoinBudget,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'Disponible: ${state.availableBudgetSol.toStringAsFixed(2)} SOL Â· En uso ${deployed.toStringAsFixed(2)} SOL',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 4),
          Text(
            'PnL realizado: ${state.realizedProfitSol.toStringAsFixed(3)} SOL Â· Retirado ${state.withdrawnProfitSol.toStringAsFixed(3)} SOL',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          Text(
            'El bot nunca invertirÃ¡ mÃ¡s que estos lÃ­mites. Ajusta segÃºn tu apetito de riesgo.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final percent in [1.0, 0.5, 0.2])
                _GradientChip(
                  label: '${(percent * 100).toInt()}% por memecoin',
                  onTap: state.totalBudgetSol <= 0
                      ? null
                      : () => notifier.updatePerCoinBudget(
                            (state.totalBudgetSol * percent).toDouble(),
                          ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.icon, required this.title, this.subtitle});
  final IconData icon;
  final String title;
  final String? subtitle;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = theme.colorScheme.primary;
    return Row(
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              colors: [accent.withValues(alpha: 0.3), accent.withValues(alpha: 0.1)],
            ),
          ),
          child: Icon(icon, color: accent),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: theme.textTheme.titleMedium),
              if (subtitle != null) Text(subtitle!, style: theme.textTheme.bodySmall),
            ],
          ),
        ),
      ],
    );
  }
}

class _FilterSection extends StatelessWidget {
  const _FilterSection({required this.state, required this.notifier});
  final AutoInvestState state;
  final AutoInvestNotifier notifier;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SoftSurface(
      color: theme.colorScheme.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionHeader(
            icon: Icons.tune_rounded,
            title: 'Criterios de mercado',
            subtitle: 'Rangos de market cap y volumen',
          ),
          const SizedBox(height: 18),
          _RRow(
            children: [
              _NumberField(
                label: 'MC mÃ­nima USD',
                value: state.minMarketCap,
                onChanged: notifier.updateMinMarketCap,
              ),
              _NumberField(
                label: 'MC mÃ¡xima USD',
                value: state.maxMarketCap,
                onChanged: notifier.updateMaxMarketCap,
              ),
            ],
          ),
          const SizedBox(height: 16),
          _RRow(
            children: [
              _NumberField(
                label: 'Volumen 24h mÃ­nimo',
                value: state.minVolume24h,
                onChanged: notifier.updateMinVolume,
              ),
              _NumberField(
                label: 'Volumen 24h mÃ¡ximo',
                value: state.maxVolume24h,
                onChanged: notifier.updateMaxVolume,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RiskSection extends StatelessWidget {
  const _RiskSection({required this.state, required this.notifier});
  final AutoInvestState state;
  final AutoInvestNotifier notifier;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SoftSurface(
      color: theme.colorScheme.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionHeader(
            icon: Icons.shield_outlined,
            title: 'Riesgo y salida',
            subtitle: 'Sliders de stop loss y take profit',
          ),
          const SizedBox(height: 16),
          _SliderTile(
            label: 'Stop loss',
            value: state.stopLossPercent.clamp(5, 90),
            min: 5,
            max: 90,
            suffix: '%',
            onChanged: notifier.updateStopLoss,
          ),
          const SizedBox(height: 16),
          _SliderTile(
            label: 'Take profit',
            value: state.takeProfitPercent.clamp(10, 200),
            min: 10,
            max: 200,
            suffix: '%',
            onChanged: notifier.updateTakeProfit,
          ),
          const SizedBox(height: 12),
          SwitchListTile.adaptive(
            value: state.withdrawOnGain,
            onChanged: notifier.updateWithdrawOnGain,
            title: const Text('Retirar tras ganancia'),
            subtitle: const Text('Si estÃ¡ activo, el bot moverÃ¡ las utilidades al presupuesto general antes de reinvertir.'),
          ),
        ],
      ),
    );
  }
}

class _ExecutionModeSection extends StatelessWidget {
  const _ExecutionModeSection({required this.state, required this.notifier});
  final AutoInvestState state;
  final AutoInvestNotifier notifier;
  static const _poolOptions = ['pump','pump-amm','launchlab','raydium','raydium-cpmm','bonk','auto'];
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final usingPumpPortal = state.executionMode == AutoInvestExecutionMode.pumpPortal;
    return SoftSurface(
      color: theme.colorScheme.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionHeader(
            icon: Icons.memory,
            title: 'Motor de ejecuciÃ³n',
            subtitle: 'Selecciona entre Jupiter o PumpPortal',
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: AutoInvestExecutionMode.values
                .map((mode) => _ModeChip(
                      label: mode == AutoInvestExecutionMode.jupiter ? 'Jupiter' : 'PumpPortal',
                      description: mode == AutoInvestExecutionMode.jupiter ? 'Tokens graduados' : 'Bonding curve',
                      selected: state.executionMode == mode,
                      onTap: () => notifier.setExecutionMode(mode),
                    ))
                .toList(),
          ),
          const SizedBox(height: 12),
          Text(
            state.executionMode == AutoInvestExecutionMode.jupiter
                ? 'Usa quotes de Jupiter, ideal para tokens que ya migraron liquidez.'
                : 'Construye Ã³rdenes sobre la bonding curve vÃ­a PumpPortal.',
            style: theme.textTheme.bodySmall,
          ),
          if (usingPumpPortal) ...[
            const SizedBox(height: 16),
            _RRow(
              children: [
                _NumberField(
                  label: 'Slippage permitido %',
                  value: state.pumpSlippagePercent,
                  suffix: '%',
                  onChanged: notifier.updatePumpSlippage,
                ),
                _NumberField(
                  label: 'Priority fee (SOL)',
                  value: state.pumpPriorityFeeSol,
                  suffix: 'SOL',
                  onChanged: notifier.updatePumpPriorityFee,
                ),
              ],
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: state.pumpPool,
              decoration: const InputDecoration(labelText: 'Pool preferido'),
              items: _poolOptions.map((p) => DropdownMenuItem(value: p, child: Text(p))).toList(),
              onChanged: (value) { if (value != null) notifier.updatePumpPool(value); },
            ),
          ],
        ],
      ),
    );
  }
}

class _BotToggleCard extends StatelessWidget {
  const _BotToggleCard({required this.state, required this.notifier});
  final AutoInvestState state;
  final AutoInvestNotifier notifier;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final enabled = state.isEnabled;
    return SoftSurface(
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(enabled ? 'Auto invest activo' : 'Auto invest pausado',
                    style: theme.textTheme.titleMedium),
                const SizedBox(height: 6),
                Text(
                  state.walletAddress == null
                      ? 'Conecta una wallet para habilitar el bot.'
                      : 'El bot evaluarÃ¡ los criterios en cada refresco.',
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
          Switch.adaptive(
            value: enabled,
            onChanged: state.walletAddress == null ? null : (value) => notifier.toggleEnabled(value),
          ),
        ],
      ),
    );
  }
}

class _NumberField extends StatefulWidget {
  const _NumberField({required this.label, required this.value, required this.onChanged, this.suffix});
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
  void initState() { super.initState(); _controller = TextEditingController(text: _format(widget.value)); }
  @override
  void didUpdateWidget(covariant _NumberField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value != oldWidget.value) {
      final text = _format(widget.value);
      if (_controller.text != text) {
        _controller.value = TextEditingValue(text: text, selection: TextSelection.collapsed(offset: text.length));
      }
    }
  }
  @override
  void dispose() { _controller.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: _controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(labelText: widget.label, suffixText: widget.suffix),
      onChanged: (text) {
        final normalized = text.replaceAll(',', '.');
        final parsed = double.tryParse(normalized);
        if (parsed != null) widget.onChanged(parsed);
      },
    );
  }
  String _format(double value) { final isInt = value % 1 == 0; return isInt ? value.toStringAsFixed(0) : value.toString(); }
}

class _SliderTile extends StatelessWidget {
  const _SliderTile({required this.label, required this.value, required this.min, required this.max, required this.onChanged, this.suffix});
  final String label; final double value; final double min; final double max; final ValueChanged<double> onChanged; final String? suffix;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('$label ${suffix != null ? '(${value.toStringAsFixed(0)}$suffix)' : value.toStringAsFixed(0)}', style: theme.textTheme.bodyMedium),
            const Spacer(),
            Text('${value.toStringAsFixed(0)}${suffix ?? ''}', style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
          ],
        ),
        Slider(min: min, max: max, divisions: (max - min).toInt(), value: value, onChanged: onChanged),
      ],
    );
  }
}

class _ModeChip extends StatelessWidget {
  const _ModeChip({required this.label, required this.description, required this.selected, required this.onTap});
  final String label; final String description; final bool selected; final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final background = selected ? theme.colorScheme.primary.withValues(alpha: 0.25) : Colors.white.withValues(alpha: 0.05);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(26),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(26), color: background,
            border: Border.all(color: selected ? theme.colorScheme.primary.withValues(alpha: 0.5) : Colors.white.withValues(alpha: 0.1)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(selected ? Icons.check_circle : Icons.circle_outlined, size: 18,
                  color: selected ? theme.colorScheme.primary : Colors.white70),
              const SizedBox(width: 10),
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(label, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
                Text(description, style: theme.textTheme.labelSmall?.copyWith(color: Colors.white70)),
              ]),
            ],
          ),
        ),
      ),
    );
  }
}

class _SimulationControls extends StatelessWidget {
  const _SimulationControls({required this.notifier, required this.state, required this.availableCoins});
  final AutoInvestNotifier notifier; final AutoInvestState state; final List<FeaturedCoin> availableCoins;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SoftSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(width: 44, height: 44, decoration: BoxDecoration(shape: BoxShape.circle, color: theme.colorScheme.primary.withValues(alpha: 0.15)), child: const Icon(Icons.play_circle_outline)),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Simular auto invest', style: theme.textTheme.titleMedium),
                Text('Prueba la configuraciÃ³n actual sin riesgo. Los resultados viven en la pestaÃ±a Resultados.', style: theme.textTheme.bodySmall),
              ])),
            ],
          ),
          const SizedBox(height: 16),
          Wrap(spacing: 12, runSpacing: 12, crossAxisAlignment: WrapCrossAlignment.center, children: [
            FilledButton.icon(
              onPressed: state.isSimulationRunning ? null : () => notifier.simulate(availableCoins),
              icon: state.isSimulationRunning
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.play_arrow),
              label: Text(state.isSimulationRunning ? 'Simulando...' : 'Simular auto invest'),
            ),
            Text('Operaciones simuladas: ${state.simulations.length}', style: theme.textTheme.bodySmall),
          ]),
        ],
      ),
    );
  }
}

class _BudgetProgressBar extends StatelessWidget {
  const _BudgetProgressBar({required this.progress, required this.availableLabel, required this.deployedLabel});
  final double progress;
  final String availableLabel;
  final String deployedLabel;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text(availableLabel, style: theme.textTheme.bodySmall),
            const Spacer(),
            Text(deployedLabel, style: theme.textTheme.bodySmall),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: LinearProgressIndicator(
            value: progress.isNaN ? 0 : progress,
            minHeight: 10,
            backgroundColor: Colors.white.withValues(alpha: 0.08),
            valueColor: AlwaysStoppedAnimation(theme.colorScheme.primary),
          ),
        ),
      ],
    );
  }
}

class _RRow extends StatelessWidget {
  const _RRow({required this.children});
  final List<Widget> children;
  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 620) {
          return Column(
            children: [
              for (int i = 0; i < children.length; i++) ...[
                if (i != 0) const SizedBox(height: 12),
                children[i],
              ],
            ],
          );
        }
        return Row(
          children: [
            for (int i = 0; i < children.length; i++) ...[
              if (i != 0) const SizedBox(width: 12),
              Expanded(child: children[i]),
            ],
          ],
        );
      },
    );
  }
}

class _GradientChip extends StatelessWidget {
  const _GradientChip({required this.label, this.onTap});
  final String label;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final enabled = onTap != null;
    final gradient = const [Color(0xFF6E7BFF), Color(0xFF9A64FF)];
    final chip = Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(30),
        gradient: enabled ? LinearGradient(colors: gradient, begin: Alignment.topLeft, end: Alignment.bottomRight) : null,
        color: enabled ? null : Colors.white.withValues(alpha: 0.06),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: Text(label,
          style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600, color: Colors.white)),
    );
    if (!enabled) return Opacity(opacity: 0.4, child: chip);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(30),
        onTap: onTap,
        child: chip,
      ),
    );
  }
}

class _PercentChip extends StatelessWidget {
  const _PercentChip({required this.label, this.selected = false, this.onPressed});
  final String label;
  final bool selected;
  final VoidCallback? onPressed;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final background = selected
        ? theme.colorScheme.primary.withValues(alpha: 0.2)
        : Colors.white12;
    final textColor = selected ? Colors.white : Colors.white70;
    final chip = Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        color: background,
      ),
      child: Text(
        label,
        style: theme.textTheme.bodyMedium?.copyWith(
          fontWeight: FontWeight.w600,
          color: textColor,
        ),
      ),
    );
    if (onPressed == null) return Opacity(opacity: 0.4, child: chip);
    return InkWell(
      borderRadius: BorderRadius.circular(24),
      onTap: onPressed,
      child: chip,
    );
  }
}

class _WalletPanel extends StatelessWidget {
  const _WalletPanel({required this.state, required this.notifier});
  final AutoInvestState state;
  final AutoInvestNotifier notifier;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final connected = state.walletAddress != null;
    final instructions = kIsWeb
        ? 'Conecta Phantom (Chrome/Edge) y autoriza a la app.'
        : 'Define --dart-define=LOCAL_KEY_PATH=/ruta/auto_bot.json y presiona Conectar.';
    final shortAddress = connected && state.walletAddress != null
        ? (state.walletAddress!.length > 12
            ? '${state.walletAddress!.substring(0, 6)}...${state.walletAddress!.substring(state.walletAddress!.length - 6)}'
            : state.walletAddress!)
        : null;
    return SoftSurface(
      color: theme.colorScheme.surface,
      borderRadius: 36,
      padding: const EdgeInsets.all(28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Wallet control room', style: theme.textTheme.headlineSmall),
                    const SizedBox(height: 4),
                    Text(
                      connected
                          ? 'Phantom/keypair vinculado y listo para asignar presupuesto.'
                          : 'Conecta Phantom o define LOCAL_KEY_PATH para keypair local.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: Colors.white.withValues(alpha: 0.75),
                      ),
                    ),
                  ],
                ),
              ),
              _StatusPill(active: connected),
            ],
          ),
          const SizedBox(height: 24),
          _VirtualWalletCard(
            connected: connected,
            shortAddress: shortAddress,
            solBalance: state.walletBalanceSol,
            usdBalance: (state.solPriceUsd > 0 ? state.walletBalanceSol * state.solPriceUsd : null),
            lastUpdated: state.walletBalanceUpdatedAt,
          ),
          const SizedBox(height: 20),
          Wrap(
            spacing: 16,
            runSpacing: 12,
            children: [
              _WalletStatPill(
                label: 'Disponible',
                value: '${state.availableBudgetSol.toStringAsFixed(2)} SOL',
                helper: 'Listo para invertir',
              ),
              _WalletStatPill(
                label: 'En uso',
                value: '${state.deployedBudgetSol.toStringAsFixed(2)} SOL',
                helper: 'Asignado a posiciones',
              ),
              _WalletStatPill(
                label: 'PnL realizado',
                value: '${state.realizedProfitSol.toStringAsFixed(2)} SOL',
                helper: 'Incluye retiros',
              ),
              _WalletStatPill(
                label: 'Retiros',
                value: '${state.withdrawnProfitSol.toStringAsFixed(2)} SOL',
                helper: 'Utilidades retiradas',
              ),
            ],
          ),
          const SizedBox(height: 20),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              FilledButton.icon(
                onPressed: state.isConnecting
                    ? null
                    : connected
                        ? notifier.disconnectWallet
                        : notifier.connectWallet,
                icon: Icon(connected ? Icons.logout_rounded : Icons.link_rounded),
                label: Text(connected ? 'Desconectar' : 'Conectar wallet'),
              ),
              OutlinedButton.icon(
                onPressed: state.walletAddress != null ? notifier.refreshWalletBalance : null,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Sincronizar saldo'),
              ),
              if (connected)
                IconButton(
                  tooltip: 'Copiar address',
                  onPressed: () {
                    final address = state.walletAddress;
                    if (address == null) return;
                    Clipboard.setData(ClipboardData(text: address));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Address copiada')),
                    );
                  },
                  icon: const Icon(Icons.copy_rounded),
                ),
              Text(
                connected ? 'Conectada' : instructions,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: Colors.white.withValues(alpha: 0.7),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ActionShortcuts extends StatelessWidget {
  const _ActionShortcuts({
    required this.state,
    required this.notifier,
    required this.availableCoins,
  });
  final AutoInvestState state;
  final AutoInvestNotifier notifier;
  final List<FeaturedCoin> availableCoins;
  @override
  Widget build(BuildContext context) {
    final actions = [
      _ShortcutData(
        title: 'Sincronizar wallet',
        subtitle: 'Refresca saldo y firmas',
        colors: const [Color(0xFF5A6BFF), Color(0xFF7F7FFF)],
        icon: Icons.sync,
        onTap: state.walletAddress == null ? null : notifier.refreshWalletBalance,

      ),
      _ShortcutData(
        title: 'Simular setup',
        subtitle: 'Backtest inmediato',
        colors: const [Color(0xFF7A5CFF), Color(0xFFB55DFF)],
        icon: Icons.auto_graph,
        onTap: state.isSimulationRunning ? null : () => notifier.simulate(availableCoins),
      ),
      _ShortcutData(
        title: 'Analizar PnL',
        subtitle: 'Insights IA/heurÃ­stico',
        colors: const [Color(0xFF4FD1FF), Color(0xFF7B89FF)],
        icon: Icons.bolt,
        onTap: state.isAnalyzingResults ? null : notifier.analyzeSimulations,
      ),
      _ShortcutData(
        title: state.isEnabled ? 'Pausar bot' : 'Activar bot',
        subtitle: state.walletAddress == null
            ? 'Conecta una wallet'
            : state.isEnabled
                ? 'Detiene nuevas Ã³rdenes'
                : 'Usa las reglas actuales',
        colors: const [Color(0xFF4CFFCE), Color(0xFF7B6CFF)],
        icon: state.isEnabled ? Icons.pause : Icons.play_arrow,
        onTap: state.walletAddress == null ? null : () => notifier.toggleEnabled(!state.isEnabled),
      ),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final cardWidth = width > 900 ? (width - 48) / 4 : null;
        return Wrap(
          spacing: 16,
          runSpacing: 16,
          children: actions.map((a) => _ShortcutCard(data: a, width: cardWidth)).toList(),
        );
      },
    );
  }
}

class _ShortcutData {
  _ShortcutData({
    required this.title,
    required this.subtitle,
    required this.colors,
    required this.icon,
    this.onTap,
  });
  final String title;
  final String subtitle;
  final List<Color> colors;
  final IconData icon;
  final VoidCallback? onTap;
}

class _ShortcutCard extends StatelessWidget {
  const _ShortcutCard({required this.data, this.width});
  final _ShortcutData data;
  final double? width;
  @override
  Widget build(BuildContext context) {
    final enabled = data.onTap != null;
    final theme = Theme.of(context);
    final blendedColors = data.colors
        .map((c) => Color.lerp(theme.colorScheme.surface, c, 0.25)!)
        .toList();
    final child = Container(
      width: width,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: LinearGradient(colors: blendedColors, begin: Alignment.topLeft, end: Alignment.bottomRight),
        border: Border.all(color: blendedColors.last.withValues(alpha: 0.25)),
        boxShadow: [
          BoxShadow(color: blendedColors.last.withValues(alpha: 0.25), blurRadius: 18, offset: const Offset(0, 12)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white.withValues(alpha: 0.15)),
            child: Icon(data.icon, color: Colors.white),
          ),
          const SizedBox(height: 16),
          Text(data.title,
              style: theme.textTheme.titleMedium?.copyWith(color: Colors.white, fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          Text(data.subtitle, style: theme.textTheme.bodySmall?.copyWith(color: Colors.white.withValues(alpha: 0.85))),
        ],
      ),
    );
    if (!enabled) return Opacity(opacity: 0.4, child: child);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(28),
        onTap: data.onTap,
        splashColor: Colors.white.withValues(alpha: 0.1),
        child: child,
      ),
    );
  }
}

class _PageHeader extends StatelessWidget {
  const _PageHeader({required this.state});
  final AutoInvestState state;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final subtitle = state.isEnabled
        ? 'Bot activo Â· monitoreando ${state.positions.length} posiciones'
        : 'Configura las reglas y activa el bot cuando estÃ©s listo.';
    return SoftSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Auto Invest cockpit', style: theme.textTheme.headlineMedium),
                    const SizedBox(height: 6),
                    Text(subtitle, style: theme.textTheme.bodyMedium),
                  ],
                ),
              ),
              OutlinedButton.icon(
                onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Tips rÃ¡pidos disponibles en la documentaciÃ³n.')),
                ),
                icon: const Icon(Icons.help_outline, size: 18),
                label: const Text('GuÃ­a rÃ¡pida'),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: const [
              _HeaderMetricChip(label: 'Simulaciones', value: null, icon: Icons.auto_graph),
              _HeaderMetricChip(label: 'Ejecuciones', value: null, icon: Icons.play_circle_outline),
              _HeaderMetricChip(label: 'Modo', value: null, icon: Icons.memory),
            ],
          ),
        ],
      ),
    );
  }
}

class _HeaderMetricChip extends StatelessWidget {
  const _HeaderMetricChip({required this.label, required this.icon, this.value});
  final String label;
  final String? value;
  final IconData icon;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final resolved = value ?? '';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(32),
        color: Colors.white.withValues(alpha: 0.04),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: theme.colorScheme.secondary),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: theme.textTheme.labelSmall?.copyWith(color: Colors.white70)),
              Text(resolved, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.active});
  final bool active;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = active ? const Color(0xFF66E39B) : Colors.white54;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(40),
        color: Colors.white.withValues(alpha: 0.08),
        border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(color: color.withValues(alpha: 0.6), blurRadius: 8, spreadRadius: 1),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(active ? 'Conectada' : 'Sin vÃ­nculo',
              style: theme.textTheme.bodySmall?.copyWith(color: Colors.white)),
        ],
      ),
    );
  }
}

class _VirtualWalletCard extends StatelessWidget {
  const _VirtualWalletCard({
    required this.connected,
    required this.shortAddress,
    required this.solBalance,
    required this.usdBalance,
    required this.lastUpdated,
  });
  final bool connected;
  final String? shortAddress;
  final double solBalance;
  final double? usdBalance;
  final DateTime? lastUpdated;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = connected
        ? [theme.colorScheme.primary.withValues(alpha: 0.25), theme.colorScheme.primary.withValues(alpha: 0.05)]
        : [theme.colorScheme.surface.withValues(alpha: 0.85), theme.colorScheme.surface.withValues(alpha: 0.6)];
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(32),
        gradient: LinearGradient(colors: colors, begin: Alignment.topLeft, end: Alignment.bottomRight),
        border: Border.all(color: theme.colorScheme.primary.withValues(alpha: 0.1)),
        boxShadow: [
          BoxShadow(color: theme.colorScheme.primary.withValues(alpha: 0.2), blurRadius: 30, offset: const Offset(0, 20)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Saldo actual',
              style: theme.textTheme.labelMedium?.copyWith(color: Colors.white.withValues(alpha: 0.75))),
          const SizedBox(height: 6),
          Text('${solBalance.toStringAsFixed(3)} SOL',
              style: theme.textTheme.headlineMedium?.copyWith(color: Colors.white, fontWeight: FontWeight.w600)),
          if (usdBalance != null)
            Text('\$${usdBalance!.toStringAsFixed(2)} USD',
                style: theme.textTheme.bodyLarge?.copyWith(color: Colors.white.withValues(alpha: 0.85))),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Wallet', style: theme.textTheme.labelSmall?.copyWith(color: Colors.white70)),
                    const SizedBox(height: 4),
                    Text(shortAddress ?? 'Pendiente de vincular',
                        style: theme.textTheme.titleMedium?.copyWith(color: Colors.white, fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white.withValues(alpha: 0.18)),
                child: const Icon(Icons.wallet_rounded, color: Colors.white),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            lastUpdated == null ? 'Sincroniza para obtener el balance.' : 'Actualizado ${DateFormat('HH:mm').format(lastUpdated!)}',
            style: theme.textTheme.bodySmall?.copyWith(color: Colors.white.withValues(alpha: 0.75)),
          ),
          const SizedBox(height: 12),
          Row(
            children: List.generate(
              4,
              (index) => Expanded(
                child: Container(
                  margin: EdgeInsets.only(right: index == 3 ? 0 : 6),
                  height: 4,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(4),
                    color: index == 1 ? Colors.white : Colors.white.withValues(alpha: 0.25),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _WalletStatPill extends StatelessWidget {
  const _WalletStatPill({required this.label, required this.value, required this.helper});
  final String label;
  final String value;
  final String helper;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(18),
      constraints: const BoxConstraints(minWidth: 180),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        color: theme.colorScheme.surface.withValues(alpha: 0.9),
        border: Border.all(color: theme.colorScheme.primary.withValues(alpha: 0.15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: theme.textTheme.labelSmall?.copyWith(color: Colors.white.withValues(alpha: 0.7))),
          const SizedBox(height: 6),
          Text(value, style: theme.textTheme.titleLarge?.copyWith(color: Colors.white, fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Text(helper, style: theme.textTheme.bodySmall?.copyWith(color: Colors.white.withValues(alpha: 0.7))),
        ],
      ),
    );
  }
}






