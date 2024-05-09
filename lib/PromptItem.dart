class PromptItem {
  String name;
  String prompt;

  PromptItem({required this.name, required this.prompt});

  Map<String, dynamic> toJson() => {
        'name': name,
        'prompt': prompt,
      };

  factory PromptItem.fromJson(Map<String, dynamic> json) {
    return PromptItem(
      name: json['name'],
      prompt: json['prompt'],
    );
  }
}
