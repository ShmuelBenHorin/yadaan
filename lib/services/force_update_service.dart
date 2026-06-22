import 'package:cloud_firestore/cloud_firestore.dart';

/// בדיקת עדכון כפוי מול Firestore.
///
/// מבנה Firestore:
///   config/app_settings {
///     min_version: "1.7.19"   ← גרסה מינימלית (ריקה = ללא כפייה)
///   }
///
/// כדי לכפות עדכון: עדכן את min_version לגרסה חדשה מהגרסה הנוכחית.
/// כדי לבטל כפייה: מחק את השדה או הגדר אותו לגרסה נמוכה מהנוכחית.
class ForceUpdateService {
  static Future<bool> isUpdateRequired(String currentVersion) async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('config')
          .doc('app_settings')
          .get()
          .timeout(const Duration(seconds: 5));

      if (!doc.exists) return false;
      final minVersion = doc.data()?['min_version'] as String?;
      if (minVersion == null || minVersion.isEmpty) return false;

      return _isBelow(currentVersion, minVersion);
    } catch (_) {
      return false; // אם Firestore לא זמין — לא חוסמים
    }
  }

  /// true אם current < minimum
  static bool _isBelow(String current, String minimum) {
    final c = _parts(current);
    final m = _parts(minimum);
    final len = m.length > c.length ? m.length : c.length;
    for (int i = 0; i < len; i++) {
      final cv = i < c.length ? c[i] : 0;
      final mv = i < m.length ? m[i] : 0;
      if (cv < mv) return true;
      if (cv > mv) return false;
    }
    return false;
  }

  static List<int> _parts(String v) =>
      v.split('.').map((s) => int.tryParse(s) ?? 0).toList();
}
