import 'package:langchain/langchain.dart';
import 'package:langchain_ollama/langchain_ollama.dart';

class OllamaService {
  OllamaService() {}

  Future<String> callLlm(String apiUrl, String prompt, String topic) async {
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
