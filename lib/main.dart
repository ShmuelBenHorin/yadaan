import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/services.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:in_app_review/in_app_review.dart';
import 'package:timezone/data/latest.dart' as tz_data;

import 'questions_bagrut.dart';
import 'user_stats.dart';
import 'interests_service.dart';
import 'cloud_sync_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'config.dart';
import 'models/question.dart';
import 'services/analytics.dart';
import 'services/notification_service.dart';
import 'services/sfx.dart';
import 'services/purchase_service.dart';
import 'services/energy_service.dart';
import 'services/level_service.dart';
import 'services/mistakes_service.dart';
import 'services/icloud_kv.dart';

part 'bagrut_screen.dart';
part 'seasonal_service.dart';

// ═══════════════════════════════════════════════
//  GAME STATE
// ═══════════════════════════════════════════════
enum Phase{playing,complete,failed}
class GameState extends ChangeNotifier {
  final int levelIdx; final Diff diff;
  final bool isSeasonal;
  late final List<Question> _queue;
  late final int _originalTotal;
  int _answeredCorrect=0,_stars=Cfg.starsPerLevel,_wrong=0,_timer=Cfg.timerSecs;
  bool _waitingContinue=false;
  int? _sel; bool _fb=false; Phase _phase=Phase.playing; Timer? _t;
  final List<Question> _failedQs=[];
  List<Question> get failedQuestions=>List.from(_failedQs);
  GameState({required this.levelIdx,required this.diff,List<Question>? retryWith,this.isSeasonal=false}){
    if(retryWith==null) Analytics.levelStarted();
    if(retryWith!=null){
      // שאלות שנכשלו קודם + שאלות חדשות להשלמה לTotal
      final failedIds=retryWith.map((q)=>q.id).toSet();
      final fresh=QRepo.forLevel(levelIdx,diff).where((q)=>!failedIds.contains(q.id)).toList();
      final needed=(Cfg.questionsPerLevel-retryWith.length).clamp(0,Cfg.questionsPerLevel);
      _queue=[...retryWith,...fresh.take(needed)];
    } else {
      _queue=List<Question>.from(QRepo.forLevel(levelIdx,diff));
    }
    _originalTotal=_queue.length;
    _startTimer();
  }
  int get stars=>_stars; int? get sel=>_sel; bool get fb=>_fb;
  bool get waitingContinue=>_waitingContinue;
  Phase get phase=>_phase; int get timer=>_timer; Question get cur=>_queue[0];
  int get total=>_originalTotal;
  int get qi=>_answeredCorrect;
  double get prog=>_originalTotal==0?1.0:_answeredCorrect/_originalTotal;
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
    await EnergyService.instance.spend(Cfg.energyCostWrong);
    MistakesService.instance.add(cur);
    if(!_failedQs.contains(cur))_failedQs.add(cur);
    // KD + חולשות
    UserStatsService.instance.recordAnswer(correct: false, diffIndex: diff.index);
    InterestsService.instance.recordAnswer(category: cur.category, correct: false);
    _waitingContinue=true; notifyListeners();
  }
  void answer(int idx) async {
    if(_fb||_waitingContinue)return; _t?.cancel(); _sel=idx; _fb=true; notifyListeners();
    final ok=idx==cur.c;
    if(ok){
      await Sfx.correct();
      if(!isSeasonal) QRepo.markSeen(cur.id,diff); // שאלות עונתיות לא נסמנות כ"נראו"
      // KD + XP + streak
      await UserStatsService.instance.recordAnswer(correct: true, diffIndex: diff.index);
      // ביטול נוטיפיקציית רצף — המשתמש שיחק היום
      NotificationService.cancelStreakNotification();
      InterestsService.instance.recordAnswer(category: cur.category, correct: true);
      // level up event
      final lu = UserStatsService.instance.consumeLevelUp();
      if (lu != null) Analytics.playerLevelUp(newLevel: lu.label, xp: UserStatsService.instance.xp);
      // streak milestones
      final st = UserStatsService.instance.streak;
      if ([3,7,14,30,60,100].contains(st)) Analytics.streakMilestone(st);
      // KD milestones
      final kd = UserStatsService.instance.kd;
      if (kd >= 0.9 && UserStatsService.instance.total % 10 == 0) Analytics.kdMilestone('90%+');
      await Future.delayed(const Duration(milliseconds:900));
      _fb=false;_sel=null;
      _queue.removeAt(0); _answeredCorrect++;
      if(_queue.isEmpty){await _finish();return;}
      _startTimer(); notifyListeners();
    } else {
      await Sfx.wrong(); _wrong++; _stars=(Cfg.starsPerLevel-_wrong).clamp(0,3);
      await EnergyService.instance.spend(Cfg.energyCostWrong);
      MistakesService.instance.add(cur);
      if(!_failedQs.contains(cur))_failedQs.add(cur);
      // KD + חולשות
      UserStatsService.instance.recordAnswer(correct: false, diffIndex: diff.index);
      InterestsService.instance.recordAnswer(category: cur.category, correct: false);
      _waitingContinue=true; notifyListeners();
    }
  }
  void continueAfterFeedback() async {
    if(!_waitingContinue)return;
    _waitingContinue=false; _fb=false; _sel=null;
    if(_wrong>Cfg.maxWrongPerLevel){
      await Sfx.fail();
      await EnergyService.instance.spend(Cfg.energyCostFail);
      _phase=Phase.failed; notifyListeners(); return;
    }
    final q=_queue.removeAt(0); _queue.add(q);
    _startTimer(); notifyListeners();
  }
  Future<void> _finish() async {
    _t?.cancel();
    if(_stars==Cfg.starsPerLevel)await Sfx.perfect();
    await LevelService.instance.save(diff,levelIdx,_stars);
    ICloudKV.saveAll(); // גיבוי רקע ל-iCloud
    if (defaultTargetPlatform == TargetPlatform.android) CloudSyncService.instance.saveProgress();
    _phase=Phase.complete;
    notifyListeners();
  }
  void dispose(){_t?.cancel();}
}

// ═══════════════════════════════════════════════
//  PALETTE
// ═══════════════════════════════════════════════
// ─── Energy Overlay flag (נטען sync בפתיחה) ────────────────────────────────
class _EnergyOverlay {
  static bool seen = false;
  static Future<void> init() async {
    final p = await SharedPreferences.getInstance();
    seen = p.getBool('energy_overlay_seen') ?? false;
  }
  static void markSeen() {
    seen = true;
    SharedPreferences.getInstance().then((p) => p.setBool('energy_overlay_seen', true));
  }
}

// ═══════════════════════════════════════════════
//  MAIN
// ═══════════════════════════════════════════════
Future<void> _launchUrl(String url) async {
  final uri = Uri.parse(url);
  if (await canLaunchUrl(uri)) await launchUrl(uri, mode: LaunchMode.externalApplication);
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Wire up callbacks to break circular imports
  PurchaseService.setOnProActivated(() => EnergyService.instance.fillToMax());
  Analytics.setEnergyGetter(() => EnergyService.instance.energy);
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp,DeviceOrientation.portraitDown]);
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    systemNavigationBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarIconBrightness: Brightness.light,
  ));
  tz_data.initializeTimeZones();
  try { await Firebase.initializeApp(); await Analytics.init(); } catch(e) { debugPrint('Firebase init failed: $e'); }
  await NotificationService.init();
  await ICloudKV.restoreIfEmpty(); // שחזור מ-iCloud לפני טעינת שירותים (התקנה חדשה)
  await PurchaseService.init(); await LevelService.init(); await EnergyService.init(); await QRepo.loadSeen(); await MistakesService.init();
  await UserStatsService.init(); await InterestsService.init(); await BagrutService.init(); await _EnergyOverlay.init(); await Sfx.init();
  SeasonalService.init(); // ברקע — לא מחכים
  if (defaultTargetPlatform == TargetPlatform.android) await CloudSyncService.init();
  // כניסה יומית
  Analytics.dailyOpen(streak: UserStatsService.instance.streak);
  // נוטיפיקציה לרצף — תזמן ל-20:00 אם לא שיחקו היום, בטל אם כבר שיחקו
  if (UserStatsService.instance.playedToday) {
    NotificationService.cancelStreakNotification();
  } else {
    NotificationService.scheduleStreakReminder(UserStatsService.instance.streak);
  }
  ICloudKV.saveAll(); // גיבוי ראשוני ל-iCloud — עוזר למשתמשים שמעדכנים מגרסה ישנה
  // ─── AdMob אתחול ──────────────────────────────────────────────────────────
  if (Cfg.adMobEnabled && !kIsWeb) {
    await MobileAds.instance.initialize();
    AdPreloader.preload(); // טוען מודעה ברקע מיד עם עלייה
  }
  final _prefs = await SharedPreferences.getInstance();
  final showOnboarding = !(_prefs.getBool('onboarding_done') ?? false);
  runApp(App(showOnboarding: showOnboarding));
}
class App extends StatefulWidget {
  final bool showOnboarding;
  const App({super.key, required this.showOnboarding});
  @override State<App> createState()=>_AppState();
}
class _AppState extends State<App> with WidgetsBindingObserver {
  @override void initState(){super.initState();WidgetsBinding.instance.addObserver(this);}
  @override void dispose(){WidgetsBinding.instance.removeObserver(this);super.dispose();}
  @override void didChangeAppLifecycleState(AppLifecycleState s){
    if(s==AppLifecycleState.paused||s==AppLifecycleState.detached){
      Analytics.sessionEnded();
      if(EnergyService.instance.energy==0) Analytics.energyDepletedUserLeft();
    }
    if(s==AppLifecycleState.resumed){
      NotificationService.cancelEnergyNotification();
      EnergyService.instance.checkRecharge();
      // עדכן נוטיפיקציית רצף בכל חזרה לאפליקציה
      if(UserStatsService.instance.playedToday){
        NotificationService.cancelStreakNotification();
      } else {
        NotificationService.scheduleStreakReminder(UserStatsService.instance.streak);
      }
    }
  }
  @override Widget build(BuildContext context) {
    return ListenableBuilder(listenable:PurchaseService.instance,
      builder:(_,__)=>MaterialApp(title:'\u05D9\u05D3\u05E2\u05DF',debugShowCheckedModeBanner:false,
        theme:ThemeData.dark().copyWith(scaffoldBackgroundColor:Pal.bg,useMaterial3:true),
        routes: {'/home': (_) => const HomeScreen()},
        home:widget.showOnboarding ? const OnboardingScreen() : const HomeScreen()));
  }
}

// \u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550
//  ONBOARDING \u2014 \u05DE\u05E1\u05DA \u05D9\u05D7\u05D9\u05D3: \u05D4\u05E1\u05D1\u05E8 \u05DE\u05D5\u05D7\u05D5\u05EA
// \u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});
  @override State<OnboardingScreen> createState() => _OnboardingState();
}
class _OnboardingState extends State<OnboardingScreen> with SingleTickerProviderStateMixin {
  late final AnimationController _brainCtrl;
  late final Animation<double> _brainY;
  late final Animation<double> _brainOpacity;

  @override
  void initState() {
    super.initState();
    _brainCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));
    _brainY = Tween(begin: 0.0, end: -48.0).animate(CurvedAnimation(parent: _brainCtrl, curve: Curves.easeOut));
    _brainOpacity = Tween(begin: 1.0, end: 0.0).animate(CurvedAnimation(parent: _brainCtrl, curve: Curves.easeIn));
    // \u05DE\u05E8\u05D9\u05E5 \u05DC\u05D5\u05DC\u05D0\u05D4: \u05DE\u05D5\u05D7 \u05D9\u05D5\u05E8\u05D3 \u05D5\u05E2\u05D5\u05DC\u05D4 \u05DB\u05DC 2 \u05E9\u05E0\u05D9\u05D5\u05EA
    Future.delayed(const Duration(milliseconds: 600), _loop);
  }

  void _loop() {
    if (!mounted) return;
    _brainCtrl.forward(from: 0).then((_) {
      if (!mounted) return;
      Future.delayed(const Duration(milliseconds: 1400), _loop);
    });
  }

  Future<void> _done() async {
    final p = await SharedPreferences.getInstance();
    await p.setBool('onboarding_done', true);
    if (mounted) Navigator.pushReplacement(context, _slide(const HomeScreen()));
  }

  @override void dispose() { _brainCtrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: Pal.bg,
        body: Stack(children: [
          const StarField(),
          SafeArea(child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(children: [
              const Spacer(),
              // \u05D0\u05E0\u05D9\u05DE\u05E6\u05D9\u05D9\u05EA \u05DE\u05D5\u05D7 \u05D9\u05D5\u05E8\u05D3
              SizedBox(height: 120, child: Stack(alignment: Alignment.center, children: [
                // \u05E9\u05D5\u05E8\u05EA \u05DE\u05D5\u05D7\u05D5\u05EA
                Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  for (int i = 0; i < 5; i++) ...[
                    Text('\uD83E\uDDE0', style: TextStyle(fontSize: 32, color: i < 4 ? null : Colors.white.withOpacity(0.2))),
                    if (i < 4) const SizedBox(width: 6),
                  ],
                ]),
                // \u05DE\u05D5\u05D7 \u05E9\u05D9\u05D5\u05E8\u05D3 (\u05D0\u05E0\u05D9\u05DE\u05E6\u05D9\u05D4)
                AnimatedBuilder(
                  animation: _brainCtrl,
                  builder: (_, __) => Positioned(
                    top: 10 - _brainY.value,
                    right: 16,
                    child: Opacity(
                      opacity: _brainOpacity.value,
                      child: const Text('\u22121\uD83E\uDDE0', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: Pal.red)),
                    ),
                  ),
                ),
              ])),
              const SizedBox(height: 32),
              // \u05DB\u05D5\u05EA\u05E8\u05EA
              const Text('\u05DB\u05DE\u05D4 \u05D0\u05EA\u05D4 \u05D7\u05DB\u05DD \u05D1\u05D9\u05D7\u05E1 \u05DC\u05D0\u05D5\u05DB\u05DC\u05D5\u05E1\u05D9\u05D4?', textAlign: TextAlign.center,
                style: TextStyle(color: Pal.tp, fontSize: 24, fontWeight: FontWeight.w900, height: 1.3)),
              const SizedBox(height: 16),
              // \u05D4\u05E1\u05D1\u05E8
              RichText(
                textAlign: TextAlign.center,
                text: TextSpan(
                  style: const TextStyle(color: Pal.ts, fontSize: 16, height: 1.8),
                  children: [
                    const TextSpan(text: '\u05E2\u05DC \u05DB\u05DC '),
                    const TextSpan(text: '\u05EA\u05E9\u05D5\u05D1\u05D4 \u05E9\u05D2\u05D5\u05D9\u05D4', style: TextStyle(color: Pal.red, fontWeight: FontWeight.w800)),
                    const TextSpan(text: ' \u05D9\u05D5\u05E8\u05D3 \u05DE\u05D5\u05D7 \u05D0\u05D7\u05D3\n'),
                    const TextSpan(text: '\u05E0\u05D2\u05DE\u05E8\u05D5 \u05D4\u05DE\u05D5\u05D7\u05D5\u05EA? \u05DE\u05DE\u05EA\u05D9\u05E0\u05D9\u05DD \u05E9\u05D9\u05EA\u05D7\u05D3\u05E9\u05D5\n\n'),
                    const TextSpan(text: '\u05DE\u05D5\u05D7 \u05D0\u05D7\u05D3 \u05DE\u05EA\u05D7\u05D3\u05E9 \u05DB\u05DC '),
                    TextSpan(text: '${Cfg.energyRechargeMins} \u05D3\u05E7\u05D5\u05EA', style: const TextStyle(color: Pal.gold, fontWeight: FontWeight.w800)),
                    const TextSpan(text: ' \u2014 \u05D0\u05D5\u05D8\u05D5\u05DE\u05D8\u05D9\u05EA'),
                  ],
                ),
              ),
              const Spacer(),
              // \u05DB\u05E4\u05EA\u05D5\u05E8 \u05D4\u05EA\u05D7\u05DC
              GestureDetector(
                onTap: _done,
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(colors: [Color(0xFF4D96FF), Color(0xFF2E5FCC)]),
                    borderRadius: BorderRadius.circular(18),
                    boxShadow: [BoxShadow(color: const Color(0xFF4D96FF).withOpacity(0.4), blurRadius: 16, offset: const Offset(0, 4))],
                  ),
                  child: const Text('\u05D1\u05D5\u05D0\u05D5 \u05E0\u05E9\u05D7\u05E7! \uD83D\uDE80', textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w900)),
                ),
              ),
              const SizedBox(height: 36),
            ]),
          )),
        ]),
      ),
    );
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
          onTap: () {
            if (e.canWatchAd) {
              _showAdDialog(context);
            } else if (!e.has && !PurchaseService.instance.isPremium) {
              Navigator.push(context, _slide(const NoEnergyScreen()));
            }
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: Pal.card, borderRadius: BorderRadius.circular(20),
              border: Border.all(color: c.withOpacity(0.6), width: 1.5)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Text('\u{1F9E0}', style: TextStyle(fontSize: 14, color: c)),
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
//  AD PRELOADER — טוען מודעה מראש ברקע
// ═══════════════════════════════════════════════
class AdPreloader {
  static RewardedAd? _ad;
  static bool _loading = false;
  static bool get isReady => _ad != null;
  static void preload() {
    if (_loading || _ad != null || !Cfg.adMobEnabled || kIsWeb) return;
    _loading = true;
    RewardedAd.load(
      adUnitId: Cfg.adRewardedUnitId,
      request: const AdRequest(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded:       (ad) { _ad = ad; _loading = false; },
        onAdFailedToLoad: (_)  { _loading = false; },
      ),
    );
  }
  static RewardedAd? consume() { final ad=_ad; _ad=null; preload(); return ad; }
}

// ═══════════════════════════════════════════════
//  AD REWARD DIALOG — Rewarded (30 שניות) → +2 מוחות
// ═══════════════════════════════════════════════
class _AdRewardDialog extends StatefulWidget {
  @override State<_AdRewardDialog> createState() => _AdRewardDialogState();
}
class _AdRewardDialogState extends State<_AdRewardDialog>
    with SingleTickerProviderStateMixin {
  bool _loading = false;
  bool _done    = false;
  late final AnimationController _anim;
  RewardedAd? _rewardedAd;

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(vsync: this, duration: const Duration(milliseconds: 600));
    _rewardedAd = AdPreloader.consume(); // מיידי אם נטען מראש
    if (_rewardedAd == null) {
      // fallback — טעינה מחדש אם ה-preloader לא היה מוכן
      _loading = true;
      RewardedAd.load(
        adUnitId: Cfg.adRewardedUnitId,
        request: const AdRequest(),
        rewardedAdLoadCallback: RewardedAdLoadCallback(
          onAdLoaded:       (ad) { _rewardedAd = ad; if (mounted) setState(() => _loading = false); },
          onAdFailedToLoad: (_)  {                    if (mounted) setState(() => _loading = false); },
        ),
      );
    }
  }

  void _showAd() {
    final ad = _rewardedAd;
    if (ad == null) return;
    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent:    (a) { a.dispose(); _rewardedAd = null; },
      onAdFailedToShowFullScreenContent: (a, _) { a.dispose(); _rewardedAd = null; },
    );
    ad.show(onUserEarnedReward: (_, __) => _onComplete());
  }

  Future<void> _onComplete() async {
    await EnergyService.instance.rewardFromAd(amount: Cfg.adRewardedEnergy);
    Analytics.adWatchedForEnergy(amount: Cfg.adRewardedEnergy);
    if (!mounted) return;
    setState(() => _done = true);
    _anim.forward();
    await HapticFeedback.lightImpact();
    await Future.delayed(const Duration(milliseconds: 150));
    if (mounted) await HapticFeedback.lightImpact();
    Future.delayed(const Duration(milliseconds: 1500), () {
      if (mounted) Navigator.pop(context);
    });
  }

  @override void dispose() { _rewardedAd?.dispose(); _anim.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    if (_done) return Dialog(
      backgroundColor: Pal.card,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Padding(padding: const EdgeInsets.all(32), child: Column(mainAxisSize: MainAxisSize.min, children: [
        ScaleTransition(scale: CurvedAnimation(parent: _anim, curve: Curves.easeOutBack),
          child: const Text('🧠', style: TextStyle(fontSize: 72))),
        const SizedBox(height: 14),
        FadeTransition(opacity: _anim,
          child: const Text('+2 מוחות!',
            style: TextStyle(color: Pal.gold, fontSize: 24, fontWeight: FontWeight.w900))),
      ])),
    );
    return Dialog(
      backgroundColor: Pal.card,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Padding(padding: const EdgeInsets.all(24), child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Text('🎬', style: TextStyle(fontSize: 48)),
        const SizedBox(height: 10),
        const Text('קבל 2 מוחות', style: TextStyle(color: Pal.tp, fontSize: 22, fontWeight: FontWeight.w800)),
        const SizedBox(height: 4),
        const Text('צפה בסרטון קצר', style: TextStyle(color: Pal.ts, fontSize: 13)),
        const SizedBox(height: 22),
        _AdButton(
          loading: _loading, available: _rewardedAd != null,
          emoji: '🎬', title: 'סרטון מלא', reward: '+2 🧠',
          subtitle: 'לא ניתן לדלג · ~30 שניות',
          color: Pal.gold, onTap: _showAd,
        ),
        const SizedBox(height: 14),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('לא תודה', style: TextStyle(color: Pal.ts))),
      ])),
    );
  }
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
//  USER STATS STRIP (HomeScreen widget)
// ═══════════════════════════════════════════════
class _UserStatsStrip extends StatelessWidget {
  @override Widget build(BuildContext context) {
    final us = UserStatsService.instance;
    final lvl = us.level;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: Row(children: [
        // ─── Streak ─── (בולט יותר)
        _StreakPill(streak: us.streak),
        const SizedBox(width: 8),
        // ─── KD ───
        _StatPill(
          emoji: '🎯',
          label: us.kdDisplay,
          sublabel: 'דיוק',
          color: const Color(0xFF4D96FF),
        ),
        const SizedBox(width: 8),
        // ─── Level + progress bar ───
        Expanded(child: GestureDetector(
          onTap: () => Navigator.push(context, _slide(const ProfileScreen())),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: lvl.color.withOpacity(0.12),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: lvl.color.withOpacity(0.35)),
            ),
            child: Row(children: [
              Text(lvl.emoji, style: const TextStyle(fontSize: 16)),
              const SizedBox(width: 6),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Text(lvl.label,
                    style: TextStyle(color: lvl.color, fontSize: 11, fontWeight: FontWeight.w800)),
                  const Spacer(),
                  Text('${us.xp} XP',
                    style: const TextStyle(color: Color(0xFF78909C), fontSize: 10)),
                ]),
                const SizedBox(height: 3),
                ClipRRect(borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: us.levelProgress,
                    backgroundColor: Colors.white.withOpacity(0.1),
                    valueColor: AlwaysStoppedAnimation(lvl.color),
                    minHeight: 4,
                  )),
              ])),
            ]),
          ),
        )),
      ]),
    );
  }
}

// Streak pill — בולט יותר עם אפקט זוהר כשיש רצף
class _StreakPill extends StatelessWidget {
  final int streak;
  const _StreakPill({required this.streak});
  @override Widget build(BuildContext context) {
    const color = Color(0xFFFF6B35);
    final hasStreak = streak > 0;
    final bigStreak = streak >= 7;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: color.withOpacity(hasStreak ? 0.18 : 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: color.withOpacity(hasStreak ? 0.7 : 0.25),
          width: hasStreak ? 1.5 : 1.0,
        ),
        boxShadow: bigStreak ? [
          BoxShadow(color: color.withOpacity(0.4), blurRadius: 14, spreadRadius: 1),
        ] : hasStreak ? [
          BoxShadow(color: color.withOpacity(0.2), blurRadius: 8),
        ] : null,
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text(bigStreak ? '🔥' : '🔥',
          style: TextStyle(fontSize: bigStreak ? 22 : 18)),
        const SizedBox(height: 2),
        Text('$streak',
          style: TextStyle(
            color: color,
            fontSize: bigStreak ? 22 : 20,
            fontWeight: FontWeight.w900,
            height: 1.0,
          )),
        const Text('רצף', style: TextStyle(color: Color(0xFF78909C), fontSize: 9)),
      ]),
    );
  }
}

class _StatPill extends StatelessWidget {
  final String emoji, label, sublabel;
  final Color color;
  const _StatPill({required this.emoji, required this.label, required this.sublabel, required this.color});
  @override Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      color: color.withOpacity(0.12),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: color.withOpacity(0.35)),
    ),
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      Text(emoji, style: const TextStyle(fontSize: 14)),
      const SizedBox(height: 1),
      Text(label, style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.w900)),
      Text(sublabel, style: const TextStyle(color: Color(0xFF78909C), fontSize: 9)),
    ]),
  );
}

// ═══════════════════════════════════════════════
//  PROFILE SCREEN
// ═══════════════════════════════════════════════
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});
  @override State<ProfileScreen> createState() => _ProfileScreenState();
}
class _ProfileScreenState extends State<ProfileScreen> {
  @override void initState() {
    super.initState();
    Analytics.profileOpened();
  }

  void _openInterests() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _InterestBottomSheet(),
    );
  }

  @override Widget build(BuildContext context) {
    final us  = UserStatsService.instance;
    final interests = InterestsService.instance;
    final lvl = us.level;
    return Scaffold(
      backgroundColor: const Color(0xFF0D1B3E),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: Colors.white),
          onPressed: () => Navigator.pop(context)),
        title: const Text('הגדרות',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900)),
        actions: [
          IconButton(
            icon: const Icon(Icons.tune, color: Color(0xFFFFD700)),
            tooltip: 'קטגוריות מועדפות',
            onPressed: _openInterests),
          IconButton(
            icon: const Icon(Icons.close, color: Pal.ts),
            onPressed: () => Navigator.push(context, _slide(const MistakesScreen()))),
        ],
      ),
      body: ListenableBuilder(
        listenable: Listenable.merge([us, InterestsService.instance, Sfx.mutedNotifier]),
        builder: (_, __) {
          return SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(children: [
              // ─── Level Card ───────────────────────────
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [lvl.color.withOpacity(0.25), lvl.color.withOpacity(0.05)],
                    begin: Alignment.topLeft, end: Alignment.bottomRight),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: lvl.color.withOpacity(0.5))),
                child: Column(children: [
                  Text(lvl.emoji, style: const TextStyle(fontSize: 52)),
                  const SizedBox(height: 8),
                  Text(lvl.titleLabel,
                    style: TextStyle(color: lvl.color, fontSize: 24, fontWeight: FontWeight.w900)),
                  const SizedBox(height: 4),
                  Text('${us.xp} נקודות ניסיון',
                    style: const TextStyle(color: Color(0xFFB0BEC5), fontSize: 14)),
                  const SizedBox(height: 16),
                  if (lvl != PlayerLevel.legend) ...[
                    Row(children: [
                      Text('${us.xpInLevel}',
                        style: TextStyle(color: lvl.color, fontSize: 13, fontWeight: FontWeight.w700)),
                      const Spacer(),
                      Text('${us.xpForLevel} נקודות',
                        style: const TextStyle(color: Color(0xFF78909C), fontSize: 12)),
                    ]),
                    const SizedBox(height: 6),
                    ClipRRect(borderRadius: BorderRadius.circular(8),
                      child: LinearProgressIndicator(
                        value: us.levelProgress,
                        backgroundColor: Colors.white.withOpacity(0.1),
                        valueColor: AlwaysStoppedAnimation(lvl.color),
                        minHeight: 10,
                      )),
                    const SizedBox(height: 6),
                    Text('עוד ${us.xpForLevel - us.xpInLevel} נקודות לרמת ${PlayerLevel.values[lvl.index + 1].label}',
                      style: const TextStyle(color: Color(0xFF78909C), fontSize: 12)),
                  ],
                ])),
              const SizedBox(height: 16),
              // ─── Stats Grid ───────────────────────────
              Row(children: [
                _StatBox(title: 'דיוק תשובות', value: us.kdDisplay, emoji: '🎯',
                  sub: us.kdRatio, color: const Color(0xFF4D96FF)),
                const SizedBox(width: 12),
                _StatBox(title: 'רצף', emoji: '🔥', color: const Color(0xFFFF6B35),
                  value: us.streak == 1 ? 'יום אחד' : '${us.streak}',
                  sub:   us.streak == 1 ? 'רצוף' : 'ימים רצופים'),
              ]),
              const SizedBox(height: 12),
              Row(children: [
                _StatBox(title: 'תשובות נכונות', value: '${us.correct}', emoji: '✅',
                  sub: 'מתוך ${us.total}', color: const Color(0xFF2ECC71)),
                const SizedBox(width: 12),
                _StatBox(title: 'שיא רצף', emoji: '🏆', color: const Color(0xFFFFD700),
                  value: us.bestStreak == 1 ? 'יום אחד' : '${us.bestStreak}',
                  sub:   us.bestStreak == 1 ? 'רצוף' : 'ימים'),
              ]),
              const SizedBox(height: 20),
              // ─── Interests ────────────────────────────
              GestureDetector(
                onTap: _openInterests,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1A2A4A),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFFFFD700).withOpacity(0.25))),
                  child: Row(children: [
                    const Text('⭐', style: TextStyle(fontSize: 16)),
                    const SizedBox(width: 8),
                    const Text('תחומי העניין שלך',
                      style: TextStyle(color: Color(0xFFFFD700), fontSize: 14, fontWeight: FontWeight.w800)),
                    const Spacer(),
                    const Icon(Icons.edit_outlined, color: Color(0xFF546E7A), size: 16),
                  ]),
                )),
              const SizedBox(height: 10),
              if (interests.hasInterests)
                Wrap(spacing: 8, runSpacing: 8, children: interests.selected.map((key) {
                  final cat = InterestCat.forKey(key);
                  if (cat == null) return const SizedBox.shrink();
                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: cat.color.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: cat.color.withOpacity(0.5))),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Text(cat.emoji, style: const TextStyle(fontSize: 14)),
                      const SizedBox(width: 6),
                      Text(cat.label, style: TextStyle(color: cat.color, fontSize: 13, fontWeight: FontWeight.w700)),
                    ]));
                }).toList())
              else
                GestureDetector(
                  onTap: _openInterests,
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0D1728),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFF2A3A55))),
                    child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Text('+ הוסף תחומי עניין',
                        style: TextStyle(color: Color(0xFF78909C), fontSize: 13)),
                    ]))),
              const SizedBox(height: 16),
              // ─── Weaknesses ───────────────────────────
              if (interests.weaknesses.isNotEmpty) ...[
                Align(alignment: Alignment.centerRight,
                  child: const Text('📈 תחומים לשיפור',
                    style: TextStyle(color: Color(0xFFFF7043), fontSize: 15, fontWeight: FontWeight.w800))),
                const SizedBox(height: 10),
                Wrap(spacing: 8, runSpacing: 8, children: interests.weaknesses.map((key) {
                  final cat = InterestCat.forKey(key);
                  if (cat == null) return const SizedBox.shrink();
                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFF7043).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: const Color(0xFFFF7043).withOpacity(0.4))),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Text(cat.emoji, style: const TextStyle(fontSize: 14)),
                      const SizedBox(width: 6),
                      Text(cat.label,
                        style: const TextStyle(color: Color(0xFFFF7043), fontSize: 13, fontWeight: FontWeight.w700)),
                    ]));
                }).toList()),
              ],
              const SizedBox(height: 24),
              // ─── הגדרות נוספות ─────────────────────────
              const Align(alignment: Alignment.centerRight,
                child: Text('⚙️  כלים נוספים',
                  style: TextStyle(color: Pal.ts, fontSize: 13, fontWeight: FontWeight.w700))),
              const SizedBox(height: 10),
              _SfxToggleRow(),
              const SizedBox(height: 8),
              _SettingsRow(icon: Icons.close, color: Pal.red, label: 'שגיאות אחרונות',
                onTap: () => Navigator.push(context, _slide(const MistakesScreen()))),
              const SizedBox(height: 8),
              if (defaultTargetPlatform == TargetPlatform.android)
                _SettingsRow(icon: Icons.cloud_upload_outlined, color: const Color(0xFF4D96FF),
                  label: CloudSyncService.instance.isSignedIn ? 'סנכרון ענן — מחובר' : 'שמור התקדמות בענן',
                  onTap: () {}),
              if (defaultTargetPlatform == TargetPlatform.android)
                const SizedBox(height: 8),
              _SettingsRow(icon: Icons.tune, color: Pal.gold, label: 'קטגוריות מועדפות',
                onTap: _openInterests),
              const SizedBox(height: 8),
              _SettingsRow(icon: Icons.star_outline_rounded, color: const Color(0xFFFFD700), label: 'דרג אותנו ⭐',
                onTap: () async {
                  final review = InAppReview.instance;
                  if (await review.isAvailable()) await review.requestReview();
                  else await review.openStoreListing();
                }),
              const SizedBox(height: 24),
            ]));
        },
      ),
    );
  }
}

class _SettingsRow extends StatelessWidget {
  final IconData icon; final Color color; final String label; final VoidCallback onTap;
  const _SettingsRow({required this.icon, required this.color, required this.label, required this.onTap});
  @override Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: const Color(0xFF112054),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withOpacity(0.06))),
      child: Row(children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(width: 12),
        Expanded(child: Text(label, style: const TextStyle(color: Pal.tp, fontSize: 14, fontWeight: FontWeight.w600))),
        const Icon(Icons.arrow_back_ios_new_rounded, color: Pal.ts, size: 13),
      ])));
}

class _SfxToggleRow extends StatelessWidget {
  @override Widget build(BuildContext context) {
    final muted = Sfx.muted;
    return GestureDetector(
      onTap: () => Sfx.setMuted(!muted),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: const Color(0xFF112054),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withOpacity(0.06))),
        child: Row(children: [
          Icon(muted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
            color: muted ? Pal.ts : Pal.accent, size: 20),
          const SizedBox(width: 12),
          Expanded(child: Text(muted ? 'צלילים — מושתק' : 'צלילים — פעיל',
            style: const TextStyle(color: Pal.tp, fontSize: 14, fontWeight: FontWeight.w600))),
          Switch(
            value: !muted,
            onChanged: (v) => Sfx.setMuted(!v),
            activeColor: Pal.accent,
            activeTrackColor: Pal.accent.withOpacity(0.3),
            inactiveThumbColor: Pal.ts,
            inactiveTrackColor: Colors.white.withOpacity(0.1),
          ),
        ])));
  }
}

class _StatBox extends StatelessWidget {
  final String title, value, emoji, sub;
  final Color color;
  const _StatBox({required this.title, required this.value, required this.emoji, required this.sub, required this.color});
  @override Widget build(BuildContext context) => Expanded(
    child: Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.25))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text(emoji, style: const TextStyle(fontSize: 18)),
          const SizedBox(width: 6),
          Flexible(child: Text(title,
            style: const TextStyle(color: Color(0xFF90A4AE), fontSize: 11, fontWeight: FontWeight.w600))),
        ]),
        const SizedBox(height: 8),
        Text(value, style: TextStyle(color: color, fontSize: 26, fontWeight: FontWeight.w900)),
        Text(sub, style: const TextStyle(color: Color(0xFF78909C), fontSize: 11)),
      ]),
    ),
  );
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
  // ─── secret logo tap ─────────────────────────────────────────────────────
  int _logoTaps = 0;
  Timer? _tapReset;

  void _onLogoTap() {
    _tapReset?.cancel();
    _logoTaps++;
    if (_logoTaps >= 7) {
      _logoTaps = 0;
      _showSecretDialog();
    } else {
      _tapReset = Timer(const Duration(seconds: 3), () => _logoTaps = 0);
    }
  }

  void _showSecretDialog() {
    final ctrl = TextEditingController();
    showDialog(context: context, builder: (_) => AlertDialog(
      backgroundColor: const Color(0xFF0F2044),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Text('🔐', textAlign: TextAlign.center, style: TextStyle(fontSize: 32)),
      content: TextField(
        controller: ctrl,
        obscureText: true,
        textAlign: TextAlign.center,
        style: const TextStyle(color: Colors.white, letterSpacing: 4),
        decoration: InputDecoration(
          hintText: 'קוד גישה',
          hintStyle: const TextStyle(color: Color(0xFF7A90C0)),
          filled: true, fillColor: const Color(0xFF152856),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none)),
        onSubmitted: (_) => _tryCode(ctrl.text),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('ביטול', style: TextStyle(color: Color(0xFF7A90C0)))),
        ElevatedButton(
          onPressed: () => _tryCode(ctrl.text),
          style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFFD700), foregroundColor: Colors.black),
          child: const Text('אישור', style: TextStyle(fontWeight: FontWeight.w800))),
      ],
    ));
  }

  void _tryCode(String code) {
    Navigator.pop(context);
    if (code == Cfg.devCode) {
      BagrutService.instance.unlockDev();
      PurchaseService.instance.tryDev(code);
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('✅ גישה הופעלה'), backgroundColor: Color(0xFF2ECC71)));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('קוד שגוי'), backgroundColor: Color(0xFFE74C3C)));
    }
  }

  @override void initState(){
    super.initState(); _bg=AnimationController(vsync:this,duration:const Duration(seconds:8))..repeat(reverse:true);
    LevelService.instance.addListener((){if(mounted)setState((){});});
    PurchaseService.instance.addListener((){if(mounted)setState((){});});
    UserStatsService.instance.addListener((){if(mounted)setState((){});});
    SeasonalService.instance.addListener((){if(mounted)setState((){});});
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkInterestAnnouncement());
  }

  Future<void> _checkInterestAnnouncement() async {
    final p = await SharedPreferences.getInstance();
    final seen = p.getBool('interests_feature_seen') ?? false;
    if (seen || !mounted) return;
    await p.setBool('interests_feature_seen', true);
    // הצג רק למשתמשים שכבר שיחקו (יש להם כוכבים או שלבים)
    if (LevelService.instance.allStars == 0) return;
    await Navigator.push(context, MaterialPageRoute(
      builder: (_) => const InterestsFeatureAnnouncementScreen()));
  }
  @override void dispose(){_bg.dispose();_tapReset?.cancel();super.dispose();}
  bool _catsExpanded = false;

  @override Widget build(BuildContext context){
    return Scaffold(body:Stack(children:[
      AnimatedBuilder(animation:_bg,builder:(_,__)=>Container(decoration:BoxDecoration(gradient:LinearGradient(
        begin:Alignment.topCenter,end:Alignment.bottomCenter,
        colors:[Color.lerp(const Color(0xFF0D1B3E),const Color(0xFF1A0D3E),_bg.value)!,Pal.bgD])))),
      const StarField(),
      SafeArea(child:Column(children:[
        // על בר (מינימלי) ─────────────────────────────────────────────
        Padding(padding:const EdgeInsets.fromLTRB(20,16,20,0),
          child:Row(children:[
            GestureDetector(
              onTap:_onLogoTap,
              child:ShaderMask(shaderCallback:(b)=>const LinearGradient(colors:[Pal.gold,Color(0xFFFF9F0A)]).createShader(b),
                child:const Text('ידען',style:TextStyle(fontSize:36,fontWeight:FontWeight.w900,color:Colors.white,letterSpacing:3)))),
            const Spacer(),
            GestureDetector(
              onTap:()=>Navigator.push(context,_slide(const ProfileScreen())),
              child:Container(
                padding:const EdgeInsets.all(8),
                decoration:BoxDecoration(color:Pal.card.withOpacity(0.6),borderRadius:BorderRadius.circular(10),
                  border:Border.all(color:Colors.white.withOpacity(0.08))),
                child:const Icon(Icons.settings_outlined,color:Pal.ts,size:20))),
            const SizedBox(width:10),
            const EnergyChip(),
          ])),
        const SizedBox(height:14),
        // ── Stars bar ────────────────────────────────────────────────────────────────────
        Padding(padding:const EdgeInsets.symmetric(horizontal:20),child:_StarsBar()),
        const SizedBox(height:20),
        // ── Content ──────────────────────────────────────────────────────────────────────────
        Expanded(child:SingleChildScrollView(padding:const EdgeInsets.symmetric(horizontal:20),child:Column(children:[
          // ── אירועים עונתיים (חם עכשיו) ─────────────────────────────────────
          ...SeasonalService.instance.activeEvents.map((event) => Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _SeasonalBanner(event: event),
          )),
          _DiffCard(diff:Diff.easy),
          const SizedBox(height:12),
          _DiffCard(diff:Diff.medium),
          const SizedBox(height:12),
          _DiffCard(diff:Diff.hard),
          const SizedBox(height:20),
          // ── קטגוריות (collapsible) ────────────────────────────────────────────────────────────
          GestureDetector(
            onTap:()=>setState(()=>_catsExpanded=!_catsExpanded),
            child:Container(
              padding:const EdgeInsets.symmetric(horizontal:16,vertical:14),
              decoration:BoxDecoration(
                color:Pal.card,borderRadius:BorderRadius.circular(16),
                border:Border.all(color:Pal.gold.withOpacity(0.3))),
              child:Row(children:[
                const Text('🎯',style:TextStyle(fontSize:20)),
                const SizedBox(width:10),
                const Expanded(child:Text('קטגוריות',style:TextStyle(color:Pal.tp,fontSize:16,fontWeight:FontWeight.w800))),
                AnimatedRotation(
                  turns:_catsExpanded?0.5:0,
                  duration:const Duration(milliseconds:200),
                  child:const Icon(Icons.keyboard_arrow_down_rounded,color:Pal.gold)),
              ]))),
          AnimatedCrossFade(
            duration:const Duration(milliseconds:250),
            crossFadeState:_catsExpanded?CrossFadeState.showSecond:CrossFadeState.showFirst,
            firstChild:const SizedBox.shrink(),
            secondChild:Column(children:[
              const SizedBox(height:10),
              ..._HomeCats.allCats.map((cat){
                final (key,name,emoji,color)=cat;
                return Padding(padding:const EdgeInsets.only(bottom:8),
                  child:GestureDetector(
                    onTap:()=>_showCatDiffPicker(context,key,name,emoji,color),
                    child:Container(
                      padding:const EdgeInsets.symmetric(horizontal:14,vertical:12),
                      decoration:BoxDecoration(
                        gradient:LinearGradient(begin:Alignment.centerRight,end:Alignment.centerLeft,
                          colors:[color.withOpacity(0.15),color.withOpacity(0.04)]),
                        borderRadius:BorderRadius.circular(12),
                        border:Border.all(color:color.withOpacity(0.35))),
                      child:Row(children:[
                        Text(emoji,style:const TextStyle(fontSize:22)),
                        const SizedBox(width:12),
                        Expanded(child:Text(name,style:const TextStyle(color:Pal.tp,fontSize:14,fontWeight:FontWeight.w700))),
                        Icon(Icons.arrow_back_ios_new_rounded,color:color,size:13),
                      ]))));
              }).toList(),
            ])),
          const SizedBox(height:16),
          // ── בגרות בהיסטוריה ────────────────────────────────────────────────────────────────────────
          _BagrutHomeCard(anim:_bg),
          const SizedBox(height:16),
          // ── פרו ────────────────────────────────────────────────────────────────────────────────────
          if(!PurchaseService.instance.isPremium)
            ListenableBuilder(listenable:PurchaseService.instance,builder:(_,__)=>
              GestureDetector(
                onTap:()=>showModalBottomSheet(context:context,isScrollControlled:true,backgroundColor:Colors.transparent,builder:(_)=>const PaywallSheet()),
                child:Container(
                  width:double.infinity,padding:const EdgeInsets.symmetric(vertical:16),
                  decoration:BoxDecoration(
                    gradient:const LinearGradient(colors:[Color(0xFFFF9F0A),Color(0xFFFF6B00)]),
                    borderRadius:BorderRadius.circular(16),
                    boxShadow:[BoxShadow(color:Pal.premium.withOpacity(0.35),blurRadius:12,offset:const Offset(0,4))]),
                  child:const Column(children:[
                    Text('👑  ידען פרו',style:TextStyle(color:Colors.white,fontSize:16,fontWeight:FontWeight.w900)),
                    SizedBox(height:3),
                    Text('ללא פרסומות · בגרות · שלבים קשים',textDirection:TextDirection.rtl,
                      style:TextStyle(color:Colors.white70,fontSize:12)),
                  ])))),
          const SizedBox(height:28),
        ]))),
      ])),
    ]));
  }
}

// ── כרטיס בגרות בדף הבית ──────────────────────────────────────────────────────────────────────
class _BagrutHomeCard extends StatelessWidget {
  final AnimationController anim;
  const _BagrutHomeCard({required this.anim});

  void _open(BuildContext ctx) {
    final allowed = PurchaseService.instance.isPremium || BagrutService.instance.devUnlocked;
    if (!allowed) { Navigator.push(ctx,MaterialPageRoute(builder:(_)=>const BagrutPaywallScreen())); return; }
    final svc = BagrutService.instance;
    Navigator.push(ctx,MaterialPageRoute(builder:(_)=>svc.isConfigured?const BagrutMainScreen():const BagrutTrackSelectionScreen()));
  }

  @override
  Widget build(BuildContext ctx) => AnimatedBuilder(
    animation:anim,
    builder:(_,__){
      final glow = 0.15 + anim.value * 0.2;
      return GestureDetector(
        onTap:()=>_open(ctx),
        child:Container(
          padding:const EdgeInsets.symmetric(horizontal:16,vertical:14),
          decoration:BoxDecoration(
            color:const Color(0xFF0F2044),
            borderRadius:BorderRadius.circular(16),
            border:Border.all(color:Pal.gold.withOpacity(glow+0.15),width:1.2),
            boxShadow:[BoxShadow(color:Pal.gold.withOpacity(glow*0.25),blurRadius:12)]),
          child:Row(children:[
            Container(width:42,height:42,
              decoration:BoxDecoration(
                gradient:const LinearGradient(colors:[Pal.gold,Color(0xFFFF9500)]),
                borderRadius:BorderRadius.circular(11)),
              child:const Center(child:Text('📜',style:TextStyle(fontSize:22)))),
            const SizedBox(width:12),
            Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
              Row(children:[
                const Text('בגרות בהיסטוריה',style:TextStyle(color:Pal.tp,fontSize:15,fontWeight:FontWeight.w800)),
                const SizedBox(width:8),
                Container(
                  padding:const EdgeInsets.symmetric(horizontal:6,vertical:2),
                  decoration:BoxDecoration(color:Pal.gold,borderRadius:BorderRadius.circular(5)),
                  child:const Text('חדש',style:TextStyle(color:Colors.black,fontSize:9,fontWeight:FontWeight.w900))),
              ]),
            ])),
            const Icon(Icons.arrow_back_ios_new_rounded,color:Pal.ts,size:13),
          ]),
        ),
      );
    });
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
                    builder:(_)=>const PaywallSheet());
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
                  Icon(locked?Icons.lock:Icons.arrow_forward_ios,color:d.color,size:14),
                ]))));
        }).toList(),
        const SizedBox(height:8),
      ])));
}

class _HomeCats {
  static const cats = [
    ('football','כדורגל ישראלי','🏟️',Color(0xFF27AE60)),
    ('israel','ישראל','🇮🇱',Color(0xFF4D96FF)),
    ('judaism','יהדות','✡️',Color(0xFF7C6FE0)),
    ('tv','טלוויזיה','📺',Color(0xFF9B59B6)),
    ('music','מוזיקה','🎵',Color(0xFFE91E8C)),
    ('sports','ספורט','⚽',Color(0xFFE74C3C)),
    ('geography','גיאוגרפיה','🌍',Color(0xFF2ECC71)),
    ('science','מדע','🔬',Color(0xFF3498DB)),
    ('world','תרבות עולמית','🎬',Color(0xFFE67E22)),
  ];
  // american_music זמין רק דרך חידון קטגוריות
  static const allCats = [
    ...cats,
    ('american_music','מוזיקה אמריקאית','🎸',Color(0xFFD35400)),
  ];
}

// ─── Bagrut teaser banner ────────────────────────────────────────────────────
class _BagrutTeaser extends StatelessWidget {
  final AnimationController anim;
  const _BagrutTeaser({required this.anim});

  void _open(BuildContext ctx) {
    final allowed = PurchaseService.instance.isPremium || BagrutService.instance.devUnlocked;
    if (!allowed) { Navigator.push(ctx, MaterialPageRoute(builder:(_)=>const BagrutPaywallScreen())); return; }
    final svc = BagrutService.instance;
    Navigator.push(ctx, MaterialPageRoute(builder:(_)=>svc.isConfigured ? const BagrutMainScreen() : const BagrutTrackSelectionScreen()));
  }

  @override
  Widget build(BuildContext ctx) => AnimatedBuilder(
    animation: anim,
    builder: (_,__) {
      final glow = 0.2 + anim.value * 0.3;
      return Align(
        alignment: Alignment.centerLeft,
        child: GestureDetector(
          onTap: () => _open(ctx),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              color: const Color(0xFF0F2044),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Pal.gold.withOpacity(glow), width: 1.2),
              boxShadow: [BoxShadow(color: Pal.gold.withOpacity(glow * 0.3), blurRadius: 10)]),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Text('📜', style: const TextStyle(fontSize: 13)),
              const SizedBox(width: 6),
              const Text('בגרות בהיסטוריה',
                style: TextStyle(color: Color(0xFFFFD700), fontSize: 12, fontWeight: FontWeight.w800)),
            ]),
          ),
        ),
      );
    },
  );
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
        Text('$all',textDirection:TextDirection.ltr,style:const TextStyle(color:Pal.gold,fontWeight:FontWeight.w700,fontSize:13)),
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

// ── באנר אירוע עונתי ──────────────────────────────────────────────────────
class _SeasonalBanner extends StatelessWidget {
  final SeasonalEvent event;
  const _SeasonalBanner({required this.event});

  void _startQuiz(BuildContext ctx) {
    Navigator.push(ctx, _slide(_SeasonalLevelsScreen(event: event)));
  }

  @override
  Widget build(BuildContext ctx) {
    final color = event.color;
    final days  = event.daysLeft;
    return GestureDetector(
      onTap: () => _startQuiz(ctx),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.centerRight,
            end:   Alignment.centerLeft,
            colors: [color.withOpacity(0.22), color.withOpacity(0.08)],
          ),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: color.withOpacity(0.6), width: 1.5),
          boxShadow: [BoxShadow(color: color.withOpacity(0.25), blurRadius: 14, offset: const Offset(0, 4))],
        ),
        child: Row(children: [
          // אייקון
          Container(
            width: 52, height: 52,
            decoration: BoxDecoration(
              color: color.withOpacity(0.18),
              shape: BoxShape.circle,
              border: Border.all(color: color.withOpacity(0.4)),
            ),
            child: Center(child: Text(event.emoji, style: const TextStyle(fontSize: 26))),
          ),
          const SizedBox(width: 14),
          // טקסט
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.25),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text('חם עכשיו 🔥',
                  style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w800)),
              ),
              const Spacer(),
              Text(
                days == 0 ? 'היום בלבד!' : 'עוד $days ימים',
                style: TextStyle(color: color.withOpacity(0.8), fontSize: 11),
              ),
            ]),
            const SizedBox(height: 5),
            Text(event.title,
              style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w900)),
            const SizedBox(height: 2),
            Text('${event.levelCount} שלבים · ${event.questions.length} שאלות',
              style: TextStyle(color: Colors.white.withOpacity(0.55), fontSize: 12)),
          ])),
          const SizedBox(width: 8),
          Icon(Icons.arrow_back_ios_new_rounded, color: color, size: 16),
        ]),
      ),
    );
  }
}

// ═══════════════════════════════════════════════
//  מסך שלבים סיזונאלי
// ═══════════════════════════════════════════════
class _SeasonalLevelsScreen extends StatelessWidget {
  final SeasonalEvent event;
  const _SeasonalLevelsScreen({required this.event});

  @override
  Widget build(BuildContext context) {
    final color = event.color;
    final count = event.levelCount;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xFF060A1A),
        body: Stack(children: [
          const _MountainBg(),
          SafeArea(child: Column(children: [
            Padding(padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Row(children: [
                _iconBtn(Icons.arrow_back, () => Navigator.pop(context)),
                const SizedBox(width: 12),
                Text(event.emoji, style: const TextStyle(fontSize: 22)),
                const SizedBox(width: 8),
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(event.title,
                    style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800)),
                  Text('$count שלבים · ${event.questions.length} שאלות',
                    style: const TextStyle(color: Pal.ts, fontSize: 11)),
                ]),
              ])),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: 0,
                  backgroundColor: Pal.card,
                  valueColor: AlwaysStoppedAnimation(color),
                  minHeight: 6))),
            Expanded(child: LayoutBuilder(builder: (ctx, cstr) {
              final w = cstr.maxWidth;
              final mapH = count * _kRowH + _kPadV * 2;
              final positions = List.generate(count, (i) => Offset(_lvlX(i, w), mapH - _kPadV - i * _kRowH));
              return SingleChildScrollView(
                reverse: true,
                child: SizedBox(width: w, height: mapH,
                  child: Stack(clipBehavior: Clip.none, children: [
                    Positioned.fill(child: CustomPaint(
                      painter: _SeasonalTrailPainter(positions: positions, count: count, color: color))),
                    ...List.generate(count, (i) {
                      final p = positions[i];
                      return Positioned(
                        left: p.dx - 40, top: p.dy - 55,
                        child: _SeasonalTrailNode(
                          index: i,
                          total: count,
                          color: color,
                          onTap: () {
                            if (!EnergyService.instance.has) {
                              Navigator.push(ctx, _slide(const NoEnergyScreen()));
                              return;
                            }
                            EnergyService.instance.spend(Cfg.energyCostWrong);
                            Navigator.push(ctx, _slide(GameScreen(
                              diff: Diff.easy,
                              levelIndex: i,
                              retryWith: event.levelQuestions(i),
                              isSeasonal: true,
                            )));
                          },
                        ));
                    }),
                  ])));
            })),
          ])),
        ])));
  }
}

// ── Seasonal trail painter — always unlocked (event color) ──
class _SeasonalTrailPainter extends CustomPainter {
  final List<Offset> positions;
  final int count;
  final Color color;
  const _SeasonalTrailPainter({required this.positions, required this.count, required this.color});
  @override void paint(Canvas canvas, Size size) {
    for (int i = 0; i < count - 1; i++) {
      final a = positions[i], b = positions[i + 1];
      final dy = a.dy - b.dy;
      final path = Path()..moveTo(a.dx, a.dy)
        ..cubicTo(a.dx, a.dy - dy * 0.45, b.dx, b.dy + dy * 0.45, b.dx, b.dy);
      canvas.drawPath(path, Paint()..color = color.withOpacity(0.12)..strokeWidth = 22
        ..style = PaintingStyle.stroke..strokeCap = StrokeCap.round
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12));
      canvas.drawPath(path, Paint()..color = color.withOpacity(0.28)..strokeWidth = 9
        ..style = PaintingStyle.stroke..strokeCap = StrokeCap.round
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5));
      canvas.drawPath(path, Paint()..color = color.withOpacity(0.90)..strokeWidth = 3.5
        ..style = PaintingStyle.stroke..strokeCap = StrokeCap.round);
    }
  }
  @override bool shouldRepaint(_SeasonalTrailPainter old) => old.color != color || old.count != count;
}

// ── Seasonal trail node ──────────────────────────────────────
class _SeasonalTrailNode extends StatefulWidget {
  final int index, total;
  final Color color;
  final VoidCallback onTap;
  const _SeasonalTrailNode({required this.index, required this.total, required this.color, required this.onTap});
  @override State<_SeasonalTrailNode> createState() => _SeasonalTrailNodeState();
}
class _SeasonalTrailNodeState extends State<_SeasonalTrailNode> with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;
  @override void initState() {
    super.initState();
    _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 1600));
    if (widget.index == 0) _pulse.repeat(reverse: true);
  }
  @override void dispose() { _pulse.dispose(); super.dispose(); }
  @override Widget build(BuildContext context) {
    final c = widget.color;
    final String nodeEmoji;
    final pct = widget.index / widget.total;
    if (pct < 0.35) nodeEmoji = '⚽';
    else if (pct < 0.70) nodeEmoji = '🌟';
    else nodeEmoji = '🏆';
    const r = _kNodeR, d = r * 2;
    final isFirst = widget.index == 0;
    return GestureDetector(
      onTap: widget.onTap,
      child: SizedBox(width: d + 30,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          SizedBox(height: 26, child: Center(child:
            isFirst
              ? AnimatedBuilder(animation: _pulse, builder: (_, __) => Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(colors: [c, Color.lerp(c, Colors.white, 0.25)!]),
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [BoxShadow(color: c.withOpacity(0.35 + _pulse.value * 0.45),
                      blurRadius: 10 + _pulse.value * 10, spreadRadius: 1)]),
                  child: const Text('▶  שחק', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 0.5))))
              : const SizedBox.shrink())),
          const SizedBox(height: 4),
          AnimatedBuilder(
            animation: _pulse,
            builder: (_, __) {
              final pv = isFirst ? _pulse.value : 0.0;
              return Stack(alignment: Alignment.center, children: [
                if (isFirst) ...[
                  Container(width: d + 30 + pv * 22, height: d + 30 + pv * 22,
                    decoration: BoxDecoration(shape: BoxShape.circle, color: c.withOpacity(0.07 * (1 - pv)))),
                  Container(width: d + 16 + pv * 12, height: d + 16 + pv * 12,
                    decoration: BoxDecoration(shape: BoxShape.circle, color: c.withOpacity(0.13 * (1 - pv * 0.5)))),
                ],
                Container(width: d, height: d,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: c.withOpacity(0.18),
                    border: Border.all(color: c, width: 2.5),
                    boxShadow: [BoxShadow(color: c.withOpacity(0.35 + pv * 0.3), blurRadius: 12 + pv * 8)]),
                  child: Center(child: Text(nodeEmoji, style: const TextStyle(fontSize: 20)))),
              ]);
            }),
          const SizedBox(height: 4),
          Text('שלב ${widget.index + 1}',
            style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700)),
        ])));
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
          if(!unlocked){
            final all=ls.allStars;
            showDialog(context:context,builder:(_)=>Dialog(
              backgroundColor:Colors.transparent,
              child:Container(
                padding:const EdgeInsets.all(28),
                decoration:BoxDecoration(color:const Color(0xFF0A1128),borderRadius:BorderRadius.circular(24),
                  border:Border.all(color:Pal.gold.withOpacity(0.4),width:1.5),
                  boxShadow:[BoxShadow(color:Pal.gold.withOpacity(0.2),blurRadius:30)]),
                child:Column(mainAxisSize:MainAxisSize.min,children:[
                  const Text('🔒',style:TextStyle(fontSize:52)),
                  const SizedBox(height:12),
                  const Text('עדיין נעול',style:TextStyle(color:Pal.tp,fontSize:22,fontWeight:FontWeight.w900)),
                  const SizedBox(height:8),
                  Text('צריך $need ⭐ כדי לפתוח',textAlign:TextAlign.center,
                    style:const TextStyle(color:Pal.ts,fontSize:15,height:1.5)),
                  const SizedBox(height:20),
                  ClipRRect(borderRadius:BorderRadius.circular(8),
                    child:LinearProgressIndicator(
                      value:(all/need).clamp(0.0,1.0),
                      minHeight:10,
                      backgroundColor:Pal.card,
                      valueColor:AlwaysStoppedAnimation(Pal.gold))),
                  const SizedBox(height:8),
                  Text('$all / $need ⭐',style:const TextStyle(color:Pal.gold,fontSize:13,fontWeight:FontWeight.w700)),
                  const SizedBox(height:20),
                  GestureDetector(onTap:()=>Navigator.pop(context),
                    child:Container(width:double.infinity,padding:const EdgeInsets.symmetric(vertical:14),
                      decoration:BoxDecoration(color:Pal.card,borderRadius:BorderRadius.circular(14)),
                      child:const Text('הבנתי',textAlign:TextAlign.center,
                        style:TextStyle(color:Pal.tp,fontSize:15,fontWeight:FontWeight.w700)))),
                ]))));
            return;}
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
              Text(unlocked?'$earned/$maxS \u2B50'
                :(isPrem?'\u05E6\u05E8\u05D9\u05DA \u05E4\u05E8\u05D5 + $need \u05DB\u05D5\u05DB\u05D1\u05D9\u05DD':'\u05E6\u05E8\u05D9\u05DA $need \u2B50 \u05DC\u05E4\u05EA\u05D9\u05D7\u05D4'),
                textDirection:TextDirection.rtl,style:const TextStyle(color:Pal.ts,fontSize:12)),
              if(unlocked&&earned>0)...[const SizedBox(height:8),ClipRRect(borderRadius:BorderRadius.circular(4),
                child:LinearProgressIndicator(value:earned/maxS,minHeight:4,backgroundColor:Pal.starOff,valueColor:AlwaysStoppedAnimation(diff.color)))],
            ])),
            if(unlocked)Column(children:List.generate(3,(i)=>Text(i<(earned/maxS*3).round().clamp(0,3)?'\u2B50':'\u2606',style:const TextStyle(fontSize:13)))),
          ])));
    });
  }
  void _paywall(BuildContext ctx){Analytics.paywallShown('locked_level');showModalBottomSheet(context:ctx,isScrollControlled:true,backgroundColor:Colors.transparent,builder:(_)=>const PaywallSheet()).then((_){if(!PurchaseService.instance.isPremium)Analytics.paywallDismissed();});}
}

// ═══════════════════════════════════════════════
// ═══════════════════════════════════════════════
//  LEVEL MAP — Mountain trail design
// ═══════════════════════════════════════════════

const _kNodeR = 30.0;
const _kRowH  = 120.0;
const _kPadV  = 80.0;

double _lvlX(int idx, double w) {
  // More dramatic winding — wide oscillation left↔right
  const f = [0.35, 0.70, 0.25, 0.65, 0.30, 0.72, 0.22, 0.58, 0.38, 0.68];
  return w * f[idx % f.length];
}

class LevelMapScreen extends StatelessWidget {
  final Diff diff;
  const LevelMapScreen({super.key,required this.diff});
  @override Widget build(BuildContext context){
    return ListenableBuilder(listenable:LevelService.instance,builder:(_,__){
      final ls=LevelService.instance;
      final count=QRepo.levelCount(diff);
      final earned=ls.totalStars(diff);
      final maxS=count*Cfg.starsPerLevel;
      final nextDiff=diff==Diff.easy?Diff.medium:diff==Diff.medium?Diff.hard:null;
      final nextUnlocked=nextDiff!=null&&ls.isDiffUnlocked(nextDiff);
      int nextIdx=-1;
      for(int i=0;i<count;i++){if(ls.isLevelUnlocked(diff,i)&&ls.starsFor(diff,i)==0){nextIdx=i;break;}}
      return Scaffold(backgroundColor:const Color(0xFF060A1A),body:Stack(children:[
        const _MountainBg(),
        SafeArea(child:Column(children:[
          Padding(padding:const EdgeInsets.fromLTRB(16,12,16,0),
            child:Row(children:[
              _iconBtn(Icons.arrow_back,()=>Navigator.pop(context)),
              const SizedBox(width:12),
              Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
                Text(diff.label,style:TextStyle(color:diff.color,fontSize:22,fontWeight:FontWeight.w800)),
                Text('$earned / $maxS ⭐',style:const TextStyle(color:Pal.ts,fontSize:11)),
              ]),
              const Spacer(),
              const EnergyChip(),
            ])),
          Padding(padding:const EdgeInsets.fromLTRB(20,8,20,0),
            child:ClipRRect(borderRadius:BorderRadius.circular(6),
              child:LinearProgressIndicator(value:maxS>0?earned/maxS:0,
                backgroundColor:Pal.card,valueColor:AlwaysStoppedAnimation(diff.color),minHeight:6))),
          Expanded(child:LayoutBuilder(builder:(ctx,cstr){
            final w=cstr.maxWidth;
            final extra=nextDiff!=null?90.0:0.0;
            final mapH=count*_kRowH+_kPadV*2+extra;
            final positions=List.generate(count,(i)=>Offset(_lvlX(i,w),mapH-_kPadV-i*_kRowH));
            return SingleChildScrollView(
              reverse:true,
              child:SizedBox(width:w,height:mapH,
                child:Stack(clipBehavior:Clip.none,children:[
                  Positioned.fill(child:CustomPaint(
                    painter:_TrailPainter(positions:positions,count:count,ls:ls,diff:diff))),
                  ...List.generate(count,(i){
                    final p=positions[i];
                    return Positioned(
                      left:p.dx-40,top:p.dy-55,
                      child:_TrailNode(
                        diff:diff,index:i,
                        unlocked:ls.isLevelUnlocked(diff,i),
                        stars:ls.starsFor(diff,i),
                        perfect:ls.starsFor(diff,i)==Cfg.starsPerLevel,
                        isNext:i==nextIdx,
                        lockLabel:(!ls.isLevelUnlocked(diff,i)&&i>0&&i%Cfg.segmentSize==0)?ls.segmentProgress(diff,i):"",
                        onTap:(){
                          if(!ls.isLevelUnlocked(diff,i))return;
                          if(!EnergyService.instance.has){Navigator.push(ctx,_slide(const NoEnergyScreen()));return;}
                          EnergyService.instance.spend(Cfg.energyCostWrong);
                          Navigator.push(ctx,_slide(GameScreen(diff:diff,levelIndex:i)));
                        }));
                  }),
                  if(nextDiff!=null)Positioned(
                    top:16,left:w*0.5-100,width:200,
                    child:_DiffTransitionNode(nextDiff:nextDiff,unlocked:nextUnlocked,currentDiff:diff)),
                ])));
          })),
        ])),
      ]));
    });
  }
}

// ── Mountain background ─────────────────────────────
class _MountainBg extends StatelessWidget {
  const _MountainBg();
  @override Widget build(BuildContext context)=>SizedBox.expand(child:CustomPaint(painter:_MtnPainter()));
}

class _MtnPainter extends CustomPainter {
  @override void paint(Canvas canvas,Size size){
    final w=size.width,h=size.height;

    // ── Sky gradient ──────────────────────────────
    canvas.drawRect(Rect.fromLTWH(0,0,w,h),Paint()
      ..shader=const LinearGradient(
        begin:Alignment.topCenter,end:Alignment.bottomCenter,
        colors:[Color(0xFF04060F),Color(0xFF060A1A),Color(0xFF091230)])
        .createShader(Rect.fromLTWH(0,0,w,h)));

    // ── Stars (random dots) ───────────────────────
    final rng=List.generate(60,(i)=>i);
    for(final i in rng){
      final x=(i*137.5%w);
      final y=(i*89.3%( h*0.7));
      final r=(i%3==0)?1.4:(i%3==1)?0.9:0.6;
      canvas.drawCircle(Offset(x,y),r,Paint()..color=Colors.white.withOpacity(0.15+(i%5)*0.07));
    }

    // ── Far mountains (faintest) ──────────────────
    _mtn(canvas,[
      Offset(0,h),Offset(0,h*0.75),
      Offset(w*0.08,h*0.75),Offset(w*0.15,h*0.30),Offset(w*0.22,h*0.68),
      Offset(w*0.32,h*0.60),Offset(w*0.40,h*0.22),Offset(w*0.48,h*0.62),
      Offset(w*0.58,h*0.55),Offset(w*0.67,h*0.18),Offset(w*0.75,h*0.58),
      Offset(w*0.84,h*0.50),Offset(w*0.92,h*0.28),Offset(w,h*0.55),
      Offset(w,h),
    ],const Color(0xFF0D1A40));

    // ── Mid mountains ─────────────────────────────
    _mtn(canvas,[
      Offset(0,h),Offset(0,h*0.82),
      Offset(w*0.10,h*0.82),Offset(w*0.18,h*0.45),Offset(w*0.26,h*0.72),
      Offset(w*0.36,h*0.65),Offset(w*0.45,h*0.35),Offset(w*0.54,h*0.68),
      Offset(w*0.63,h*0.60),Offset(w*0.72,h*0.38),Offset(w*0.80,h*0.65),
      Offset(w*0.89,h*0.55),Offset(w,h*0.68),Offset(w,h),
    ],const Color(0xFF091025));

    // ── Near mountains (darkest foreground) ───────
    _mtn(canvas,[
      Offset(0,h),Offset(0,h*0.88),
      Offset(w*0.12,h*0.88),Offset(w*0.20,h*0.58),Offset(w*0.28,h*0.80),
      Offset(w*0.38,h*0.74),Offset(w*0.47,h*0.55),Offset(w*0.56,h*0.76),
      Offset(w*0.65,h*0.68),Offset(w*0.74,h*0.52),Offset(w*0.82,h*0.72),
      Offset(w*0.91,h*0.63),Offset(w,h*0.75),Offset(w,h),
    ],const Color(0xFF060810));

    // ── Bottom fog ────────────────────────────────
    canvas.drawRect(Rect.fromLTWH(0,h*0.75,w,h*0.25),Paint()
      ..shader=LinearGradient(begin:Alignment.topCenter,end:Alignment.bottomCenter,
        colors:[Colors.transparent,const Color(0xFF0D1840).withOpacity(0.55)])
        .createShader(Rect.fromLTWH(0,h*0.75,w,h*0.25)));
  }

  // Sharp lineTo peaks — no bezier smoothing so peaks stay pointy
  void _mtn(Canvas c,List<Offset> pts,Color col){
    final path=Path()..moveTo(pts[0].dx,pts[0].dy);
    for(int i=1;i<pts.length;i++) path.lineTo(pts[i].dx,pts[i].dy);
    path.close();
    c.drawPath(path,Paint()..color=col);
  }

  @override bool shouldRepaint(_)=>false;
}

// ── Trail path painter ──────────────────────────────
class _TrailPainter extends CustomPainter {
  final List<Offset> positions;
  final int count;
  final LevelService ls;
  final Diff diff;
  _TrailPainter({required this.positions,required this.count,required this.ls,required this.diff});
  @override void paint(Canvas canvas,Size size){
    for(int i=0;i<count-1;i++){
      final a=positions[i],b=positions[i+1];
      final unlocked=ls.isLevelUnlocked(diff,i);
      // S-curve bezier between nodes
      final dy=a.dy-b.dy;
      final path=Path()..moveTo(a.dx,a.dy)
        ..cubicTo(a.dx,a.dy-dy*0.45,b.dx,b.dy+dy*0.45,b.dx,b.dy);
      if(unlocked){
        canvas.drawPath(path,Paint()..color=diff.color.withOpacity(0.12)..strokeWidth=22
          ..style=PaintingStyle.stroke..strokeCap=StrokeCap.round
          ..maskFilter=const MaskFilter.blur(BlurStyle.normal,12));
        canvas.drawPath(path,Paint()..color=diff.color.withOpacity(0.28)..strokeWidth=9
          ..style=PaintingStyle.stroke..strokeCap=StrokeCap.round
          ..maskFilter=const MaskFilter.blur(BlurStyle.normal,5));
        canvas.drawPath(path,Paint()..color=diff.color.withOpacity(0.90)..strokeWidth=3.5
          ..style=PaintingStyle.stroke..strokeCap=StrokeCap.round);
      }else{
        // Dashed locked path
        final tot=(b-a).distance;
        final dir=(b-a)/tot;
        double d=0;bool on=true;
        final p=Paint()..color=Pal.ts.withOpacity(0.22)..strokeWidth=2
          ..style=PaintingStyle.stroke..strokeCap=StrokeCap.round;
        while(d<tot){
          final seg=on?9.0:5.0;
          final end=min(d+seg,tot);
          if(on)canvas.drawLine(a+dir*d,a+dir*end,p);
          d=end;on=!on;
        }
      }
    }
  }
  @override bool shouldRepaint(_TrailPainter old)=>
    old.count!=count||old.diff!=diff||old.positions!=positions;
}

// ── Trail node widget ───────────────────────────────
class _TrailNode extends StatefulWidget {
  final Diff diff;final int index,stars;
  final bool unlocked,perfect,isNext;
  final String lockLabel;
  final VoidCallback onTap;
  const _TrailNode({required this.diff,required this.index,required this.unlocked,
    required this.stars,required this.perfect,required this.isNext,
    this.lockLabel="",required this.onTap});
  @override State<_TrailNode> createState()=>_TrailNodeState();
}
class _TrailNodeState extends State<_TrailNode> with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;
  @override void initState(){
    super.initState();
    _pulse=AnimationController(vsync:this,duration:const Duration(milliseconds:1600));
    if(widget.isNext)_pulse.repeat(reverse:true);
  }
  @override void dispose(){_pulse.dispose();super.dispose();}
  @override Widget build(BuildContext context){
    final nc=widget.perfect?Pal.gold:widget.diff.color;
    const r=_kNodeR,d=r*2;
    return GestureDetector(
      onTap:widget.onTap,
      child:SizedBox(width:d+30,
        child:Column(mainAxisSize:MainAxisSize.min,children:[
          SizedBox(height:26,child:Center(child:
            widget.isNext
              ?AnimatedBuilder(animation:_pulse,builder:(_,__)=>Container(
                  padding:const EdgeInsets.symmetric(horizontal:10,vertical:4),
                  decoration:BoxDecoration(
                    gradient:LinearGradient(colors:[widget.diff.color,Color.lerp(widget.diff.color,Colors.white,0.25)!]),
                    borderRadius:BorderRadius.circular(12),
                    boxShadow:[BoxShadow(color:widget.diff.color.withOpacity(0.35+_pulse.value*0.45),
                      blurRadius:10+_pulse.value*10,spreadRadius:1)]),
                  child:const Text('▶  שחק',style:TextStyle(color:Colors.white,fontSize:10,fontWeight:FontWeight.w800,letterSpacing:0.5))))
              :(widget.unlocked&&widget.stars>0
                  ?Row(mainAxisSize:MainAxisSize.min,children:List.generate(Cfg.starsPerLevel,(i)=>Icon(
                      i<widget.stars?Icons.star_rounded:Icons.star_border_rounded,
                      size:13,color:i<widget.stars?Pal.starOn:Pal.starOff.withOpacity(0.2))))
                  :const SizedBox.shrink()))),
          const SizedBox(height:4),
          AnimatedBuilder(
            animation:_pulse,
            builder:(_,__){
              final pv=widget.isNext?_pulse.value:0.0;
              return Stack(alignment:Alignment.center,children:[
                if(widget.isNext)...[
                  Container(width:d+30+pv*22,height:d+30+pv*22,
                    decoration:BoxDecoration(shape:BoxShape.circle,color:nc.withOpacity(0.07*(1-pv)))),
                  Container(width:d+16+pv*12,height:d+16+pv*12,
                    decoration:BoxDecoration(shape:BoxShape.circle,color:nc.withOpacity(0.13*(1-pv*0.5)))),
                ],
                Container(
                  width:d,height:d,
                  decoration:BoxDecoration(shape:BoxShape.circle,
                    boxShadow:widget.unlocked?[
                      BoxShadow(color:nc.withOpacity(widget.isNext?0.60+pv*0.40:widget.perfect?0.55:0.28),
                        blurRadius:widget.isNext?28+pv*18:widget.perfect?22:13,
                        spreadRadius:widget.isNext?4+pv*4:widget.perfect?3:1),
                    ]:null),
                  child:Container(
                    decoration:BoxDecoration(shape:BoxShape.circle,
                      gradient:widget.unlocked?LinearGradient(
                        begin:const Alignment(-0.3,-0.7),end:const Alignment(0.5,0.8),
                        colors:widget.perfect
                          ?[const Color(0xFFFFEA80),const Color(0xFFFFB830),const Color(0xFFFF7A00)]
                          :widget.isNext
                            ?[Color.lerp(nc,Colors.white,0.35)!,nc,Color.lerp(nc,Colors.black,0.30)!]
                            :[nc.withOpacity(0.9),nc.withOpacity(0.55)]):null,
                      color:widget.unlocked?null:const Color(0xFF10152A),
                      border:Border.all(
                        color:widget.perfect?const Color(0xFFFFD700):widget.unlocked?nc.withOpacity(0.85):Pal.ts.withOpacity(0.16),
                        width:widget.perfect?2.8:widget.isNext?2.2:1.8)),
                    child:Stack(alignment:Alignment.center,children:[
                      if(widget.unlocked)Positioned(top:5,left:8,
                        child:Container(width:14,height:6,
                          decoration:BoxDecoration(borderRadius:BorderRadius.circular(8),
                            color:Colors.white.withOpacity(0.32)))),
                      widget.unlocked
                        ?widget.perfect
                          ?const Text('👑',style:TextStyle(fontSize:22))
                          :Text('${widget.index+1}',style:TextStyle(
                              color:Colors.white,fontSize:widget.isNext?24:20,
                              fontWeight:FontWeight.w900,
                              shadows:const [Shadow(color:Colors.black45,blurRadius:6)]))
                        :Icon(Icons.lock_rounded,color:Pal.ts.withOpacity(0.40),size:18),
                    ])),
                ),
              ]);
            }),
          if(widget.lockLabel.isNotEmpty)...[
            const SizedBox(height:6),
            Container(
              padding:const EdgeInsets.symmetric(horizontal:6,vertical:4),
              decoration:BoxDecoration(
                color:const Color(0xFFFF9500).withOpacity(0.15),
                borderRadius:BorderRadius.circular(8),
                border:Border.all(color:const Color(0xFFFF9500).withOpacity(0.45),width:1)),
              child:Column(mainAxisSize:MainAxisSize.min,children:[
                Text(widget.lockLabel,textAlign:TextAlign.center,
                  style:const TextStyle(color:Color(0xFFFFAA33),fontSize:9,fontWeight:FontWeight.w800)),
                Text('לפתיחה',textAlign:TextAlign.center,
                  style:TextStyle(color:const Color(0xFFFF9500).withOpacity(0.70),fontSize:8,fontWeight:FontWeight.w600)),
              ])),
          ],
        ])));
  }
}

// ── Diff transition node ────────────────────────────
class _DiffTransitionNode extends StatelessWidget {
  final Diff nextDiff,currentDiff;final bool unlocked;
  const _DiffTransitionNode({required this.nextDiff,required this.currentDiff,required this.unlocked});
  @override Widget build(BuildContext context){
    return GestureDetector(
      onTap:unlocked?()=>Navigator.pushReplacement(context,_slide(LevelMapScreen(diff:nextDiff))):null,
      child:Container(
        padding:const EdgeInsets.symmetric(horizontal:16,vertical:12),
        decoration:BoxDecoration(
          gradient:unlocked?LinearGradient(colors:[nextDiff.color.withOpacity(0.25),nextDiff.color.withOpacity(0.08)]):null,
          color:unlocked?null:Pal.card.withOpacity(0.4),
          borderRadius:BorderRadius.circular(20),
          border:Border.all(color:unlocked?nextDiff.color.withOpacity(0.7):Pal.ts.withOpacity(0.2),width:unlocked?2:1),
          boxShadow:unlocked?[BoxShadow(color:nextDiff.color.withOpacity(0.3),blurRadius:16)]:null),
        child:Row(mainAxisSize:MainAxisSize.min,mainAxisAlignment:MainAxisAlignment.center,children:[
          Text(unlocked?nextDiff.emoji:'🔒',style:const TextStyle(fontSize:20)),
          const SizedBox(width:10),
          Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
            Text(nextDiff.label,style:TextStyle(color:unlocked?Pal.tp:Pal.ts,fontSize:14,fontWeight:FontWeight.w800)),
            Text(unlocked?'לחץ לפתיחה ▶':'Need ${nextDiff==Diff.medium?Cfg.starsToUnlockMedium:Cfg.starsToUnlockHard} ⭐ to unlock',
              style:TextStyle(color:unlocked?nextDiff.color:Pal.ts.withOpacity(0.6),fontSize:11)),
          ]),
        ])));
  }
}


//  GAME SCREEN
// ═══════════════════════════════════════════════
class GameScreen extends StatefulWidget {
  final Diff diff; final int levelIndex;
  final List<Question>? retryWith;
  final bool isSeasonal;
  const GameScreen({super.key,required this.diff,required this.levelIndex,this.retryWith,this.isSeasonal=false});
  @override State<GameScreen> createState()=>_GS();
}
class _GS extends State<GameScreen> with TickerProviderStateMixin {
  late final GameState _gs;
  late final AnimationController _shakeCtrl,_cardCtrl,_energyLossCtrl;
  late final Animation<double> _shake,_card,_energyLossOpacity,_energyLossOffset;
  bool _exiting=false;
  late final bool _showEnergyOverlay;

  @override void initState(){
    super.initState();
    // בדיקה סינכרונית — נטען בעליית האפליקציה
    _showEnergyOverlay = widget.diff == Diff.easy &&
        widget.levelIndex == 0 &&
        widget.retryWith == null &&
        !_EnergyOverlay.seen;
    if (_showEnergyOverlay) _EnergyOverlay.markSeen();
    _gs=GameState(diff:widget.diff,levelIdx:widget.levelIndex,retryWith:widget.retryWith,isSeasonal:widget.isSeasonal);
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
    if(_gs.phase==Phase.complete&&!_exiting){_exiting=true;Analytics.levelCompleted(diff:widget.diff.name,levelIndex:widget.levelIndex,stars:_gs.stars);Future.delayed(const Duration(milliseconds:400),(){if(mounted)Navigator.pushReplacement(context,_slide(CompleteScreen(diff:widget.diff,levelIndex:widget.levelIndex,stars:_gs.stars)));});}
    if(_gs.phase==Phase.failed&&!_exiting){final fq=_gs.failedQuestions;_exiting=true;Analytics.levelFailed(diff:widget.diff.name,levelIndex:widget.levelIndex);Future.delayed(const Duration(milliseconds:400),(){if(mounted)Navigator.pushReplacement(context,_slide(FailedScreen(diff:widget.diff,levelIndex:widget.levelIndex,failedQuestions:fq)));});}
  }
  @override void dispose(){_gs.removeListener(_onChange);EnergyService.instance.removeListener(_onEnergyChange);_gs.dispose();_shakeCtrl.dispose();_cardCtrl.dispose();_energyLossCtrl.dispose();super.dispose();}
  Future<bool> _quit() async {
    final leave=await showDialog<bool>(context:context,barrierDismissible:false,builder:(_)=>_QuitDlg());
    return leave??false;
  }
  @override Widget build(BuildContext context){
    // המסך ממשיך להיות בstackbזמן הtransition — לא לגשת לcur כשהqueue ריק
    if (_gs.phase != Phase.playing || _exiting) {
      return const Scaffold(backgroundColor: Pal.bg, body: SizedBox.shrink());
    }
    final q=_gs.cur;
    return WillPopScope(onWillPop:_quit,
      child:Scaffold(backgroundColor:Pal.bg,body:Stack(children:[
        const StarField(),
        SafeArea(child:Column(children:[
          // Top bar
          Padding(padding:const EdgeInsets.fromLTRB(16,8,16,0),child:Row(children:[
            _iconBtn(Icons.close,()async{final l=await _quit();if(l&&mounted){Analytics.levelQuit(diff:widget.diff.name,levelIndex:widget.levelIndex);Navigator.pop(context);}}),const SizedBox(width:8),_iconBtn(Icons.refresh_rounded,()async{final l=await showDialog<bool>(context:context,barrierDismissible:false,builder:(_)=>_RestartDlg());if((l??false)&&mounted){setState((){});_gs.removeListener(_onChange);_gs.dispose();setState((){_gs=GameState(diff:widget.diff,levelIdx:widget.levelIndex);_gs.addListener(_onChange);_exiting=false;_cardCtrl.forward(from:0);});}}),
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
            if(_gs.waitingContinue&&q.f!=null)_FactBanner(gs:_gs),
            const SizedBox(height:10),
            ...List.generate(q.a.length,(i)=>Padding(padding:const EdgeInsets.only(bottom:10),child:_ABtn(gs:_gs,i:i))),
            if(_gs.waitingContinue)Padding(
              padding:const EdgeInsets.only(top:4),
              child:GestureDetector(
                onTap:_gs.continueAfterFeedback,
                child:Container(
                  width:double.infinity,
                  padding:const EdgeInsets.symmetric(vertical:16),
                  decoration:BoxDecoration(
                    gradient:LinearGradient(colors:[widget.diff.color,Color.lerp(widget.diff.color,Colors.black,0.3)!]),
                    borderRadius:BorderRadius.circular(16),
                    boxShadow:[BoxShadow(color:widget.diff.color.withOpacity(0.4),blurRadius:12,offset:const Offset(0,4))]),
                  child:Text('המשך',textAlign:TextAlign.center,
                    style:const TextStyle(color:Colors.white,fontSize:18,fontWeight:FontWeight.w800))))),
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
                    const Text('🧠',style:TextStyle(fontSize:28)),
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
        Text(q.q,textDirection:TextDirection.rtl,style:const TextStyle(color:Pal.tp,fontSize:17,fontWeight:FontWeight.w700,height:1.35)),
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
            Text(ok?'\u05E0\u05DB\u05D5\u05DF!':'\u05EA\u05E9\u05D5\u05D1\u05D4: ${q.a[q.c]}',textDirection:TextDirection.rtl,style:TextStyle(color:c,fontWeight:FontWeight.w800,fontSize:13)),
            if(q.f!=null)...[const SizedBox(height:4),Text(q.f!,textDirection:TextDirection.rtl,style:const TextStyle(color:Pal.ts,fontSize:12,height:1.4))],
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
            Expanded(child:Text(widget.gs.cur.a[widget.i],textDirection:TextDirection.rtl,style:TextStyle(color:widget.gs.fb&&widget.i!=widget.gs.cur.c&&widget.i!=widget.gs.sel?Pal.ts:Pal.tp,fontSize:14,fontWeight:FontWeight.w600))),
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
//  INTERESTS BOTTOM SHEET (מינימלי)
// ═══════════════════════════════════════════════
class _InfoRow extends StatelessWidget {
  final String emoji, text;
  const _InfoRow({required this.emoji, required this.text});
  @override Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(emoji, style: const TextStyle(fontSize: 13)),
      const SizedBox(width: 8),
      Expanded(child: Text(text, textDirection: TextDirection.rtl,
        style: const TextStyle(color: Color(0xFF90A4AE), fontSize: 12, height: 1.4))),
    ],
  );
}

class _InterestBottomSheet extends StatefulWidget {
  const _InterestBottomSheet();
  @override State<_InterestBottomSheet> createState() => _IBSState();
}
class _IBSState extends State<_InterestBottomSheet> {
  final Set<String> _sel = {};
  bool _expanded = false;

  @override Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF111E35),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(20, 16, 20, MediaQuery.of(context).viewInsets.bottom + 24),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        // Handle
        Container(width: 36, height: 4,
          decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2))),
        const SizedBox(height: 18),
        const Text('מה מעניין אותך?', textAlign: TextAlign.center,
          style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800)),
        const SizedBox(height: 6),
        // ─── הסבר + קרא עוד ───────────────────────────────────────────────
        GestureDetector(
          onTap: () => setState(() => _expanded = !_expanded),
          child: Column(children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                color: const Color(0xFF1A2A40),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: const Color(0xFF2A3A55)),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Text('רוב השאלות יהיו ממה שבחרת',
                  style: TextStyle(color: Color(0xFF90A4AE), fontSize: 12)),
                const SizedBox(width: 6),
                AnimatedCrossFade(
                  firstChild: const Text('קרא עוד',
                    style: TextStyle(color: Color(0xFF4D96FF), fontSize: 12, fontWeight: FontWeight.w700)),
                  secondChild: const Text('סגור',
                    style: TextStyle(color: Color(0xFF4D96FF), fontSize: 12, fontWeight: FontWeight.w700)),
                  crossFadeState: _expanded ? CrossFadeState.showSecond : CrossFadeState.showFirst,
                  duration: const Duration(milliseconds: 150)),
              ]),
            ),
            AnimatedCrossFade(
              firstChild: const SizedBox.shrink(),
              secondChild: Container(
                margin: const EdgeInsets.only(top: 10),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF0D1728),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFF1E2D45))),
                child: const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  _InfoRow(emoji: '🎯', text: 'שאלות מהתחומים שבחרת: כ-70% מהזמן'),
                  SizedBox(height: 6),
                  _InfoRow(emoji: '🔀', text: 'שאלות מגוונות מכל הנושאים: כ-30% — כדי לשמור על האתגר'),
                  SizedBox(height: 6),
                  _InfoRow(emoji: '🔓', text: 'אף נושא לא נחסם לחלוטין'),
                  SizedBox(height: 6),
                  _InfoRow(emoji: '📈', text: 'המערכת מזהה נושאים שקשים לך ומשלבת אותם בהדרגה — לא כענישה, אלא כדי לעזור לך להשתפר'),
                ]),
              ),
              crossFadeState: _expanded ? CrossFadeState.showSecond : CrossFadeState.showFirst,
              duration: const Duration(milliseconds: 200),
            ),
          ]),
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 8, runSpacing: 8,
          alignment: WrapAlignment.center,
          children: InterestCat.all.map((cat) {
            final on = _sel.contains(cat.key);
            return GestureDetector(
              onTap: () => setState(() {
                if (on) _sel.remove(cat.key); else _sel.add(cat.key);
              }),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                decoration: BoxDecoration(
                  color: on ? cat.color.withOpacity(0.2) : const Color(0xFF1E2D45),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: on ? cat.color : const Color(0xFF2A3A55), width: 1.5),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Text(cat.emoji, style: const TextStyle(fontSize: 14)),
                  const SizedBox(width: 5),
                  Text(cat.label,
                    style: TextStyle(
                      color: on ? Colors.white : const Color(0xFF78909C),
                      fontSize: 12, fontWeight: on ? FontWeight.w700 : FontWeight.w500)),
                ]),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 20),
        Row(children: [
          Expanded(child: TextButton(
            onPressed: () { Analytics.interestsSkipped(); Navigator.pop(context); },
            child: const Text('דלג', style: TextStyle(color: Color(0xFF546E7A), fontSize: 14)),
          )),
          const SizedBox(width: 8),
          Expanded(flex: 2, child: ElevatedButton(
            onPressed: _sel.isEmpty ? null : _save,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFFD700),
              foregroundColor: Colors.black,
              disabledBackgroundColor: const Color(0xFF1E2D45),
              padding: const EdgeInsets.symmetric(vertical: 13),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            child: const Text('שמור ✓', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
          )),
        ]),
      ]),
    );
  }

  Future<void> _save() async {
    final isFirst = !InterestsService.instance.hasInterests;
    await InterestsService.instance.setInterests(_sel);
    if (isFirst) {
      Analytics.interestsSelected(categories: _sel.toList());
    } else {
      Analytics.interestsChanged(categories: _sel.toList());
    }
    if (mounted) Navigator.pop(context);
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
  late final AnimationController _enter, _confettiCtrl, _burstCtrl;
  final List<_Confetti> _confettiPieces = [];
  bool _showButtons = false;
  bool _showLevelUp = false;
  late final AnimationController _levelUpCtrl;

  @override void initState() {
    super.initState();
    _enter = AnimationController(vsync:this, duration:const Duration(milliseconds:700))..forward();
    _confettiCtrl = AnimationController(vsync:this, duration:const Duration(seconds:3))..forward();
    _burstCtrl = AnimationController(vsync:this, duration:const Duration(milliseconds:900))..forward();
    _levelUpCtrl = AnimationController(vsync:this, duration:const Duration(milliseconds:800));
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
    // Level up animation (only if next level available)
    Future.delayed(Duration(milliseconds: 600 + widget.stars * 300 + 700), () {
      if (mounted && _canNext) {
        setState(() => _showLevelUp = true);
        _levelUpCtrl.forward();
      }
    });
    // אחרי השלב הראשון — הצג בחירת תחומי עניין
    _maybeShowInterests();
  }

  Future<void> _maybeShowInterests() async {
    if (InterestsService.instance.hasInterests) return;
    final p = await SharedPreferences.getInstance();
    if ((p.getInt('levels_completed') ?? 0) < 3) return;
    if (p.getBool('interests_prompt_shown') ?? false) return;
    await p.setBool('interests_prompt_shown', true);
    await Future.delayed(const Duration(milliseconds: 400));
    if (!mounted) return;
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      isDismissible: false,
      enableDrag: false,
      builder: (_) => const _InterestBottomSheet(),
    );
  }

  Future<void> _maybeRequestReview() async {
    try {
      final p = await SharedPreferences.getInstance();
      final shownReview = p.getBool('review_dialog_shown') ?? false;
      if (shownReview) return;
      await p.setBool('review_dialog_shown', true);
      await Future.delayed(const Duration(milliseconds: 300));
      if (!mounted) return;
      final enjoyed = await showDialog<bool?>(
        context: context,
        barrierDismissible: false,
        builder: (_) => const _EnjoyedDialog(),
      );
      await NotificationService.requestPermission();
      if (!mounted) return;
      if (enjoyed == true) {
        FirebaseAnalytics.instance.logEvent(name: 'review_prompt_yes');
        final review = InAppReview.instance;
        if (await review.isAvailable()) {
          await review.requestReview();
        } else {
          await review.openStoreListing();
        }
      } else if (enjoyed == false) {
        FirebaseAnalytics.instance.logEvent(name: 'review_prompt_no');
      } else {
        FirebaseAnalytics.instance.logEvent(name: 'review_prompt_skip');
      }
    } catch (_) {}
  }

  @override void dispose() {
    _enter.dispose(); _confettiCtrl.dispose(); _levelUpCtrl.dispose(); _burstCtrl.dispose();
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
      // Burst shockwave
      AnimatedBuilder(
        animation: _burstCtrl,
        builder: (_, __) => CustomPaint(
          size: Size.infinite,
          painter: _BurstPainter(_burstCtrl.value, perfect ? Pal.gold : widget.diff.color))),
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
          // Level Up banner
          if (_showLevelUp) ...[
            const SizedBox(height: 8),
            AnimatedBuilder(
              animation: _levelUpCtrl,
              builder: (_, __) {
                final v = CurvedAnimation(parent: _levelUpCtrl, curve: Curves.easeOutBack).value;
                return Opacity(
                  opacity: v.clamp(0.0, 1.0),
                  child: Transform.scale(
                    scale: 0.5 + v * 0.5,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 10),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(colors: [Color(0xFFFF9F0A), Color(0xFFFF6B00)]),
                        borderRadius: BorderRadius.circular(30),
                        boxShadow: [BoxShadow(color: const Color(0xFFFF9F0A).withOpacity(0.6 * v), blurRadius: 24, spreadRadius: 2)]),
                      child: const Text('עלית שלב! 🚀',
                        style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w900, letterSpacing: 1.5)))));
              }),
            const SizedBox(height: 24),
          ],
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

// ─── Burst / shockwave painter ───────────────────
class _BurstPainter extends CustomPainter {
  final double t; // 0..1
  final Color color;
  _BurstPainter(this.t, this.color);
  @override void paint(Canvas canvas, Size size) {
    final cx = size.width / 2, cy = size.height * 0.38;
    // 3 expanding rings, staggered
    for (int i = 0; i < 3; i++) {
      final delay = i * 0.15;
      final progress = ((t - delay) / (1 - delay)).clamp(0.0, 1.0);
      if (progress <= 0) continue;
      final r = progress * size.width * 0.85;
      final opacity = (1.0 - progress) * (i == 0 ? 0.55 : i == 1 ? 0.35 : 0.20);
      if (opacity <= 0) continue;
      canvas.drawCircle(
        Offset(cx, cy), r,
        Paint()
          ..color = color.withOpacity(opacity)
          ..style = PaintingStyle.stroke
          ..strokeWidth = (1 - progress) * (i == 0 ? 8 : i == 1 ? 5 : 3)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, (1 - progress) * 12));
    }
  }
  @override bool shouldRepaint(_BurstPainter old) => old.t != t;
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
  final List<Question> failedQuestions;
  const FailedScreen({super.key,required this.diff,required this.levelIndex,required this.failedQuestions});
  @override State<FailedScreen> createState()=>_FS();
}
class _FS extends State<FailedScreen> with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  @override void initState(){
    super.initState();
    _c=AnimationController(vsync:this,duration:const Duration(milliseconds:600))..forward();
    _maybeShowInterests();
  }
  Future<void> _maybeShowInterests() async {
    if (InterestsService.instance.hasInterests) return;
    final p = await SharedPreferences.getInstance();
    if ((p.getInt('levels_completed') ?? 0) < 3) return;
    if (p.getBool('interests_prompt_shown') ?? false) return;
    await p.setBool('interests_prompt_shown', true);
    await Future.delayed(const Duration(milliseconds: 1400));
    if (!mounted) return;
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      isDismissible: false,
      enableDrag: false,
      builder: (_) => const _InterestBottomSheet(),
    );
  }
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
          Navigator.pushReplacement(context,_slide(GameScreen(diff:widget.diff,levelIndex:widget.levelIndex,retryWith:widget.failedQuestions)));
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
//  MISTAKES SCREEN
// ═══════════════════════════════════════════════
class MistakesScreen extends StatelessWidget {
  const MistakesScreen({super.key});
  @override Widget build(BuildContext context) {
    final list = MistakesService.instance.list;
    return Scaffold(
      backgroundColor: Pal.bgD,
      appBar: AppBar(
        backgroundColor: Pal.bgD,
        title: const Text('❌  שגיאות אחרונות', style: TextStyle(color: Pal.tp, fontWeight: FontWeight.w800)),
        leading: IconButton(icon: const Icon(Icons.arrow_back_ios_new, color: Pal.tp), onPressed: () => Navigator.pop(context)),
      ),
      body: list.isEmpty
        ? const Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('🎉', style: TextStyle(fontSize: 48)),
            SizedBox(height: 12),
            Text('עדיין אין שגיאות!', style: TextStyle(color: Pal.tp, fontSize: 18, fontWeight: FontWeight.w700)),
            SizedBox(height: 6),
            Text('כל הכבוד, המשך כך', style: TextStyle(color: Pal.ts, fontSize: 14)),
          ]))
        : ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: list.length,
            itemBuilder: (_, i) {
              final q = list[i];
              return Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Pal.card,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Pal.red.withOpacity(0.4), width: 1.2)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(color: Pal.red.withOpacity(0.15), borderRadius: BorderRadius.circular(8)),
                      child: Text(q.category, style: const TextStyle(color: Pal.red, fontSize: 11, fontWeight: FontWeight.w700))),
                    const SizedBox(width: 8),
                    Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(color: q.diff.color.withOpacity(0.15), borderRadius: BorderRadius.circular(8)),
                      child: Text(q.diff.label, style: TextStyle(color: q.diff.color, fontSize: 11, fontWeight: FontWeight.w700))),
                  ]),
                  const SizedBox(height: 10),
                  Text(q.q, textDirection: TextDirection.rtl, style: const TextStyle(color: Pal.tp, fontSize: 15, fontWeight: FontWeight.w600, height: 1.4)),
                  const SizedBox(height: 10),
                  Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(color: Pal.green.withOpacity(0.12), borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Pal.green.withOpacity(0.4))),
                    child: Row(children: [
                      const Text('✅ ', style: TextStyle(fontSize: 14)),
                      Expanded(child: Text(q.a[q.c], textDirection: TextDirection.rtl, style: const TextStyle(color: Pal.green, fontSize: 14, fontWeight: FontWeight.w700))),
                    ])),
                  if (q.f != null) ...[
                    const SizedBox(height: 8),
                    Text(q.f!, textDirection: TextDirection.rtl, style: const TextStyle(color: Pal.ts, fontSize: 12, height: 1.5)),
                  ],
                ]),
              );
            }),
    );
  }
}

// ═══════════════════════════════════════════════
//  COUNTDOWN CLOCK (analog-style circular timer)
// ═══════════════════════════════════════════════
class _CountdownClock extends StatefulWidget {
  const _CountdownClock();
  @override State<_CountdownClock> createState() => _CountdownClockState();
}
class _CountdownClockState extends State<_CountdownClock> {
  late final Timer _t;
  @override void initState() { super.initState(); _t = Timer.periodic(const Duration(seconds:1),(_){if(mounted)setState((){});}); }
  @override void dispose() { _t.cancel(); super.dispose(); }
  @override Widget build(BuildContext context) {
    final secs = EnergyService.instance.secondsUntilNext;
    final total = Cfg.energyRechargeMins * 60;
    final progress = total > 0 ? secs / total : 0.0;
    final m = secs ~/ 60, s = secs % 60;
    return Column(children: [
      SizedBox(width:150, height:150, child: Stack(alignment:Alignment.center, children:[
        CustomPaint(size:const Size(150,150), painter:_ClockPainter(progress:progress)),
        const Text('🧠', style:TextStyle(fontSize:38)),
      ])),
      const SizedBox(height:12),
      Text('${m.toString().padLeft(2,'0')}:${s.toString().padLeft(2,'0')}',
        style:const TextStyle(color:Pal.gold, fontSize:32, fontWeight:FontWeight.w900)),
      const SizedBox(height:4),
      const Text('עד המוח הבא', style:TextStyle(color:Pal.ts, fontSize:13)),
    ]);
  }
}
class _ClockPainter extends CustomPainter {
  final double progress;
  const _ClockPainter({required this.progress});
  @override void paint(Canvas canvas, Size size) {
    final c = Offset(size.width/2, size.height/2);
    final r = size.width/2 - 10;
    // Background ring
    canvas.drawArc(Rect.fromCircle(center:c,radius:r), -pi/2, 2*pi, false,
      Paint()..color=const Color(0xFF2A3A6E)..style=PaintingStyle.stroke..strokeWidth=10..strokeCap=StrokeCap.round);
    // Progress arc (gold, remaining time)
    if (progress > 0.002) {
      canvas.drawArc(Rect.fromCircle(center:c,radius:r), -pi/2, 2*pi*progress, false,
        Paint()..color=Pal.gold..style=PaintingStyle.stroke..strokeWidth=10..strokeCap=StrokeCap.round);
    }
    // 12 tick marks
    for (int i=0;i<12;i++) {
      final a = (i*30-90)*pi/180;
      canvas.drawLine(
        Offset(c.dx+(r+8)*cos(a), c.dy+(r+8)*sin(a)),
        Offset(c.dx+(r-4)*cos(a), c.dy+(r-4)*sin(a)),
        Paint()..color=Colors.white.withOpacity(0.2)..strokeWidth=1.5);
    }
  }
  @override bool shouldRepaint(covariant _ClockPainter old) => old.progress != progress;
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
    void openPaywall(){
      Analytics.noEnergyAction('bought_pro');
      Analytics.paywallShown('no_energy');
      Navigator.pop(context);
      showModalBottomSheet(context:context,isScrollControlled:true,backgroundColor:Colors.transparent,
        builder:(_)=>const PaywallSheet());
    }
    return Scaffold(backgroundColor:Pal.bg,body:Stack(children:[
      const StarField(),
      SafeArea(child:Column(children:[
        Padding(padding:const EdgeInsets.fromLTRB(16,12,16,0),
          child:Row(children:[_iconBtn(Icons.arrow_back,(){Analytics.noEnergyAction('left');Navigator.pop(context);})])),
        Expanded(child:Center(child:SingleChildScrollView(padding:const EdgeInsets.symmetric(horizontal:28,vertical:20),child:Column(mainAxisAlignment:MainAxisAlignment.center,children:[
          FadeTransition(opacity:_c,child:const Text('נגמרו המוחות!',
            style:TextStyle(color:Pal.tp,fontSize:26,fontWeight:FontWeight.w900))),
          const SizedBox(height:6),
          Text('🧠 ${e.energy}/${e.maxE}',style:const TextStyle(color:Pal.ts,fontSize:15)),
          const SizedBox(height:28),
          const _CountdownClock(),
          const SizedBox(height:28),
          if(e.canWatchAd)...[
            GestureDetector(
              onTap:(){Analytics.noEnergyAction('watched_ad');showDialog(context:context,builder:(_)=>_AdRewardDialog());},
              child:Container(
                width:double.infinity,
                padding:const EdgeInsets.symmetric(vertical:16),
                decoration:BoxDecoration(
                  color:Pal.gold.withOpacity(0.12),
                  border:Border.all(color:Pal.gold.withOpacity(0.6),width:1.5),
                  borderRadius:BorderRadius.circular(18)),
                child:const Column(children:[
                  Text('🎬  צפה בסרטון',style:TextStyle(color:Pal.gold,fontSize:17,fontWeight:FontWeight.w800)),
                  SizedBox(height:4),
                  Text('קבל 2 מוחות 🧠 מיידית',textDirection:TextDirection.rtl,style:TextStyle(color:Pal.ts,fontSize:13)),
                ]))),
            const SizedBox(height:14),
          ],
          if(!isPro)
            GestureDetector(
              onTap:openPaywall,
              child:Container(
                width:double.infinity,
                padding:const EdgeInsets.symmetric(vertical:16),
                decoration:BoxDecoration(
                  gradient:const LinearGradient(colors:[Color(0xFFFF9F0A),Color(0xFFFF6B00)]),
                  borderRadius:BorderRadius.circular(18),
                  boxShadow:[BoxShadow(color:Pal.premium.withOpacity(0.4),blurRadius:16,offset:const Offset(0,4))]),
                child:const Column(children:[
                  Text('👑  רכוש פרו',style:TextStyle(color:Colors.white,fontSize:17,fontWeight:FontWeight.w900)),
                  SizedBox(height:4),
                  Text('יותר מוחות · טעינה מהירה · ללא פרסומות',textDirection:TextDirection.rtl,style:TextStyle(color:Colors.white70,fontSize:12)),
                ]))),
          const SizedBox(height:20),
          _outBtn('חזרה',()=>Navigator.pop(context)),
        ])))),
      ])),
    ]));
  }
}

//  PAYWALL
// ═══════════════════════════════════════════════
class PaywallSheet extends StatefulWidget {
  const PaywallSheet({super.key});
  @override State<PaywallSheet> createState()=>_PS();
}
class _PS extends State<PaywallSheet>{
  String? _errMsg;
  @override void initState(){
    super.initState();
    PurchaseService.instance.addListener(_rebuild);
    // אם כבר פרמיום — סגור מיד (מניעת מצב שבו מסך הרכישה נפתח אחרי רכישה)
    WidgetsBinding.instance.addPostFrameCallback((_){
      if(mounted && PurchaseService.instance.isPremium) Navigator.pop(context);
    });
  }
  void _rebuild(){
    if(mounted){
      setState((){});
      // אם הרכישה הצליחה בזמן שהמסך פתוח — סגור
      if(PurchaseService.instance.isPremium) Navigator.pop(context);
    }
  }
  @override void dispose(){PurchaseService.instance.removeListener(_rebuild);super.dispose();}
  @override Widget build(BuildContext context){
    final ps=PurchaseService.instance;
    final bot=MediaQuery.of(context).padding.bottom;
    return Container(
      height:MediaQuery.of(context).size.height*0.88,
      decoration:const BoxDecoration(
        color:Color(0xFF080F1E),
        borderRadius:BorderRadius.vertical(top:Radius.circular(28))),
      child:Column(children:[
        // handle
        Container(margin:const EdgeInsets.only(top:12),width:40,height:4,
          decoration:BoxDecoration(color:Colors.white12,borderRadius:BorderRadius.circular(2))),
        Expanded(child:SingleChildScrollView(
          padding:const EdgeInsets.fromLTRB(24,24,24,0),
          child:Column(children:[
            // ── Crown ──────────────────────────────────────────────────────
            Container(width:80,height:80,
              decoration:BoxDecoration(shape:BoxShape.circle,
                gradient:const LinearGradient(
                  colors:[Color(0xFFFFD700),Color(0xFFFF9F0A)],
                  begin:Alignment.topLeft,end:Alignment.bottomRight),
                boxShadow:[BoxShadow(color:const Color(0xFFFFD700).withOpacity(0.4),blurRadius:28,spreadRadius:2)]),
              child:const Center(child:Text('👑',style:TextStyle(fontSize:40)))),
            const SizedBox(height:18),
            // ── Title ──────────────────────────────────────────────────────
            const Text('ידען פרו',
              style:TextStyle(color:Colors.white,fontSize:30,fontWeight:FontWeight.w900,letterSpacing:1)),
            const SizedBox(height:6),
            ShaderMask(
              shaderCallback:(b)=>const LinearGradient(
                colors:[Color(0xFFFFD700),Color(0xFFFF9F0A)]).createShader(b),
              child:const Text('שחק ללא גבולות',
                style:TextStyle(color:Colors.white,fontSize:16,fontWeight:FontWeight.w600))),
            const SizedBox(height:28),
            // ── Benefits ───────────────────────────────────────────────────
            _PBenefit(emoji:'🔴',title:'שלבים קשים — פתוחים',sub:'גישה לכל רמות הקושי'),
            const SizedBox(height:10),
            _PBenefit(emoji:'🧠',title:'50 מוחות מיידית',sub:'במקום 15 — כמעט פי 4'),
            const SizedBox(height:10),
            _PBenefit(emoji:'⚡',title:'טעינה מהירה פי 3',sub:'חזרה למשחק מהר יותר'),
            const SizedBox(height:10),
            _PBenefit(emoji:'🚫',title:'ללא פרסומות',sub:'חוויה נקייה ורציפה'),
            const SizedBox(height:10),
            _PBenefit(emoji:'📜',title:'בגרות בהיסטוריה',sub:'תרגול חכם לפי חולשות וחוזקות אישיות'),
            const SizedBox(height:10),
            _PBenefit(emoji:'🔓',title:'כל התכנים העתידיים',sub:'עדכונים, קטגוריות וניחוש מיוחדים'),
            const SizedBox(height:28),
            // ── Price badge ────────────────────────────────────────────────
            Container(
              width:double.infinity,
              padding:const EdgeInsets.symmetric(vertical:12),
              decoration:BoxDecoration(
                color:const Color(0xFFFFD700).withOpacity(0.08),
                borderRadius:BorderRadius.circular(14),
                border:Border.all(color:const Color(0xFFFFD700).withOpacity(0.25))),
              child:const Column(children:[
                Text('12.90 ₪ לחודש בלבד',textAlign:TextAlign.center,
                  textDirection:TextDirection.rtl,
                  style:TextStyle(color:Color(0xFFFFD700),fontSize:16,fontWeight:FontWeight.w800)),
                SizedBox(height:2),
                Text('ביטול בכל עת',textAlign:TextAlign.center,
                  style:TextStyle(color:Color(0xFF78909C),fontSize:12)),
              ])),
            const SizedBox(height:20),
          ]))),
        // ── Bottom bar ─────────────────────────────────────────────────────
        Padding(padding:EdgeInsets.fromLTRB(24,0,24,bot+16),
          child:Column(children:[
            if(_errMsg!=null)Padding(padding:const EdgeInsets.only(bottom:10),
              child:Text(_errMsg!,textAlign:TextAlign.center,
                style:const TextStyle(color:Pal.red,fontSize:13))),
            if(ps.isLoading)
              const Padding(padding:EdgeInsets.symmetric(vertical:14),
                child:CircularProgressIndicator(color:Color(0xFFFFD700)))
            else GestureDetector(
              onTap:()async{
                // אם כבר פרמיום — סגור מיד (מניעת רכישה כפולה)
                if(ps.isPremium){Navigator.pop(context);return;}
                setState(()=>_errMsg=null);
                if(ps.packages.isEmpty) await ps.loadOfferings();
                if(!mounted)return;
                if(ps.packages.isEmpty){
                  setState(()=>_errMsg='לא ניתן לטעון מוצרים. בדוק חיבור לאינטרנט ונסה שוב.');
                  return;
                }
                try{
                  final ok=await ps.purchase(ps.packages.first);
                  if(!mounted)return;
                  if(ok) Navigator.pop(context);
                }on PurchasesError catch(e){
                  if(!mounted)return;
                  setState(()=>_errMsg='שגיאת רכישה: ${e.message}');
                }catch(e){
                  if(!mounted)return;
                  setState(()=>_errMsg='שגיאה: $e');
                }
              },
              child:Container(width:double.infinity,
                padding:const EdgeInsets.symmetric(vertical:17),
                decoration:BoxDecoration(
                  gradient:const LinearGradient(
                    colors:[Color(0xFFFFD700),Color(0xFFFF9F0A)],
                    begin:Alignment.topLeft,end:Alignment.bottomRight),
                  borderRadius:BorderRadius.circular(18),
                  boxShadow:[BoxShadow(color:const Color(0xFFFFD700).withOpacity(0.35),blurRadius:18,offset:const Offset(0,4))]),
                child:const Text('התחל עכשיו — ‏12.90 ₪ לחודש',
                  textAlign:TextAlign.center,textDirection:TextDirection.rtl,
                  style:TextStyle(color:Colors.black,fontSize:16,fontWeight:FontWeight.w900)))),
            const SizedBox(height:12),
            GestureDetector(
              onTap:()async{
                final ok=await ps.restore();
                if(mounted){
                  Navigator.pop(context);
                  if(ok)ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content:Text('✅ הרכישה שוחזרה!'),backgroundColor:Pal.green));
                }
              },
              child:const Text('שחזר רכישות',
                style:TextStyle(color:Color(0xFF546E7A),fontSize:13,decoration:TextDecoration.underline))),
            const SizedBox(height:16),
            Text(
              defaultTargetPlatform==TargetPlatform.iOS
                ? 'המנוי מתחדש אוטומטית ב־12.90 ₪ לחודש אלא אם כן בוטל לפחות 24 שעות לפני סוף התקופה. ניתן לנהל ולבטל את המנוי בהגדרות ה־Apple ID שלך.'
                : 'המנוי מתחדש אוטומטית ב־12.90 ₪ לחודש אלא אם כן בוטל לפחות 24 שעות לפני סוף התקופה. ניתן לנהל ולבטל את המנוי בהגדרות Google Play שלך.',
              textAlign:TextAlign.center,
              textDirection:TextDirection.rtl,
              style:const TextStyle(color:Pal.ts,fontSize:11)),
            const SizedBox(height:8),
            Row(mainAxisAlignment:MainAxisAlignment.center,children:[
              GestureDetector(
                onTap:()=>_launchUrl('https://sites.google.com/view/yadaan-privacy/%D7%91%D7%99%D7%AA'),
                child:const Text('מדיניות פרטיות',style:TextStyle(color:Pal.ts,fontSize:11,decoration:TextDecoration.underline))),
              const Text('  |  ',style:TextStyle(color:Pal.ts,fontSize:11)),
              GestureDetector(
                onTap:()=>_launchUrl('https://sites.google.com/view/yadaan-terms-of-use/%D7%91%D7%99%D7%AA'),
                child:const Text('תנאי שימוש',style:TextStyle(color:Pal.ts,fontSize:11,decoration:TextDecoration.underline))),
            ]),
            const SizedBox(height:8),

          ])),
      ]));
  }
}

class _PBenefit extends StatelessWidget {
  final String emoji, title, sub;
  const _PBenefit({required this.emoji, required this.title, required this.sub});
  @override Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    decoration: BoxDecoration(
      color: const Color(0xFF0E1A2E),
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: Colors.white.withOpacity(0.06))),
    child: Row(children: [
      Text(emoji, style: const TextStyle(fontSize: 22)),
      const SizedBox(width: 14),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, textDirection: TextDirection.rtl,
          style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700)),
        const SizedBox(height: 2),
        Text(sub, textDirection: TextDirection.rtl,
          style: const TextStyle(color: Color(0xFF78909C), fontSize: 12)),
      ])),
      const Icon(Icons.check_circle_rounded, color: Color(0xFF2ECC71), size: 18),
    ]),
  );
}


// ══════════════════════════════════════════════════
//  CATEGORY SELECT SCREEN
// ══════════════════════════════════════════════════
class CategorySelectScreen extends StatelessWidget {
  const CategorySelectScreen({super.key});

  static const _cats = [
    ('israel',         'ישראל',          '🇮🇱', Color(0xFF4D96FF)),
    ('judaism',        'יהדות',          '✡️',  Color(0xFF7C6FE0)),
    ('tv',             'טלוויזיה',       '📺',  Color(0xFF9B59B6)),
    ('music',          'מוזיקה',         '🎵',  Color(0xFFE91E8C)),
    ('sports',         'ספורט',          '⚽',  Color(0xFFE74C3C)),
    ('geography',      'גיאוגרפיה',      '🌍',  Color(0xFF2ECC71)),
    ('science',        'מדע',            '🔬',  Color(0xFF3498DB)),
    ('world',          'תרבות עולמית',   '🎬',  Color(0xFFE67E22)),
    ('american_music', 'מוזיקה אמריקאית', '🎸',  Color(0xFFD35400)),
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
    Analytics.categoryQuizStarted(widget.category);
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
      // KD + XP
      UserStatsService.instance.recordAnswer(correct: true, diffIndex: _cur.diff.index);
      InterestsService.instance.recordAnswer(category: _cur.category, correct: true);
      setState(() {
        _score += 10 + _cur.diff.index*5 + _streak*2;
        _correct++; _streak++;
        if (_streak > _bestStreak) _bestStreak = _streak;
      });
    } else {
      await Sfx.wrong();
      // KD + חולשות
      UserStatsService.instance.recordAnswer(correct: false, diffIndex: _cur.diff.index);
      InterestsService.instance.recordAnswer(category: _cur.category, correct: false);
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
      onBack: (){Analytics.categoryQuizCompleted(category:widget.category,correct:_correct,total:_maxQ);Navigator.pop(context);});

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
                        Text(_cur.f!,textDirection:TextDirection.rtl,style:const TextStyle(color:Pal.ts,fontSize:12,height:1.4)),
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

  Future<void> _maybeRequestReview() async {
    final pct = widget.correct / widget.total;
    if (pct < 0.5) return;
    try {
      final p = await SharedPreferences.getInstance();
      final completed = (p.getInt('levels_completed') ?? 0) + 1;
      await p.setInt('levels_completed', completed);

      // דיאלוג "נהנית?" — מוצג פעם אחת בלבד
      final shownReview = p.getBool('review_dialog_shown') ?? false;
      if (!shownReview) {
        await p.setBool('review_dialog_shown', true);
        await Future.delayed(const Duration(milliseconds: 1500));
        if (!mounted) return;
        final enjoyed = await showDialog<bool?>(
          context: context,
          barrierDismissible: false,
          builder: (_) => const _EnjoyedDialog(),
        );
        await NotificationService.requestPermission();
        if (enjoyed == true) {
          FirebaseAnalytics.instance.logEvent(name: 'review_prompt_yes');
          final review = InAppReview.instance;
          if (await review.isAvailable()) {
            await review.requestReview();
          } else {
            await review.openStoreListing();
          }
        } else if (enjoyed == false) {
          FirebaseAnalytics.instance.logEvent(name: 'review_prompt_no');
        } else {
          FirebaseAnalytics.instance.logEvent(name: 'review_prompt_skip');
        }
        return;
      }

      // שלבים 10 ו-30 — פופ-אפ ישיר
      if (completed == 10 || completed == 30) {
        await Future.delayed(const Duration(milliseconds: 300));
        final review = InAppReview.instance;
        if (await review.isAvailable()) await review.requestReview();
      }
    } catch (_) {}
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
        Text(q.q,textDirection:TextDirection.rtl,style:const TextStyle(color:Pal.tp,fontSize:20,fontWeight:FontWeight.w700,height:1.4)),
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
            Expanded(child:Text(widget.q.a[widget.index],textDirection:TextDirection.rtl,style:TextStyle(color:widget.fb&&widget.index!=widget.q.c&&widget.index!=widget.sel?Pal.ts:Pal.tp,fontSize:16,fontWeight:FontWeight.w600))),
            if(widget.fb)Text(widget.index==widget.q.c?'✅':widget.index==widget.sel?'❌':'',style:const TextStyle(fontSize:18)),
          ]))));
  }
}

// ═══════════════════════════════════════════════
//  ENJOYED DIALOG
// ═══════════════════════════════════════════════
class _EnjoyedDialog extends StatelessWidget {
  const _EnjoyedDialog();
  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Dialog(
        backgroundColor: Pal.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('😊', style: TextStyle(fontSize: 48)),
            const SizedBox(height: 12),
            const Text('נהנית עד עכשיו?',
              style: TextStyle(color: Pal.tp, fontSize: 20, fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            const Text('נשמח לדירוג קטן שיעזור לנו לגדול',
              textAlign: TextAlign.center,
              style: TextStyle(color: Pal.ts, fontSize: 14)),
            const SizedBox(height: 24),
            Row(children: [
              Expanded(child: GestureDetector(
                onTap: () => Navigator.pop(context, false),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  decoration: BoxDecoration(
                    color: Pal.cardL,
                    borderRadius: BorderRadius.circular(14)),
                  child: const Text('לא 😕',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Pal.ts, fontSize: 15, fontWeight: FontWeight.w700))))),
              const SizedBox(width: 10),
              Expanded(child: GestureDetector(
                onTap: () => Navigator.pop(context, true),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(colors: [Color(0xFFFF9F0A), Color(0xFFFF6B00)]),
                    borderRadius: BorderRadius.circular(14)),
                  child: const Text('כן 😊',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w800))))),
            ]),
            const SizedBox(height: 10),
            GestureDetector(
              onTap: () => Navigator.pop(context, null),
              child: const Padding(
                padding: EdgeInsets.symmetric(vertical: 6),
                child: Text('דלג', style: TextStyle(color: Pal.ts, fontSize: 13, decoration: TextDecoration.underline)))),
          ]),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════
//  HELPERS
// ═══════════════════════════════════════════════
Widget _iconBtn(IconData icon,VoidCallback onTap)=>GestureDetector(onTap:onTap,child:Container(padding:const EdgeInsets.all(10),decoration:BoxDecoration(color:Pal.card,borderRadius:BorderRadius.circular(12),border:Border.all(color:Pal.ts.withOpacity(0.2))),child:Icon(icon,color:Pal.ts,size:20)));
Widget _bigBtn(String l,Color c,VoidCallback t)=>GestureDetector(onTap:t,child:Container(width:double.infinity,padding:const EdgeInsets.symmetric(vertical:18),decoration:BoxDecoration(gradient:LinearGradient(colors:[c,c.withOpacity(0.7)]),borderRadius:BorderRadius.circular(18),boxShadow:[BoxShadow(color:c.withOpacity(0.4),blurRadius:16,offset:const Offset(0,6))]),child:Text(l,textAlign:TextAlign.center,style:const TextStyle(color:Colors.white,fontSize:18,fontWeight:FontWeight.w800))));
Widget _outBtn(String l,VoidCallback t)=>GestureDetector(onTap:t,child:Container(width:double.infinity,padding:const EdgeInsets.symmetric(vertical:16),decoration:BoxDecoration(borderRadius:BorderRadius.circular(18),border:Border.all(color:Pal.ts.withOpacity(0.4))),child:Text(l,textAlign:TextAlign.center,style:const TextStyle(color:Pal.ts,fontSize:16,fontWeight:FontWeight.w700))));
PageRouteBuilder _slide(Widget p)=>PageRouteBuilder(pageBuilder:(_,__,___)=>p,transitionsBuilder:(_,a,__,child)=>SlideTransition(position:Tween(begin:const Offset(1,0),end:Offset.zero).animate(CurvedAnimation(parent:a,curve:Curves.easeOutCubic)),child:child),transitionDuration:const Duration(milliseconds:350));