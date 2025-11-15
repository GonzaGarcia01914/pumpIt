import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/widgets/soft_surface.dart';
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

    return SoftSurface(
      color: theme.colorScheme.surface,
      margin: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _CoinAvatar(symbol: coin.symbol, imageUri: coin.imageUri),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${coin.name} · ${coin.symbol}',
                      style: theme.textTheme.titleMedium,
                    ),
                    Text(
                      'Creado hace $ageText',
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              FilledButton.icon(
                onPressed: () =>
                    onLaunch(Uri.parse('https://pump.fun/${coin.mint}')),
                icon: const Icon(Icons.open_in_new),
                label: const Text('Ver'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _CoinStat(
                label: 'Market cap USD',
                value: _numberFormat.format(coin.usdMarketCap),
              ),
              _CoinStat(
                label: 'Market cap SOL',
                value: coin.marketCapSol.toStringAsFixed(1),
              ),
              _CoinStat(
                label: 'Replies',
                value: coin.replyCount.toString(),
                icon: Icons.chat_bubble_outline,
              ),
              if (coin.isCurrentlyLive)
                _CoinStat(
                  label: 'Estado',
                  value: 'Live',
                  icon: Icons.bolt,
                  accent: Colors.amber,
                ),
            ],
          ),
          const SizedBox(height: 12),
          Text(lastReplyText, style: theme.textTheme.bodySmall),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            children: [
              if (coin.twitterUrl != null)
                _SocialButton(
                  icon: Icons.share,
                  tooltip: 'Abrir Twitter',
                  onTap: () => _launch(coin.twitterUrl!),
                ),
              if (coin.telegramUrl != null)
                _SocialButton(
                  icon: Icons.send,
                  tooltip: 'Abrir Telegram',
                  onTap: () => _launch(coin.telegramUrl!),
                ),
              if (coin.websiteUrl != null)
                _SocialButton(
                  icon: Icons.language,
                  tooltip: 'Abrir sitio',
                  onTap: () => _launch(coin.websiteUrl!),
                ),
            ],
          ),
        ],
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

class _CoinAvatar extends StatelessWidget {
  const _CoinAvatar({required this.symbol, required this.imageUri});

  final String symbol;
  final String imageUri;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (imageUri.isNotEmpty) {
      return CircleAvatar(
        radius: 26,
        backgroundImage: NetworkImage(imageUri),
      );
    }
    final text = symbol.isEmpty
        ? '?'
        : symbol.substring(0, symbol.length > 2 ? 2 : symbol.length);
    return Container(
      width: 52,
      height: 52,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          colors: [
            theme.colorScheme.primary.withOpacity(0.4),
            theme.colorScheme.secondary.withOpacity(0.4),
          ],
        ),
      ),
      alignment: Alignment.center,
      child: Text(text, style: theme.textTheme.titleMedium),
    );
  }
}

class _CoinStat extends StatelessWidget {
  const _CoinStat({
    required this.label,
    required this.value,
    this.icon,
    this.accent,
  });

  final String label;
  final String value;
  final IconData? icon;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        color: Colors.white.withOpacity(0.05),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 16, color: accent ?? theme.colorScheme.primary),
            const SizedBox(width: 6),
          ],
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: theme.textTheme.labelSmall
                    ?.copyWith(color: Colors.white70),
              ),
              Text(
                value,
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

class _SocialButton extends StatelessWidget {
  const _SocialButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      icon: Icon(icon),
      onPressed: onTap,
    );
  }
}
