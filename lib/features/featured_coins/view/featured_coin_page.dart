import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/widgets/soft_surface.dart';
import '../controller/featured_coin_notifier.dart';
import '../models/ai_insight.dart';
import 'widgets/featured_coin_tile.dart';

final _compactUsd = NumberFormat.compactCurrency(
  symbol: '\$',
  decimalDigits: 0,
);

class _FeaturedHeader extends StatelessWidget {
  const _FeaturedHeader({required this.state});

  final FeaturedCoinState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final lastUpdated = state.lastUpdated == null
        ? 'Pendiente'
        : DateFormat.Hms().format(state.lastUpdated!);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Featured memecoins', style: theme.textTheme.headlineSmall),
        const SizedBox(height: 6),
        Text(
          'Explora memecoins con actividad on-chain destacada y filtros dinámicos.',
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 8,
          children: [
            _MetricBadge(
              label: 'Listado',
              value: '${state.coins.length}',
            ),
            _MetricBadge(
              label: 'Min MC',
              value: '${_compactUsd.format(state.minUsdMarketCap)}+',
            ),
            _MetricBadge(
              label: 'Última sync',
              value: lastUpdated,
            ),
          ],
        ),
      ],
    );
  }
}

class _MetricBadge extends StatelessWidget {
  const _MetricBadge({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(30),
        color: Colors.white.withValues(alpha: 0.04),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            value,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: theme.textTheme.bodySmall
                ?.copyWith(color: Colors.white70),
          ),
        ],
      ),
    );
  }
}

class FeaturedCoinTab extends ConsumerWidget {
  const FeaturedCoinTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(featuredCoinProvider);
    final notifier = ref.read(featuredCoinProvider.notifier);
    final theme = Theme.of(context);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _FeaturedHeader(state: state),
            const SizedBox(height: 16),
            SoftSurface(
              padding: const EdgeInsets.all(20),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Filtrando MC USD >= ${_compactUsd.format(state.minUsdMarketCap)}',
                          style: theme.textTheme.bodyMedium,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Volumen mínimo ${_compactUsd.format(state.minVolume24h)}',
                          style: theme.textTheme.bodySmall,
                        ),
                        if (state.lastUpdated != null) ...[
                          const SizedBox(height: 4),
                          Text(
                            'Actualizado ${DateFormat.Hms().format(state.lastUpdated!)}',
                            style: theme.textTheme.bodySmall,
                          ),
                        ],
                      ],
                    ),
                  ),
                  FilledButton.icon(
                    onPressed:
                        state.isFetching ? null : () => notifier.refresh(),
                    icon: state.isFetching
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.refresh),
                    label: Text(state.isFetching ? 'Actualizando...' : 'Refrescar'),
                  ),
                ],
              ),
            ),
            if (state.errorMessage != null) ...[
              const SizedBox(height: 12),
              SoftSurface(
                color: theme.colorScheme.surface,
                gradient: LinearGradient(
                  colors: [
                    theme.colorScheme.error.withValues(alpha: 0.2),
                    theme.colorScheme.error.withValues(alpha: 0.05),
                  ],
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Ups, ${state.errorMessage}',
                        style: theme.textTheme.bodyMedium,
                      ),
                    ),
                    TextButton(
                      onPressed: () => notifier.refresh(),
                      child: const Text('Reintentar'),
                    ),
                  ],
                ),
              ),
            ],
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final filtersPanel = _FiltersPanel(
                    state: state,
                    notifier: notifier,
                  );
                  final insightSection = _InsightPanel(
                    insight: state.insight,
                    isGenerating: state.isInsightLoading,
                    usedAi:
                        state.insight?.usedGenerativeModel ??
                        notifier.hasGenerativeAi,
                    onGenerate: notifier.generateInsight,
                    canGenerate: state.coins.isNotEmpty,
                  );

                  final listSection = _CoinList(
                    state: state,
                    onLaunchFallback: (uri) =>
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('No pude abrir $uri')),
                        ),
                  );

                  if (constraints.maxWidth < 1100) {
                    return Column(
                      children: [
                        filtersPanel,
                        const SizedBox(height: 16),
                        SizedBox(height: 320, child: insightSection),
                        const SizedBox(height: 16),
                        Expanded(child: listSection),
                      ],
                    );
                  }

                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(flex: 5, child: listSection),
                      const SizedBox(width: 20),
                      Expanded(
                        flex: 3,
                        child: SingleChildScrollView(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              filtersPanel,
                              const SizedBox(height: 16),
                              SizedBox(height: 360, child: insightSection),
                            ],
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CoinList extends StatelessWidget {
  const _CoinList({required this.state, required this.onLaunchFallback});

  final FeaturedCoinState state;
  final void Function(Uri uri) onLaunchFallback;

  @override
  Widget build(BuildContext context) {
    if (state.isFetching && state.coins.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (state.coins.isEmpty) {
      return const Center(
        child: Text('Aun no hay memecoins en featured con ese market cap.'),
      );
    }

    return ListView.separated(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(0, 12, 0, 32),
      itemBuilder: (context, index) => FeaturedCoinTile(
        coin: state.coins[index],
        onLaunch: onLaunchFallback,
      ),
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemCount: state.coins.length,
    );
  }
}

class _FiltersPanel extends StatefulWidget {
  const _FiltersPanel({required this.state, required this.notifier});

  final FeaturedCoinState state;
  final FeaturedCoinNotifier notifier;

  @override
  State<_FiltersPanel> createState() => _FiltersPanelState();
}

class _FiltersPanelState extends State<_FiltersPanel> {
  late final TextEditingController _mcController;
  late final TextEditingController _volumeController;
  DateTime? _selectedDate;
  FeaturedSortOption? _sortOption;

  @override
  void initState() {
    super.initState();
    _mcController = TextEditingController(
      text: widget.state.minUsdMarketCap.toString(),
    );
    _volumeController = TextEditingController(
      text: widget.state.minVolume24h.toStringAsFixed(0),
    );
    _selectedDate = widget.state.createdAfter;
    _sortOption = widget.state.sortOption;
  }

  @override
  void didUpdateWidget(covariant _FiltersPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.state.minUsdMarketCap != oldWidget.state.minUsdMarketCap) {
      _mcController.text = widget.state.minUsdMarketCap.toString();
    }
    if (widget.state.minVolume24h != oldWidget.state.minVolume24h) {
      _volumeController.text = widget.state.minVolume24h.toStringAsFixed(0);
    }
    if (widget.state.createdAfter != oldWidget.state.createdAfter) {
      _selectedDate = widget.state.createdAfter;
    }
    if (widget.state.sortOption != oldWidget.state.sortOption) {
      _sortOption = widget.state.sortOption;
    }
  }

  @override
  void dispose() {
    _mcController.dispose();
    _volumeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dateLabel = _selectedDate == null
        ? 'Cualquier fecha'
        : DateFormat.yMMMd().format(_selectedDate!);

    return SoftSurface(
      color: Theme.of(context).colorScheme.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Filtros rapidos', style: theme.textTheme.titleMedium),
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, constraints) {
              final isCompact = constraints.maxWidth < 700;
              final fieldWidth = isCompact ? double.infinity : 240.0;
              return Wrap(
                spacing: 16,
                runSpacing: 16,
                children: [
                  SizedBox(
                    width: fieldWidth,
                    child: TextField(
                      controller: _mcController,
                      decoration: const InputDecoration(
                        labelText: 'Market cap USD minimo',
                        prefixText: '\$',
                      ),
                      keyboardType: TextInputType.number,
                    ),
                  ),
                  SizedBox(
                    width: fieldWidth,
                    child: TextField(
                      controller: _volumeController,
                      decoration: const InputDecoration(
                        labelText: 'Volumen 24h minimo',
                        prefixText: '\$',
                      ),
                      keyboardType: TextInputType.number,
                    ),
                  ),
                  SizedBox(
                    width: fieldWidth,
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: FeaturedSortOption.values
                          .map(
                            (option) => ChoiceChip(
                              selected: _sortOption == option,
                              label: Text(_labelForOption(option)),
                              onSelected: (_) {
                                setState(() {
                                  _sortOption = option;
                                });
                              },
                            ),
                          )
                          .toList(),
                    ),
                  ),
                  Wrap(
                    spacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      OutlinedButton.icon(
                        icon: const Icon(Icons.today),
                        label: Text('Creacion desde: $dateLabel'),
                        onPressed: () => _pickDate(context),
                      ),
                      if (_selectedDate != null)
                        TextButton(
                          onPressed: () => setState(() {
                            _selectedDate = null;
                          }),
                          child: const Text('Limpiar fecha'),
                        ),
                    ],
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              FilledButton.icon(
                onPressed: _applyFilters,
                icon: const Icon(Icons.filter_alt),
                label: const Text('Aplicar filtros'),
              ),
              const SizedBox(width: 12),
              Text(
                'Edita los valores y presiona Aplicar para refrescar.',
                style: theme.textTheme.bodySmall,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _pickDate(BuildContext context) async {
    final now = DateTime.now();
    final initial = _selectedDate ?? now.subtract(const Duration(days: 1));
    final picked = await showDatePicker(
      context: context,
      firstDate: now.subtract(const Duration(days: 7)),
      lastDate: now,
      initialDate: initial,
    );
    if (picked != null) {
      setState(() {
        _selectedDate = DateTime(picked.year, picked.month, picked.day);
      });
    }
  }

  void _applyFilters() {
    final parsedCap =
        int.tryParse(_mcController.text) ?? widget.state.minUsdMarketCap;
    final parsedVolume =
        double.tryParse(_volumeController.text) ?? widget.state.minVolume24h;

    widget.notifier.applyFilters(
      minMarketCap: parsedCap,
      minVolume: parsedVolume,
      createdAfter: _selectedDate,
      sortOption: _sortOption,
    );
    FocusScope.of(context).unfocus();
  }
}

String _labelForOption(FeaturedSortOption option) {
  switch (option) {
    case FeaturedSortOption.highestCap:
      return 'Mayor MC';
    case FeaturedSortOption.newest:
      return 'Recientes';
    case FeaturedSortOption.mostReplies:
      return 'Mas replies';
  }
}

class _InsightPanel extends StatelessWidget {
  const _InsightPanel({
    required this.insight,
    required this.isGenerating,
    required this.usedAi,
    required this.onGenerate,
    required this.canGenerate,
  });

  final AiInsight? insight;
  final bool isGenerating;
  final bool usedAi;
  final Future<void> Function()? onGenerate;
  final bool canGenerate;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textTheme = theme.textTheme;

    return SoftSurface(
      color: Theme.of(context).colorScheme.tertiary,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: theme.colorScheme.primary.withValues(alpha: 0.2),
                ),
                child: const Icon(Icons.auto_awesome),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('IA market intel', style: textTheme.titleMedium),
                    if (insight != null)
                      Text(
                        'Generado ${DateFormat.Hm().format(insight!.generatedAt)}',
                        style: textTheme.bodySmall,
                      ),
                  ],
                ),
              ),
              FilledButton.tonalIcon(
                onPressed: isGenerating || onGenerate == null || !canGenerate
                    ? null
                    : () => onGenerate!(),
                icon: isGenerating
                    ? const SizedBox(
                        width: 12,
                        height: 12,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.auto_graph, size: 16),
                label: Text(isGenerating ? 'Generando...' : 'Refrescar'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (isGenerating) const LinearProgressIndicator(minHeight: 3),
          const SizedBox(height: 12),
          Expanded(
            child: SingleChildScrollView(
              child: Text(
                insight?.summary ??
                    'Aguardando datos para generar la primera lectura...',
                style: textTheme.bodyLarge,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.bottomLeft,
            child: Chip(
              avatar: Icon(usedAi ? Icons.memory : Icons.rule, size: 16),
              label: Text(
                usedAi
                    ? 'IA generativa conectada'
                    : 'Modo heuristico (sin API key)',
              ),
            ),
          ),
        ],
      ),
    );
  }
}
