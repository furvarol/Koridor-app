import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'models.dart';

/// Koridorlar ve geçmiş, uygulamanın özel dizininde JSON olarak tutulur.
class Storage {
  static Future<File> _file(String name) async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$name');
  }

  static Future<List<Corridor>> loadCorridors() async {
    final f = await _file('corridors.json');
    if (!await f.exists()) return [];
    final list = jsonDecode(await f.readAsString()) as List;
    return list.map((e) => Corridor.fromJson(e)).toList();
  }

  static Future<void> saveCorridors(List<Corridor> cs) async {
    final f = await _file('corridors.json');
    await f.writeAsString(jsonEncode(cs.map((c) => c.toJson()).toList()));
  }

  static Future<List<Passage>> loadPassages() async {
    final f = await _file('passages.json');
    if (!await f.exists()) return [];
    final list = jsonDecode(await f.readAsString()) as List;
    return list.map((e) => Passage.fromJson(e)).toList();
  }

  static Future<void> savePassages(List<Passage> ps) async {
    final f = await _file('passages.json');
    await f.writeAsString(jsonEncode(ps.map((p) => p.toJson()).toList()));
  }
}
