import 'dart:convert';

class RecordResult {
  int? id;
  String originalText;
  String processedText;
  String? whisperPrompt;
  final String timestamp;
  String promptText; // Added to store the prompt text itself
  String? filePath; // New field to store the original file path
  List<Map<String, String>> screenshots; // New field to store screenshots

  RecordResult({
    this.id,
    this.whisperPrompt = '',
    required this.originalText,
    required this.processedText,
    required this.timestamp,
    this.filePath = '',
    this.promptText = '',
    List<Map<String, String>>? screenshots, // Accept a nullable list
  }) : screenshots =
            screenshots ?? []; // Initialize screenshots as a mutable list

  Map<String, dynamic> toJson() => {
        'id': id,
        'whisperPrompt': whisperPrompt,
        'timestamp': timestamp,
        'originalText': originalText,
        'processedText': processedText,
        'promptText': promptText,
        'filePath': filePath, // Include the new field in JSON
        'screenshots':
            jsonEncode(screenshots), // Encode screenshots as JSON string
      };

  factory RecordResult.fromJson(Map<String, dynamic> json) {
    List<Map<String, String>> screenshots = [];
    if (json['screenshots'] != null) {
      try {
        screenshots =
            (jsonDecode(json['screenshots'] as String) as List<dynamic>)
                .map((e) => Map<String, String>.from(e as Map))
                .toList();
      } catch (e) {
        // Handle the error or provide a default value
        screenshots = [];
      }
    }
    return RecordResult(
      id: json['id'],
      whisperPrompt: json['whisperPrompt'] as String? ?? '',
      timestamp: json['timestamp'] as String,
      originalText: json['originalText'] as String,
      processedText: json['processedText'] as String,
      promptText: json['promptText'] as String? ?? '',
      filePath: json['filePath'] as String? ?? '',
      screenshots: screenshots,
    );
  }

  void addScreenshot(String path, String timestamp) {
    screenshots.add({'path': path, 'timestamp': timestamp});
  }
}
