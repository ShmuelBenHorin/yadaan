part of 'main.dart';

// ═══════════════════════════════════════════════
//  SeasonalService — שאלות עונתיות מ-Firestore
//  ניהול מ-Firebase Console, ללא עדכון חנות
// ═══════════════════════════════════════════════

class SeasonalEvent {
  final String id, title, emoji, colorHex;
  final DateTime from, until;
  final int order;
  final List<Question> questions;

  const SeasonalEvent({
    required this.id,
    required this.title,
    required this.emoji,
    required this.colorHex,
    required this.from,
    required this.until,
    required this.order,
    required this.questions,
  });

  Color get color {
    final hex = colorHex.replaceAll('#', '').padLeft(6, '0');
    return Color(int.parse('FF$hex', radix: 16));
  }

  bool get isActive {
    final now = DateTime.now();
    return now.isAfter(from) && now.isBefore(until);
  }

  // ימים שנותרו
  int get daysLeft => until.difference(DateTime.now()).inDays.clamp(0, 9999);
}

class SeasonalService extends ChangeNotifier {
  static final SeasonalService _i = SeasonalService._();
  static SeasonalService get instance => _i;
  SeasonalService._();

  List<SeasonalEvent> _events = [];
  bool _loaded = false;
  bool get loaded => _loaded;

  List<SeasonalEvent> get activeEvents {
    final list = _events.where((e) => e.isActive && e.questions.isNotEmpty).toList();
    list.sort((a, b) => a.order.compareTo(b.order));
    return list;
  }

  static Future<void> init() async {
    // שאלות קשועות בקוד — מיידיות, ללא Firestore
    _i._events = _hardcodedEvents();
    await _i._loadCached();   // דריסה/מיזוג עם cache אם יש
    _i._loaded = true;
    _i.notifyListeners();
    _i._fetchFromFirestore(); // רענון ברקע — Firestore גובר על הקשועות
  }

  // ─── שאלות קשועות בקוד ────────────────────────
  static List<SeasonalEvent> _hardcodedEvents() {
    final wc2026questions = [
      Question(id:'wc_01',category:'football',diff:Diff.easy,
        q:'כמה קבוצות ישתתפו במונדיאל 2026?',
        a:['32','40','48','64'],c:2,
        f:'מונדיאל 2026 יהיה הגדול בהיסטוריה עם 48 קבוצות, במקום 32 עד כה.'),
      Question(id:'wc_02',category:'football',diff:Diff.easy,
        q:'באיזה יבשת מתקיים מונדיאל 2026?',
        a:['אירופה','אמריקה הדרומית','אמריקה הצפונית','אסיה'],c:2,
        f:'מונדיאל 2026 מתקיים בארה״ב, קנדה ומקסיקו — שלוש מדינות באמריקה הצפונית.'),
      Question(id:'wc_03',category:'football',diff:Diff.easy,
        q:'מי זכה במונדיאל 2022 בקטאר?',
        a:['צרפת','ארגנטינה','קרואטיה','מרוקו'],c:1,
        f:'ארגנטינה זכתה בגמר נגד צרפת (3:3 אחרי הארכה, 4:2 בפנדלים). מסי הוכתר לשחקן הטורניר.'),
      Question(id:'wc_04',category:'football',diff:Diff.easy,
        q:'מי זכה במונדיאל 2018 ברוסיה?',
        a:['צרפת','קרואטיה','בלגיה','אנגליה'],c:0,
        f:'צרפת ניצחה את קרואטיה 4:2 בגמר. קיליאן מבאפה כיבש שני שערים בגמר בגיל 19.'),
      Question(id:'wc_05',category:'football',diff:Diff.easy,
        q:'כמה פעמים ברזיל זכתה במונדיאל?',
        a:['3','4','5','6'],c:2,
        f:'ברזיל זכתה 5 פעמים: 1958, 1962, 1970, 1994, 2002 — יותר מכל נבחרת אחרת.'),
      Question(id:'wc_06',category:'football',diff:Diff.medium,
        q:'מי השחקן עם הכי הרבה שערים בהיסטוריית המונדיאל?',
        a:['רונאלדו הברזילאי','מירוסלב קלוזה','פלה','גרד מולר'],c:1,
        f:'מירוסלב קלוזה (גרמניה) כיבש 16 שערים במונדיאלים — שיא עולמי. שיחק ב-2002, 2006, 2010, 2014.'),
      Question(id:'wc_07',category:'football',diff:Diff.medium,
        q:'מי כיבש הכי הרבה שערים במונדיאל 2022?',
        a:['ליונל מסי','אוליבייה ז\'ירו','קיליאן מבאפה','מרקוס ראשפורד'],c:2,
        f:'קיליאן מבאפה כיבש 8 שערים במונדיאל 2022, כולל הטריק בגמר נגד ארגנטינה.'),
      Question(id:'wc_08',category:'football',diff:Diff.medium,
        q:'באיזו שנה ישראל השתתפה במונדיאל בפעם היחידה?',
        a:['1958','1966','1970','1974'],c:2,
        f:'ישראל השתתפה במונדיאל 1970 במקסיקו. הפסידה לאורוגוואי (0:2), שוודיה (1:1) ואיטליה (0:0).'),
      Question(id:'wc_09',category:'football',diff:Diff.medium,
        q:'מי זכה במונדיאל הראשון בהיסטוריה (1930)?',
        a:['ברזיל','איטליה','ארגנטינה','אורוגוואי'],c:3,
        f:'אורוגוואי זכתה במונדיאל הראשון בהיסטוריה, שהתקיים אצלם בבית. ניצחה את ארגנטינה 4:2 בגמר.'),
      Question(id:'wc_10',category:'football',diff:Diff.medium,
        q:'כמה פעמים גרמניה זכתה במונדיאל?',
        a:['3','4','5','6'],c:1,
        f:'גרמניה זכתה 4 פעמים: 1954, 1974, 1990, 2014. הזכייה האחרונה הייתה בברזיל.'),
      Question(id:'wc_11',category:'football',diff:Diff.medium,
        q:'כמה מדינות מארחות את מונדיאל 2026?',
        a:['1','2','3','4'],c:2,
        f:'ארה״ב, קנדה ומקסיקו מארחות יחד. זו הפעם הראשונה שמונדיאל מתקיים בשלוש מדינות.'),
      Question(id:'wc_12',category:'football',diff:Diff.hard,
        q:'איזה שחקן כיבש שלושה שערים בגמר מונדיאל 2022?',
        a:['ליונל מסי','אנחל די מריה','קיליאן מבאפה','אוליבייה ז\'ירו'],c:2,
        f:'מבאפה כיבש האט-טריק בגמר נגד ארגנטינה — ה-2 בלבד בהיסטוריית הגמרים. צרפת הפסידה בפנדלים.'),
      Question(id:'wc_13',category:'football',diff:Diff.hard,
        q:'כמה שחקנים נמצאים בסגל כל קבוצה במונדיאל מאז 2022?',
        a:['23','25','26','28'],c:2,
        f:'מאז מונדיאל 2022 הסגל הורחב ל-26 שחקנים (היה 23 לפני כן).'),
      Question(id:'wc_14',category:'football',diff:Diff.hard,
        q:'באיזה איצטדיון יתקיים גמר מונדיאל 2026?',
        a:['סנפורד סטייב','מטלייף סטייב','AT&T סטייב','רוז בול'],c:1,
        f:'גמר מונדיאל 2026 יתקיים ב-MetLife Stadium בניו ג\'רזי (ניו יורק). קיבולת: כ-82,500.'),
      Question(id:'wc_15',category:'football',diff:Diff.hard,
        q:'מה מספר המשחקים שיתקיימו במונדיאל 2026?',
        a:['64','80','96','104'],c:2,
        f:'עם 48 קבוצות ב-104 — לא, 96 משחקים סה"כ. הפורמט: 12 בתות של 4, שלב 32, 16, רבעגמר, חצי, גמר.'),
    ];

    return [
      SeasonalEvent(
        id: 'wc2026_builtin',
        title: 'מונדיאל 2026 ⚽',
        emoji: '⚽',
        colorHex: '1E8449',
        from:  DateTime(2026, 6, 11),
        until: DateTime(2026, 7, 20),
        order: 0,
        questions: wc2026questions,
      ),
    ];
  }

  // ─── Firestore ────────────────────────────────
  Future<void> _fetchFromFirestore() async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('seasonal_events')
          .where('active', isEqualTo: true)
          .get();

      final events = <SeasonalEvent>[];
      for (final doc in snap.docs) {
        final data = doc.data();
        final qSnap = await FirebaseFirestore.instance
            .collection('seasonal_events')
            .doc(doc.id)
            .collection('questions')
            .get();

        final questions = qSnap.docs
            .where((q) => q.data().containsKey('q'))
            .map((q) => Question.fromMap({...q.data(), 'id': q.id}))
            .toList();

        if (questions.isEmpty) continue;

        final from  = (data['from']  as Timestamp).toDate();
        final until = (data['until'] as Timestamp).toDate();

        events.add(SeasonalEvent(
          id:       doc.id,
          title:    data['title']    ?? '',
          emoji:    data['emoji']    ?? '🔥',
          colorHex: data['colorHex'] ?? 'FF6B35',
          from:     from,
          until:    until,
          order:    (data['order']   as int?) ?? 0,
          questions: questions,
        ));
      }

      // מיזוג: Firestore גובר על קשועות, קשועות שאין להן override נשארות
      final firestoreIds = events.map((e) => e.id).toSet();
      final hardcoded = _hardcodedEvents()
          .where((e) => !firestoreIds.contains(e.id))
          .toList();
      _events = [...hardcoded, ...events];
      _loaded = true;
      await _saveCache(_events);
      notifyListeners();
    } catch (e) {
      debugPrint('SeasonalService fetch error: $e');
      _loaded = true;
      notifyListeners();
    }
  }

  // ─── Cache (SharedPreferences) ───────────────
  static const _cacheKey = 'seasonal_events_v1';

  Future<void> _loadCached() async {
    try {
      final p = await SharedPreferences.getInstance();
      final json = p.getString(_cacheKey);
      if (json == null) { _loaded = false; return; }
      final list = jsonDecode(json) as List;
      _events = list.map((e) => _fromCacheMap(e as Map<String, dynamic>)).toList();
      _loaded = true;
    } catch (_) { _loaded = false; }
  }

  Future<void> _saveCache(List<SeasonalEvent> events) async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(_cacheKey, jsonEncode(events.map(_toCacheMap).toList()));
    } catch (_) {}
  }

  Map<String, dynamic> _toCacheMap(SeasonalEvent e) => {
    'id': e.id, 'title': e.title, 'emoji': e.emoji,
    'colorHex': e.colorHex,
    'from':  e.from.millisecondsSinceEpoch,
    'until': e.until.millisecondsSinceEpoch,
    'order': e.order,
    'questions': e.questions.map((q) => {
      'id': q.id, 'category': q.category, 'q': q.q,
      'a': q.a, 'c': q.c, 'd': q.diff.index + 1, 'f': q.f,
    }).toList(),
  };

  SeasonalEvent _fromCacheMap(Map<String, dynamic> m) => SeasonalEvent(
    id:       m['id'],
    title:    m['title'],
    emoji:    m['emoji'],
    colorHex: m['colorHex'],
    from:     DateTime.fromMillisecondsSinceEpoch(m['from'] as int),
    until:    DateTime.fromMillisecondsSinceEpoch(m['until'] as int),
    order:    m['order'] as int,
    questions: (m['questions'] as List)
        .map((q) => Question.fromMap(q as Map<String, dynamic>))
        .toList(),
  );
}
