import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../models/featured_coin.dart';

final _numberFormat = NumberFormat.compactCurrency(
  decimalDigits: 0,
  symbol: '\$',
);

class FeaturedCoinTile extends StatelessWidget {
  const FeaturedCoinTile({
    super.key,
    required this.coin,
    required this.onLaunch,
  });

  final FeaturedCoin coin;
  final void Function(Uri url) onLaunch;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final age = DateTime.now().difference(coin.createdAt);
    final ageText = _describeDuration(age);
    final lastReplyText = coin.lastReplyAt == null
        ? 'Sin replies'
        : 'Ultimo reply hace ${_describeDuration(DateTime.now().difference(coin.lastReplyAt!))}';

    return Card(
      elevation: 0.6,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor:
                      theme.colorScheme.surfaceTint.withValues(alpha: 0.1),
                  backgroundImage:
                      coin.imageUri.isNotEmpty ? NetworkImage(coin.imageUri) : null,
                  child: coin.imageUri.isEmpty
                      ? Text(coin.symbol.isEmpty
                          ? '?'
                          : coin.symbol.substring(
                              0,
                              coin.symbol.length > 2 ? 2 : coin.symbol.length,
                            ))
                      : null,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${coin.name} - ${coin.symbol}',
                        style: theme.textTheme.titleMedium,
                      ),
                      Text(
                        'Creado hace $ageText',
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                FilledButton.tonalIcon(
                  onPressed: () =>
                      onLaunch(Uri.parse('https://pump.fun/${coin.mint}')),
                  icon: const Icon(Icons.open_in_new),
                  label: const Text('Ver'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                Chip(
                  label: Text('MC USD ${_numberFormat.format(coin.usdMarketCap)}'),
                ),
                Chip(
                  label:
                      Text('MC SOL ${coin.marketCapSol.toStringAsFixed(1)}'),
                ),
                Chip(
                  avatar: const Icon(Icons.chat_bubble_outline, size: 16),
                  label: Text('${coin.replyCount} replies'),
                ),
                if (coin.isCurrentlyLive)
                  Chip(
                    avatar:
                        const Icon(Icons.bolt, size: 16, color: Colors.amber),
                    label: const Text('Currently live'),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              lastReplyText,
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                if (coin.twitterUrl != null)
                  IconButton(
                    tooltip: 'Abrir Twitter',
                    onPressed: () => _launch(coin.twitterUrl!),
                    icon: const Icon(Icons.share),
                  ),
                if (coin.telegramUrl != null)
                  IconButton(
                    tooltip: 'Abrir Telegram',
                    onPressed: () => _launch(coin.telegramUrl!),
                    icon: const Icon(Icons.send),
                  ),
                if (coin.websiteUrl != null)
                  IconButton(
                    tooltip: 'Abrir sitio',
                    onPressed: () => _launch(coin.websiteUrl!),
                    icon: const Icon(Icons.language),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _launch(Uri url) async {
    if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
      onLaunch(url);
    }
  }
}

String _describeDuration(Duration duration) {
  if (duration.inMinutes < 1) return 'instantes';
  if (duration.inHours < 1) return '${duration.inMinutes} min';
  if (duration.inHours < 24) return '${duration.inHours} h';
  return '${duration.inDays} d';
}
