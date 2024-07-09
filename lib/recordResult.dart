class RecordResult {
  int? id;
  String originalText;
  String processedText;
  String? whisperPrompt;
  final String timestamp;
  String promptText; // Added to store the prompt text itself
  String? filePath; // New field to store the original file path

  RecordResult({
    this.id,
    this.whisperPrompt = '',
    required this.originalText,
    required this.processedText,
    required this.timestamp,
    this.filePath = '',
    this.promptText = '',
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'whisperPrompt': whisperPrompt,
        'timestamp': timestamp,
        'originalText': originalText,
        'processedText': processedText,
        'promptText': promptText,
        'filePath': filePath, // Include the new field in JSON
      };

  factory RecordResult.fromJson(Map<String, dynamic> json) => RecordResult(
        id: json['id'],
        whisperPrompt: json['whisperPrompt'] as String?,
        timestamp: json['timestamp'],
        originalText: json['originalText'],
        processedText: json['processedText'],
        promptText: json['promptText'],
        filePath: json['filePath'] as String?, // Parse the new field from JSON
      );
}
