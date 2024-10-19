import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:hotkey_manager/hotkey_manager.dart';
import 'package:flutter/services.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:share_plus/share_plus.dart';
import 'package:window_manager/window_manager.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'screenshot_service.dart'; // Import the screenshot service

import './storage.dart';
import './settingsPage.dart';
import './recordService.dart';
import './PromptItem.dart';
import './recordResult.dart';
import './SettingService.dart';
import './chatPage.dart';
import './WikiService.dart';

GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
GlobalKey<ScaffoldMessengerState> _scaffoldMessengerKey =
    GlobalKey<ScaffoldMessengerState>();

ValueNotifier<String?> messageNotifier = ValueNotifier<String?>(null);

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();
  await hotKeyManager.unregisterAll();

  runApp(MyApp(title: 'G Whisper dev-0.3.0'));
  // await hotKeyManager.unregisterAll();
}

class MyApp extends StatefulWidget {
  const MyApp({super.key, required this.title});
  final String title;
  @override
  State<MyApp> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyApp> with TrayListener {
  final SettingsService settingsService = SettingsService();
  // final _cropperKey = GlobalKey(debugLabel: 'cropperKey');
  late final RecorderService _recorderService;
  late final ScreenshotService _screenshotService;
  late HotKey _hotKey;
  late HotKey _screenshotHotKey;
  late final WikiService _wikiService;
  bool isSettingsDialogOpen =
      false; // Flag to track if the settings dialog is open
  List<RecordResult> recordLogs = []; // 存储录音记录的列表
  List<MapEntry<int, RecordResult>> filteredRecordLogs = []; // 存储过滤后的录音记录的列表

  bool hasVoice = false;
  bool isDragging = false;
  String searchKeyword = '';
  bool isSearchBarVisible = false;

  late TextEditingController searchController;
  late ScreenshotService screenshotService;

  ValueNotifier<String?> messageNotifier = ValueNotifier<String?>(null);

  int selectedYear = DateTime.now().year;
  int selectedMonth = DateTime.now().month;

  bool _isInitializing = true; // Flag to track initialization status
  bool showAllRecordings = false; // Flag to track if "All" is selected

  @override
  void initState() {
    super.initState();
    searchController = TextEditingController(text: searchKeyword);
    _initializeRecorderService().then((_) {
      setState(() {
        _isInitializing = false; // Set to false once initialization is complete
      });
    });
  }

  Future<void> _loadCurrentMonthRecordings() async {
    recordLogs = await DatabaseHelper().getRecordingsByCurrentMonth();
    _filterRecords();
  }

  Future<void> _initializeRecorderService() async {
    _wikiService = WikiService(settingsService);
    // await _wikiService.initialize();
    await _loadCurrentMonthRecordings();
    // filteredRecordLogs = recordLogs.asMap().entries.toList();
    _filterRecords();
    _recorderService = RecorderService();
    _recorderService.onRecordingStateChanged = () {
      setState(() {
        // 這會觸發 UI 重新建構
        updateTrayIcon();
        _handleScreenshotHotKey();
      });
    };
    _screenshotService = ScreenshotService(
      onScreenshotTaken: (imagePath, timestamp) {
        if (imagePath != null) {
          _recorderService.addScreenshot(imagePath, timestamp);
        }
      },
    );
    await _recorderService.init();
    setState(() => {});
    _recorderService.onRecordCompleteReturn =
        (RecordResult result, [int? id]) async {
      // 在这里处理录音完成后的逻辑
      // 在插入新录音记录之前，先用户的视图切换到最新的 year 和 month
      _onYearMonthSelected(
          year: DateTime.now().year, month: DateTime.now().month);

      if (id == null ||
          recordLogs.indexWhere((record) => record.id == id) == -1) {
        // 如果 id 为 null 或者没有找到对应的录音记录，插入新录音记录
        final newRecord = await DatabaseHelper().insertRecording(result);
        setState(() {
          recordLogs.insert(0, newRecord); // 将新记录插入到开头
          hideMessage();
        });
      } else {
        // 使用 id 查找对应的录音记录
        int index = recordLogs.indexWhere((record) => record.id == id);
        // 更新现有录音记录
        DatabaseHelper().updateRecording(result, id);
        setState(() {
          recordLogs[index] = result; // 替换现有的录音记录
          hideMessage();
        });
      }
      bool isWikiServiceEnabled = await _wikiService.isEnabled();
      if (isWikiServiceEnabled) {
        bool syncSuccess = await _wikiService.syncToWiki(result);
        if (syncSuccess) {
          showMessage('Successfully synced to Wiki');
        } else {
          showMessage('Failed to sync to Wiki. Please check your settings.');
        }
      }
      _filterRecords(); // 更新过滤结果
    };
    _recorderService.onAmplitudeChange = (bool voicePresent) {
      hasVoice = voicePresent;
      print(voicePresent);
      updateTrayIcon();
    };
    _recorderService.onStatusUpdateCallback = (String message) {
      showMessage(message);
    };
    settingsService.onSettingChanged = () {
      setState(() => {});
    };
    _setupHotKey();
    initTray();
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

  Future<HotKey> _setupCustomHotKey(
      String settingKey, HotKey defaultHotKey, Function() handler) async {
    String? shortcut = await settingsService.getShortcut(settingKey);
    HotKey hotKey;

    if (shortcut != null && shortcut.isNotEmpty) {
      List<String> keys = shortcut.split(' + ');
      if (keys.length == 2) {
        try {
          int primaryKeyId = int.parse(keys[0]);
          int secondaryKeyId = int.parse(keys[1]);

          LogicalKeyboardKey? primaryKey =
              LogicalKeyboardKey.findKeyByKeyId(primaryKeyId);
          LogicalKeyboardKey? secondaryKey =
              LogicalKeyboardKey.findKeyByKeyId(secondaryKeyId);

          if (primaryKey != null && secondaryKey != null) {
            hotKey = HotKey(
              key: secondaryKey,
              modifiers: [_convertToHotKeyModifier(primaryKey)],
              scope: HotKeyScope.system,
            );
          } else {
            throw Exception('Invalid key found');
          }
        } catch (e) {
          print('Error parsing hotkey for $settingKey: $e');
          hotKey = defaultHotKey;
        }
      } else {
        hotKey = defaultHotKey;
      }
    } else {
      hotKey = defaultHotKey;
    }

    await hotKeyManager
        .register(
      hotKey,
      keyDownHandler: (_) => handler(),
    )
        .catchError((error) {
      print('Failed to register hotkey for $settingKey: $error');
    });

    return hotKey;
  }

  void _setupHotKey() async {
    await hotKeyManager.unregisterAll();

    _hotKey = await _setupCustomHotKey(
      SettingsService.TRIGGER_RECORD,
      _getDefaultHotKey(),
      _recorderService.toggleRecording,
    );
  }

  void _setupScreenshotHotKey() async {
    _screenshotHotKey = await _setupCustomHotKey(
      SettingsService.SCREENSHOT,
      _getDefaultScreenshotHotKey(),
      () => _screenshotService
          .captureAndCropScreenshot(navigatorKey.currentContext!),
    );
  }

  HotKey _getDefaultHotKey() {
    return HotKey(
      key: PhysicalKeyboardKey.keyW,
      modifiers: [HotKeyModifier.alt],
      scope: HotKeyScope.system,
    );
  }

  HotKey _getDefaultScreenshotHotKey() {
    return HotKey(
      key: PhysicalKeyboardKey.keyC,
      modifiers: [HotKeyModifier.alt],
      scope: HotKeyScope.system,
    );
  }

  HotKeyModifier _convertToHotKeyModifier(LogicalKeyboardKey key) {
    if (key == LogicalKeyboardKey.control ||
        key == LogicalKeyboardKey.controlLeft ||
        key == LogicalKeyboardKey.controlRight) {
      return HotKeyModifier.control;
    } else if (key == LogicalKeyboardKey.alt ||
        key == LogicalKeyboardKey.altLeft ||
        key == LogicalKeyboardKey.altRight) {
      return HotKeyModifier.alt;
    } else if (key == LogicalKeyboardKey.shift ||
        key == LogicalKeyboardKey.shiftLeft ||
        key == LogicalKeyboardKey.shiftRight) {
      return HotKeyModifier.shift;
    } else if (key == LogicalKeyboardKey.meta ||
        key == LogicalKeyboardKey.metaLeft ||
        key == LogicalKeyboardKey.metaRight) {
      return HotKeyModifier.meta;
    } else {
      throw Exception('Unsupported modifier key');
    }
  }

  void _onYearMonthSelected({int? year, int? month}) {
    if (year == null && month == null) {
      setState(() {
        showAllRecordings = true; // Set flag to true when "All" is selected
      });
      getRecordings(); // Call to get all recordings
    } else {
      setState(() {
        showAllRecordings =
            false; // Reset flag when specific year/month is selected
        if (year != null) {
          selectedYear = year;
        }
        if (month != null) {
          selectedMonth = month;
        }
      });
      getRecordingsByMonth(
          selectedMonth, selectedYear); // Call to get recordings by month/year
    }
  }

  void getRecordings() async {
    recordLogs = await DatabaseHelper().getRecordings();
    _filterRecords();
  }

  void getRecordingsByMonth(int month, int year) async {
    recordLogs = await DatabaseHelper().getRecordingsByMonth(month, year);
    _filterRecords();
  }

  void _handleScreenshotHotKey() {
    if (_recorderService.isRecording) {
      _setupScreenshotHotKey();
    } else {
      _unregisterScreenshotHotKey();
    }
  }

  void _unregisterScreenshotHotKey() async {
    try {
      hotKeyManager.unregister(_screenshotHotKey).catchError((error) {
        print('Failed to unregister screenshot hotkey: $error');
      });
    } catch (e) {
      print('Failed to unregister screenshot hotkey: $e');
    }
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
      return;
    }

    final settingsChanged = await navigatorKey.currentState!.push<bool>(
      MaterialPageRoute(
        builder: (context) => SettingsPage(),
        settings: RouteSettings(name: SettingsPage.routeName),
      ),
    );

    if (settingsChanged == true) {
      _reloadSettings();
    }
  }

  void _reloadSettings() async {
    // 重新加载设置
    _setupHotKey();
    _setupScreenshotHotKey();
    // 如果有其他需要更新的设置，也在这里更新
    setState(() {}); // 触发 UI 重建
  }

  Future<void> showChatPage(
      List<RecordResult> recordLogs, String initialText) async {
    if (navigatorKey.currentState == null) return;

    var currentRoute = ModalRoute.of(navigatorKey.currentContext!);

    if (currentRoute != null &&
        currentRoute.settings.name == ChatPage.routeName) {
      // 如果当前顶部已是 ChatPage，则不执行任何操作
      return;
    }

    // 推送 ChatPage 到 Navigator
    navigatorKey.currentState!.push(MaterialPageRoute(
      builder: (context) =>
          ChatPage(recordLogs: recordLogs, initialText: initialText),
      settings: RouteSettings(name: ChatPage.routeName),
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

  void deleteRecording(int recordId) {
    RecordResult record = recordLogs.firstWhere((r) => r.id == recordId);
    recordLogs.remove(record);
    _filterRecords();
    print('Delete Recording Id - $recordId');
    DatabaseHelper().deleteRecording(recordId);
    setState(() {});
  }

  void shareRecording(RecordResult recordResult) {
    final String content =
        "Recording on ${recordResult.timestamp}:\nOriginal Text: ${recordResult.originalText}\nProcessed Text: ${recordResult.processedText}";
    Share.share(content);
  }

  void saveRecordResult(RecordResult recordResult) {
    setState(() {
      int index = recordLogs.indexWhere((r) => r.id == recordResult.id);
      if (index != -1) {
        recordLogs[index].originalText = recordResult.originalText;
        recordLogs[index].processedText = recordResult.processedText;
        DatabaseHelper().updateRecording(recordLogs[index]);
      }
    });
    _filterRecords();
    print(
        'Saved: Original Text = ${recordResult.originalText}, Processed Text = ${recordResult.processedText}');
  }

  void saveWhisperPrompt(RecordResult recordResult, int originalIndex) async {
    await DatabaseHelper().updateRecording(recordResult);
    _recorderService.rerun(recordResult, originalIndex);
    setState(() {});
    print('Saved: whisperPrompt = ${recordResult.whisperPrompt}');
  }

  void editRecording(RecordResult recordResult) {
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
          ),
          actions: <Widget>[
            TextButton(
              child: const Text("Save"),
              onPressed: () {
                recordResult.originalText = textEditingController.text;
                saveRecordResult(recordResult); // Use the updated method
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

  void _filterRecords() {
    setState(() {
      if (searchKeyword.isEmpty) {
        filteredRecordLogs = recordLogs.asMap().entries.toList();
      } else {
        filteredRecordLogs = recordLogs
            .asMap()
            .entries
            .where((entry) =>
                entry.value.originalText.contains(searchKeyword) ||
                entry.value.processedText.contains(searchKeyword))
            .toList();
      }
      // Sort the filtered records by timestamp in descending order (newest first)
      filteredRecordLogs
          .sort((a, b) => b.value.timestamp.compareTo(a.value.timestamp));
    });
  }

  void toggleSearchBar() {
    setState(() {
      isSearchBarVisible = !isSearchBarVisible;
      if (isSearchBarVisible) {
        searchController.text = searchKeyword;
      }
    });
  }

  void hideSearchBar() {
    setState(() {
      isSearchBarVisible = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_isInitializing) {
      return Center(
        child: SizedBox(
          width: 50, // Set the width of the loading indicator
          height: 50, // Set the height of the loading indicator
          child:
              CircularProgressIndicator(), // Show loading indicator while initializing
        ),
      );
    }
    return GestureDetector(
        onTap: hideSearchBar,
        child: MaterialApp(
          navigatorKey: navigatorKey,
          title: 'Flutter Audio Recorder',
          theme: ThemeData(
            primarySwatch: Colors.blue,
            useMaterial3: true,
          ),
          scaffoldMessengerKey: _scaffoldMessengerKey,
          home: Scaffold(
              appBar: AppBar(
                title: Row(children: [
                  Text(widget.title),
                  Spacer(),
                  IconButton(
                    icon: Icon(Icons.search),
                    onPressed: toggleSearchBar,
                  ),
                  if (!isSearchBarVisible && searchKeyword.isNotEmpty)
                    Text(
                      'Results for "$searchKeyword"',
                      style: TextStyle(fontSize: 16),
                    ),
                  IconButton(
                    icon: Icon(Icons.chat),
                    onPressed: () {
                      if (!isSettingsDialogOpen) {
                        showChatPage(recordLogs,
                            "Ask anything with your past chat logs, example - Any meeting mentioned about Meeting Noter?");
                      }
                    },
                  ),
                  IconButton(
                    icon: Icon(Icons.settings),
                    onPressed: () {
                      if (!isSettingsDialogOpen) {
                        showSettingsDialog();
                      }
                    },
                  ),
                ]),
                bottom: PreferredSize(
                  preferredSize: Size.fromHeight(isSearchBarVisible ? 48.0 : 0),
                  child: isSearchBarVisible
                      ? Padding(
                          padding: const EdgeInsets.all(8.0),
                          child: TextField(
                            controller: searchController,
                            onChanged: (value) {
                              setState(() {
                                searchKeyword = value;
                                _filterRecords();
                              });
                            },
                            decoration: InputDecoration(
                              hintText: 'Search...',
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8.0),
                              ),
                              filled: true,
                              fillColor: Colors.white,
                            ),
                          ),
                        )
                      : SizedBox.shrink(),
                ),
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
                      if (filePath.endsWith('.mp4') ||
                          filePath.endsWith('.wav') ||
                          filePath.endsWith('.mp3') ||
                          filePath.endsWith('.mov') ||
                          filePath.endsWith('.m4a')) {
                        _recorderService
                            .stopRecording(details.files.first.path);
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
                                        width:
                                            20, // Specify the width of the box
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
                          Row(
                            children: [
                              Text('Show All'),
                              Checkbox(
                                value: showAllRecordings,
                                onChanged: (bool? value) {
                                  setState(() {
                                    showAllRecordings = value ?? false;
                                    if (showAllRecordings) {
                                      getRecordings(); // Call to get all recordings
                                    } else {
                                      getRecordingsByMonth(
                                          selectedMonth, selectedYear);
                                    }
                                  });
                                },
                              ),
                              if (!showAllRecordings) ...[
                                Text('Year:'),
                                DropdownButton<int>(
                                  value: selectedYear,
                                  onChanged: (int? year) =>
                                      _onYearMonthSelected(year: year),
                                  items: [
                                    DropdownMenuItem<int>(
                                      value: null,
                                      child: Text('All'), // Add "All" option
                                    ),
                                    ...List.generate(DateTime.now().year - 2022,
                                            (index) => 2023 + index)
                                        .map((int year) {
                                      return DropdownMenuItem<int>(
                                        value: year,
                                        child: Text(year.toString()),
                                      );
                                    }).toList(),
                                  ],
                                ),
                                // Show month dropdown only if not "All"
                                Text('Month:'),
                                DropdownButton<int>(
                                  value: selectedMonth,
                                  onChanged: (int? month) =>
                                      _onYearMonthSelected(month: month),
                                  items: List.generate(12, (index) => index + 1)
                                      .map((int month) {
                                    return DropdownMenuItem<int>(
                                      value: month,
                                      child: Text(month.toString()),
                                    );
                                  }).toList(),
                                ),
                              ]
                            ],
                          ),
                          Expanded(
                            child: ListView.builder(
                              itemCount: filteredRecordLogs.length,
                              itemBuilder: (context, index) {
                                int originalIndex =
                                    filteredRecordLogs[index].key;
                                RecordResult recordResult =
                                    filteredRecordLogs[index].value;

                                // 创建控制器和焦点节点
                                TextEditingController originalTextController =
                                    TextEditingController(
                                        text: recordResult.originalText);
                                FocusNode originalTextFocusNode = FocusNode();
                                TextEditingController processedTextController =
                                    TextEditingController(
                                        text: recordResult.processedText);
                                TextEditingController whisperPromptController =
                                    TextEditingController(
                                        text: recordResult.whisperPrompt);
                                FocusNode processedTextFocusNode = FocusNode();
                                bool isRecordProcessed =
                                    !(recordResult.processedText == null ||
                                        recordResult.processedText.isEmpty);

                                // 添加焦点监听器
                                originalTextFocusNode.addListener(() {
                                  if (!originalTextFocusNode.hasFocus) {
                                    // 更新数据并保存
                                    recordResult.originalText =
                                        originalTextController.text;
                                    saveRecordResult(recordResult);
                                  }
                                });

                                processedTextFocusNode.addListener(() {
                                  if (!processedTextFocusNode.hasFocus) {
                                    // 更新数据并保存
                                    recordResult.processedText =
                                        processedTextController.text;
                                    saveRecordResult(recordResult);
                                  }
                                });

                                return Card(
                                  elevation: 4.0,
                                  margin: EdgeInsets.symmetric(
                                      horizontal: 10.0, vertical: 6.0),
                                  child: ExpansionTile(
                                    title: isRecordProcessed
                                        ? Text('${recordResult.timestamp}')
                                        : Row(
                                            mainAxisAlignment:
                                                MainAxisAlignment.spaceBetween,
                                            children: [
                                              Expanded(
                                                child: Text(
                                                  '${recordResult.timestamp} - This recording has not been processed completely.',
                                                  style: TextStyle(
                                                      color: Colors.red),
                                                ),
                                              ),
                                              IconButton(
                                                onPressed: () {
                                                  _recorderService.rerun(
                                                      recordResult,
                                                      recordResult.id!);
                                                },
                                                icon: Icon(Icons.refresh,
                                                    color: Colors.blue),
                                              ),
                                              IconButton(
                                                onPressed: () {
                                                  deleteRecording(
                                                      recordResult.id!);
                                                },
                                                icon: Icon(Icons.delete,
                                                    color: Colors.red),
                                              ),
                                            ],
                                          ),
                                    subtitle: isRecordProcessed
                                        ? Text(
                                            recordResult.processedText.length >
                                                    50
                                                ? '${recordResult.processedText.substring(0, 50)}...'
                                                : recordResult.processedText,
                                          )
                                        : null,
                                    backgroundColor: Colors.grey[200],
                                    children: !isRecordProcessed
                                        ? []
                                        : <Widget>[
                                            ExpansionTile(
                                                title: const Text(
                                                  '細節內容',
                                                  style: TextStyle(
                                                    fontSize: 20, // 更大的字体尺寸
                                                    fontWeight:
                                                        FontWeight.bold, // 加粗字体
                                                  ),
                                                ),
                                                children: <Widget>[
                                                  ExpansionTile(
                                                    title: Row(
                                                      children: [
                                                        const Expanded(
                                                          child: Text(
                                                            '原始檔文字',
                                                            style: TextStyle(
                                                                fontSize: 18,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .bold,
                                                                color: Colors
                                                                    .black87),
                                                          ),
                                                        ),
                                                        IconButton(
                                                          icon: Icon(Icons.copy,
                                                              size: 20),
                                                          onPressed: () {
                                                            Clipboard.setData(
                                                                ClipboardData(
                                                                    text: recordResult
                                                                        .originalText));
                                                            ScaffoldMessenger
                                                                    .of(context)
                                                                .showSnackBar(
                                                              SnackBar(
                                                                  content: Text(
                                                                      '原始文字已複製到剪貼板')),
                                                            );
                                                          },
                                                        ),
                                                      ],
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
                                                        cursorColor:
                                                            Colors.blue,
                                                        decoration:
                                                            InputDecoration(
                                                          border: InputBorder
                                                              .none, // 边框，根据需要选择合适的边框样式
                                                        ),
                                                        maxLines: null, // 允许无限行
                                                      ),
                                                    ],
                                                  ),
                                                  buildPromptDropdown(
                                                      recordResult.promptText,
                                                      _recorderService
                                                          .getPrompts(),
                                                      (selectedPrompt) {
                                                    setState(() {
                                                      recordResult.promptText =
                                                          selectedPrompt; // Update the current prompt text
                                                      _recorderService
                                                          .handleExistingPrompt(
                                                              selectedPrompt,
                                                              recordResult,
                                                              recordResult.id!);
                                                    });
                                                  }),
                                                  if (recordResult.filePath !=
                                                          null &&
                                                      recordResult
                                                          .filePath!.isNotEmpty)
                                                    ListTile(
                                                      title: const Text(
                                                        '專有詞修正（Optional -  會覆蓋 default settings)',
                                                        style: TextStyle(
                                                            fontSize: 15,
                                                            fontWeight:
                                                                FontWeight.bold,
                                                            color:
                                                                Colors.black87),
                                                      ),
                                                      subtitle: TextField(
                                                        controller:
                                                            whisperPromptController,
                                                        style: TextStyle(
                                                            color: Colors.black,
                                                            fontSize: 16),
                                                        cursorColor:
                                                            Colors.blue,
                                                        decoration:
                                                            InputDecoration(
                                                          border:
                                                              OutlineInputBorder(), // Use an outline border
                                                          hintText:
                                                              'ex: LIAM HUB, IAM',
                                                        ),
                                                        maxLines: null,
                                                      ),
                                                      trailing: IconButton(
                                                        icon:
                                                            Icon(Icons.refresh),
                                                        onPressed: () {
                                                          String whisperPrompt =
                                                              whisperPromptController
                                                                  .text;
                                                          recordResult
                                                                  .whisperPrompt =
                                                              whisperPrompt;
                                                          saveWhisperPrompt(
                                                              recordResult,
                                                              recordResult.id!);
                                                        },
                                                      ),
                                                    ),
                                                  ListTile(
                                                    title: const Text(
                                                      'AI整理檔案（可編輯）',
                                                      style: TextStyle(
                                                          fontSize: 18,
                                                          fontWeight:
                                                              FontWeight.bold,
                                                          color:
                                                              Colors.black87),
                                                    ),
                                                    subtitle: Container(
                                                      padding:
                                                          EdgeInsets.all(8.0),
                                                      decoration: BoxDecoration(
                                                        border: Border.all(
                                                            color: Colors.grey),
                                                        borderRadius:
                                                            BorderRadius
                                                                .circular(5),
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
                                                  ),
                                                ]),
                                            if (!processedTextFocusNode
                                                .hasFocus)
                                              ListTile(
                                                title: const Text(
                                                  '會議總結',
                                                  style: TextStyle(
                                                    fontSize: 20, // 更大的字体尺寸
                                                    fontWeight:
                                                        FontWeight.bold, // 加粗字体
                                                  ),
                                                ),
                                                subtitle: Container(
                                                  padding: EdgeInsets.all(8.0),
                                                  child: MarkdownBody(
                                                    data:
                                                        processedTextController
                                                            .text,
                                                  ),
                                                ),
                                              ),
                                            Row(
                                              mainAxisAlignment:
                                                  MainAxisAlignment.end,
                                              children: [
                                                IconButton(
                                                  icon: Icon(Icons.chat),
                                                  onPressed: () {
                                                    // Navigate to chat page with the current record
                                                    showChatPage([
                                                      recordResult
                                                    ], "${recordResult.processedText.substring(0, 100)}... \n\n\n Ask anything detail about this meeting");
                                                  },
                                                ),
                                                IconButton(
                                                  icon: Icon(Icons.share),
                                                  onPressed: () {
                                                    // 分享操作
                                                    shareRecording(
                                                        recordResult);
                                                  },
                                                ),
                                                IconButton(
                                                  icon:
                                                      Icon(Icons.content_copy),
                                                  onPressed: () {
                                                    copyRecording(recordResult);
                                                  },
                                                ),
                                                IconButton(
                                                  icon: Icon(Icons.delete),
                                                  onPressed: () {
                                                    // 删除操作
                                                    deleteRecording(
                                                        recordResult.id!);
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
                  ]))),
          routes: {
            SettingsPage.routeName: (context) => SettingsPage(),
            ChatPage.routeName: (context) =>
                ChatPage(recordLogs: recordLogs, initialText: ''),
          },
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

Widget buildPromptDropdown(String? currentPrompt, List<PromptItem> prompts,
    Function(String) onSelected) {
  // Handle case when prompts are empty
  if (prompts.isEmpty) {
    currentPrompt = null;
  } else {
    // Ensure currentPrompt is in the list of prompts
    bool promptExists =
        prompts.any((PromptItem prompt) => prompt.prompt == currentPrompt);
    if (!promptExists) {
      currentPrompt = null;
    }
  }

  return DropdownMenu<PromptItem>(
    initialSelection: currentPrompt != null
        ? prompts
            .firstWhere((PromptItem prompt) => prompt.prompt == currentPrompt)
        : null,
    onSelected: (PromptItem? newValue) {
      if (newValue != null) {
        onSelected(newValue.prompt);
      }
    },
    dropdownMenuEntries: [
      DropdownMenuEntry<PromptItem>(
        value: PromptItem(name: 'Select a prompt...', prompt: ''),
        label: 'Select a prompt...', // Default non-selectable item
        enabled: false, // Make it non-selectable
      ),
      ...prompts.map((PromptItem prompt) {
        return DropdownMenuEntry<PromptItem>(
          value: prompt,
          label: prompt.name,
        );
      }).toList()
    ],
  );
}
