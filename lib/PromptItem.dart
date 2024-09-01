class PromptItem {
  String name;
  String prompt;
  bool enableChapter;

  PromptItem(
      {required this.name, required this.prompt, this.enableChapter = false});

  Map<String, dynamic> toJson() => {
        'name': name,
        'prompt': prompt,
        'enableChapter': enableChapter,
      };

  factory PromptItem.fromJson(Map<String, dynamic> json) {
    return PromptItem(
      name: json['name'],
      prompt: json['prompt'],
      enableChapter: json['enableChapter'] ?? false,
    );
  }
}
