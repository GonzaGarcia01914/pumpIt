import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../featured_coins/controller/featured_coin_notifier.dart';
import '../../featured_coins/models/featured_coin.dart';
import '../controller/auto_invest_notifier.dart';
import '../models/execution_mode.dart';
import 'widgets/analysis_drawer_panel.dart';

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
            Text('Auto Invest', style: theme.textTheme.headlineSmall),
            const SizedBox(height: 8),
            Text(
              'Configura los criterios del bot y vincula tu wallet '
              '(Phantom en web o keypair local en desktop).\n'
              'Cuando Auto Invest est� activo, las reglas se usar�n para futuras compras/ventas automatizadas.',
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
                    : 'El bot evaluar� los criterios en cada refresco.',
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
              Text(state.statusMessage!, style: theme.textTheme.bodySmall),
            ],
          ],
        ),
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
              ],\n
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
            ],\n
      ],
    );
  }
}

class _HeaderMetricChip extends StatelessWidget {
  const _HeaderMetricChip({
    required this.label,
    required this.value,
    required this.icon,
  });
  final String label;
  final String value;
  final IconData icon;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
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
                style:
                    theme.textTheme.labelSmall?.copyWith(color: Colors.white70),
              ),
              Text(
                value,
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ],\n;
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
              ],\n
          const SizedBox(width: 8),
          Text(
            active ? 'Conectada' : 'Sin vínculo',
            style: theme.textTheme.bodySmall?.copyWith(color: Colors.white),
          ),
        ],\n;
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
              color: Colors.white.withValues(alpha: 0.75),\n
          const SizedBox(height: 6),
          Text(
            '${solBalance.toStringAsFixed(3)} SOL',
            style: theme.textTheme.headlineMedium?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w600,\n
          if (usdBalance != null)
              '\$${usdBalance!.toStringAsFixed(2)} USD',
              style: theme.textTheme.bodyLarge?.copyWith(
                color: Colors.white.withValues(alpha: 0.85),\n
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
                        color: Colors.white70,\n
                    const SizedBox(height: 4),
                    Text(
                      shortAddress ?? 'Pendiente de vincular',
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,\n
                  ],\n
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: 0.18),
                ),
                child: const Icon(
                  Icons.wallet_rounded,
                  color: Colors.white,\n
            ],
          ),
          const SizedBox(height: 12),
          Text(
            lastUpdated == null
                ? 'Sincroniza para obtener el balance.'
                : 'Actualizado ${DateFormat('HH:mm').format(lastUpdated!)}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: Colors.white.withValues(alpha: 0.75),\n
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
                        : Colors.white.withValues(alpha: 0.25),\n\n
          ),
        ],\n;
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
          color: theme.colorScheme.primary.withValues(alpha: 0.15),\n
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: Colors.white.withValues(alpha: 0.7),\n
          const SizedBox(height: 6),
          Text(
            value,
            style: theme.textTheme.titleLarge?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w600,\n
          const SizedBox(height: 4),
          Text(
            helper,
            style: theme.textTheme.bodySmall?.copyWith(
              color: Colors.white.withValues(alpha: 0.7),\n
        ],\n;
  }
}

class _ResponsiveFieldRow extends StatelessWidget {
  const _ResponsiveFieldRow({required this.children});
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
            _PageHeader(state: state),
            const SizedBox(height: 20),
            _WalletPanel(state: state, notifier: notifier),
            _ActionShortcuts(
              state: state,
              notifier: notifier,
              availableCoins: featured.coins,
            ),
            _BudgetSection(state: state, notifier: notifier),
            _FilterSection(state: state, notifier: notifier),
            _RiskSection(state: state, notifier: notifier),
            _ExecutionModeSection(state: state, notifier: notifier),
            _BotToggleCard(state: state, notifier: notifier),
            const SizedBox(height: 12),
            
            AnalysisDrawerPanel(
              summary: state.analysisSummary,
              isLoading: state.isAnalyzingResults,
              onAnalyze: notifier.analyzeSimulations,
              collapsed: true,
            ),
            _PageHeader(state: state),
            const SizedBox(height: 20),
            _WalletPanel(state: state, notifier: notifier),
            _ActionShortcuts(
              state: state,
              notifier: notifier,
              availableCoins: featured.coins,
            ),
            _BudgetSection(state: state, notifier: notifier),
            _FilterSection(state: state, notifier: notifier),
            _RiskSection(state: state, notifier: notifier),
            _ExecutionModeSection(state: state, notifier: notifier),
            _BotToggleCard(state: state, notifier: notifier),
            const SizedBox(height: 12),
            
            AnalysisDrawerPanel(
              summary: state.analysisSummary,
              isLoading: state.isAnalyzingResults,
              onAnalyze: notifier.analyzeSimulations,
              collapsed: true,
            ),
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
    final gradient = const [
      Color(0xFF6E7BFF),
      Color(0xFF9A64FF),
    ];
    final chip = Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(30),
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
          color: Colors.white,\n
    );
    if (!enabled) {
      return Opacity(opacity: 0.4, child: chip);
    }
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(30),
        onTap: onTap,
        child: chip,\n;
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
            valueColor: AlwaysStoppedAnimation(
              theme.colorScheme.primary,\n
        ),
      ],
    );
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
  });
  final String label;
  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;
  final String? suffix;
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
                fontWeight: FontWeight.w600,\n
          ],
        ),
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
          color: textColor,\n
    );
    if (onPressed == null) {
      return Opacity(opacity: 0.4, child: chip);
    }
    return InkWell(
      borderRadius: BorderRadius.circular(24),
      onTap: onPressed,
      child: chip,
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
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(26),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(26),
            color: background,
            border: Border.all(
              color: selected
                  ? theme.colorScheme.primary.withValues(alpha: 0.5)
                  : Colors.white.withValues(alpha: 0.1),\n
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
                      fontWeight: FontWeight.w600,\n
                  Text(
                    description,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: Colors.white70,\n
                ],
              ),
            ],\n\n;
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
                    Text('Auto Invest cockpit',
                        style: theme.textTheme.headlineMedium),
                    const SizedBox(height: 6),
                    Text(subtitle, style: theme.textTheme.bodyMedium),
                  ],\n
              OutlinedButton.icon(
                onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Tips rápidos disponibles en la documentación.'),\n
                icon: const Icon(Icons.help_outline, size: 18),
                label: const Text('Guía rápida'),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              _HeaderMetricChip(
                label: 'Simulaciones',
                value: state.simulations.length.toString(),
                icon: Icons.auto_graph,
              ),
              _HeaderMetricChip(
                label: 'Ejecuciones',
                value: state.executions.length.toString(),
                icon: Icons.play_circle_outline,
              ),
              _HeaderMetricChip(
                label: 'Modo',
                value: state.executionMode.name,
                icon: Icons.memory,
              ),
            ],
          ),
        ],\n;
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
                    Text('Wallet control room',
                        style: theme.textTheme.headlineSmall),
                    const SizedBox(height: 4),
                    Text(
                      connected
                          ? 'Phantom/keypair vinculado y listo para asignar presupuesto.'
                          : 'Conecta Phantom o define LOCAL_KEY_PATH para keypair local.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: Colors.white.withValues(alpha: 0.75),\n
                  ],\n
              _StatusPill(active: connected),
            ],
          ),
          const SizedBox(height: 24),
          _VirtualWalletCard(
            connected: connected,
            shortAddress: shortAddress,
            solBalance: 0,
            usdBalance: null,
            lastUpdated: null,
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
                icon:
                    Icon(connected ? Icons.logout_rounded : Icons.link_rounded),
                label: Text(connected ? 'Desconectar' : 'Conectar wallet'),
              ),
              OutlinedButton.icon(
                onPressed: null,
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
                  color: Colors.white.withValues(alpha: 0.7),\n
            ],
          ),
        ],\n;
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
        onTap: null,
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
        onTap: state.isAnalyzingResults ? null : notifier.analyzeSimulations,
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
    final child = Container(
      width: width,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: LinearGradient(
          colors: blendedColors,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border:
            Border.all(color: blendedColors.last.withValues(alpha: 0.25)),
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
          Text(
            data.title,
            style: theme.textTheme.titleMedium?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w600,\n
          const SizedBox(height: 6),
          Text(
            data.subtitle,
            style: theme.textTheme.bodySmall?.copyWith(
              color: Colors.white.withValues(alpha: 0.85),\n
        ],\n;
    if (!enabled) return Opacity(opacity: 0.4, child: child);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(28),
        onTap: data.onTap,
        splashColor: Colors.white.withValues(alpha: 0.1),
        child: child,\n;
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
            subtitle: 'Define límites globales y por token',
          ),
          const SizedBox(height: 18),
          _BudgetProgressBar(
            progress: progress,
            availableLabel: '${available.toStringAsFixed(2)} SOL libres',
            deployedLabel: '${deployed.toStringAsFixed(2)} SOL usados',
          ),
          const SizedBox(height: 18),
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
                            (state.totalBudgetSol * percent).toDouble(),\n
            ],
          ),
        ],\n;
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
                label: 'MC mínima USD',
                value: state.minMarketCap,
                onChanged: notifier.updateMinMarketCap,
              ),
              _NumberField(
                label: 'MC máxima USD',
                value: state.maxMarketCap,
                onChanged: notifier.updateMaxMarketCap,
              ),
            ],
          ),
          _ResponsiveFieldRow(
            children: [
              _NumberField(
                label: 'Volumen 24h mínimo',
                value: state.minVolume24h,
                onChanged: notifier.updateMinVolume,
              ),
              _NumberField(
                label: 'Volumen 24h máximo',
                value: state.maxVolume24h,
                onChanged: notifier.updateMaxVolume,
              ),
            ],
          ),
        ],\n;
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
          _SliderTile(
            label: 'Stop loss',
            value: state.stopLossPercent.clamp(5, 90),
            min: 5,
            max: 90,
            suffix: '%',
            onChanged: notifier.updateStopLoss,
          ),
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
            subtitle: const Text(
              'Si está activo, el bot moverá las utilidades al presupuesto general antes de reinvertir.',\n
        ],\n;
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
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: AutoInvestExecutionMode.values
                .map((mode) => _ModeChip(
                      label: mode == AutoInvestExecutionMode.jupiter
                          ? 'Jupiter'
                          : 'PumpPortal',
                      description: mode == AutoInvestExecutionMode.jupiter
                          ? 'Tokens graduados'
                          : 'Bonding curve',
                      selected: state.executionMode == mode,
                      onTap: () => notifier.setExecutionMode(mode),
                    ))
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
              items: _poolOptions
                  .map((pool) => DropdownMenuItem(value: pool, child: Text(pool)))
                  .toList(),
              onChanged: (value) {
                if (value != null) notifier.updatePumpPool(value);
              },
            ),
          ],
        ],\n;
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
                      
                  style: theme.textTheme.bodySmall,
                ),
              ],\n
          Switch.adaptive(
            value: enabled,
            onChanged: state.walletAddress == null
                ? null
                : (value) => notifier.toggleEnabled(value),
          ),
        ],\n;
  }
}
import '../../../core/widgets/soft_surface.dart';







