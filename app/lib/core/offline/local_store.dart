import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// Keeps JSON values on the phone between app runs: the last data each
/// screen loaded, and the changes waiting to be sent. Values are plain JSON
/// (maps, lists, strings, numbers), exactly as the server sent them.
abstract class LocalStore {
  Future<Object?> read(String key);
  Future<void> write(String key, Object? value);
  Future<void> clear();
}

/// For tests and the web build: nothing survives a restart.
class MemoryLocalStore implements LocalStore {
  final _data = <String, String>{};

  @override
  Future<Object?> read(String key) async {
    final s = _data[key];
    return s == null ? null : jsonDecode(s);
  }

  @override
  Future<void> write(String key, Object? value) async {
    if (value == null) {
      _data.remove(key);
    } else {
      _data[key] = jsonEncode(value);
    }
  }

  @override
  Future<void> clear() async => _data.clear();
}

/// One small file per key in the app's private folder. Other apps cannot
/// read it, and uninstalling the app removes it.
class FileLocalStore implements LocalStore {
  FileLocalStore._(this._dir);
  final Directory _dir;

  static Future<FileLocalStore> open() async {
    final base = await getApplicationSupportDirectory();
    final dir = Directory('${base.path}/offline');
    await dir.create(recursive: true);
    return FileLocalStore._(dir);
  }

  File _file(String key) {
    final safe = base64Url.encode(utf8.encode(key)).replaceAll('=', '');
    return File('${_dir.path}/$safe.json');
  }

  @override
  Future<Object?> read(String key) async {
    try {
      final f = _file(key);
      if (!await f.exists()) return null;
      return jsonDecode(await f.readAsString());
    } catch (e) {
      debugPrint('LocalStore read $key failed: $e');
      return null;
    }
  }

  @override
  Future<void> write(String key, Object? value) async {
    final f = _file(key);
    try {
      if (value == null) {
        if (await f.exists()) await f.delete();
        return;
      }
      // Write next to it, then swap, so a crash never leaves half a file.
      final tmp = File('${f.path}.tmp');
      await tmp.writeAsString(jsonEncode(value), flush: true);
      await tmp.rename(f.path);
    } catch (e) {
      debugPrint('LocalStore write $key failed: $e');
    }
  }

  @override
  Future<void> clear() async {
    try {
      if (await _dir.exists()) await _dir.delete(recursive: true);
      await _dir.create(recursive: true);
    } catch (e) {
      debugPrint('LocalStore clear failed: $e');
    }
  }
}
