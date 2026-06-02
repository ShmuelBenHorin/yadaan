import 'dart:math';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ═══════════════════════════════════════════════
//  קטגוריות עניין (מתאימות למפתחות שאלות)
// ═══════════════════════════════════════════════
class InterestCat {
  final String key, label, emoji;
  final Color color;
  const InterestCat({required this.key, required this.label, required this.emoji, required this.color});

  static const List<InterestCat> all = [
    InterestCat(key:'israel',         label:'ישראל',             emoji:'🇮🇱', color:Color(0xFF1E88E5)),
    InterestCat(key:'judaism',        label:'יהדות',             emoji:'✡️',  color:Color(0xFF8E24AA)),
    InterestCat(key:'football',       label:'כדורגל',            emoji:'⚽',  color:Color(0xFF43A047)),
    InterestCat(key:'world',          label:'עולם',              emoji:'🌍',  color:Color(0xFF00ACC1)),
    InterestCat(key:'geography',      label:'גיאוגרפיה',         emoji:'🗺️',  color:Color(0xFFFF7043)),
    InterestCat(key:'science',        label:'מדע',               emoji:'🔬',  color:Color(0xFF7CB342)),
    InterestCat(key:'sports',         label:'ספורט',             emoji:'🏅',  color:Color(0xFFF4511E)),
    InterestCat(key:'music',          label:'מוזיקה ישראלית',   emoji:'🎵',  color:Color(0xFFE91E63)),
    InterestCat(key:'american_music', label:'מוזיקה אמריקאית', emoji:'🎸',  color:Color(0xFF039BE5)),
  ];

  static InterestCat? forKey(String key) {
    try { return all.firstWhere((c) => c.key == key); } catch (_) { return null; }
  }
}

// ═══════════════════════════════════════════════
//  InterestsService — תחומי עניין + חולשות
// ═══════════════════════════════════════════════
class InterestsService extends ChangeNotifier {
  static final InterestsService _i = InterestsService._();
  static InterestsService get instance => _i;
  InterestsService._();

  Set<String> _interests = {};
  // מספר טעויות לכל קטגוריה (חלון גלגול של 20 אחרונות)
  final Map<String, int> _mistakes = {};
  // מספר ניסיונות לכל קטגוריה
  final Map<String, int> _attempts = {};

  // ─── Getters ────────────────────────────────
  Set<String> get selected => Set.unmodifiable(_interests);
  bool isSelected(String key) => _interests.contains(key);
  bool get hasInterests => _interests.isNotEmpty;

  /// קטגוריות חולשה: 3+ טעויות מתוך 10+ ניסיונות
  Set<String> get weaknesses => _attempts.entries
      .where((e) => e.value >= 8 && (_mistakes[e.key] ?? 0) / e.value > 0.35)
      .map((e) => e.key)
      .toSet();

  /// האם קטגוריה היא חולשה?
  bool isWeakness(String key) => weaknesses.contains(key);

  // ─── Init ────────────────────────────────────
  // ברירת מחדל: כל הקטגוריות חוץ ממוזיקה אמריקאית
  static Set<String> get _defaultInterests =>
      InterestCat.all.map((c) => c.key).where((k) => k != 'american_music').toSet();

  static Future<void> init() async {
    final p = await SharedPreferences.getInstance();
    final saved = p.getStringList('interests_v1');
    _i._interests = (saved ?? _defaultInterests.toList()).toSet();
    for (final c in InterestCat.all) {
      _i._mistakes[c.key]  = p.getInt('weak_m_${c.key}') ?? 0;
      _i._attempts[c.key]  = p.getInt('weak_a_${c.key}') ?? 0;
    }
  }

  // ─── Set Interests ───────────────────────────
  Future<void> setInterests(Set<String> interests) async {
    _interests = interests;
    final p = await SharedPreferences.getInstance();
    await p.setStringList('interests_v1', interests.toList());
    notifyListeners();
  }

  // ─── Record Answer (לזיהוי חולשות) ──────────
  Future<void> recordAnswer({required String category, required bool correct}) async {
    _attempts[category] = (_attempts[category] ?? 0) + 1;
    if (!correct) _mistakes[category] = (_mistakes[category] ?? 0) + 1;
    final p = await SharedPreferences.getInstance();
    await Future.wait([
      p.setInt('weak_m_$category', _mistakes[category]!),
      p.setInt('weak_a_$category', _attempts[category]!),
    ]);
    // notify רק אם הסף השתנה (כדי לא להאט)
    notifyListeners();
  }

  // ─── Weighted Category Picker ────────────────
  /// כל קטגוריה לא-נבחרת מקבלת 3% קבוע בדיוק.
  /// שאר ה-% (100% − 3%×מספר_לא_נבחרות) מתחלק שווה בין הנבחרות,
  /// עם בוסט קל לקטגוריות חולשה (מתוך הנבחרות בלבד).
  String pickCategory(List<String> available, Random rng) {
    if (_interests.isEmpty) {
      return available[rng.nextInt(available.length)];
    }

    final interestCats = available.where(_interests.contains).toList();
    final generalCats  = available.where((c) => !_interests.contains(c)).toList();

    if (interestCats.isEmpty) return available[rng.nextInt(available.length)];

    // כל קטגוריה לא-נבחרת = 3% בדיוק
    final generalTotal = generalCats.length * 0.03;
    final r = rng.nextDouble();

    if (generalCats.isNotEmpty && r < generalTotal) {
      // בחר אחת מהלא-נבחרות בשוויון (כל אחת מקבלת 3%)
      return generalCats[rng.nextInt(generalCats.length)];
    }

    // שאר ה-% לנבחרות — עם בוסט לחולשות
    final weaknessCats = interestCats.where(isWeakness).toList();
    if (weaknessCats.isNotEmpty && rng.nextDouble() < 0.15) {
      return weaknessCats[rng.nextInt(weaknessCats.length)];
    }
    return interestCats[rng.nextInt(interestCats.length)];
  }
}

// ═══════════════════════════════════════════════
//  UI — הכרזה על פיצ'ר חדש (למשתמשים ישנים)
// ═══════════════════════════════════════════════
class InterestsFeatureAnnouncementScreen extends StatelessWidget {
  const InterestsFeatureAnnouncementScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A1628),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Column(
            children: [
              const Spacer(),
              // badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFD700).withOpacity(0.15),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0xFFFFD700).withOpacity(0.5))),
                child: const Text('✨  חדש בידען',
                  style: TextStyle(color: Color(0xFFFFD700), fontSize: 13, fontWeight: FontWeight.w800))),
              const SizedBox(height: 24),
              const Text('🎯', style: TextStyle(fontSize: 64)),
              const SizedBox(height: 20),
              const Text('שאלות שמתאימות לך',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w900)),
              const SizedBox(height: 12),
              const Text(
                'עכשיו אפשר לבחור את הקטגוריות האהובות עליך\nעדיין תקבל שאלות מכל הנושאים — אבל הרבה פחות',
                textAlign: TextAlign.center,
                style: TextStyle(color: Color(0xFF7A90C0), fontSize: 16, height: 1.6)),
              const Spacer(),
              // chips preview
              Wrap(
                spacing: 10, runSpacing: 10,
                alignment: WrapAlignment.center,
                children: InterestCat.all.take(6).map((cat) => Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: cat.color.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: cat.color.withOpacity(0.5))),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Text(cat.emoji, style: const TextStyle(fontSize: 16)),
                    const SizedBox(width: 6),
                    Text(cat.label, style: TextStyle(color: cat.color, fontSize: 13, fontWeight: FontWeight.w700)),
                  ]))).toList()),
              const Spacer(),
              // CTA button
              SizedBox(
                width: double.infinity, height: 54,
                child: ElevatedButton(
                  onPressed: () => Navigator.pushReplacement(context, MaterialPageRoute(
                    builder: (_) => const InterestPickerScreen(isOnboarding: true))),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFFD700),
                    foregroundColor: Colors.black,
                    elevation: 6,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    textStyle: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900)),
                  child: const Text('בחר קטגוריות'))),
              const SizedBox(height: 12),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('דלג', style: TextStyle(color: Color(0xFF546E7A), fontSize: 14))),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════
//  UI — מסך בחירת תחומי עניין
// ═══════════════════════════════════════════════
class InterestPickerScreen extends StatefulWidget {
  final bool isOnboarding; // true = חלק מ-onboarding, false = מהגדרות
  const InterestPickerScreen({super.key, this.isOnboarding = false});
  @override State<InterestPickerScreen> createState() => _IPState();
}

class _IPState extends State<InterestPickerScreen> {
  final Set<String> _sel = {};
  static const _maxUnselected = 5; // אפשר לבטל עד 5 קטגוריות לכל היותר

  @override void initState() {
    super.initState();
    final current = InterestsService.instance.selected;
    // משתמש חדש (אין שמור) → ברירת מחדל: הכל חוץ ממוזיקה אמריקאית
    _sel.addAll(current.isEmpty ? InterestsService._defaultInterests : current);
  }

  int get _unselected => InterestCat.all.length - _sel.length;
  bool get _atLimit    => _unselected >= _maxUnselected;

  @override Widget build(BuildContext context) {
    final canSave = _sel.isNotEmpty;
    return Scaffold(
      backgroundColor: const Color(0xFF0D1B3E),
      body: SafeArea(child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(children: [
          const SizedBox(height: 32),
          const Text('⭐ תחומי העניין שלך', textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w900)),
          const SizedBox(height: 10),
          Text(
            widget.isOnboarding
                ? 'בחר תחומים שמעניינים אותך\nנתאים את השאלות בשבילך'
                : 'בחר את התחומים שמעניינים אותך',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Color(0xFFB0BEC5), fontSize: 15, height: 1.6)),
          const SizedBox(height: 28),
          Expanded(child: GridView.builder(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3, mainAxisSpacing: 12, crossAxisSpacing: 12, childAspectRatio: 1.15),
            itemCount: InterestCat.all.length,
            itemBuilder: (_, i) {
              final cat = InterestCat.all[i];
              final selected = _sel.contains(cat.key);
              return GestureDetector(
                onTap: () {
                  setState(() {
                    if (selected) {
                      // מניעת ביטול אם כבר הגענו למגבלת 5 לא-נבחרות
                      if (_atLimit) return;
                      _sel.remove(cat.key);
                    } else {
                      _sel.add(cat.key);
                    }
                  });
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  decoration: BoxDecoration(
                    color: selected ? cat.color.withOpacity(0.25) : const Color(0xFF1A2A4A),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: selected ? cat.color : const Color(0xFF2A3A5A),
                      width: selected ? 2 : 1),
                    boxShadow: selected ? [BoxShadow(color: cat.color.withOpacity(0.3), blurRadius: 8)] : [],
                  ),
                  child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Text(cat.emoji, style: const TextStyle(fontSize: 28)),
                    const SizedBox(height: 6),
                    Text(cat.label, textAlign: TextAlign.center,
                      style: TextStyle(
                        color: selected ? Colors.white : const Color(0xFF78909C),
                        fontSize: 11, fontWeight: selected ? FontWeight.w700 : FontWeight.w500)),
                  ]),
                ),
              );
            },
          )),
          const SizedBox(height: 12),
          // הסבר ה-3% + אינדיקטור מגבלה
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Column(children: [
              Text(
                _unselected == 0
                    ? 'כל הקטגוריות נבחרו — חלוקה שווה'
                    : 'קטגוריות לא-נבחרות מקבלות 3% סיכוי כל אחת',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Color(0xFF78909C), fontSize: 12)),
              const SizedBox(height: 4),
              Text(
                _atLimit
                    ? '⚠️ הגעת למגבלה — אפשר לבטל עד $_maxUnselected קטגוריות'
                    : 'ניתן לבטל עוד ${_maxUnselected - _unselected} קטגוריות',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: _atLimit ? const Color(0xFFFF7043) : const Color(0xFF546E7A),
                  fontSize: 12, fontWeight: _atLimit ? FontWeight.w700 : FontWeight.w400)),
            ])),
          const SizedBox(height: 12),
          SizedBox(width: double.infinity,
            child: ElevatedButton(
              onPressed: canSave ? _save : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: canSave ? const Color(0xFFFFD700) : const Color(0xFF2A3A5A),
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
              child: Text(widget.isOnboarding ? 'התחל לשחק! 🚀' : 'שמור',
                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900)),
            )),
          const SizedBox(height: 24),
          if (widget.isOnboarding)
            TextButton(
              onPressed: _skip,
              child: const Text('דלג', style: TextStyle(color: Color(0xFF546E7A), fontSize: 14)),
            ),
          const SizedBox(height: 16),
        ]),
      )),
    );
  }

  Future<void> _save() async {
    await InterestsService.instance.setInterests(_sel);
    if (!mounted) return;
    if (widget.isOnboarding) {
      Navigator.pushReplacementNamed(context, '/home');
    } else {
      Navigator.pop(context);
    }
  }

  void _skip() {
    if (widget.isOnboarding) {
      Navigator.pushReplacementNamed(context, '/home');
    } else {
      Navigator.pop(context);
    }
  }
}

// ═══════════════════════════════════════════════
//  UI — כרטיס סטטיסטיקות (לשימוש ב-HomeScreen)
// ═══════════════════════════════════════════════
class UserStatsCard extends StatelessWidget {
  const UserStatsCard({super.key});

  @override Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([]),
      builder: (_, __) => const _StatsContent(),
    );
  }
}

class _StatsContent extends StatelessWidget {
  const _StatsContent();

  @override Widget build(BuildContext context) {
    // imported via main.dart — see integration below
    return const SizedBox.shrink();
  }
}
