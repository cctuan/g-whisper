import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as path;
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ffmpeg_kit_flutter/ffmpeg_kit.dart';
import 'package:path_provider/path_provider.dart';

const PREF_KEY_MODEL = 'MODEL';
const PREF_KEY_LANG = 'LANG';

const MODELS = [
  'tiny.en',
  'tiny',
  'base.en',
  'base',
  'small.en',
  'small',
  'medium.en',
  'medium',
  'large',
];

class WhisperTranscriber {
  final Directory tempDir;
  final String whispercppPath;
  SharedPreferences? _prefs;
  Process? _currentProcess;

  WhisperTranscriber({
    required this.tempDir,
    required this.whispercppPath,
  });

  Future<void> initialize() async {
    _prefs = await SharedPreferences.getInstance();
  }

  Future<File> getModelFile(String model) async {
    return File(path.join(tempDir.path, 'ggml-$model.bin'));
  }

  Future<void> checkAndDownloadModel(String model) async {
    await initialize();
    File modelFile = await getModelFile(model);
    if (await modelFile.exists()) {
      print('Skip download $modelFile\n');
      return;
    }
    await downloadModel(modelFile, model);
  }

  Future<void> downloadModel(File modelFile, String model) async {
    final uri = Uri.https(
        'huggingface.co', 'ggerganov/whisper.cpp/resolve/main/ggml-$model.bin');
    print('Downloading $uri...\n');

    var client = http.Client();
    var response = await client.send(http.Request('GET', uri));
    if (response.statusCode >= 300) {
      throw response.stream.toString();
    }
    var writer = modelFile.openWrite();
    await writer.addStream(response.stream);
    await writer.close();
    print('Download ${modelFile.path} (${response.contentLength} bytes)\n');
  }

  Future<void> transcribeToSrt(
      String inputFilePath, String outputFilePath, String model) async {
    await initialize();
    await checkAndDownloadModel(model);

    File wavfile = await _convertWavfile(inputFilePath);
    await _generateSrt(wavfile, outputFilePath, model);
  }

  Future<File> _convertWavfile(String sourceFile) async {
    final tempDir = await getTemporaryDirectory();
    File wavfile = File(path.join(tempDir!.path, "input.wav"));
    if (await wavfile.exists()) {
      await wavfile.delete();
    }
    String command =
        '-i $sourceFile -ar 16000 -ac 1 -c:a pcm_s16le ${wavfile.path}';

    await FFmpegKit.execute(command).then((session) async {
      final returnCode = await session.getReturnCode();
      if (returnCode != null && returnCode.isValueSuccess()) {
        print('Conversion successful: ${wavfile.path}');
      } else {
        print('Conversion failed with return code ${returnCode}');
        throw Exception('FFmpeg conversion failed');
      }
    });

    return wavfile;
  }

  Future<void> _generateSrt(
      File wavfile, String outputFilePath, String model) async {
    File modelFile = await getModelFile(model);
    var args = [
      '-m',
      modelFile.path,
      '-f',
      wavfile.path,
      '--language',
      'auto',
      '--output-srt',
      '--output-file',
      outputFilePath,
    ];
    await _runCommand(whispercppPath, args);
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
    print('\n');

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

  static Future<void> checkAndDownloadModelIfNotExists(String model) async {
    final tempDir = await getTemporaryDirectory();
    File modelFile = File(path.join(tempDir.path, 'ggml-$model.bin'));
    if (await modelFile.exists()) {
      print('Model $model already exists at ${modelFile.path}');
      return;
    }

    final uri = Uri.https(
        'huggingface.co', 'ggerganov/whisper.cpp/resolve/main/ggml-$model.bin');
    print('Downloading $uri...\n');

    var client = http.Client();
    var response = await client.send(http.Request('GET', uri));
    if (response.statusCode >= 300) {
      throw response.stream.toString();
    }
    var writer = modelFile.openWrite();
    await writer.addStream(response.stream);
    await writer.close();
    print('Downloaded ${modelFile.path} (${response.contentLength} bytes)\n');
  }
}
