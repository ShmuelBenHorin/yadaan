import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'services/level_service.dart';
import 'models/question.dart';

// ═══════════════════════════════════════════════════════════════════════
//  LeaderboardService — Firebase Anonymous Auth + טבלת מובילים
//
//  Firestore: users/{uid}
//    display_name:  String     ← כינוי שבחר המשתמש
//    stars_easy:    int
//    stars_medium:  int
//    stars_hard:    int
//    correct:       int
//    total:         int
//    accuracy:      double
//    streak:        int
//    last_updated:  Timestamp
// ═══════════════════════════════════════════════════════════════════════

class LeaderEntry {
  final String uid;
  final String name;
  final int starsEasy;
  final int starsMedium;
  final int starsHard;
  final double accuracy;
  final int streak;

  int get totalStars => starsEasy + starsMedium + starsHard;

  LeaderEntry({
    required this.uid,
    required this.name,
    required this.starsEasy,
    required this.starsMedium,
    required this.starsHard,
    required this.accuracy,
    required this.streak,
  });

  factory LeaderEntry.fromDoc(DocumentSnapshot doc) {
    final m = doc.data() as Map<String, dynamic>;
    return LeaderEntry(
      uid:         doc.id,
      name:        (m['display_name'] as String?) ?? 'אנונימי',
      starsEasy:   (m['stars_easy']   as int?) ?? 0,
      starsMedium: (m['stars_medium'] as int?) ?? 0,
      starsHard:   (m['stars_hard']   as int?) ?? 0,
      accuracy:    ((m['accuracy']    as num?) ?? 0).toDouble(),
      streak:      (m['streak']       as int?) ?? 0,
    );
  }
}

// ────────────────────────────────────────────────────────────────────────
class LeaderboardService {
  static final LeaderboardService _i = LeaderboardService._();
  static LeaderboardService get instance => _i;
  LeaderboardService._();

  String? _uid;
  String? _displayName;
  bool _ready = false;

  // מצטבר בזיכרון בין רמות
  int _pendingCorrect = 0;
  int _pendingTotal   = 0;

  static const _nameKey = 'leaderboard_display_name';
  static const _nameSetKey = 'leaderboard_name_set';

  String? get displayName => _displayName;
  String? get uid => _uid;
  bool get isReady => _ready;
  bool get isAnonymous => FirebaseAuth.instance.currentUser?.isAnonymous ?? true;

  // האם המשתמש כבר בחר כינוי
  static bool _nameSet = false;
  static bool get nameSet => _nameSet;

  /// קורא לזה ב-main() לאחר Firebase.initializeApp()
  static Future<void> init() async {
    try {
      final p = await SharedPreferences.getInstance();
      _nameSet = p.getBool(_nameSetKey) ?? false;
      _i._displayName = p.getString(_nameKey);
      await _i._signIn();
    } catch (e) {
      debugPrint('LeaderboardService init error: $e');
    }
  }

  Future<void> _signIn() async {
    final auth = FirebaseAuth.instance;
    User? user = auth.currentUser;
    if (user == null) {
      final cred = await auth.signInAnonymously();
      user = cred.user;
    }
    _uid = user?.uid;
    _ready = _uid != null;
    debugPrint('LeaderboardService ready. uid=$_uid');
  }

  // ─── שמירת כינוי ──────────────────────────────────────────────────────
  Future<void> setDisplayName(String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;
    _displayName = trimmed;
    _nameSet = true;
    final p = await SharedPreferences.getInstance();
    await p.setString(_nameKey, trimmed);
    await p.setBool(_nameSetKey, true);
    // עדכון ב-Firestore
    if (_ready && _uid != null) {
      try {
        await FirebaseFirestore.instance.collection('users').doc(_uid).set(
          {'display_name': trimmed},
          SetOptions(merge: true),
        );
      } catch (e) {
        debugPrint('LeaderboardService.setDisplayName error: $e');
      }
    }
  }

  // ─── נקרא מ-GameState._finish() אחרי כל שלב ──────────────────────────
  Future<void> recordLevel({
    required Diff diff,
    required int correct,
    required int total,
    required int streak,
  }) async {
    if (!_ready || _uid == null) return;

    _pendingCorrect += correct;
    _pendingTotal   += total;

    try {
      final ls  = LevelService.instance;
      final ref = FirebaseFirestore.instance.collection('users').doc(_uid);

      final allCorrect = _pendingCorrect.toDouble();
      final allTotal   = _pendingTotal.toDouble();
      final accuracy   = allTotal > 0 ? allCorrect / allTotal : 0.0;

      final data = <String, dynamic>{
        'stars_easy':   ls.totalStars(Diff.easy),
        'stars_medium': ls.totalStars(Diff.medium),
        'stars_hard':   ls.totalStars(Diff.hard),
        'correct':      FieldValue.increment(correct),
        'total':        FieldValue.increment(total),
        'accuracy':     accuracy,
        'streak':       streak,
        'last_updated': FieldValue.serverTimestamp(),
      };
      // כולל כינוי אם הוגדר
      if (_displayName != null) data['display_name'] = _displayName;

      await ref.set(data, SetOptions(merge: true));
    } catch (e) {
      debugPrint('LeaderboardService.recordLevel error: $e');
    }
  }

  // ─── שליפת טבלת מובילים ───────────────────────────────────────────────
  /// מחזיר Top-50 לפי סה״כ כוכבים (stars_easy + stars_medium + stars_hard).
  /// Firestore אינו תומך בשדה מחושב, לכן ממיין כאן בצד הלקוח.
  ///
  /// ⚠️ Firebase Console → Firestore → Indexes → Composite:
  ///   Collection: users
  ///   Fields: display_name ASC, stars_hard DESC
  Future<List<LeaderEntry>> fetchTop50() async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('users')
          .where('display_name', isGreaterThan: '')
          .orderBy('display_name')
          .orderBy('stars_hard', descending: true)
          .limit(100)
          .get();
      final entries = snap.docs.map((d) => LeaderEntry.fromDoc(d)).toList();
      entries.sort((a, b) => b.totalStars.compareTo(a.totalStars));
      return entries.take(50).toList();
    } catch (e) {
      debugPrint('LeaderboardService.fetchTop50 error: $e');
      return [];
    }
  }

  /// מחזיר את הנתונים של המשתמש הנוכחי (לסימון בטבלה)
  Future<LeaderEntry?> fetchMyEntry() async {
    if (!_ready || _uid == null) return null;
    try {
      final doc = await FirebaseFirestore.instance.collection('users').doc(_uid).get();
      if (!doc.exists) return null;
      return LeaderEntry.fromDoc(doc);
    } catch (e) {
      return null;
    }
  }
}
