// ════════════════════════════════════════════════════
//  Trivio — World Version (English)
//  שים קובץ זה ב: lib/main.dart
//  שים גם: questions_easy_en.dart, questions_medium_en.dart, questions_hard_en.dart
//  (צור קבצים אלה עם שאלות אנגלית כשתהיה מוכן)
// ════════════════════════════════════════════════════
import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

// כשתוסיף שאלות אנגלית — פשוט הוסף את הקבצים ובטל את ה-//
// import 'questions_easy_en.dart';
// import 'questions_medium_en.dart';
// import 'questions_hard_en.dart';

// ─── PLACEHOLDER — מחק כשתוסיף קבצי שאלות אמיתיים ───
const String kEasy   = '[]';
const String kMedium = '[]';
const String kHard   = '[]';

// ─── ALL STRINGS IN ENGLISH ───
class S {
  static const appName      = 'QuizMaster';
  static const startBtn     = '▶  START QUIZ';
  static const catLbl       = 'CATEGORY';
  static const diffLbl      = 'DIFFICULTY';
  static const allCat       = 'All';
  static const questionsLbl = 'Questions';
  static const catsLbl      = 'Categories';
  static const levelsLbl    = 'Levels';
  static const unlockHard   = 'Unlock Hard Mode';
  static const unlockBtn    = 'UNLOCK';
  static const proLbl       = '⭐ PRO';
  static const pointsLbl    = 'POINTS';
  static const correctLbl   = '✅ Correct';
  static const streakLbl    = '🔥 Streak';
  static const accuracyLbl  = '🎯 Accuracy';
  static const byCatLbl     = 'BY CATEGORY';
  static const playAgain    = '🔄  Play Again';
  static const homeLbl      = '🏠  Home';
  static const restoreLbl   = 'Restore purchases';
  static const cancelLbl    = 'Cancel anytime · Billed via App Store';
  static const codeHint     = 'Have an access code?';
  static const codeField    = 'Enter code...';
  static const codeOk       = 'OK';
  static const codeSuccess  = 'Code accepted! All content unlocked 🎉';
  static const codeWrong    = 'Wrong code';
  static const ansCorrect   = 'Correct!';
  static const ansWrong     = 'Answer:';
  static const proTitle     = 'QuizMaster Pro';
  static const upgradeTitle = 'Want more?';

  static String diffLabel(int d)  => ['','Easy','Medium','Hard'][d.clamp(0,3)];
  static String planLabel(int i)  => ['Monthly','Yearly','Lifetime'][i];
  static String planPrice(int i)  => [r'$2.99/mo',r'$19.99/yr',r'$14.99'][i];
  static String planSaving(int i) => ['','Save 44%','Best Value'][i];
  static String ptsLabel(int p,int s) => s>=2?'+$p pts  🔥+${s*2}':'+$p pts';
  static String premCount(int n)  => '+$n Hard questions';
  static String upgradeMsg(int n) => 'Unlock +$n Hard questions!';
  static String gradeMsg(String g) {
    switch(g) {
      case 'S': return 'Absolutely brilliant! 🏆';
      case 'A': return 'Excellent performance! 🎯';
      case 'B': return 'Good job! Keep it up! 💪';
      case 'C': return 'Not bad! Room to grow! 📖';
      default:  return 'Keep practising! 💡';
    }
  }
}

// ─── CATEGORIES (English) ───
class Cat {
  static const colors = <String,Color>{
    'history':   Color(0xFFE67E22), 'science':   Color(0xFF3498DB),
    'geography': Color(0xFF2ECC71), 'arts':      Color(0xFFE91E8C),
    'sports':    Color(0xFFE74C3C), 'pop':       Color(0xFF9B59B6),
    'tech':      Color(0xFF1ABC9C), 'literature':Color(0xFFF39C12),
  };
  static const emojis = <String,String>{
    'history':'🏛️','science':'🔬','geography':'🌍','arts':'🎭',
    'sports':'⚽','pop':'🎬','tech':'💻','literature':'📚',
  };
  static const names = <String,String>{
    'history':'History','science':'Science','geography':'Geography','arts':'Arts',
    'sports':'Sports','pop':'Pop Culture','tech':'Tech','literature':'Literature',
  };
  static Color  color(String c) => colors[c]  ?? const Color(0xFF7C6FE0);
  static String emoji(String c) => emojis[c]  ?? '❓';
  static String name(String c)  => names[c]   ?? (c[0].toUpperCase()+c.substring(1));
}

// ─── CONFIG ───
class AppConfig {
  static const rcAndroid     = 'YOUR_REVENUECAT_ANDROID_KEY';
  static const rciOS         = 'YOUR_REVENUECAT_IOS_KEY';
  static const entitlement   = 'premium';
  static const mockPremium   = false;
  static const devUnlockCode = 'shmuel1231';
}

// ─── PURCHASE SERVICE ───
class PurchaseService extends ChangeNotifier {
  static final PurchaseService _i = PurchaseService._();
  static PurchaseService get instance => _i;
  PurchaseService._();
  bool _isPremium=false, _loading=false, _dev=false;
  List<Package> _packages=[];
  bool get isPremium => _isPremium||_dev;
  bool get isLoading => _loading;
  List<Package> get packages => _packages;

  bool tryDevUnlock(String code) {
    if(code!=AppConfig.devUnlockCode) return false;
    _dev=true; notifyListeners(); return true;
  }

  static Future<void> init() async {
    if(AppConfig.mockPremium){_i._isPremium=true;return;}
    try {
      await Purchases.setLogLevel(LogLevel.debug);
      await Purchases.configure(PurchasesConfiguration(
        defaultTargetPlatform==TargetPlatform.iOS?AppConfig.rciOS:AppConfig.rcAndroid));
      final ci=await Purchases.getCustomerInfo();
      _i._isPremium=ci.entitlements.all[AppConfig.entitlement]?.isActive??false;
      _i.notifyListeners();
    } catch(e){debugPrint('RC: $e');}
  }

  Future<void> loadOfferings() async {
    _loading=true; notifyListeners();
    try{final o=await Purchases.getOfferings();_packages=o.current?.availablePackages??[];}catch(_){}
    _loading=false; notifyListeners();
  }

  Future<bool> purchase(Package pkg) async {
    _loading=true; notifyListeners();
    try {
      final ci=await Purchases.purchasePackage(pkg);
      _isPremium=ci.entitlements.all[AppConfig.entitlement]?.isActive??false;
      _loading=false; notifyListeners(); return _isPremium;
    } on PurchasesErrorCode catch(e) {
      if(e!=PurchasesErrorCode.purchaseCancelledError) debugPrint('purchase failed');
      _loading=false; notifyListeners(); return false;
    }
  }

  Future<bool> restore() async {
    _loading=true; notifyListeners();
    try {
      final ci=await Purchases.restorePurchases();
      _isPremium=ci.entitlements.all[AppConfig.entitlement]?.isActive??false;
      _loading=false; notifyListeners(); return _isPremium;
    } catch(_){_loading=false;notifyListeners();return false;}
  }
}

// ─── MAIN ───
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp,DeviceOrientation.portraitDown]);
  await PurchaseService.init();
  runApp(const QuizMasterApp());
}

class QuizMasterApp extends StatelessWidget {
  const TrivioApp({super.key});
  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable:PurchaseService.instance,
      builder:(_,__)=>MaterialApp(
        title: 'QuizMaster', debugShowCheckedModeBanner: false,
        theme:ThemeData.dark().copyWith(scaffoldBackgroundColor:Pal.bg,colorScheme:const ColorScheme.dark(primary:Pal.gold),useMaterial3:true),
        home:const HomeScreen()));
  }
}

// ─── PALETTE ───
class Pal {
  static const bg=Color(0xFF0D0D1A),card=Color(0xFF1E1E36),gold=Color(0xFFFFD700);
  static const accent=Color(0xFF7C6FE0),green=Color(0xFF2ECC71),red=Color(0xFFE74C3C);
  static const premium=Color(0xFFFF9F0A),tp=Color(0xFFF0F0FF),ts=Color(0xFF8888AA);
  static Color diff(int d)=>[Colors.transparent,green,const Color(0xFFF39C12),red][d.clamp(0,3)];
}

// ─── DATA MODEL ───
class Question {
  final String id,category,q; final List<String> a; final int c,d; final String? f;
  const Question({required this.id,required this.category,required this.q,required this.a,required this.c,this.d=1,this.f});
  factory Question.fromMap(Map<String,dynamic> m)=>Question(id:m['id'],category:m['category'],q:m['q'],a:List<String>.from(m['a']),c:m['c'],d:m['d']??1,f:m['f']);
  int get points=>d*10;
}

// ─── REPOSITORY ───
class QRepo {
  static List<Question>? _free,_prem;
  static List<Question> get free {
    if(_free==null){
      final e=(jsonDecode(kEasy) as List).map((x)=>Question.fromMap(x)).toList();
      final m=(jsonDecode(kMedium) as List).map((x)=>Question.fromMap(x)).toList();
      _free=[...e,...m];
    }
    return _free!;
  }
  static List<Question> get premium {
    _prem??=(jsonDecode(kHard) as List).map((x)=>Question.fromMap(x)).toList();
    return _prem!;
  }
  static List<Question> all(bool p)=>p?[...free,...premium]:free;
  static List<String> get categories=>all(true).map((q)=>q.category).toSet().toList()..sort();
  static List<Question> forGame(String cat,int maxD,bool prem){
    final pool=all(prem).where((q)=>(cat=='all'||q.category==cat)&&q.d<=maxD).toList()..shuffle(Random());
    return pool.take(min(15,pool.length)).toList();
  }
  static int total(bool p)=>p?free.length+premium.length:free.length;
}

// ─── GAME STATE ───
enum Ans{waiting,correct,wrong}
class GameState extends ChangeNotifier {
  String cat='all'; int maxD=2,score=0,streak=0,best=0,idx=0;
  List<Question> questions=[]; Ans ans=Ans.waiting; int? sel; List<bool> results=[];
  void start({String c='all',int d=2,bool prem=false}){cat=c;maxD=d;score=streak=best=idx=0;questions=QRepo.forGame(c,d,prem);ans=Ans.waiting;sel=null;results=[];notifyListeners();}
  Question get cur=>questions[idx];
  bool get done=>idx>=questions.length;
  double get progress=>questions.isEmpty?0:idx/questions.length;
  int get correct=>results.where((r)=>r).length;
  void answer(int i){if(ans!=Ans.waiting)return;sel=i;final ok=i==cur.c;results.add(ok);if(ok){score+=cur.points+streak*2;streak++;if(streak>best)best=streak;ans=Ans.correct;}else{streak=0;ans=Ans.wrong;}notifyListeners();}
  void next(){idx++;ans=Ans.waiting;sel=null;notifyListeners();}
}

// ─── HOME SCREEN ───
class HomeScreen extends StatefulWidget{const HomeScreen({super.key});@override State<HomeScreen> createState()=>_HomeState();}
class _HomeState extends State<HomeScreen> with SingleTickerProviderStateMixin {
  late final AnimationController _glow; String _cat='all'; int _diff=2;
  bool get _pro=>PurchaseService.instance.isPremium;
  @override void initState(){super.initState();_glow=AnimationController(vsync:this,duration:const Duration(seconds:3))..repeat(reverse:true);PurchaseService.instance.addListener((){if(mounted)setState((){});});}
  @override void dispose(){_glow.dispose();super.dispose();}

  void _start(){if(!_pro&&_diff==3){_paywall();return;}Navigator.push(context,_Slide(QuizScreen(gs:GameState()..start(c:_cat,d:_diff,prem:_pro))));}
  void _paywall()=>showModalBottomSheet(context:context,isScrollControlled:true,backgroundColor:Colors.transparent,builder:(_)=>PaywallSheet(onCode:(code){final ok=PurchaseService.instance.tryDevUnlock(code);Navigator.pop(context);ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(ok?S.codeSuccess:S.codeWrong),backgroundColor:ok?Pal.green:Pal.red));}));

  @override Widget build(BuildContext context)=>Scaffold(body:Container(decoration:const BoxDecoration(gradient:RadialGradient(center:Alignment(0,-0.5),radius:1.2,colors:[Color(0xFF1A1A3E),Color(0xFF0D0D1A)])),child:SafeArea(child:SingleChildScrollView(padding:const EdgeInsets.symmetric(horizontal:24,vertical:20),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[_header(),const SizedBox(height:20),if(!_pro)...[_banner(),const SizedBox(height:20)],_lbl(S.catLbl),const SizedBox(height:12),_catGrid(),const SizedBox(height:28),_lbl(S.diffLbl),const SizedBox(height:12),_diffRow(),const SizedBox(height:40),_startBtn(),const SizedBox(height:20),_stats()])))));

  Widget _header()=>AnimatedBuilder(animation:_glow,builder:(_,__)=>Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Row(children:[ShaderMask(shaderCallback:(b)=>LinearGradient(colors:[Pal.gold,Color.lerp(Pal.gold,Pal.accent,_glow.value)!,Pal.gold]).createShader(b),child:const Text(S.appName,style:TextStyle(fontSize:56,fontWeight:FontWeight.w900,color:Colors.white,letterSpacing:3))),const Spacer(),if(_pro)Container(padding:const EdgeInsets.symmetric(horizontal:12,vertical:6),decoration:BoxDecoration(gradient:const LinearGradient(colors:[Color(0xFFFF9F0A),Color(0xFFFF6B00)]),borderRadius:BorderRadius.circular(20),boxShadow:[BoxShadow(color:Pal.premium.withOpacity(0.5),blurRadius:12)]),child:const Text(S.proLbl,style:TextStyle(color:Colors.white,fontWeight:FontWeight.w900,fontSize:13)))]),const SizedBox(height:6),Text('${QRepo.total(_pro)} ${S.questionsLbl} · ${QRepo.categories.length} ${S.catsLbl}',style:const TextStyle(color:Pal.ts,fontSize:14))]));

  Widget _banner()=>GestureDetector(onTap:_paywall,child:Container(padding:const EdgeInsets.all(16),decoration:BoxDecoration(gradient:LinearGradient(colors:[Pal.premium.withOpacity(0.2),Pal.accent.withOpacity(0.2)]),borderRadius:BorderRadius.circular(18),border:Border.all(color:Pal.premium.withOpacity(0.5),width:1.5)),child:Row(children:[const Text('👑',style:TextStyle(fontSize:28)),const SizedBox(width:12),Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[const Text(S.unlockHard,style:TextStyle(color:Pal.tp,fontWeight:FontWeight.w800,fontSize:15)),const SizedBox(height:2),Text(S.premCount(QRepo.premium.length),style:const TextStyle(color:Pal.ts,fontSize:12))])),Container(padding:const EdgeInsets.symmetric(horizontal:12,vertical:6),decoration:BoxDecoration(color:Pal.premium,borderRadius:BorderRadius.circular(10)),child:const Text(S.unlockBtn,style:TextStyle(color:Colors.white,fontWeight:FontWeight.w900,fontSize:12)))])));

  Widget _lbl(String t)=>Text(t,style:const TextStyle(color:Pal.gold,fontSize:11,fontWeight:FontWeight.w700,letterSpacing:2));

  Widget _catGrid(){final cats=['all',...QRepo.categories];return Wrap(spacing:10,runSpacing:10,children:cats.map((cat){final sel=cat==_cat;final color=cat=='all'?Pal.gold:Cat.color(cat);return GestureDetector(onTap:()=>setState(()=>_cat=cat),child:AnimatedContainer(duration:const Duration(milliseconds:200),padding:const EdgeInsets.symmetric(horizontal:14,vertical:10),decoration:BoxDecoration(color:sel?color:Pal.card,borderRadius:BorderRadius.circular(14),border:Border.all(color:sel?color:color.withOpacity(0.3),width:1.5),boxShadow:sel?[BoxShadow(color:color.withOpacity(0.4),blurRadius:12)]:[]),child:Row(mainAxisSize:MainAxisSize.min,children:[Text(cat=='all'?'🌐':Cat.emoji(cat),style:const TextStyle(fontSize:16)),const SizedBox(width:6),Text(cat=='all'?S.allCat:Cat.name(cat),style:TextStyle(color:sel?Colors.white:Pal.ts,fontWeight:FontWeight.w700,fontSize:13))])));}).toList());}

  Widget _diffRow()=>Row(children:[1,2,3].map((d){final locked=d==3&&!_pro;final sel=d==_diff;final color=Pal.diff(d);return Expanded(child:Padding(padding:EdgeInsets.only(right:d<3?10:0),child:GestureDetector(onTap:(){if(locked){_paywall();return;}setState(()=>_diff=d);},child:AnimatedContainer(duration:const Duration(milliseconds:200),padding:const EdgeInsets.symmetric(vertical:14),decoration:BoxDecoration(color:sel?color:Pal.card,borderRadius:BorderRadius.circular(14),border:Border.all(color:sel?color:color.withOpacity(0.3),width:1.5),boxShadow:sel?[BoxShadow(color:color.withOpacity(0.4),blurRadius:12)]:[]),child:Column(children:[Text(locked?'🔒':['','🟢','🟡','🔴'][d],style:const TextStyle(fontSize:22)),const SizedBox(height:4),Text(S.diffLabel(d),style:TextStyle(color:sel?Colors.white:Pal.ts,fontWeight:FontWeight.w700,fontSize:13)),if(locked)const Text('PRO',style:TextStyle(color:Pal.premium,fontSize:9,fontWeight:FontWeight.w900))])))))).toList());

  Widget _startBtn()=>GestureDetector(onTap:_start,child:Container(width:double.infinity,padding:const EdgeInsets.symmetric(vertical:20),decoration:BoxDecoration(gradient:const LinearGradient(colors:[Color(0xFF7C6FE0),Color(0xFF4D96FF)]),borderRadius:BorderRadius.circular(20),boxShadow:[BoxShadow(color:Pal.accent.withOpacity(0.5),blurRadius:20,offset:const Offset(0,6))]),child:const Text(S.startBtn,textAlign:TextAlign.center,style:TextStyle(fontSize:22,fontWeight:FontWeight.w900,color:Colors.white,letterSpacing:2))));

  Widget _stats()=>Container(padding:const EdgeInsets.all(16),decoration:BoxDecoration(color:Pal.card,borderRadius:BorderRadius.circular(16),border:Border.all(color:Pal.gold.withOpacity(0.15))),child:Row(mainAxisAlignment:MainAxisAlignment.spaceAround,children:[_si('📚','${QRepo.total(_pro)}',S.questionsLbl),_div(),_si('🏷️','${QRepo.categories.length}',S.catsLbl),_div(),_si('🎯',_pro?'3':'2',S.levelsLbl)]));
  Widget _si(String e,String v,String l)=>Column(children:[Text(e,style:const TextStyle(fontSize:24)),const SizedBox(height:4),Text(v,style:const TextStyle(color:Pal.gold,fontSize:20,fontWeight:FontWeight.w900)),Text(l,style:const TextStyle(color:Pal.ts,fontSize:11))]);
  Widget _div()=>Container(width:1,height:50,color:Pal.ts.withOpacity(0.2));
}

// ─── PAYWALL, QUIZ, RESULT, NAV ─── (same engine as IL, English strings)
class PaywallSheet extends StatefulWidget{final void Function(String) onCode;const PaywallSheet({super.key,required this.onCode});@override State<PaywallSheet> createState()=>_PaywallState();}
class _PaywallState extends State<PaywallSheet>{int _plan=1;bool _showCode=false;final _ctrl=TextEditingController();@override void dispose(){_ctrl.dispose();super.dispose();}
@override Widget build(BuildContext context){final ps=PurchaseService.instance;return Container(height:MediaQuery.of(context).size.height*0.85,decoration:const BoxDecoration(color:Color(0xFF12122A),borderRadius:BorderRadius.vertical(top:Radius.circular(28))),child:Column(children:[Container(margin:const EdgeInsets.only(top:12),width:40,height:4,decoration:BoxDecoration(color:Pal.ts.withOpacity(0.4),borderRadius:BorderRadius.circular(2))),Expanded(child:SingleChildScrollView(padding:const EdgeInsets.fromLTRB(24,20,24,0),child:Column(children:[Container(width:72,height:72,decoration:BoxDecoration(shape:BoxShape.circle,gradient:const LinearGradient(colors:[Color(0xFFFF9F0A),Color(0xFFFF6B00)]),boxShadow:[BoxShadow(color:Pal.premium.withOpacity(0.5),blurRadius:20)]),child:const Center(child:Text('👑',style:TextStyle(fontSize:36)))),const SizedBox(height:16),const Text(S.proTitle,style:TextStyle(color:Pal.tp,fontSize:28,fontWeight:FontWeight.w900)),const SizedBox(height:6),Text(S.premCount(QRepo.premium.length),textAlign:TextAlign.center,style:const TextStyle(color:Pal.ts,fontSize:14)),const SizedBox(height:24),Row(children:List.generate(3,(i){final sel=i==_plan;return Expanded(child:Padding(padding:EdgeInsets.only(right:i<2?8:0),child:GestureDetector(onTap:()=>setState(()=>_plan=i),child:AnimatedContainer(duration:const Duration(milliseconds:200),padding:const EdgeInsets.symmetric(vertical:16,horizontal:4),decoration:BoxDecoration(color:sel?Pal.premium.withOpacity(0.15):Pal.card,borderRadius:BorderRadius.circular(14),border:Border.all(color:sel?Pal.premium:Pal.ts.withOpacity(0.2),width:sel?2:1)),child:Column(children:[Text(['📅','📆','♾️'][i],style:const TextStyle(fontSize:22)),const SizedBox(height:6),Text(S.planLabel(i),style:TextStyle(color:sel?Pal.tp:Pal.ts,fontSize:13,fontWeight:FontWeight.w700)),const SizedBox(height:2),Text(S.planPrice(i),style:TextStyle(color:sel?Pal.premium:Pal.ts,fontSize:11,fontWeight:FontWeight.w600)),if(S.planSaving(i).isNotEmpty)...[const SizedBox(height:4),Container(padding:const EdgeInsets.symmetric(horizontal:6,vertical:2),decoration:BoxDecoration(color:Pal.green.withOpacity(0.2),borderRadius:BorderRadius.circular(6)),child:Text(S.planSaving(i),style:const TextStyle(color:Pal.green,fontSize:9,fontWeight:FontWeight.w800)))]]))));})),const SizedBox(height:20),GestureDetector(onTap:()=>setState(()=>_showCode=!_showCode),child:Text(S.codeHint,style:TextStyle(color:Pal.ts.withOpacity(0.6),fontSize:12,decoration:TextDecoration.underline))),if(_showCode)...[const SizedBox(height:12),Row(children:[Expanded(child:TextField(controller:_ctrl,style:const TextStyle(color:Pal.tp),decoration:InputDecoration(hintText:S.codeField,hintStyle:const TextStyle(color:Pal.ts),filled:true,fillColor:Pal.card,border:OutlineInputBorder(borderRadius:BorderRadius.circular(12)),contentPadding:const EdgeInsets.symmetric(horizontal:16,vertical:12)))),const SizedBox(width:10),GestureDetector(onTap:()=>widget.onCode(_ctrl.text.trim()),child:Container(padding:const EdgeInsets.symmetric(horizontal:16,vertical:14),decoration:BoxDecoration(color:Pal.accent,borderRadius:BorderRadius.circular(12)),child:const Text(S.codeOk,style:TextStyle(color:Colors.white,fontWeight:FontWeight.w900))))])],const SizedBox(height:20)]))),Padding(padding:EdgeInsets.fromLTRB(24,0,24,MediaQuery.of(context).padding.bottom+16),child:Column(children:[if(ps.isLoading)const CircularProgressIndicator(color:Pal.premium) else GestureDetector(onTap:() async{await ps.loadOfferings();if(ps.packages.isNotEmpty&&mounted){final pkg=ps.packages[_plan.clamp(0,ps.packages.length-1)];final ok=await ps.purchase(pkg);if(ok&&mounted)Navigator.pop(context);}},child:Container(width:double.infinity,padding:const EdgeInsets.symmetric(vertical:18),decoration:BoxDecoration(gradient:const LinearGradient(colors:[Color(0xFFFF9F0A),Color(0xFFFF6B00)]),borderRadius:BorderRadius.circular(18),boxShadow:[BoxShadow(color:Pal.premium.withOpacity(0.5),blurRadius:16,offset:const Offset(0,4))]),child:Text('${S.planLabel(_plan)} — ${S.planPrice(_plan)}',textAlign:TextAlign.center,style:const TextStyle(color:Colors.white,fontSize:16,fontWeight:FontWeight.w900)))),const SizedBox(height:10),GestureDetector(onTap:() async{final ok=await ps.restore();if(mounted){Navigator.pop(context);if(ok)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('✅ Restored!'),backgroundColor:Pal.green));}},child:const Text(S.restoreLbl,style:TextStyle(color:Pal.ts,fontSize:13,decoration:TextDecoration.underline))),const SizedBox(height:8),const Text(S.cancelLbl,textAlign:TextAlign.center,style:TextStyle(color:Pal.ts,fontSize:11))]))]));}
}

class QuizScreen extends StatefulWidget{final GameState gs;const QuizScreen({super.key,required this.gs});@override State<QuizScreen> createState()=>_QuizState();}
class _QuizState extends State<QuizScreen> with TickerProviderStateMixin{late final AnimationController _ok,_bad,_slide;late final Animation<double> _pulse,_shake;late final Animation<Offset> _slideAnim;bool _fact=false;GameState get gs=>widget.gs;
@override void initState(){super.initState();gs.addListener(_onChange);_ok=AnimationController(vsync:this,duration:const Duration(milliseconds:500));_bad=AnimationController(vsync:this,duration:const Duration(milliseconds:400));_slide=AnimationController(vsync:this,duration:const Duration(milliseconds:350));_pulse=TweenSequence([TweenSequenceItem(tween:Tween(begin:1.0,end:1.04),weight:40),TweenSequenceItem(tween:Tween(begin:1.04,end:1.0),weight:60)]).animate(CurvedAnimation(parent:_ok,curve:Curves.easeInOut));_shake=TweenSequence([TweenSequenceItem(tween:Tween(begin:0.0,end:-10.0),weight:25),TweenSequenceItem(tween:Tween(begin:-10.0,end:10.0),weight:50),TweenSequenceItem(tween:Tween(begin:10.0,end:0.0),weight:25)]).animate(CurvedAnimation(parent:_bad,curve:Curves.easeInOut));_slideAnim=Tween(begin:const Offset(1,0),end:Offset.zero).animate(CurvedAnimation(parent:_slide,curve:Curves.easeOutCubic));_slide.forward();}
void _onChange(){if(!mounted)return;setState(()=>_fact=false);if(gs.ans==Ans.correct){_ok.forward(from:0);Future.delayed(const Duration(milliseconds:300),()=>mounted?setState(()=>_fact=true):null);Future.delayed(const Duration(milliseconds:2000),_next);}else if(gs.ans==Ans.wrong){_bad.forward(from:0);Future.delayed(const Duration(milliseconds:300),()=>mounted?setState(()=>_fact=true):null);Future.delayed(const Duration(milliseconds:2200),_next);}}
void _next(){if(!mounted)return;_slide.reverse().then((_){gs.next();if(!gs.done)_slide.forward();else if(mounted)Navigator.pushReplacement(context,_Slide(ResultScreen(gs:gs)));});}
@override void dispose(){gs.removeListener(_onChange);_ok.dispose();_bad.dispose();_slide.dispose();super.dispose();}
@override Widget build(BuildContext context){if(gs.done)return const SizedBox.shrink();final q=gs.cur;final cc=Cat.color(q.category);return Scaffold(backgroundColor:Pal.bg,body:SafeArea(child:Column(children:[_top(q,cc),Expanded(child:SlideTransition(position:_slideAnim,child:SingleChildScrollView(padding:const EdgeInsets.fromLTRB(20,8,20,16),child:Column(children:[_qCard(q,cc),const SizedBox(height:14),if(_fact&&q.f!=null)_factBanner(q),const SizedBox(height:6),...List.generate(q.a.length,(i)=>Padding(padding:const EdgeInsets.only(bottom:10),child:_AnsBtn(i:i,q:q,gs:gs)))]))))]));}
Widget _top(Question q,Color cc)=>Padding(padding:const EdgeInsets.fromLTRB(16,12,16,10),child:Row(children:[GestureDetector(onTap:()=>Navigator.pop(context),child:Container(padding:const EdgeInsets.all(10),decoration:BoxDecoration(color:Pal.card,borderRadius:BorderRadius.circular(12),border:Border.all(color:Pal.ts.withOpacity(0.2))),child:const Icon(Icons.close,color:Pal.ts,size:20))),const SizedBox(width:12),Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text('${gs.idx+1} / ${gs.questions.length}',style:const TextStyle(color:Pal.ts,fontSize:12,fontWeight:FontWeight.w600)),const SizedBox(height:4),ClipRRect(borderRadius:BorderRadius.circular(4),child:LinearProgressIndicator(value:gs.progress,minHeight:6,backgroundColor:Pal.card,valueColor:AlwaysStoppedAnimation(cc)))])),const SizedBox(width:12),Container(padding:const EdgeInsets.symmetric(horizontal:14,vertical:8),decoration:BoxDecoration(color:Pal.card,borderRadius:BorderRadius.circular(12),border:Border.all(color:Pal.gold.withOpacity(0.4))),child:Row(children:[const Text('⭐',style:TextStyle(fontSize:16)),const SizedBox(width:4),Text('${gs.score}',style:const TextStyle(color:Pal.gold,fontWeight:FontWeight.w900,fontSize:16))])),if(gs.streak>=2)...[const SizedBox(width:8),Container(padding:const EdgeInsets.symmetric(horizontal:10,vertical:8),decoration:BoxDecoration(color:const Color(0xFFFF6B00).withOpacity(0.15),borderRadius:BorderRadius.circular(12),border:Border.all(color:const Color(0xFFFF6B00).withOpacity(0.5))),child:Text('🔥 ${gs.streak}',style:const TextStyle(color:Color(0xFFFF6B00),fontWeight:FontWeight.w900,fontSize:14)))]]));
Widget _qCard(Question q,Color cc)=>AnimatedBuilder(animation:Listenable.merge([_pulse,_shake]),builder:(_,__){final scale=gs.ans==Ans.correct?_pulse.value:1.0;final tx=gs.ans==Ans.wrong?_shake.value:0.0;Color border=cc.withOpacity(0.3);if(gs.ans==Ans.correct)border=Pal.green;if(gs.ans==Ans.wrong)border=Pal.red;return Transform.translate(offset:Offset(tx,0),child:Transform.scale(scale:scale,child:Container(width:double.infinity,padding:const EdgeInsets.all(22),decoration:BoxDecoration(color:Pal.card,borderRadius:BorderRadius.circular(22),border:Border.all(color:border,width:1.5),boxShadow:[BoxShadow(color:cc.withOpacity(0.1),blurRadius:20)]),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Row(children:[Container(padding:const EdgeInsets.symmetric(horizontal:10,vertical:5),decoration:BoxDecoration(color:cc.withOpacity(0.15),borderRadius:BorderRadius.circular(8),border:Border.all(color:cc.withOpacity(0.4))),child:Text('${Cat.emoji(q.category)}  ${Cat.name(q.category)}',style:TextStyle(color:cc,fontSize:11,fontWeight:FontWeight.w700))),const Spacer(),Container(padding:const EdgeInsets.symmetric(horizontal:8,vertical:4),decoration:BoxDecoration(color:Pal.diff(q.d).withOpacity(0.15),borderRadius:BorderRadius.circular(8)),child:Text(S.diffLabel(q.d),style:TextStyle(color:Pal.diff(q.d),fontSize:11,fontWeight:FontWeight.w700)))]),const SizedBox(height:14),Text(q.q,style:const TextStyle(color:Pal.tp,fontSize:20,fontWeight:FontWeight.w700,height:1.4)),const SizedBox(height:8),Row(children:[Icon(Icons.toll_rounded,size:14,color:Pal.gold.withOpacity(0.7)),const SizedBox(width:4),Text(S.ptsLabel(q.points,gs.streak),style:TextStyle(color:Pal.gold.withOpacity(0.7),fontSize:12,fontWeight:FontWeight.w600))])]))));});
Widget _factBanner(Question q){final ok=gs.ans==Ans.correct;final color=ok?Pal.green:Pal.red;return AnimatedOpacity(opacity:_fact?1:0,duration:const Duration(milliseconds:300),child:Container(margin:const EdgeInsets.only(bottom:10),padding:const EdgeInsets.all(14),decoration:BoxDecoration(color:color.withOpacity(0.1),borderRadius:BorderRadius.circular(16),border:Border.all(color:color.withOpacity(0.4))),child:Row(crossAxisAlignment:CrossAxisAlignment.start,children:[Text(ok?'✅':'❌',style:const TextStyle(fontSize:18)),const SizedBox(width:10),Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text(ok?S.ansCorrect:'${S.ansWrong} ${q.a[q.c]}',style:TextStyle(color:color,fontWeight:FontWeight.w800,fontSize:13)),const SizedBox(height:4),Text(q.f!,style:const TextStyle(color:Pal.ts,fontSize:12,height:1.4))]))]));}
}

class _AnsBtn extends StatefulWidget{final int i;final Question q;final GameState gs;const _AnsBtn({required this.i,required this.q,required this.gs});@override State<_AnsBtn> createState()=>_AnsBtnState();}
class _AnsBtnState extends State<_AnsBtn> with SingleTickerProviderStateMixin{late final AnimationController _c;late final Animation<double> _s;@override void initState(){super.initState();_c=AnimationController(vsync:this,duration:const Duration(milliseconds:100));_s=Tween(begin:1.0,end:0.97).animate(CurvedAnimation(parent:_c,curve:Curves.easeOut));}@override void dispose(){_c.dispose();super.dispose();}
Color get _bg{if(widget.gs.ans==Ans.waiting)return Pal.card;if(widget.i==widget.q.c)return Pal.green.withOpacity(0.2);if(widget.i==widget.gs.sel)return Pal.red.withOpacity(0.2);return Pal.card.withOpacity(0.5);}
Color get _border{if(widget.gs.ans==Ans.waiting)return Pal.ts.withOpacity(0.2);if(widget.i==widget.q.c)return Pal.green;if(widget.i==widget.gs.sel)return Pal.red;return Pal.ts.withOpacity(0.1);}
@override Widget build(BuildContext context){const letters=['A','B','C','D'];final lColors=[Pal.accent,const Color(0xFF4D96FF),const Color(0xFFFF6B9D),const Color(0xFF2ECC71)];final lc=lColors[widget.i%lColors.length];return AnimatedBuilder(animation:_c,builder:(_,child)=>Transform.scale(scale:_s.value,child:child),child:GestureDetector(onTapDown:(_){if(widget.gs.ans!=Ans.waiting)return;_c.forward();},onTapUp:(_){_c.reverse();widget.gs.answer(widget.i);},onTapCancel:()=>_c.reverse(),child:AnimatedContainer(duration:const Duration(milliseconds:200),padding:const EdgeInsets.symmetric(vertical:16,horizontal:16),decoration:BoxDecoration(color:_bg,borderRadius:BorderRadius.circular(16),border:Border.all(color:_border,width:1.5)),child:Row(children:[Container(width:32,height:32,decoration:BoxDecoration(color:lc.withOpacity(0.15),borderRadius:BorderRadius.circular(8),border:Border.all(color:lc.withOpacity(0.5))),child:Center(child:Text(letters[widget.i],style:TextStyle(color:lc,fontWeight:FontWeight.w900,fontSize:14)))),const SizedBox(width:14),Expanded(child:Text(widget.q.a[widget.i],style:TextStyle(color:widget.gs.ans!=Ans.waiting&&widget.i!=widget.q.c&&widget.i!=widget.gs.sel?Pal.ts:Pal.tp,fontSize:16,fontWeight:FontWeight.w600))),if(widget.gs.ans!=Ans.waiting)Text(widget.i==widget.q.c?'✅':widget.i==widget.gs.sel?'❌':'',style:const TextStyle(fontSize:18))]))));}}

class ResultScreen extends StatefulWidget{final GameState gs;const ResultScreen({super.key,required this.gs});@override State<ResultScreen> createState()=>_ResultState();}
class _ResultState extends State<ResultScreen> with TickerProviderStateMixin{late final AnimationController _enter,_scoreCtrl;late final Animation<double> _enterAnim;late final Animation<int> _scoreAnim;
@override void initState(){super.initState();_enter=AnimationController(vsync:this,duration:const Duration(milliseconds:700));_scoreCtrl=AnimationController(vsync:this,duration:const Duration(milliseconds:1200));_enterAnim=CurvedAnimation(parent:_enter,curve:Curves.easeOutBack);_scoreAnim=IntTween(begin:0,end:widget.gs.score).animate(CurvedAnimation(parent:_scoreCtrl,curve:Curves.easeOut));_enter.forward();Future.delayed(const Duration(milliseconds:200),()=>_scoreCtrl.forward());}
@override void dispose(){_enter.dispose();_scoreCtrl.dispose();super.dispose();}
String get _grade{final p=widget.gs.correct/max(1,widget.gs.results.length);if(p>=0.9)return 'S';if(p>=0.75)return 'A';if(p>=0.55)return 'B';if(p>=0.35)return 'C';return 'D';}
Color get _gc{switch(_grade){case 'S':return Pal.gold;case 'A':return Pal.green;case 'B':return const Color(0xFF4D96FF);case 'C':return const Color(0xFFF39C12);default:return Pal.red;}}
@override Widget build(BuildContext context){final gs=widget.gs;final prem=PurchaseService.instance.isPremium;return Scaffold(backgroundColor:Pal.bg,body:SafeArea(child:SingleChildScrollView(padding:const EdgeInsets.all(24),child:Column(children:[const SizedBox(height:20),ScaleTransition(scale:_enterAnim,child:Column(children:[Container(width:120,height:120,decoration:BoxDecoration(shape:BoxShape.circle,color:_gc.withOpacity(0.15),border:Border.all(color:_gc,width:3),boxShadow:[BoxShadow(color:_gc.withOpacity(0.4),blurRadius:30,spreadRadius:2)]),child:Center(child:Text(_grade,style:TextStyle(fontSize:56,fontWeight:FontWeight.w900,color:_gc)))),const SizedBox(height:20),Text(S.gradeMsg(_grade),style:const TextStyle(color:Pal.tp,fontSize:22,fontWeight:FontWeight.w800))])),const SizedBox(height:30),AnimatedBuilder(animation:_scoreCtrl,builder:(_,__)=>Text('${_scoreAnim.value}',style:TextStyle(fontSize:72,fontWeight:FontWeight.w900,color:Pal.gold,shadows:[Shadow(color:Pal.gold.withOpacity(0.4),blurRadius:20)]))),const Text(S.pointsLbl,style:TextStyle(color:Pal.ts,letterSpacing:4,fontSize:12)),const SizedBox(height:28),Row(children:[_sbox(S.correctLbl,'${gs.correct}/${gs.results.length}',Pal.green),const SizedBox(width:12),_sbox(S.streakLbl,'${gs.best}x',const Color(0xFFFF6B00)),const SizedBox(width:12),_sbox(S.accuracyLbl,'${gs.results.isEmpty?0:((gs.correct/gs.results.length)*100).round()}%',Pal.accent)]),const SizedBox(height:28),_catBreak(gs),if(!prem)...[const SizedBox(height:20),GestureDetector(onTap:()=>showModalBottomSheet(context:context,isScrollControlled:true,backgroundColor:Colors.transparent,builder:(_)=>PaywallSheet(onCode:(code){PurchaseService.instance.tryDevUnlock(code);Navigator.pop(context);})),child:Container(padding:const EdgeInsets.all(16),decoration:BoxDecoration(gradient:LinearGradient(colors:[Pal.premium.withOpacity(0.2),Pal.accent.withOpacity(0.15)]),borderRadius:BorderRadius.circular(16),border:Border.all(color:Pal.premium.withOpacity(0.5))),child:Row(children:[const Text('👑',style:TextStyle(fontSize:26)),const SizedBox(width:12),Expanded(child:Text(S.upgradeMsg(QRepo.premium.length),style:const TextStyle(color:Pal.tp,fontSize:13,fontWeight:FontWeight.w600))),const Text('→',style:TextStyle(color:Pal.premium,fontSize:18,fontWeight:FontWeight.w900))])))],const SizedBox(height:36),_btn('🔄  ${S.playAgain}',const LinearGradient(colors:[Color(0xFF7C6FE0),Color(0xFF4D96FF)]),()=>Navigator.pushReplacement(context,_Slide(QuizScreen(gs:GameState()..start(c:gs.cat,d:gs.maxD,prem:PurchaseService.instance.isPremium))))),const SizedBox(height:12),_btn('🏠  ${S.homeLbl}',LinearGradient(colors:[Pal.card,Pal.card]),()=>Navigator.popUntil(context,(r)=>r.isFirst),border:Border.all(color:Pal.ts.withOpacity(0.3))),const SizedBox(height:20)]))));}
Widget _sbox(String l,String v,Color c)=>Expanded(child:Container(padding:const EdgeInsets.symmetric(vertical:16,horizontal:8),decoration:BoxDecoration(color:Pal.card,borderRadius:BorderRadius.circular(16),border:Border.all(color:c.withOpacity(0.3))),child:Column(children:[Text(v,style:TextStyle(color:c,fontSize:22,fontWeight:FontWeight.w900)),const SizedBox(height:4),Text(l,textAlign:TextAlign.center,style:const TextStyle(color:Pal.ts,fontSize:11,height:1.3))])));
Widget _catBreak(GameState gs){final m=<String,List<bool>>{};for(int i=0;i<gs.questions.length&&i<gs.results.length;i++){m.putIfAbsent(gs.questions[i].category,()=>[]);m[gs.questions[i].category]!.add(gs.results[i]);}if(m.isEmpty)return const SizedBox.shrink();return Container(padding:const EdgeInsets.all(18),decoration:BoxDecoration(color:Pal.card,borderRadius:BorderRadius.circular(18),border:Border.all(color:Pal.ts.withOpacity(0.15))),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[const Text(S.byCatLbl,style:TextStyle(color:Pal.gold,fontSize:10,fontWeight:FontWeight.w700,letterSpacing:3)),const SizedBox(height:14),...m.entries.map((e){final c=e.value.where((v)=>v).length;final t=e.value.length;final color=Cat.color(e.key);return Padding(padding:const EdgeInsets.only(bottom:12),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Row(children:[Text(Cat.emoji(e.key),style:const TextStyle(fontSize:14)),const SizedBox(width:6),Text(Cat.name(e.key),style:const TextStyle(color:Pal.tp,fontSize:13,fontWeight:FontWeight.w600)),const Spacer(),Text('$c/$t',style:TextStyle(color:color,fontSize:12,fontWeight:FontWeight.w700))]),const SizedBox(height:6),ClipRRect(borderRadius:BorderRadius.circular(4),child:LinearProgressIndicator(value:c/max(1,t),minHeight:6,backgroundColor:Pal.bg,valueColor:AlwaysStoppedAnimation(color)))]));})]));}
Widget _btn(String l,Gradient g,VoidCallback t,{Border? border})=>GestureDetector(onTap:t,child:Container(width:double.infinity,padding:const EdgeInsets.symmetric(vertical:18),decoration:BoxDecoration(gradient:g,borderRadius:BorderRadius.circular(18),border:border,boxShadow:border==null?[BoxShadow(color:Pal.accent.withOpacity(0.3),blurRadius:16,offset:const Offset(0,6))]:[]),child:Text(l,textAlign:TextAlign.center,style:const TextStyle(color:Colors.white,fontSize:18,fontWeight:FontWeight.w800,letterSpacing:1))));
}

class _Slide<T> extends PageRouteBuilder<T>{final Widget page;_Slide(this.page):super(pageBuilder:(_,__,___)=>page,transitionsBuilder:(_,a,__,child)=>SlideTransition(position:Tween(begin:const Offset(1,0),end:Offset.zero).animate(CurvedAnimation(parent:a,curve:Curves.easeOutCubic)),child:child),transitionDuration:const Duration(milliseconds:350));}
