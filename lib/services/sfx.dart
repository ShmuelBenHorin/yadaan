import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../sfx_stub.dart' if (dart.library.html) '../sfx_web.dart';

// ═══════════════════════════════════════════════
//  SOUND
// ═══════════════════════════════════════════════
class Sfx {
  // ─── השתקה ───────────────────────────────────
  static final ValueNotifier<bool> mutedNotifier = ValueNotifier(false);
  static bool get muted => mutedNotifier.value;

  static Future<void> init() async {
    final p = await SharedPreferences.getInstance();
    mutedNotifier.value = p.getBool('sfx_muted') ?? false;
  }

  static Future<void> setMuted(bool v) async {
    mutedNotifier.value = v;
    final p = await SharedPreferences.getInstance();
    await p.setBool('sfx_muted', v);
  }

  // ✅ נכון — מרימבה בהירה בדיוק כמו Duolingo
  // שלושה harmonic ביחד: בסיס + אוקטבה + קווינטה — נותן את הצליל "עץ" הזה
  static Future<void> correct() async {
    if (muted) return;
    playWebTone([
      {'freq': 1318, 'dur': 0.55, 'vol': 0.42, 'type': 'sine', 'attack': 0.005},
      {'freq': 2637, 'dur': 0.35, 'vol': 0.14, 'type': 'sine', 'attack': 0.005, 'overlap': true},
      {'freq': 1976, 'dur': 0.28, 'vol': 0.10, 'type': 'sine', 'attack': 0.005, 'overlap': true},
    ]);
    if (!kIsWeb) await HapticFeedback.lightImpact();
  }

  // ❌ טעות — "dunk" נמוך ועמוק כמו Duolingo, לא בוזר
  static Future<void> wrong() async {
    if (muted) return;
    playWebTone([
      {'freq': 294, 'glide': 196, 'dur': 0.38, 'vol': 0.48, 'type': 'sine', 'attack': 0.008},
      {'freq': 196, 'dur': 0.28, 'vol': 0.22, 'type': 'sine', 'attack': 0.008, 'overlap': true},
    ]);
    if (!kIsWeb) await HapticFeedback.heavyImpact();
  }

  // 🏆 מושלם — ג'ינגל חגיגי קצר בסגנון Duolingo streak
  static Future<void> perfect() async {
    if (muted) return;
    playWebTone([
      {'freq': 784,  'dur': 0.13, 'vol': 0.40, 'type': 'sine', 'attack': 0.005},
      {'freq': 988,  'dur': 0.13, 'vol': 0.40, 'type': 'sine', 'attack': 0.005},
      {'freq': 1175, 'dur': 0.13, 'vol': 0.40, 'type': 'sine', 'attack': 0.005},
      // אקורד סיום
      {'freq': 1568, 'dur': 0.60, 'vol': 0.42, 'type': 'sine', 'attack': 0.010},
      {'freq': 1976, 'dur': 0.55, 'vol': 0.18, 'type': 'sine', 'attack': 0.010, 'overlap': true},
      {'freq': 2349, 'dur': 0.48, 'vol': 0.10, 'type': 'sine', 'attack': 0.010, 'overlap': true},
    ]);
    if (!kIsWeb) {
      for(int i=0;i<3;i++){await HapticFeedback.lightImpact();if(i<2)await Future.delayed(const Duration(milliseconds:120));}
    }
  }

  // 💀 נכשלת — שלושה "dunk" יורדים, כמו Duolingo כשמפסידים streak
  static Future<void> fail() async {
    if (muted) return;
    playWebTone([
      {'freq': 392, 'glide': 330, 'dur': 0.32, 'vol': 0.42, 'type': 'sine', 'attack': 0.008},
      {'freq': 330, 'glide': 277, 'dur': 0.32, 'vol': 0.38, 'type': 'sine', 'attack': 0.008},
      {'freq': 247, 'glide': 196, 'dur': 0.50, 'vol': 0.34, 'type': 'sine', 'attack': 0.008},
    ]);
    if (!kIsWeb) {
      await HapticFeedback.vibrate();
      await Future.delayed(const Duration(milliseconds: 200));
      await HapticFeedback.vibrate();
    }
  }
}
