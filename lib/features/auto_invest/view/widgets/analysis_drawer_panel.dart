import 'package:flutter/material.dart';

import '../../../../core/widgets/soft_surface.dart';

class AnalysisDrawerPanel extends StatelessWidget {
  const AnalysisDrawerPanel({
    super.key,
    required this.summary,
    required this.isLoading,
    required this.onAnalyze,
    this.collapsed = false,
    this.onToggle,
    this.showButton = true,
  });

  final String? summary;
  final bool isLoading;
  final VoidCallback onAnalyze;
  final bool collapsed;
  final VoidCallback? onToggle;
  final bool showButton;

  @override
  Widget build(BuildContext context) {
    final sections = _parseSummary(summary);
    final child = collapsed
        ? _CollapsedAnalysisCard(
            hasSummary: summary != null,
            onAnalyze: onAnalyze,
            onToggle: onToggle,
          )
        : _ExpandedAnalysisCard(
            sections: sections,
            isLoading: isLoading,
            showButton: showButton,
            onAnalyze: onAnalyze,
            summaryAvailable: summary != null,
            onToggle: onToggle,
          );

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 280),
      switchInCurve: Curves.easeOut,
      switchOutCurve: Curves.easeIn,
      child: child,
    );
  }
}

class _CollapsedAnalysisCard extends StatelessWidget {
  const _CollapsedAnalysisCard({
    required this.hasSummary,
    required this.onAnalyze,
    required this.onToggle,
  });

  final bool hasSummary;
  final VoidCallback onAnalyze;
  final VoidCallback? onToggle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SoftSurface(
      key: const ValueKey('analysis-collapsed'),
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
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('IA resultados', style: theme.textTheme.titleMedium),
                    Text(
                      hasSummary
                          ? 'Último análisis disponible.'
                          : 'Sin análisis aún.',
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Expandir panel',
                icon: const Icon(Icons.unfold_more),
                onPressed: onToggle,
              ),
            ],
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: onAnalyze,
            icon: const Icon(Icons.auto_graph),
            label: const Text('Analizar ahora'),
          ),
        ],
      ),
    );
  }
}

class _ExpandedAnalysisCard extends StatelessWidget {
  const _ExpandedAnalysisCard({
    required this.sections,
    required this.isLoading,
    required this.showButton,
    required this.onAnalyze,
    required this.summaryAvailable,
    required this.onToggle,
  });

  final List<_AnalysisSection> sections;
  final bool isLoading;
  final bool showButton;
  final VoidCallback onAnalyze;
  final bool summaryAvailable;
  final VoidCallback? onToggle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SoftSurface(
      key: const ValueKey('analysis-expanded'),
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
                  color: theme.colorScheme.primary.withValues(alpha: 0.2),
                ),
                child: const Icon(Icons.auto_awesome),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('IA resultados', style: theme.textTheme.titleMedium),
                    Text(
                      summaryAvailable
                          ? 'Último análisis listo.'
                          : 'Genera un análisis bajo demanda.',
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Colapsar panel',
                icon: const Icon(Icons.close_fullscreen),
                onPressed: onToggle,
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (showButton)
            FilledButton.icon(
              onPressed: isLoading ? null : onAnalyze,
              icon: isLoading
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.auto_graph),
              label: const Text('Analizar posiciones cerradas'),
            ),
          if (isLoading) ...[
            const SizedBox(height: 16),
            const LinearProgressIndicator(minHeight: 3),
          ],
          if (!summaryAvailable && !isLoading) ...[
            const SizedBox(height: 16),
            Text(
              'Genera un análisis cuando tengas posiciones cerradas.',
              style: theme.textTheme.bodyMedium,
            ),
          ],
          if (sections.isNotEmpty) ...[
            const SizedBox(height: 16),
            ...sections.map((section) => _SectionCard(section: section)),
          ],
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.section});

  final _AnalysisSection section;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final Color borderColor;
    final List<Color> gradient;
    switch (section.type) {
      case AnalysisType.positive:
        borderColor = Colors.greenAccent;
        gradient = const [Color(0xFF1B2F1F), Color(0xFF0F2414)];
        break;
      case AnalysisType.negative:
        borderColor = Colors.redAccent;
        gradient = const [Color(0xFF2F1B1B), Color(0xFF240F14)];
        break;
      case AnalysisType.opportunity:
        borderColor = theme.colorScheme.primary;
        gradient = const [Color(0xFF1B1F34), Color(0xFF1F1634)];
        break;
    }
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          colors: gradient,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(color: borderColor.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            section.title,
            style: theme.textTheme.titleSmall?.copyWith(color: borderColor),
          ),
          const SizedBox(height: 8),
          if (section.items.isEmpty)
            Text('- Sin observaciones', style: theme.textTheme.bodySmall)
          else
            ...section.items.map(
              (item) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Text('- $item', style: theme.textTheme.bodyMedium),
              ),
            ),
        ],
      ),
    );
  }
}

List<_AnalysisSection> _parseSummary(String? raw) {
  if (raw == null || raw.trim().isEmpty) return [];
  final lines = raw.split('\n');
  final sections = <_AnalysisSection>[];
  _AnalysisSection? current;
  for (final line in lines) {
    final trimmed = line.trim();
    if (trimmed.isEmpty) continue;
    final upper = trimmed.toUpperCase();
    if (upper.startsWith('POSITIVAS:')) {
      current = _AnalysisSection(
        title: 'Positivas',
        type: AnalysisType.positive,
        items: [],
      );
      sections.add(current);
      final rest = trimmed.substring('POSITIVAS:'.length).trim();
      if (rest.isNotEmpty) {
        current.items.add(rest);
      }
      continue;
    }
    if (upper.startsWith('NEGATIVAS:')) {
      current = _AnalysisSection(
        title: 'Negativas',
        type: AnalysisType.negative,
        items: [],
      );
      sections.add(current);
      final rest = trimmed.substring('NEGATIVAS:'.length).trim();
      if (rest.isNotEmpty) {
        current.items.add(rest);
      }
      continue;
    }
    if (upper.startsWith('OPORTUNIDADES:')) {
      current = _AnalysisSection(
        title: 'Oportunidades',
        type: AnalysisType.opportunity,
        items: [],
      );
      sections.add(current);
      final rest = trimmed.substring('OPORTUNIDADES:'.length).trim();
      if (rest.isNotEmpty) {
        current.items.add(rest);
      }
      continue;
    }
    current ??= _AnalysisSection(
      title: 'Notas',
      type: AnalysisType.opportunity,
      items: [],
    );
    if (!sections.contains(current)) {
      sections.add(current);
    }
    current.items.add(trimmed.replaceFirst(RegExp(r'^[--]\s*'), ''));
  }
  return sections;
}

class _AnalysisSection {
  _AnalysisSection({
    required this.title,
    required this.type,
    required this.items,
  });

  final String title;
  final AnalysisType type;
  final List<String> items;
}

enum AnalysisType { positive, negative, opportunity }
