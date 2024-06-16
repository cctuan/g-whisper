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
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE recordings(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            timestamp TEXT,
            originalText TEXT,
            processedText TEXT,
            promptText TEXT
          )
        ''');
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

  Future<void> updateRecording(RecordResult record) async {
    final db = await database;
    await db.update(
      'recordings',
      record.toJson(),
      where: 'id = ?',
      whereArgs: [record.id],
    );
  }

  Future<void> deleteRecording(int id) async {
    final db = await database;
    await db.delete(
      'recordings',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<List<RecordResult>> getRecordings() async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query('recordings');

    return List.generate(maps.length, (i) {
      return RecordResult.fromJson(maps[i]);
    });
  }
}
