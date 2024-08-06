import 'dart:async';
import 'dart:io';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import './recordResult.dart';

class DatabaseHelper {
  static final DatabaseHelper _instance = DatabaseHelper._internal();
  factory DatabaseHelper() => _instance;

  DatabaseHelper._internal();

  static Database? _database;

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'recordings.db');
    print(dbPath);

    return await openDatabase(
      path,
      version: 3, // Incremented database version
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE recordings(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            timestamp TEXT,
            originalText TEXT,
            processedText TEXT,
            promptText TEXT,
            whisperPrompt TEXT,
            filePath TEXT,
            screenshots TEXT
          )
        ''');
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db.execute('''
            ALTER TABLE recordings ADD COLUMN whisperPrompt TEXT;
          ''');
          await db.execute('''
            ALTER TABLE recordings ADD COLUMN filePath TEXT;
          ''');
        }
        if (oldVersion < 3) {
          await db.execute('''
            ALTER TABLE recordings ADD COLUMN screenshots TEXT;
          ''');
        }
      },
    );
  }

  Future<RecordResult> insertRecording(RecordResult record) async {
    final db = await database;
    final id = await db.insert(
      'recordings',
      record.toJson(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    final Map<String, dynamic> result = (await db.query(
      'recordings',
      where: 'id = ?',
      whereArgs: [id],
    ))
        .first;
    return RecordResult.fromJson(result);
  }

  Future<void> updateRecording(RecordResult record, [int? id]) async {
    final db = await database;
    final recordId = record.id ?? id;
    print('Updating record with id: $recordId');
    if (recordId == null) {
      throw ArgumentError("Either record.id or id must be provided");
    }

    if (record.id == null) {
      record.id = id;
    }
    try {
      await db.update(
        'recordings',
        record.toJson(),
        where: 'id = ?',
        whereArgs: [recordId],
      );
      print("Record updated successfully");
    } catch (e) {
      print("Failed to update record: $e");
      rethrow;
    }
  }

  Future<void> deleteRecording(int id) async {
    final db = await database;

    // Retrieve the recording to get the filePath
    final List<Map<String, dynamic>> result = await db.query(
      'recordings',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );

    if (result.isNotEmpty) {
      final RecordResult record = RecordResult.fromJson(result.first);

      // Check if the file exists and delete it
      if (record.filePath != null && record.filePath!.isNotEmpty) {
        final file = File(record.filePath!);
        if (await file.exists()) {
          await file.delete();
        }
      }

      // Delete the record from the database
      await db.delete(
        'recordings',
        where: 'id = ?',
        whereArgs: [id],
      );
    }
  }

  Future<List<RecordResult>> getRecordings() async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query('recordings');

    return List.generate(maps.length, (i) {
      return RecordResult.fromJson(maps[i]);
    });
  }
}
