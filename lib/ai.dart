import 'dart:convert';
import 'dart:io';
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
  LlmOptions(
      {this.apiKey,
      this.apiUrl,
      this.model,
      this.openAiModel,
      this.customLlmModel,
      this.customLlmUrl,
      this.huggingfaceToken,
      this.huggingfaceGguf});
}

class LlmService {
  final String llamaCliPath;
  final Directory tempDir;
  Process? _currentProcess;
  StatusUpdateCallback? onStatusUpdateCallback;

  LlmService({required this.llamaCliPath, required this.tempDir});

  Future<String> callLlm(String prompt, String content, String llmChoice,
      LlmOptions config, onStatusUpdateCallback) async {
    if (llmChoice == 'openai') {
      if (!prompt.contains('{topic}')) {
        prompt = '{topic}\n$prompt';
      }
      return await callOpenAI(config.apiKey ?? '',
          config.openAiModel ?? 'gpt-3.5-turbo', prompt, content);
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

  Future<String> callOpenAI(
      String apiKey, String? modelType, String prompt, String content) async {
    int chunkSize = 3000; // Default chunk size for GPT-3.5
    int chunkOverlap = 200;

    if (modelType != null && modelType.startsWith('gpt-4')) {
      chunkSize = 60000; // GPT-4 can handle larger texts
    } else if (modelType != null && modelType.startsWith('gpt-3')) {
      chunkSize = 6000; // Adjusted chunk size for GPT-3 models
    }
    ChatOpenAI model = ChatOpenAI(
        apiKey: apiKey,
        defaultOptions: ChatOpenAIOptions(
          model: modelType ?? "gpt-3.5-turbo",
        ));
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
