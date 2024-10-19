import 'package:flutter/material.dart';
import 'package:flutter_chat_ui/flutter_chat_ui.dart';
import 'package:flutter_chat_types/flutter_chat_types.dart' as types;
import 'dart:math';
import './conversationQA.dart';
import './recordResult.dart';
import './SettingService.dart';

class ExpandableText extends StatefulWidget {
  final String text;
  final int initialLines;

  ExpandableText({required this.text, this.initialLines = 3});

  @override
  _ExpandableTextState createState() => _ExpandableTextState();
}

class _ExpandableTextState extends State<ExpandableText> {
  bool _isExpanded = false;

  void _toggleExpanded() {
    setState(() {
      _isExpanded = !_isExpanded;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          padding: EdgeInsets.symmetric(
              horizontal: 24.0, vertical: 4.0), // Add padding
          child: Text(
            widget.text,
            maxLines: _isExpanded ? null : widget.initialLines,
            overflow:
                _isExpanded ? TextOverflow.visible : TextOverflow.ellipsis,
          ),
        ),
        GestureDetector(
          onTap: _toggleExpanded,
          child: Text(
            _isExpanded ? 'Show less' : 'Show more',
            style: TextStyle(color: Colors.blue),
          ),
        ),
      ],
    );
  }
}

class ChatPage extends StatefulWidget {
  static const String routeName = '/chat';

  final List<RecordResult> recordLogs;
  final String initialText;

  const ChatPage(
      {Key? key, required this.recordLogs, required this.initialText})
      : super(key: key);

  @override
  _ChatPageState createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final SettingsService settingsService = SettingsService();
  late Map<String, dynamic> settings;
  final List<types.Message> _messages = [];
  final types.User _ai = const types.User(id: 'ai-id');
  final types.User _user = const types.User(id: 'user-id');
  late ConversationalQA conversationalQA;
  bool _isLoading = true;
  List<RecordResult> selectedRecordLogs = [];

  @override
  void initState() {
    super.initState();
    _initializeSettings();
  }

  Future<void> _initializeSettings() async {
    settings = await settingsService.loadSettings();
    await _initializeConversationalQA();
    // _loadMessages();
    setState(() {
      _isLoading = false;
    });
  }

  Future<void> _initializeConversationalQA() async {
    conversationalQA = ConversationalQA(
      settings: settings,
      recordLogs: selectedRecordLogs,
    );
    await conversationalQA.init();

    // Clear existing messages
    setState(() {
      _messages.clear();
    });

    // Add initial message based on selectedRecordLogs
    if (selectedRecordLogs.isEmpty) {
      _addMessage(types.TextMessage(
        author: _ai,
        createdAt: DateTime.now().millisecondsSinceEpoch,
        id: Random().nextInt(100000).toString(),
        text:
            "Please select records from the left panel and press 'Save Selection' to start the chat.",
      ));
    } else {
      String selectedLogsPreview = selectedRecordLogs.map((log) {
        String previewText =
            log.processedText.substring(0, min(50, log.processedText.length));
        return "${log.timestamp}\n$previewText";
      }).join('\n\n');

      _addMessage(types.TextMessage(
        author: _ai,
        createdAt: DateTime.now().millisecondsSinceEpoch,
        id: Random().nextInt(100000).toString(),
        text:
            "Chat will use the selected logs as knowledge base. Here's a preview of the selected logs:\n\n$selectedLogsPreview",
      ));
    }
  }

  void _loadMessages() {
    final textMessage = types.TextMessage(
      author: _ai,
      createdAt: DateTime.now().millisecondsSinceEpoch,
      id: Random().nextInt(100000).toString(),
      text: widget.initialText,
    );
    _messages.insert(0, textMessage);
  }

  void _addMessage(types.Message message) {
    setState(() {
      _messages.insert(0, message);
    });
  }

  Future<void> _handleSendPressed(types.PartialText message) async {
    if (_isLoading) return;
    final userMessage = types.TextMessage(
      author: _user,
      createdAt: DateTime.now().millisecondsSinceEpoch,
      id: Random().nextInt(100000).toString(),
      text: message.text,
    );

    _addMessage(userMessage);

    final response = await conversationalQA.askQuestion(message.text);

    final aiMessage = types.TextMessage(
      author: _ai,
      createdAt: DateTime.now().millisecondsSinceEpoch,
      id: Random().nextInt(100000).toString(),
      text: response['answer'],
    );

    _addMessage(aiMessage);
    // Document messages
    for (var doc in response['docs']) {
      String pageContent = doc.pageContent;
      if (doc.metadata != null && doc.metadata?['timestamp'] != null) {
        pageContent = doc.metadata?['timestamp'] + '\n' + doc.pageContent;
      }
      final docMessage = types.CustomMessage(
        author: _ai,
        createdAt: DateTime.now().millisecondsSinceEpoch,
        id: Random().nextInt(100000).toString(),
        metadata: {'pageContent': pageContent},
      );

      _addMessage(docMessage);
    }
  }

  Future<void> _updateSelectedRecordLogs(List<RecordResult> logs) async {
    setState(() {
      _isLoading = true;
      selectedRecordLogs = logs;
    });
    await _initializeConversationalQA();
    setState(() {
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Chat'),
      ),
      body: Row(
        children: [
          Expanded(
            flex: 1,
            child: RecordLogsSelector(
              recordLogs: widget.recordLogs,
              onSave: _updateSelectedRecordLogs,
            ),
          ),
          Expanded(
            flex: 2,
            child: _isLoading
                ? Center(child: CircularProgressIndicator())
                : Chat(
                    messages: _messages,
                    onSendPressed: _handleSendPressed,
                    user: _user,
                    customMessageBuilder: (types.CustomMessage customMessage,
                        {required int messageWidth}) {
                      return ExpandableText(
                        text: customMessage.metadata?['pageContent'],
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class RecordLogsSelector extends StatefulWidget {
  final List<RecordResult> recordLogs;
  final Function(List<RecordResult>) onSave;

  const RecordLogsSelector({
    Key? key,
    required this.recordLogs,
    required this.onSave,
  }) : super(key: key);

  @override
  _RecordLogsSelectorState createState() => _RecordLogsSelectorState();
}

class _RecordLogsSelectorState extends State<RecordLogsSelector> {
  List<RecordResult> selectedLogs = [];
  String searchQuery = '';

  String getContextAroundMatch(String fullText, String query) {
    // Remove whitespace and newlines
    fullText = fullText.replaceAll(RegExp(r'\s+'), ' ').trim();

    if (query.isEmpty) {
      return fullText.length > 50
          ? fullText.substring(0, 50) + '...'
          : fullText;
    }

    int matchIndex = fullText.toLowerCase().indexOf(query.toLowerCase());
    if (matchIndex == -1) {
      return fullText.length > 50
          ? fullText.substring(0, 50) + '...'
          : fullText;
    }

    int contextLength = 50;
    int queryLength = query.length;
    int remainingContext = contextLength - queryLength;
    int leftContext = remainingContext ~/ 2;
    int rightContext = remainingContext - leftContext;

    int startIndex = (matchIndex - leftContext).clamp(0, fullText.length);
    int endIndex =
        (matchIndex + queryLength + rightContext).clamp(0, fullText.length);

    // Adjust start and end to ensure we have at least 50 characters
    if (endIndex - startIndex < contextLength) {
      if (startIndex == 0) {
        endIndex = min(fullText.length, contextLength);
      } else if (endIndex == fullText.length) {
        startIndex = max(0, fullText.length - contextLength);
      }
    }

    String result = fullText.substring(startIndex, endIndex);

    // Add ellipsis if necessary
    if (startIndex > 0) result = '...' + result;
    if (endIndex < fullText.length) result = result + '...';

    return result;
  }

  @override
  Widget build(BuildContext context) {
    List<RecordResult> filteredLogs = widget.recordLogs
        .where((log) =>
            log.originalText
                .toLowerCase()
                .contains(searchQuery.toLowerCase()) ||
            log.processedText.toLowerCase().contains(searchQuery.toLowerCase()))
        .toList();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: TextField(
            decoration: InputDecoration(
              labelText: 'Search RecordLogs',
              border: OutlineInputBorder(),
            ),
            onChanged: (value) {
              setState(() {
                searchQuery = value;
              });
            },
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: filteredLogs.length,
            itemBuilder: (context, index) {
              final log = filteredLogs[index];
              String displayText;
              if (log.processedText
                  .toLowerCase()
                  .contains(searchQuery.toLowerCase())) {
                displayText =
                    getContextAroundMatch(log.processedText, searchQuery);
              } else {
                displayText =
                    getContextAroundMatch(log.originalText, searchQuery);
              }
              return ExpansionTile(
                title: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      log.timestamp,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[600],
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      displayText,
                      maxLines: 4,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('Detail'),
                    Icon(Icons.arrow_drop_down),
                  ],
                ),
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Text(
                      log.processedText
                          .substring(0, min(500, log.processedText.length)),
                      style: TextStyle(fontSize: 14),
                    ),
                  ),
                ],
                leading: Checkbox(
                  value: selectedLogs.contains(log),
                  onChanged: (bool? value) {
                    setState(() {
                      if (value == true) {
                        selectedLogs.add(log);
                      } else {
                        selectedLogs.remove(log);
                      }
                    });
                  },
                ),
              );
            },
          ),
        ),
        ElevatedButton(
          onPressed: () {
            widget.onSave(selectedLogs);
          },
          child: Text('Save Selection'),
        ),
      ],
    );
  }
}
