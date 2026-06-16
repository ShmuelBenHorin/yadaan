import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ═══════════════════════════════════════════════
//  ICLOUD KEY-VALUE STORE  (iOS בלבד)
// ═══════════════════════════════════════════════
class ICloudKV {
  static const _ch = MethodChannel('icloud_kv');

  /// שמור את כל ה-SharedPreferences ל-iCloud אחרי סיום שלב
  static Future<void> saveAll() async {
    if (defaultTargetPlatform != TargetPlatform.iOS) return;
    try {
      final p = await SharedPreferences.getInstance();
      final Map<String, dynamic> data = {};

      // רשימות שאלות שנראו + טעויות
      for (final key in ['seen_easy','seen_medium','seen_hard','mistakes_v2']) {
        final v = p.getStringList(key);
        if (v != null) data[key] = v;
      }
      // כוכבים לכל שלב (נפסוק כשאין ערך = 0 מעולם לא הושלם)
      for (final d in ['easy','medium','hard']) {
        for (int i = 0; i < 500; i++) {
          final key = 'lvl_${d}_$i';
          final v = p.getInt(key);
          if (v == null) break;
          data[key] = v;
        }
      }
      // ערכים בודדים
      for (final key in ['energy','energy_ts','levels_completed',
                         'us_xp','us_correct','us_wrong','us_streak','us_best_str']) {
        final v = p.getInt(key);
        if (v != null) data[key] = v;
      }
      // UserStats — תאריך + תחומי עניין
      final lastDate = p.getString('us_last_date');
      if (lastDate != null) data['us_last_date'] = lastDate;
      final interests = p.getStringList('interests_v1');
      if (interests != null) data['interests_v1'] = interests;
      // חולשות
      for (final cat in ['israel','judaism','football','world','geography','science','sports','music','american_music']) {
        final m = p.getInt('weak_m_$cat');
        final a = p.getInt('weak_a_$cat');
        if (m != null) data['weak_m_$cat'] = m;
        if (a != null) data['weak_a_$cat'] = a;
      }
      final ob = p.getBool('onboarding_done');
      if (ob != null) data['onboarding_done'] = ob;

      await _ch.invokeMethod('writeAll', data);
    } catch (_) {}
  }

  /// בהפעלה ראשונה אחרי מחיקת האפליקציה — שחזר מ-iCloud אם אין נתונים מקומיים
  static Future<void> restoreIfEmpty() async {
    if (defaultTargetPlatform != TargetPlatform.iOS) return;
    try {
      final p = await SharedPreferences.getInstance();
      // יש נתונים מקומיים → אין צורך לשחזר
      if (p.getKeys().any((k) => k.startsWith('lvl_'))) return;

      final raw = await _ch.invokeMapMethod<String, dynamic>('readAll');
      if (raw == null || raw.isEmpty) return;

      for (final entry in raw.entries) {
        final key = entry.key;
        final val = entry.value;
        if (val is List) {
          await p.setStringList(key, List<String>.from(val));
        } else if (val is int) {
          await p.setInt(key, val);
        } else if (val is bool) {
          await p.setBool(key, val);
        } else if (val is double) {
          await p.setDouble(key, val);
        } else if (val is String) {
          await p.setString(key, val);
        }
      }
    } catch (_) {}
  }
}
