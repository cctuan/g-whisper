import 'package:ffmpeg_kit_flutter/ffmpeg_kit_config.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter/material.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:dart_openai/dart_openai.dart';
import 'package:intl/intl.dart';
import 'ai.dart';
import 'package:whisper/whisper_dart.dart';
import 'fileManager.dart';
import 'package:ffmpeg_kit_flutter/ffmpeg_kit.dart';
import './SettingService.dart';
import './PromptItem.dart';
import './localWhisper.dart'; // 引入 WhisperTranscriber

class RecordResult {
  String originalText;
  String processedText;
  final String timestamp;
  String promptText; // Added to store the prompt text itself

  RecordResult({
    required this.originalText,
    required this.processedText,
    required this.timestamp,
    this.promptText = '',
  });
}

class AudioPart {
  File file;
  double startTime; // Start time in seconds

  AudioPart(this.file, this.startTime);
}

typedef RecordCompleteCallback = void Function(RecordResult result,
    [int? index]);
typedef RecordAmplitudeChange = void Function(bool haVoice);
typedef StatusUpdateCallback = void Function(String status);

class RecorderService {
  Whisper whisper = Whisper();
  final AudioRecorder _recorder = AudioRecorder();
  final SettingsService settingsService = SettingsService();
  bool _isRecording = false;
  String? _recordedFilePath;
  bool _isProcessing = false;
  bool get isProcessing => _isProcessing;

  bool get isRecording => _isRecording;
  String? get recordedFilePath => _recordedFilePath;
  final llmService = LlmService();
  final fileManager = FileManager();
  WhisperTranscriber? localWhisper; // 增加本地 WhisperTranscriber
  VoidCallback? onRecordingStateChanged;
  RecordCompleteCallback? onRecordCompleteReturn;
  StatusUpdateCallback? onStatusUpdateCallback;
  RecordAmplitudeChange? onAmplitudeChange;
  Map<String, dynamic>? settings;
  double thresholdHigh = -39.0; // 高于初始值的百分比
  bool lastVolumeStatus = false;

  Future<void> init() async {
    settings = await settingsService.loadSettings();
    final hasPermission = await _recorder.hasPermission();
    final tempDir = await getTemporaryDirectory();

    String whispercppPath = await _copyAssetToAppDirectory(
        'assets/executables/whispercpp', tempDir.path);

    localWhisper = WhisperTranscriber(
        tempDir: tempDir,
        whispercppPath: whispercppPath); // 初始化本地 WhisperTranscriber

    if (settings?['use_local_whisper'] == true) {
      onStatusUpdateCallback?.call('Initializing local whisper...');
      await localWhisper
          ?.checkAndDownloadModel(settings?['local_whisper_model'] ?? 'base');
    }

    _recorder
        .onAmplitudeChanged(const Duration(milliseconds: 500))
        .listen((amp) {
      double currentAmplitude = amp.current;
      if (currentAmplitude < thresholdHigh) {
        if (lastVolumeStatus != false) {
          onAmplitudeChange?.call(false);
          lastVolumeStatus = false;
        }
      } else if (currentAmplitude > thresholdHigh) {
        if (lastVolumeStatus != true) {
          onAmplitudeChange?.call(true);
          lastVolumeStatus = true;
        }
      }
    });
    if (!hasPermission) {
      // Handle permission request here if you plan to request permissions
    }
  }

  Future<String> _copyAssetToAppDirectory(
      String assetPath, String appDirPath) async {
    final byteData = await rootBundle.load(assetPath);
    final file = File('$appDirPath/${assetPath.split('/').last}');
    await file.writeAsBytes(byteData.buffer.asUint8List());

    // Ensure the file is executable by setting the appropriate permissions
    if (Platform.isLinux || Platform.isMacOS) {
      final result = await Process.run('chmod', ['+x', file.path]);
      if (result.exitCode != 0) {
        throw Exception('Failed to set executable permissions on ${file.path}');
      }
    } else if (Platform.isWindows) {
      // Handle Windows executable permissions if needed
    }

    return file.path;
  }

  void setProcessing(bool value) {
    _isProcessing = value;
    onRecordingStateChanged?.call(); // Call this to trigger a UI rebuild
  }

  Future<void> toggleRecording() async {
    if (_isProcessing) {
      setProcessing(false);
      await cancelRecording();
      return;
    }
    if (_isRecording) {
      await stopRecording();
    } else {
      await startRecording();
    }
  }

  Future<void> startRecording() async {
    if (await _recorder.hasPermission()) {
      Directory? dir = await getTemporaryDirectory();
      String path = '${dir!.path}/record.m4a';
      await _recorder.start(
        const RecordConfig(encoder: AudioEncoder.wav),
        path: path,
      );
      _isRecording = true;
      onRecordingStateChanged?.call();
    }
  }

  Future<void> stopRecording([String? path]) async {
    if (_isRecording) {
      path = await _recorder.stop();
      _isRecording = false;
    }
    _recordedFilePath = path;
    onRecordingStateChanged?.call();
    lastVolumeStatus = false;
    if (path != null) {
      try {
        settings = await settingsService.loadSettings();
        setProcessing(true);
        onStatusUpdateCallback?.call('Transcribing audio...');
        String text;
        if (settings?['use_openai_whisper'] == false) {
          print("Transcribing audio with local whisper...");
          text = await transcribeAudioLocal(path);
          await localWhisper?.killCurrentProcess();
        } else {
          text = await transcribeAudioOpenAi(path);
        }
        print(text);
        onStatusUpdateCallback?.call('Transcribed audio successfully.');
        handleText(text);
      } catch (e) {
        // Handle the error more specifically if you can
        if (e is SocketException) {
          print(
              "Network issue when sending audio for transcription: ${e.message}");
        } else {
          print("Failed to transcribe audio: $e");
        }
        setProcessing(false);
      }
    } else {
      setProcessing(false);
      print("Recording failed to save or was cancelled.");
      onStatusUpdateCallback
          ?.call("Recording failed to save or was cancelled.");
    }
  }

  Future<void> cancelRecording() async {
    await _recorder.cancel();
    _isRecording = false;
    _recordedFilePath = null;
    onRecordingStateChanged?.call();
    setProcessing(false);
  }

  Future<String> callWhisperApi(AudioPart part) async {
    try {
      OpenAI.requestsTimeOut = Duration(minutes: 5);
      OpenAI.apiKey = settings?['openai_key'] ?? "";
      OpenAIAudioModel transcription =
          await OpenAI.instance.audio.createTranscription(
        file: part.file,
        model: "whisper-1",
        responseFormat: OpenAIAudioResponseFormat.srt,
      );
      // 删除临时文件
      part.file.deleteSync();
      // Print the transcription to the console or handle it as needed.
      return transcription.text;
    } catch (e) {
      print("Error during transcription: $e");
      return "";
    }
  }

  Future<String> transcribeAudioOpenAi(String filePath) async {
    try {
      onStatusUpdateCallback?.call("Transcribing audio with whisper...");
      File audioFile = File(filePath);
      int fileSizeInBytes = await audioFile.length();
      double fileSizeInMB = fileSizeInBytes / (1024 * 1024);
      int numberOfParts = (fileSizeInMB / 10).ceil();
      // 切割檔案
      List<AudioPart> files =
          await splitAudioFile(filePath, numberOfParts); // 2 MB

      List<String> transcriptions = [];
      List<Future<String>> transcriptionFutures = files.map((part) async {
        String transcriptionText = await callWhisperApi(part);
        return adjustTimestamps(transcriptionText, part.startTime, 0);
      }).toList();

      List<String> results = await Future.wait(transcriptionFutures);

      int srtIndex = 1; // SRT index starts at 1

      for (String transcription in results) {
        String adjustedSrt = adjustSrtIndices(transcription, srtIndex);
        transcriptions.add(adjustedSrt);

        // Update the SRT index to maintain continuity
        srtIndex += adjustedSrt
            .split('\n')
            .where((line) => line.contains('-->'))
            .length;
      }

      // 删除临时文件
      audioFile.deleteSync();

      // 合併文本
      return transcriptions.join("\n");
    } catch (e) {
      print("Error during transcription: $e");
      onStatusUpdateCallback?.call("Error during transcription: $e");
      return "";
    }
  }

  Future<String> transcribeAudioLocal(String filePath) async {
    if (localWhisper == null) {
      throw Exception("Local WhisperTranscriber is not initialized");
    }

    try {
      Directory tempDir = await getTemporaryDirectory();
      String outputSrtPath = '${tempDir.path}/transcription';
      onStatusUpdateCallback?.call('Transcribing audio locally...');
      await localWhisper!.transcribeToSrt(
          filePath, outputSrtPath, settings?['local_whisper_model'] ?? 'base');
      String srtContent = File(outputSrtPath + '.srt').readAsStringSync();
      // 删除临时文件
      File(outputSrtPath + '.srt').deleteSync();
      File(filePath).deleteSync();
      return srtContent;
    } catch (e) {
      print("Error during local transcription: $e");
      return "";
    }
  }

  String adjustSrtIndices(String srtContent, int initialIndex) {
    final lines = srtContent.split('\n');
    StringBuffer adjustedSrt = StringBuffer();
    int index = initialIndex; // 序号从initialIndex开始
    bool isNextSubtitleText = false;

    for (var i = 0; i < lines.length; i++) {
      String line = lines[i].trim();
      if (line.isEmpty) {
        continue; // 忽略空行
      }
      if (isNextSubtitleText) {
        adjustedSrt.writeln(line); // 直接写入字幕文本
        isNextSubtitleText = false; // 重置标志
        continue;
      }
      if (line.contains('-->')) {
        adjustedSrt.writeln(index.toString()); // 在时间戳前添加序号
        index++; // 序号递增
        adjustedSrt.writeln(line); // 写入时间戳
        isNextSubtitleText = true;
      }
    }

    return adjustedSrt.toString();
  }

  String adjustTimestamps(
      String srtContent, double startTime, int initialIndex) {
    final startTimeDuration = Duration(
        seconds: startTime.toInt(),
        milliseconds: ((startTime % 1) * 1000).toInt());
    final lines = srtContent.split('\n');
    StringBuffer adjustedSrt = StringBuffer();
    int index = initialIndex; // 序号从initialIndex开始
    bool isNextSubtitleText = false;

    for (var i = 0; i < lines.length; i++) {
      String line = lines[i].trim();
      if (line.isEmpty) {
        continue; // 忽略空行
      }
      if (isNextSubtitleText) {
        adjustedSrt.writeln(line); // 直接写入字幕文本
        isNextSubtitleText = false; // 重置标志
        continue;
      }
      if (line.contains('-->')) {
        adjustedSrt.writeln(index.toString()); // 在时间戳前添加序号
        index++; // 序号递增

        final timestamps = line.split('-->');
        final adjustedStart =
            _adjustSrtTime(timestamps[0].trim(), startTimeDuration);
        final adjustedEnd =
            _adjustSrtTime(timestamps[1].trim(), startTimeDuration);
        adjustedSrt.writeln('$adjustedStart --> $adjustedEnd'); // 写入调整后的时间戳
        isNextSubtitleText = true;
      }
    }

    return adjustedSrt.toString();
  }

  String _adjustSrtTime(String timestamp, Duration startTime) {
    final times = timestamp.split(':');
    final hours = int.parse(times[0]);
    final minutes = int.parse(times[1]);
    final secondsMilliseconds = times[2].split(',');
    final seconds = int.parse(secondsMilliseconds[0]);
    final milliseconds = int.parse(secondsMilliseconds[1]);

    final originalDuration = Duration(
        hours: hours,
        minutes: minutes,
        seconds: seconds,
        milliseconds: milliseconds);
    final adjustedDuration = originalDuration + startTime;

    return '${adjustedDuration.inHours.toString().padLeft(2, '0')}:${(adjustedDuration.inMinutes % 60).toString().padLeft(2, '0')}:${(adjustedDuration.inSeconds % 60).toString().padLeft(2, '0')},${(adjustedDuration.inMilliseconds % 1000).toString().padLeft(3, '0')}';
  }

  Future<List<AudioPart>> splitAudioFile(
      String filePath, int numberOfParts) async {
    List<AudioPart> parts = [];
    Directory tempDir = await getTemporaryDirectory();
    String tempPath = tempDir.path;

    // Check the file extension and convert if necessary
    String inputFilePath = filePath;
    String m4aFilePath = "$tempPath/converted_audio.m4a";
    String convertCommand =
        "-i $filePath -vn -acodec aac -ar 44100 -ac 2 $m4aFilePath -y";

    await FFmpegKit.execute(convertCommand).then((session) async {
      final returnCode = await session.getReturnCode();
      if (returnCode != null && returnCode.isValueSuccess()) {
        print("Conversion to m4a succeeded");
        inputFilePath = m4aFilePath;
      } else if (returnCode != null && returnCode.isValueError()) {
        print("Error occurred while converting mov to m4a");
        onStatusUpdateCallback
            ?.call("Error occurred while converting mov to m4a");
        return parts; // Return an empty list if conversion fails
      } else {
        print("FFmpeg process did not return a valid status for conversion");
        onStatusUpdateCallback?.call(
            "FFmpeg process did not return a valid status for conversion");
        return parts; // Return an empty list if conversion fails
      }
    });

    // Calculate the duration of each part
    double duration = await getDuration(inputFilePath);
    print('Duration: $duration');

    double partDuration = duration / numberOfParts;
    if (partDuration <= 1) {
      // Check if the duration calculation is correct
      parts.add(AudioPart(File(inputFilePath),
          0)); // Entire file as one part if duration calculation is too small
      return parts;
    }
    onStatusUpdateCallback
        ?.call("Splitting audio into $numberOfParts parts...");

    // Generate FFmpeg commands and execute
    for (int i = 0; i < numberOfParts; i++) {
      double startTime = partDuration * i;
      String outputFileName = "$tempPath/output_part_$i.m4a";
      String command =
          "-i $inputFilePath -ss $startTime -t $partDuration -c copy $outputFileName -y";

      await FFmpegKit.execute(command).then((session) async {
        final returnCode = await session.getReturnCode();
        if (returnCode != null && returnCode.isValueSuccess()) {
          print("Splitting part $i succeeded");
          parts.add(AudioPart(File(outputFileName), startTime));
        } else if (returnCode != null && returnCode.isValueError()) {
          print("Error occurred while splitting part $i");
          onStatusUpdateCallback
              ?.call("Error occurred while splitting part $i.");
        } else {
          onStatusUpdateCallback?.call(
              "FFmpeg process did not return a valid status for part $i");
          print("FFmpeg process did not return a valid status for part $i");
        }
      });
    }

    return parts;
  }

  Future<double> getDuration(String filePath) async {
    double duration = 0.0;

    await FFmpegKit.executeWithArguments(["-i", filePath, "-hide_banner"])
        .then((session) async {
      final output = await session.getOutput();
      final regex = RegExp(r"Duration: (\d+):(\d+):(\d+\.\d+)");
      if (regex.hasMatch(output ?? '')) {
        var match = regex.firstMatch(output ?? '');
        int hours = int.parse(match!.group(1)!);
        int minutes = int.parse(match.group(2)!);
        double seconds = double.parse(match.group(3)!);
        duration = hours * 3600 + minutes * 60 + seconds;
      }
    });

    return duration;
  }

  Future<String> transcribeAudio(String filePath) async {
    try {
      String binFilePath = await fileManager.ensureFileExists(
          'ggml-medium-q5_0.bin',
          'https://huggingface.co/ggerganov/whisper.cpp/resolve/main');
      print(binFilePath);
      var res = await whisper.transcribe(
        // whisperRequest: WhisperRequest.fromWavFile(
        audio: filePath,
        model: binFilePath,
        // ),
      );

      print(res);
      // 删除临时文件
      File(filePath).deleteSync();
      // Print the transcription to the console or handle it as needed.
      return res.toString();
    } catch (e) {
      print("Error during transcription: $e");
      return "";
    }
  }

  List<PromptItem> getPrompts() {
    return settings?['prompts'] ?? [];
  }

  void handleExistingPrompt(
      String prompt, RecordResult recordResult, int recordIndex) async {
    setProcessing(true);

    LlmOptions options = LlmOptions(
      apiKey: settings?['openai_key'],
      openAiModel: settings?['openai_model'],
      apiUrl: settings?['ollama_url'],
      model: settings?['ollama_model'],
    );

    final result = await llmService.callLlm(prompt ?? '',
        recordResult.originalText, settings?['use_openai_llm'], options);

    recordResult.processedText = result;
    setProcessing(false);
    onRecordCompleteReturn?.call(recordResult, recordIndex);
  }

  void handleText(String content) async {
    if (!isProcessing) {
      return;
    }
    List<PromptItem> prompts = settings?['prompts'] ?? [];
    if (prompts.isEmpty || settings == null) {
      print("Settings are not configured properly.");
      onStatusUpdateCallback?.call("Settings are not configured properly.");
      setProcessing(false);
      return;
    }
    if (settings?['use_openai_llm'] && settings?['openai_key'] == null) {
      print("Settings are not configured properly.");
      onStatusUpdateCallback?.call("Settings are not configured properly.");
      setProcessing(false);
      return;
    }
    if (settings?['use_openai_llm'] == false &&
        settings?['ollama_url'] == null) {
      print("Settings are not configured properly.");
      onStatusUpdateCallback?.call("Settings are not configured properly.");
      setProcessing(false);
      return;
    }

    int defaultPromptIndex = settings?['defaultPromptIndex'] ?? 0;
    PromptItem selectedPrompt = prompts[defaultPromptIndex];

    String promptTemplate = selectedPrompt.prompt;
    if (defaultPromptIndex! >= prompts.length) {
      print("Settings are not configured properly.");
      setProcessing(false);
      onStatusUpdateCallback?.call("Settings are not configured properly.");
      return;
    }
    LlmOptions options = LlmOptions(
      apiKey: settings?['openai_key'],
      openAiModel: settings?['openai_model'],
      apiUrl: settings?['ollama_url'],
      model: settings?['ollama_model'],
    );
    onStatusUpdateCallback?.call("Processing summary...");

    String result = await llmService.callLlm(
        promptTemplate ?? '', content, settings?['use_openai_llm'], options);

    // Create a date-time stamp
    String formattedDate =
        DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now());

    // Prepare the message string according to the specified format
    String message = '''
      $formattedDate

      會議總結內容:
      $result

      原始檔案:
      $content
      ''';
    // Print the message to console
    print(message);
    RecordResult recordResult = RecordResult(
      originalText: content,
      processedText: result,
      timestamp: formattedDate,
      promptText: promptTemplate,
    );
    setProcessing(false);
    onStatusUpdateCallback?.call("Summary processed successfully.");
    onRecordCompleteReturn?.call(recordResult);
    // Share the message
    // Share.share(message);
  }

  void dispose() {
    localWhisper?.killCurrentProcess();
    _recorder.dispose();
  }
}
