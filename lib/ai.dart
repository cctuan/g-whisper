import 'package:langchain/langchain.dart';
import 'package:langchain_openai/langchain_openai.dart';
import 'package:langchain_ollama/langchain_ollama.dart';

class LlmOptions {
  String? apiKey;
  String? apiUrl;
  String? model;
  String? openAiModel;
  LlmOptions({this.apiKey, this.apiUrl, this.model, this.openAiModel});
}

class LlmService {
  LlmService() {}

  Future<String> callLlm(
      String prompt, String content, bool useOpenAi, LlmOptions config) async {
    if (!prompt.contains('{topic}')) {
      prompt = '{topic}\n$prompt';
    }
    if (useOpenAi) {
      return await callOpenAI(config.apiKey ?? '',
          config.openAiModel ?? 'gpt-3.5-turbo', prompt, content);
    } else {
      return await callOllama(
          config.apiUrl ?? '', config.model ?? 'llama3', prompt, content);
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
      defaultOptions: const OllamaOptions(
        model: 'llama3',
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
