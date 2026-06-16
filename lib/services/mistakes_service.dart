import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/question.dart';

// ═══════════════════════════════════════════════
//  MISTAKES SERVICE
// ═══════════════════════════════════════════════
class MistakesService {
  static final MistakesService _i = MistakesService._();
  static MistakesService get instance => _i;
  MistakesService._();
  List<Question> _list = [];
  List<Question> get list => List.unmodifiable(_list);

  static Future<void> init() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getStringList('mistakes_v2') ?? [];
    _i._list = raw.map((s) {
      try { return Question.fromMap(jsonDecode(s) as Map<String,dynamic>); }
      catch(_) { return null; }
    }).whereType<Question>().toList();
  }

  void add(Question q) {
    _list.removeWhere((m) => m.id == q.id);
    _list.insert(0, q);
    if (_list.length > 10) _list = _list.sublist(0, 10);
    _save();
  }

  Future<void> _save() async {
    final p = await SharedPreferences.getInstance();
    await p.setStringList('mistakes_v2', _list.map((q) =>
      jsonEncode({'id':q.id,'category':q.category,'q':q.q,'a':q.a,'c':q.c,'d':q.diff.index+1,'f':q.f})
    ).toList());
  }
}
