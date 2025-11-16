import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../log/global_log.dart';

class GlobalLogBanner extends ConsumerWidget {
  const GlobalLogBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final log = ref.watch(globalLogProvider);
    final theme = Theme.of(context);
    final color = switch (log.level) {
      AppLogLevel.error => const Color(0xFFFF6B6B),
      AppLogLevel.success => const Color(0xFF61E294),
      AppLogLevel.neutral => Colors.white,
    };
    final bg = Colors.black.withValues(alpha: 0.7);
    final border = color.withValues(alpha: 0.7);

    return IgnorePointer(
      ignoring: !log.visible,
      child: AnimatedSlide(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
        offset: log.visible ? Offset.zero : const Offset(0, 0.25),
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 220),
          opacity: log.visible ? 1 : 0,
          child: Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 18),
              child: Container(
                constraints: const BoxConstraints(maxWidth: 1000),
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: bg,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: border, width: 1.2),
                  boxShadow: [
                    BoxShadow(
                      color: border.withValues(alpha: 0.3),
                      blurRadius: 16,
                      spreadRadius: 0,
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Icon(
                      switch (log.level) {
                        AppLogLevel.error => Icons.error_outline,
                        AppLogLevel.success => Icons.check_circle_outline,
                        AppLogLevel.neutral => Icons.info_outline,
                      },
                      color: color,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        log.message ?? '',
                        style: theme.textTheme.bodyMedium,
                      ),
                    ),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      onPressed: () =>
                          ref.read(globalLogProvider.notifier).hide(),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

