import 'package:g_whisper/ai.dart';
import 'package:langchain/langchain.dart';
import 'package:langchain_openai/langchain_openai.dart';
import './recordResult.dart';

class ChatMessageContent {
  final String content;

  ChatMessageContent(this.content);
}

class Memory {
  final List<Map<String, String>> _history = [];

  List<Map<String, String>> get history => _history;

  void addToMemory(String question, String answer) {
    _history.add({'question': question, 'answer': answer});
  }

  List<ChatMessage> getChatMessages() {
    return _history
        .map((entry) => [
              ChatMessage.humanText(entry['question'] ?? ''),
              ChatMessage.ai(entry['answer'] ?? '')
            ])
        .expand((element) => element)
        .toList();
  }

  Map<String, dynamic> loadMemoryVariables() {
    return {
      'history': getChatMessages(),
    };
  }
}

class ConversationalQA {
  final Map<String, dynamic> settings;
  final List<RecordResult> recordLogs;
  final Memory memory = Memory();
  late Runnable conversationalQaChain;

  ConversationalQA({required this.settings, required this.recordLogs});

  Future<void> init() async {
    final OpenAIEmbeddings embeddings;
    if (settings['openai_completion_base_url'] != null &&
        settings['openai_completion_base_url'].isNotEmpty) {
      embeddings = OpenAIEmbeddings(
        apiKey: settings['openai_key'],
        baseUrl: settings['openai_completion_base_url'],
      );
    } else {
      embeddings = OpenAIEmbeddings(
        apiKey: settings['openai_key'],
      );
    }
    List<Document> documents;
    // Load documents from recordLogs
    if (recordLogs.length == 1) {
      const textSplitter = CharacterTextSplitter(
        chunkSize: 1000,
        chunkOverlap: 200,
      );
      final text = recordLogs.first.originalText;
      documents = textSplitter.createDocuments(textSplitter.splitText(text));
    } else {
      const textSplitter = CharacterTextSplitter(
        chunkSize: 3000,
        chunkOverlap: 200,
      );
      documents =
          recordLogs.where((log) => log.processedText.isNotEmpty).expand((log) {
        final splitTexts = textSplitter.splitText(log.processedText);
        return splitTexts.map((splitText) => Document(
              pageContent: splitText,
              metadata: {'id': log.id, 'timestamp': log.timestamp},
            ));
      }).toList();
    }

    final docSearch = await MemoryVectorStore.fromDocuments(
      documents: documents,
      embeddings: embeddings,
    );

    // Set up retriever and model
    final retriever = docSearch.asRetriever(
      defaultOptions: const VectorStoreRetrieverOptions(
        searchType: VectorStoreSimilaritySearch(k: 3),
      ),
    );
    final ChatOpenAI model;
    if (settings['openai_completion_base_url'] != null &&
        settings['openai_completion_base_url'].isNotEmpty) {
      model = ChatOpenAI(
        apiKey: settings['openai_key'],
        baseUrl: settings['openai_completion_base_url'],
        defaultOptions: ChatOpenAIOptions(model: 'gpt-4o-mini'),
      );
    } else {
      model = ChatOpenAI(
        apiKey: settings['openai_key'],
        defaultOptions: ChatOpenAIOptions(model: 'gpt-4o-mini'),
      );
    }
    const stringOutputParser = StringOutputParser<ChatResult>();

    // Define prompts
    final condenseQuestionPrompt = ChatPromptTemplate.fromTemplate('''
    Given the following conversation and a follow up question, rephrase the follow up question to be a standalone question that includes all the details from the conversation in its original language

    Chat History:
    {chat_history}
    Follow Up Input: {question}
    Standalone question:''');

    final answerPrompt = ChatPromptTemplate.fromTemplate('''
    Answer the question based only on the following context in zh-hant:
    {context}

    Question: {question}''');

    String combineDocuments(
      final List<Document> documents, {
      final String separator = '\n\n',
    }) =>
        documents.map((final d) => d.pageContent).join(separator);

    String formatChatHistory(final List<ChatMessage> chatHistory) {
      final formattedDialogueTurns = chatHistory
          .map(
            (final msg) => switch (msg) {
              HumanChatMessage _ => 'Human: ${msg.content}',
              AIChatMessage _ => 'AI: ${msg.content}',
              _ => '',
            },
          )
          .toList();
      return formattedDialogueTurns.join('\n');
    }

    // Load memory
    final loadedMemory = Runnable.fromMap({
      'question': Runnable.getItemFromMap('question'),
      'memory': Runnable.mapInput((_) => memory.loadMemoryVariables()),
    });

    // Expand memory
    final expandedMemory = Runnable.fromMap({
      'question': Runnable.getItemFromMap('question'),
      'chat_history': Runnable.getItemFromMap('memory') |
          Runnable.mapInput<Map<String, dynamic>, List<ChatMessage>>(
            (final input) => input['history'],
          ),
    });

    // Generate standalone question
    final standaloneQuestion = Runnable.fromMap({
      'standalone_question': Runnable.fromMap({
            'question': Runnable.getItemFromMap('question'),
            'chat_history':
                Runnable.getItemFromMap<List<ChatMessage>>('chat_history') |
                    Runnable.mapInput(formatChatHistory),
          }) |
          condenseQuestionPrompt |
          model |
          stringOutputParser,
    });

    // Retrieve documents
    final retrievedDocs = Runnable.fromMap({
      'docs': Runnable.getItemFromMap('standalone_question') | retriever,
      'question': Runnable.getItemFromMap('standalone_question'),
    });

    // Construct inputs for the answer prompt
    final finalInputs = Runnable.fromMap({
      'context': Runnable.getItemFromMap('docs') |
          Runnable.mapInput<List<Document>, String>(combineDocuments),
      'question': Runnable.getItemFromMap('question'),
    });

    // Get answer
    final answer = Runnable.fromMap({
      'answer': finalInputs | answerPrompt | model | stringOutputParser,
      'docs': Runnable.getItemFromMap('docs'),
    });

    // Put it all together
    conversationalQaChain = loadedMemory |
        expandedMemory |
        standaloneQuestion |
        retrievedDocs |
        answer;
  }

  Future<Map<String, dynamic>> askQuestion(String question) async {
    final res = await conversationalQaChain.invoke({'question': question});
    // print(res);
    // Save context to memory
    memory.addToMemory(question, (res as Map<String, dynamic>)['answer'] ?? '');

    return res;
  }
}
