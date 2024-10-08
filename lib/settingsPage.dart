import 'package:flutter/material.dart';
import './SettingService.dart';
import './PromptItem.dart';
import './settingSidebar.dart';
import './inputField.dart';
import './checkboxField.dart';
import './dropdownField.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/gestures.dart'; // Add this line
import 'package:flutter/services.dart'; // 用於處理鍵盤事件

class SettingsPage extends StatefulWidget {
  static const routeName = '/settings';

  @override
  _SettingsPageState createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool _settingsChanged = false;
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

  Map<String, String> shortcuts = {};

  @override
  void initState() {
    super.initState();
    loadSettings();
  }

  void addNewPrompt() {
    setState(() {
      prompts
          .add(PromptItem(name: '(Please replace with new name)', prompt: ''));
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
      shortcuts =
          Map<String, String>.from(settings[SettingsService.SHORTCUTS] ?? {});
    });
  }

  void _saveSettings() async {
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
      shortcuts,
    );
    _settingsChanged = true;
    Navigator.of(context).pop(_settingsChanged);
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        Navigator.of(context).pop(_settingsChanged);
        return false;
      },
      child: Scaffold(
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
                  _saveSettings();
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
      case 'Shortcuts':
        return _buildShortcutsView();
      default:
        return _buildGeneralView();
    }
  }

  Widget _buildSttOptionsView() {
    return Center(
        child: Column(children: [
      CheckboxField(
        label: "Use OpenAI whisper",
        description: "Use OpenAI Whisper for STT or Local Whisper",
        initialValue: useOpenAIWhisper,
        onChanged: (bool? value) {
          setState(() {
            useOpenAIWhisper = value!;
          });
        },
      ),
      SizedBox(height: 20),
      if (!useOpenAIWhisper) ...[
        DropdownField(
          label: "Local Whisper Model",
          value: localWhisperModel,
          items: <String>['tiny', 'base', 'small', 'medium'],
          onChanged: (String? newValue) {
            setState(() {
              localWhisperModel = newValue!;
            });
          },
        ),
      ],
      if (useOpenAIWhisper) ...[
        InputField(
          label: "OpenAI API Key",
          helperText: "Enter your OpenAI API Key here",
          controller: openAiKeyController,
          isPassword: true,
        ),
        InputField(
          label: "OpenAI Audio Base URL (optional)",
          helperText: "Enter your OpenAI Audio Base URL here",
          controller: openaiAudioBaseUrlController,
        ),
      ]
    ]));
  }

  Widget _buildLlmOptionsView() {
    return Center(
        child: Column(
      children: [
        CheckboxField(
          label: "Use OpenAI LLM",
          description: "Use OpenAI LLM for LLM",
          initialValue: llmChoice == 'openai',
          onChanged: (bool? value) {
            setState(() {
              llmChoice = value! ? 'openai' : 'ollama';
            });
          },
        ),
        if (llmChoice == 'openai') ...[
          InputField(
            label: "OpenAI API Key",
            helperText: "Enter your OpenAI API Key here",
            controller: openAiKeyController,
            isPassword: true,
          ),
          InputField(
            label: 'OpenAI Completion Base URL (optional)',
            helperText: 'Enter your OpenAI Completion Base URL here',
            controller: openaiCompletionBaseUrlController,
          ),
          DropdownField(
            label: 'OpenAI Model',
            value: openAiModel,
            items: <String>['gpt-4-turbo', 'gpt-4o', 'gpt-4o-mini'],
            onChanged: (String? newValue) {
              setState(() {
                openAiModel = newValue!;
              });
            },
          ),
        ],
        CheckboxField(
          label: "Use Ollama",
          description: "Use Ollama for LLM",
          initialValue: llmChoice == 'ollama',
          onChanged: (bool? value) {
            setState(() {
              llmChoice = value! ? 'ollama' : 'custom';
            });
          },
        ),
        if (llmChoice == 'ollama') ...[
          InputField(
            label: 'Ollama URL',
            helperText: 'Enter Ollama Service URL here',
            controller: ollamaUrlController,
          ),
          InputField(
            label: 'Ollama Model',
            helperText: 'Enter the model identifier for Ollama',
            controller: ollamaModelController,
          ),
        ],
        CheckboxField(
          label: "Use Custom LLM",
          description: "Use Custom LLM for LLM",
          initialValue: llmChoice == 'custom',
          onChanged: (bool? value) {
            setState(() {
              llmChoice = value! ? 'custom' : 'llama_cpp';
            });
          },
        ),
        if (llmChoice == 'custom') ...[
          InputField(
            label: 'Custom LLM URL',
            helperText: 'Enter Custom LLM Service URL here',
            controller: customLlmUrlController,
          ),
          InputField(
            label: 'Custom LLM Model',
            helperText: 'Enter the model identifier for Custom LLM',
            controller: customLlmModelController,
          ),
        ],
        CheckboxField(
          label: "Run LlamaCpp",
          description: "Run LlamaCpp for LLM",
          initialValue: llmChoice == 'llama_cpp',
          onChanged: (bool? value) {
            setState(() {
              llmChoice = value! ? 'llama_cpp' : 'openai';
            });
          },
        ),
        if (llmChoice == 'llama_cpp') ...[
          InputField(
            label: 'Huggingface Token',
            helperText: 'Enter your Huggingface Token here',
            controller: huggingfaceTokenController,
            isPassword: true,
          ),
          InputField(
            label: 'Huggingface GGUF',
            helperText: 'Enter the GGUF identifier here',
            controller: huggingfaceGgufController,
          ),
        ]
      ],
    ));
  }

  Widget _buildFileSettingsView() {
    return Center(
        child: Column(
      children: [
        InputField(
          controller: whisperPromptController,
          label: 'Uncommon Nouns',
          helperText: 'Enter uncommon nouns here to prevent misspellings',
        ),
        const SizedBox(height: 20),
        CheckboxField(
          label: "Preserve Original Audio File",
          description: "Preserve the original audio file after processing.",
          initialValue: storeOriginalAudio,
          onChanged: (bool? value) {
            setState(() {
              storeOriginalAudio = value!;
            });
          },
        ),
      ],
    ));
  }

  Widget _buildWikiSettingsView() {
    return Center(
        child: Column(
      crossAxisAlignment:
          CrossAxisAlignment.start, // Align children to the start
      children: [
        Padding(
          padding: const EdgeInsets.all(24), // Add padding
          child: Column(
            crossAxisAlignment:
                CrossAxisAlignment.start, // Align children to the start
            children: [
              const SizedBox(height: 8),
              Text(
                "It will help you to export the meeting notes to the wiki page automatically.",
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 16),
              InputField(
                label: "Wiki API Token",
                helperText: "Enter your Wiki API Token here",
                controller: wikiApiTokenController,
                isPassword: true,
              ),
              const SizedBox(height: 16), // Space between fields
              InputField(
                label: "Wiki Page ID",
                controller: wikiPageIdController,
                helperText: 'Enter the Wiki Page ID here',
              ),
              const SizedBox(height: 16), // Space between fields
              InputField(
                label: "Space ID",
                controller: spaceIdController,
                helperText: 'Enter the Space ID here',
              ),
            ],
          ),
        ),
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
                  title: InputField(
                    label: 'Name',
                    controller:
                        TextEditingController(text: prompts[index].name),
                    onChanged: (value) {
                      prompts[index].name = value;
                    },
                  ),
                  subtitle: InputField(
                    label: 'Prompt',
                    controller:
                        TextEditingController(text: prompts[index].prompt),
                    onChanged: (value) {
                      prompts[index].prompt = value;
                    },
                    minLines: 1,
                    // maxLines: 50,
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
                CheckboxField(
                  label: "Enable Chapter",
                  description: "Enable Chapter for this prompt",
                  initialValue: prompts[index].enableChapter,
                  onChanged: (bool? value) {
                    setState(() {
                      prompts[index].enableChapter = value!;
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
            backgroundColor: const Color(0xFF0F66DE),
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(5),
            ),
            side: BorderSide(
              color: Colors.black.withOpacity(0.05),
              width: 0.5,
            ),
          ),
        )
      ],
    )));
  }

  Widget _buildShortcutsView() {
    return Center(
      child: Column(
        children: [
          _buildShortcutField(SettingsService.TRIGGER_RECORD, 'Trigger Record'),
          _buildShortcutField(SettingsService.SCREENSHOT, 'Screenshot'),
          // 可以根據需要添加更多快捷鍵
        ],
      ),
    );
  }

  Widget _buildShortcutField(String key, String label) {
    String _formatShortcut(String shortcut) {
      List<String> keyIds = shortcut.split(' + ');
      if (keyIds.length != 2) return '';

      LogicalKeyboardKey? primary;
      LogicalKeyboardKey? secondary;

      try {
        primary = LogicalKeyboardKey.findKeyByKeyId(int.parse(keyIds[0]));
        secondary = LogicalKeyboardKey.findKeyByKeyId(int.parse(keyIds[1]));
      } catch (e) {
        // 如果 keyIds[0] 不是有效的數字，返回空字符串
        return '';
      }

      if (primary == null || secondary == null) return '';

      return '${primary.keyLabel} + ${secondary.keyLabel}';
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        children: [
          Expanded(
            child: Text(label),
          ),
          SizedBox(width: 20),
          Expanded(
            child: TextFormField(
              key: ValueKey(shortcuts[key]),
              initialValue: shortcuts[key] != null
                  ? _formatShortcut(shortcuts[key]!)
                  : '',
              decoration: InputDecoration(
                labelText: 'Click to set',
                hintText: 'Click to set',
              ),
              readOnly: true,
              onTap: () async {
                await showDialog<void>(
                  context: context,
                  builder: (BuildContext context) => _ShortcutCaptureDialog(
                    initialShortcut: shortcuts[key] ?? '',
                    shortcutKey: key,
                    onSave: (key, value) {
                      setState(() {
                        shortcuts[key] = value;
                      });
                      settingsService.updateShortcuts(shortcuts);
                    },
                  ),
                );
                setState(() {});
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGeneralView() {
    return Column(
      children: [
        Text(
          '產品目的：\n1. 會議記錄：提供簡便的會議記錄功能。\n2. 會議小秘書：讓會議小秘書回答會議相關問題。\n3. 實驗小模型：探索使用 OpenAI 以外的模型與效果。',
          textAlign: TextAlign.left,
        ),
        SizedBox(height: 10),
        Text(
          '環境限制：目前只有支援 Mac 與電腦的麥克風收音。',
          textAlign: TextAlign.left,
        ),
        SizedBox(height: 10),
        RichText(
          textAlign: TextAlign.left,
          text: TextSpan(
            children: [
              TextSpan(
                text: '請於 ',
                style: TextStyle(color: Colors.black),
              ),
              TextSpan(
                text: 'Download Link',
                style: TextStyle(
                    color: Colors.blue, decoration: TextDecoration.underline),
                recognizer: TapGestureRecognizer()
                  ..onTap = () {
                    launch(
                        'https://workers-hub.enterprise.slack.com/archives/C0749M8BCKT');
                  },
              ),
              TextSpan(
                text: '下載最新的 g_record_helper.zip 檔案。',
                style: TextStyle(color: Colors.black),
              ),
            ],
          ),
        ),
        SizedBox(height: 10),
        RichText(
          textAlign: TextAlign.left,
          text: TextSpan(
            children: [
              TextSpan(
                text: '更多說明請參考 ',
                style: TextStyle(color: Colors.black),
              ),
              TextSpan(
                text: 'Wiki',
                style: TextStyle(
                    color: Colors.blue, decoration: TextDecoration.underline),
                recognizer: TapGestureRecognizer()
                  ..onTap = () {
                    launch(
                        'https://wiki.workers-hub.com/pages/viewpage.action?spaceKey=LineTWRD&title=AI+Meeting+Noter');
                  },
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ShortcutCaptureDialog extends StatefulWidget {
  final String initialShortcut;
  final String shortcutKey;
  final Function(String, String) onSave;

  const _ShortcutCaptureDialog({
    Key? key,
    required this.initialShortcut,
    required this.shortcutKey,
    required this.onSave,
  }) : super(key: key);

  @override
  _ShortcutCaptureDialogState createState() => _ShortcutCaptureDialogState();
}

class _ShortcutCaptureDialogState extends State<_ShortcutCaptureDialog> {
  LogicalKeyboardKey? _primaryKey;
  LogicalKeyboardKey? _secondaryKey;
  FocusNode _focusNode = FocusNode();

  static final Set<LogicalKeyboardKey> _modifierKeys = {
    LogicalKeyboardKey.controlLeft,
    LogicalKeyboardKey.controlRight,
    LogicalKeyboardKey.altLeft,
    LogicalKeyboardKey.altRight,
    LogicalKeyboardKey.shiftLeft,
    LogicalKeyboardKey.shiftRight,
    LogicalKeyboardKey.metaLeft,
    LogicalKeyboardKey.metaRight,
  };

  @override
  void initState() {
    super.initState();
    _focusNode.requestFocus();
    _parseInitialShortcut();
  }

  void _parseInitialShortcut() {
    final keys = widget.initialShortcut.split(' + ');
    if (keys.length == 2) {
      try {
        _primaryKey = LogicalKeyboardKey.findKeyByKeyId(int.parse(keys[0]));
        _secondaryKey = LogicalKeyboardKey.findKeyByKeyId(int.parse(keys[1]));
      } catch (e) {
        // 如果解析失敗，將兩個鍵都設置為 null
        _primaryKey = null;
        _secondaryKey = null;
      }
    } else {
      // 如果格式不正確，將兩個鍵都設置為 null
      _primaryKey = null;
      _secondaryKey = null;
    }
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RawKeyboardListener(
      focusNode: _focusNode,
      onKey: (RawKeyEvent event) {
        if (event is RawKeyDownEvent) {
          setState(() {
            if (_modifierKeys.contains(event.logicalKey)) {
              _primaryKey = event.logicalKey;
              _secondaryKey = null;
            } else if (_primaryKey != null && _secondaryKey == null) {
              _secondaryKey = event.logicalKey;
            }
          });
        }
      },
      child: AlertDialog(
        title: Text('Press desired shortcut'),
        content: Text(_getDisplayText()),
        actions: <Widget>[
          TextButton(
            child: Text('Clear'),
            onPressed: () {
              setState(() {
                _primaryKey = null;
                _secondaryKey = null;
              });
            },
          ),
          TextButton(
            child: Text('Cancel'),
            onPressed: () => Navigator.of(context).pop(),
          ),
          TextButton(
            child: Text('OK'),
            onPressed: () {
              if (_primaryKey != null && _secondaryKey != null) {
                widget.onSave(widget.shortcutKey, _getShortcutString());
                Navigator.of(context).pop();
              }
            },
          ),
        ],
      ),
    );
  }

  String _getDisplayText() {
    if (_primaryKey == null) {
      return 'Press a modifier key (Ctrl, Alt, Shift, or Meta)';
    } else if (_secondaryKey == null) {
      return '${_primaryKey!.keyLabel} + ...';
    } else {
      return '${_primaryKey!.keyLabel} + ${_secondaryKey!.keyLabel}';
    }
  }

  String _getShortcutString() {
    if (_primaryKey == null || _secondaryKey == null) {
      return '';
    }
    return '${_primaryKey!.keyId} + ${_secondaryKey!.keyId}';
  }
}

void main() {
  runApp(MaterialApp(
    home: SettingsPage(),
  ));
}
