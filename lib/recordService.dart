import 'dart:ffi';

import 'package:flutter/material.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:dart_openai/dart_openai.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';
import 'ai.dart';
import 'customOllama.dart';
import 'package:whisper/whisper_dart.dart';
import 'fileManager.dart';
import 'package:ffmpeg_kit_flutter/ffmpeg_kit.dart';
import './SettingService.dart';
import './PromptItem.dart';

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
  VoidCallback? onRecordingStateChanged;
  RecordCompleteCallback? onRecordCompleteReturn;
  RecordAmplitudeChange? onAmplitudeChange;
  Map<String, dynamic>? settings;
  double thresholdHigh = -39.0; // 高于初始值的百分比
  bool lastVolumeStatus = false;

  Future<void> init() async {
    settings = await settingsService.loadSettings();
    final hasPermission = await _recorder.hasPermission();
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

  // void _updateSettings() async {
  //   print('Settings updated: $settings');
  //   settings = await settingsService.loadSettings();
  //   // Update internal state based on new settings
  // }

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
      Directory? dir = await getApplicationDocumentsDirectory();
      String path = '${dir!.path}/record.wav';
      await _recorder.start(
        const RecordConfig(encoder: AudioEncoder.wav),
        path: path,
      );
      _isRecording = true;
      onRecordingStateChanged?.call();
    }
  }

  Future<void> stopRecording() async {
    final path = await _recorder.stop();
    _isRecording = false;
    _recordedFilePath = path;
    onRecordingStateChanged?.call();
    lastVolumeStatus = false;
    if (path != null) {
      try {
        settings = await settingsService.loadSettings();
        setProcessing(true);
        final text = await transcribeAudioOpenAi(path);
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
    }
  }

  Future<void> cancelRecording() async {
    await _recorder.cancel();
    _isRecording = false;
    _recordedFilePath = null;
    onRecordingStateChanged?.call();
    setProcessing(false);
  }

  Future<String> transcribeAudioOpenAi(String filePath) async {
    try {
      File audioFile = File(filePath);
      int fileSizeInBytes = await audioFile.length();
      double fileSizeInMB = fileSizeInBytes / (1024 * 1024);
      int numberOfParts = (fileSizeInMB / 24).ceil();
      // 切割檔案
      List<AudioPart> files =
          await splitAudioFile(filePath, numberOfParts); // 25 MB

      List<String> transcriptions = [];
      int srtIndex = 1; // SRT index starts at 1

      for (AudioPart part in files) {
        OpenAI.apiKey = settings?['openai_key'] ?? "";
        OpenAIAudioModel transcription =
            await OpenAI.instance.audio.createTranscription(
          file: part.file,
          model: "whisper-1",
          responseFormat: OpenAIAudioResponseFormat.srt,
        );
        String adjustedSrt =
            adjustTimestamps(transcription.text, part.startTime, srtIndex);
        transcriptions.add(adjustedSrt);

        // Update the SRT index to maintain continuity
        srtIndex += transcription.text
            .split('\n')
            .where((line) => line.contains('-->'))
            .length;
      }

      // 合併文本
      return transcriptions.join("\n");
    } catch (e) {
      print("Error during transcription: $e");
      return "";
    }
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
    Directory tempDir = await getApplicationDocumentsDirectory();
    String tempPath = tempDir.path;

    // Calculate the duration of each part
    double duration = await getDuration(filePath);
    print('Duration: $duration');

    double partDuration = duration / numberOfParts;
    if (partDuration <= 1) {
      // Check if the duration calculation is correct
      parts.add(AudioPart(File(filePath),
          0)); // Entire file as one part if duration calculation is too small
      return parts;
    }

    // Generate FFmpeg commands and execute
    for (int i = 0; i < numberOfParts; i++) {
      double startTime = partDuration * i;
      String outputFileName = "$tempPath/output_part_$i.wav";
      String command =
          "-i $filePath -ss $startTime -t $partDuration -c copy $outputFileName -y";

      await FFmpegKit.execute(command).then((session) async {
        final returnCode = await session.getReturnCode();
        if (returnCode != null && returnCode.isValueSuccess()) {
          print("Splitting part $i succeeded");
          parts.add(AudioPart(File(outputFileName), startTime));
        } else if (returnCode != null && returnCode.isValueError()) {
          print("Error occurred while splitting part $i");
        } else {
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
      apiUrl: settings?['ollama_url'],
      model: settings?['ollama_model'],
    );

    final result = await llmService.callLlm(prompt ?? '',
        recordResult.originalText, settings?['use_openai'], options);

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
      setProcessing(false);
      return;
    }
    if (settings?['use_openai'] && settings?['openai_key'] == null) {
      print("Settings are not configured properly.");
      setProcessing(false);
      return;
    }
    if (settings?['use_openai'] == false && settings?['ollama_url'] == null) {
      print("Settings are not configured properly.");
      setProcessing(false);
      return;
    }

    int defaultPromptIndex = settings?['defaultPromptIndex'] ?? 0;
    PromptItem selectedPrompt = prompts[defaultPromptIndex];

    String promptTemplate = selectedPrompt.prompt;
    if (defaultPromptIndex! >= prompts.length) {
      print("Settings are not configured properly.");
      setProcessing(false);
      return;
    }
    LlmOptions options = LlmOptions(
      apiKey: settings?['openai_key'],
      apiUrl: settings?['ollama_url'],
      model: settings?['ollama_model'],
    );

    String result = await llmService.callLlm(
        promptTemplate ?? '', content, settings?['use_openai'], options);

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
    onRecordCompleteReturn?.call(recordResult);
    // Share the message
    // Share.share(message);
  }

  void dispose() {
    _recorder.dispose();
  }
}
