// ════════════════════════════════════════════════════════
//  config.dart  —  כל ההגדרות של המשחק במקום אחד
//  שים קובץ זה ב: lib/config.dart
// ════════════════════════════════════════════════════════

class Cfg {

  // ─── RevenueCat ───────────────────────────────────────
  static const rcAndroid   = 'YOUR_REVENUECAT_ANDROID_KEY';
  static const rciOS       = 'YOUR_REVENUECAT_IOS_KEY';
  static const entitlement = 'premium';

  // ─── קוד מפתח (לפתיחת פרו בלי תשלום בזמן פיתוח) ────
  static const devCode     = 'shmuel1231';
  static const mockPremium = false;  // true = כל המשתמשים נחשבים פרו

  // ─── שאלות ───────────────────────────────────────────
  // כמה שאלות בכל שלב
  static const questionsPerLevel = 7;

  // ─── כוכבים ──────────────────────────────────────────
  // כמה כוכבים מקסימום לשלב
  static const starsPerLevel = 3;

  // כמה טעויות מותר לפני שמאבדים כוכב
  // 0 טעויות = 3 כוכבים, 1 טעות = 2 כוכבים, 2 טעויות = 1 כוכב
  static const maxWrongPerLevel = 2;

  // כמה כוכבים צריך לצבור (מהשלב הקודם) כדי לפתוח את השלב הבא
  static const starsToUnlockNext = 2;

  // ─── פתיחת רמות ──────────────────────────────────────
  // כמה כוכבים כולל נדרשים לפתיחת רמה בינוני
  // (10 = ממוצע 2 כוכבים מתוך 5 שלבים)
  static const starsToUnlockMedium = 25;

  // כמה כוכבים כולל נדרשים לפתיחת רמה קשה (דורש גם פרו)
  static const starsToUnlockHard = 25;

  // ─── אנרגיה ──────────────────────────────────────────
  // מקסימום אנרגיה למשתמש רגיל
  static const maxEnergyFree = 12;

  // מקסימום אנרגיה למשתמש פרו
  static const maxEnergyPremium = 50;

  // כמה אנרגיה עולה תשובה שגויה
  static const energyCostWrong = 1;

  // כמה אנרגיה עולה כישלון בשלב
  static const energyCostFail = 0;

  // כל כמה דקות מתווספת אנרגיה
  static const energyRechargeMins = 2;

  // כמה אנרגיה מתווספת כל טעינה — משתמש רגיל
  static const energyRechargeAmt = 1;

  // כמה אנרגיה מתווספת כל טעינה — פרו
  static const energyRechargeAmtPro = 3;

  // ─── טיימר ───────────────────────────────────────────
  // כמה שניות יש לענות על כל שאלה
  static const timerSecs = 10;

}
class Cfg {
  static const bool adMobEnabled = false;
  static const int adEnergyThreshold = 5;
}
