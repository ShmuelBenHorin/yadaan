import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config.dart';
import '../questions_easy.dart';
import '../questions_medium.dart';
import '../questions_hard.dart';
import '../interests_service.dart';

// ═══════════════════════════════════════════════
//  DIFFICULTY
// ═══════════════════════════════════════════════
enum Diff { easy, medium, hard }
extension DiffX on Diff {
  String get label   => ['קל', 'בינוני', 'קשה'][index];
  Color  get color   => [const Color(0xFF2ECC71), const Color(0xFF4D96FF), const Color(0xFFE74C3C)][index];
  bool   get isPrem  => this == Diff.hard;
  String get emoji   => ['\u{1F921}', '\u{1F535}', '\u{1F534}'][index];
}

// ═══════════════════════════════════════════════
//  DATA MODEL
// ═══════════════════════════════════════════════
class Question {
  final String id, category, q;
  final List<String> a;
  final int c;
  final Diff diff;
  final String? f;
  const Question({required this.id, required this.category,
    required this.q, required this.a, required this.c,
    required this.diff, this.f});
  factory Question.fromMap(Map<String,dynamic> m) {
    final d = (m['d'] as int?) ?? 1;
    return Question(id:m['id'], category:m['category'], q:m['q'],
      a:List<String>.from(m['a']), c:m['c'],
      diff: d==3?Diff.hard:d==2?Diff.medium:Diff.easy, f:m['f']);
  }
}

// ═══════════════════════════════════════════════
//  REPO — להוסיף שאלות: ערוך questions_easy/medium/hard.dart
// ═══════════════════════════════════════════════
class QRepo {
  static List<Question>? _e,_m,_h;
  static List<Question> get easy   { _e??=_p(kEasy,   Diff.easy);   return _e!; }
  static List<Question> get medium { _m??=_p(kMedium, Diff.medium); return _m!; }
  static List<Question> get hard   { _h??=_p(kHard,   Diff.hard);   return _h!; }
  static List<Question> _p(String j, Diff d) =>
      (jsonDecode(j) as List).map((e)=>Question.fromMap(e)).toList();
  static List<Question> forDiff(Diff d) => [easy,medium,hard][d.index];

  // ─── מעקב שאלות שנראו ────────────────────────────────────────────────────
  static final Map<Diff,Set<String>> _seen = {Diff.easy:{},Diff.medium:{},Diff.hard:{}};
  static Future<void> loadSeen() async {
    final p = await SharedPreferences.getInstance();
    for (final d in Diff.values) {
      _seen[d] = Set<String>.from(p.getStringList('seen_${d.name}') ?? []);
    }
  }
  static Future<void> markSeen(String id, Diff d) async {
    _seen[d]!.add(id);
    final p = await SharedPreferences.getInstance();
    await p.setStringList('seen_${d.name}', _seen[d]!.toList());
  }

  static List<Question> forLevel(int idx, Diff d) {
    final all = forDiff(d);
    final n   = Cfg.questionsPerLevel;

    // ── חלוקה קבועה לפי שלב ──────────────────────────────────────
    // כל שלב מקבל 8 שאלות משלו — ללא חפיפה עם שאלות שלב אחר.
    // שאלה שנענתה נכון בשלב 3 לא נעלמת ממאגר שלב 7.
    final count = max(1, (all.length / n).floor());
    final safeIdx = idx % count;
    final start   = safeIdx * n;
    final end     = (start + n).clamp(0, all.length);
    final partition = List<Question>.from(all.sublist(start, end));

    // ── unseen קודם, seen אחר (recycled) ─────────────────────────
    final seen = _seen[d] ?? {};
    var unseen  = partition.where((q) => !seen.contains(q.id)).toList();
    final recycled = partition.where((q) => seen.contains(q.id)).toList();
    // אם כל השאלות בשלב כבר נענו נכון — מחזירים אותן (השלב תמיד ניתן לשחק)
    if (unseen.isEmpty) unseen = recycled;

    final interests = InterestsService.instance;
    final rng = Random();

    // ── סינון לפי עניין (70% מועדף / 30% אחר) ───────────────────
    final Map<String, List<Question>> liked = {};
    final Map<String, List<Question>> other = {};
    for (final q in unseen) {
      if (interests.isSelected(q.category)) {
        liked.putIfAbsent(q.category, () => []).add(q);
      } else {
        other.putIfAbsent(q.category, () => []).add(q);
      }
    }
    for (final l in liked.values) { l.shuffle(rng); }
    for (final l in other.values) { l.shuffle(rng); }

    Question? _pick(Map<String, List<Question>> pool, Set<String> used) {
      final avail = pool.entries.where((e) => e.value.any((q) => !used.contains(q.id))).toList();
      if (avail.isEmpty) return null;
      final cat = avail[rng.nextInt(avail.length)];
      return cat.value.firstWhere((q) => !used.contains(q.id));
    }

    final result = <Question>[];
    final used   = <String>{};
    for (int i = 0; i < n; i++) {
      final fromLiked = rng.nextDouble() < 0.7 && liked.isNotEmpty;
      final q = fromLiked
          ? (_pick(liked, used) ?? _pick(other, used))
          : (_pick(other, used) ?? _pick(liked, used));
      if (q != null) { result.add(q); used.add(q.id); }
    }
    // השלם מ-recycled אם נדרש (מצב שכל 8 שאלות כבר נענו נכון)
    if (result.length < n) {
      final rem = recycled.where((q) => !used.contains(q.id)).toList()..shuffle(rng);
      result.addAll(rem.take(n - result.length));
    }
    return result;
  }
  static int levelCount(Diff d) => max(1,(forDiff(d).length/Cfg.questionsPerLevel).floor());
  static List<Question> all(bool prem) =>
      prem ? [...easy, ...medium, ...hard] : [...easy, ...medium];
}
