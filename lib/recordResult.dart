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
    this.screenshots = const [], // Initialize screenshots as an empty list
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'whisperPrompt': whisperPrompt,
        'timestamp': timestamp,
        'originalText': originalText,
        'processedText': processedText,
        'promptText': promptText,
        'filePath': filePath, // Include the new field in JSON
        'screenshots': screenshots, // Include screenshots in JSON
      };

  factory RecordResult.fromJson(Map<String, dynamic> json) => RecordResult(
        id: json['id'],
        whisperPrompt: json['whisperPrompt'] as String?,
        timestamp: json['timestamp'],
        originalText: json['originalText'],
        processedText: json['processedText'],
        promptText: json['promptText'],
        filePath: json['filePath'] as String?, // Parse the new field from JSON
        screenshots:
            (json.containsKey('screenshots') && json['screenshots'] != null)
                ? (json['screenshots'] as List)
                    .map((e) => Map<String, String>.from(e))
                    .toList()
                : [], // Parse screenshots from JSON or provide default value
      );

  void addScreenshot(String path, String timestamp) {
    screenshots.add({'path': path, 'timestamp': timestamp});
  }
}
