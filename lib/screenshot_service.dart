import 'dart:io';
import 'dart:typed_data';
import 'dart:convert';
import 'package:path_provider/path_provider.dart';
import 'package:screen_capturer/screen_capturer.dart';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart'; // Import window_manager

typedef ScreenshotCallback = void Function(String? imagePath, String timestamp);

class ScreenshotService {
  final ScreenshotCallback onScreenshotTaken;

  ScreenshotService({required this.onScreenshotTaken});

  Future<void> captureAndCropScreenshot(BuildContext context) async {
    String timestamp = DateTime.now().toIso8601String();
    Directory? dir = await getTemporaryDirectory();
    String screenshotPath = '${dir!.path}/screen_$timestamp.png';

    try {
      // Capture the entire screen
      CapturedData? capturedData = await screenCapturer.capture(
        mode: CaptureMode.window,
        imagePath: screenshotPath,
        copyToClipboard: false,
      );
      windowManager.show();
      windowManager.focus();
      if (capturedData != null) {
        File imgFile = File(screenshotPath);
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) {
            return Material(
              type: MaterialType.transparency,
              child: Scaffold(
                appBar: AppBar(
                  title: Text('Preview Image'),
                  actions: [
                    IconButton(
                      icon: Icon(Icons.check),
                      onPressed: () async {
                        Navigator.of(context).pop();
                        onScreenshotTaken(imgFile.path, timestamp);
                      },
                    ),
                  ],
                ),
                body: Center(
                  child: InteractiveViewer(
                    child: Image.file(imgFile),
                  ),
                ),
              ),
            );
          },
        );
      }
    } catch (e) {
      print('Failed to capture screenshot: $e');
    }
  }
}
