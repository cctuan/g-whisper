import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:hotkey_manager/hotkey_manager.dart';
import 'package:flutter/services.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:share_plus/share_plus.dart';
import 'package:window_manager/window_manager.dart';
import 'package:desktop_drop/desktop_drop.dart';
import './storage.dart';
import './settingsPage.dart';
import './recordService.dart';
import './PromptItem.dart';
import './recordResult.dart';

GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
GlobalKey<ScaffoldMessengerState> _scaffoldMessengerKey =
    GlobalKey<ScaffoldMessengerState>();

ValueNotifier<String?> messageNotifier = ValueNotifier<String?>(null);

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();
  await hotKeyManager.unregisterAll();
  List<RecordResult> recordLogs = await DatabaseHelper().getRecordings();

  runApp(MyApp(title: 'G Whisper', initialRecordLogs: recordLogs));
  // await hotKeyManager.unregisterAll();
}

class MyApp extends StatefulWidget {
  const MyApp(
      {super.key, required this.title, required this.initialRecordLogs});
  final String title;
  final List<RecordResult> initialRecordLogs;
  @override
  State<MyApp> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyApp> with TrayListener {
  late final RecorderService _recorderService;
  late HotKey _hotKey;
  bool isSettingsDialogOpen =
      false; // Flag to track if the settings dialog is open
  List<RecordResult> recordLogs = []; // 存储录音记录的列表
  bool hasVoice = false;
  bool isDragging = false;
  ValueNotifier<String?> messageNotifier = ValueNotifier<String?>(null);

  @override
  void initState() {
    recordLogs = widget.initialRecordLogs;
    _recorderService = RecorderService();
    _recorderService.onRecordingStateChanged = () {
      setState(() {
        // 這會觸發 UI 重新建構
        updateTrayIcon();
      });
    };
    _recorderService.init();
    _recorderService.onRecordCompleteReturn =
        (RecordResult result, [int? index]) {
      // 在这里处理录音完成后的逻辑
      setState(() {
        if (index != null && index >= 0 && index < recordLogs.length) {
          recordLogs[index] = result; // Replace the existing entry at the index
          DatabaseHelper().updateRecording(result);
        } else {
          recordLogs.insert(0, result); // Insert new record at the beginning
          DatabaseHelper().insertRecording(result);
        }
        hideMessage();
      });
    };
    _recorderService.onAmplitudeChange = (bool voicePresent) {
      hasVoice = voicePresent;
      print(voicePresent);
      updateTrayIcon();
    };
    _recorderService.onStatusUpdateCallback = (String message) {
      showMessage(message);
    };
    _setupHotKey();
    initTray();
    super.initState();
  }

  void showMessage(String message) {
    print("Message: $message");
    messageNotifier.value = message;
  }

  void hideMessage() {
    messageNotifier.value = null;
  }

  Future<void> initTray() async {
    updateTrayIcon();
    updateTrayMenu();
    trayManager.addListener(this);
  }

  @override
  void onTrayIconMouseDown() {
    trayManager.popUpContextMenu();
  }

  void updateTrayMenu() async {
    Menu menu = Menu(
      items: [
        MenuItem(
          key: 'show_settings',
          label: 'Settings',
        ),
        MenuItem.separator(),
        MenuItem(
          key: 'close_app',
          label: 'Close App',
        ),
      ],
    );
    await trayManager.setContextMenu(menu);
  }

  void updateTrayIcon() {
    String iconPath;
    if (_recorderService.isProcessing) {
      iconPath = 'images/loading.png';
    } else if (_recorderService.isRecording) {
      if (hasVoice) {
        iconPath = 'images/icon_mic_recording2.png'; // 正在录音且有声音
      } else {
        iconPath = 'images/icon_mic_recording.png'; // 正在录音但无声音
      }
    } else {
      iconPath = 'images/micromuted.png'; // 没有录音
    }
    trayManager.setIcon(iconPath);
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    if (menuItem.key == 'show_settings') {
      WindowOptions windowOptions = WindowOptions(
        center: true,
      );
      windowManager.waitUntilReadyToShow(windowOptions, () async {
        await windowManager.show();
        await windowManager.focus();
      });
      showSettingsDialog();
    } else if (menuItem.key == 'close_app') {
      // closeApplication();
      // do something
    }
  }

  void _setupHotKey() async {
    await hotKeyManager.unregisterAll();
    _hotKey = HotKey(
      key: PhysicalKeyboardKey.keyW,
      modifiers: [HotKeyModifier.alt],
      scope: HotKeyScope.system,
    );

    hotKeyManager
        .register(
      _hotKey,
      keyDownHandler: (_) => _recorderService.toggleRecording(),
    )
        .catchError((error) {
      print('Failed to register hotkey: $error');
    });
  }

  Future<void> saveSettings(String key, String prompt) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString('openai_key', key);
    await prefs.setString('prompt', prompt);
    _recorderService.init();
  }

  Future<Map<String, String>> loadSettings() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    String key = prefs.getString('openai_key') ?? '';
    String prompt = prefs.getString('prompt') ?? '';
    return {'openai_key': key, 'prompt': prompt};
  }

  Future<void> showSettingsDialog() async {
    if (navigatorKey.currentState == null) return;

    var currentRoute = ModalRoute.of(navigatorKey.currentContext!);

    if (currentRoute != null &&
        currentRoute.settings.name == SettingsPage.routeName) {
      // 如果当前顶部已是 SettingsPage，则不执行任何操作
      return;
    }

    // 推送 SettingsPage 到 Navigator
    navigatorKey.currentState!.push(MaterialPageRoute(
      builder: (context) => const SettingsPage(),
      settings: RouteSettings(name: SettingsPage.routeName),
    ));
  }

  void copyRecording(RecordResult recordResult) {
    final String content =
        "Recording on ${recordResult.timestamp}:\nProcessed Text: ${recordResult.processedText}";
    Clipboard.setData(ClipboardData(text: content)).then((_) {
      _scaffoldMessengerKey.currentState?.showSnackBar(
        SnackBar(content: Text('Recording copied to clipboard!')),
      );
    }).catchError((error) {
      // Handle any errors here
      print('Error copying to clipboard: $error');
    });
  }

  void deleteRecording(int index) {
    setState(() {
      RecordResult record = recordLogs[index];
      recordLogs.removeAt(index);
      DatabaseHelper().deleteRecording(record.id!);
    });
  }

  void shareRecording(RecordResult recordResult) {
    final String content =
        "Recording on ${recordResult.timestamp}:\nOriginal Text: ${recordResult.originalText}\nProcessed Text: ${recordResult.processedText}";
    Share.share(content);
  }

  void saveRecordResult(RecordResult recordResult, int index) {
    setState(() {
      recordLogs[index].originalText = recordResult.originalText;
      recordLogs[index].processedText = recordResult.processedText;
      DatabaseHelper().updateRecording(recordLogs[index]);
    });
    // 保存逻辑，可能是更新状态、发送到服务器等
    print(
        'Saved: Original Text = ${recordResult.originalText}, Processed Text = ${recordResult.processedText}');
  }

  void editRecording(RecordResult recordResult, int index) {
    BuildContext context = navigatorKey.currentState!.overlay!.context;
    TextEditingController textEditingController =
        TextEditingController(text: recordResult.originalText);

    showDialog<void>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text("Edit Recording"),
          content: TextFormField(
            controller: textEditingController,
            // The onChanged isn't necessary if you're updating the text only after the button press
            // onChanged: (value) {},
          ),
          actions: <Widget>[
            TextButton(
              child: const Text("Save"),
              onPressed: () {
                // Update the logic here to save the edited text
                setState(() {
                  recordLogs[index].originalText = textEditingController.text;
                  DatabaseHelper().updateRecording(recordLogs[index]);
                });
                Navigator.of(context).pop(); // Close the dialog
              },
            ),
            TextButton(
              child: const Text("Close"),
              onPressed: () {
                Navigator.of(context).pop(); // Close the dialog without saving
              },
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
        navigatorKey: navigatorKey,
        title: 'Flutter Audio Recorder',
        theme: ThemeData(
          primarySwatch: Colors.blue,
          useMaterial3: true,
        ),
        scaffoldMessengerKey: _scaffoldMessengerKey,
        home: Scaffold(
            appBar: AppBar(
              title: Text(widget.title),
              actions: [
                IconButton(
                  icon: Icon(Icons.settings),
                  onPressed: () {
                    if (!isSettingsDialogOpen) {
                      showSettingsDialog();
                    }
                  },
                ),
              ],
            ),
            body: DropTarget(
                onDragEntered: (details) {
                  setState(() {
                    isDragging = true;
                  });
                },
                onDragExited: (details) {
                  setState(() {
                    isDragging = false;
                  });
                },
                onDragDone: (details) {
                  setState(() {
                    isDragging = false;
                  });
                  if (details.files.isNotEmpty) {
                    String filePath = details.files.first.path;
                    if (filePath.endsWith('.wav') ||
                        filePath.endsWith('.mp3') ||
                        filePath.endsWith('.mov') ||
                        filePath.endsWith('.m4a')) {
                      _recorderService.stopRecording(details.files.first.path);
                    } else {
                      // Show a message to the user indicating the file format is not supported
                      _scaffoldMessengerKey.currentState?.showSnackBar(
                        SnackBar(
                            content: Text(
                                'Unsupported file format. Please use WAV, MP3, mov or m4a.')),
                      );
                    }
                  }
                },
                child: Stack(children: [
                  Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: <Widget>[
                        Text(
                          _recorderService.isRecording
                              ? 'Recording in Progress'
                              : 'Press the mic to start recording or option + w',
                        ),
                        Text(
                          _recorderService.recordedFilePath ??
                              'No file recorded yet',
                        ),
                        Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: <Widget>[
                            ElevatedButton(
                              onPressed: () {
                                if (!_recorderService.isProcessing) {
                                  _recorderService.toggleRecording();
                                }
                              },
                              child: _recorderService.isProcessing
                                  ? SizedBox(
                                      height:
                                          20, // Specify the height of the box
                                      width: 20, // Specify the width of the box
                                      child: CircularProgressIndicator(
                                        strokeWidth:
                                            1, // Reduce the stroke width to make it look thinner
                                      ),
                                    )
                                  : _recorderService.isRecording
                                      ? Image.asset(
                                          'images/icon_mic_recording2.png',
                                          width: 24,
                                          height: 24)
                                      : Image.asset('images/micromuted.png',
                                          width: 24, height: 24),
                            ),
                            SizedBox(height: 20),
                            _recorderService.isProcessing
                                ? InkWell(
                                    onTap: () =>
                                        _recorderService.cancelRecording(),
                                    child: Text("Cancel",
                                        style: TextStyle(
                                            decoration:
                                                TextDecoration.underline,
                                            color: Colors.blue)),
                                  )
                                : Text(_recorderService.isRecording
                                    ? 'Recording'
                                    : 'Pausing'),
                            ValueListenableBuilder<String?>(
                              valueListenable: messageNotifier,
                              builder: (context, message, child) {
                                if (message == null) {
                                  return Container(); // No message, return an empty container
                                }
                                return Container(
                                  color: Colors.blue,
                                  padding: EdgeInsets.all(8.0),
                                  width: double.infinity,
                                  child: Text(
                                    message,
                                    style: TextStyle(color: Colors.white),
                                    textAlign: TextAlign.center,
                                  ),
                                );
                              },
                            ),
                          ],
                        ),
                        Expanded(
                          child: ListView.builder(
                            itemCount: recordLogs.length,
                            itemBuilder: (context, index) {
                              RecordResult recordResult = recordLogs[index];

                              // 创建控制器和焦点节点
                              TextEditingController originalTextController =
                                  TextEditingController(
                                      text: recordResult.originalText);
                              FocusNode originalTextFocusNode = FocusNode();
                              TextEditingController processedTextController =
                                  TextEditingController(
                                      text: recordResult.processedText);
                              FocusNode processedTextFocusNode = FocusNode();

                              // 添加焦点监听器
                              originalTextFocusNode.addListener(() {
                                if (!originalTextFocusNode.hasFocus) {
                                  // 更新数据并保存
                                  recordResult.originalText =
                                      originalTextController.text;
                                  saveRecordResult(recordResult, index);
                                }
                              });

                              processedTextFocusNode.addListener(() {
                                if (!processedTextFocusNode.hasFocus) {
                                  // 更新数据并保存
                                  recordResult.processedText =
                                      processedTextController.text;
                                  saveRecordResult(recordResult, index);
                                }
                              });
                              return Card(
                                elevation: 4.0,
                                margin: EdgeInsets.symmetric(
                                    horizontal: 10.0, vertical: 6.0),
                                child: ExpansionTile(
                                  title: Text('${recordResult.timestamp}'),
                                  subtitle: Text(
                                    recordResult.processedText.length > 50
                                        ? '${recordResult.processedText.substring(0, 50)}...'
                                        : recordResult.processedText,
                                  ),
                                  backgroundColor: Colors.grey[200],
                                  children: <Widget>[
                                    ExpansionTile(
                                        title: const Text(
                                          '細節內容',
                                          style: TextStyle(
                                            fontSize: 20, // 更大的字体尺寸
                                            fontWeight: FontWeight.bold, // 加粗字体
                                          ),
                                        ),
                                        children: <Widget>[
                                          ExpansionTile(
                                            title: const Text(
                                              '原始音檔文字',
                                              style: TextStyle(
                                                  fontSize: 18,
                                                  fontWeight: FontWeight.bold,
                                                  color: Colors.black87),
                                            ),
                                            children: <Widget>[
                                              TextField(
                                                controller:
                                                    originalTextController,
                                                focusNode:
                                                    originalTextFocusNode,
                                                style: TextStyle(
                                                    color: Colors.black,
                                                    fontSize: 16),
                                                cursorColor: Colors.blue,
                                                decoration: InputDecoration(
                                                  border: InputBorder
                                                      .none, // 无边框，根据需要选择合适的边框样式
                                                ),
                                                maxLines: null, // 允许无限行
                                              ),
                                            ],
                                          ),
                                          buildPromptDropdown(
                                              recordResult.promptText,
                                              _recorderService.getPrompts(),
                                              (selectedPrompt) {
                                            setState(() {
                                              recordResult.promptText =
                                                  selectedPrompt; // Update the current prompt text
                                              _recorderService
                                                  .handleExistingPrompt(
                                                      selectedPrompt,
                                                      recordResult,
                                                      index);
                                              // print(selectedPrompt);
                                              // recordResult.promptText = selectedPrompt;
                                              // // Optionally trigger processing with the new prompt
                                              // _recorderService.reprocessRecord(record, selectedPrompt);
                                            });
                                          }),
                                          ListTile(
                                            title: const Text(
                                              'AI整理檔案（可編輯）',
                                              style: TextStyle(
                                                  fontSize: 18,
                                                  fontWeight: FontWeight.bold,
                                                  color: Colors.black87),
                                            ),
                                            subtitle: Column(
                                              children: <Widget>[
                                                Container(
                                                  padding: EdgeInsets.all(8.0),
                                                  decoration: BoxDecoration(
                                                    border: Border.all(
                                                        color: Colors.grey),
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                            5),
                                                  ),
                                                  child: TextField(
                                                    controller:
                                                        processedTextController,
                                                    focusNode:
                                                        processedTextFocusNode,
                                                    maxLines: 5,
                                                    style: TextStyle(
                                                        color: Colors.black,
                                                        fontSize: 16),
                                                    decoration: InputDecoration
                                                        .collapsed(
                                                            hintText:
                                                                "Edit Processed Text"),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ]),
                                    if (!processedTextFocusNode.hasFocus)
                                      ListTile(
                                        title: const Text(
                                          '會議總結',
                                          style: TextStyle(
                                            fontSize: 20, // 更大的字体尺寸
                                            fontWeight: FontWeight.bold, // 加粗字体
                                          ),
                                        ),
                                        subtitle: Container(
                                          padding: EdgeInsets.all(8.0),
                                          child: MarkdownBody(
                                            data: processedTextController.text,
                                          ),
                                        ),
                                      ),
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.end,
                                      children: [
                                        IconButton(
                                          icon: Icon(Icons.share),
                                          onPressed: () {
                                            // 分享操作
                                            shareRecording(recordResult);
                                          },
                                        ),
                                        IconButton(
                                          icon: Icon(Icons.content_copy),
                                          onPressed: () {
                                            copyRecording(recordResult);
                                          },
                                        ),
                                        IconButton(
                                          icon: Icon(Icons.delete),
                                          onPressed: () {
                                            // 删除操作
                                            deleteRecording(index);
                                          },
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (isDragging)
                    Container(
                      color: Colors.blue.withOpacity(0.2),
                      child: Center(
                        child: Text(
                          'Drop the file here',
                          style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                              color: Colors.blue),
                        ),
                      ),
                    ),
                ]))));
  }

  @override
  void dispose() {
    trayManager.removeListener(this);
    _recorderService.dispose();
    hotKeyManager.unregister(_hotKey);
    super.dispose();
  }
}

Widget buildPromptDropdown(String? currentPrompt, List<PromptItem> prompts,
    Function(String) onSelected) {
  // Create a set to filter out duplicates
  final uniquePrompts = <String>{};

  return DropdownButton<String>(
    value: currentPrompt,
    onChanged: (newValue) {
      if (newValue != null && newValue != 'Select a prompt...') {
        onSelected(newValue);
      }
    },
    items: [
      DropdownMenuItem<String>(
        value: 'Select a prompt...', // Default non-selectable item
        child: Text('Select a prompt...'),
        enabled: false, // Make it non-selectable
      ),
      ...prompts.where((PromptItem prompt) {
        // Check if the prompt is unique before adding it to the set
        return uniquePrompts.add(prompt.prompt);
      }).map((PromptItem prompt) {
        return DropdownMenuItem<String>(
          value: prompt.prompt,
          child: Text(prompt.name),
        );
      }).toList(),
    ],
  );
}
