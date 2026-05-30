import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ═══════════════════════════════════════════════
//  רמות שחקן
// ═══════════════════════════════════════════════
enum PlayerLevel { beginner, amateur, advanced, expert, legend }

extension PlayerLevelX on PlayerLevel {
  String get label      => ['מתחיל', 'חובבן', 'מתקדם', 'מומחה', 'אגדה'][index];
  String get titleLabel => 'רמת $label'; // "רמת מתחיל", "רמת חובבן"…
  String get emoji   => ['🌱', '📘', '🔥', '💡', '🏆'][index];
  Color  get color   => [
    const Color(0xFF95A5A6),
    const Color(0xFF3498DB),
    const Color(0xFFE67E22),
    const Color(0xFF9B59B6),
    const Color(0xFFFFD700),
  ][index];
  // XP הדרוש להגיע לרמה זו
  int get xpRequired => [0, 200, 600, 1500, 4000][index];
  // XP הדרוש לרמה הבאה
  int get nextLevelXp => index < 4 ? [200, 600, 1500, 4000, 99999][index] : 99999;
}

// ═══════════════════════════════════════════════
//  UserStatsService — KD + XP + Level + Streak
// ═══════════════════════════════════════════════
class UserStatsService extends ChangeNotifier {
  static final UserStatsService _i = UserStatsService._();
  static UserStatsService get instance => _i;
  UserStatsService._();

  int _xp          = 0;
  int _correct     = 0;
  int _wrong       = 0;
  int _streak      = 0;
  int _bestStreak  = 0;
  String _lastPlayDate = '';

  // ─── Getters ────────────────────────────────
  int get xp         => _xp;
  int get correct    => _correct;
  int get wrong      => _wrong;
  int get total      => _correct + _wrong;
  int get streak     => _streak;
  int get bestStreak => _bestStreak;

  /// KD: אחוז תשובות נכונות
  double get kd          => total == 0 ? 0.0 : _correct / total;
  String get kdDisplay   => total == 0 ? '-' : '${(kd * 100).toStringAsFixed(0)}%';
  String get kdRatio     => '$_correct/$total';

  /// רמת שחקן נוכחית
  PlayerLevel get level {
    for (int i = PlayerLevel.values.length - 1; i >= 0; i--) {
      if (_xp >= PlayerLevel.values[i].xpRequired) return PlayerLevel.values[i];
    }
    return PlayerLevel.beginner;
  }

  /// XP בתוך הרמה הנוכחית
  int get xpInLevel  => _xp - level.xpRequired;
  /// XP נדרש לסיום הרמה הנוכחית
  int get xpForLevel => level.nextLevelXp - level.xpRequired;
  /// אחוז התקדמות ברמה (0.0 – 1.0)
  double get levelProgress =>
      level == PlayerLevel.legend ? 1.0 : (xpInLevel / xpForLevel).clamp(0.0, 1.0);

  // ─── Init ────────────────────────────────────
  static Future<void> init() async {
    final p = await SharedPreferences.getInstance();
    _i._xp          = p.getInt('us_xp')      ?? 0;
    _i._correct     = p.getInt('us_correct')  ?? 0;
    _i._wrong       = p.getInt('us_wrong')    ?? 0;
    _i._streak      = p.getInt('us_streak')   ?? 0;
    _i._bestStreak  = p.getInt('us_best_str') ?? 0;
    _i._lastPlayDate = p.getString('us_last_date') ?? '';
    // בדוק streak: אם לא שיחקו אתמול — אפס
    _i._checkStreak();
  }

  void _checkStreak() {
    final today     = _dateStr(DateTime.now());
    final yesterday = _dateStr(DateTime.now().subtract(const Duration(days: 1)));
    if (_lastPlayDate == today) return;        // כבר שיחקו היום
    if (_lastPlayDate != yesterday) _streak = 0; // פספסו יום
  }

  // ─── Record Answer ───────────────────────────
  /// diffIndex: 0=קל, 1=בינוני, 2=קשה
  Future<void> recordAnswer({required bool correct, required int diffIndex}) async {
    final prevLevel = level;

    if (correct) {
      _correct++;
      _xp += [10, 20, 30][diffIndex];
    } else {
      _wrong++;
    }

    // streak
    final today = _dateStr(DateTime.now());
    if (_lastPlayDate != today) {
      final yesterday = _dateStr(DateTime.now().subtract(const Duration(days: 1)));
      _streak = (_lastPlayDate == yesterday) ? _streak + 1 : 1;
      if (_streak > _bestStreak) _bestStreak = _streak;
      _lastPlayDate = today;
    }

    final newLevel = level;
    final leveledUp = newLevel.index > prevLevel.index;

    await _save();
    notifyListeners();

    if (leveledUp) {
      _onLevelUp(newLevel);
    }
  }

  void _onLevelUp(PlayerLevel newLevel) {
    // callback חיצוני יכול להאזין — אפשר להוסיף אנימציה/dialog בהמשך
    debugPrint('⬆️ Level up! → ${newLevel.label}');
  }

  // ─── Helpers ─────────────────────────────────
  static String _dateStr(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<void> _save() async {
    final p = await SharedPreferences.getInstance();
    await Future.wait([
      p.setInt('us_xp',         _xp),
      p.setInt('us_correct',    _correct),
      p.setInt('us_wrong',      _wrong),
      p.setInt('us_streak',     _streak),
      p.setInt('us_best_str',   _bestStreak),
      p.setString('us_last_date', _lastPlayDate),
    ]);
  }
}
