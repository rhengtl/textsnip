class SnipResult {
  final String text;
  final String imagePath;

  const SnipResult({required this.text, required this.imagePath});

  bool get hasText => text.trim().isNotEmpty;
}
