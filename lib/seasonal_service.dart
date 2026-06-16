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
      // ── קל מאוד (1-10) ──────────────────────────
      Question(id:'wc_01',category:'football',diff:Diff.easy,
        q:'כמה שחקנים משחקים בכל קבוצת כדורגל על המגרש?',
        a:['9','10','11','12'],c:2,
        f:'כל קבוצת כדורגל משחקת עם 11 שחקנים על המגרש, כולל השוער.'),
      Question(id:'wc_02',category:'football',diff:Diff.easy,
        q:'כמה קבוצות משתתפות במונדיאל 2026?',
        a:['32','40','48','64'],c:2,
        f:'מונדיאל 2026 הוא הגדול בהיסטוריה עם 48 קבוצות — במקום 32 שהיו עד כה.'),
      Question(id:'wc_03',category:'football',diff:Diff.easy,
        q:'מי זכה במונדיאל 2022 בקטאר?',
        a:['צרפת','ארגנטינה','קרואטיה','מרוקו'],c:1,
        f:'ארגנטינה ניצחה את צרפת בגמר — 3:3 אחרי הארכה, 4:2 בפנדלים. מסי קיבל כדור זהב.'),
      Question(id:'wc_04',category:'football',diff:Diff.easy,
        q:'כמה מדינות מארחות את מונדיאל 2026?',
        a:['1','2','3','4'],c:2,
        f:'ארה״ב, קנדה ומקסיקו מארחות יחד — הפעם הראשונה שמונדיאל מתקיים בשלוש מדינות.'),
      Question(id:'wc_05',category:'football',diff:Diff.easy,
        q:'מי זכה במונדיאל 2018 ברוסיה?',
        a:['צרפת','קרואטיה','בלגיה','אנגליה'],c:0,
        f:'צרפת ניצחה את קרואטיה 4:2 בגמר. מבאפה כיבש שני שערים בגיל 19.'),
      Question(id:'wc_06',category:'football',diff:Diff.easy,
        q:'כמה פעמים ברזיל זכתה בגביע העולם?',
        a:['3','4','5','6'],c:2,
        f:'ברזיל זכתה 5 פעמים: 1958, 1962, 1970, 1994, 2002 — יותר מכל מדינה אחרת.'),
      Question(id:'wc_07',category:'football',diff:Diff.easy,
        q:'מי זכה במונדיאל 2014 בברזיל?',
        a:['ברזיל','ארגנטינה','גרמניה','הולנד'],c:2,
        f:'גרמניה ניצחה את ארגנטינה 1:0 בהארכה. מריו גוצה כיבש בדקה 113.'),
      Question(id:'wc_08',category:'football',diff:Diff.easy,
        q:'באיזה יבשת מתקיים מונדיאל 2026?',
        a:['אירופה','אמריקה הדרומית','אמריקה הצפונית','אסיה'],c:2,
        f:'מונדיאל 2026 מתקיים בארה״ב, קנדה ומקסיקו — שלוש מדינות באמריקה הצפונית.'),
      Question(id:'wc_09',category:'football',diff:Diff.easy,
        q:'מי זכה במונדיאל 2010 בדרום אפריקה?',
        a:['ספרד','הולנד','גרמניה','ארגנטינה'],c:0,
        f:'ספרד ניצחה את הולנד 1:0 בהארכה. אנדרס אינייסטה כיבש את שער הזכייה.'),
      Question(id:'wc_10',category:'football',diff:Diff.easy,
        q:'איזו מדינה זכתה בגביע העולם יותר פעמים מכל מדינה אחרת?',
        a:['גרמניה','איטליה','ברזיל','ארגנטינה'],c:2,
        f:'ברזיל זכתה 5 פעמים — שיא עולמי. גרמניה ואיטליה זכו 4 פעמים כל אחת.'),
      // ── קל (11-20) ──────────────────────────────
      Question(id:'wc_11',category:'football',diff:Diff.easy,
        q:'כמה פעמים גרמניה זכתה בגביע העולם?',
        a:['3','4','5','6'],c:1,
        f:'גרמניה זכתה 4 פעמים: 1954, 1974, 1990, 2014.'),
      Question(id:'wc_12',category:'football',diff:Diff.easy,
        q:'כמה פעמים איטליה זכתה בגביע העולם?',
        a:['3','4','5','6'],c:1,
        f:'איטליה זכתה 4 פעמים: 1934, 1938, 1982, 2006.'),
      Question(id:'wc_13',category:'football',diff:Diff.easy,
        q:'מי זכה במונדיאל 2006 בגרמניה?',
        a:['גרמניה','צרפת','פורטוגל','איטליה'],c:3,
        f:'איטליה ניצחה את צרפת בפנדלים 5:3. זידאן הורחק מהמגרש עם נגיחה.'),
      Question(id:'wc_14',category:'football',diff:Diff.easy,
        q:'כמה פעמים ארגנטינה זכתה בגביע העולם?',
        a:['2','3','4','5'],c:1,
        f:'ארגנטינה זכתה 3 פעמים: 1978, 1986, 2022.'),
      Question(id:'wc_15',category:'football',diff:Diff.easy,
        q:'מי זכה במונדיאל 2002 ביפן ודרום קוריאה?',
        a:['ארגנטינה','גרמניה','ברזיל','ספרד'],c:2,
        f:'ברזיל ניצחה את גרמניה 2:0 בגמר. רונאלדו (הברזילאי) כיבש שני שערים.'),
      Question(id:'wc_16',category:'football',diff:Diff.easy,
        q:'מה שם האיצטדיון שבו מתקיים גמר מונדיאל 2026?',
        a:['רוז בול','AT&T Stadium','MetLife Stadium','Levi\'s Stadium'],c:2,
        f:'גמר מונדיאל 2026 מתקיים ב-MetLife Stadium בניו ג\'רזי, ליד ניו יורק. קיבולת: 82,500.'),
      Question(id:'wc_17',category:'football',diff:Diff.easy,
        q:'מי זכה במונדיאל 1998 בצרפת?',
        a:['ברזיל','איטליה','גרמניה','צרפת'],c:3,
        f:'צרפת ניצחה את ברזיל 3:0 בגמר. זינדין זידאן כיבש שני שערים.'),
      Question(id:'wc_18',category:'football',diff:Diff.easy,
        q:'כמה שחקנים נמצאים בסגל כל קבוצה במונדיאל?',
        a:['23','24','25','26'],c:3,
        f:'מאז מונדיאל 2022 הסגל הורחב ל-26 שחקנים, במקום 23 שהיו לפני כן.'),
      Question(id:'wc_19',category:'football',diff:Diff.easy,
        q:'מי זכה במונדיאל 1994 בארה״ב?',
        a:['איטליה','ברזיל','ספרד','גרמניה'],c:1,
        f:'ברזיל ניצחה את איטליה בפנדלים 3:2. רוברטו באג\'יו החמיץ את הפנדל המכריע.'),
      Question(id:'wc_20',category:'football',diff:Diff.easy,
        q:'באיזו שנה ישראל השתתפה לראשונה בגביע העולם?',
        a:['1958','1962','1970','1974'],c:2,
        f:'ישראל השתתפה לראשונה במונדיאל 1970 במקסיקו. שיחקה מול אורוגוואי, שוודיה ואיטליה.'),
      // ── בינוני (21-35) ──────────────────────────
      Question(id:'wc_21',category:'football',diff:Diff.medium,
        q:'מי זכה במונדיאל הראשון בהיסטוריה (1930)?',
        a:['ברזיל','איטליה','ארגנטינה','אורוגוואי'],c:3,
        f:'אורוגוואי זכתה במונדיאל הראשון שהתקיים אצלה. ניצחה את ארגנטינה 4:2 בגמר.'),
      Question(id:'wc_22',category:'football',diff:Diff.medium,
        q:'מי כיבש הכי הרבה שערים במונדיאל 2022?',
        a:['ליונל מסי','אנחל די מריה','קיליאן מבאפה','אוליבייה ז\'ירו'],c:2,
        f:'קיליאן מבאפה כיבש 8 שערים במונדיאל 2022 — כולל האט-טריק בגמר.'),
      Question(id:'wc_23',category:'football',diff:Diff.medium,
        q:'מי זכה במונדיאל 1990 באיטליה?',
        a:['איטליה','ארגנטינה','גרמניה המערבית','אנגליה'],c:2,
        f:'גרמניה המערבית ניצחה את ארגנטינה 1:0 בגמר.'),
      Question(id:'wc_24',category:'football',diff:Diff.medium,
        q:'מי זכה במונדיאל 1986 במקסיקו?',
        a:['גרמניה המערבית','ארגנטינה','ברזיל','צרפת'],c:1,
        f:'ארגנטינה ניצחה את גרמניה המערבית 3:2 בגמר. מרדונה היה כוכב הטורניר.'),
      Question(id:'wc_25',category:'football',diff:Diff.medium,
        q:'מי זכה במונדיאל 1982 בספרד?',
        a:['ברזיל','גרמניה המערבית','פולין','איטליה'],c:3,
        f:'איטליה ניצחה את גרמניה המערבית 3:1 בגמר. פאולו רוסי כיבש 6 שערים בטורניר.'),
      Question(id:'wc_26',category:'football',diff:Diff.medium,
        q:'מי זכה במונדיאל 1978 בארגנטינה?',
        a:['ברזיל','הולנד','פרו','ארגנטינה'],c:3,
        f:'ארגנטינה ניצחה את הולנד 3:1 בהארכה בגמר. זכייתה הראשונה.'),
      Question(id:'wc_27',category:'football',diff:Diff.medium,
        q:'מי זכה במונדיאל 1974 בגרמניה המערבית?',
        a:['הולנד','פולין','גרמניה המערבית','שוודיה'],c:2,
        f:'גרמניה המערבית ניצחה את הולנד 2:1 בגמר. יוהאן קרויף הוביל את ההולנדים.'),
      Question(id:'wc_28',category:'football',diff:Diff.medium,
        q:'מי קיבל את פרס השחקן הטוב ביותר (כדור זהב) במונדיאל 2022?',
        a:['קיליאן מבאפה','לוקה מודריץ\'','ליונל מסי','אמיליאנו מרטינס'],c:2,
        f:'ליונל מסי קיבל את כדור הזהב במונדיאל 2022 — זכייתו השנייה בפרס זה (גם 2014).'),
      Question(id:'wc_29',category:'football',diff:Diff.medium,
        q:'מי זכה במונדיאל 1970 במקסיקו?',
        a:['איטליה','אנגליה','גרמניה המערבית','ברזיל'],c:3,
        f:'ברזיל ניצחה את איטליה 4:1 בגמר. פלה פתח בשער ראשון. אחד הגמרים הטובים בהיסטוריה.'),
      Question(id:'wc_30',category:'football',diff:Diff.medium,
        q:'מי זכה במונדיאל 1966 באנגליה?',
        a:['גרמניה המערבית','פורטוגל','ברזיל','אנגליה'],c:3,
        f:'אנגליה ניצחה את גרמניה המערבית 4:2 בהארכה. ג\'ף הרסט כיבש האט-טריק.'),
      Question(id:'wc_31',category:'football',diff:Diff.medium,
        q:'איזו קבוצה אפריקאית הגיעה לחצי גמר המונדיאל לראשונה בהיסטוריה?',
        a:['סנגל','ניגריה','קמרון','מרוקו'],c:3,
        f:'מרוקו הפכה ב-2022 לקבוצה האפריקאית הראשונה שהגיעה לחצי הגמר של גביע העולם.'),
      Question(id:'wc_32',category:'football',diff:Diff.medium,
        q:'מי זכה במונדיאל 1962 בצ\'ילה?',
        a:['צ\'כוסלובקיה','ארגנטינה','ברזיל','צ\'ילה'],c:2,
        f:'ברזיל ניצחה את צ\'כוסלובקיה 3:1 בגמר. גרינצ\'ה היה כוכב הטורניר.'),
      Question(id:'wc_33',category:'football',diff:Diff.medium,
        q:'מי זכה במונדיאל 1958 בשוודיה?',
        a:['שוודיה','צרפת','גרמניה המערבית','ברזיל'],c:3,
        f:'ברזיל ניצחה את שוודיה 5:2 בגמר. פלה בן ה-17 כיבש שני שערים.'),
      Question(id:'wc_34',category:'football',diff:Diff.medium,
        q:'מי קיבל את פרס הכפפת הזהב (שוער הטורניר) במונדיאל 2022?',
        a:['הוגו לוריס','דומינק לייבה','אמיליאנו מרטינס','טיבו קורטואה'],c:2,
        f:'אמיליאנו מרטינס (ארגנטינה) קיבל את הכפפת הזהב — שמר על שוורים קריטיים בחצי גמר ובגמר.'),
      Question(id:'wc_35',category:'football',diff:Diff.medium,
        q:'מי זכה במונדיאל 1950 בברזיל?',
        a:['ברזיל','ספרד','שוודיה','אורוגוואי'],c:3,
        f:'אורוגוואי ניצחה את ברזיל 2:1 במשחק האחרון בפני ~200,000 צופים ב-Maracanã — המכונה "מראקנאסו".'),
      // ── קשה (36-50) ─────────────────────────────
      Question(id:'wc_36',category:'football',diff:Diff.hard,
        q:'מי השחקן עם הכי הרבה שערים בהיסטוריית גביע העולם?',
        a:['רונאלדו הברזילאי','פלה','גרד מולר','מירוסלב קלוזה'],c:3,
        f:'מירוסלב קלוזה (גרמניה) כיבש 16 שערים ב-4 מונדיאלים (2002-2014) — שיא עולמי.'),
      Question(id:'wc_37',category:'football',diff:Diff.hard,
        q:'איזה שחקן כיבש האט-טריק בגמר מונדיאל 2022?',
        a:['ליונל מסי','אנחל די מריה','אוליבייה ז\'ירו','קיליאן מבאפה'],c:3,
        f:'מבאפה כיבש 3 שערים בגמר. לפניו רק ג\'ף הרסט (אנגליה, 1966) כיבש האט-טריק בגמר מונדיאל.'),
      Question(id:'wc_38',category:'football',diff:Diff.hard,
        q:'מי כיבש הכי הרבה שערים במונדיאל אחד?',
        a:['פלה (1958)','גרד מולר (1970)','ז\'וסט פונטן (1958)','רונאלדו (2002)'],c:2,
        f:'ז\'וסט פונטן (צרפת) כיבש 13 שערים במונדיאל 1958 בשוודיה — שיא שעומד עד היום.'),
      Question(id:'wc_39',category:'football',diff:Diff.hard,
        q:'כמה פעמים גמר מונדיאל הוכרע בפנדלים (עד 2022)?',
        a:['2','3','4','5'],c:1,
        f:'שלושה גמרים הוכרעו בפנדלים: 1994 (ברזיל-איטליה), 2006 (איטליה-צרפת), 2022 (ארגנטינה-צרפת).'),
      Question(id:'wc_40',category:'football',diff:Diff.hard,
        q:'מי זכה בנעל הזהב (מלך השערים) במונדיאל 2022?',
        a:['ליונל מסי','אוליבייה ז\'ירו','אנחל די מריה','קיליאן מבאפה'],c:3,
        f:'מבאפה זכה בנעל הזהב עם 8 שערים — הכי הרבה בטורניר.'),
      Question(id:'wc_41',category:'football',diff:Diff.hard,
        q:'מי הוא השחקן המבוגר ביותר שכיבש שער במונדיאל?',
        a:['פלה','פרנצ\'סקו טוטי','רוג\'ר מילה','ריקאלדו'],c:2,
        f:'רוג\'ר מילה (קמרון) כיבש שער במונדיאל 1994 בגיל 42 — שיא גיל בהיסטוריית המונדיאל.'),
      Question(id:'wc_42',category:'football',diff:Diff.hard,
        q:'מי זכה במונדיאל 1954 בשוויץ?',
        a:['הונגריה','אוסטריה','גרמניה המערבית','ברזיל'],c:2,
        f:'גרמניה המערבית ניצחה את הונגריה 3:2 — "נס ברן". הונגריה לא הפסידה 4 שנים לפני הגמר.'),
      Question(id:'wc_43',category:'football',diff:Diff.hard,
        q:'כמה פעמים הולנד הגיעה לגמר מונדיאל מבלי לזכות?',
        a:['2','3','4','5'],c:1,
        f:'הולנד הגיעה לגמר 3 פעמים (1974, 1978, 2010) ולא זכתה אף פעם.'),
      Question(id:'wc_44',category:'football',diff:Diff.hard,
        q:'מי זכה במונדיאל 1938 בצרפת?',
        a:['צרפת','הונגריה','ברזיל','איטליה'],c:3,
        f:'איטליה ניצחה את הונגריה 4:2 — זכייתה השנייה ברציפות תחת המאמן ויטוריו פוצו.'),
      Question(id:'wc_45',category:'football',diff:Diff.hard,
        q:'מי זכה במונדיאל 1934 באיטליה?',
        a:['גרמניה','צ\'כוסלובקיה','איטליה','אוסטריה'],c:2,
        f:'איטליה ניצחה את צ\'כוסלובקיה 2:1 בהארכה. המארחת זכתה בביתה.'),
      Question(id:'wc_46',category:'football',diff:Diff.hard,
        q:'כמה פעמים צרפת הגיעה לגמר המונדיאל?',
        a:['2','3','4','5'],c:1,
        f:'צרפת הגיעה לגמר 3 פעמים: 1998 (זכתה), 2006 (הפסידה לאיטליה), 2022 (הפסידה לארגנטינה).'),
      Question(id:'wc_47',category:'football',diff:Diff.hard,
        q:'מה היה התוצאה הגבוהה ביותר בגמר מונדיאל מבחינת מספר שערים?',
        a:['4:2','4:1','5:2','3:1'],c:2,
        f:'ברזיל ניצחה את שוודיה 5:2 בגמר 1958 — הגמר עם הכי הרבה שערים בהיסטוריה.'),
      Question(id:'wc_48',category:'football',diff:Diff.hard,
        q:'מי הוא המאמן היחיד שזכה פעמיים במונדיאל כמאמן?',
        a:['דידייה דשאן','הלמוט שון','ויטוריו פוצו','ביאנצ\'י'],c:2,
        f:'ויטוריו פוצו הוביל את איטליה לזכייה ב-1934 וב-1938 — הישג ייחודי שלא הושג מאז.'),
      Question(id:'wc_49',category:'football',diff:Diff.hard,
        q:'כמה פעמים ספרד השתתפה בגמר המונדיאל?',
        a:['1','2','3','4'],c:0,
        f:'ספרד הגיעה לגמר פעם אחת בלבד — 2010 (ניצחה את הולנד 1:0 בהארכה) — וזכתה.'),
      Question(id:'wc_50',category:'football',diff:Diff.hard,
        q:'מה שמה של נבחרת ברזיל בפורטוגזית?',
        a:['Os Verdes','A Seleção','Canarinha','Auriverde'],c:1,
        f:'"A Seleção" (הנבחרת) הוא הכינוי הרשמי. "Canarinha" (הכנרית הצהובה) הוא הכינוי העממי.'),
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
