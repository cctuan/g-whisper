import 'package:flutter/material.dart';
import './SettingService.dart';
import './PromptItem.dart';
import './settingSidebar.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({Key? key}) : super(key: key);

  static const String routeName = '/settings';
  @override
  _SettingsPageState createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  String selectedView = 'General'; // Track the selected view
  final SettingsService settingsService = SettingsService();
  final TextEditingController openAiKeyController = TextEditingController();
  final TextEditingController ollamaUrlController = TextEditingController();
  final TextEditingController ollamaModelController = TextEditingController();
  final TextEditingController customLlmUrlController = TextEditingController();
  final TextEditingController customLlmModelController =
      TextEditingController();
  final TextEditingController huggingfaceTokenController =
      TextEditingController();
  final TextEditingController huggingfaceGgufController =
      TextEditingController();
  final TextEditingController whisperPromptController = TextEditingController();
  final TextEditingController openaiAudioBaseUrlController =
      TextEditingController();
  final TextEditingController openaiCompletionBaseUrlController =
      TextEditingController();
  String openAiModel = 'gpt-4o-mini'; // Default model
  String localWhisperModel = 'base'; // Default local whisper model
  final TextEditingController promptController = TextEditingController();
  List<PromptItem> prompts = [];
  int? defaultPromptIndex;
  bool useOpenAIWhisper = true; // true for OpenAI, false for Local Whisper
  bool storeOriginalAudio = false;
  String llmChoice = 'openai'; // 'openai', 'ollama', 'custom', 'llama_cpp'

  final TextEditingController wikiApiTokenController = TextEditingController();
  final TextEditingController wikiPageIdController = TextEditingController();
  final TextEditingController spaceIdController = TextEditingController();

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
          : 'gpt-4o-mini';
      localWhisperModel = (settings['local_whisper_model']?.isNotEmpty ?? false)
          ? settings['local_whisper_model']
          : 'base';
      openAiKeyController.text = settings['openai_key'] ?? '';
      ollamaUrlController.text = settings['ollama_url'] ?? '';
      ollamaModelController.text = settings['ollama_model'] ?? '';
      customLlmUrlController.text = settings['custom_llm_url'] ?? '';
      customLlmModelController.text = settings['custom_llm_model'] ?? '';
      huggingfaceTokenController.text = settings['huggingface_token'] ?? '';
      huggingfaceGgufController.text = settings['huggingface_gguf'] ?? '';
      whisperPromptController.text = settings['whisper_prompt'] ?? '';
      openaiAudioBaseUrlController.text =
          settings['openai_audio_base_url'] ?? '';
      openaiCompletionBaseUrlController.text =
          settings['openai_completion_base_url'] ?? '';
      prompts = settings['prompts'];
      useOpenAIWhisper = settings['use_openai_whisper'] ?? false;
      llmChoice = settings['llm_choice'] ?? 'openai';
      defaultPromptIndex = settings['defaultPromptIndex'] ?? 0;
      storeOriginalAudio = settings['store_original_audio'] ?? false;
      wikiApiTokenController.text = settings['wiki_api_token'] ?? '';
      wikiPageIdController.text = settings['wiki_page_id'] ?? '';
      spaceIdController.text = settings['space_id'] ?? '';
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
      customLlmModelController.text,
      huggingfaceTokenController.text,
      huggingfaceGgufController.text,
      whisperPromptController.text,
      storeOriginalAudio,
      openaiCompletionBaseUrlController.text,
      openaiAudioBaseUrlController.text,
      wikiApiTokenController.text,
      wikiPageIdController.text,
      spaceIdController.text,
    );
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        actions: [
          TextButton(
            child: const Text('Save'),
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
          ),
        ],
      ),
      body: Row(
        children: [
          Sidebar(
            onItemSelected: (String view) {
              setState(() {
                selectedView = view; // Update the selected view
              });
            },
          ),
          Expanded(
            child: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(20.0),
                child: _buildSelectedView(),
              ),
            ),
          )
        ],
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
    huggingfaceTokenController.dispose();
    huggingfaceGgufController.dispose();
    whisperPromptController.dispose();
    promptController.dispose();
    wikiApiTokenController.dispose();
    wikiPageIdController.dispose();
    spaceIdController.dispose();
    super.dispose();
  }

  Widget _buildSelectedView() {
    switch (selectedView) {
      case 'STT Options':
        return _buildSttOptionsView();
      case 'LLM Options':
        return _buildLlmOptionsView();
      case 'File Settings':
        return _buildFileSettingsView();
      case 'Wiki Settings':
        return _buildWikiSettingsView();
      case 'Prompt Settings':
        return _buildPromptSettingsView();
      default:
        return _buildGeneralView();
    }
  }

  Widget _buildSttOptionsView() {
    return Center(
        child: Column(children: [
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
          obscureText: true,
          controller: openAiKeyController,
          decoration: InputDecoration(
            labelText: 'OpenAI API Key',
            helperText: 'Enter your OpenAI API Key here',
          ),
        ),
        TextField(
          controller: openaiAudioBaseUrlController,
          decoration: InputDecoration(
            labelText: 'OpenAI Audio Base URL (optional)',
            helperText: 'Enter your OpenAI Audio Base URL here',
          ),
        )
      ]
    ]));
  }

  Widget _buildLlmOptionsView() {
    return Center(
        child: Column(
      children: [
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
            obscureText: true,
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
            items: <String>['gpt-4-turbo', 'gpt-4o', 'gpt-4o-mini']
                .map<DropdownMenuItem<String>>((String value) {
              return DropdownMenuItem<String>(
                value: value,
                child: Text(value),
              );
            }).toList(),
          ),
          TextField(
            controller: openaiCompletionBaseUrlController,
            decoration: InputDecoration(
              labelText: 'OpenAI Completion Base URL (optional)',
              helperText: 'Enter your OpenAI Completion Base URL here',
            ),
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
        ListTile(
          title: const Text("Run LlamaCpp"),
          leading: Radio<String>(
            value: 'llama_cpp',
            groupValue: llmChoice,
            onChanged: (String? value) {
              setState(() {
                llmChoice = value!;
              });
            },
          ),
        ),
        if (llmChoice == 'llama_cpp') ...[
          TextField(
            controller: huggingfaceTokenController,
            decoration: InputDecoration(
              labelText: 'Huggingface Token',
              helperText: 'Enter your Huggingface Token here',
            ),
          ),
          TextField(
            controller: huggingfaceGgufController,
            decoration: InputDecoration(
              labelText: 'Huggingface GGUF',
              helperText: 'Enter the GGUF identifier here',
            ),
          ),
        ]
      ],
    ));
  }

  Widget _buildFileSettingsView() {
    return Center(
        child: Column(
      children: [
        Text(
          "Uncommon Nouns",
          style: Theme.of(context).textTheme.headlineMedium,
        ),
        TextField(
          controller: whisperPromptController,
          decoration: InputDecoration(
            labelText: 'Uncommon Nouns',
            helperText: 'Enter uncommon nouns here to prevent misspellings',
          ),
        ),
        const SizedBox(height: 20),
        Text(
          "File Settings",
          style: Theme.of(context).textTheme.headlineMedium,
        ),
        SwitchListTile(
          title: const Text("Preserve Original Audio File"),
          value: storeOriginalAudio,
          onChanged: (bool value) {
            setState(() {
              storeOriginalAudio = value;
            });
          },
        )
      ],
    ));
  }

  Widget _buildWikiSettingsView() {
    return Center(
        child: Column(
      children: [
        TextField(
          controller: wikiApiTokenController,
          decoration: InputDecoration(
            labelText: 'Wiki API Token',
            helperText: 'Enter your Wiki API Token here',
          ),
        ),
        TextField(
          controller: wikiPageIdController,
          decoration: InputDecoration(
            labelText: 'Wiki Page ID',
            helperText: 'Enter the Wiki Page ID here',
          ),
        ),
        TextField(
          controller: spaceIdController,
          decoration: InputDecoration(
            labelText: 'Space ID',
            helperText: 'Enter the Space ID here',
          ),
        )
      ],
    ));
  }

  Widget _buildPromptSettingsView() {
    return Center(
        child: SingleChildScrollView(
            child: Column(
      children: [
        ListView.builder(
          shrinkWrap: true,
          physics: NeverScrollableScrollPhysics(),
          itemCount: prompts.length,
          itemBuilder: (context, index) {
            return Column(
              children: [
                ListTile(
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
                ),
                SwitchListTile(
                  title: Text('Enable Chapter'),
                  value: prompts[index].enableChapter,
                  onChanged: (bool value) {
                    setState(() {
                      prompts[index].enableChapter = value;
                    });
                  },
                ),
                const Divider(),
              ],
            );
          },
        ),
        ElevatedButton(
          onPressed: addNewPrompt,
          child: Text('Add New Prompt'),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.green,
          ),
        )
      ],
    )));
  }

  Widget _buildGeneralView() {
    return Center(child: Text('General View'));
  }
}

void main() {
  runApp(MaterialApp(
    home: SettingsPage(),
  ));
}
