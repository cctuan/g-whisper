import 'package:flutter/material.dart';
import './SettingService.dart';
import './PromptItem.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({Key? key}) : super(key: key);

  static const String routeName = '/settings';
  @override
  _SettingsPageState createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final SettingsService settingsService = SettingsService();
  final TextEditingController openAiKeyController = TextEditingController();
  final TextEditingController ollamaUrlController = TextEditingController();
  final TextEditingController ollamaModelController = TextEditingController();
  final TextEditingController customLlmUrlController = TextEditingController();
  final TextEditingController customLlmModelController =
      TextEditingController();
  String openAiModel = 'gpt-3.5-turbo'; // Default model
  String localWhisperModel = 'base'; // Default local whisper model
  final TextEditingController promptController = TextEditingController();
  List<PromptItem> prompts = [];
  int? defaultPromptIndex;
  bool useOpenAIWhisper = true; // true for OpenAI, false for Local Whisper
  String llmChoice = 'openai'; // 'openai', 'ollama', 'custom'

  @override
  void initState() {
    super.initState();
    loadSettings();
  }

  void addNewPrompt() {
    setState(() {
      prompts.add(PromptItem(name: 'New Prompt', prompt: ''));
    });
  }

  void removePrompt(int index) {
    setState(() {
      prompts.removeAt(index);
    });
  }

  Future<void> loadSettings() async {
    var settings = await settingsService.loadSettings();
    setState(() {
      openAiModel = (settings['openai_model']?.isNotEmpty ?? false)
          ? settings['openai_model']
          : 'gpt-3.5-turbo';
      localWhisperModel = (settings['local_whisper_model']?.isNotEmpty ?? false)
          ? settings['local_whisper_model']
          : 'base';
      openAiKeyController.text = settings['openai_key'] ?? '';
      ollamaUrlController.text = settings['ollama_url'] ?? '';
      ollamaModelController.text = settings['ollama_model'] ?? '';
      customLlmUrlController.text = settings['custom_llm_url'] ?? '';
      customLlmModelController.text = settings['custom_llm_model'] ?? '';
      prompts = settings['prompts'];
      useOpenAIWhisper = settings['use_openai_whisper'] ?? false;
      llmChoice = settings['llm_choice'] ?? 'openai';
      defaultPromptIndex = settings['defaultPromptIndex'] ?? 0;
    });
  }

  Future<void> saveSettings() async {
    await settingsService.saveSettings(
        openAiKeyController.text,
        openAiModel,
        ollamaUrlController.text,
        ollamaModelController.text,
        useOpenAIWhisper,
        llmChoice,
        localWhisperModel,
        prompts,
        defaultPromptIndex,
        customLlmUrlController.text,
        customLlmModelController.text);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).primaryColor,
                foregroundColor: Colors.white,
              ),
              onPressed: () {
                if (openAiKeyController.text.isNotEmpty &&
                    prompts.isNotEmpty &&
                    prompts
                        .any((p) => p.name.isNotEmpty && p.prompt.isNotEmpty) &&
                    defaultPromptIndex != null &&
                    prompts.length > defaultPromptIndex!) {
                  saveSettings();
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                          'Please fill in all fields, add at least one prompt with name and content, and set a default prompt.'),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              },
              child: const Text('Save Settings'),
            ),
            const SizedBox(height: 20),
            Text(
              "STT Options",
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            ListTile(
              title: const Text("Use Local Whisper"),
              leading: Radio<bool>(
                value: false,
                groupValue: useOpenAIWhisper,
                onChanged: (bool? value) {
                  setState(() {
                    useOpenAIWhisper = value!;
                  });
                },
              ),
            ),
            if (!useOpenAIWhisper) ...[
              DropdownButton<String>(
                value: localWhisperModel,
                onChanged: (String? newValue) {
                  setState(() {
                    localWhisperModel = newValue!;
                  });
                },
                items: <String>['tiny', 'base', 'small', 'medium']
                    .map<DropdownMenuItem<String>>((String value) {
                  return DropdownMenuItem<String>(
                    value: value,
                    child: Text(value),
                  );
                }).toList(),
              ),
            ],
            ListTile(
              title: const Text("Use OpenAI Whisper"),
              leading: Radio<bool>(
                value: true,
                groupValue: useOpenAIWhisper,
                onChanged: (bool? value) {
                  setState(() {
                    useOpenAIWhisper = value!;
                  });
                },
              ),
            ),
            if (useOpenAIWhisper) ...[
              TextField(
                controller: openAiKeyController,
                decoration: InputDecoration(
                  labelText: 'OpenAI API Key',
                  helperText: 'Enter your OpenAI API Key here',
                ),
              ),
            ],
            const SizedBox(height: 20),
            Text(
              "LLM Options",
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            ListTile(
              title: const Text("Use OpenAI LLM"),
              leading: Radio<String>(
                value: 'openai',
                groupValue: llmChoice,
                onChanged: (String? value) {
                  setState(() {
                    llmChoice = value!;
                  });
                },
              ),
            ),
            if (llmChoice == 'openai') ...[
              TextField(
                controller: openAiKeyController,
                decoration: InputDecoration(
                  labelText: 'OpenAI API Key',
                  helperText: 'Enter your OpenAI API Key here',
                ),
              ),
              DropdownButton<String>(
                value: openAiModel,
                onChanged: (String? newValue) {
                  setState(() {
                    openAiModel = newValue!;
                  });
                },
                items: <String>['gpt-3.5-turbo', 'gpt-4-turbo', 'gpt-4o']
                    .map<DropdownMenuItem<String>>((String value) {
                  return DropdownMenuItem<String>(
                    value: value,
                    child: Text(value),
                  );
                }).toList(),
              ),
            ],
            ListTile(
              title: const Text("Use Ollama"),
              leading: Radio<String>(
                value: 'ollama',
                groupValue: llmChoice,
                onChanged: (String? value) {
                  setState(() {
                    llmChoice = value!;
                  });
                },
              ),
            ),
            if (llmChoice == 'ollama') ...[
              TextField(
                controller: ollamaUrlController,
                decoration: InputDecoration(
                  labelText: 'Ollama URL',
                  helperText: 'Enter Ollama Service URL here',
                ),
              ),
              TextField(
                controller: ollamaModelController,
                decoration: InputDecoration(
                  labelText: 'Ollama Model',
                  helperText: 'Enter the model identifier for Ollama',
                ),
              ),
            ],
            ListTile(
              title: const Text("Use Custom LLM"),
              leading: Radio<String>(
                value: 'custom',
                groupValue: llmChoice,
                onChanged: (String? value) {
                  setState(() {
                    llmChoice = value!;
                  });
                },
              ),
            ),
            if (llmChoice == 'custom') ...[
              TextField(
                controller: customLlmUrlController,
                decoration: InputDecoration(
                  labelText: 'Custom LLM URL',
                  helperText: 'Enter Custom LLM Service URL here',
                ),
              ),
              TextField(
                controller: customLlmModelController,
                decoration: InputDecoration(
                  labelText: 'Custom LLM Model',
                  helperText: 'Enter the model identifier for Custom LLM',
                ),
              ),
            ],
            const SizedBox(height: 10),
            ListView.builder(
              shrinkWrap: true,
              physics: NeverScrollableScrollPhysics(),
              itemCount: prompts.length,
              itemBuilder: (context, index) {
                return ListTile(
                  trailing: IconButton(
                    icon: Icon(Icons.delete),
                    onPressed: () => removePrompt(index),
                  ),
                  title: TextField(
                    controller:
                        TextEditingController(text: prompts[index].name),
                    decoration: InputDecoration(labelText: 'Name'),
                    onChanged: (value) {
                      prompts[index].name = value;
                    },
                  ),
                  subtitle: TextField(
                    controller:
                        TextEditingController(text: prompts[index].prompt),
                    decoration: InputDecoration(labelText: 'Prompt'),
                    onChanged: (value) {
                      prompts[index].prompt = value;
                    },
                    maxLines: null,
                    keyboardType: TextInputType.multiline,
                  ),
                  leading: Radio<int>(
                    value: index,
                    groupValue: defaultPromptIndex,
                    onChanged: (int? value) {
                      setState(() {
                        defaultPromptIndex = value;
                      });
                    },
                  ),
                );
              },
            ),
            ElevatedButton(
              onPressed: addNewPrompt,
              child: Text('Add New Prompt'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    openAiKeyController.dispose();
    ollamaUrlController.dispose();
    ollamaModelController.dispose();
    customLlmUrlController.dispose();
    customLlmModelController.dispose();
    promptController.dispose();
    super.dispose();
  }
}

void main() {
  runApp(MaterialApp(
    home: SettingsPage(),
  ));
}
