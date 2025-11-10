import 'dart:convert';

class FeaturedCoin {
  const FeaturedCoin({
    required this.mint,
    required this.name,
    required this.symbol,
    required this.imageUri,
    required this.marketCapSol,
    required this.usdMarketCap,
    required this.createdAt,
    required this.lastReplyAt,
    required this.replyCount,
    required this.isComplete,
    required this.isCurrentlyLive,
    required this.twitterUrl,
    required this.telegramUrl,
    required this.websiteUrl,
  });

  final String mint;
  final String name;
  final String symbol;
  final String imageUri;
  final double marketCapSol;
  final double usdMarketCap;
  final DateTime createdAt;
  final DateTime? lastReplyAt;
  final int replyCount;
  final bool isComplete;
  final bool isCurrentlyLive;
  final Uri? twitterUrl;
  final Uri? telegramUrl;
  final Uri? websiteUrl;

  static List<FeaturedCoin> listFromJson(String source) {
    final dynamic decoded = jsonDecode(source);
    if (decoded is! List) {
      throw const FormatException('Unexpected payload received from pump.fun');
    }
    return decoded
        .whereType<Map<String, dynamic>>()
        .map(FeaturedCoin.fromJson)
        .toList();
  }

  factory FeaturedCoin.fromJson(Map<String, dynamic> json) {
    DateTime? parseEpoch(dynamic value) {
      if (value == null) return null;
      if (value is int) {
        return DateTime.fromMillisecondsSinceEpoch(value, isUtc: true).toLocal();
      }
      if (value is double) {
        return DateTime.fromMillisecondsSinceEpoch(value.toInt(), isUtc: true)
            .toLocal();
      }
      return null;
    }

    Uri? parseUri(dynamic value) {
      if (value == null) return null;
      final str = value.toString().trim();
      if (str.isEmpty) return null;
      return Uri.tryParse(str);
    }

    double normalizeNum(dynamic value) {
      if (value == null) return 0;
      if (value is num) return value.toDouble();
      return double.tryParse(value.toString()) ?? 0;
    }

    return FeaturedCoin(
      mint: json['mint']?.toString() ?? '',
      name: json['name']?.toString() ?? 'Unknown',
      symbol: json['symbol']?.toString() ?? '',
      imageUri: json['image_uri']?.toString() ?? '',
      marketCapSol: normalizeNum(json['market_cap']),
      usdMarketCap: normalizeNum(json['usd_market_cap']),
      createdAt: parseEpoch(json['created_timestamp']) ?? DateTime.now(),
      lastReplyAt: parseEpoch(json['last_reply']),
      replyCount: (json['reply_count'] as num?)?.toInt() ?? 0,
      isComplete: json['complete'] as bool? ?? false,
      isCurrentlyLive: json['is_currently_live'] as bool? ?? false,
      twitterUrl: parseUri(json['twitter']),
      telegramUrl: parseUri(json['telegram']),
      websiteUrl: parseUri(json['website']),
    );
  }

  FeaturedCoin copyWith({
    double? marketCapSol,
    double? usdMarketCap,
  }) {
    return FeaturedCoin(
      mint: mint,
      name: name,
      symbol: symbol,
      imageUri: imageUri,
      marketCapSol: marketCapSol ?? this.marketCapSol,
      usdMarketCap: usdMarketCap ?? this.usdMarketCap,
      createdAt: createdAt,
      lastReplyAt: lastReplyAt,
      replyCount: replyCount,
      isComplete: isComplete,
      isCurrentlyLive: isCurrentlyLive,
      twitterUrl: twitterUrl,
      telegramUrl: telegramUrl,
      websiteUrl: websiteUrl,
    );
  }
}
