import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;

class FileManager {
  /// Checks if a file exists locally; downloads it if it does not.
  ///
  /// [fileName] - The local name to check or save as.
  /// [url] - The URL to download the file from if it's not found locally.
  /// Returns the path to the file.
  Future<String> ensureFileExists(String fileName, String url) async {
    Directory dir = await getApplicationDocumentsDirectory();
    File file = File('${dir.path}/$fileName');

    if (await file.exists()) {
      print('File already exists locally.');
      return file.path;
    } else {
      print('File does not exist. Downloading...');
      return await downloadFile(url, fileName, dir.path);
    }
  }

  /// Downloads a file from [url] and saves it as [file].
  /// Returns the path to the downloaded file.
  Future<String> downloadFile(String url, String fileName, String path) async {
    File file =
        File('$path/$fileName'); // Create the File object with the full path
    try {
      var response = await http.get(Uri.parse(
          'https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-small.bin?download=true'));
      if (response.statusCode == 200) {
        await file.writeAsBytes(response.bodyBytes);
        print('File downloaded: ${file.path}');
        return file.path;
      } else {
        throw Exception('Failed to download file: HTTP ${response.statusCode}');
      }
    } catch (e) {
      print('Error downloading file: $e');
      throw Exception('Error downloading file: $e');
    }
  }
}
