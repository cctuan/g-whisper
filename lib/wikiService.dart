import 'package:http/http.dart' as http;
import 'dart:convert';
import './recordResult.dart';
import './SettingService.dart';

class WikiService {
  final SettingsService _settingsService;
  late String _baseUrl;
  late String _spaceId;
  late String _token;
  late String _pageId;
  WikiService(this._settingsService);

  Future<void> initialize() async {
    var settings = await _settingsService.loadSettings();
    _baseUrl = 'https://wiki.workers-hub.com';
    _spaceId = settings['space_id'] ?? '';
    _token = settings['wiki_api_token'] ?? '';
    _pageId = settings['wiki_page_id'] ?? '';
  }

  String _formatProcessedText(String text) {
    List<String> lines = text.split('\n');
    List<String> paragraphs = lines.map((line) {
      if (line.trim().isEmpty) {
        return '<br/>';
      } else {
        return '<p>${_escapeHtml(line)}</p>';
      }
    }).toList();
    return paragraphs.join('\n');
  }

  String _escapeHtml(String text) {
    return text
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&#039;');
  }

  Future<bool> isEnabled() async {
    await initialize();

    if (_spaceId.isEmpty || _token.isEmpty || _pageId.isEmpty) {
      return false;
    }
    return true;
  }

  Future<bool> syncToWiki(RecordResult record) async {
    final isEnabled = await this.isEnabled();
    if (isEnabled == false) {
      return false;
    }

    final pageTitle = "會議記錄：${record.timestamp}";
    final formattedProcessedText = _formatProcessedText(record.processedText);

    // 檢查頁面是否存在
    final existingPage = await _getExistingPage(pageTitle);

    if (existingPage != null) {
      // 更新現有頁面
      return _updatePage(existingPage['id'], existingPage['version']['number'],
          pageTitle, record, formattedProcessedText);
    } else {
      // 創建新頁面
      return _createPage(pageTitle, record, formattedProcessedText);
    }
  }

  Future<Map<String, dynamic>?> _getExistingPage(String title) async {
    final url =
        '$_baseUrl/rest/api/content?title=${Uri.encodeComponent(title)}&spaceKey=$_spaceId&expand=version';

    final headers = {
      'Authorization': 'Bearer $_token',
      'Content-Type': 'application/json',
    };

    try {
      final response = await http.get(Uri.parse(url), headers: headers);
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['results'].isNotEmpty) {
          return data['results'][0];
        }
      }
    } catch (e) {
      print('Error checking existing page: $e');
    }
    return null;
  }

  Future<bool> _createPage(
      String title, RecordResult record, String formattedProcessedText) async {
    final url = '$_baseUrl/rest/api/content';

    final headers = {
      'Authorization': 'Bearer $_token',
      'Content-Type': 'application/json',
    };

    final content = {
      "type": "page",
      "title": title,
      "ancestors": [
        {"id": _pageId}
      ],
      "space": {"key": _spaceId},
      "body": {
        "storage": {
          "value": _generatePageContent(record, formattedProcessedText),
          "representation": "storage"
        }
      }
    };

    try {
      final response = await http.post(
        Uri.parse(url),
        headers: headers,
        body: json.encode(content),
      );

      if (response.statusCode != 200) {
        throw Exception(
            'Failed to create Wiki page. Status code: ${response.statusCode}');
      }
      return true;
    } catch (e) {
      print('Error creating Wiki page: $e');
      return false;
    }
  }

  Future<bool> _updatePage(String pageId, int version, String title,
      RecordResult record, String formattedProcessedText) async {
    final url = '$_baseUrl/rest/api/content/$pageId';

    final headers = {
      'Authorization': 'Bearer $_token',
      'Content-Type': 'application/json',
    };

    final content = {
      "type": "page",
      "title": title,
      "version": {"number": version + 1},
      "body": {
        "storage": {
          "value": _generatePageContent(record, formattedProcessedText),
          "representation": "storage"
        }
      }
    };

    try {
      final response = await http.put(
        Uri.parse(url),
        headers: headers,
        body: json.encode(content),
      );

      if (response.statusCode != 200) {
        throw Exception(
            'Failed to update Wiki page. Status code: ${response.statusCode}');
      }
      return true;
    } catch (e) {
      print('Error updating Wiki page: $e');
      return false;
    }
  }

  String _generatePageContent(
      RecordResult record, String formattedProcessedText) {
    return """
<h1>會議記錄：${record.timestamp}</h1>
<h2>原始錄音文字</h2>
<ac:structured-macro ac:name="expand">
  <ac:parameter ac:name="title">點擊查看原始錄音文字</ac:parameter>
  <ac:rich-text-body>
    <p>${_escapeHtml(record.originalText)}</p>
  </ac:rich-text-body>
</ac:structured-macro>
<h2>處理後的會議記錄</h2>
$formattedProcessedText
    """;
  }
}
