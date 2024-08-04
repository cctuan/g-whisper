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
  final List<types.Message> _messages = [];
  final types.User _ai = const types.User(id: 'ai-id');
  final types.User _user = const types.User(id: 'user-id');
  late ConversationalQA conversationalQA;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    loadSettings();
    _loadMessages();
  }

  Future<void> loadSettings() async {
    var settings = await settingsService.loadSettings();
    conversationalQA = ConversationalQA(
      settings: settings,
      recordLogs: widget.recordLogs,
    );
    await conversationalQA.init();
    setState(() {
      _isLoading = false;
    });
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Chat'),
      ),
      body: _isLoading
          ? Center(
              child:
                  CircularProgressIndicator()) // Show a loading spinner while initializing
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
    );
  }
}
