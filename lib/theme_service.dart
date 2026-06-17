import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ═══════════════════════════════════════════════════════════════════════
//  ThemeService — רקעים דינמיים מ-Firestore
//  נשלט לגמרי מ-Firebase Console, ללא עדכוני קוד
//
//  מבנה Firestore:
//    app_themes/{key}
//      type:        'mountains' | 'gradient' | 'stadium'
//      skyTop:      'FF04060F'   ← hex עם alpha (8 תווים) או 6 תווים
//      skyBottom:   'FF091230'
//      mtFar:       'FF0D1A40'   ← רק ל-mountains
//      mtMid:       'FF091025'
//      mtNear:      'FF060810'
//      accentColor: 'FF1E8449'   ← צבע גוון כללי (כוכבים, ערפל)
//      starOpacity: 0.15          ← 0.0–1.0
//      starCount:   60
//
//  מפתחות מסכים (key):
//    'home'                         ← מסך בית
//    'levels_easy'                  ← מפת שלבים קל
//    'levels_medium'                ← מפת שלבים בינוני
//    'levels_hard'                  ← מפת שלבים קשה
//    'game_easy'                    ← משחק קל
//    'game_medium'                  ← משחק בינוני
//    'game_hard'                    ← משחק קשה
//    'seasonal_{eventId}'           ← שלבים + משחק של אירוע ספציפי
//    'category_{categoryName}'      ← קטגוריה ספציפית (future)
// ═══════════════════════════════════════════════════════════════════════

class BgConfig {
  final String type; // 'mountains' | 'gradient' | 'stadium'
  final Color skyTop;
  final Color skyBottom;
  final Color mtFar;
  final Color mtMid;
  final Color mtNear;
  final Color accentColor;
  final double starOpacity;
  final int starCount;

  const BgConfig({
    this.type        = 'mountains',
    this.skyTop      = const Color(0xFF04060F),
    this.skyBottom   = const Color(0xFF091230),
    this.mtFar       = const Color(0xFF0D1A40),
    this.mtMid       = const Color(0xFF091025),
    this.mtNear      = const Color(0xFF060810),
    this.accentColor = const Color(0xFF091230),
    this.starOpacity = 0.15,
    this.starCount   = 60,
  });

  /// ברירת מחדל — הרקע הכחול הכהה הנוכחי
  static const BgConfig defaultDark = BgConfig();

  static Color _c(dynamic hex) {
    if (hex == null) return const Color(0xFF04060F);
    final s = (hex as String).replaceAll('#', '');
    return Color(int.parse(s.length == 6 ? 'FF$s' : s, radix: 16));
  }

  factory BgConfig.fromMap(Map<String, dynamic> m) => BgConfig(
    type:        (m['type']        as String?) ?? 'mountains',
    skyTop:      _c(m['skyTop']),
    skyBottom:   _c(m['skyBottom'] ?? m['skyTop']),
    mtFar:       _c(m['mtFar']),
    mtMid:       _c(m['mtMid']),
    mtNear:      _c(m['mtNear']),
    accentColor: _c(m['accentColor'] ?? m['skyBottom']),
    starOpacity: ((m['starOpacity'] as num?) ?? 0.15).toDouble(),
    starCount:   (m['starCount']   as int?) ?? 60,
  );

  Map<String, dynamic> toMap() => {
    'type': type,
    'skyTop':      skyTop.value.toRadixString(16).padLeft(8, '0'),
    'skyBottom':   skyBottom.value.toRadixString(16).padLeft(8, '0'),
    'mtFar':       mtFar.value.toRadixString(16).padLeft(8, '0'),
    'mtMid':       mtMid.value.toRadixString(16).padLeft(8, '0'),
    'mtNear':      mtNear.value.toRadixString(16).padLeft(8, '0'),
    'accentColor': accentColor.value.toRadixString(16).padLeft(8, '0'),
    'starOpacity': starOpacity,
    'starCount':   starCount,
  };
}

// ────────────────────────────────────────────────────────────────────────
class ThemeService extends ChangeNotifier {
  static final ThemeService _i = ThemeService._();
  static ThemeService get instance => _i;
  ThemeService._();

  final Map<String, BgConfig> _themes = {};
  static const _cacheKey = 'app_themes_v1';

  /// מחזיר config לפי מפתח מסך — fallback לברירת מחדל
  BgConfig bgFor(String key) => _themes[key] ?? BgConfig.defaultDark;

  static Future<void> init() async {
    await _i._loadCached();
    _i._fetchFromFirestore(); // ברקע
  }

  Future<void> _fetchFromFirestore() async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('app_themes')
          .get();
      for (final doc in snap.docs) {
        _themes[doc.id] = BgConfig.fromMap(doc.data());
      }
      await _saveCache();
      notifyListeners();
    } catch (e) {
      debugPrint('ThemeService fetch error: $e');
    }
  }

  Future<void> _loadCached() async {
    try {
      final p = await SharedPreferences.getInstance();
      final raw = p.getString(_cacheKey);
      if (raw == null) return;
      final map = jsonDecode(raw) as Map<String, dynamic>;
      map.forEach((k, v) => _themes[k] = BgConfig.fromMap(v as Map<String, dynamic>));
    } catch (_) {}
  }

  Future<void> _saveCache() async {
    try {
      final p = await SharedPreferences.getInstance();
      final map = _themes.map((k, v) => MapEntry(k, v.toMap()));
      await p.setString(_cacheKey, jsonEncode(map));
    } catch (_) {}
  }
}

// ════════════════════════════════════════════════════════════════════════
//  Widget — _ScreenBg
//  שימוש: _ScreenBg('levels_easy') — מחליף את _MountainBg
// ════════════════════════════════════════════════════════════════════════
class ScreenBg extends StatelessWidget {
  final String screenKey;
  const ScreenBg(this.screenKey, {super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ThemeService.instance,
      builder: (_, __) {
        final cfg = ThemeService.instance.bgFor(screenKey);
        return SizedBox.expand(child: CustomPaint(painter: _AppBgPainter(cfg)));
      },
    );
  }
}

// ────────────────────────────────────────────────────────────────────────
class _AppBgPainter extends CustomPainter {
  final BgConfig cfg;
  const _AppBgPainter(this.cfg);

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;

    // שמיים
    canvas.drawRect(
      Rect.fromLTWH(0, 0, w, h),
      Paint()..shader = LinearGradient(
        begin: Alignment.topCenter, end: Alignment.bottomCenter,
        colors: [cfg.skyTop, cfg.skyBottom],
      ).createShader(Rect.fromLTWH(0, 0, w, h)));

    if (cfg.type == 'gradient') return; // gradient בלבד — סיים כאן

    // כוכבים
    for (int i = 0; i < cfg.starCount; i++) {
      final x = i * 137.5 % w;
      final y = i * 89.3 % (h * 0.7);
      final r = i % 3 == 0 ? 1.4 : i % 3 == 1 ? 0.9 : 0.6;
      canvas.drawCircle(
        Offset(x, y), r,
        Paint()..color = Colors.white.withOpacity(cfg.starOpacity + (i % 5) * 0.07));
    }

    if (cfg.type == 'mountains' || cfg.type == 'stadium') {
      // הרים רחוקים
      _mtn(canvas, [
        Offset(0, h), Offset(0, h * 0.75),
        Offset(w * 0.08, h * 0.75), Offset(w * 0.15, h * 0.30), Offset(w * 0.22, h * 0.68),
        Offset(w * 0.32, h * 0.60), Offset(w * 0.40, h * 0.22), Offset(w * 0.48, h * 0.62),
        Offset(w * 0.58, h * 0.55), Offset(w * 0.67, h * 0.18), Offset(w * 0.75, h * 0.58),
        Offset(w * 0.84, h * 0.50), Offset(w * 0.92, h * 0.28), Offset(w, h * 0.55), Offset(w, h),
      ], cfg.mtFar);

      // הרים אמצעיים
      _mtn(canvas, [
        Offset(0, h), Offset(0, h * 0.82),
        Offset(w * 0.10, h * 0.82), Offset(w * 0.18, h * 0.45), Offset(w * 0.26, h * 0.72),
        Offset(w * 0.36, h * 0.65), Offset(w * 0.45, h * 0.35), Offset(w * 0.54, h * 0.68),
        Offset(w * 0.63, h * 0.60), Offset(w * 0.72, h * 0.38), Offset(w * 0.80, h * 0.65),
        Offset(w * 0.89, h * 0.55), Offset(w, h * 0.68), Offset(w, h),
      ], cfg.mtMid);

      // הרים קרובים
      _mtn(canvas, [
        Offset(0, h), Offset(0, h * 0.88),
        Offset(w * 0.12, h * 0.88), Offset(w * 0.20, h * 0.58), Offset(w * 0.28, h * 0.80),
        Offset(w * 0.38, h * 0.74), Offset(w * 0.47, h * 0.55), Offset(w * 0.56, h * 0.76),
        Offset(w * 0.65, h * 0.68), Offset(w * 0.74, h * 0.52), Offset(w * 0.82, h * 0.72),
        Offset(w * 0.91, h * 0.63), Offset(w, h * 0.75), Offset(w, h),
      ], cfg.mtNear);
    }

    if (cfg.type == 'stadium') {
      // דשא אצטדיון — רצועות ירוקות
      final base = cfg.accentColor;
      final dark  = Color.alphaBlend(Colors.black.withOpacity(0.25), base);
      final light = Color.alphaBlend(Colors.white.withOpacity(0.08), base);
      const stripes = 6;
      final stripeH = h * 0.22 / stripes;
      for (int i = 0; i < stripes; i++) {
        canvas.drawRect(
          Rect.fromLTWH(0, h * 0.78 + i * stripeH, w, stripeH),
          Paint()..color = i.isEven ? dark : light);
      }
      // קו אמצע
      canvas.drawLine(Offset(w * 0.5, h * 0.78), Offset(w * 0.5, h),
        Paint()..color = Colors.white.withOpacity(0.08)..strokeWidth = 1.5);
    }

    // ערפל תחתון
    canvas.drawRect(
      Rect.fromLTWH(0, h * 0.75, w, h * 0.25),
      Paint()..shader = LinearGradient(
        begin: Alignment.topCenter, end: Alignment.bottomCenter,
        colors: [Colors.transparent, cfg.accentColor.withOpacity(0.55)],
      ).createShader(Rect.fromLTWH(0, h * 0.75, w, h * 0.25)));
  }

  void _mtn(Canvas c, List<Offset> pts, Color col) {
    final path = Path()..moveTo(pts[0].dx, pts[0].dy);
    for (int i = 1; i < pts.length; i++) path.lineTo(pts[i].dx, pts[i].dy);
    path.close();
    c.drawPath(path, Paint()..color = col);
  }

  @override
  bool shouldRepaint(_AppBgPainter old) => old.cfg != cfg;
}
