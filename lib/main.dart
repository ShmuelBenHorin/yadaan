import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'questions_easy.dart';
import 'questions_medium.dart';
import 'questions_hard.dart';
import 'sfx_stub.dart' if (dart.library.html) 'sfx_web.dart';
// ═══════════════════════════════════════════════
//  CONFIG
// ═══════════════════════════════════════════════
class Cfg {
  static const rcAndroid            = 'YOUR_REVENUECAT_ANDROID_KEY';
  static const rciOS                = 'appl_DSEyAVZKuOktZXgzNqiPKhjnOlO';
  static const entitlement          = 'premium';
  static const devCode              = 'shmuel1231';
  static const mockPremium          = false;
  static const adMobEnabled         = true;
  static const adEnergyThreshold    = 3;

  // ─── AdMob Ad Unit IDs ───────────────────────────────────────────────────
  // כרגע: Test IDs של גוגל — לאחר פתיחת חשבון AdMob החלף ב-IDs האמיתיים שלך
  // Android test rewarded: ca-app-pub-3940256099942544/5224354917
  // iOS     test rewarded: ca-app-pub-3940256099942544/1712485313
  // פרסומת מלאה 30 שניות → +5 אנרגיה
  static String get adRewardedUnitId =>
      defaultTargetPlatform == TargetPlatform.iOS
          ? 'ca-app-pub-3940256099942544/1712485313'  // ← החלף ב-iOS Rewarded Ad Unit ID שלך
          : 'ca-app-pub-3940256099942544/5224354917'; // ← החלף ב-Android Rewarded Ad Unit ID שלך

  // פרסומת עם דילוג אחרי 5 שניות → +1 אנרגיה
  static String get adInterstitialUnitId =>
      defaultTargetPlatform == TargetPlatform.iOS
          ? 'ca-app-pub-3940256099942544/4411468910'  // ← החלף ב-iOS Interstitial Ad Unit ID שלך
          : 'ca-app-pub-3940256099942544/1033173712'; // ← החלף ב-Android Interstitial Ad Unit ID שלך

  static const adRewardedEnergy     = 5;  // אנרגיה מפרסומת מלאה
  static const adInterstitialEnergy = 1;  // אנרגיה מפרסומת עם דילוג

  static const questionsPerLevel    = 10;
  static const starsPerLevel        = 3;
  static const maxWrongPerLevel     = 2;
  static const starsToUnlockNext    = 2;
  static const starsToUnlockMedium  = 25;
  static const starsToUnlockHard    = 25;

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
//  DIFFICULTY
// ═══════════════════════════════════════════════
enum Diff { easy, medium, hard }
extension DiffX on Diff {
  String get label   => ['\u05E7\u05DC', '\u05D1\u05D9\u05E0\u05D5\u05E0\u05D9', '\u05E7\u05E9\u05D4'][index];
  Color  get color   => [const Color(0xFF2ECC71), const Color(0xFF4D96FF), const Color(0xFFE74C3C)][index];
  bool   get isPrem  => this == Diff.hard;
  String get emoji   => ['\u{1F7E2}', '\u{1F535}', '\u{1F534}'][index];
}

// ═══════════════════════════════════════════════
//  DATA MODEL
// ═══════════════════════════════════════════════
class Question {
  final String id, category, q;
  final List<String> a;
  final int c;
  final Diff diff;
  final String? f;
  const Question({required this.id, required this.category,
    required this.q, required this.a, required this.c,
    required this.diff, this.f});
  factory Question.fromMap(Map<String,dynamic> m) {
    final d = (m['d'] as int?) ?? 1;
    return Question(id:m['id'], category:m['category'], q:m['q'],
      a:List<String>.from(m['a']), c:m['c'],
      diff: d==3?Diff.hard:d==2?Diff.medium:Diff.easy, f:m['f']);
  }
}

// ═══════════════════════════════════════════════
//  REPO — להוסיף שאלות: ערוך questions_easy/medium/hard.dart
// ═══════════════════════════════════════════════
class QRepo {
  static List<Question>? _e,_m,_h;
  static List<Question> get easy   { _e??=_p(kEasy,   Diff.easy);   return _e!; }
  static List<Question> get medium { _m??=_p(kMedium, Diff.medium); return _m!; }
  static List<Question> get hard   { _h??=_p(kHard,   Diff.hard);   return _h!; }
  static List<Question> _p(String j, Diff d) =>
      (jsonDecode(j) as List).map((e)=>Question.fromMap(e)).toList();
  static List<Question> forDiff(Diff d) => [easy,medium,hard][d.index];
  static List<Question> forLevel(int idx, Diff d) {
    final pool = List<Question>.from(forDiff(d))..shuffle(Random(idx*31+d.index*7));
    return pool.take(Cfg.questionsPerLevel).toList();
  }
  static int levelCount(Diff d) => max(1,(forDiff(d).length/Cfg.questionsPerLevel).floor());
  static List<Question> all(bool prem) =>
      prem ? [...easy, ...medium, ...hard] : [...easy, ...medium];
}

// ═══════════════════════════════════════════════
//  LEVEL SERVICE
// ═══════════════════════════════════════════════
class LevelService extends ChangeNotifier {
  static final LevelService _i = LevelService._();
  static LevelService get instance => _i;
  LevelService._();
  final Map<Diff,Map<int,int>> _s = {Diff.easy:{},Diff.medium:{},Diff.hard:{}};
  static Future<void> init() async {
    final p = await SharedPreferences.getInstance();
    for (final d in Diff.values)
      for (int i=0;i<QRepo.levelCount(d);i++)
        _i._s[d]![i] = p.getInt('lvl_${d.name}_$i')??0;
  }
  int starsFor(Diff d,int i) => _s[d]![i]??0;
  int totalStars(Diff d) => _s[d]?.values.fold(0,(a,b)=>a!+b)??0;
  int get allStars => Diff.values.fold(0,(a,d)=>a+totalStars(d));
  bool isDiffUnlocked(Diff d) {
    if (d==Diff.easy) return true;
    if (d==Diff.medium) return allStars>=Cfg.starsToUnlockMedium;
    return PurchaseService.instance.isPremium && allStars>=Cfg.starsToUnlockHard;
  }
  bool isLevelUnlocked(Diff d,int idx) {
    if (!isDiffUnlocked(d)) return false;
    if (idx==0) return true;
    int cum=0; for(int i=0;i<idx;i++) cum+=starsFor(d,i);
    return cum>=idx*Cfg.starsToUnlockNext;
  }
  Future<void> save(Diff d,int idx,int stars) async {
    if (stars>starsFor(d,idx)) {
      _s[d]![idx]=stars;
      final p=await SharedPreferences.getInstance();
      await p.setInt('lvl_${d.name}_$idx',stars);
      notifyListeners();
    }
  }
}

// ═══════════════════════════════════════════════
//  ENERGY SERVICE
// ═══════════════════════════════════════════════
class EnergyService extends ChangeNotifier {
  static final EnergyService _i = EnergyService._();
  static EnergyService get instance => _i;
  EnergyService._();
  int _e = Cfg.maxEnergyFree;
  DateTime _last = DateTime.now();
  Timer? _t;
  int get energy => _e;
  int get maxE => PurchaseService.instance.isPremium?Cfg.maxEnergyPremium:Cfg.maxEnergyFree;
  int get rechargeAmt => PurchaseService.instance.isPremium?Cfg.energyRechargeAmtPro:Cfg.energyRechargeAmt;
  bool get has => _e>0;
  static Future<void> init() async {
    final p=await SharedPreferences.getInstance();
    _i._e=p.getInt('energy')??Cfg.maxEnergyFree;
    final ts=p.getInt('energy_ts');
    if(ts!=null){_i._last=DateTime.fromMillisecondsSinceEpoch(ts);_i._check();}
    _i._t=Timer.periodic(const Duration(seconds:30),(_)=>_i._check());
  }
  void _check() {
    final elapsed=DateTime.now().difference(_last);
    final cycles=elapsed.inMinutes~/Cfg.energyRechargeMins;
    if(cycles>0&&_e<maxE){
      _e=(_e+cycles*rechargeAmt).clamp(0,maxE);
      _last=_last.add(Duration(minutes:cycles*Cfg.energyRechargeMins));
      _save(); notifyListeners();
    }
  }
  Future<void> spend(int n) async { _e=(_e-n).clamp(0,maxE); await _save(); notifyListeners(); }
  Future<void> _save() async {
    final p=await SharedPreferences.getInstance();
    await p.setInt('energy',_e); await p.setInt('energy_ts',_last.millisecondsSinceEpoch);
  }
  // לא מציגים זמן — שומרים על אי-וודאות כמו Duolingo
  String get label {
    if (_e >= maxE) return '';
    final next = _last.add(Duration(minutes: Cfg.energyRechargeMins));
    final diff = next.difference(DateTime.now());
    if (diff.inSeconds <= 0) return 'עכשיו';
    if (diff.inMinutes < 1) return 'פחות מדקה';
    final mins = diff.inMinutes + 1;
    return mins.toString() + ' דקות';
  }
  bool get canWatchAd => _e < maxE && !PurchaseService.instance.isPremium;
  // אנרגיה מפרסומת — amount לפי סוג הפרסומת
  Future<void> rewardFromAd({int amount = Cfg.adRewardedEnergy}) async {
    _e = (_e + amount).clamp(0, maxE);
    await _save(); notifyListeners();
  }
  @override void dispose(){_t?.cancel();super.dispose();}
}
// ═══════════════════════════════════════════════
//  PURCHASE SERVICE
// ═══════════════════════════════════════════════
class PurchaseService extends ChangeNotifier {
  static final PurchaseService _i = PurchaseService._();
  static PurchaseService get instance => _i;
  PurchaseService._();
  bool _pro=false,_loading=false,_dev=false;
  List<Package> _pkgs=[];
  bool get isPremium => _pro||_dev||Cfg.mockPremium;
  bool get isLoading => _loading;
  List<Package> get packages => _pkgs;
  bool tryDev(String c){if(c!=Cfg.devCode)return false;_dev=true;EnergyService.instance._e=EnergyService.instance.maxE;EnergyService.instance.notifyListeners();notifyListeners();return true;}
  static Future<void> init() async {
    if(Cfg.mockPremium){_i._pro=true;return;}
    try{
      await Purchases.setLogLevel(LogLevel.debug);
      await Purchases.configure(PurchasesConfiguration(
        defaultTargetPlatform==TargetPlatform.iOS?Cfg.rciOS:Cfg.rcAndroid));
      final ci=await Purchases.getCustomerInfo();
      _i._pro=ci.entitlements.all[Cfg.entitlement]?.isActive??false;
      _i.notifyListeners();
    }catch(e){debugPrint('RC:$e');}
  }
  Future<void> loadOfferings() async {
    _loading=true;notifyListeners();
    try{final o=await Purchases.getOfferings();_pkgs=o.current?.availablePackages??[];}catch(_){}
    _loading=false;notifyListeners();
  }
  Future<bool> purchase(Package pkg) async {
    _loading=true;notifyListeners();
    try{
      final ci=await Purchases.purchasePackage(pkg);
      _pro=ci.entitlements.all[Cfg.entitlement]?.isActive??false;
      if(_pro){EnergyService.instance._e=EnergyService.instance.maxE;EnergyService.instance.notifyListeners();}
      _loading=false;notifyListeners();return _pro;
    }on PurchasesErrorCode catch(e){
      if(e!=PurchasesErrorCode.purchaseCancelledError)debugPrint('err');
      _loading=false;notifyListeners();return false;
    }
  }
  Future<bool> restore() async {
    _loading=true;notifyListeners();
    try{
      final ci=await Purchases.restorePurchases();
      _pro=ci.entitlements.all[Cfg.entitlement]?.isActive??false;
      if(_pro){EnergyService.instance._e=EnergyService.instance.maxE;EnergyService.instance.notifyListeners();}
      _loading=false;notifyListeners();return _pro;
    }catch(_){_loading=false;notifyListeners();return false;}
  }
}

// ═══════════════════════════════════════════════
//  SOUND
// ═══════════════════════════════════════════════
class Sfx {
  // ✅ נכון — מרימבה בהירה בדיוק כמו Duolingo
  // שלושה harmonic ביחד: בסיס + אוקטבה + קווינטה — נותן את הצליל "עץ" הזה
  static Future<void> correct() async {
    playWebTone([
      {'freq': 1318, 'dur': 0.55, 'vol': 0.42, 'type': 'sine', 'attack': 0.005},
      {'freq': 2637, 'dur': 0.35, 'vol': 0.14, 'type': 'sine', 'attack': 0.005, 'overlap': true},
      {'freq': 1976, 'dur': 0.28, 'vol': 0.10, 'type': 'sine', 'attack': 0.005, 'overlap': true},
    ]);
    if (!kIsWeb) await HapticFeedback.lightImpact();
  }

  // ❌ טעות — "dunk" נמוך ועמוק כמו Duolingo, לא בוזר
  static Future<void> wrong() async {
    playWebTone([
      {'freq': 294, 'glide': 196, 'dur': 0.38, 'vol': 0.48, 'type': 'sine', 'attack': 0.008},
      {'freq': 196, 'dur': 0.28, 'vol': 0.22, 'type': 'sine', 'attack': 0.008, 'overlap': true},
    ]);
    if (!kIsWeb) await HapticFeedback.heavyImpact();
  }

  // 🏆 מושלם — ג'ינגל חגיגי קצר בסגנון Duolingo streak
  static Future<void> perfect() async {
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

// ═══════════════════════════════════════════════
//  GAME STATE
// ═══════════════════════════════════════════════
enum Phase{playing,complete,failed}
class GameState extends ChangeNotifier {
  final int levelIdx; final Diff diff; final List<Question> questions;
  int _qi=0,_stars=Cfg.starsPerLevel,_wrong=0,_timer=Cfg.timerSecs;
  int? _sel; bool _fb=false; Phase _phase=Phase.playing; Timer? _t;
  GameState({required this.levelIdx,required this.diff}):questions=QRepo.forLevel(levelIdx,diff){_startTimer();}
  int get qi=>_qi; int get stars=>_stars; int? get sel=>_sel; bool get fb=>_fb;
  Phase get phase=>_phase; int get timer=>_timer; Question get cur=>questions[_qi];
  int get total=>questions.length; double get prog=>(_qi+1)/total;
  void _startTimer(){
    _t?.cancel(); _timer=Cfg.timerSecs; notifyListeners();
    _t=Timer.periodic(const Duration(seconds:1),(t){
      if(_fb)return; _timer--; notifyListeners();
      if(_timer<=0){t.cancel();_timeout();}
    });
  }
  void _timeout() async {
    await Sfx.wrong(); _wrong++; _stars=(Cfg.starsPerLevel-_wrong).clamp(0,3);
    _sel=-1; _fb=true;
    await EnergyService.instance.spend(Cfg.energyCostWrong); notifyListeners();
    if(_wrong>Cfg.maxWrongPerLevel){await Sfx.fail();await EnergyService.instance.spend(Cfg.energyCostFail);await Future.delayed(const Duration(milliseconds:1500));_phase=Phase.failed;notifyListeners();return;}
    await Future.delayed(const Duration(milliseconds:1800));
    _fb=false;_sel=null;
    if(_qi<total-1){_qi++;_startTimer();}else{await _finish();}
    notifyListeners();
  }
  void answer(int idx) async {
    if(_fb)return; _t?.cancel(); _sel=idx; _fb=true; notifyListeners();
    final ok=idx==cur.c;
    if(ok){await Sfx.correct();await Future.delayed(const Duration(milliseconds:1600));}
    else{
      await Sfx.wrong(); _wrong++; _stars=(Cfg.starsPerLevel-_wrong).clamp(0,3);
      await EnergyService.instance.spend(Cfg.energyCostWrong);
      await Future.delayed(const Duration(milliseconds:1800));
      if(_wrong>Cfg.maxWrongPerLevel){await Sfx.fail();await EnergyService.instance.spend(Cfg.energyCostFail);_phase=Phase.failed;notifyListeners();return;}
    }
    _fb=false;_sel=null;
    if(_qi>=total-1){await _finish();}else{_qi++;_startTimer();}
    notifyListeners();
  }
  Future<void> _finish() async {
    _t?.cancel();
    if(_stars==Cfg.starsPerLevel)await Sfx.perfect();
    await LevelService.instance.save(diff,levelIdx,_stars);
    _phase=Phase.complete;
  }
  void dispose(){_t?.cancel();}
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

// ═══════════════════════════════════════════════
//  MAIN
// ═══════════════════════════════════════════════
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp,DeviceOrientation.portraitDown]);
  await PurchaseService.init(); await LevelService.init(); await EnergyService.init();
  // ─── AdMob אתחול ──────────────────────────────────────────────────────────
  if (Cfg.adMobEnabled && !kIsWeb) {
    await MobileAds.instance.initialize();
  }
  runApp(const App());
}
class App extends StatelessWidget {
  const App({super.key});
  @override Widget build(BuildContext context) {
    return ListenableBuilder(listenable:PurchaseService.instance,
      builder:(_,__)=>MaterialApp(title:'\u05D9\u05D3\u05E2\u05DF',debugShowCheckedModeBanner:false,
        theme:ThemeData.dark().copyWith(scaffoldBackgroundColor:Pal.bg,useMaterial3:true),
        home:const HomeScreen()));
  }
}

// ═══════════════════════════════════════════════
//  STAR FIELD
// ═══════════════════════════════════════════════
class StarField extends StatelessWidget {
  const StarField({super.key});
  @override Widget build(BuildContext context) =>
      IgnorePointer(child:CustomPaint(size:Size.infinite,painter:_SP()));
}
class _SP extends CustomPainter {
  static final List<List<double>> _s=List.generate(60,(i){
    final r=Random(i*7919);
    return[r.nextDouble(),r.nextDouble(),r.nextDouble()*2+0.5,r.nextDouble()*0.5+0.2];
  });
  @override void paint(Canvas c,Size s){
    for(final st in _s)c.drawCircle(Offset(st[0]*s.width,st[1]*s.height),st[2],Paint()..color=Colors.white.withOpacity(st[3]));
  }
  @override bool shouldRepaint(_)=>false;
}

// ═══════════════════════════════════════════════
//  ENERGY CHIP
// ═══════════════════════════════════════════════
class EnergyChip extends StatefulWidget {
  const EnergyChip({super.key});
  @override State<EnergyChip> createState() => _EnergyChipState();
}
class _EnergyChipState extends State<EnergyChip> with SingleTickerProviderStateMixin {
  late final AnimationController _anim;
  late final Animation<double> _scale;
  int _lastEnergy = -1;

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(vsync: this, duration: const Duration(milliseconds: 400));
    _scale = TweenSequence([
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.3), weight: 40),
      TweenSequenceItem(tween: Tween(begin: 1.3, end: 0.9), weight: 30),
      TweenSequenceItem(tween: Tween(begin: 0.9, end: 1.0), weight: 30),
    ]).animate(CurvedAnimation(parent: _anim, curve: Curves.easeInOut));
    EnergyService.instance.addListener(_onEnergyChange);
    _lastEnergy = EnergyService.instance.energy;
  }

  void _onEnergyChange() {
    final cur = EnergyService.instance.energy;
    if (cur != _lastEnergy) {
      _anim.forward(from: 0);
      _lastEnergy = cur;
    }
  }

  @override
  void dispose() {
    EnergyService.instance.removeListener(_onEnergyChange);
    _anim.dispose();
    super.dispose();
  }

  @override Widget build(BuildContext context) {
    return ListenableBuilder(listenable: EnergyService.instance, builder: (_, __) {
      final e = EnergyService.instance;
      final pct = e.energy / e.maxE;
      final c = pct > 0.5 ? Pal.green : pct > 0.2 ? Pal.premium : Pal.red;
      return AnimatedBuilder(
        animation: _scale,
        builder: (_, child) => Transform.scale(scale: _scale.value, child: child),
        child: GestureDetector(
          onTap: e.canWatchAd ? () => _showAdDialog(context) : null,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: Pal.card, borderRadius: BorderRadius.circular(20),
              border: Border.all(color: c.withOpacity(0.6), width: 1.5)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Text('\u26A1', style: TextStyle(fontSize: 14, color: c)),
              const SizedBox(width: 4),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                transitionBuilder: (child, anim) => SlideTransition(
                  position: Tween(begin: const Offset(0, -0.8), end: Offset.zero).animate(
                    CurvedAnimation(parent: anim, curve: Curves.easeOut)),
                  child: FadeTransition(opacity: anim, child: child)),
                child: Text('${e.energy}',
                  key: ValueKey(e.energy),
                  style: TextStyle(color: c, fontWeight: FontWeight.w900, fontSize: 14))),
              Text('/${e.maxE}', style: const TextStyle(color: Pal.ts, fontSize: 11)),
              if (e.label.isNotEmpty && e.energy < e.maxE) ...[
                const SizedBox(width: 6),
                Text(e.label, style: const TextStyle(color: Pal.gold, fontSize: 10, fontWeight: FontWeight.w700)),
              ],
              if (e.canWatchAd) ...[
                const SizedBox(width: 4),
                const Text('+', style: TextStyle(color: Pal.gold, fontSize: 13, fontWeight: FontWeight.w900)),
              ],
            ]))));
    });
  }

  void _showAdDialog(BuildContext context) {
    showDialog(context: context, builder: (_) => _AdRewardDialog());
  }
}

// ═══════════════════════════════════════════════
//  AD REWARD DIALOG — שני סוגי פרסומות AdMob
//  • Rewarded (30 שניות) → +5 אנרגיה
//  • Interstitial (דילוג אחרי 5 שניות) → +1 אנרגיה
// ═══════════════════════════════════════════════
class _AdRewardDialog extends StatefulWidget {
  @override State<_AdRewardDialog> createState() => _AdRewardDialogState();
}

class _AdRewardDialogState extends State<_AdRewardDialog>
    with SingleTickerProviderStateMixin {
  // מצב כללי
  bool _loadingRewarded     = true;
  bool _loadingInterstitial = true;
  bool _done                = false;
  int  _earnedEnergy        = 0;

  late final AnimationController _anim;
  RewardedAd?      _rewardedAd;
  InterstitialAd?  _interstitialAd;

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(vsync: this, duration: const Duration(milliseconds: 600));
    _loadRewardedAd();
    _loadInterstitialAd();
  }

  // ── טעינת פרסומת Rewarded (30 שניות, +5 אנרגיה) ──────────────────────────
  void _loadRewardedAd() {
    RewardedAd.load(
      adUnitId: Cfg.adRewardedUnitId,
      request: const AdRequest(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded:       (ad) { _rewardedAd = ad;    if (mounted) setState(() => _loadingRewarded = false); },
        onAdFailedToLoad: (_)  {                       if (mounted) setState(() => _loadingRewarded = false); },
      ),
    );
  }

  // ── טעינת פרסומת Interstitial (דילוג אחרי 5 שניות, +1 אנרגיה) ────────────
  void _loadInterstitialAd() {
    InterstitialAd.load(
      adUnitId: Cfg.adInterstitialUnitId,
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded:       (ad) { _interstitialAd = ad; if (mounted) setState(() => _loadingInterstitial = false); },
        onAdFailedToLoad: (_)  {                        if (mounted) setState(() => _loadingInterstitial = false); },
      ),
    );
  }

  // ── הצגת פרסומת Rewarded ──────────────────────────────────────────────────
  void _showRewardedAd() {
    final ad = _rewardedAd;
    if (ad == null) return;
    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (a) { a.dispose(); _rewardedAd = null; },
      onAdFailedToShowFullScreenContent: (a, _) { a.dispose(); _rewardedAd = null; },
    );
    ad.show(onUserEarnedReward: (_, __) => _onComplete(Cfg.adRewardedEnergy));
  }

  // ── הצגת פרסומת Interstitial ──────────────────────────────────────────────
  void _showInterstitialAd() {
    final ad = _interstitialAd;
    if (ad == null) return;
    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (a) {
        a.dispose(); _interstitialAd = null;
        // נותנים +1 גם אם דילגו — כי ראו לפחות חלק מהפרסומת
        _onComplete(Cfg.adInterstitialEnergy);
      },
      onAdFailedToShowFullScreenContent: (a, _) { a.dispose(); _interstitialAd = null; },
    );
    ad.show();
  }

  // ── השלמה ─────────────────────────────────────────────────────────────────
  Future<void> _onComplete(int energy) async {
    await EnergyService.instance.rewardFromAd(amount: energy);
    if (!mounted) return;
    setState(() { _done = true; _earnedEnergy = energy; });
    _anim.forward();
    await HapticFeedback.lightImpact();
    await Future.delayed(const Duration(milliseconds: 150));
    if (mounted) await HapticFeedback.lightImpact();
    Future.delayed(const Duration(milliseconds: 1500), () {
      if (mounted) Navigator.pop(context);
    });
  }

  @override
  void dispose() {
    _rewardedAd?.dispose();
    _interstitialAd?.dispose();
    _anim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Pal.card,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Padding(padding: const EdgeInsets.all(24), child: _done ? _doneView() : _mainView()),
    );
  }

  // ── מסך ראשי עם שתי אפשרויות ────────────────────────────────────────────
  Widget _mainView() => Column(mainAxisSize: MainAxisSize.min, children: [
    const Text('⚡', style: TextStyle(fontSize: 48)),
    const SizedBox(height: 10),
    const Text('קבל אנרגיה',
      style: TextStyle(color: Pal.tp, fontSize: 22, fontWeight: FontWeight.w800)),
    const SizedBox(height: 4),
    const Text('בחר איזה פרסומת לצפות',
      style: TextStyle(color: Pal.ts, fontSize: 13)),
    const SizedBox(height: 22),

    // ── כפתור 1: Rewarded (30 שניות, +5) ────────────────────────────────
    _AdButton(
      loading:    _loadingRewarded,
      available:  _rewardedAd != null,
      emoji:      '🎬',
      title:      'סרטון מלא (30 שניות)',
      reward:     '+5 ⚡',
      subtitle:   'לא ניתן לדלג',
      color:      Pal.gold,
      onTap:      _showRewardedAd,
    ),
    const SizedBox(height: 12),

    // ── כפתור 2: Interstitial (דילוג אחרי 5 שניות, +1) ──────────────────
    _AdButton(
      loading:    _loadingInterstitial,
      available:  _interstitialAd != null,
      emoji:      '⏩',
      title:      'פרסומת קצרה',
      reward:     '+1 ⚡',
      subtitle:   'ניתן לדלג אחרי 5 שניות',
      color:      const Color(0xFF4D96FF),
      onTap:      _showInterstitialAd,
    ),
    const SizedBox(height: 14),

    TextButton(
      onPressed: () => Navigator.pop(context),
      child: const Text('לא תודה', style: TextStyle(color: Pal.ts))),
  ]);

  // ── מסך סיום ─────────────────────────────────────────────────────────────
  Widget _doneView() => Column(mainAxisSize: MainAxisSize.min, children: [
    ScaleTransition(
      scale: CurvedAnimation(parent: _anim, curve: Curves.easeOutBack),
      child: const Text('⚡', style: TextStyle(fontSize: 72))),
    const SizedBox(height: 14),
    FadeTransition(
      opacity: _anim,
      child: Text('+$_earnedEnergy אנרגיה!',
        style: const TextStyle(color: Pal.gold, fontSize: 24, fontWeight: FontWeight.w900))),
  ]);
}

// ── ווידג'ט עזר: כפתור פרסומת ────────────────────────────────────────────
class _AdButton extends StatelessWidget {
  final bool    loading;
  final bool    available;
  final String  emoji;
  final String  title;
  final String  reward;
  final String  subtitle;
  final Color   color;
  final VoidCallback onTap;

  const _AdButton({
    required this.loading, required this.available, required this.emoji,
    required this.title,   required this.reward,    required this.subtitle,
    required this.color,   required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: available ? onTap : null,
      child: AnimatedOpacity(
        opacity: loading || available ? 1.0 : 0.4,
        duration: const Duration(milliseconds: 300),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
          decoration: BoxDecoration(
            color: color.withOpacity(0.12),
            border: Border.all(color: color.withOpacity(0.5), width: 1.5),
            borderRadius: BorderRadius.circular(16),
          ),
          child: loading
            ? Center(child: SizedBox(width: 22, height: 22,
                child: CircularProgressIndicator(color: color, strokeWidth: 2)))
            : Row(children: [
                Text(emoji, style: const TextStyle(fontSize: 28)),
                const SizedBox(width: 12),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(title, style: TextStyle(color: color, fontSize: 15, fontWeight: FontWeight.w700)),
                  Text(subtitle, style: TextStyle(color: color.withOpacity(0.7), fontSize: 11)),
                ])),
                Text(reward, style: TextStyle(color: color, fontSize: 18, fontWeight: FontWeight.w900)),
              ]),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════
//  HOME SCREEN
// ═══════════════════════════════════════════════
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override State<HomeScreen> createState()=>_HS();
}
class _HS extends State<HomeScreen> with TickerProviderStateMixin {
  late final AnimationController _bg;
  @override void initState(){
    super.initState(); _bg=AnimationController(vsync:this,duration:const Duration(seconds:8))..repeat(reverse:true);
    LevelService.instance.addListener((){if(mounted)setState((){});});
    PurchaseService.instance.addListener((){if(mounted)setState((){});});
  }
  @override void dispose(){_bg.dispose();super.dispose();}
  @override Widget build(BuildContext context){
    return Scaffold(body:Stack(children:[
      AnimatedBuilder(animation:_bg,builder:(_,__)=>Container(decoration:BoxDecoration(gradient:LinearGradient(
        begin:Alignment.topCenter,end:Alignment.bottomCenter,
        colors:[Color.lerp(const Color(0xFF0D1B3E),const Color(0xFF1A0D3E),_bg.value)!,Pal.bgD])))),
      const StarField(),
      SafeArea(child:Column(children:[
        // Top bar
        Padding(padding:const EdgeInsets.fromLTRB(20,16,20,0),
          child:Row(children:[
            ShaderMask(shaderCallback:(b)=>const LinearGradient(colors:[Pal.gold,Color(0xFFFF9F0A)]).createShader(b),
              child:const Text('\u05D9\u05D3\u05E2\u05DF',style:TextStyle(fontSize:36,fontWeight:FontWeight.w900,color:Colors.white,letterSpacing:3))),
            const Spacer(),
            const EnergyChip(),
          ])),
        const SizedBox(height:12),
        // Stars bar
        Padding(padding:const EdgeInsets.symmetric(horizontal:20),child:_StarsBar()),
        const SizedBox(height:24),
        // Only show EASY card in home — medium/hard accessed via map
        Expanded(child:SingleChildScrollView(padding:const EdgeInsets.symmetric(horizontal:20),child:Column(children:[
          _DiffCard(diff:Diff.easy),
          const SizedBox(height:16),
          _DiffCard(diff:Diff.medium),
          const SizedBox(height:16),
          _DiffCard(diff:Diff.hard),
          const SizedBox(height:20),
          // ─── Categories section ───
          Align(alignment:Alignment.centerRight,
            child:Text('🎯 חידון קטגוריות',style:TextStyle(color:Pal.gold,fontSize:15,fontWeight:FontWeight.w800))),
          const SizedBox(height:10),
          ..._HomeCats.cats.map((cat){
            final (key,name,emoji,color)=cat;
            final count=QRepo.all(PurchaseService.instance.isPremium).where((q)=>q.category==key).length;
            return Padding(padding:const EdgeInsets.only(bottom:10),
              child:GestureDetector(
                onTap:()=>_showCatDiffPicker(context,key,name,emoji,color),
                child:Container(
                  padding:const EdgeInsets.symmetric(horizontal:16,vertical:13),
                  decoration:BoxDecoration(
                    gradient:LinearGradient(begin:Alignment.topLeft,end:Alignment.bottomRight,
                      colors:[color.withOpacity(0.18),color.withOpacity(0.05)]),
                    borderRadius:BorderRadius.circular(16),
                    border:Border.all(color:color.withOpacity(0.4),width:1.2),
                    boxShadow:[BoxShadow(color:color.withOpacity(0.10),blurRadius:8)]),
                  child:Row(children:[
                    Text(emoji,style:const TextStyle(fontSize:24)),
                    const SizedBox(width:12),
                    Expanded(child:Text(name,style:const TextStyle(color:Pal.tp,fontSize:15,fontWeight:FontWeight.w700))),
                    Text('$count שאלות',style:TextStyle(color:color,fontSize:11,fontWeight:FontWeight.w600)),
                    const SizedBox(width:6),
                    Icon(Icons.chevron_right,color:color,size:18),
                  ]))));
          }).toList(),
          const SizedBox(height:24),
        ]))),
      ])),
    ]));
  }
}

// helper: show difficulty picker for category quiz
void _showCatDiffPicker(BuildContext ctx,String key,String name,String emoji,Color color){
  showModalBottomSheet(context:ctx,backgroundColor:Colors.transparent,builder:(_)=>
    Container(
      padding:const EdgeInsets.all(24),
      decoration:BoxDecoration(color:Pal.bgD,borderRadius:const BorderRadius.vertical(top:Radius.circular(24)),
        border:Border(top:BorderSide(color:color.withOpacity(0.4),width:1.5))),
      child:Column(mainAxisSize:MainAxisSize.min,children:[
        Container(width:40,height:4,decoration:BoxDecoration(color:Pal.ts.withOpacity(0.3),borderRadius:BorderRadius.circular(2))),
        const SizedBox(height:16),
        Row(mainAxisAlignment:MainAxisAlignment.center,children:[
          Text(emoji,style:const TextStyle(fontSize:26)),
          const SizedBox(width:10),
          Text(name,style:const TextStyle(color:Pal.tp,fontSize:18,fontWeight:FontWeight.w800)),
        ]),
        const SizedBox(height:6),
        Text('בחר רמת קושי',style:const TextStyle(color:Pal.ts,fontSize:13)),
        const SizedBox(height:20),
        ...Diff.values.map((d){
          final prem=PurchaseService.instance.isPremium;
          final locked=d.isPrem && !prem;
          final count=QRepo.all(true).where((q)=>q.category==key&&q.diff==d).length;
          return Padding(padding:const EdgeInsets.only(bottom:10),
            child:GestureDetector(
              onTap:(){
                Navigator.pop(ctx);
                if(locked){
                  showModalBottomSheet(context:ctx,isScrollControlled:true,backgroundColor:Colors.transparent,
                    builder:(_)=>PaywallSheet(onCode:(c){
                      final ok=PurchaseService.instance.tryDev(c);
                      Navigator.pop(ctx);
                      ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
                        content:Text(ok?'\u05E7\u05D5\u05D3 \u05D0\u05D5\u05E9\u05E8! \u05DB\u05DC \u05D4\u05EA\u05DB\u05E0\u05D9\u05DD \u05E4\u05EA\u05D5\u05D7\u05D9\u05DD \u{1F389}':'\u05E7\u05D5\u05D3 \u05E9\u05D2\u05D5\u05D9'),
                        backgroundColor:ok?Pal.green:Pal.red));
                    }));
                  return;
                }
                if(!EnergyService.instance.has){Navigator.push(ctx,_slide(const NoEnergyScreen()));return;}
                EnergyService.instance.spend(Cfg.energyCostWrong);
                Navigator.push(ctx,_slide(CategoryQuizScreen(category:key,name:name,emoji:emoji,color:color,diff:d)));
              },
              child:Container(
                padding:const EdgeInsets.symmetric(horizontal:16,vertical:13),
                decoration:BoxDecoration(
                  gradient:LinearGradient(colors:[d.color.withOpacity(0.2),d.color.withOpacity(0.05)]),
                  borderRadius:BorderRadius.circular(14),
                  border:Border.all(color:d.color.withOpacity(0.5),width:1.2)),
                child:Row(children:[
                  Text(locked?'\u{1F451}':d.emoji,style:const TextStyle(fontSize:20)),
                  const SizedBox(width:12),
                  Text(d.label,style:TextStyle(color:d.color,fontSize:15,fontWeight:FontWeight.w700)),
                  if(locked)...[const SizedBox(width:8),Container(padding:const EdgeInsets.symmetric(horizontal:8,vertical:2),
                    decoration:BoxDecoration(color:Pal.premium.withOpacity(0.2),borderRadius:BorderRadius.circular(8)),
                    child:const Text('\u05E4\u05E8\u05D5',style:TextStyle(color:Pal.premium,fontSize:10,fontWeight:FontWeight.w800)))],
                  const Spacer(),
                  Text('$count שאלות',style:TextStyle(color:d.color.withOpacity(0.8),fontSize:12)),
                  const SizedBox(width:8),
                  Icon(locked?Icons.lock:Icons.arrow_forward_ios,color:d.color,size:14),
                ]))));
        }).toList(),
        const SizedBox(height:8),
      ])));
}

class _HomeCats {
  static const cats = [
    ('israel','ישראל','🇮🇱',Color(0xFF4D96FF)),
    ('judaism','יהדות','✡️',Color(0xFF7C6FE0)),
    ('tv','טלוויזיה','📺',Color(0xFF9B59B6)),
    ('music','מוזיקה','🎵',Color(0xFFE91E8C)),
    ('sports','ספורט','⚽',Color(0xFFE74C3C)),
    ('geography','גיאוגרפיה','🌍',Color(0xFF2ECC71)),
    ('science','מדע','🔬',Color(0xFF3498DB)),
    ('world','תרבות עולמית','🎬',Color(0xFFE67E22)),
  ];
}

class _StarsBar extends StatelessWidget {
  @override Widget build(BuildContext context){
    final ls=LevelService.instance;
    final all=ls.allStars;
    final next=all<Cfg.starsToUnlockMedium?Cfg.starsToUnlockMedium:all<Cfg.starsToUnlockHard?Cfg.starsToUnlockHard:null;
    return Container(
      padding:const EdgeInsets.symmetric(horizontal:14,vertical:10),
      decoration:BoxDecoration(color:Pal.card.withOpacity(0.6),borderRadius:BorderRadius.circular(14),
        border:Border.all(color:Pal.gold.withOpacity(0.2))),
      child:Row(children:[
        const Text('\u2B50',style:TextStyle(fontSize:15)),const SizedBox(width:8),
        Text('$all \u05DB\u05D5\u05DB\u05D1\u05D9\u05DD',style:const TextStyle(color:Pal.gold,fontWeight:FontWeight.w700,fontSize:13)),
        if(next!=null)...[
          const SizedBox(width:10),
          Expanded(child:ClipRRect(borderRadius:BorderRadius.circular(4),
            child:LinearProgressIndicator(value:all/next,minHeight:5,backgroundColor:Pal.starOff,valueColor:const AlwaysStoppedAnimation(Pal.gold)))),
          const SizedBox(width:8),
          Text('$next',style:const TextStyle(color:Pal.ts,fontSize:11)),
        ]else const Expanded(child:SizedBox()),
      ]));
  }
}

class _DiffCard extends StatelessWidget {
  final Diff diff;
  const _DiffCard({required this.diff});
  @override Widget build(BuildContext context){
    return ListenableBuilder(listenable:LevelService.instance,builder:(_,__){
      final ls=LevelService.instance;
      final unlocked=ls.isDiffUnlocked(diff);
      final isPrem=diff.isPrem&&!PurchaseService.instance.isPremium;
      final earned=ls.totalStars(diff);
      final maxS=QRepo.levelCount(diff)*Cfg.starsPerLevel;
      final need=diff==Diff.medium?Cfg.starsToUnlockMedium:Cfg.starsToUnlockHard;
      return GestureDetector(
        onTap:(){
          if(isPrem){_paywall(context);return;}
          if(!unlocked){ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('\u05E6\u05E8\u05D9\u05DA $need \u05DB\u05D5\u05DB\u05D1\u05D9\u05DD \u05DB\u05D3\u05D9 \u05DC\u05E4\u05EA\u05D5\u05D7'),backgroundColor:Pal.red));return;}
          Navigator.push(context,_slide(LevelMapScreen(diff:diff)));
        },
        child:Container(
          padding:const EdgeInsets.all(20),
          decoration:BoxDecoration(
            gradient:LinearGradient(begin:Alignment.topLeft,end:Alignment.bottomRight,
              colors:unlocked?[diff.color.withOpacity(0.25),diff.color.withOpacity(0.05)]:[Pal.card.withOpacity(0.5),Pal.card.withOpacity(0.3)]),
            borderRadius:BorderRadius.circular(22),
            border:Border.all(color:unlocked?diff.color.withOpacity(0.6):Pal.ts.withOpacity(0.2),width:1.5),
            boxShadow:unlocked?[BoxShadow(color:diff.color.withOpacity(0.15),blurRadius:20,offset:const Offset(0,6))]:[]),
          child:Row(children:[
            Container(width:56,height:56,decoration:BoxDecoration(shape:BoxShape.circle,
              color:unlocked?diff.color.withOpacity(0.2):Pal.ts.withOpacity(0.1),
              border:Border.all(color:unlocked?diff.color.withOpacity(0.5):Pal.ts.withOpacity(0.2))),
              child:Center(child:Text(unlocked?diff.emoji:(isPrem?'\u{1F451}':'\u{1F512}'),style:const TextStyle(fontSize:26)))),
            const SizedBox(width:16),
            Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
              Row(children:[
                Text(diff.label,style:TextStyle(color:unlocked?Pal.tp:Pal.ts,fontSize:20,fontWeight:FontWeight.w800)),
                if(isPrem)...[const SizedBox(width:8),Container(padding:const EdgeInsets.symmetric(horizontal:8,vertical:2),
                  decoration:BoxDecoration(color:Pal.premium.withOpacity(0.2),borderRadius:BorderRadius.circular(8)),
                  child:const Text('\u05E4\u05E8\u05D5',style:TextStyle(color:Pal.premium,fontSize:10,fontWeight:FontWeight.w800)))],
              ]),
              const SizedBox(height:4),
              Text(unlocked?'${QRepo.levelCount(diff)} \u05E9\u05DC\u05D1\u05D9\u05DD \u00B7 $earned/$maxS \u2B50'
                :(isPrem?'\u05E6\u05E8\u05D9\u05DA \u05E4\u05E8\u05D5 + $need \u05DB\u05D5\u05DB\u05D1\u05D9\u05DD':'\u05E6\u05E8\u05D9\u05DA $need \u2B50 \u05DC\u05E4\u05EA\u05D9\u05D7\u05D4'),
                style:const TextStyle(color:Pal.ts,fontSize:12)),
              if(unlocked&&earned>0)...[const SizedBox(height:8),ClipRRect(borderRadius:BorderRadius.circular(4),
                child:LinearProgressIndicator(value:earned/maxS,minHeight:4,backgroundColor:Pal.starOff,valueColor:AlwaysStoppedAnimation(diff.color)))],
            ])),
            if(unlocked)Column(children:List.generate(3,(i)=>Text(i<(earned/maxS*3).round().clamp(0,3)?'\u2B50':'\u2606',style:const TextStyle(fontSize:13)))),
          ])));
    });
  }
  void _paywall(BuildContext ctx){showModalBottomSheet(context:ctx,isScrollControlled:true,backgroundColor:Colors.transparent,builder:(_)=>PaywallSheet(onCode:(c){final ok=PurchaseService.instance.tryDev(c);Navigator.pop(ctx);ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content:Text(ok?'\u05E7\u05D5\u05D3 \u05D0\u05D5\u05E9\u05E8! \u05DB\u05DC \u05D4\u05EA\u05DB\u05E0\u05D9\u05DD \u05E4\u05EA\u05D5\u05D7\u05D9\u05DD \u{1F389}':'\u05E7\u05D5\u05D3 \u05E9\u05D2\u05D5\u05D9'),backgroundColor:ok?Pal.green:Pal.red));}));}
}

// ═══════════════════════════════════════════════
//  LEVEL MAP — Snake path with diff transitions
// ═══════════════════════════════════════════════
class LevelMapScreen extends StatelessWidget {
  final Diff diff;
  const LevelMapScreen({super.key,required this.diff});
  @override Widget build(BuildContext context){
    return ListenableBuilder(listenable:LevelService.instance,builder:(_,__){
      final count=QRepo.levelCount(diff);
      // Check if next diff is unlocked to show transition node
      final nextDiff=diff==Diff.easy?Diff.medium:diff==Diff.medium?Diff.hard:null;
      final nextUnlocked=nextDiff!=null&&LevelService.instance.isDiffUnlocked(nextDiff);
      return Scaffold(backgroundColor:Pal.bgD,body:Stack(children:[
        const StarField(),
        SafeArea(child:Column(children:[
          Padding(padding:const EdgeInsets.fromLTRB(16,12,16,0),
            child:Row(children:[
              _iconBtn(Icons.arrow_back,()=>Navigator.pop(context)),
              const SizedBox(width:12),
              Text('\u05E8\u05DE\u05D4 ${diff.label}',style:TextStyle(color:diff.color,fontSize:22,fontWeight:FontWeight.w800)),
              const Spacer(),
              const EnergyChip(),
            ])),
          Padding(padding:const EdgeInsets.fromLTRB(20,12,20,0),child:_StarsBar()),
          const SizedBox(height:8),
          Expanded(child:SingleChildScrollView(
            reverse:true,
            padding:const EdgeInsets.symmetric(horizontal:20,vertical:20),
            child:Column(children:[
              // Next difficulty unlock node at top
              if(nextDiff!=null)_DiffTransitionNode(nextDiff:nextDiff,unlocked:nextUnlocked,currentDiff:diff),
              // Level nodes (reversed so 1 is at bottom)
              ...List.generate(count,(rawIdx){
                final idx=count-1-rawIdx;
                return _LevelNode(diff:diff,index:idx,count:count);
              }),
            ]))),
        ])),
      ]));
    });
  }
}

// Node showing transition to next difficulty
class _DiffTransitionNode extends StatelessWidget {
  final Diff nextDiff,currentDiff;
  final bool unlocked;
  const _DiffTransitionNode({required this.nextDiff,required this.currentDiff,required this.unlocked});
  @override Widget build(BuildContext context){
    return Padding(padding:const EdgeInsets.only(bottom:8),
      child:Column(children:[
        Container(height:40,child:Center(child:Container(width:3,color:unlocked?nextDiff.color.withOpacity(0.5):Pal.ts.withOpacity(0.2)))),
        GestureDetector(
          onTap:unlocked?()=>Navigator.pushReplacement(context,_slide(LevelMapScreen(diff:nextDiff))):null,
          child:Container(
            padding:const EdgeInsets.symmetric(horizontal:20,vertical:14),
            decoration:BoxDecoration(
              gradient:unlocked?LinearGradient(colors:[nextDiff.color.withOpacity(0.3),nextDiff.color.withOpacity(0.1)]):null,
              color:unlocked?null:Pal.card.withOpacity(0.5),
              borderRadius:BorderRadius.circular(20),
              border:Border.all(color:unlocked?nextDiff.color:Pal.ts.withOpacity(0.3),width:unlocked?2:1)),
            child:Row(mainAxisSize:MainAxisSize.min,children:[
              Text(unlocked?nextDiff.emoji:'\u{1F512}',style:const TextStyle(fontSize:20)),
              const SizedBox(width:10),
              Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
                Text('\u05E8\u05DE\u05D4 ${nextDiff.label}',style:TextStyle(color:unlocked?Pal.tp:Pal.ts,fontSize:15,fontWeight:FontWeight.w800)),
                Text(unlocked?'\u05DC\u05D7\u05E5 \u05DC\u05E4\u05EA\u05D9\u05D7\u05D4 \u25B6':'\u05E6\u05E8\u05D9\u05DA ${nextDiff==Diff.medium?Cfg.starsToUnlockMedium:Cfg.starsToUnlockHard} \u2B50 \u05DC\u05E4\u05EA\u05D9\u05D7\u05D4',
                  style:const TextStyle(color:Pal.ts,fontSize:11)),
              ]),
            ]))),
      ]));
  }
}

class _LevelNode extends StatelessWidget {
  final Diff diff; final int index,count;
  const _LevelNode({required this.diff,required this.index,required this.count});
  @override Widget build(BuildContext context){
    final ls=LevelService.instance;
    final unlocked=ls.isLevelUnlocked(diff,index);
    final stars=ls.starsFor(diff,index);
    final perfect=stars==Cfg.starsPerLevel;
    // Snake: 3 columns, alternating direction per row
    final row=index~/3;
    final col=index%3;
    final positions=[0.15,0.5,0.85];
    final posX=row%2==0?positions[col]:positions[2-col];
    final align=Alignment(posX*2-1,0);
    return SizedBox(height:110,child:Stack(children:[
      if(index<count-1)Positioned.fill(child:CustomPaint(
        painter:_ConPainter(from:align,
          to:(){final ni=index+1;final nr=ni~/3;final nc=ni%3;final px=nr%2==0?positions[nc]:positions[2-nc];return Alignment(px*2-1,0);}(),
          color:unlocked?diff.color.withOpacity(0.4):Pal.ts.withOpacity(0.15),dashed:!unlocked))),
      Align(alignment:align,child:GestureDetector(
        onTap:(){
          if(!unlocked)return;
          if(!EnergyService.instance.has){Navigator.push(context,_slide(const NoEnergyScreen()));return;}
          EnergyService.instance.spend(Cfg.energyCostWrong); // כניסה לשלב עולה 1 אנרגיה
          Navigator.push(context,_slide(GameScreen(diff:diff,levelIndex:index)));
        },
        child:Column(mainAxisSize:MainAxisSize.min,children:[
          if(unlocked&&stars>0)Row(mainAxisSize:MainAxisSize.min,children:List.generate(3,(i)=>Text(i<stars?'\u2B50':'\u2606',style:TextStyle(fontSize:11,color:i<stars?Pal.starOn:Pal.starOff)))),
          const SizedBox(height:2),
          AnimatedContainer(duration:const Duration(milliseconds:300),
            width:unlocked?68:58,height:unlocked?68:58,
            decoration:BoxDecoration(shape:BoxShape.circle,
              gradient:unlocked?LinearGradient(begin:Alignment.topLeft,end:Alignment.bottomRight,
                colors:perfect?[Pal.gold,const Color(0xFFFF9F0A)]:[diff.color,diff.color.withOpacity(0.7)]):null,
              color:unlocked?null:Pal.card,
              border:Border.all(color:perfect?Pal.gold:unlocked?diff.color:Pal.ts.withOpacity(0.3),width:perfect?3:2),
              boxShadow:unlocked?[BoxShadow(color:(perfect?Pal.gold:diff.color).withOpacity(0.4),blurRadius:18,spreadRadius:2)]:null),
            child:Center(child:unlocked
              ?Text('${index+1}',style:const TextStyle(color:Colors.white,fontSize:22,fontWeight:FontWeight.w900))
              :const Icon(Icons.lock_rounded,color:Pal.ts,size:22))),
        ]))),
    ]));
  }
}

class _ConPainter extends CustomPainter {
  final Alignment from,to; final Color color; final bool dashed;
  const _ConPainter({required this.from,required this.to,required this.color,this.dashed=false});
  @override void paint(Canvas c,Size s){
    final p=Paint()..color=color..strokeWidth=3..style=PaintingStyle.stroke..strokeCap=StrokeCap.round;
    final f=Offset((from.x+1)/2*s.width,s.height);
    final t=Offset((to.x+1)/2*s.width,0);
    if(!dashed){
      final path=Path()..moveTo(f.dx,f.dy)..cubicTo(f.dx,f.dy-s.height*0.4,t.dx,t.dy+s.height*0.4,t.dx,t.dy);
      c.drawPath(path,p);
    }else{
      final tot=(t-f).distance;final dir=(t-f)/tot;double drawn=0;bool on=true;
      while(drawn<tot){final seg=on?8.0:6.0;final end=min(drawn+seg,tot);if(on)c.drawLine(f+dir*drawn,f+dir*end,p);drawn=end;on=!on;}
    }
  }
  @override bool shouldRepaint(_)=>false;
}

// ═══════════════════════════════════════════════
//  GAME SCREEN
// ═══════════════════════════════════════════════
class GameScreen extends StatefulWidget {
  final Diff diff; final int levelIndex;
  const GameScreen({super.key,required this.diff,required this.levelIndex});
  @override State<GameScreen> createState()=>_GS();
}
class _GS extends State<GameScreen> with TickerProviderStateMixin {
  late final GameState _gs;
  late final AnimationController _shakeCtrl,_cardCtrl,_energyLossCtrl;
  late final Animation<double> _shake,_card,_energyLossOpacity,_energyLossOffset;
  bool _exiting=false;
  @override void initState(){
    super.initState();
    _gs=GameState(diff:widget.diff,levelIdx:widget.levelIndex);
    _gs.addListener(_onChange);
    EnergyService.instance.addListener(_onEnergyChange);
    _shakeCtrl=AnimationController(vsync:this,duration:const Duration(milliseconds:400));
    _cardCtrl=AnimationController(vsync:this,duration:const Duration(milliseconds:400));
    _energyLossCtrl=AnimationController(vsync:this,duration:const Duration(milliseconds:900));
    _shake=TweenSequence([TweenSequenceItem(tween:Tween(begin:0.0,end:-12.0),weight:25),TweenSequenceItem(tween:Tween(begin:-12.0,end:12.0),weight:50),TweenSequenceItem(tween:Tween(begin:12.0,end:0.0),weight:25)]).animate(CurvedAnimation(parent:_shakeCtrl,curve:Curves.easeInOut));
    _card=CurvedAnimation(parent:_cardCtrl,curve:Curves.easeOutBack);
    _energyLossOpacity=TweenSequence([TweenSequenceItem(tween:Tween(begin:0.0,end:1.0),weight:15),TweenSequenceItem(tween:Tween(begin:1.0,end:1.0),weight:50),TweenSequenceItem(tween:Tween(begin:1.0,end:0.0),weight:35)]).animate(CurvedAnimation(parent:_energyLossCtrl,curve:Curves.easeInOut));
    _energyLossOffset=Tween(begin:0.0,end:-80.0).animate(CurvedAnimation(parent:_energyLossCtrl,curve:Curves.easeOut));
    _cardCtrl.forward();
  }
  void _onEnergyChange(){
    if(!mounted||_exiting)return;
    if(!EnergyService.instance.has){
      _exiting=true;
      Future.delayed(const Duration(milliseconds:300),(){
        if(mounted)Navigator.pushReplacement(context,_slide(const NoEnergyScreen()));
      });
    }
  }
  void _onChange(){
    if(!mounted)return;
    if(_gs.fb&&_gs.sel!=null&&_gs.sel!=_gs.cur.c){
      _shakeCtrl.forward(from:0);
      _energyLossCtrl.forward(from:0);
    }
    setState((){});
    if(_gs.phase==Phase.complete&&!_exiting){_exiting=true;Future.delayed(const Duration(milliseconds:400),(){if(mounted)Navigator.pushReplacement(context,_slide(CompleteScreen(diff:widget.diff,levelIndex:widget.levelIndex,stars:_gs.stars)));});}
    if(_gs.phase==Phase.failed&&!_exiting){_exiting=true;Future.delayed(const Duration(milliseconds:400),(){if(mounted)Navigator.pushReplacement(context,_slide(FailedScreen(diff:widget.diff,levelIndex:widget.levelIndex)));});}
  }
  @override void dispose(){_gs.removeListener(_onChange);EnergyService.instance.removeListener(_onEnergyChange);_gs.dispose();_shakeCtrl.dispose();_cardCtrl.dispose();_energyLossCtrl.dispose();super.dispose();}
  Future<bool> _quit() async {
    final leave=await showDialog<bool>(context:context,barrierDismissible:false,builder:(_)=>_QuitDlg());
    return leave??false;
  }
  @override Widget build(BuildContext context){
    final q=_gs.cur;
    return WillPopScope(onWillPop:_quit,
      child:Scaffold(backgroundColor:Pal.bg,body:Stack(children:[
        const StarField(),
        SafeArea(child:Column(children:[
          // Top bar
          Padding(padding:const EdgeInsets.fromLTRB(16,8,16,0),child:Row(children:[
            _iconBtn(Icons.close,()async{final l=await _quit();if(l&&mounted)Navigator.pop(context);}),const SizedBox(width:8),_iconBtn(Icons.refresh_rounded,()async{final l=await showDialog<bool>(context:context,barrierDismissible:false,builder:(_)=>_RestartDlg());if((l??false)&&mounted){setState((){});_gs.removeListener(_onChange);_gs.dispose();setState((){_gs=GameState(diff:widget.diff,levelIdx:widget.levelIndex);_gs.addListener(_onChange);_exiting=false;_cardCtrl.forward(from:0);});}}),
            const SizedBox(width:12),
            Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
              Text('\u05E9\u05DC\u05D1 ${_gs.levelIdx+1} \u00B7 ${widget.diff.label}',style:const TextStyle(color:Pal.ts,fontSize:11,fontWeight:FontWeight.w600)),
              const SizedBox(height:4),
              ClipRRect(borderRadius:BorderRadius.circular(6),
                child:LinearProgressIndicator(value:_gs.prog,minHeight:8,backgroundColor:Pal.card,valueColor:AlwaysStoppedAnimation(widget.diff.color))),
            ])),
            const SizedBox(width:8),
            const EnergyChip(),
            const SizedBox(width:8),
            _TimerRing(gs:_gs),
          ])),
          const SizedBox(height:14),
          // Stars
          Row(mainAxisAlignment:MainAxisAlignment.center,children:List.generate(3,(i)=>Padding(
            padding:const EdgeInsets.symmetric(horizontal:6),
            child:AnimatedSwitcher(duration:const Duration(milliseconds:300),
              child:Text(i<_gs.stars?'\u2B50':'\u2606',key:ValueKey('$i-${_gs.stars}'),
                style:TextStyle(fontSize:36,color:i<_gs.stars?Pal.starOn:Pal.starOff)))))),
          const SizedBox(height:16),
          // Content
          Expanded(child:SingleChildScrollView(padding:const EdgeInsets.fromLTRB(20,0,20,20),child:Column(children:[
            ScaleTransition(scale:_card,child:AnimatedBuilder(animation:_shake,builder:(_,__)=>Transform.translate(
              offset:Offset(_gs.fb&&_gs.sel!=null&&_gs.sel!=q.c?_shake.value:0,0),
              child:_QCard(gs:_gs,diff:widget.diff)))),
            const SizedBox(height:16),
            if(_gs.fb&&q.f!=null)_FactBanner(gs:_gs),
            const SizedBox(height:10),
            ...List.generate(q.a.length,(i)=>Padding(padding:const EdgeInsets.only(bottom:10),child:_ABtn(gs:_gs,i:i))),
          ]))),
        ])),
        // ─── אפקט −1 ⚡ באמצע המסך ───
        AnimatedBuilder(
          animation:_energyLossCtrl,
          builder:(_,__){
            if(_energyLossCtrl.status==AnimationStatus.dismissed)return const SizedBox.shrink();
            return Positioned.fill(child:IgnorePointer(child:Center(child:Transform.translate(
              offset:Offset(0,_energyLossOffset.value),
              child:Opacity(opacity:_energyLossOpacity.value,
                child:Container(
                  padding:const EdgeInsets.symmetric(horizontal:20,vertical:12),
                  decoration:BoxDecoration(
                    color:Pal.red.withOpacity(0.15),
                    borderRadius:BorderRadius.circular(40),
                    border:Border.all(color:Pal.red.withOpacity(0.6),width:2),
                    boxShadow:[BoxShadow(color:Pal.red.withOpacity(0.35),blurRadius:24,spreadRadius:4)]),
                  child:Row(mainAxisSize:MainAxisSize.min,children:[
                    const Text('⚡',style:TextStyle(fontSize:28)),
                    const SizedBox(width:6),
                    Text('−1',style:TextStyle(fontSize:32,fontWeight:FontWeight.w900,color:Pal.red,
                      shadows:[Shadow(color:Pal.red.withOpacity(0.8),blurRadius:12)])),
                  ])))))));
          }),
      ])));
  }
}

class _TimerRing extends StatelessWidget {
  final GameState gs;
  const _TimerRing({required this.gs});
  @override Widget build(BuildContext context){
    final s=gs.timer; final pct=s/Cfg.timerSecs;
    final c=pct>0.5?const Color(0xFF4D96FF):pct>0.25?const Color(0xFFF39C12):Pal.red;
    return SizedBox(width:54,height:54,child:Stack(alignment:Alignment.center,children:[
      SizedBox(width:54,height:54,child:CircularProgressIndicator(value:pct,strokeWidth:5,
        backgroundColor:Pal.card,valueColor:AlwaysStoppedAnimation(c))),
      Text('$s',style:TextStyle(color:c,fontSize:16,fontWeight:FontWeight.w900)),
    ]));
  }
}

class _QCard extends StatelessWidget {
  final GameState gs; final Diff diff;
  const _QCard({required this.gs,required this.diff});
  @override Widget build(BuildContext context){
    final q=gs.cur;
    Color bc=diff.color.withOpacity(0.3);
    if(gs.fb)bc=gs.sel==q.c?Pal.green:Pal.red;
    return Container(width:double.infinity,padding:const EdgeInsets.all(18),
      decoration:BoxDecoration(color:Pal.card,borderRadius:BorderRadius.circular(20),
        border:Border.all(color:bc,width:2),
        boxShadow:[BoxShadow(color:(gs.fb?(gs.sel==q.c?Pal.green:Pal.red):diff.color).withOpacity(0.15),blurRadius:16,offset:const Offset(0,6))]),
      child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
        Row(children:[
          Container(padding:const EdgeInsets.symmetric(horizontal:8,vertical:3),
            decoration:BoxDecoration(color:diff.color.withOpacity(0.15),borderRadius:BorderRadius.circular(8),border:Border.all(color:diff.color.withOpacity(0.4))),
            child:Text('${gs.qi+1} / ${gs.total}',style:TextStyle(color:diff.color,fontSize:10,fontWeight:FontWeight.w700))),
          const Spacer(),
          Text(diff.label,style:TextStyle(color:diff.color,fontSize:10,fontWeight:FontWeight.w700)),
        ]),
        const SizedBox(height:12),
        Text(q.q,style:const TextStyle(color:Pal.tp,fontSize:17,fontWeight:FontWeight.w700,height:1.35)),
      ]));
  }
}

class _FactBanner extends StatelessWidget {
  final GameState gs;
  const _FactBanner({required this.gs});
  @override Widget build(BuildContext context){
    final q=gs.cur; final ok=gs.sel==q.c; final c=ok?Pal.green:Pal.red;
    return AnimatedOpacity(opacity:gs.fb?1:0,duration:const Duration(milliseconds:250),
      child:Container(margin:const EdgeInsets.only(bottom:8),padding:const EdgeInsets.all(14),
        decoration:BoxDecoration(color:c.withOpacity(0.1),borderRadius:BorderRadius.circular(16),border:Border.all(color:c.withOpacity(0.4))),
        child:Row(crossAxisAlignment:CrossAxisAlignment.start,children:[
          Text(ok?'\u2705':'\u274C',style:const TextStyle(fontSize:16)),const SizedBox(width:10),
          Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
            Text(ok?'\u05E0\u05DB\u05D5\u05DF!':'\u05EA\u05E9\u05D5\u05D1\u05D4: ${q.a[q.c]}',style:TextStyle(color:c,fontWeight:FontWeight.w800,fontSize:13)),
            if(q.f!=null)...[const SizedBox(height:4),Text(q.f!,style:const TextStyle(color:Pal.ts,fontSize:12,height:1.4))],
          ])),
        ])));
  }
}

class _ABtn extends StatefulWidget {
  final GameState gs; final int i;
  const _ABtn({required this.gs,required this.i});
  @override State<_ABtn> createState()=>_ABtnS();
}
class _ABtnS extends State<_ABtn> with SingleTickerProviderStateMixin {
  late final AnimationController _c; late final Animation<double> _s;
  @override void initState(){super.initState();_c=AnimationController(vsync:this,duration:const Duration(milliseconds:100));_s=Tween(begin:1.0,end:0.96).animate(CurvedAnimation(parent:_c,curve:Curves.easeOut));}
  @override void dispose(){_c.dispose();super.dispose();}
  Color _bg(){if(!widget.gs.fb)return Pal.cardL;if(widget.i==widget.gs.cur.c)return Pal.green.withOpacity(0.25);if(widget.i==widget.gs.sel)return Pal.red.withOpacity(0.25);return Pal.card.withOpacity(0.5);}
  Color _bd(){if(!widget.gs.fb)return Pal.ts.withOpacity(0.3);if(widget.i==widget.gs.cur.c)return Pal.green;if(widget.i==widget.gs.sel)return Pal.red;return Pal.ts.withOpacity(0.1);}
  @override Widget build(BuildContext context){
    const letters=['\u05D0','\u05D1','\u05D2','\u05D3'];
    final lc=[Pal.accent,const Color(0xFF4D96FF),const Color(0xFFFF6B9D),const Color(0xFF2ECC71)][widget.i%4];
    return AnimatedBuilder(animation:_c,builder:(_,child)=>Transform.scale(scale:_s.value,child:child),
      child:GestureDetector(
        onTapDown:(_){if(!widget.gs.fb)_c.forward();},
        onTapUp:(_){_c.reverse();if(!widget.gs.fb)widget.gs.answer(widget.i);},
        onTapCancel:()=>_c.reverse(),
        child:AnimatedContainer(duration:const Duration(milliseconds:200),
          padding:const EdgeInsets.symmetric(vertical:12,horizontal:14),
          decoration:BoxDecoration(color:_bg(),borderRadius:BorderRadius.circular(14),border:Border.all(color:_bd(),width:1.5),
            boxShadow:[BoxShadow(color:lc.withOpacity(widget.gs.fb?0:0.1),blurRadius:6)]),
          child:Row(children:[
            Container(width:30,height:30,decoration:BoxDecoration(color:lc.withOpacity(0.15),borderRadius:BorderRadius.circular(8),border:Border.all(color:lc.withOpacity(0.5))),
              child:Center(child:Text(letters[widget.i],style:TextStyle(color:lc,fontWeight:FontWeight.w900,fontSize:13)))),
            const SizedBox(width:12),
            Expanded(child:Text(widget.gs.cur.a[widget.i],style:TextStyle(color:widget.gs.fb&&widget.i!=widget.gs.cur.c&&widget.i!=widget.gs.sel?Pal.ts:Pal.tp,fontSize:14,fontWeight:FontWeight.w600))),
            if(widget.gs.fb)Text(widget.i==widget.gs.cur.c?'\u2705':widget.i==widget.gs.sel?'\u274C':'',style:const TextStyle(fontSize:16)),
          ]))));
  }
}

// ═══════════════════════════════════════════════
//  QUIT DIALOG
// ═══════════════════════════════════════════════
class _QuitDlg extends StatelessWidget {
  @override Widget build(BuildContext context){
    return Dialog(backgroundColor:Pal.card,shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(24)),
      child:Padding(padding:const EdgeInsets.all(24),child:Column(mainAxisSize:MainAxisSize.min,children:[
        const Text('\u{1F6AA}',style:TextStyle(fontSize:48)),const SizedBox(height:12),
        const Text('\u05DC\u05E6\u05D0\u05EA \u05DE\u05D4\u05E9\u05DC\u05D1?',style:TextStyle(color:Pal.tp,fontSize:20,fontWeight:FontWeight.w800)),
        const SizedBox(height:8),
        const Text('\u05D4\u05D4\u05EA\u05E7\u05D3\u05DE\u05D5\u05EA \u05D1\u05E9\u05DC\u05D1 \u05D6\u05D4 \u05DC\u05D0 \u05EA\u05D9\u05E9\u05DE\u05E8',textAlign:TextAlign.center,style:TextStyle(color:Pal.ts,fontSize:14)),
        const SizedBox(height:24),
        Row(children:[
          Expanded(child:OutlinedButton(onPressed:()=>Navigator.pop(context,false),
            style:OutlinedButton.styleFrom(side:const BorderSide(color:Pal.accent),shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(14))),
            child:const Padding(padding:EdgeInsets.symmetric(vertical:12),child:Text('\u05D4\u05DE\u05E9\u05DA \u05DC\u05E9\u05D7\u05E7',style:TextStyle(color:Pal.accent,fontWeight:FontWeight.w700))))),
          const SizedBox(width:12),
          Expanded(child:ElevatedButton(onPressed:()=>Navigator.pop(context,true),
            style:ElevatedButton.styleFrom(backgroundColor:Pal.red.withOpacity(0.2),shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(14))),
            child:const Padding(padding:EdgeInsets.symmetric(vertical:12),child:Text('\u05D9\u05E6\u05D9\u05D0\u05D4',style:TextStyle(color:Pal.red,fontWeight:FontWeight.w700))))),
        ]),
      ])));
  }
}

// ═══════════════════════════════════════════════
//  COMPLETE SCREEN
// ═══════════════════════════════════════════════
class CompleteScreen extends StatefulWidget {
  final Diff diff; final int levelIndex,stars;
  const CompleteScreen({super.key,required this.diff,required this.levelIndex,required this.stars});
  @override State<CompleteScreen> createState()=>_CS();
}
class _CS extends State<CompleteScreen> with TickerProviderStateMixin {
  late final List<AnimationController> _sc;
  late final AnimationController _enter, _confettiCtrl;
  final List<_Confetti> _confettiPieces = [];
  bool _showButtons = false;

  @override void initState() {
    super.initState();
    _enter = AnimationController(vsync:this, duration:const Duration(milliseconds:700))..forward();
    _confettiCtrl = AnimationController(vsync:this, duration:const Duration(seconds:3))..forward();
    _sc = List.generate(3,(i) => AnimationController(vsync:this, duration:const Duration(milliseconds:600)));
    // Generate confetti
    final rnd = Random();
    for (int i = 0; i < 60; i++) {
      _confettiPieces.add(_Confetti(
        x: rnd.nextDouble(),
        delay: rnd.nextDouble() * 0.6,
        color: [Pal.gold, Pal.green, Pal.accent, Pal.premium,
          const Color(0xFF4D96FF), const Color(0xFFFF6B9D)][rnd.nextInt(6)],
        size: rnd.nextDouble() * 8 + 5,
        rotSpeed: (rnd.nextDouble() - 0.5) * 3,
        swayAmp: rnd.nextDouble() * 0.05 + 0.01,
      ));
    }
    // Animate stars one by one
    for (int i = 0; i < widget.stars; i++) {
      Future.delayed(Duration(milliseconds: 600 + i * 300), () {
        if (mounted) { _sc[i].forward(); HapticFeedback.lightImpact(); }
      });
    }
    // Show buttons after animation
    Future.delayed(Duration(milliseconds: 600 + widget.stars * 300 + 400), () {
      if (mounted) setState(() => _showButtons = true);
    });
  }

  @override void dispose() {
    _enter.dispose(); _confettiCtrl.dispose();
    for (final c in _sc) c.dispose();
    super.dispose();
  }

  bool get _canNext {
    final n = widget.levelIndex + 1;
    return n < QRepo.levelCount(widget.diff) && LevelService.instance.isLevelUnlocked(widget.diff, n);
  }

  @override Widget build(BuildContext context) {
    final perfect = widget.stars == Cfg.starsPerLevel;
    return Scaffold(backgroundColor: Pal.bg, body: Stack(children: [
      const StarField(),
      // Confetti layer
      AnimatedBuilder(
        animation: _confettiCtrl,
        builder: (_, __) => CustomPaint(
          size: Size.infinite,
          painter: _ConfettiPainter(_confettiPieces, _confettiCtrl.value))),
      SafeArea(child: Center(child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          ScaleTransition(
            scale: CurvedAnimation(parent: _enter, curve: Curves.easeOutBack),
            child: Text(perfect ? '\u{1F3C6}' : '\u{1F3AF}',
              style: const TextStyle(fontSize: 90))),
          const SizedBox(height: 16),
          FadeTransition(opacity: _enter,
            child: Text(perfect ? 'מושלם! 🌟' : 'כל הכבוד!',
              style: TextStyle(color: perfect ? Pal.gold : Pal.tp,
                fontSize: 30, fontWeight: FontWeight.w900))),
          const SizedBox(height: 6),
          Text('שלב ${widget.levelIndex + 1} · ${widget.diff.label}',
            style: const TextStyle(color: Pal.ts, fontSize: 16)),
          const SizedBox(height: 36),
          // Stars with animation
          Row(mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(3, (i) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: ScaleTransition(
                scale: CurvedAnimation(parent: _sc[i], curve: Curves.easeOutBack),
                child: AnimatedBuilder(
                  animation: _sc[i],
                  builder: (_, child) => Container(
                    decoration: BoxDecoration(
                      boxShadow: _sc[i].value > 0 && i < widget.stars ? [
                        BoxShadow(color: Pal.gold.withOpacity(0.6 * _sc[i].value),
                          blurRadius: 20, spreadRadius: 2)] : []),
                    child: Text(i < widget.stars ? '\u2B50' : '\u2606',
                      style: TextStyle(fontSize: 56,
                        color: i < widget.stars ? Pal.starOn : Pal.starOff)))))))),
          const SizedBox(height: 48),
          // Buttons appear after animation
          AnimatedOpacity(
            opacity: _showButtons ? 1.0 : 0.0,
            duration: const Duration(milliseconds: 400),
            child: AnimatedSlide(
              offset: _showButtons ? Offset.zero : const Offset(0, 0.3),
              duration: const Duration(milliseconds: 400),
              curve: Curves.easeOut,
              child: Column(children: [
                if (_canNext) ...[
                  _bigBtn('השלב הבא ▶', widget.diff.color, () {
                    if(!EnergyService.instance.has){Navigator.push(context,_slide(const NoEnergyScreen()));return;}
                    EnergyService.instance.spend(Cfg.energyCostWrong);
                    Navigator.pushReplacement(context, _slide(GameScreen(
                      diff: widget.diff, levelIndex: widget.levelIndex + 1)));
                  }),
                  const SizedBox(height: 14),
                ],
                _outBtn('🗺️  מפת שלבים', () =>
                  Navigator.popUntil(context, (r) => r.isFirst)),
              ]))),
        ])))),
    ]));
  }
}

// ─── Confetti data ───
class _Confetti {
  final double x, delay, size, rotSpeed, swayAmp;
  final Color color;
  const _Confetti({required this.x, required this.delay,
    required this.color, required this.size,
    required this.rotSpeed, required this.swayAmp});
}

class _ConfettiPainter extends CustomPainter {
  final List<_Confetti> pieces;
  final double t; // 0..1
  _ConfettiPainter(this.pieces, this.t);

  @override void paint(Canvas canvas, Size size) {
    for (final p in pieces) {
      final progress = ((t - p.delay) / (1 - p.delay)).clamp(0.0, 1.0);
      if (progress <= 0) continue;
      final y = progress * size.height * 1.2;
      final x = p.x * size.width + sin(progress * pi * 4 * p.swayAmp * 20) * size.width * p.swayAmp;
      final rotation = progress * pi * 4 * p.rotSpeed;
      final opacity = progress < 0.7 ? 1.0 : (1.0 - (progress - 0.7) / 0.3);
      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(rotation);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: Offset.zero, width: p.size, height: p.size * 0.5),
          const Radius.circular(2)),
        Paint()..color = p.color.withOpacity(opacity));
      canvas.restore();
    }
  }
  @override bool shouldRepaint(_ConfettiPainter old) => old.t != t;
}

// ═══════════════════════════════════════════════
//  FAILED SCREEN
// ═══════════════════════════════════════════════
class FailedScreen extends StatefulWidget {
  final Diff diff; final int levelIndex;
  const FailedScreen({super.key,required this.diff,required this.levelIndex});
  @override State<FailedScreen> createState()=>_FS();
}
class _FS extends State<FailedScreen> with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  @override void initState(){super.initState();_c=AnimationController(vsync:this,duration:const Duration(milliseconds:600))..forward();}
  @override void dispose(){_c.dispose();super.dispose();}
  @override Widget build(BuildContext context){
    return Scaffold(backgroundColor:Pal.bg,body:Stack(children:[
      const StarField(),
      SafeArea(child:Center(child:SingleChildScrollView(padding:const EdgeInsets.all(32),child:Column(mainAxisAlignment:MainAxisAlignment.center,children:[
        ScaleTransition(scale:CurvedAnimation(parent:_c,curve:Curves.easeOutBack),child:const Text('\u{1F494}',style:TextStyle(fontSize:90))),
        const SizedBox(height:16),
        FadeTransition(opacity:_c,child:const Text('\u05E0\u05E4\u05E1\u05DC\u05EA!',style:TextStyle(color:Pal.red,fontSize:36,fontWeight:FontWeight.w900))),
        const SizedBox(height:8),
        Text('\u05E9\u05DC\u05D1 ${widget.levelIndex+1} \u00B7 ${widget.diff.label}',style:const TextStyle(color:Pal.ts,fontSize:16)),
        const SizedBox(height:20),
        ListenableBuilder(listenable:EnergyService.instance,builder:(_,__)=>Container(
          padding:const EdgeInsets.symmetric(horizontal:24,vertical:12),
          decoration:BoxDecoration(color:Pal.card,borderRadius:BorderRadius.circular(16),border:Border.all(color:Pal.red.withOpacity(0.3))),
          child:Row(mainAxisSize:MainAxisSize.min,children:[
            const Text('\u26A1',style:TextStyle(fontSize:18)),const SizedBox(width:8),
            Text('\u05D0\u05E0\u05E8\u05D2\u05D9\u05D4: ${EnergyService.instance.energy}/${EnergyService.instance.maxE}',style:const TextStyle(color:Pal.tp,fontSize:14)),
          ]))),
        const SizedBox(height:48),
        _bigBtn('\u{1F504}  \u05E0\u05E1\u05D4 \u05E9\u05D5\u05D1',widget.diff.color,(){
          if(!EnergyService.instance.has){Navigator.push(context,_slide(const NoEnergyScreen()));return;}
          Navigator.pushReplacement(context,_slide(GameScreen(diff:widget.diff,levelIndex:widget.levelIndex)));
        }),
        const SizedBox(height:14),
        _outBtn('\u{1F5FA}\uFE0F  \u05DE\u05E4\u05EA \u05E9\u05DC\u05D1\u05D9\u05DD',()=>Navigator.popUntil(context,(r)=>r.isFirst)),
      ])))),
    ]));
  }
}

// ═══════════════════════════════════════════════
// ═══════════════════════════════════════════════
//  RESTART DIALOG
// ═══════════════════════════════════════════════
class _RestartDlg extends StatelessWidget {
  @override Widget build(BuildContext context){
    return Dialog(backgroundColor:Pal.card,shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(24)),
      child:Padding(padding:const EdgeInsets.all(24),child:Column(mainAxisSize:MainAxisSize.min,children:[
        const Text('\u{1F504}',style:TextStyle(fontSize:48)),const SizedBox(height:12),
        const Text('\u05D4\u05EA\u05D7\u05DC \u05DE\u05D4\u05EA\u05D7\u05DC\u05D4?',style:TextStyle(color:Pal.tp,fontSize:20,fontWeight:FontWeight.w800)),
        const SizedBox(height:8),
        const Text('\u05D4\u05E9\u05DC\u05D1 \u05D9\u05EA\u05D7\u05D9\u05DC \u05DE\u05D7\u05D3\u05E9. \u05D4\u05DB\u05D5\u05DB\u05D1\u05D9\u05DD \u05E9\u05E0\u05E6\u05D1\u05E8\u05D5 \u05D9\u05E9\u05DE\u05E8\u05D5.',textAlign:TextAlign.center,style:TextStyle(color:Pal.ts,fontSize:14)),
        const SizedBox(height:24),
        Row(children:[
          Expanded(child:OutlinedButton(onPressed:()=>Navigator.pop(context,false),
            style:OutlinedButton.styleFrom(side:const BorderSide(color:Pal.accent),shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(14))),
            child:const Padding(padding:EdgeInsets.symmetric(vertical:12),child:Text('\u05D1\u05D8\u05DC',style:TextStyle(color:Pal.accent,fontWeight:FontWeight.w700))))),
          const SizedBox(width:12),
          Expanded(child:ElevatedButton(onPressed:()=>Navigator.pop(context,true),
            style:ElevatedButton.styleFrom(backgroundColor:Pal.green.withOpacity(0.2),shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(14))),
            child:const Padding(padding:EdgeInsets.symmetric(vertical:12),child:Text('\u05D4\u05EA\u05D7\u05DC',style:TextStyle(color:Pal.green,fontWeight:FontWeight.w700))))),
        ]),
      ])));
  }
}

// ═══════════════════════════════════════════════
//  NO ENERGY SCREEN
// ═══════════════════════════════════════════════
class NoEnergyScreen extends StatefulWidget {
  const NoEnergyScreen({super.key});
  @override State<NoEnergyScreen> createState()=>_NES();
}
class _NES extends State<NoEnergyScreen> with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  Timer? _timer;
  @override void initState(){
    super.initState();
    _c=AnimationController(vsync:this,duration:const Duration(milliseconds:600))..forward();
    EnergyService.instance.addListener(_refresh);
    _timer=Timer.periodic(const Duration(seconds:1),(_){if(mounted)setState((){});});
  }
  void _refresh(){if(mounted)setState((){});}
  @override void dispose(){_c.dispose();_timer?.cancel();EnergyService.instance.removeListener(_refresh);super.dispose();}
  @override Widget build(BuildContext context){
    final e=EnergyService.instance;
    final isPro=PurchaseService.instance.isPremium;
    return Scaffold(backgroundColor:Pal.bg,body:Stack(children:[
      const StarField(),
      SafeArea(child:Column(children:[
        Padding(padding:const EdgeInsets.fromLTRB(16,12,16,0),
          child:Row(children:[_iconBtn(Icons.arrow_back,()=>Navigator.pop(context))])),
        Expanded(child:Center(child:SingleChildScrollView(padding:const EdgeInsets.all(28),child:Column(mainAxisAlignment:MainAxisAlignment.center,children:[
          ScaleTransition(scale:CurvedAnimation(parent:_c,curve:Curves.easeOutBack),
            child:const Text('\u26A1',style:TextStyle(fontSize:80))),
          const SizedBox(height:16),
          FadeTransition(opacity:_c,child:const Text('\u05E0\u05D2\u05DE\u05E8\u05D4 \u05D4\u05D0\u05E0\u05E8\u05D2\u05D9\u05D4!',
            style:TextStyle(color:Pal.tp,fontSize:26,fontWeight:FontWeight.w900))),
          const SizedBox(height:20),
          Container(
            width:double.infinity,
            padding:const EdgeInsets.all(20),
            decoration:BoxDecoration(color:Pal.card,borderRadius:BorderRadius.circular(20),
              border:Border.all(color:Pal.ts.withOpacity(0.2))),
            child:Column(children:[
              Row(mainAxisAlignment:MainAxisAlignment.center,children:[
                const Text('\u26A1',style:TextStyle(fontSize:20)),const SizedBox(width:8),
                Text('${e.energy} / ${e.maxE} \u05D0\u05E0\u05E8\u05D2\u05D9\u05D4',
                  style:const TextStyle(color:Pal.tp,fontSize:17,fontWeight:FontWeight.w700)),
              ]),
              const SizedBox(height:14),
              const Divider(color:Color(0x222A3A6E)),
              const SizedBox(height:14),
              Text(
                'כל 15 דקות מתווספות ${isPro?Cfg.energyRechargeAmtPro:Cfg.energyRechargeAmt} אנרגיה',
                textAlign:TextAlign.center,
                style:const TextStyle(color:Pal.ts,fontSize:14,height:1.5)),
              if(e.label.isNotEmpty)...[
                const SizedBox(height:10),
                Container(
                  padding:const EdgeInsets.symmetric(horizontal:16,vertical:10),
                  decoration:BoxDecoration(color:Pal.gold.withOpacity(0.1),borderRadius:BorderRadius.circular(12),
                    border:Border.all(color:Pal.gold.withOpacity(0.3))),
                  child:Text('הטעינה הבאה: ${e.label}',
                    style:const TextStyle(color:Pal.gold,fontSize:15,fontWeight:FontWeight.w700))),
              ],
            ])),
          const SizedBox(height:20),
          if(!isPro)...[
            Container(
              width:double.infinity,
              padding:const EdgeInsets.all(20),
              decoration:BoxDecoration(
                gradient:LinearGradient(colors:[Pal.premium.withOpacity(0.18),Pal.premium.withOpacity(0.04)]),
                borderRadius:BorderRadius.circular(20),
                border:Border.all(color:Pal.premium.withOpacity(0.5))),
              child:Column(children:[
                const Text('\u{1F451}  \u05E8\u05DB\u05D5\u05E9 \u05E4\u05E8\u05D5',
                  style:TextStyle(color:Pal.premium,fontSize:18,fontWeight:FontWeight.w900)),
                const SizedBox(height:10),
                Text(
                  '50 אנרגיה במקום 15 · טעינה של ${Cfg.energyRechargeAmtPro} כל 15 דקות\nבמקום ${Cfg.energyRechargeAmt} במצב הרגיל',
                  textAlign:TextAlign.center,
                  style:const TextStyle(color:Pal.ts,fontSize:13,height:1.6)),
                const SizedBox(height:16),
                GestureDetector(
                  onTap:(){
                    Navigator.pop(context);
                    showModalBottomSheet(context:context,isScrollControlled:true,backgroundColor:Colors.transparent,
                      builder:(_)=>PaywallSheet(onCode:(c){
                        final ok=PurchaseService.instance.tryDev(c);
                        Navigator.pop(context);
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                          content:Text(ok?'\u05E7\u05D5\u05D3 \u05D0\u05D5\u05E9\u05E8! \u{1F389}':'\u05E7\u05D5\u05D3 \u05E9\u05D2\u05D5\u05D9'),
                          backgroundColor:ok?Pal.green:Pal.red));
                      }));
                  },
                  child:Container(width:double.infinity,
                    padding:const EdgeInsets.symmetric(vertical:14),
                    decoration:BoxDecoration(
                      gradient:const LinearGradient(colors:[Color(0xFFFF9F0A),Color(0xFFFF6B00)]),
                      borderRadius:BorderRadius.circular(14)),
                    child:const Text('רכישת פרו',
                      textAlign:TextAlign.center,
                      style:TextStyle(color:Colors.white,fontSize:16,fontWeight:FontWeight.w900)))),
              ])),
            const SizedBox(height:16),
          ],
          _outBtn('\u05D7\u05D6\u05E8\u05D4',()=>Navigator.pop(context)),
        ])))),
      ])),
    ]));
  }
}

//  PAYWALL
// ═══════════════════════════════════════════════
class PaywallSheet extends StatefulWidget {
  final void Function(String) onCode;
  const PaywallSheet({super.key,required this.onCode});
  @override State<PaywallSheet> createState()=>_PS();
}
class _PS extends State<PaywallSheet>{
  bool _showCode=false;
  final _ctrl=TextEditingController();
  @override void dispose(){_ctrl.dispose();super.dispose();}
  @override Widget build(BuildContext context){
    final ps=PurchaseService.instance;
    return Container(
      height:MediaQuery.of(context).size.height*0.85,
      decoration:const BoxDecoration(color:Color(0xFF0A1128),borderRadius:BorderRadius.vertical(top:Radius.circular(28))),
      child:Column(children:[
        Container(margin:const EdgeInsets.only(top:12),width:40,height:4,decoration:BoxDecoration(color:Pal.ts.withOpacity(0.4),borderRadius:BorderRadius.circular(2))),
        Expanded(child:SingleChildScrollView(padding:const EdgeInsets.fromLTRB(24,20,24,0),child:Column(children:[
          Container(width:76,height:76,
            decoration:BoxDecoration(shape:BoxShape.circle,
              gradient:const LinearGradient(colors:[Color(0xFFFF9F0A),Color(0xFFFF6B00)]),
              boxShadow:[BoxShadow(color:Pal.premium.withOpacity(0.6),blurRadius:24)]),
            child:const Center(child:Text('👑',style:TextStyle(fontSize:38)))),
          const SizedBox(height:16),
          const Text('ידען פרו',style:TextStyle(color:Pal.tp,fontSize:28,fontWeight:FontWeight.w900)),
          const SizedBox(height:6),
          const Text('12.90 ₪ לחודש',style:TextStyle(color:Pal.premium,fontSize:18,fontWeight:FontWeight.w700)),
          const SizedBox(height:24),
          _bf('🔴','שלבים קשים פתוחים'),
          _bf('⚡','50 אנרגיה — פי 3 יותר מרגיל'),
          _bf('🔄','טעינה של 3 אנרגיה כל רבע שעה'),
          _bf('🚫','ללא פרסומות'),
          _bf('🔓','גישה לכל התכנים העתידיים'),
          const SizedBox(height:24),
          GestureDetector(
            onTap:()=>setState(()=>_showCode=!_showCode),
            child:Text('יש לך קוד גישה?',style:TextStyle(color:Pal.ts.withOpacity(0.6),fontSize:12,decoration:TextDecoration.underline))),
          if(_showCode)...[
            const SizedBox(height:12),
            Row(children:[
              Expanded(child:TextField(controller:_ctrl,
                style:const TextStyle(color:Pal.tp),
                decoration:InputDecoration(
                  hintText:'הזן קוד...',
                  hintStyle:const TextStyle(color:Pal.ts),
                  filled:true,fillColor:Pal.card,
                  border:OutlineInputBorder(borderRadius:BorderRadius.circular(12)),
                  contentPadding:const EdgeInsets.symmetric(horizontal:16,vertical:12)))),
              const SizedBox(width:10),
              GestureDetector(
                onTap:()=>widget.onCode(_ctrl.text.trim()),
                child:Container(
                  padding:const EdgeInsets.symmetric(horizontal:16,vertical:14),
                  decoration:BoxDecoration(color:Pal.accent,borderRadius:BorderRadius.circular(12)),
                  child:const Text('אשר',style:TextStyle(color:Colors.white,fontWeight:FontWeight.w900)))),
            ]),
          ],
          const SizedBox(height:20),
        ]))),
        Padding(padding:EdgeInsets.fromLTRB(24,0,24,MediaQuery.of(context).padding.bottom+16),
          child:Column(children:[
            if(ps.isLoading)
              const CircularProgressIndicator(color:Pal.premium)
            else GestureDetector(
              onTap:()async{
                await ps.loadOfferings();
                if(ps.packages.isNotEmpty&&mounted){
                  final ok=await ps.purchase(ps.packages.first);
                  if(ok&&mounted)Navigator.pop(context);
                }
              },
              child:Container(width:double.infinity,
                padding:const EdgeInsets.symmetric(vertical:18),
                decoration:BoxDecoration(
                  gradient:const LinearGradient(colors:[Color(0xFFFF9F0A),Color(0xFFFF6B00)]),
                  borderRadius:BorderRadius.circular(18),
                  boxShadow:[BoxShadow(color:Pal.premium.withOpacity(0.5),blurRadius:16,offset:const Offset(0,4))]),
                child:const Text('התחל עכשיו — 12.90 ₪ לחודש',
                  textAlign:TextAlign.center,
                  style:TextStyle(color:Colors.white,fontSize:16,fontWeight:FontWeight.w900)))),
            const SizedBox(height:10),
            GestureDetector(
              onTap:()async{
                final ok=await ps.restore();
                if(mounted){
                  Navigator.pop(context);
                  if(ok)ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content:Text('✅ הרכישה שוחזרה!'),backgroundColor:Pal.green));
                }
              },
              child:const Text('שחזר רכישות',style:TextStyle(color:Pal.ts,fontSize:13,decoration:TextDecoration.underline))),

          ])),
      ]));
  }
  Widget _bf(String e,String t)=>Padding(
    padding:const EdgeInsets.only(bottom:14),
    child:Row(children:[
      Text(e,style:const TextStyle(fontSize:20)),
      const SizedBox(width:14),
      Expanded(child:Text(t,style:const TextStyle(color:Pal.tp,fontSize:15,fontWeight:FontWeight.w600))),
    ]));
}


// ══════════════════════════════════════════════════
//  CATEGORY SELECT SCREEN
// ══════════════════════════════════════════════════
class CategorySelectScreen extends StatelessWidget {
  const CategorySelectScreen({super.key});

  static const _cats = [
    ('israel',    'ישראל',         '🇮🇱', Color(0xFF4D96FF)),
    ('judaism',   'יהדות',         '✡️',  Color(0xFF7C6FE0)),
    ('tv',        'טלוויזיה',      '📺',  Color(0xFF9B59B6)),
    ('music',     'מוזיקה',        '🎵',  Color(0xFFE91E8C)),
    ('sports',    'ספורט',         '⚽',  Color(0xFFE74C3C)),
    ('geography', 'גיאוגרפיה',     '🌍',  Color(0xFF2ECC71)),
    ('science',   'מדע',           '🔬',  Color(0xFF3498DB)),
    ('world',     'תרבות עולמית',  '🎬',  Color(0xFFE67E22)),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Pal.bg,
      body: Stack(children: [
        const StarField(),
        SafeArea(child: Column(children: [
          Padding(padding: const EdgeInsets.fromLTRB(16,12,16,0),
            child: Row(children: [
              _iconBtn(Icons.arrow_back, () => Navigator.pop(context)),
              const SizedBox(width:12),
              const Text('חידון קטגוריה', style: TextStyle(
                color: Pal.gold, fontSize: 22, fontWeight: FontWeight.w800)),
              const SizedBox(width:8),
              const Text('🎯', style: TextStyle(fontSize:20)),
            ])),          const SizedBox(height:16),
          Expanded(child: GridView.builder(
            padding: const EdgeInsets.symmetric(horizontal:16, vertical:4),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2, mainAxisSpacing:10, crossAxisSpacing:10,
              childAspectRatio: 1.55),
            itemCount: _cats.length,
            itemBuilder: (_, i) {
              final (key, name, emoji, color) = _cats[i];
              final count = QRepo.all(PurchaseService.instance.isPremium)
                  .where((q) => q.category == key).length;
              return GestureDetector(
                onTap: () => Navigator.push(context, _slide(
                  CategoryQuizScreen(category: key, name: name, emoji: emoji, color: color))),
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft, end: Alignment.bottomRight,
                      colors: [color.withOpacity(0.22), color.withOpacity(0.07)]),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: color.withOpacity(0.45), width:1.2),
                    boxShadow: [BoxShadow(color: color.withOpacity(0.12), blurRadius:8)]),
                  child: Row(children: [
                    const SizedBox(width:14),
                    Text(emoji, style: const TextStyle(fontSize:26)),
                    const SizedBox(width:10),
                    Expanded(child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(name, style: const TextStyle(
                          color: Pal.tp, fontSize:14, fontWeight:FontWeight.w800)),
                        const SizedBox(height:2),
                        Text('$count שאלות', style: TextStyle(
                          color: color, fontSize:10, fontWeight:FontWeight.w600)),
                      ])),
                    const SizedBox(width:8),
                  ])));
            })),
        ])),
      ]));
  }
}

// ══════════════════════════════════════════════════
//  CATEGORY QUIZ SCREEN
// ══════════════════════════════════════════════════
class CategoryQuizScreen extends StatefulWidget {
  final String category, name, emoji;
  final Color color;
  final Diff? diff;
  const CategoryQuizScreen({super.key,
    required this.category, required this.name,
    required this.emoji, required this.color, this.diff});
  @override State<CategoryQuizScreen> createState() => _CQState();
}

class _CQState extends State<CategoryQuizScreen> with TickerProviderStateMixin {
  static const _maxQ = 15;
  late List<Question> _questions;
  int _qi=0, _score=0, _correct=0, _streak=0, _bestStreak=0;
  int? _sel;
  bool _fb=false, _done=false;
  int _timerSecs=Cfg.timerSecs;
  Timer? _timer;
  late final AnimationController _shakeCtrl;
  late final Animation<double> _shake;
  late final AnimationController _energyLossCtrl;
  late final Animation<double> _energyLossOpacity;
  late final Animation<double> _energyLossOffset;

  Question get _cur => _questions[_qi];

  @override
  void initState() {
    super.initState();
    _shakeCtrl = AnimationController(vsync:this, duration:const Duration(milliseconds:400));
    _shake = TweenSequence([
      TweenSequenceItem(tween:Tween(begin:0.0,end:-10.0),weight:25),
      TweenSequenceItem(tween:Tween(begin:-10.0,end:10.0),weight:50),
      TweenSequenceItem(tween:Tween(begin:10.0,end:0.0),weight:25),
    ]).animate(CurvedAnimation(parent:_shakeCtrl,curve:Curves.easeInOut));
    _energyLossCtrl = AnimationController(vsync:this, duration:const Duration(milliseconds:900));
    _energyLossOpacity = TweenSequence([
      TweenSequenceItem(tween:Tween(begin:0.0,end:1.0),weight:15),
      TweenSequenceItem(tween:Tween(begin:1.0,end:1.0),weight:50),
      TweenSequenceItem(tween:Tween(begin:1.0,end:0.0),weight:35),
    ]).animate(CurvedAnimation(parent:_energyLossCtrl,curve:Curves.easeInOut));
    _energyLossOffset = Tween(begin:0.0,end:-80.0)
      .animate(CurvedAnimation(parent:_energyLossCtrl,curve:Curves.easeOut));
    final prem = PurchaseService.instance.isPremium;
    final pool = QRepo.all(prem)
        .where((q) => q.category == widget.category && (widget.diff == null || q.diff == widget.diff))
        .toList()..shuffle(Random());
    if (pool.length < _maxQ) {
      final extra = QRepo.all(prem)
          .where((q) => widget.diff == null || q.diff == widget.diff)
          .toList()..shuffle(Random());
      pool.addAll(extra.where((q) => q.category != widget.category));
    }
    _questions = pool.take(_maxQ).toList();
    // כניסה לחידון עולה 1 אנרגיה
    EnergyService.instance.spend(Cfg.energyCostWrong);
    _startTimer();
  }

  void _startTimer() {
    _timer?.cancel();
    _timerSecs = Cfg.timerSecs;
    _timer = Timer.periodic(const Duration(seconds:1), (t) {
      if (_fb) return;
      setState(() => _timerSecs--);
      if (_timerSecs <= 0) { t.cancel(); _onAnswer(-1); }
    });
  }

  void _onAnswer(int idx) async {
    if (_fb || _done) return;
    _timer?.cancel();
    setState(() { _sel=idx; _fb=true; });
    final ok = idx == _cur.c;
    if (ok) {
      await Sfx.correct();
      setState(() {
        _score += 10 + _cur.diff.index*5 + _streak*2;
        _correct++; _streak++;
        if (_streak > _bestStreak) _bestStreak = _streak;
      });
    } else {
      await Sfx.wrong();
      // אנרגיה יורדת בשקט — ללא פופאפ, ללא אישור
      await EnergyService.instance.spend(Cfg.energyCostWrong);
      _shakeCtrl.forward(from:0);
      _energyLossCtrl.forward(from:0);
      setState(() => _streak=0);
    }
    await Future.delayed(const Duration(milliseconds:1800));
    if (_qi >= _maxQ - 1) {
      _timer?.cancel();
      setState(() => _done = true);
    } else {
      setState(() { _qi++; _sel=null; _fb=false; });
      _startTimer();
    }
  }

  @override
  void dispose() { _timer?.cancel(); _shakeCtrl.dispose(); _energyLossCtrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    // מסך תוצאה
    if (_done) return _ResultView(
      name: widget.name, emoji: widget.emoji, color: widget.color,
      score: _score, correct: _correct, total: _maxQ, bestStreak: _bestStreak,
      onPlayAgain: () => Navigator.pushReplacement(context, _slide(
        CategoryQuizScreen(category:widget.category, name:widget.name,
          emoji:widget.emoji, color:widget.color))),
      onBack: () => Navigator.pop(context));

    final pct = _timerSecs / Cfg.timerSecs;
    final tc = pct>0.5?const Color(0xFF4D96FF):pct>0.25?const Color(0xFFF39C12):Pal.red;
    return Scaffold(
      backgroundColor: Pal.bg,
      body: Stack(children: [
        const StarField(),
        SafeArea(child: Column(children: [
          // Top bar
          Padding(padding:const EdgeInsets.fromLTRB(16,12,16,0),
            child:Row(children:[
              _iconBtn(Icons.close, ()=>Navigator.pop(context)),
              const SizedBox(width:8),
              Text(widget.emoji,style:const TextStyle(fontSize:20)),
              const SizedBox(width:6),
              Expanded(child:Text(widget.name,style:TextStyle(
                color:widget.color,fontSize:16,fontWeight:FontWeight.w800),
                overflow:TextOverflow.ellipsis)),
              // ⭐ ניקוד
              Container(
                padding:const EdgeInsets.symmetric(horizontal:10,vertical:6),
                decoration:BoxDecoration(color:Pal.card,borderRadius:BorderRadius.circular(12),
                  border:Border.all(color:Pal.gold.withOpacity(0.4))),
                child:Row(children:[
                  const Text('⭐',style:TextStyle(fontSize:13)),
                  const SizedBox(width:3),
                  AnimatedSwitcher(
                    duration:const Duration(milliseconds:250),
                    child:Text('$_score',key:ValueKey(_score),
                      style:const TextStyle(color:Pal.gold,fontWeight:FontWeight.w900,fontSize:13))),
                ])),
              const SizedBox(width:8),
              // ⚡ אנרגיה — יורדת בשקט
              const EnergyChip(),
              const SizedBox(width:8),
              // ⏱ טיימר
              SizedBox(width:46,height:46,child:Stack(alignment:Alignment.center,children:[
                SizedBox(width:46,height:46,child:CircularProgressIndicator(
                  value:pct,strokeWidth:5,backgroundColor:Pal.card,
                  valueColor:AlwaysStoppedAnimation(tc))),
                Text('$_timerSecs',style:TextStyle(color:tc,fontSize:13,fontWeight:FontWeight.w900)),
              ])),
            ])),
          // Progress bar
          Padding(padding:const EdgeInsets.fromLTRB(20,8,20,0),
            child:Row(children:[
              Text('${_qi+1}/$_maxQ',style:const TextStyle(color:Pal.ts,fontSize:11)),
              const SizedBox(width:8),
              Expanded(child:ClipRRect(borderRadius:BorderRadius.circular(4),
                child:LinearProgressIndicator(
                  value:(_qi+1)/_maxQ, minHeight:6,
                  backgroundColor:Pal.card,
                  valueColor:AlwaysStoppedAnimation(widget.color)))),
              const SizedBox(width:8),
              if (_streak>=2)
                Text('🔥×$_streak',style:const TextStyle(
                  color:Color(0xFFFF6B00),fontSize:11,fontWeight:FontWeight.w700))
              else
                Text('✅ $_correct',style:const TextStyle(color:Pal.green,fontSize:11)),
            ])),
          const SizedBox(height:12),
          // Content
          Expanded(child:SingleChildScrollView(
            padding:const EdgeInsets.fromLTRB(20,0,20,20),
            child:Column(children:[
              AnimatedBuilder(animation:_shake,builder:(_,__)=>Transform.translate(
                offset:Offset(_fb&&_sel!=_cur.c?_shake.value:0,0),
                child:_CatQCard(q:_cur,color:widget.color,fb:_fb,sel:_sel))),
              const SizedBox(height:14),
              if (_fb&&_cur.f!=null)
                AnimatedOpacity(opacity:_fb?1:0,duration:const Duration(milliseconds:250),
                  child:Container(
                    padding:const EdgeInsets.all(14),
                    decoration:BoxDecoration(
                      color:(_sel==_cur.c?Pal.green:Pal.red).withOpacity(0.1),
                      borderRadius:BorderRadius.circular(16),
                      border:Border.all(color:(_sel==_cur.c?Pal.green:Pal.red).withOpacity(0.4))),
                    child:Row(crossAxisAlignment:CrossAxisAlignment.start,children:[
                      Text(_sel==_cur.c?'✅':'❌',style:const TextStyle(fontSize:16)),
                      const SizedBox(width:10),
                      Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
                        Text(_sel==_cur.c?'נכון!':'תשובה: ${_cur.a[_cur.c]}',
                          style:TextStyle(color:_sel==_cur.c?Pal.green:Pal.red,
                            fontWeight:FontWeight.w800,fontSize:13)),
                        const SizedBox(height:4),
                        Text(_cur.f!,style:const TextStyle(color:Pal.ts,fontSize:12,height:1.4)),
                      ])),
                    ]))),
              const SizedBox(height:10),
              ...List.generate(_cur.a.length,(i)=>Padding(
                padding:const EdgeInsets.only(bottom:12),
                child:_CatAnsBtn(index:i,q:_cur,fb:_fb,sel:_sel,onTap:()=>_onAnswer(i)))),
            ]))),
        ])),
        // ─── אפקט −1 ⚡ באמצע המסך ───
        AnimatedBuilder(
          animation: _energyLossCtrl,
          builder: (_, __) {
            if (_energyLossCtrl.status == AnimationStatus.dismissed) return const SizedBox.shrink();
            return Positioned.fill(
              child: IgnorePointer(
                child: Center(
                  child: Transform.translate(
                    offset: Offset(0, _energyLossOffset.value),
                    child: Opacity(
                      opacity: _energyLossOpacity.value,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal:20, vertical:12),
                        decoration: BoxDecoration(
                          color: Pal.red.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(40),
                          border: Border.all(color: Pal.red.withOpacity(0.6), width: 2),
                          boxShadow: [BoxShadow(color: Pal.red.withOpacity(0.35), blurRadius:24, spreadRadius:4)],
                        ),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          const Text('⚡', style: TextStyle(fontSize:28)),
                          const SizedBox(width:6),
                          Text('−1', style: TextStyle(
                            fontSize: 32, fontWeight: FontWeight.w900,
                            color: Pal.red,
                            shadows: [Shadow(color: Pal.red.withOpacity(0.8), blurRadius:12)],
                          )),
                        ]),
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ]));
  }
}

// מסך תוצאה לחידון קטגוריה
class _ResultView extends StatefulWidget {
  final String name, emoji;
  final Color color;
  final int score, correct, total, bestStreak;
  final VoidCallback onPlayAgain, onBack;
  const _ResultView({required this.name, required this.emoji, required this.color,
    required this.score, required this.correct, required this.total,
    required this.bestStreak, required this.onPlayAgain, required this.onBack});
  @override State<_ResultView> createState() => _ResultViewState();
}
class _ResultViewState extends State<_ResultView> with TickerProviderStateMixin {
  late final AnimationController _enter, _scoreCtrl, _confettiCtrl;
  late final Animation<double> _enterAnim;
  late final Animation<int> _scoreAnim;
  final List<_Confetti> _pieces = [];
  bool _showBtns = false;

  @override
  void initState() {
    super.initState();
    _enter = AnimationController(vsync:this, duration:const Duration(milliseconds:700))..forward();
    _scoreCtrl = AnimationController(vsync:this, duration:const Duration(milliseconds:1200));
    _confettiCtrl = AnimationController(vsync:this, duration:const Duration(seconds:3));
    _enterAnim = CurvedAnimation(parent:_enter, curve:Curves.easeOutBack);
    _scoreAnim = IntTween(begin:0, end:widget.score)
        .animate(CurvedAnimation(parent:_scoreCtrl, curve:Curves.easeOut));
    // קונפטי רק אם מעל 70%
    final pct = widget.correct / widget.total;
    if (pct >= 0.7) {
      final rnd = Random();
      for (int i=0;i<50;i++) {
        _pieces.add(_Confetti(
          x:rnd.nextDouble(), delay:rnd.nextDouble()*0.5,
          color:[Pal.gold,Pal.green,Pal.accent,Pal.premium,
            widget.color,const Color(0xFFFF6B9D)][rnd.nextInt(6)],
          size:rnd.nextDouble()*8+4,
          rotSpeed:(rnd.nextDouble()-0.5)*3,
          swayAmp:rnd.nextDouble()*0.05+0.01));
      }
      _confettiCtrl.forward();
    }
    Future.delayed(const Duration(milliseconds:300), () => _scoreCtrl.forward());
    Future.delayed(const Duration(milliseconds:1800), () {
      if (mounted) setState(() => _showBtns = true);
    });
  }

  @override void dispose() {
    _enter.dispose(); _scoreCtrl.dispose(); _confettiCtrl.dispose(); super.dispose();
  }

  String get _grade {
    final p = widget.correct / widget.total;
    if (p >= 0.93) return 'S'; if (p >= 0.75) return 'A';
    if (p >= 0.55) return 'B'; if (p >= 0.35) return 'C';
    return 'D';
  }

  Color get _gc => {'S':Pal.gold,'A':Pal.green,'B':const Color(0xFF4D96FF),
    'C':const Color(0xFFF39C12)}[_grade] ?? Pal.red;

  String get _msg => {'S':'מושלם! גאון אמיתי 🏆',
    'A':'מצוין! כמעט מושלם 🎯',
    'B':'כל הכבוד! 💪',
    'C':'לא רע, אפשר יותר 📖',
    'D':'תמשיך להתאמן 💡'}[_grade]!;

  @override
  Widget build(BuildContext context) {
    return Scaffold(backgroundColor:Pal.bg, body:Stack(children:[
      const StarField(),
      if (_pieces.isNotEmpty) AnimatedBuilder(animation:_confettiCtrl,
        builder:(_,__)=>CustomPaint(size:Size.infinite,
          painter:_ConfettiPainter(_pieces,_confettiCtrl.value))),
      SafeArea(child:Center(child:SingleChildScrollView(
        padding:const EdgeInsets.all(28),
        child:Column(mainAxisAlignment:MainAxisAlignment.center, children:[
          // Category badge
          ScaleTransition(scale:_enterAnim,
            child:Container(
              padding:const EdgeInsets.symmetric(horizontal:20,vertical:12),
              decoration:BoxDecoration(
                color:widget.color.withOpacity(0.15),
                borderRadius:BorderRadius.circular(20),
                border:Border.all(color:widget.color.withOpacity(0.5))),
              child:Row(mainAxisSize:MainAxisSize.min,children:[
                Text(widget.emoji,style:const TextStyle(fontSize:24)),
                const SizedBox(width:10),
                Text(widget.name,style:TextStyle(
                  color:widget.color,fontSize:18,fontWeight:FontWeight.w800)),
              ]))),
          const SizedBox(height:24),
          // Grade circle
          ScaleTransition(scale:_enterAnim,
            child:Container(
              width:110,height:110,
              decoration:BoxDecoration(shape:BoxShape.circle,
                color:_gc.withOpacity(0.12),
                border:Border.all(color:_gc,width:3),
                boxShadow:[BoxShadow(color:_gc.withOpacity(0.35),blurRadius:28,spreadRadius:2)]),
              child:Center(child:Text(_grade,style:TextStyle(
                fontSize:52,fontWeight:FontWeight.w900,color:_gc))))),
          const SizedBox(height:16),
          FadeTransition(opacity:_enter,
            child:Text(_msg,style:TextStyle(
              color:_gc,fontSize:22,fontWeight:FontWeight.w800))),
          const SizedBox(height:28),
          // Score
          AnimatedBuilder(animation:_scoreCtrl,
            builder:(_,__)=>Text('${_scoreAnim.value}',style:TextStyle(
              fontSize:64,fontWeight:FontWeight.w900,color:Pal.gold,
              shadows:[Shadow(color:Pal.gold.withOpacity(0.4),blurRadius:20)]))),
          const Text('נקודות',style:TextStyle(color:Pal.ts,letterSpacing:3,fontSize:12)),
          const SizedBox(height:24),
          // Stats row
          Row(children:[
            _stat('✅ נכון','${widget.correct}/${widget.total}',Pal.green),
            const SizedBox(width:12),
            _stat('🔥 רצף מקס','${widget.bestStreak}x',const Color(0xFFFF6B00)),
            const SizedBox(width:12),
            _stat('🎯 דיוק',
              '${((widget.correct/widget.total)*100).round()}%',Pal.accent),
          ]),
          const SizedBox(height:36),
          // Buttons
          AnimatedOpacity(opacity:_showBtns?1:0,duration:const Duration(milliseconds:400),
            child:AnimatedSlide(
              offset:_showBtns?Offset.zero:const Offset(0,0.3),
              duration:const Duration(milliseconds:400),
              curve:Curves.easeOut,
              child:Column(children:[
                _bigBtn('🔄  שחק שוב',widget.color,widget.onPlayAgain),
                const SizedBox(height:12),
                _outBtn('🏠  חזרה',widget.onBack),
              ]))),
        ])))),
    ]));
  }

  Widget _stat(String l,String v,Color c)=>Expanded(child:Container(
    padding:const EdgeInsets.symmetric(vertical:14,horizontal:8),
    decoration:BoxDecoration(color:Pal.card,borderRadius:BorderRadius.circular(14),
      border:Border.all(color:c.withOpacity(0.3))),
    child:Column(children:[
      Text(v,style:TextStyle(color:c,fontSize:20,fontWeight:FontWeight.w900)),
      const SizedBox(height:4),
      Text(l,textAlign:TextAlign.center,
        style:const TextStyle(color:Pal.ts,fontSize:10,height:1.3)),
    ])));
}

// Simple question card for category mode
class _CatQCard extends StatelessWidget {
  final Question q; final Color color; final bool fb; final int? sel;
  const _CatQCard({required this.q,required this.color,required this.fb,required this.sel});
  @override Widget build(BuildContext context) {
    Color bc = color.withOpacity(0.3);
    if (fb) bc = sel==q.c ? Pal.green : Pal.red;
    return Container(width:double.infinity,padding:const EdgeInsets.all(24),
      decoration:BoxDecoration(color:Pal.card,borderRadius:BorderRadius.circular(24),
        border:Border.all(color:bc,width:2),
        boxShadow:[BoxShadow(color:(fb?(sel==q.c?Pal.green:Pal.red):color).withOpacity(0.15),blurRadius:24,offset:const Offset(0,8))]),
      child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
        Container(padding:const EdgeInsets.symmetric(horizontal:10,vertical:4),
          decoration:BoxDecoration(color:q.diff.color.withOpacity(0.15),borderRadius:BorderRadius.circular(10)),
          child:Text(q.diff.label,style:TextStyle(color:q.diff.color,fontSize:11,fontWeight:FontWeight.w700))),
        const SizedBox(height:14),
        Text(q.q,style:const TextStyle(color:Pal.tp,fontSize:20,fontWeight:FontWeight.w700,height:1.4)),
      ]));
  }
}

// Answer button for category mode
class _CatAnsBtn extends StatefulWidget {
  final int index; final Question q; final bool fb; final int? sel; final VoidCallback onTap;
  const _CatAnsBtn({required this.index,required this.q,required this.fb,required this.sel,required this.onTap});
  @override State<_CatAnsBtn> createState() => _CatAnsBtnState();
}
class _CatAnsBtnState extends State<_CatAnsBtn> with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  late final Animation<double> _s;
  @override void initState(){super.initState();_c=AnimationController(vsync:this,duration:const Duration(milliseconds:100));_s=Tween(begin:1.0,end:0.96).animate(CurvedAnimation(parent:_c,curve:Curves.easeOut));}
  @override void dispose(){_c.dispose();super.dispose();}
  Color get _bg{if(!widget.fb)return Pal.cardL;if(widget.index==widget.q.c)return Pal.green.withOpacity(0.2);if(widget.index==widget.sel)return Pal.red.withOpacity(0.2);return Pal.card.withOpacity(0.5);}
  Color get _bd{if(!widget.fb)return Pal.ts.withOpacity(0.3);if(widget.index==widget.q.c)return Pal.green;if(widget.index==widget.sel)return Pal.red;return Pal.ts.withOpacity(0.1);}
  @override Widget build(BuildContext context){
    const letters=['א','ב','ג','ד'];
    final lc=[Pal.accent,const Color(0xFF4D96FF),const Color(0xFFFF6B9D),const Color(0xFF2ECC71)][widget.index%4];
    return AnimatedBuilder(animation:_c,builder:(_,child)=>Transform.scale(scale:_s.value,child:child),
      child:GestureDetector(
        onTapDown:(_){if(!widget.fb)_c.forward();},
        onTapUp:(_){_c.reverse();if(!widget.fb)widget.onTap();},
        onTapCancel:()=>_c.reverse(),
        child:AnimatedContainer(duration:const Duration(milliseconds:200),
          padding:const EdgeInsets.symmetric(vertical:16,horizontal:16),
          decoration:BoxDecoration(color:_bg,borderRadius:BorderRadius.circular(18),border:Border.all(color:_bd,width:1.5)),
          child:Row(children:[
            Container(width:34,height:34,decoration:BoxDecoration(color:lc.withOpacity(0.15),borderRadius:BorderRadius.circular(10),border:Border.all(color:lc.withOpacity(0.5))),
              child:Center(child:Text(letters[widget.index],style:TextStyle(color:lc,fontWeight:FontWeight.w900,fontSize:15)))),
            const SizedBox(width:14),
            Expanded(child:Text(widget.q.a[widget.index],style:TextStyle(color:widget.fb&&widget.index!=widget.q.c&&widget.index!=widget.sel?Pal.ts:Pal.tp,fontSize:16,fontWeight:FontWeight.w600))),
            if(widget.fb)Text(widget.index==widget.q.c?'✅':widget.index==widget.sel?'❌':'',style:const TextStyle(fontSize:18)),
          ]))));
  }
}

// ═══════════════════════════════════════════════
//  HELPERS
// ═══════════════════════════════════════════════
Widget _iconBtn(IconData icon,VoidCallback onTap)=>GestureDetector(onTap:onTap,child:Container(padding:const EdgeInsets.all(10),decoration:BoxDecoration(color:Pal.card,borderRadius:BorderRadius.circular(12),border:Border.all(color:Pal.ts.withOpacity(0.2))),child:Icon(icon,color:Pal.ts,size:20)));
Widget _bigBtn(String l,Color c,VoidCallback t)=>GestureDetector(onTap:t,child:Container(width:double.infinity,padding:const EdgeInsets.symmetric(vertical:18),decoration:BoxDecoration(gradient:LinearGradient(colors:[c,c.withOpacity(0.7)]),borderRadius:BorderRadius.circular(18),boxShadow:[BoxShadow(color:c.withOpacity(0.4),blurRadius:16,offset:const Offset(0,6))]),child:Text(l,textAlign:TextAlign.center,style:const TextStyle(color:Colors.white,fontSize:18,fontWeight:FontWeight.w800))));
Widget _outBtn(String l,VoidCallback t)=>GestureDetector(onTap:t,child:Container(width:double.infinity,padding:const EdgeInsets.symmetric(vertical:16),decoration:BoxDecoration(borderRadius:BorderRadius.circular(18),border:Border.all(color:Pal.ts.withOpacity(0.4))),child:Text(l,textAlign:TextAlign.center,style:const TextStyle(color:Pal.ts,fontSize:16,fontWeight:FontWeight.w700))));
PageRouteBuilder _slide(Widget p)=>PageRouteBuilder(pageBuilder:(_,__,___)=>p,transitionsBuilder:(_,a,__,child)=>SlideTransition(position:Tween(begin:const Offset(1,0),end:Offset.zero).animate(CurvedAnimation(parent:a,curve:Curves.easeOutCubic)),child:child),transitionDuration:const Duration(milliseconds:350));