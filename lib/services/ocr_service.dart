import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

class OcrService {
  final _recognizer = TextRecognizer(script: TextRecognitionScript.latin);

  /// Returns the full recognised text, newline-joined across blocks and lines.
  Future<String> extractText(String imagePath) async {
    final result = await _recognizer.processImage(
      InputImage.fromFilePath(imagePath),
    );
    return result.text;
  }

  /// Must be called when the service is no longer needed to release the
  /// native ML Kit recogniser. Reusing a single instance across snips
  /// (rather than creating one per call) is intentional — it avoids the
  /// cold-start cost of loading the model each time.
  Future<void> dispose() => _recognizer.close();
}
