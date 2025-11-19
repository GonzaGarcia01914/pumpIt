import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../featured_coins/controller/featured_coin_notifier.dart';
import '../../featured_coins/models/featured_coin.dart';
import '../controller/auto_invest_notifier.dart';
import '../models/execution_mode.dart';
import '../models/sale_level.dart';
import '../../../core/widgets/hover_glow.dart';
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
            _ManualMintsSection(state: state, notifier: notifier),
            const SizedBox(height: 16),
            _RiskSection(state: state, notifier: notifier),
            const SizedBox(height: 16),
            _LimitsSection(state: state, notifier: notifier),
            const SizedBox(height: 16),
            _EliteFeaturesSection(),
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
              onAnalyze: notifier.analyzeClosedPositions,
              collapsed: true,
            ),
            if (state.statusMessage != null) ...[
              const SizedBox(height: 12),
              Text(
                state.statusMessage!,
                style: Theme.of(context).textTheme.bodySmall,
              ),
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
    final progress = total <= 0
        ? 0.0
        : (deployed / total).clamp(0, 1).toDouble();
    return SoftSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionHeader(
            icon: Icons.savings_outlined,
            title: 'Presupuestos (SOL)',
            subtitle: 'Define límites globales y por token',
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
            onChanged: state.walletBalanceSol > 0
                ? notifier.toggleAutoBudgetSync
                : null,
            title: const Text('Ajustar al saldo de la wallet'),
            subtitle: Text(
              state.walletBalanceSol > 0
                  ? 'Mantén el presupuesto como un porcentaje del balance.'
                  : 'Conecta y sincroniza tu wallet para habilitarlo.',
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Presupuesto total (% de la wallet)',
            style: Theme.of(context).textTheme.labelMedium,
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                for (final p in [
                  0.1,
                  0.2,
                  0.3,
                  0.4,
                  0.5,
                  0.6,
                  0.7,
                  0.8,
                  0.9,
                  1.0,
                ])
                  _PercentChip(
                    label: '${(p * 100).toInt()}%',
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
          ),
          const SizedBox(height: 8),
          Text(
            'Máximo por memecoin (% del presupuesto)',
            style: Theme.of(context).textTheme.labelMedium,
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                for (final p in [
                  0.1,
                  0.2,
                  0.3,
                  0.4,
                  0.5,
                  0.6,
                  0.7,
                  0.8,
                  0.9,
                  1.0,
                ])
                  _PercentChip(
                    label: '${(p * 100).toInt()}%',
                    selected: (state.perCoinPercentOfTotal - p).abs() < 0.001,
                    onPressed: state.totalBudgetSol <= 0
                        ? null
                        : () {
                            if (state.syncBudgetToWallet) {
                              notifier.setAutoPerCoinPercent(p);
                            } else {
                              notifier.applyPerCoinPercent(p);
                            }
                          },
                  ),
              ],
            ),
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
                label: 'Máximo por memecoin',
                value: state.perCoinBudgetSol,
                suffix: 'SOL',
                onChanged: notifier.updatePerCoinBudget,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'Disponible: ${state.availableBudgetSol.toStringAsFixed(2)} SOL · En uso ${deployed.toStringAsFixed(2)} SOL',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 4),
          Text(
            'PnL realizado: ${state.realizedProfitSol.toStringAsFixed(3)} SOL · Retirado ${state.withdrawnProfitSol.toStringAsFixed(3)} SOL',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          Text(
            'El bot nunca invertirá más que estos límites. Ajusta según tu apetito de riesgo.',
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
  const _SectionHeader({
    required this.icon,
    required this.title,
    this.subtitle,
  });
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
              colors: [
                accent.withValues(alpha: 0.3),
                accent.withValues(alpha: 0.1),
              ],
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
              if (subtitle != null)
                Text(subtitle!, style: theme.textTheme.bodySmall),
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
            subtitle: 'Rangos de market cap, volumen y señales sociales',
          ),
          const SizedBox(height: 18),
          _SectionLabel('Market Cap (USD)'),
          const SizedBox(height: 8),
          _RRow(
            children: [
              _NumberField(
                label: 'M\u00ednimo',
                value: state.minMarketCap,
                onChanged: notifier.updateMinMarketCap,
              ),
              _NumberField(
                label: 'M\u00e1ximo',
                value: state.maxMarketCap,
                onChanged: notifier.updateMaxMarketCap,
              ),
            ],
          ),
          const SizedBox(height: 16),
          _NumberField(
            label: 'Liquidez mínima USD',
            value: state.minLiquidity,
            onChanged: notifier.updateMinLiquidity,
          ),
          const SizedBox(height: 16),
          // ⚡ Volumen unificado: min/max, unidad y tiempo
          _SectionLabel('Volumen'),
          const SizedBox(height: 8),
          _RRow(
            children: [
              _NumberField(
                label: 'Mínimo',
                value: state.minVolume24h,
                onChanged: notifier.updateMinVolume,
              ),
              _NumberField(
                label: 'Máximo',
                value: state.maxVolume24h,
                onChanged: notifier.updateMaxVolume,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<VolumeTimeUnit>(
                  value: state.volumeTimeUnit,
                  decoration: const InputDecoration(
                    labelText: 'Unidad',
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 16,
                    ),
                  ),
                  items: VolumeTimeUnit.values
                      .map(
                        (unit) => DropdownMenuItem(
                          value: unit,
                          child: Text(unit == VolumeTimeUnit.minutes ? 'min' : 'h'),
                        ),
                      )
                      .toList(),
                  onChanged: (unit) {
                    if (unit != null) notifier.updateVolumeTimeUnit(unit);
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _NumberField(
                  label: 'Tiempo',
                  value: state.volumeTimeValue,
                  onChanged: notifier.updateVolumeTimeValue,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _NumberField(
            label: 'Mínimo replies',
            value: state.minReplies,
            onChanged: notifier.updateMinReplies,
          ),
          const SizedBox(height: 16),
          // ⚡ Edad unificada: min/max con unidad
          _SectionLabel('Edad del token'),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _NumberField(
                  label: 'Edad mín.',
                  value: state.minAgeValue,
                  onChanged: notifier.updateMinAgeValue,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _NumberField(
                  label: 'Edad máxima',
                  value: state.maxAgeValue,
                  onChanged: notifier.updateMaxAgeValue,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: DropdownButtonFormField<TimeUnit>(
                  value: state.ageTimeUnit,
                  decoration: const InputDecoration(
                    labelText: 'Unidad',
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 16,
                    ),
                  ),
                  items: TimeUnit.values
                      .map(
                        (unit) => DropdownMenuItem(
                          value: unit,
                          child: Text(unit == TimeUnit.minutes ? 'min' : 'h'),
                        ),
                      )
                      .toList(),
                  onChanged: (unit) {
                    if (unit != null) notifier.updateAgeTimeUnit(unit);
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SwitchListTile.adaptive(
            value: state.preferNewest,
            onChanged: notifier.updatePreferNewest,
            title: const Text('Priorizar tokens más recientes'),
            subtitle: const Text(
              'Si está activo, el bot elegirá primero los mints más nuevos que cumplan los filtros.',
            ),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: notifier.resetMarketFilters,
              icon: const Icon(Icons.restart_alt),
              label: const Text('Restablecer filtros'),
            ),
          ),
        ],
      ),
    );
  }
}

class _ManualMintsSection extends StatefulWidget {
  const _ManualMintsSection({required this.state, required this.notifier});
  final AutoInvestState state;
  final AutoInvestNotifier notifier;
  @override
  State<_ManualMintsSection> createState() => _ManualMintsSectionState();
}

class _ManualMintsSectionState extends State<_ManualMintsSection> {
  late final TextEditingController _controller;
  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final state = widget.state;
    final notifier = widget.notifier;
    return SoftSurface(
      color: theme.colorScheme.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionHeader(
            icon: Icons.playlist_add,
            title: 'Mints manuales',
            subtitle: 'Incluye direcciones de mint adicionales a Featured',
          ),
          const SizedBox(height: 14),
          SwitchListTile.adaptive(
            value: state.includeManualMints,
            onChanged: notifier.toggleIncludeManualMints,
            title: const Text('Incluir mints manuales en la selección'),
            subtitle: const Text(
              'No excluye Featured; solo agrega estas direcciones',
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _controller,
                  decoration: const InputDecoration(
                    labelText: 'Mint address (Solana)',
                    hintText: 'Ej: So11111111111111111111111111111111111111112',
                  ),
                ),
              ),
              const SizedBox(width: 10),
              FilledButton.icon(
                onPressed: () {
                  final v = _controller.text.trim();
                  if (v.isNotEmpty) {
                    notifier.addManualMint(v);
                    _controller.clear();
                  }
                },
                icon: const Icon(Icons.add),
                label: const Text('Agregar'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (state.manualMints.isNotEmpty)
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: state.manualMints
                  .map(
                    (m) => Chip(
                      label: Text(m),
                      onDeleted: () => notifier.removeManualMint(m),
                    ),
                  )
                  .toList(),
            )
          else
            Text(
              'Aún no agregaste mints manuales.',
              style: theme.textTheme.bodySmall,
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
            subtitle: 'Ventas escalonadas y trailing stop',
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
          _SaleLevelsEditor(
            title: 'Ventas escalonadas - Take Profit',
            levels: state.takeProfitLevels,
            onAdd: (level) => notifier.addTakeProfitLevel(level),
            onRemove: (index) => notifier.removeTakeProfitLevel(index),
            onUpdate: (index, level) => notifier.updateTakeProfitLevel(index, level),
            isTakeProfit: true,
          ),
          const SizedBox(height: 16),
          _SaleLevelsEditor(
            title: 'Ventas escalonadas - Stop Loss',
            levels: state.stopLossLevels,
            onAdd: (level) => notifier.addStopLossLevel(level),
            onRemove: (index) => notifier.removeStopLossLevel(index),
            onUpdate: (index, level) => notifier.updateStopLossLevel(index, level),
            isTakeProfit: false,
          ),
          const SizedBox(height: 16),
          SwitchListTile.adaptive(
            value: state.trailingStopEnabled,
            onChanged: notifier.updateTrailingStopEnabled,
            title: const Text('Trailing Stop Loss'),
            subtitle: const Text(
              'Ajusta el stop loss automáticamente cuando el precio sube',
            ),
          ),
          if (state.trailingStopEnabled) ...[
            const SizedBox(height: 8),
            _SliderTile(
              label: 'Trailing Stop %',
              value: state.trailingStopPercent.clamp(1, 50),
              min: 1,
              max: 50,
              suffix: '%',
              subtitle: 'Porcentaje de retroceso desde el máximo para activar stop loss',
              onChanged: notifier.updateTrailingStopPercent,
            ),
          ],
          const SizedBox(height: 12),
          SwitchListTile.adaptive(
            value: state.withdrawOnGain,
            onChanged: notifier.updateWithdrawOnGain,
            title: const Text('Retirar tras ganancia'),
            subtitle: const Text(
              'Si está activo, el bot moverá las utilidades al presupuesto general antes de reinvertir.',
            ),
          ),
        ],
      ),
    );
  }
}

class _EliteFeaturesSection extends ConsumerWidget {
  const _EliteFeaturesSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return SoftSurface(
      color: theme.colorScheme.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionHeader(
            icon: Icons.stars_rounded,
            title: 'Características Elite',
            subtitle: 'Funciones avanzadas activas automáticamente',
          ),
          const SizedBox(height: 16),
          _EliteFeatureCard(
            icon: Icons.speed,
            title: 'Priority Fees Dinámicos',
            description:
                'Ajusta automáticamente los fees según congestión de red y competencia',
            status: 'Activo',
            isActive: true,
          ),
          const SizedBox(height: 12),
          _EliteFeatureCard(
            icon: Icons.shield,
            title: 'Detección de Rug Pulls',
            description:
                'Analiza tokens antes de comprar para detectar riesgos de seguridad',
            status: 'Activo',
            isActive: true,
          ),
          const SizedBox(height: 12),
          _EliteFeatureCard(
            icon: Icons.water_drop,
            title: 'Detección de Whales',
            description:
                'Monitorea actividad de wallets grandes y detecta ventas del creator',
            status: 'Activo',
            isActive: true,
          ),
          const SizedBox(height: 12),
          _EliteFeatureCard(
            icon: Icons.trending_up,
            title: 'Slippage Dinámico',
            description:
                'Ajusta slippage automáticamente según volatilidad y liquidez',
            status: 'Activo',
            isActive: true,
          ),
          const SizedBox(height: 12),
          _EliteFeatureCard(
            icon: Icons.access_time,
            title: 'Timing de Entrada Inteligente',
            description:
                'Espera confirmación de momentum y detecta pumps reales vs fake pumps',
            status: 'Activo',
            isActive: true,
          ),
          const SizedBox(height: 12),
          _EliteFeatureCard(
            icon: Icons.wifi_tethering,
            title: 'Monitoreo de Pools en Tiempo Real',
            description:
                'Reacciona en <100ms a cambios críticos usando WebSockets',
            status: 'Activo',
            isActive: true,
          ),
          const SizedBox(height: 12),
          _EliteFeatureCard(
            icon: Icons.error_outline,
            title: 'Manejo de Errores Inteligente',
            description:
                'Clasifica errores y aplica circuit breaker para evitar loops infinitos',
            status: 'Activo',
            isActive: true,
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: theme.colorScheme.primaryContainer.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: theme.colorScheme.primary.withValues(alpha: 0.2),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.info_outline,
                  size: 20,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Estas características funcionan automáticamente en segundo plano. '
                    'Los mensajes de status mostrarán cuando se activen.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _EliteFeatureCard extends StatelessWidget {
  const _EliteFeatureCard({
    required this.icon,
    required this.title,
    required this.description,
    required this.status,
    required this.isActive,
  });

  final IconData icon;
  final String title;
  final String description;
  final String status;
  final bool isActive;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isActive
            ? theme.colorScheme.primaryContainer.withValues(alpha: 0.15)
            : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isActive
              ? theme.colorScheme.primary.withValues(alpha: 0.3)
              : theme.colorScheme.outline.withValues(alpha: 0.2),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: isActive
                  ? theme.colorScheme.primary.withValues(alpha: 0.2)
                  : theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              icon,
              size: 20,
              color: isActive
                  ? theme.colorScheme.primary
                  : theme.colorScheme.onSurface.withValues(alpha: 0.5),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: isActive
                              ? theme.colorScheme.onSurface
                              : theme.colorScheme.onSurface.withValues(alpha: 0.7),
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: isActive
                            ? Colors.green.withValues(alpha: 0.2)
                            : Colors.grey.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        status,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: isActive ? Colors.green : Colors.grey,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  description,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LimitsSection extends StatelessWidget {
  const _LimitsSection({required this.state, required this.notifier});
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
            icon: Icons.speed,
            title: 'Límites y controles',
            subtitle: 'Límites de tokens simultáneos y límites diarios',
          ),
          const SizedBox(height: 18),
          _NumberField(
            label: 'Máx. tokens simultáneos',
            value: state.maxTokensSimultaneous.toDouble(),
            onChanged: (value) => notifier.updateMaxTokensSimultaneous(value.toInt()),
            suffix: 'tokens',
          ),
          const SizedBox(height: 16),
          _RRow(
            children: [
              _NumberField(
                label: 'Máx. pérdida/día',
                value: state.maxLossPerDay,
                onChanged: notifier.updateMaxLossPerDay,
                suffix: 'SOL',
              ),
              _NumberField(
                label: 'Máx. ganancia/día',
                value: state.maxEarningPerDay,
                onChanged: notifier.updateMaxEarningPerDay,
                suffix: 'SOL',
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Nota: 0 = sin límite. Los límites se calculan desde posiciones cerradas hoy.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
            ),
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
    final usingPumpPortal =
        state.executionMode == AutoInvestExecutionMode.pumpPortal;
    return SoftSurface(
      color: theme.colorScheme.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionHeader(
            icon: Icons.memory,
            title: 'Motor de ejecución',
            subtitle: 'Selecciona entre Jupiter o PumpPortal',
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: AutoInvestExecutionMode.values
                .map(
                  (mode) => _ModeChip(
                    label: mode == AutoInvestExecutionMode.jupiter
                        ? 'Jupiter'
                        : 'PumpPortal',
                    description: mode == AutoInvestExecutionMode.jupiter
                        ? 'Tokens graduados'
                        : 'Bonding curve',
                    selected: state.executionMode == mode,
                    onTap: () => notifier.setExecutionMode(mode),
                  ),
                )
                .toList(),
          ),
          const SizedBox(height: 12),
          Text(
            state.executionMode == AutoInvestExecutionMode.jupiter
                ? 'Usa quotes de Jupiter, ideal para tokens que ya migraron liquidez.'
                : 'Construye órdenes sobre la bonding curve vía PumpPortal.',
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
              initialValue: state.pumpPool,
              decoration: const InputDecoration(labelText: 'Pool preferido'),
              items: _poolOptions
                  .map((p) => DropdownMenuItem(value: p, child: Text(p)))
                  .toList(),
              onChanged: (value) {
                if (value != null) notifier.updatePumpPool(value);
              },
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
                Text(
                  enabled ? 'Auto invest activo' : 'Auto invest pausado',
                  style: theme.textTheme.titleMedium,
                ),
                const SizedBox(height: 6),
                Text(
                  state.walletAddress == null
                      ? 'Conecta una wallet para habilitar el bot.'
                      : 'El bot evaluará los criterios en cada refresco.',
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
          Switch.adaptive(
            value: enabled,
            onChanged: state.walletAddress == null
                ? null
                : (value) => notifier.toggleEnabled(value),
          ),
        ],
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
      decoration: InputDecoration(
        labelText: widget.label,
        suffixText: widget.suffix,
      ),
      onChanged: (text) {
        final normalized = text.replaceAll(',', '.');
        final parsed = double.tryParse(normalized);
        if (parsed != null) widget.onChanged(parsed);
      },
    );
  }

  String _format(double value) {
    final isInt = value % 1 == 0;
    return isInt ? value.toStringAsFixed(0) : value.toString();
  }
}

class _SliderTile extends StatelessWidget {
  const _SliderTile({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    this.suffix,
    this.subtitle,
  });
  final String label;
  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;
  final String? suffix;
  final String? subtitle;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              '$label ${suffix != null ? '(${value.toStringAsFixed(0)}$suffix)' : value.toStringAsFixed(0)}',
              style: theme.textTheme.bodyMedium,
            ),
            const Spacer(),
            Text(
              '${value.toStringAsFixed(0)}${suffix ?? ''}',
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 4),
          Text(
            subtitle!,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
            ),
          ),
          const SizedBox(height: 8),
        ],
        Slider(
          min: min,
          max: max,
          divisions: (max - min).toInt(),
          value: value,
          onChanged: onChanged,
        ),
      ],
    );
  }
}

class _ModeChip extends StatelessWidget {
  const _ModeChip({
    required this.label,
    required this.description,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final String description;
  final bool selected;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final background = selected
        ? theme.colorScheme.primary.withValues(alpha: 0.25)
        : Colors.white.withValues(alpha: 0.05);
    final radius = BorderRadius.circular(26);
    final glowColor = selected
        ? theme.colorScheme.primary.withValues(alpha: 0.5)
        : Colors.white.withValues(alpha: 0.25);
    final child = Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      decoration: BoxDecoration(
        borderRadius: radius,
        color: background,
        border: Border.all(
          color: selected
              ? theme.colorScheme.primary.withValues(alpha: 0.5)
              : Colors.white.withValues(alpha: 0.1),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            selected ? Icons.check_circle : Icons.circle_outlined,
            size: 18,
            color: selected ? theme.colorScheme.primary : Colors.white70,
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                description,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: Colors.white70,
                ),
              ),
            ],
          ),
        ],
      ),
    );
    return HoverGlow(
      borderRadius: radius,
      glowColor: glowColor,
      blurRadius: 28,
      spreadRadius: -10,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: radius,
          hoverColor: Colors.white.withValues(alpha: 0.08),
          child: child,
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
    return SoftSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: theme.colorScheme.primary.withValues(alpha: 0.15),
                ),
                child: const Icon(Icons.play_circle_outline),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Simular auto invest',
                      style: theme.textTheme.titleMedium,
                    ),
                    Text(
                      'Prueba la configuración actual sin riesgo. Los resultados viven en la pestaña Resultados.',
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
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
                label: Text(
                  state.isSimulationRunning
                      ? 'Simulando...'
                      : 'Simular auto invest',
                ),
              ),
              Text(
                'Operaciones simuladas: ${state.simulations.length}',
                style: theme.textTheme.bodySmall,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _BudgetProgressBar extends StatelessWidget {
  const _BudgetProgressBar({
    required this.progress,
    required this.availableLabel,
    required this.deployedLabel,
  });
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

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      text,
      style: theme.textTheme.titleSmall?.copyWith(
        fontWeight: FontWeight.bold,
        color: theme.colorScheme.onSurface,
      ),
    );
  }
}

class _SaleLevelsEditor extends StatefulWidget {
  const _SaleLevelsEditor({
    required this.title,
    required this.levels,
    required this.onAdd,
    required this.onRemove,
    required this.onUpdate,
    required this.isTakeProfit,
  });
  final String title;
  final List<SaleLevel> levels;
  final void Function(SaleLevel) onAdd;
  final void Function(int) onRemove;
  final void Function(int, SaleLevel) onUpdate;
  final bool isTakeProfit;

  @override
  State<_SaleLevelsEditor> createState() => _SaleLevelsEditorState();
}

class _SaleLevelsEditorState extends State<_SaleLevelsEditor> {
  void _showAddDialog() {
    showDialog(
      context: context,
      builder: (context) => _SaleLevelDialog(
        isTakeProfit: widget.isTakeProfit,
        onSave: widget.onAdd,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              widget.title,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            TextButton.icon(
              onPressed: _showAddDialog,
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Agregar nivel'),
            ),
          ],
        ),
        if (widget.levels.isEmpty)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              'No hay niveles configurados. Agrega uno para activar ventas escalonadas.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
          )
        else
          ...widget.levels.asMap().entries.map((entry) {
            final index = entry.key;
            final level = entry.value;
            return Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                title: Text(
                  '${widget.isTakeProfit ? '+' : ''}${level.pnlPercent.toStringAsFixed(2)}% → Vender ${level.sellPercent.toStringAsFixed(0)}% del restante',
                ),
                trailing: IconButton(
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () => widget.onRemove(index),
                ),
                onTap: () {
                  showDialog(
                    context: context,
                    builder: (context) => _SaleLevelDialog(
                      isTakeProfit: widget.isTakeProfit,
                      initialLevel: level,
                      onSave: (updated) => widget.onUpdate(index, updated),
                    ),
                  );
                },
              ),
            );
          }),
      ],
    );
  }
}

class _SaleLevelDialog extends StatefulWidget {
  const _SaleLevelDialog({
    required this.isTakeProfit,
    required this.onSave,
    this.initialLevel,
  });
  final bool isTakeProfit;
  final SaleLevel? initialLevel;
  final void Function(SaleLevel) onSave;

  @override
  State<_SaleLevelDialog> createState() => _SaleLevelDialogState();
}

class _SaleLevelDialogState extends State<_SaleLevelDialog> {
  late final TextEditingController _pnlController;
  late final TextEditingController _sellController;

  @override
  void initState() {
    super.initState();
    _pnlController = TextEditingController(
      text: widget.initialLevel?.pnlPercent.toStringAsFixed(2) ?? '',
    );
    _sellController = TextEditingController(
      text: widget.initialLevel?.sellPercent.toStringAsFixed(0) ?? '',
    );
  }

  @override
  void dispose() {
    _pnlController.dispose();
    _sellController.dispose();
    super.dispose();
  }

  void _save() {
    final pnl = double.tryParse(_pnlController.text);
    final sell = double.tryParse(_sellController.text);
    if (pnl == null || sell == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Valores inválidos')),
      );
      return;
    }
    if (widget.isTakeProfit && pnl <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('El PnL para Take Profit debe ser positivo')),
      );
      return;
    }
    if (!widget.isTakeProfit && pnl >= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('El PnL para Stop Loss debe ser negativo')),
      );
      return;
    }
    if (sell < 0 || sell > 100) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('El porcentaje a vender debe estar entre 0 y 100')),
      );
      return;
    }
    widget.onSave(SaleLevel(pnlPercent: pnl, sellPercent: sell));
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.isTakeProfit ? 'Nivel Take Profit' : 'Nivel Stop Loss'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _pnlController,
            decoration: InputDecoration(
              labelText: 'PnL % para activar',
              hintText: widget.isTakeProfit ? 'Ej: 15' : 'Ej: -10',
              helperText: widget.isTakeProfit
                  ? 'Porcentaje de ganancia que activa este nivel'
                  : 'Porcentaje de pérdida que activa este nivel',
            ),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _sellController,
            decoration: const InputDecoration(
              labelText: '% a vender',
              hintText: 'Ej: 50',
              helperText: 'Porcentaje del restante a vender en este nivel',
            ),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _save,
          child: const Text('Guardar'),
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
    final radius = BorderRadius.circular(30);
    final chip = Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
      decoration: BoxDecoration(
        borderRadius: radius,
        gradient: enabled
            ? LinearGradient(
                colors: gradient,
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              )
            : null,
        color: enabled ? null : Colors.white.withValues(alpha: 0.06),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: Text(
        label,
        style: theme.textTheme.bodyMedium?.copyWith(
          fontWeight: FontWeight.w600,
          color: Colors.white,
        ),
      ),
    );
    if (!enabled) return Opacity(opacity: 0.4, child: chip);
    return HoverGlow(
      borderRadius: radius,
      glowColor: gradient.last.withValues(alpha: 0.45),
      blurRadius: 30,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: radius,
          hoverColor: Colors.white.withValues(alpha: 0.08),
          onTap: onTap,
          child: chip,
        ),
      ),
    );
  }
}

class _PercentChip extends StatelessWidget {
  const _PercentChip({
    required this.label,
    this.selected = false,
    this.onPressed,
  });
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
    final radius = BorderRadius.circular(24);
    final chip = Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(borderRadius: radius, color: background),
      child: Text(
        label,
        style: theme.textTheme.bodyMedium?.copyWith(
          fontWeight: FontWeight.w600,
          color: textColor,
        ),
      ),
    );
    if (onPressed == null) return Opacity(opacity: 0.4, child: chip);
    final glowColor = selected
        ? theme.colorScheme.primary.withValues(alpha: 0.4)
        : Colors.white.withValues(alpha: 0.2);
    return HoverGlow(
      borderRadius: radius,
      glowColor: glowColor,
      blurRadius: 24,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: radius,
          hoverColor: Colors.white.withValues(alpha: 0.08),
          onTap: onPressed,
          child: chip,
        ),
      ),
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
                    Text(
                      'Wallet control room',
                      style: theme.textTheme.headlineSmall,
                    ),
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
            usdBalance: (state.solPriceUsd > 0
                ? state.walletBalanceSol * state.solPriceUsd
                : null),
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
                icon: Icon(
                  connected ? Icons.logout_rounded : Icons.link_rounded,
                ),
                label: Text(connected ? 'Desconectar' : 'Conectar wallet'),
              ),
              OutlinedButton.icon(
                onPressed: state.walletAddress != null
                    ? notifier.refreshWalletBalance
                    : null,
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
        onTap: state.walletAddress == null
            ? null
            : notifier.refreshWalletBalance,
      ),
      _ShortcutData(
        title: 'Simular setup',
        subtitle: 'Backtest inmediato',
        colors: const [Color(0xFF7A5CFF), Color(0xFFB55DFF)],
        icon: Icons.auto_graph,
        onTap: state.isSimulationRunning
            ? null
            : () => notifier.simulate(availableCoins),
      ),
      _ShortcutData(
        title: 'Analizar PnL',
        subtitle: 'Insights IA/heurístico',
        colors: const [Color(0xFF4FD1FF), Color(0xFF7B89FF)],
        icon: Icons.bolt,
        onTap:
            state.isAnalyzingResults ? null : notifier.analyzeClosedPositions,
      ),
      _ShortcutData(
        title: state.isEnabled ? 'Pausar bot' : 'Activar bot',
        subtitle: state.walletAddress == null
            ? 'Conecta una wallet'
            : state.isEnabled
            ? 'Detiene nuevas órdenes'
            : 'Usa las reglas actuales',
        colors: const [Color(0xFF4CFFCE), Color(0xFF7B6CFF)],
        icon: state.isEnabled ? Icons.pause : Icons.play_arrow,
        onTap: state.walletAddress == null
            ? null
            : () => notifier.toggleEnabled(!state.isEnabled),
      ),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final cardWidth = width > 900 ? (width - 48) / 4 : null;
        return Wrap(
          spacing: 16,
          runSpacing: 16,
          children: actions
              .map((a) => _ShortcutCard(data: a, width: cardWidth))
              .toList(),
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
    final radius = BorderRadius.circular(28);
    final child = Container(
      width: width,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: radius,
        gradient: LinearGradient(
          colors: blendedColors,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(color: blendedColors.last.withValues(alpha: 0.25)),
        boxShadow: [
          BoxShadow(
            color: blendedColors.last.withValues(alpha: 0.25),
            blurRadius: 18,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withValues(alpha: 0.15),
            ),
            child: Icon(data.icon, color: Colors.white),
          ),
          const SizedBox(height: 16),
          Text(
            data.title,
            style: theme.textTheme.titleMedium?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            data.subtitle,
            style: theme.textTheme.bodySmall?.copyWith(
              color: Colors.white.withValues(alpha: 0.85),
            ),
          ),
        ],
      ),
    );
    if (!enabled) return Opacity(opacity: 0.4, child: child);
    final interactive = Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: radius,
        onTap: data.onTap,
        splashColor: Colors.white.withValues(alpha: 0.1),
        child: child,
      ),
    );
    return HoverGlow(
      borderRadius: radius,
      glowColor: blendedColors.last.withValues(alpha: 0.35),
      blurRadius: 42,
      spreadRadius: -14,
      shadowOffset: const Offset(0, 26),
      child: interactive,
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
        ? 'Bot activo · monitoreando ${state.positions.length} posiciones'
        : 'Configura las reglas y activa el bot cuando estés listo.';
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
                    Text(
                      'Auto Invest cockpit',
                      style: theme.textTheme.headlineMedium,
                    ),
                    const SizedBox(height: 6),
                    Text(subtitle, style: theme.textTheme.bodyMedium),
                  ],
                ),
              ),
              OutlinedButton.icon(
                onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                      'Tips rápidos disponibles en la documentación.',
                    ),
                  ),
                ),
                icon: const Icon(Icons.help_outline, size: 18),
                label: const Text('Guía rápida'),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: const [
              _HeaderMetricChip(
                label: 'Simulaciones',
                value: null,
                icon: Icons.auto_graph,
              ),
              _HeaderMetricChip(
                label: 'Ejecuciones',
                value: null,
                icon: Icons.play_circle_outline,
              ),
              _HeaderMetricChip(label: 'Modo', value: null, icon: Icons.memory),
            ],
          ),
        ],
      ),
    );
  }
}

class _HeaderMetricChip extends StatelessWidget {
  const _HeaderMetricChip({
    required this.label,
    required this.icon,
    this.value,
  });
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
              Text(
                label,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: Colors.white70,
                ),
              ),
              Text(
                resolved,
                style: theme.textTheme.titleMedium?.copyWith(
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
                BoxShadow(
                  color: color.withValues(alpha: 0.6),
                  blurRadius: 8,
                  spreadRadius: 1,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            active ? 'Conectada' : 'Sin vínculo',
            style: theme.textTheme.bodySmall?.copyWith(color: Colors.white),
          ),
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
        ? [
            theme.colorScheme.primary.withValues(alpha: 0.25),
            theme.colorScheme.primary.withValues(alpha: 0.05),
          ]
        : [
            theme.colorScheme.surface.withValues(alpha: 0.85),
            theme.colorScheme.surface.withValues(alpha: 0.6),
          ];
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(32),
        gradient: LinearGradient(
          colors: colors,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(
          color: theme.colorScheme.primary.withValues(alpha: 0.1),
        ),
        boxShadow: [
          BoxShadow(
            color: theme.colorScheme.primary.withValues(alpha: 0.2),
            blurRadius: 30,
            offset: const Offset(0, 20),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Saldo actual',
            style: theme.textTheme.labelMedium?.copyWith(
              color: Colors.white.withValues(alpha: 0.75),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '${solBalance.toStringAsFixed(3)} SOL',
            style: theme.textTheme.headlineMedium?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (usdBalance != null)
            Text(
              '\$${usdBalance!.toStringAsFixed(2)} USD',
              style: theme.textTheme.bodyLarge?.copyWith(
                color: Colors.white.withValues(alpha: 0.85),
              ),
            ),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Wallet',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: Colors.white70,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      shortAddress ?? 'Pendiente de vincular',
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: 0.18),
                ),
                child: const Icon(Icons.wallet_rounded, color: Colors.white),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            lastUpdated == null
                ? 'Sincroniza para obtener el balance.'
                : 'Actualizado ${DateFormat('HH:mm').format(lastUpdated!)}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: Colors.white.withValues(alpha: 0.75),
            ),
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
                    color: index == 1
                        ? Colors.white
                        : Colors.white.withValues(alpha: 0.25),
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
  const _WalletStatPill({
    required this.label,
    required this.value,
    required this.helper,
  });
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
        border: Border.all(
          color: theme.colorScheme.primary.withValues(alpha: 0.15),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: Colors.white.withValues(alpha: 0.7),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: theme.textTheme.titleLarge?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            helper,
            style: theme.textTheme.bodySmall?.copyWith(
              color: Colors.white.withValues(alpha: 0.7),
            ),
          ),
        ],
      ),
    );
  }
}
