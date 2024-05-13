import 'package:langchain/langchain.dart';
import 'package:langchain_openai/langchain_openai.dart';
import 'package:langchain_ollama/langchain_ollama.dart';

class LlmOptions {
  String? apiKey;
  String? apiUrl;
  String? model;
  LlmOptions({this.apiKey, this.apiUrl, this.model});
}

class LlmService {
  LlmService() {}

  Future<String> callLlm(
      String prompt, String content, bool useOpenAi, LlmOptions config) async {
    const textSplitter =
        RecursiveCharacterTextSplitter(chunkSize: 3000, chunkOverlap: 200);
    final texts = textSplitter.splitText(content);
    final docs = textSplitter.createDocuments(texts);
    // print('prompt $prompt \n content $content');
    if (useOpenAi) {
      return await callOpenAI(
          config.apiKey ?? '', config.model ?? '', prompt, docs);
    } else {
      return await callOllama(
          config.apiUrl ?? '', config.model ?? 'llama3', prompt, docs);
    }
  }

  Future<String> callOpenAI(
      String apiKey, String model, String prompt, List<Document> docs) async {
    // print('prompt $prompt \n content $topic');
    ChatPromptTemplate promptTemplate = ChatPromptTemplate.fromTemplate(
      prompt,
    );
    ChatOpenAI model = ChatOpenAI(apiKey: apiKey);

    final summarizeChain =
        SummarizeChain.stuff(llm: model, promptTemplate: promptTemplate);

    // RunnableSequence<Map<String, dynamic>, String> chain =
    //     promptTemplate.pipe(model).pipe(outputParser);

    final result = await summarizeChain.run(docs);
    return result;
  }

  Future<String> callOllama(
      String apiUrl, String model, String prompt, List<Document> docs) async {
    ChatPromptTemplate promptTemplate = ChatPromptTemplate.fromTemplate(
      prompt,
    );
    Ollama llm = Ollama(
      baseUrl: apiUrl,
      defaultOptions: const OllamaOptions(
        model: 'llama3',
      ),
    );
    final summarizeChain =
        SummarizeChain.stuff(llm: llm, promptTemplate: promptTemplate);

    final result = await summarizeChain.run(docs);
    return result;
  }
}
