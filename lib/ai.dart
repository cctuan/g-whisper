import 'dart:convert';
import 'dart:io';
import 'package:g_whisper/PromptItem.dart';
import 'package:http/http.dart' as http;
import 'package:langchain/langchain.dart';
import 'package:langchain_openai/langchain_openai.dart';
import 'package:langchain_ollama/langchain_ollama.dart';

typedef StatusUpdateCallback = void Function(String status);

class LlmOptions {
  String? apiKey;
  String? apiUrl;
  String? model;
  String? openAiModel;
  String? customLlmModel;
  String? customLlmUrl;
  String? huggingfaceToken;
  String? huggingfaceGguf;
  String? openaiCompletionBaseUrl;
  String? openaiAudioBaseUrl;
  LlmOptions(
      {this.apiKey,
      this.apiUrl,
      this.model,
      this.openAiModel,
      this.customLlmModel,
      this.customLlmUrl,
      this.huggingfaceToken,
      this.huggingfaceGguf,
      this.openaiCompletionBaseUrl,
      this.openaiAudioBaseUrl});
}

class LlmService {
  final String llamaCliPath;
  final Directory tempDir;
  Process? _currentProcess;
  StatusUpdateCallback? onStatusUpdateCallback;

  LlmService({required this.llamaCliPath, required this.tempDir});

  Future<String> callLlm(PromptItem promptItem, String content,
      String llmChoice, LlmOptions config, onStatusUpdateCallback) async {
    String prompt = promptItem.prompt;
    if (llmChoice == 'openai') {
      if (!prompt.contains('{topic}')) {
        prompt = '{topic}\n$prompt';
      }
      return await callOpenAI(config, prompt, content, promptItem);
    } else if (llmChoice == 'ollama') {
      if (!prompt.contains('{topic}')) {
        prompt = '{topic}\n$prompt';
      }
      return await callOllama(
          config.apiUrl ?? '', config.model ?? 'llama3', prompt, content);
    } else if (llmChoice == 'custom') {
      return await callCustomLlm(config.customLlmUrl ?? '',
          config.customLlmModel ?? '', prompt, content);
    } else if (llmChoice == 'llama_cpp') {
      return await callLocalLlama(config.huggingfaceToken ?? '',
          config.huggingfaceGguf ?? '', prompt, content);
    } else {
      throw Exception('Invalid LLM choice');
    }
  }

  Future<void> downloadModel(
      File modelFile, String huggingfaceToken, String huggingfaceGguf) async {
    final uri = Uri.https('huggingface.co', huggingfaceGguf);
    onStatusUpdateCallback?.call('Downloading $uri...');
    print('Downloading $uri...\n');

    var client = http.Client();
    final request = http.Request('GET', uri);
    request.headers['Authorization'] = 'Bearer $huggingfaceToken';
    var response = await client.send(request);

    if (response.statusCode >= 300) {
      final responseBody = await response.stream.bytesToString();
      onStatusUpdateCallback?.call('Failed to download file: $responseBody');
      throw Exception('Failed to download file: $responseBody');
    }

    var writer = modelFile.openWrite();
    await response.stream.pipe(writer);
    await writer.close();
    onStatusUpdateCallback?.call(
        'Downloaded ${modelFile.path} (${response.contentLength} bytes)\n');
    print('Download ${modelFile.path} (${response.contentLength} bytes)\n');
  }

  Future<String> callLocalLlama(String huggingfaceToken, String huggingfaceGguf,
      String prompt, String content) async {
    File modelFile = File('${tempDir.path}/llama.gguf');
    if (!await modelFile.exists()) {
      await downloadModel(modelFile, huggingfaceToken, huggingfaceGguf);
    }

    onStatusUpdateCallback?.call('Running local llama...');
    var result = await _runCommand(
        llamaCliPath, ['-m', modelFile.path, '-p', '$content\n$prompt']);
    if (result.exitCode == 0) {
      print(result.stdout);
      return result.stdout;
    } else {
      throw Exception('Failed to run local llama: ${result.stderr}');
    }
  }

  Future<ProcessResult> _runCommand(String command, List<String> args) async {
    print("\$ $command ${args.join(' ')}\n");
    _currentProcess = await Process.start(command, args);
    var stdout = '';
    var stderr = '';
    _currentProcess!.stderr.transform(utf8.decoder).forEach((line) {
      stderr += line;
    });
    _currentProcess!.stdout.transform(utf8.decoder).forEach((line) {
      stdout += line;
    });

    var exitCode = await _currentProcess!.exitCode;
    return ProcessResult(_currentProcess!.pid, exitCode, stdout, stderr);
  }

  void killCurrentProcess() {
    if (_currentProcess != null) {
      _currentProcess!.kill();
      _currentProcess = null;
      print('Process terminated.');
    } else {
      print('No running process to terminate.');
    }
  }

  Future<String> callCustomLlm(
      String apiUrl, String modelName, String prompt, String topic) async {
    final String fullUrl = '$apiUrl/$modelName/completions';
    final Map<String, dynamic> body = {
      'model': modelName,
      'prompt': '$topic\n$prompt',
    };
    final http.Response response = await http.post(
      Uri.parse(fullUrl),
      headers: <String, String>{
        'Content-Type': 'application/json; charset=utf-8',
      },
      body: utf8.encode(jsonEncode(body)),
    );

    if (response.statusCode == 200) {
      final Map<String, dynamic> responseBody =
          jsonDecode(utf8.decode(response.bodyBytes));
      final String result = responseBody['choices'][0]['text'];
      print(result);
      return result;
    } else {
      throw Exception('Failed to load data');
    }
  }

  ChatOpenAI getModel(LlmOptions config) {
    if (config.openaiCompletionBaseUrl != null &&
        config.openaiCompletionBaseUrl!.isNotEmpty) {
      return ChatOpenAI(
        apiKey: config.apiKey,
        baseUrl: config.openaiCompletionBaseUrl!,
        defaultOptions: ChatOpenAIOptions(
          model: config.openAiModel ?? "gpt-4o-mini",
        ),
      );
    } else {
      return ChatOpenAI(
        apiKey: config.apiKey,
        defaultOptions: ChatOpenAIOptions(
          model: config.openAiModel ?? "gpt-4o-mini",
        ),
      );
    }
  }

  Future<String> callOpenAI(LlmOptions config, String prompt, String content,
      PromptItem promptItem) async {
    int chunkSize = 3000; // Default chunk size for GPT-3.5
    int chunkOverlap = 200;

    if (config.openAiModel != null && config.openAiModel!.startsWith('gpt-4')) {
      chunkSize = 60000; // GPT-4 can handle larger texts
    }
    if (promptItem.enableChapter) {
      return await processVideoSubtitles(config, prompt, content);
    } else {
      ChatOpenAI model = getModel(config);
      RecursiveCharacterTextSplitter textSplitter =
          RecursiveCharacterTextSplitter(
              chunkSize: chunkSize, chunkOverlap: chunkOverlap);
      final texts = textSplitter.splitText(content);
      final docs = textSplitter.createDocuments(texts);

      // Decide based on content length
      if (content.length <= chunkSize) {
        return await callSingleChain(model, docs, prompt);
      } else {
        return await callSummarizeChain(model, docs, prompt);
      }
    }
  }

  Future<String> processVideoSubtitles(
      LlmOptions config, String prompt, String subtitles) async {
    // Step 1: Extract chapters using function calling
    List<Map<String, String>> chapters =
        await extractChapters(config, subtitles, prompt);

    // Step 2: Summarize each chapter
    String summarizedContent =
        await summarizeChapters(config, chapters, prompt);

    return summarizedContent;
  }

  Future<List<Map<String, String>>> extractChapters(
      LlmOptions config, String subtitles, String prompt) async {
    final model = getModel(config);
    const chapterTool = ToolSpec(
        name: "extract_chapters",
        description: "Extract chapters from video subtitles",
        inputJsonSchema: {
          "type": "object",
          "properties": {
            "chapters": {
              "type": "array",
              "items": {
                "type": "object",
                "properties": {
                  "chapter": {
                    "type": "string",
                    "description": "Title of the chapter"
                  },
                  "context": {
                    "type": "string",
                    "description":
                        "Full transcript of all subtitles within this chapter"
                  },
                  "time": {
                    "type": "string",
                    "description":
                        "Start time of the chapter in HH:MM:SS format, exactly matching a timestamp from the subtitles"
                  }
                },
                "required": ["chapter", "context", "time"]
              }
            }
          },
          "required": ["chapters"]
        });

    final chain = model.bind(ChatOpenAIOptions(
        tools: [chapterTool],
        toolChoice: ChatToolChoice.forced(name: 'extract_chapters')));

    final res = await chain.invoke(
      PromptValue.string('''
You are an expert at structuring information into meaningful, interconnected chapters with appropriate titles and accurate start times.

Your task is to analyze the given subtitles and extract distinct chapters. Follow these guidelines carefully:

1. Identify natural breaks or topic changes in the content to determine chapter boundaries.
2. Create a title for each chapter that accurately reflects its main topic or theme.
3. Set the start time (time) for each chapter to the exact timestamp of the first subtitle in that chapter. The time must be in HH:MM:SS format and must match a timestamp from the subtitles exactly.
4. Include ALL subtitles from the start of the chapter up to (but not including) the start of the next chapter in the context field. The context should be the full, unaltered text of these subtitles.
5. Ensure that every subtitle is included in exactly one chapter, with no overlap or omissions between chapters.
6. Aim for chapters of roughly similar length, but prioritize coherence and natural topic divisions over strict uniformity.
7. The first chapter should start at the beginning of the subtitles, and the last chapter should include all remaining subtitles to the end.
Remember:
- Every timestamp and subtitle must be accounted for in your chapter division.
- The 'time' field must always match an actual subtitle timestamp.
- The 'context' field must contain the complete, verbatim text of all subtitles in the chapter.
- Chapter titles should be concise but descriptive.

Additional instructions:
$prompt

Here are the subtitles to process:

$subtitles

Please analyze these subtitles and extract the chapters accordingly.
'''),
    );

    final toolCall = res.output.toolCalls.firstWhere(
      (call) => call.name == 'extract_chapters',
      orElse: () => throw Exception('No extract_chapters tool call found'),
    );

    final chaptersJson = toolCall.arguments;
    final chaptersData = chaptersJson['chapters'] as List<dynamic>;
    return chaptersData
        .map<Map<String, String>>((chapter) => {
              'chapter': chapter['chapter'] as String,
              'context': chapter['context'] as String,
              'time': chapter['time'] as String,
            })
        .toList();
  }

  Future<String> summarizeChapters(LlmOptions config,
      List<Map<String, String>> chapters, String prompt) async {
    final llm = getModel(config);

    // 並行處理所有章節
    final List<Future<String>> chapterFutures = chapters.map((chapter) async {
      try {
        final contents = await processChapter(llm, chapter, prompt);
        return contents;
      } catch (e) {
        print('Error processing chapter: ${chapter['chapter']}, Error: $e');
        return '處理章節 "${chapter['chapter']}" 時發生錯誤: $e';
      }
    }).toList();

    // 等待所有章節處理完成
    final List<String> summarizedChapters = await Future.wait(chapterFutures);

    // 將所有摘要合併為一個字符串
    return summarizedChapters.join('\n\n');
  }

  Future<String> processChapter(
      ChatOpenAI llm, Map<String, String> chapter, String prompt) async {
    try {
      final String transcript = chapter['context'] ?? '';
      final String chapterTitle = chapter['chapter'] ?? '';
      final String timestamp = chapter['time'] ?? '';

      if (transcript.isEmpty) {
        throw Exception('Empty transcript for chapter: $chapterTitle');
      }

      String systemTemplate = '''
<instructions>
Your task is to transform the given transcript into a well-structured markdown blog post or textbook chapter.
The transcript was generated by an AI speech recognition tool and may contain some errors or infelicities.
Please rewrite it using the following guidelines:
- Output valid markdown
- Compose in Traditional Chinese (zh-hant)
- Insert section headings and other formatting where appropriate
- You are given only part of a transcript, so do not include introductory or concluding paragraphs. Only include the main topics discussed in the transcript
- Use styling to make the text, code, callouts, and the page layout look like a typical blog post or textbook
- Remove any verbal tics or filler words
- If there are redundant pieces of information, only present them once
- Keep the conversational content in the style of the transcript, but make it more formal and structured
- Use headings to make the narrative structure easier to follow
- When relevant, transcribe important pieces of code and other valuable text, formatting them appropriately in markdown
- Do not add any extraneous information: only include what is mentioned in the transcript

Additional instructions:
{prompt}

Your final output should be suitable for inclusion in a textbook or professional blog, with well-organized and clearly presented content.
</instructions>
''';

      const humanTemplate = '''
章節標題：{chapter_title}
時間戳：{timestamp}

轉錄文本：
{transcript}

基於以上信息和指示，請處理這個章節的內容。確保你的輸出是一個完整的、經過精心編輯的 Markdown 格式章節。
''';

      final systemMessagePrompt =
          SystemChatMessagePromptTemplate.fromTemplate(systemTemplate);
      final humanMessagePrompt =
          HumanChatMessagePromptTemplate.fromTemplate(humanTemplate);

      final chatPrompt = ChatPromptTemplate.fromPromptMessages([
        systemMessagePrompt,
        humanMessagePrompt,
      ]);

      final chain = LLMChain(
        llm: llm,
        prompt: chatPrompt,
      );

      final res = await chain.run({
        'chapter_title': chapterTitle,
        'timestamp': timestamp,
        'transcript': transcript,
        'prompt': prompt,
      });
      String content = extractContent(res);
      print("Chapter: $chapterTitle");
      return cleanMarkdown(content);
    } catch (e) {
      print('Error processing chapter: $e');
      return '處理本章節時發生錯誤。錯誤信息：$e';
    }
  }

  String extractContent(String response) {
    // 使用正則表達式匹配 content 部分
    final contentRegex =
        RegExp(r'content:\s*(.+?)\s*(?=,\s*tool|$)', dotAll: true);
    final match = contentRegex.firstMatch(response);

    if (match != null && match.groupCount >= 1) {
      // 提取並清理 content
      String content = match.group(1)!.trim();

      // 移除開頭和結尾的引號（如果有）
      if (content.startsWith('"') && content.endsWith('"')) {
        content = content.substring(1, content.length - 1);
      }

      // 解碼可能的 JSON 轉義字符
      content = content.replaceAllMapped(
          RegExp(r'\\(.)', dotAll: true), (match) => match.group(1)!);

      return content.trim();
    }

    // 如果無法匹配，返回原始字符串
    return response.trim();
  }

  String cleanMarkdown(String markdown) {
    // 移除多餘的空行
    markdown = markdown.replaceAll(RegExp(r'\n{3,}'), '\n\n');

    // 確保標題前有空行
    markdown = markdown.replaceAllMapped(RegExp(r'(\S)(\n#+\s)'),
        (match) => '${match.group(1)}\n\n${match.group(2)}');

    // 確保代碼塊前後有空行
    markdown = markdown.replaceAllMapped(RegExp(r'(\S)(\n```)'),
        (match) => '${match.group(1)}\n\n${match.group(2)}');
    markdown = markdown.replaceAllMapped(RegExp(r'(```)(\n\S)'),
        (match) => '${match.group(1)}\n\n${match.group(2)}');

    // 移除行首和行尾的空白字符
    markdown = markdown.split('\n').map((line) => line.trim()).join('\n');

    return markdown.trim();
  }

  Future<String> callOllama(
      String apiUrl, String model, String prompt, String content) async {
    const int chunkSize = 3000; // Fixed chunk size for Ollama
    const textSplitter =
        RecursiveCharacterTextSplitter(chunkSize: chunkSize, chunkOverlap: 200);
    // Decide based on content length
    final texts = textSplitter.splitText(content * 1);
    final docs = textSplitter.createDocuments(texts);
    Ollama llm = Ollama(
      baseUrl: apiUrl,
      defaultOptions: OllamaOptions(
        model: model,
      ),
    );
    if (content.length <= chunkSize) {
      return await callSingleChain(llm, docs, prompt);
    } else {
      return await callSummarizeChain(llm, docs, prompt);
    }
  }

  Future<String> callSummarizeChain(
      dynamic llm, List<Document> docs, String prompt) async {
    ChatPromptTemplate promptTemplate = ChatPromptTemplate.fromTemplate(
      prompt,
    );
    final summarizeChain = SummarizeChain.mapReduce(
        llm: llm,
        combinePrompt: promptTemplate,
        mapPrompt: PromptTemplate.fromTemplate('''
Write a concise and detail summary of the following text. 
Avoid unnecessary info. Write at profession level.
"{context}"
CONCISE SUMMARY:'''));

    final result = await summarizeChain.run(docs);
    return result;
  }

  Future<String> callSingleChain(
      dynamic llm, List<Document> docs, String prompt) async {
    ChatPromptTemplate promptTemplate = ChatPromptTemplate.fromTemplate(
      prompt,
    );

    final summarizeChain =
        SummarizeChain.stuff(llm: llm, promptTemplate: promptTemplate);
    final result = await summarizeChain.run(docs);
    return result;
  }
}
