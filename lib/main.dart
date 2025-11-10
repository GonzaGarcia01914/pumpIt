import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'features/auto_invest/controller/auto_invest_executor.dart';
import 'features/auto_invest/view/auto_invest_page.dart';
import 'features/auto_invest/view/results_page.dart';
import 'features/featured_coins/view/featured_coin_page.dart';

void main() {
  runApp(const ProviderScope(child: PumpItBabyApp()));
}

class PumpItBabyApp extends StatelessWidget {
  const PumpItBabyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Pump It Baby',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.dark,
      darkTheme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorSchemeSeed: Colors.tealAccent,
      ),
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: Colors.teal,
      ),
      home: const HomeTabsPage(),
    );
  }
}

class HomeTabsPage extends ConsumerWidget {
  const HomeTabsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(autoInvestExecutorProvider);
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Pump It Baby'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Featured bot'),
              Tab(text: 'Auto invest'),
              Tab(text: 'Resultados'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            FeaturedCoinTab(),
            AutoInvestPage(),
            SimulationResultsPage(),
          ],
        ),
      ),
    );
  }
}
