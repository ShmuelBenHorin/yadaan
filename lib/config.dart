import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

// ═══════════════════════════════════════════════
//  CONFIG
// ═══════════════════════════════════════════════
class Cfg {
  static const rcAndroid            = 'goog_uYtvWookyMtAzQQXtOyGOETNCXz';
  static const rciOS                = 'appl_DSEyAVZKuOktZXgzNqiPKhjnOlO';
  static const entitlement          = 'premium';
  static const devCode              = 'shmuel1231';
  static const mockPremium          = false;
  static const adMobEnabled         = true;
  static const adEnergyThreshold    = 3;

  // ─── AdMob Ad Unit IDs ───────────────────────────────────────────────────
  // פרסומת מלאה 30 שניות → +5 אנרגיה
  static String get adRewardedUnitId =>
      defaultTargetPlatform == TargetPlatform.iOS
          ? 'ca-app-pub-1305167445502870/9990640892'  // iOS Rewarded
          : 'ca-app-pub-1305167445502870/2554080569'; // Android Rewarded

  // פרסומת עם דילוג אחרי כמה שניות → +1 אנרגיה
  static String get adRewardedInterstitialUnitId =>
      defaultTargetPlatform == TargetPlatform.iOS
          ? 'ca-app-pub-1305167445502870/4131809558'  // iOS Rewarded Interstitial
          : 'ca-app-pub-1305167445502870/1697217900'; // Android Rewarded Interstitial

  static const adRewardedEnergy             = 2; // מוחות מפרסומת
  static const adRewardedInterstitialEnergy = 1; // אנרגיה מפרסומת עם דילוג

  static const questionsPerLevel    = 8;
  static const starsPerLevel        = 3;
  static const maxWrongPerLevel     = 2;
  static const segmentSize          = 5;
  static const starsPerSegment      = 10;
  static const starsToUnlockMedium  = 10;
  static const starsToUnlockHard    = 15;

  static const maxEnergyFree        = 15;
  static const maxEnergyPremium     = 50;
  static const energyCostWrong      = 1;
  static const energyCostFail       = 1;
  static const energyRechargeMins   = 15;
  static const energyRechargeAmt    = 1;
  static const energyRechargeAmtPro = 3;

  static const timerSecs            = 15;
}

// ═══════════════════════════════════════════════
//  PALETTE
// ═══════════════════════════════════════════════
class Pal {
  static const bg=Color(0xFF0D1B3E), bgD=Color(0xFF060D20);
  static const card=Color(0xFF112054), cardL=Color(0xFF1A2E6E);
  static const gold=Color(0xFFFFD700), accent=Color(0xFF7C6FE0);
  static const green=Color(0xFF2ECC71), red=Color(0xFFE74C3C);
  static const premium=Color(0xFFFF9F0A);
  static const tp=Color(0xFFF0F0FF), ts=Color(0xFF8898CC);
  static const starOn=Color(0xFFFFD700), starOff=Color(0xFF2A3A6E);
}
