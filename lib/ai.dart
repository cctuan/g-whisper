import 'package:langchain/langchain.dart';
import 'package:langchain_openai/langchain_openai.dart';

class OpenAIService {
  OpenAIService() {}

  Future<String> callLlm(String apiKey, String prompt, String topic) async {
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
}
