import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core/storage/shared_prefs_provider.dart';
import 'core/theme/app_theme.dart';
import 'features/auto_invest/controller/auto_invest_executor.dart';
import 'features/auto_invest/controller/auto_invest_notifier.dart';
import 'features/auto_invest/controller/position_monitor.dart';
import 'features/auto_invest/controller/sol_price_ticker.dart';
import 'features/auto_invest/models/position.dart';
import 'package:pump_it_baby/features/auto_invest/view/auto_invest_page.dart';
import 'features/auto_invest/view/results_page.dart';
import 'core/widgets/global_log_banner.dart';
import 'features/featured_coins/view/featured_coin_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  runApp(
    ProviderScope(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      child: const PumpItBabyApp(),
    ),
  );
}

class PumpItBabyApp extends StatelessWidget {
  const PumpItBabyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Pump It Baby',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.dark,
      theme: AppTheme.dark(),
      darkTheme: AppTheme.dark(),
      home: const HomeTabsPage(),
    );
  }
}

class HomeTabsPage extends ConsumerWidget {
  const HomeTabsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(autoInvestExecutorProvider);
    ref.watch(autoInvestMonitorProvider);
    ref.watch(solPriceTickerProvider);
    final autoInvestState = ref.watch(autoInvestProvider);
    return DefaultTabController(
      length: 3,
      child: Stack(
        children: [
          const _DashboardBackdrop(),
          Scaffold(
            backgroundColor: Colors.transparent,
            body: SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 18, 24, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _DashboardTopBar(
                      positions: autoInvestState.positions,
                      isPausedForFunds:
                          autoInvestState.isEnabled &&
                              autoInvestState.perCoinBudgetSol > 0 &&
                              autoInvestState.availableBudgetSol + 1e-6 <
                                  autoInvestState.perCoinBudgetSol,
                      availableBudget: autoInvestState.availableBudgetSol,
                      perCoinBudget: autoInvestState.perCoinBudgetSol,
                    ),
                    const SizedBox(height: 16),
                    Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(36),
                        gradient: LinearGradient(
                          colors: [
                            Colors.white.withValues(alpha: 0.05),
                            Colors.white.withValues(alpha: 0.02),
                          ],
                        ),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.06),
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: TabBar(
                          padding: const EdgeInsets.symmetric(horizontal: 6),
                          indicatorPadding: const EdgeInsets.symmetric(
                            vertical: 2,
                            horizontal: 4,
                          ),
                          labelPadding: EdgeInsets.zero,
                          splashFactory: NoSplash.splashFactory,
                          overlayColor:
                              WidgetStateProperty.all(Colors.transparent),
                          dividerColor: Colors.transparent,
                          tabs: const [
                            Tab(
                              child: _TabLabel(
                                icon: Icons.auto_awesome,
                                label: 'Featured bot',
                              ),
                            ),
                            Tab(
                              child: _TabLabel(
                                icon: Icons.sailing_outlined,
                                label: 'Auto invest',
                              ),
                            ),
                            Tab(
                              child: _TabLabel(
                                icon: Icons.leaderboard_outlined,
                                label: 'Resultados',
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Expanded(
                      child: TabBarView(
                        physics: BouncingScrollPhysics(),
                        children: [
                          FeaturedCoinTab(),
                          AutoInvestPage(),
                          SimulationResultsPage(),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          // Global logs overlay
          const GlobalLogBanner(),
        ],
      ),
    );
  }
}

class _DashboardBackdrop extends StatelessWidget {
  const _DashboardBackdrop();

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF03030D), Color(0xFF050611)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: IgnorePointer(
          child: Stack(
            children: [
              Positioned.fill(
                child: CustomPaint(
                  painter: _GridPainter(),
                ),
              ),
              Align(
                alignment: Alignment.topRight,
                child: Padding(
                  padding: const EdgeInsets.only(top: 80),
                  child: Transform.translate(
                    offset: const Offset(60, 0),
                    child: Container(
                      width: 260,
                      height: 260,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: RadialGradient(
                          colors: [
                            Color(0x334B6BFF),
                            Colors.transparent,
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              Align(
                alignment: Alignment.bottomLeft,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 20),
                  child: Transform.translate(
                    offset: const Offset(-40, 20),
                    child: Container(
                      width: 320,
                      height: 320,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: RadialGradient(
                          colors: [
                            Color(0x3329F1C3),
                            Colors.transparent,
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.02)
      ..strokeWidth = 1;
    const spacing = 90.0;
    for (double x = 0; x < size.width; x += spacing) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 0; y < size.height; y += spacing) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _DashboardTopBar extends StatelessWidget {
  const _DashboardTopBar({
    required this.positions,
    required this.isPausedForFunds,
    required this.availableBudget,
    required this.perCoinBudget,
  });

  final List<OpenPosition> positions;
  final bool isPausedForFunds;
  final double availableBudget;
  final double perCoinBudget;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (isPausedForFunds)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Text(
              'Bot pausado: presupuesto disponible '
              '${availableBudget.toStringAsFixed(3)} SOL < '
              '${perCoinBudget.toStringAsFixed(3)} SOL por token.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: const Color(0xFFFFB74D),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        _HoldingsStrip(positions: positions),
      ],
    );
  }
}

class _HoldingsStrip extends StatelessWidget {
  const _HoldingsStrip({required this.positions});

  final List<OpenPosition> positions;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final holdings = positions.take(10).toList();
    if (holdings.isEmpty) {
      return Text(
        'Holdings actuales: sin posiciones abiertas',
        style: theme.textTheme.bodyMedium,
      );
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (var i = 0; i < holdings.length; i++) ...[
            _HoldingPill(position: holdings[i]),
            if (i != holdings.length - 1) const SizedBox(width: 10),
          ],
        ],
      ),
    );
  }
}

class _HoldingPill extends StatelessWidget {
  const _HoldingPill({required this.position});

  final OpenPosition position;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fallback = position.mint.length >= 3
        ? position.mint.substring(0, 3)
        : position.mint;
    final symbol = (position.symbol.isNotEmpty ? position.symbol : fallback)
        .toUpperCase();
    final amount = position.currentValueSol ?? position.entrySol;
    final pnl = position.pnlPercent;
    final pnlText =
        pnl == null ? null : '${pnl >= 0 ? '+' : ''}${pnl.toStringAsFixed(1)}%';
    final pnlColor = pnl == null
        ? Colors.white70
        : pnl >= 0
            ? const Color(0xFF61E294)
            : const Color(0xFFFF6B6B);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        color: Colors.white.withValues(alpha: 0.05),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: theme.colorScheme.primary.withValues(alpha: 0.2),
            ),
            alignment: Alignment.center,
            child: Text(
              symbol.substring(0, symbol.length.clamp(1, 3)),
              style: theme.textTheme.labelLarge,
            ),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '$symbol · ${amount.toStringAsFixed(3)} SOL',
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (pnlText != null)
                Text(
                  pnlText,
                  style: theme.textTheme.labelSmall?.copyWith(color: pnlColor),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TabLabel extends StatelessWidget {
  const _TabLabel({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      height: 48,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withValues(alpha: 0.1),
            ),
            child: Icon(icon, size: 18),
          ),
          const SizedBox(width: 10),
          Text(
            label,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
