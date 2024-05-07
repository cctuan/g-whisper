import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:hotkey_manager/hotkey_manager.dart';
import 'package:flutter/services.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:share_plus/share_plus.dart';
import 'package:markdown/markdown.dart' as md;
import './recordService.dart';

GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await hotKeyManager.unregisterAll();
  runApp(const MyApp(title: 'G Whisper'));
  // await hotKeyManager.unregisterAll();
}

class MyApp extends StatefulWidget {
  const MyApp({super.key, required this.title});
  final String title;

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
  @override
  void initState() {
    _recorderService = RecorderService();
    _recorderService.onRecordingStateChanged = () {
      setState(() {
        // 這會觸發 UI 重新建構
        updateTrayIcon();
      });
    };
    _recorderService.init();
    _recorderService.onRecordCompleteReturn = (text) {
      // 在这里处理录音完成后的逻辑
      setState(() {
        // 假设 _recordedFilePath 是录音文件的路径
        // if (text != null) {
        recordLogs.insert(0, text);
        // }
      });
    };
    _recorderService.onAmplitudeChange = (bool voicePresent) {
      hasVoice = voicePresent;
      print(voicePresent);
      updateTrayIcon();
    };
    _setupHotKey();
    initTray();
    super.initState();
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
    BuildContext context = navigatorKey.currentState!.overlay!.context;
    if (isSettingsDialogOpen) {
      return; // If the dialog is already open, do nothing
    }
    isSettingsDialogOpen = true; // Set flag to true as dialog is opening

    Map<String, String> settings = await loadSettings();
    TextEditingController openAiKeyController =
        TextEditingController(text: settings['openai_key']);
    TextEditingController promptController =
        TextEditingController(text: settings['prompt']);

    return showDialog<void>(
      context: context,
      barrierDismissible: false, // User must tap button!
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('OpenAI Settings'),
          content: SingleChildScrollView(
            child: ListBody(
              children: <Widget>[
                TextField(
                  controller: openAiKeyController,
                  decoration: InputDecoration(
                    hintText: "Enter OpenAI Key",
                    border:
                        OutlineInputBorder(), // Standard border when not focused
                    enabledBorder: OutlineInputBorder(
                      // Border style when TextField is enabled but not focused
                      borderSide:
                          BorderSide(color: Colors.grey[400]!, width: 0.5),
                    ),
                    focusedBorder: OutlineInputBorder(
                      // Border style when TextField is focused
                      borderSide:
                          BorderSide(color: Colors.grey[600]!, width: 1.0),
                    ),
                    prefixIcon: Icon(
                        Icons.vpn_key), // Icon to indicate purpose of the field
                  ),
                ),
                TextField(
                  controller: promptController,
                  decoration: InputDecoration(
                    hintText: "Enter Prompt",
                    border: OutlineInputBorder(),
                    enabledBorder: OutlineInputBorder(
                      borderSide:
                          BorderSide(color: Colors.grey[400]!, width: 0.5),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderSide:
                          BorderSide(color: Colors.grey[600]!, width: 1.0),
                    ),
                    prefixIcon:
                        Icon(Icons.text_fields), // Icon to suggest text input
                  ),
                  keyboardType: TextInputType.multiline,
                  maxLines: null,
                  minLines: 3,
                  cursorColor: Colors.grey[800], // Make the cursor more visible
                  cursorWidth:
                      2.0, // Increase the width of the cursor for better visibility
                )
              ],
            ),
          ),
          actions: <Widget>[
            TextButton(
              child: const Text('Cancel'),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
            TextButton(
              child: const Text('Save'),
              onPressed: () {
                // Save the OpenAI Key and Prompt somewhere
                // For example, using SharedPreferences or to the state
                print('OpenAI Key: ${openAiKeyController.text}');
                print('Prompt: ${promptController.text}');
                saveSettings(openAiKeyController.text, promptController.text);
                Navigator.of(context).pop();
              },
            ),
          ],
        );
      },
    ).then((_) => isSettingsDialogOpen = false);
  }

  void deleteRecording(int index) {
    setState(() {
      recordLogs.removeAt(index);
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
          body: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                Text(
                  _recorderService.isRecording
                      ? 'Recording in Progress'
                      : 'Press the mic to start recording or option + w',
                ),
                Text(
                  _recorderService.recordedFilePath ?? 'No file recorded yet',
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
                              height: 20, // Specify the height of the box
                              width: 20, // Specify the width of the box
                              child: CircularProgressIndicator(
                                strokeWidth:
                                    1, // Reduce the stroke width to make it look thinner
                              ),
                            )
                          : _recorderService.isRecording
                              ? Image.asset('images/icon_mic_recording2.png',
                                  width: 24, height: 24)
                              : Image.asset('images/micromuted.png',
                                  width: 24, height: 24),
                    ),
                    SizedBox(height: 20),
                    _recorderService.isProcessing
                        ? InkWell(
                            onTap: () => _recorderService.cancelRecording(),
                            child: Text("Cancel",
                                style: TextStyle(
                                    decoration: TextDecoration.underline,
                                    color: Colors.blue)),
                          )
                        : Text(_recorderService.isRecording
                            ? 'Recording'
                            : 'Pausing'),
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
                              recordResult.processedText.substring(0, 50) +
                                  '...'),
                          backgroundColor: Colors.grey[200],
                          children: <Widget>[
                            ExpansionTile(
                                title: const Text(
                                  '文本內容',
                                  style: TextStyle(
                                    fontSize: 20, // 更大的字体尺寸
                                    fontWeight: FontWeight.bold, // 加粗字体
                                  ),
                                ),
                                children: <Widget>[
                                  ListTile(
                                      title: const Text(
                                        '原始音檔文字',
                                        style: TextStyle(
                                            fontSize: 18,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.black87),
                                      ),
                                      subtitle: Column(
                                        children: <Widget>[
                                          TextField(
                                            controller: originalTextController,
                                            focusNode: originalTextFocusNode,
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
                                      )),
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
                                            border:
                                                Border.all(color: Colors.grey),
                                            borderRadius:
                                                BorderRadius.circular(5),
                                          ),
                                          child: TextField(
                                            controller: processedTextController,
                                            focusNode: processedTextFocusNode,
                                            maxLines: 5,
                                            style: TextStyle(
                                                color: Colors.black,
                                                fontSize: 16),
                                            decoration:
                                                InputDecoration.collapsed(
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
        ));
  }

  @override
  void dispose() {
    trayManager.removeListener(this);
    _recorderService.dispose();
    hotKeyManager.unregister(_hotKey);
    super.dispose();
  }
}
