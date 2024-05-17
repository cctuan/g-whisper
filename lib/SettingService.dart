import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import './PromptItem.dart';

class SettingsService {
  Future<Map<String, dynamic>> loadSettings() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    String openAiKey = prefs.getString('openai_key') ?? '';
    String ollamaUrl = prefs.getString('ollama_url') ?? '';
    String ollamaModel = prefs.getString('ollama_model') ?? '';
    String openAiModel = prefs.getString('openai_model') ?? '';
    String localWhisperModel = prefs.getString('local_whisper_model') ?? 'base';
    bool useOpenAIWhisper = prefs.getBool('use_openai_whisper') ??
        true; // Default to using OpenAI Whisper
    bool useOpenAILLM =
        prefs.getBool('use_openai_llm') ?? true; // Default to using OpenAI LLM
    List<String> promptsJson = prefs.getStringList('prompts') ?? [];
    int? defaultPromptIndex = prefs.getInt('defaultPromptIndex');
    List<PromptItem> prompts = promptsJson
        .map((str) => PromptItem.fromJson(json.decode(str)))
        .toList();

    return {
      'openai_model': openAiModel,
      'openai_key': openAiKey,
      'ollama_url': ollamaUrl,
      'ollama_model': ollamaModel,
      'use_openai_whisper': useOpenAIWhisper,
      'use_openai_llm': useOpenAILLM,
      'local_whisper_model': localWhisperModel,
      'prompts': prompts,
      'defaultPromptIndex': defaultPromptIndex,
    };
  }

  Future<void> saveSettings(
    String openAiKey,
    String openAiModel,
    String ollamaUrl,
    String ollamaModel,
    bool useOpenAIWhisper,
    bool useOpenAILLM,
    String localWhisperModel,
    List<PromptItem> prompts,
    int? defaultPromptIndex,
  ) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString('openai_key', openAiKey);
    await prefs.setString('ollama_url', ollamaUrl);
    await prefs.setString('ollama_model', ollamaModel);
    await prefs.setString('openai_model', openAiModel);
    await prefs.setBool('use_openai_whisper', useOpenAIWhisper);
    await prefs.setBool('use_openai_llm', useOpenAILLM);
    await prefs.setString('local_whisper_model', localWhisperModel);
    List<String> promptsJson =
        prompts.map((prompt) => json.encode(prompt.toJson())).toList();
    await prefs.setStringList('prompts', promptsJson);
    if (defaultPromptIndex != null) {
      await prefs.setInt('defaultPromptIndex', defaultPromptIndex);
    }
  }
}
