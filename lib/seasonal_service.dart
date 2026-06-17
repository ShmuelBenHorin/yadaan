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
  /// 'levels'     — מסך שלבים בלבד (ברירת מחדל)
  /// 'categories' — שאלות נכנסות לפול הקל/בינוני/קשה הרגיל
  /// 'both'       — גם שלבים וגם קטגוריות
  final String mode;

  bool get hasLevels     => mode == 'levels'     || mode == 'both';
  bool get hasCategories => mode == 'categories' || mode == 'both';

  const SeasonalEvent({
    required this.id,
    required this.title,
    required this.emoji,
    required this.colorHex,
    required this.from,
    required this.until,
    required this.order,
    required this.questions,
    this.mode = 'levels',
  });

  // ─── שלבים ───────────────────────────────────
  static const _qPerLevel = 5;
  int get levelCount => (questions.length / _qPerLevel).ceil();
  List<Question> levelQuestions(int level) {
    final start = level * _qPerLevel;
    final end   = (start + _qPerLevel).clamp(0, questions.length);
    return questions.sublist(start, end);
  }

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

  // מזריק שאלות עונתיות לפול הקטגוריות הרגיל (mode=categories/both)
  void _updateCategoriesPool() {
    final injected = activeEvents
        .where((e) => e.hasCategories)
        .expand((e) => e.questions)
        .toList();
    QRepo.setSeasonalQuestions(injected);
  }

  static Future<void> init() async {
    // שאלות קשועות בקוד — מיידיות, ללא Firestore
    _i._events = _hardcodedEvents();
    await _i._loadCached();   // דריסה/מיזוג עם cache אם יש
    _i._loaded = true;
    _i._updateCategoriesPool();
    _i.notifyListeners();
    _i._fetchFromFirestore(); // רענון ברקע — Firestore גובר על הקשועות
  }

  // ─── שאלות קשועות בקוד ────────────────────────
  static List<SeasonalEvent> _hardcodedEvents() {
    final wc2026questions = [
      // ── קל מאוד (1-15) ──────────────────────────
      Question(id:'wc_01',category:'football',diff:Diff.easy,
        q:'כמה קבוצות משתתפות במונדיאל 2026?',
        a:['32','40','48','64'],c:2,
        f:'מונדיאל 2026 הוא הגדול בהיסטוריה — 48 קבוצות, לעומת 32 שהיו לפני כן.'),
      Question(id:'wc_02',category:'football',diff:Diff.easy,
        q:'כמה מדינות מארחות את מונדיאל 2026?',
        a:['1','2','3','4'],c:2,
        f:'ארה״ב, קנדה ומקסיקו מארחות יחד — הפעם הראשונה שמונדיאל מתקיים בשלוש מדינות.'),
      Question(id:'wc_03',category:'football',diff:Diff.easy,
        q:'איזו נבחרת מגינה על תואר אלופת העולם במונדיאל 2026?',
        a:['צרפת','ברזיל','ספרד','ארגנטינה'],c:3,
        f:'ארגנטינה זכתה במונדיאל 2022 בקטאר ומגינה על התואר ב-2026.'),
      Question(id:'wc_04',category:'football',diff:Diff.easy,
        q:'כמה ערים מארחות משחקים במונדיאל 2026?',
        a:['12','14','16','20'],c:2,
        f:'16 ערים מארחות: 11 בארה״ב, 3 במקסיקו ו-2 בקנדה.'),
      Question(id:'wc_05',category:'football',diff:Diff.easy,
        q:'מי הוא נשיא FIFA כיום?',
        a:['שפ בלאטר','מישל פלטיני','לנארט יוהנסון','ג\'ובאני אינפנטינו'],c:3,
        f:'ג\'ובאני אינפנטינו מאיטליה נבחר לנשיא FIFA ב-2016 וחידש את כהונתו. הוא יזם את הרחבה ל-48 קבוצות.'),
      Question(id:'wc_06',category:'football',diff:Diff.easy,
        q:'כמה בתות יש בשלב הבתות של מונדיאל 2026?',
        a:['8','10','12','16'],c:2,
        f:'12 בתות, כל אחד עם 4 קבוצות — 72 משחקים בשלב הבתות.'),
      Question(id:'wc_07',category:'football',diff:Diff.easy,
        q:'כמה קבוצות יש בכל בית במונדיאל 2026?',
        a:['3','4','5','6'],c:1,
        f:'12 בתות עם 4 קבוצות בכל אחד — פורמט שמבטיח יותר משחקים ופחות הגרלות.'),
      Question(id:'wc_08',category:'football',diff:Diff.easy,
        q:'לאיזה מועדון שייך קיליאן מבאפה?',
        a:['פריז סן-ז\'רמן','ברצלונה','מנצ\'סטר סיטי','ריאל מדריד'],c:3,
        f:'מבאפה עבר לריאל מדריד בקיץ 2024. כוכב נבחרת צרפת במונדיאל 2026.'),
      Question(id:'wc_09',category:'football',diff:Diff.easy,
        q:'מי קפטן נבחרת ארגנטינה?',
        a:['לאוטארו מרטינס','אנחל די מריה','אמיליאנו מרטינס','ליאונל מסי'],c:3,
        f:'ליאונל מסי, אחד הכדורגלנים הגדולים בהיסטוריה, מוביל את ארגנטינה המגינה על התואר.'),
      Question(id:'wc_10',category:'football',diff:Diff.easy,
        q:'לאיזה מועדון שייך הארי קיין?',
        a:['טוטנהם הוטספר','מנצ\'סטר סיטי','ריאל מדריד','בייארן מינכן'],c:3,
        f:'קיין עבר לבייארן מינכן בקיץ 2023. הוא קפטן נבחרת אנגליה.'),
      Question(id:'wc_11',category:'football',diff:Diff.easy,
        q:'כמה משחקים מתקיימים בסך הכל במונדיאל 2026?',
        a:['64','80','96','104'],c:3,
        f:'104 משחקים — 72 בשלב הבתות ו-32 בשלב הנוק-אאוט. שיא בהיסטוריית גביע העולם.'),
      Question(id:'wc_12',category:'football',diff:Diff.easy,
        q:'לאיזה מועדון שייך ג\'וד בלינגהם?',
        a:['בורוסיה דורטמונד','מנצ\'סטר סיטי','ליברפול','ריאל מדריד'],c:3,
        f:'בלינגהם עבר לריאל מדריד בקיץ 2023 ומהר הפך לאחד הכוכבים של הקבוצה ושל אנגליה.'),
      Question(id:'wc_13',category:'football',diff:Diff.easy,
        q:'מי הכוכב המרכזי של נבחרת ברזיל?',
        a:['נימאר','רודריגו','אנדריק','וינישיוס ג\'וניור'],c:3,
        f:'וינישיוס ג\'וניור מריאל מדריד נחשב לאחד הכוכבים הגדולים בעולם ומוביל את ברזיל.'),
      Question(id:'wc_14',category:'football',diff:Diff.easy,
        q:'לאיזה מועדון שייך וינישיוס ג\'וניור?',
        a:['פלמינגו','ברצלונה','מנצ\'סטר סיטי','ריאל מדריד'],c:3,
        f:'וינישיוס הצטרף לריאל מדריד ב-2018 בגיל 18 והפך לאחד הכוכבים הגדולים בעולם.'),
      Question(id:'wc_15',category:'football',diff:Diff.easy,
        q:'מי הכוכב הצעיר של נבחרת ספרד?',
        a:['פדרי','גאבי','ניקו וויליאמס','למין יאמאל'],c:3,
        f:'למין יאמאל (ברצלונה), יליד 2007 — אחד הכישרונות הצעירים ביותר בהיסטוריית הכדורגל.'),
      // ── קל-בינוני (16-25) ───────────────────────
      Question(id:'wc_16',category:'football',diff:Diff.easy,
        q:'לאיזה מועדון שייך למין יאמאל?',
        a:['ריאל מדריד','פריז סן-ז\'רמן','מנצ\'סטר יונייטד','ברצלונה'],c:3,
        f:'יאמאל גדל באקדמיית לה מאסיה של ברצלונה ופרץ לסגל הבכורה בגיל 16.'),
      Question(id:'wc_17',category:'football',diff:Diff.easy,
        q:'כמה ערים בארה״ב מארחות את מונדיאל 2026?',
        a:['8','9','10','11'],c:3,
        f:'11 ערים אמריקאיות: ניו יורק/ניו ג\'רזי, לוס אנג\'לס, דאלאס, מיאמי, אטלנטה, סיאטל, בוסטון, פילדלפיה, קנסס סיטי, סן פרנסיסקו ויוסטון.'),
      Question(id:'wc_18',category:'football',diff:Diff.easy,
        q:'לאיזה מועדון שייך ג\'מאל מוסיאלה?',
        a:['בורוסיה דורטמונד','בייאר לברקוזן','מנצ\'סטר יונייטד','בייארן מינכן'],c:3,
        f:'מוסיאלה, כוכב גרמניה הצעיר, שייך לבייארן מינכן ונחשב לאחד הכישרונות הגדולים בעולם.'),
      Question(id:'wc_19',category:'football',diff:Diff.easy,
        q:'מי הוא מאמן נבחרת ארגנטינה?',
        a:['חוסה פקרמן','אלביו בסיו','מרסלו גאיארדו','ליאונל סקלוני'],c:3,
        f:'ליאונל סקלוני הוביל את ארגנטינה לזכייה בקופה אמריקה 2021 ובמונדיאל 2022 בקטאר.'),
      Question(id:'wc_20',category:'football',diff:Diff.easy,
        q:'לאיזה מועדון שייך ארלינג הולאן?',
        a:['בורוסיה דורטמונד','ריאל מדריד','ברצלונה','מנצ\'סטר סיטי'],c:3,
        f:'הולאן הצטרף למנצ\'סטר סיטי בקיץ 2022 ושבר שיאי שערים בפרמייר ליג.'),
      Question(id:'wc_21',category:'football',diff:Diff.easy,
        q:'לאיזה מועדון שייך פדרי?',
        a:['ריאל מדריד','אטלטיקו מדריד','סביליה','ברצלונה'],c:3,
        f:'פדרי, קשר ספרד המוכשר, גדל באקדמיית ברצלונה ונחשב לאחד הכישרונות הגדולים בדורו.'),
      Question(id:'wc_22',category:'football',diff:Diff.easy,
        q:'לאיזה מועדון שייך ג\'וליאן אלבארס?',
        a:['ריבר פלייט','מנצ\'סטר סיטי','ברצלונה','אטלטיקו מדריד'],c:3,
        f:'אלבארס עבר לאטלטיקו מדריד בקיץ 2024 לאחר שזכה עם מנצ\'סטר סיטי בכל התארים.'),
      Question(id:'wc_23',category:'football',diff:Diff.easy,
        q:'כמה קבוצות אירופאיות משתתפות במונדיאל 2026?',
        a:['13','14','15','16'],c:3,
        f:'אירופה (UEFA) מייצגת 16 קבוצות — נתח הגדול ביותר מכל קבוצת יבשות.'),
      Question(id:'wc_24',category:'football',diff:Diff.easy,
        q:'כמה קבוצות מדרום אמריקה משתתפות במונדיאל 2026?',
        a:['4','5','6','7'],c:2,
        f:'CONMEBOL (דרום אמריקה) מקבלת 6 מקומות ישירים למונדיאל 2026.'),
      Question(id:'wc_25',category:'football',diff:Diff.medium,
        q:'כמה משחקים מתקיימים בשלב הבתות של מונדיאל 2026?',
        a:['48','56','64','72'],c:3,
        f:'12 בתות × 6 משחקים לכל בית (4 קבוצות, כל אחת נגד כולן) = 72 משחקים.'),
      // ── בינוני (26-40) ──────────────────────────
      Question(id:'wc_26',category:'football',diff:Diff.medium,
        q:'מי הוא מאמן נבחרת צרפת?',
        a:['זינדין זידאן','ריימון דומנך','לורן בלאן','דידיה דשאן'],c:3,
        f:'דידיה דשאן מאמן את צרפת מאז 2012 והוביל אותה לזכייה במונדיאל 2018. כוכב בעצמו בניצחון 1998.'),
      Question(id:'wc_27',category:'football',diff:Diff.medium,
        q:'כמה ערים מקסיקניות מארחות את מונדיאל 2026?',
        a:['2','3','4','5'],c:1,
        f:'שלוש ערים מקסיקניות: מקסיקו סיטי, גוואדלחרה ומונטריי. מקסיקו ארחה גם ב-1970 וב-1986 — 2026 תהיה הפעם השלישית שלה.'),
      Question(id:'wc_28',category:'football',diff:Diff.medium,
        q:'לאיזה מועדון שייך ניקו וויליאמס?',
        a:['ברצלונה','ריאל מדריד','סביליה','אתלטיק בילבאו'],c:3,
        f:'ניקו וויליאמס נאמן לאתלטיק בילבאו — קבוצה שמכבדת שחקנים בסקים בלבד.'),
      Question(id:'wc_29',category:'football',diff:Diff.medium,
        q:'לאיזה מועדון שייך לאוטארו מרטינס?',
        a:['בוקה ג\'וניורס','ריאל מדריד','ברצלונה','אינטר מילאן'],c:3,
        f:'מרטינס, חלוץ ארגנטינה, שייך לאינטר מילאן ומוביל את הקבוצה בשנים האחרונות.'),
      Question(id:'wc_30',category:'football',diff:Diff.medium,
        q:'מי הוא מאמן נבחרת ספרד?',
        a:['לואיס אנריקה','ביסנטה דל בוסקה','רוברטו מורינו','לואיס דה לה פואנטה'],c:3,
        f:'לואיס דה לה פואנטה מינה לתפקיד ב-2023 והוביל את ספרד לזכייה באליפות אירופה 2024.'),
      Question(id:'wc_31',category:'football',diff:Diff.medium,
        q:'כמה ערים קנדיות מארחות את מונדיאל 2026?',
        a:['1','2','3','4'],c:1,
        f:'שתי ערים קנדיות: טורונטו (BMO Field) ווונקובר (BC Place). קנדה תארח את המונדיאל הראשון שלה אי פעם.'),
      Question(id:'wc_32',category:'football',diff:Diff.medium,
        q:'באיזו שנה ארחה מקסיקו את המונדיאל הקודמת לפני 2026?',
        a:['1970','1978','1982','1986'],c:3,
        f:'מקסיקו ארחה את המונדיאל ב-1970 (ברזיל זכתה) וב-1986 (ארגנטינה זכתה). ב-2026 זו הפעם השלישית.'),
      Question(id:'wc_33',category:'football',diff:Diff.medium,
        q:'כמה קבוצות מאפריקה משתתפות במונדיאל 2026?',
        a:['7','8','9','10'],c:2,
        f:'CAF (אפריקה) מקבלת 9 מקומות ישירים — עלייה לעומת 5 שהיו כשהיו רק 32 קבוצות.'),
      Question(id:'wc_34',category:'football',diff:Diff.medium,
        q:'כמה קבוצות ממקום שלישי בבתות מתקדמות לשלב הנוק-אאוט?',
        a:['6','8','10','12'],c:1,
        f:'8 הטובות מבין 12 קבוצות שסיימו שלישיות בבתים מתקדמות — סה״כ 32 קבוצות בשלב הנוק-אאוט.'),
      Question(id:'wc_35',category:'football',diff:Diff.medium,
        q:'לאיזה מועדון שייך רודרי?',
        a:['אטלטיקו מדריד','ברצלונה','ריאל מדריד','מנצ\'סטר סיטי'],c:3,
        f:'רודרי, מחזיק כדור הזהב לשנת 2024, שייך למנצ\'סטר סיטי וקשר ספרד.'),
      Question(id:'wc_36',category:'football',diff:Diff.medium,
        q:'מי הוא מאמן נבחרת פורטוגל?',
        a:['פרנאנדו סנטוש','לואיס פיגו','רובן פינייארו','רוברטו מרטינס'],c:3,
        f:'רוברטו מרטינס מבלגיה מינה לתפקיד ב-2023 לאחר עידן פרנאנדו סנטוש. מוביל את פורטוגל עם רונאלדו ועמיתיו.'),
      Question(id:'wc_37',category:'football',diff:Diff.medium,
        q:'לאיזה מועדון שייך ברונו פרננדס?',
        a:['ספורטינג ליסבון','ברנפיקה','ריאל מדריד','מנצ\'סטר יונייטד'],c:3,
        f:'פרננדס עבר למנצ\'סטר יונייטד ב-2020 והפך לשחקן המפתח וקפטן הקבוצה.'),
      Question(id:'wc_38',category:'football',diff:Diff.medium,
        q:'לאיזה מועדון שייך בוקאיו סאקה?',
        a:['צ\'לסי','טוטנהם הוטספר','מנצ\'סטר סיטי','ארסנל'],c:3,
        f:'סאקה, כנף אנגליה המוכשר, עלה דרך האקדמיה של ארסנל ונחשב לאחד הטובים בעולם.'),
      Question(id:'wc_39',category:'football',diff:Diff.medium,
        q:'כמה קבוצות מאסיה משתתפות במונדיאל 2026?',
        a:['5','6','7','8'],c:3,
        f:'AFC (אסיה) מקבלת 8 מקומות ישירים — עלייה משמעותית לעומת 4.5 שהיו ב-32 קבוצות.'),
      Question(id:'wc_40',category:'football',diff:Diff.medium,
        q:'לאיזה מועדון שייך אמיליאנו מרטינס?',
        a:['מנצ\'סטר יונייטד','ברייטון','צ\'לסי','אסטון וילה'],c:3,
        f:'מרטינס (דיבו), שוער ארגנטינה, שייך לאסטון וילה ונחשב לאחד השוערים הטובים בעולם.'),
      // ── קשה (41-50) ─────────────────────────────
      Question(id:'wc_41',category:'football',diff:Diff.hard,
        q:'כמה פעמים זכתה ארגנטינה בגביע העולם?',
        a:['פעמיים','שלוש פעמים','ארבע פעמים','חמש פעמים'],c:1,
        f:'ארגנטינה זכתה שלוש פעמים: 1978 (בית, נגד הולנד), 1986 (מקסיקו, עם מרדונה) ו-2022 (קטאר, עם מסי).'),
      Question(id:'wc_42',category:'football',diff:Diff.hard,
        q:'מי הוא מאמן נבחרת אנגליה?',
        a:['גארת\' סאות\'גייט','פרנק לאמפארד','סטיבן ג\'רארד','תומאס טוכל'],c:3,
        f:'תומאס טוכל מגרמניה מינה לאמן אנגליה בספטמבר 2024, לאחר שגארת\' סאות\'גייט עזב עם תום יורו 2024.'),
      Question(id:'wc_43',category:'football',diff:Diff.hard,
        q:'כמה פעמים זכתה גרמניה בגביע העולם?',
        a:['שלוש פעמים','ארבע פעמים','חמש פעמים','שש פעמים'],c:1,
        f:'גרמניה זכתה ארבע פעמים: 1954, 1974, 1990 ו-2014 (ברזיל, 7-1 בחצי גמר נגד ברזיל).'),
      Question(id:'wc_44',category:'football',diff:Diff.hard,
        q:'לאיזה מועדון שייך רפאל לאו?',
        a:['יובנטוס','אינטר מילאן','נאפולי','אי.סי. מילאן'],c:3,
        f:'לאו, כנף פורטוגל, שייך לאי.סי. מילאן ונחשב לאחד הכוכבים המהירים ביותר בכדורגל.'),
      Question(id:'wc_45',category:'football',diff:Diff.hard,
        q:'לאיזה מועדון שייך אנדריק?',
        a:['פלמיירס','ברצלונה','בייארן מינכן','ריאל מדריד'],c:3,
        f:'אנדריק, כוכב ברזיל הצעיר, הצטרף לריאל מדריד בקיץ 2024 בגיל 18.'),
      Question(id:'wc_46',category:'football',diff:Diff.hard,
        q:'מי הוא מאמן נבחרת גרמניה?',
        a:['הנסי פליק','טומאס טוכל','יואכים לב','יוליאן נגלסמן'],c:3,
        f:'יוליאן נגלסמן מינה לתפקיד ב-2023 והחזיר את גרמניה לרמה גבוהה.'),
      Question(id:'wc_47',category:'football',diff:Diff.hard,
        q:'מי הוא מאמן נבחרת ברזיל?',
        a:['טייטה','פ\'ליפה סקולארי','אנדרה יארלי','דורבאל ג\'וניור'],c:3,
        f:'דורבאל ג\'וניור מינה לאמן ברזיל בינואר 2024. בעברו אימן את פלמינגו וקורינתיאנס וידוע כמומחה לכדורגל התקפי.'),
      Question(id:'wc_48',category:'football',diff:Diff.hard,
        q:'לאיזה מועדון שייך רפיניה?',
        a:['לידס יונייטד','אייאקס','אטלטיקו מדריד','ברצלונה'],c:3,
        f:'רפיניה עבר לברצלונה ב-2022 מלידס יונייטד ונהפך לאחד מכוכבי הקבוצה ונבחרת ברזיל.'),
      Question(id:'wc_49',category:'football',diff:Diff.hard,
        q:'כמה פעמים Estadio Azteca ארח את גביע העולם לפני מונדיאל 2026?',
        a:['פעם אחת','פעמיים','שלוש פעמים','ארבע פעמים'],c:1,
        f:'האצטקה ארח ב-1970 (ברזיל זכתה) וב-1986 (ארגנטינה זכתה). ב-2026 זו הפעם השלישית — שיא עולמי.'),
      Question(id:'wc_50',category:'football',diff:Diff.hard,
        q:'לאיזה מועדון שייך אדואר קמאבינגה?',
        a:['מונאקו','סטאד דה ריים','ליל','ריאל מדריד'],c:3,
        f:'קמאבינגה הצטרף לריאל מדריד ב-2021 מהקבוצה הצרפתית רן (Rennes) והפך לאחד המגנים המוכשרים בעולם — כוכב נבחרת צרפת.'),
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
          mode:     data['mode']     ?? 'levels',
        ));
      }

      // מיזוג: Firestore גובר על קשועות, קשועות שאין להן override נשארות
      final firestoreIds = events.map((e) => e.id).toSet();
      final hardcoded = _hardcodedEvents()
          .where((e) => !firestoreIds.contains(e.id))
          .toList();
      _events = [...hardcoded, ...events];
      _loaded = true;
      _updateCategoriesPool();
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
    'mode':  e.mode,
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
    mode:     (m['mode'] as String?) ?? 'levels',
    questions: (m['questions'] as List)
        .map((q) => Question.fromMap(q as Map<String, dynamic>))
        .toList(),
  );
}
