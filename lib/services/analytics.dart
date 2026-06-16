import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../user_stats.dart';

// ═══════════════════════════════════════════════
//  ANALYTICS
// ═══════════════════════════════════════════════
class Analytics {
  static FirebaseAnalytics? _fa;
  static int _sessionStages = 0;

  /// Callback set from main.dart to retrieve current energy (breaks circular import)
  static int Function()? _getEnergy;
  static void setEnergyGetter(int Function() fn) { _getEnergy = fn; }

  static Future<void> init() async { _fa = FirebaseAnalytics.instance; }

  static void levelStarted() { _sessionStages++; }

  // אנרגיה
  static Future<void> energyDepleted() async {
    try { await _fa?.logEvent(name:'energy_depleted',
      parameters:{'stages_played':_sessionStages}); } catch(_){}
  }
  static Future<void> energyDepletedUserLeft() async {
    try { await _fa?.logEvent(name:'energy_depleted_user_left',
      parameters:{'stages_played':_sessionStages}); } catch(_){}
  }
  static Future<void> adWatchedForEnergy({required int amount}) async {
    try { await _fa?.logEvent(name:'ad_watched_for_energy',
      parameters:{'energy_gained':amount}); } catch(_){}
  }

  // מסך אין אנרגיה — מה המשתמש עשה
  static Future<void> noEnergyAction(String action) async {
    // action: 'bought_pro' | 'watched_ad' | 'left'
    try { await _fa?.logEvent(name:'no_energy_action',
      parameters:{'action':action,'stages_played':_sessionStages}); } catch(_){}
  }

  // שלבים
  static Future<void> levelCompleted({required String diff, required int levelIndex, required int stars}) async {
    try {
      await _fa?.logEvent(name:'level_completed',
        parameters:{'diff':diff,'level':levelIndex,'stars':stars});
      // User Property: השלב המקסימלי שהמשתמש הגיע אליו
      await _fa?.setUserProperty(name:'max_level_reached', value:'${diff}_$levelIndex');
      // User Property: סך השלבים שהמשתמש השלים — רואים פר-משתמש בFirebase
      final p = await SharedPreferences.getInstance();
      final total = (p.getInt('levels_completed') ?? 0);
      await _fa?.setUserProperty(name:'total_levels_completed', value:'$total');
    } catch(_){}
  }
  static Future<void> levelFailed({required String diff, required int levelIndex}) async {
    try { await _fa?.logEvent(name:'level_failed',
      parameters:{'diff':diff,'level':levelIndex}); } catch(_){}
  }
  static Future<void> levelQuit({required String diff, required int levelIndex}) async {
    try { await _fa?.logEvent(name:'level_quit',
      parameters:{'diff':diff,'level':levelIndex,'stages_played':_sessionStages}); } catch(_){}
  }

  // רכישת פרו
  static Future<void> proPurchased({required String source}) async {
    // source: 'purchase' | 'restore'
    try { await _fa?.logEvent(name:'pro_tier_purchased',
      parameters:{'source':source}); } catch(_){}
  }

  // paywall — מסך רכישה
  static Future<void> paywallShown(String source) async {
    // source: 'no_energy' | 'locked_level' | 'category'
    try { await _fa?.logEvent(name:'paywall_shown',
      parameters:{'source':source}); } catch(_){}
  }
  static Future<void> paywallDismissed() async {
    try { await _fa?.logEvent(name:'paywall_dismissed'); } catch(_){}
  }

  // חידון קטגוריה
  static Future<void> categoryQuizStarted(String category) async {
    try { await _fa?.logEvent(name:'category_quiz_started',
      parameters:{'category':category}); } catch(_){}
  }
  static Future<void> categoryQuizCompleted({required String category, required int correct, required int total}) async {
    try { await _fa?.logEvent(name:'category_quiz_completed',
      parameters:{'category':category,'correct':correct,'total':total}); } catch(_){}
  }

  // סיום סשן
  static Future<void> sessionEnded() async {
    try { await _fa?.logEvent(name:'session_ended',
      parameters:{'stages_played':_sessionStages,'energy_remaining':_getEnergy?.call() ?? 0}); } catch(_){}
  }

  // ─── רמות שחקן ───────────────────────────────────────────────────────────
  /// נקרא כשמשתמש עולה רמה
  static Future<void> playerLevelUp({required String newLevel, required int xp}) async {
    try { await _fa?.logEvent(name:'player_level_up',
      parameters:{'new_level':newLevel,'total_xp':xp}); } catch(_){}
  }

  /// streak — רצף ימים
  static Future<void> streakMilestone(int days) async {
    try { await _fa?.logEvent(name:'streak_milestone',
      parameters:{'days':days}); } catch(_){}
  }

  /// KD — דיוק
  static Future<void> kdMilestone(String pct) async {
    // pct: '50%' | '75%' | '90%' | '100%'
    try { await _fa?.logEvent(name:'kd_milestone',
      parameters:{'accuracy':pct}); } catch(_){}
  }

  // ─── תחומי עניין ──────────────────────────────────────────────────────────
  /// המשתמש בחר תחומי עניין (אחרי שלב ראשון)
  static Future<void> interestsSelected({required List<String> categories}) async {
    try { await _fa?.logEvent(name:'interests_selected',
      parameters:{'count':categories.length,'categories':categories.join(',')}); } catch(_){}
  }

  /// המשתמש דילג על בחירת תחומי עניין
  static Future<void> interestsSkipped() async {
    try { await _fa?.logEvent(name:'interests_skipped'); } catch(_){}
  }

  /// המשתמש שינה תחומי עניין מהפרופיל
  static Future<void> interestsChanged({required List<String> categories}) async {
    try { await _fa?.logEvent(name:'interests_changed',
      parameters:{'count':categories.length,'categories':categories.join(',')}); } catch(_){}
  }

  // ─── פרופיל ───────────────────────────────────────────────────────────────
  /// פתיחת מסך פרופיל
  static Future<void> profileOpened() async {
    try { await _fa?.logEvent(name:'profile_opened',
      parameters:{
        'level': UserStatsService.instance.level.label,
        'xp':    UserStatsService.instance.xp,
        'streak':UserStatsService.instance.streak,
      }); } catch(_){}
  }

  // ─── retention ────────────────────────────────────────────────────────────
  /// כניסה יומית (נקרא בעת הפעלת האפליקציה)
  static Future<void> dailyOpen({required int streak}) async {
    try { await _fa?.logEvent(name:'daily_open',
      parameters:{'streak':streak}); } catch(_){}
  }
}
