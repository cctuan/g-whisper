class RecordResult {
  int? id;
  String originalText;
  String processedText;
  final String timestamp;
  String promptText; // Added to store the prompt text itself

  RecordResult({
    this.id,
    required this.originalText,
    required this.processedText,
    required this.timestamp,
    this.promptText = '',
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'timestamp': timestamp,
        'originalText': originalText,
        'processedText': processedText,
        'promptText': promptText,
      };

  factory RecordResult.fromJson(Map<String, dynamic> json) => RecordResult(
        id: json['id'],
        timestamp: json['timestamp'],
        originalText: json['originalText'],
        processedText: json['processedText'],
        promptText: json['promptText'],
      );
}
