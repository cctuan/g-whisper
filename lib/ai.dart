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
    print('prompt $prompt \n content $content');
    if (useOpenAi) {
      return await callOpenAI(
          config.apiKey ?? '', config.model ?? '', prompt, content);
    } else {
      return await callOllama(
          config.apiUrl ?? '', config.model ?? 'llama3', prompt, content);
    }
  }

  Future<String> callOpenAI(
      String apiKey, String model, String prompt, String topic) async {
    print('prompt $prompt \n content $topic');
    ChatPromptTemplate promptTemplate = ChatPromptTemplate.fromTemplate(
      prompt,
    );
    ChatOpenAI model = ChatOpenAI(apiKey: apiKey);
    StringOutputParser<ChatResult> outputParser =
        StringOutputParser<ChatResult>();

    RunnableSequence<Map<String, dynamic>, String> chain =
        promptTemplate.pipe(model).pipe(outputParser);
    final result = await chain.invoke({'topic': topic});
    return result;
  }

  Future<String> callOllama(
      String apiUrl, String model, String prompt, String topic) async {
    print('prompt $prompt \n content $topic');
    ChatPromptTemplate promptTemplate = ChatPromptTemplate.fromTemplate(
      prompt,
    );
    Ollama llm = Ollama(
      baseUrl: apiUrl,
      defaultOptions: const OllamaOptions(
        model: 'llama3',
      ),
    );
    RunnableSequence<Map<String, dynamic>, String> chain =
        promptTemplate.pipe(llm).pipe(StringOutputParser());
    final result = await chain.invoke({'topic': topic});
    print(result);
    return result;
  }
}
