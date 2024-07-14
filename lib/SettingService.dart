import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import './PromptItem.dart';

typedef SettingChangeCallback = void Function();

class SettingsService {
  SettingChangeCallback? onSettingChanged;

  Future<Map<String, dynamic>> loadSettings() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    String openAiKey = prefs.getString('openai_key') ?? '';
    String ollamaUrl = prefs.getString('ollama_url') ?? '';
    String ollamaModel = prefs.getString('ollama_model') ?? '';
    String customLlmUrl = prefs.getString('custom_llm_url') ?? '';
    String customLlmModel = prefs.getString('custom_llm_model') ?? '';
    String openAiModel = prefs.getString('openai_model') ?? '';
    String localWhisperModel = prefs.getString('local_whisper_model') ?? 'base';
    bool useOpenAIWhisper = prefs.getBool('use_openai_whisper') ?? true;
    String llmChoice = prefs.getString('llm_choice') ??
        'openai'; // Default to using OpenAI LLM
    List<String> promptsJson = prefs.getStringList('prompts') ?? [];
    int? defaultPromptIndex = prefs.getInt('defaultPromptIndex');
    List<PromptItem> prompts = promptsJson
        .map((str) => PromptItem.fromJson(json.decode(str)))
        .toList();
    String huggingfaceToken = prefs.getString('huggingface_token') ?? '';
    String huggingfaceGguf = prefs.getString('huggingface_gguf') ?? '';
    String whisperPrompt = prefs.getString('whisper_prompt') ?? '';
    bool storeOriginalAudio = prefs.getBool('store_original_audio') ?? false;

    return {
      'openai_model': openAiModel,
      'openai_key': openAiKey,
      'ollama_url': ollamaUrl,
      'ollama_model': ollamaModel,
      'custom_llm_url': customLlmUrl,
      'custom_llm_model': customLlmModel,
      'use_openai_whisper': useOpenAIWhisper,
      'llm_choice': llmChoice,
      'local_whisper_model': localWhisperModel,
      'prompts': prompts,
      'defaultPromptIndex': defaultPromptIndex,
      'huggingface_token': huggingfaceToken,
      'huggingface_gguf': huggingfaceGguf,
      'whisper_prompt': whisperPrompt,
      'store_original_audio': storeOriginalAudio,
    };
  }

  Future<void> saveSettings(
    String openAiKey,
    String openAiModel,
    String ollamaUrl,
    String ollamaModel,
    bool useOpenAIWhisper,
    String llmChoice,
    String localWhisperModel,
    List<PromptItem> prompts,
    int? defaultPromptIndex,
    String customLlmUrl,
    String customLlmModel,
    String huggingfaceToken,
    String huggingfaceGguf,
    String whisperPrompt,
    bool? storeOriginalAudio,
  ) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString('openai_key', openAiKey);
    await prefs.setString('ollama_url', ollamaUrl);
    await prefs.setString('ollama_model', ollamaModel);
    await prefs.setString('custom_llm_url', customLlmUrl);
    await prefs.setString('custom_llm_model', customLlmModel);
    await prefs.setString('openai_model', openAiModel);
    await prefs.setBool('use_openai_whisper', useOpenAIWhisper);
    await prefs.setString('llm_choice', llmChoice);
    await prefs.setString('local_whisper_model', localWhisperModel);
    await prefs.setString('huggingface_token', huggingfaceToken);
    await prefs.setString('huggingface_gguf', huggingfaceGguf);
    await prefs.setString('whisper_prompt', whisperPrompt);
    await prefs.setBool('store_original_audio', storeOriginalAudio ?? false);
    List<String> promptsJson =
        prompts.map((prompt) => json.encode(prompt.toJson())).toList();
    await prefs.setStringList('prompts', promptsJson);
    if (defaultPromptIndex != null) {
      await prefs.setInt('defaultPromptIndex', defaultPromptIndex);
    }
    onSettingChanged?.call();
  }
}
