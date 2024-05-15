import 'package:flutter/material.dart';
import 'dart:convert';
import './SettingService.dart';
import './PromptItem.dart';

import 'package:shared_preferences/shared_preferences.dart';

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
  final TextEditingController openAiModelController = TextEditingController();
  String openAiModel = 'gpt-3.5-turbo'; // Default model
  final TextEditingController promptController = TextEditingController();
  List<PromptItem> prompts = [];
  int? defaultPromptIndex;
  bool useOpenAI = true; // true for OpenAI, false for Ollama

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
      openAiModel = settings['openai_model'];
      openAiKeyController.text = settings['openai_key'];
      ollamaUrlController.text = settings['ollama_url'];
      ollamaModelController.text = settings['ollama_model'];
      prompts = settings['prompts'];
      useOpenAI = settings['use_openai'];
      defaultPromptIndex = settings['defaultPromptIndex'];
    });
  }

  Future<void> saveSettings() async {
    await settingsService.saveSettings(
        openAiKeyController.text,
        openAiModel,
        ollamaUrlController.text,
        ollamaModelController.text,
        useOpenAI,
        prompts,
        defaultPromptIndex);
    // Navigator.pop(context);
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
                backgroundColor:
                    Theme.of(context).primaryColor, // Background color
                foregroundColor: Colors.white, // Foreground color
              ),
              onPressed: () {
                if (openAiKeyController.text.isNotEmpty &&
                    prompts.isNotEmpty &&
                    prompts
                        .any((p) => p.name.isNotEmpty && p.prompt.isNotEmpty) &&
                    defaultPromptIndex != null &&
                    prompts.length > defaultPromptIndex!) {
                  saveSettings();
                  Navigator.pop(context);
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
            ListTile(
              title: const Text("OpenAI"),
              leading: Radio<bool>(
                value: true,
                groupValue: useOpenAI,
                onChanged: (bool? value) {
                  setState(() {
                    useOpenAI = value!;
                  });
                },
              ),
            ),
            if (useOpenAI) ...[
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
              title: const Text("Ollama"),
              leading: Radio<bool>(
                value: false,
                groupValue: useOpenAI,
                onChanged: (bool? value) {
                  setState(() {
                    useOpenAI = value!;
                  });
                },
              ),
            ),
            if (!useOpenAI) ...[
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
    promptController.dispose();
    super.dispose();
  }
}
