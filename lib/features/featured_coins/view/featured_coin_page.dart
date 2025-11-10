import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../controller/featured_coin_notifier.dart';
import '../models/ai_insight.dart';
import 'widgets/featured_coin_tile.dart';

final _compactUsd = NumberFormat.compactCurrency(
  symbol: '\$',
  decimalDigits: 0,
);

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
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Filtrando MC USD >= ${_compactUsd.format(state.minUsdMarketCap)}',
                        style: theme.textTheme.bodyMedium,
                      ),
                      if (state.lastUpdated != null)
                        Text(
                          'Actualizado ${DateFormat.Hms().format(state.lastUpdated!)}',
                          style: theme.textTheme.bodySmall,
                        ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Actualizar ahora',
                  onPressed: state.isFetching ? null : () => notifier.refresh(),
                  icon: state.isFetching
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.refresh),
                ),
              ],
            ),
            if (state.errorMessage != null) ...[
              const SizedBox(height: 12),
              MaterialBanner(
                backgroundColor: theme.colorScheme.errorContainer,
                content: Text(
                  'Ups, ${state.errorMessage}',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onErrorContainer,
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => notifier.refresh(),
                    child: const Text('Reintentar'),
                  )
                ],
              ),
            ],
            const SizedBox(height: 12),
            _FiltersPanel(state: state, notifier: notifier),
            const SizedBox(height: 16),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final insightSection = _InsightPanel(
                    insight: state.insight,
                    isGenerating: state.isInsightLoading,
                    usedAi: state.insight?.usedGenerativeModel ??
                        notifier.hasGenerativeAi,
                  );

                  final listSection = _CoinList(
                    state: state,
                    onLaunchFallback: (uri) => ScaffoldMessenger.of(context)
                        .showSnackBar(
                      SnackBar(
                        content: Text('No pude abrir $uri'),
                      ),
                    ),
                  );

                  if (constraints.maxWidth < 900) {
                    return Column(
                      children: [
                        SizedBox(height: 320, child: insightSection),
                        const SizedBox(height: 16),
                        Expanded(child: listSection),
                      ],
                    );
                  } else {
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(flex: 5, child: listSection),
                        const SizedBox(width: 20),
                        Expanded(
                          flex: 3,
                          child: SizedBox(
                            height: constraints.maxHeight,
                            child: insightSection,
                          ),
                        ),
                      ],
                    );
                  }
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
  const _CoinList({
    required this.state,
    required this.onLaunchFallback,
  });

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
    _mcController =
        TextEditingController(text: widget.state.minUsdMarketCap.toString());
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

    return Card(
      elevation: 0.6,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Wrap(
          spacing: 16,
          runSpacing: 12,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SizedBox(
              width: 220,
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
              width: 220,
              child: TextField(
                controller: _volumeController,
                decoration: const InputDecoration(
                  labelText: 'Volumen 24h minimo',
                  prefixText: '\$',
                ),
                keyboardType: TextInputType.number,
              ),
            ),
            DropdownButton<FeaturedSortOption>(
              value: _sortOption,
              onChanged: (value) {
                setState(() {
                  _sortOption = value ?? FeaturedSortOption.highestCap;
                });
              },
              items: FeaturedSortOption.values
                  .map(
                    (option) => DropdownMenuItem(
                      value: option,
                      child: Text(_labelForOption(option)),
                    ),
                  )
                  .toList(),
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
            ElevatedButton.icon(
              onPressed: _applyFilters,
              icon: const Icon(Icons.check),
              label: const Text('Aplicar filtros'),
            ),
            Text(
              'Edita los valores y presiona Aplicar para refrescar.',
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
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
  });

  final AiInsight? insight;
  final bool isGenerating;
  final bool usedAi;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textTheme = theme.textTheme;

    return Card(
      elevation: 1.5,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.auto_awesome,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  'IA market intel',
                  style: textTheme.titleMedium,
                ),
                const Spacer(),
                if (insight != null)
                  Text(
                    DateFormat.Hm().format(insight!.generatedAt),
                    style: textTheme.bodySmall,
                  ),
              ],
            ),
            const SizedBox(height: 12),
            if (isGenerating)
              const LinearProgressIndicator(minHeight: 3),
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
                avatar: Icon(
                  usedAi ? Icons.memory : Icons.rule,
                  size: 16,
                ),
                label: Text(
                  usedAi
                      ? 'IA generativa conectada'
                      : 'Modo heuristico (sin API key)',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
