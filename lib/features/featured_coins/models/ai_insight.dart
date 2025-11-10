class AiInsight {
  const AiInsight({
    required this.summary,
    required this.generatedAt,
    required this.usedGenerativeModel,
    this.provider,
  });

  final String summary;
  final DateTime generatedAt;
  final bool usedGenerativeModel;
  final String? provider;
}
