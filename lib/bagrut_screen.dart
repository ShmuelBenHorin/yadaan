part of 'main.dart';

// ════════════════════════════════════════════════════════════════════════════
//  BAGRUT — בגרות בהיסטוריה
// ════════════════════════════════════════════════════════════════════════════

const _kTopicName = {
  'leumiyut'       : 'לאומיות',
  'tsiyonut'       : 'ציונות',
  'hayishuv'       : 'היישוב היהודי',
  'hamandat'       : 'המנדט הבריטי',
  'milhemet_olam_1': 'מלחמת העולם הראשונה',
  'milhemet_olam_2': 'מלחמת העולם השנייה',
  'shoah'          : 'השואה',
  'hakamah'        : 'הקמת המדינה',
  'medinat_israel' : 'מדינת ישראל',
  'shivat_tsiyon'  : 'שיבת ציון',
  'helenistit'     : 'התקופה ההלניסטית',
  'hashmonaim'     : 'מרד החשמונאים',
  'horodos'        : 'הורדוס',
  'hamered_hagadol': 'המרד הגדול',
  'yavne'          : 'יבנה וחכמיה',
  'bar_kokhva'     : 'מרד בר כוכבא',
  'kehilot'        : 'קהילות ישראל',
};

const _kTrackTopics = {
  'mamlachti': ['leumiyut','tsiyonut','hayishuv','milhemet_olam_1','hamandat','milhemet_olam_2','shoah','hakamah','medinat_israel'],
  'external' : ['leumiyut','tsiyonut','hayishuv','hamandat','milhemet_olam_2','shoah','hakamah','medinat_israel'],
  'chmd'     : ['leumiyut','tsiyonut','hayishuv','milhemet_olam_1','hamandat','milhemet_olam_2','shoah','hakamah','medinat_israel','shivat_tsiyon','helenistit','hashmonaim','horodos','hamered_hagadol','yavne','bar_kokhva','kehilot'],
};

const _kTrackLabel = {'mamlachti':'ממלכתי','external':'אקסטרני','chmd':'ממלכתי דתי (חמ"ד)'};

// ─── palette (local) ─────────────────────────────────────────────────────────
const _bg    = Color(0xFF0A1628);
const _card  = Color(0xFF0F2044);
const _card2 = Color(0xFF152856);
const _gold  = Color(0xFFFFD700);
const _blue  = Color(0xFF4D96FF);
const _green = Color(0xFF2ECC71);
const _red   = Color(0xFFE74C3C);
const _textP = Color(0xFFF0F4FF);
const _textS = Color(0xFF7A90C0);
const _border= Color(0xFF1E3260);

// ─── BagrutQuestion ──────────────────────────────────────────────────────────
class BagrutQuestion {
  final String id,cat,q,f;
  final List<String> a;
  final int c;
  final List<String> tracks;
  const BagrutQuestion({required this.id,required this.cat,required this.q,required this.a,required this.c,required this.f,required this.tracks});
  factory BagrutQuestion.fromMap(Map<String,dynamic> m)=>BagrutQuestion(
    id:m['id'],cat:m['cat'],q:m['q'],a:List<String>.from(m['a']),c:m['c'],f:m['f']??'',tracks:List<String>.from(m['track']??[]));
}

// ─── BagrutService ───────────────────────────────────────────────────────────
class BagrutService extends ChangeNotifier {
  static final BagrutService _i = BagrutService._();
  static BagrutService get instance => _i;
  BagrutService._();

  static List<BagrutQuestion>? _allQ;
  static List<BagrutQuestion> get allQ{_allQ??=(jsonDecode(kBagrut) as List).map((e)=>BagrutQuestion.fromMap(e)).toList();return _allQ!;}

  String? _track;
  bool _onboarded=false;
  bool _devUnlocked=false;
  bool get devUnlocked=>_devUnlocked;
  final Map<String,int> _strength={};
  final Map<String,Set<String>> _seen={};
  final Map<String,int> _correct={},_total={};

  String? get track=>_track;
  bool get onboarded=>_onboarded;
  bool get isConfigured=>_track!=null&&_onboarded;
  List<String> get trackTopics=>_track==null?[]:List.from(_kTrackTopics[_track!]??[]);

  int strength(String cat)=>_strength[cat]??1;
  bool isExcluded(String cat)=>(_strength[cat]??1)==0;
  int correct(String cat)=>_correct[cat]??0;
  int total(String cat)=>_total[cat]??0;
  double accuracy(String cat){final t=total(cat);return t==0?-1:correct(cat)/t;}

  static Future<void> init() async {
    final p=await SharedPreferences.getInstance();
    _i._track=p.getString('bagrut_track');
    _i._onboarded=p.getBool('bagrut_onboarded')??false;
    _i._devUnlocked=p.getBool('bagrut_dev')??false;
    for(final cat in _kTopicName.keys){
      _i._strength[cat]=p.getInt('bagrut_str_$cat')??1;
      _i._seen[cat]=Set.from(p.getStringList('bagrut_seen_$cat')??[]);
      _i._correct[cat]=p.getInt('bagrut_correct_$cat')??0;
      _i._total[cat]=p.getInt('bagrut_total_$cat')??0;
    }
  }

  Future<void> unlockDev() async {
    _devUnlocked=true;
    final p=await SharedPreferences.getInstance();
    await p.setBool('bagrut_dev',true);
    notifyListeners();
  }

  Future<void> setTrack(String t) async {
    _track=t;_onboarded=false;
    final p=await SharedPreferences.getInstance();
    await p.setString('bagrut_track',t);await p.setBool('bagrut_onboarded',false);
    notifyListeners();
  }

  Future<void> saveOnboarding(Map<String,int> s) async {
    final p=await SharedPreferences.getInstance();
    for(final e in s.entries){_strength[e.key]=e.value;await p.setInt('bagrut_str_${e.key}',e.value);}
    _onboarded=true;await p.setBool('bagrut_onboarded',true);
    notifyListeners();
  }

  Future<void> updateStrength(String cat,int s) async {
    _strength[cat]=s;final p=await SharedPreferences.getInstance();await p.setInt('bagrut_str_$cat',s);notifyListeners();
  }

  Future<void> recordAnswer(String qId,String cat,bool ok) async {
    _total[cat]=(_total[cat]??0)+1;
    final p=await SharedPreferences.getInstance();
    await p.setInt('bagrut_total_$cat',_total[cat]!);
    if(ok){_correct[cat]=(_correct[cat]??0)+1;await p.setInt('bagrut_correct_$cat',_correct[cat]!);
      _seen[cat]??={};_seen[cat]!.add(qId);await p.setStringList('bagrut_seen_$cat',_seen[cat]!.toList());}
    notifyListeners();
  }

  List<BagrutQuestion> buildPool({int size=10}) {
    if(_track==null)return[];
    final topics=trackTopics.where((t)=>!isExcluded(t)).toList();
    Map<String,List<BagrutQuestion>> byTopic={};
    for(final cat in topics){
      final seen=_seen[cat]??{};
      byTopic[cat]=allQ.where((q)=>q.cat==cat&&q.tracks.contains(_track!)&&!seen.contains(q.id)).toList()..shuffle();
      if((byTopic[cat]?.isEmpty??true)&&allQ.any((q)=>q.cat==cat&&q.tracks.contains(_track!))){
        _seen[cat]={};SharedPreferences.getInstance().then((p)=>p.remove('bagrut_seen_$cat'));
        byTopic[cat]=allQ.where((q)=>q.cat==cat&&q.tracks.contains(_track!)).toList()..shuffle();
      }
    }
    final weakTopics=topics.where((c)=>strength(c)==1).toList()..shuffle();
    final strongTopics=topics.where((c)=>strength(c)>=2).toList()..shuffle();
    final weakN=(size*0.7).round();final strongN=size-weakN;
    List<BagrutQuestion> pool=[];
    int added=0;
    for(final cat in weakTopics){if(added>=weakN)break;final qs=byTopic[cat]??[];final take=min(qs.length,weakN-added);pool.addAll(qs.take(take));added+=take;}
    int addedS=0;
    for(final cat in strongTopics){if(addedS>=strongN)break;final qs=byTopic[cat]??[];final take=min(qs.length,strongN-addedS);pool.addAll(qs.take(take));addedS+=take;}
    if(pool.length<size){for(final cat in topics){final qs=(byTopic[cat]??[]).where((q)=>!pool.contains(q)).toList();pool.addAll(qs.take(size-pool.length));if(pool.length>=size)break;}}
    pool.shuffle();return pool.take(size).toList();
  }

  List<String> detectLiedStrength()=>trackTopics.where((cat){
    final t=total(cat);if(t<3)return false;if(strength(cat)<2)return false;return accuracy(cat)<0.5;
  }).toList();
}

// ════════════════════════════════════════════════════════════════════════════
//  HOME ENTRY CARD
// ════════════════════════════════════════════════════════════════════════════
class BagrutEntryCard extends StatelessWidget {
  const BagrutEntryCard({super.key});

  void _open(BuildContext ctx) {
    if(!PurchaseService.instance.isPremium){
      Navigator.push(ctx,_bagRoute(const BagrutPaywallScreen()));return;
    }
    final svc=BagrutService.instance;
    Navigator.push(ctx,_bagRoute(svc.isConfigured?const BagrutMainScreen():const BagrutTrackSelectionScreen()));
  }

  @override
  Widget build(BuildContext ctx)=>GestureDetector(
    onTap:()=>_open(ctx),
    child:Container(
      decoration:BoxDecoration(
        gradient:const LinearGradient(colors:[Color(0xFF1B3A6B),Color(0xFF0F2044)],begin:Alignment.topRight,end:Alignment.bottomLeft),
        borderRadius:BorderRadius.circular(18),
        border:Border.all(color:_gold.withAlpha(80),width:1.5),
        boxShadow:[BoxShadow(color:_gold.withAlpha(25),blurRadius:16,offset:const Offset(0,4))]),
      child:Padding(
        padding:const EdgeInsets.symmetric(horizontal:18,vertical:16),
        child:Row(children:[
          // icon
          Container(width:52,height:52,
            decoration:BoxDecoration(gradient:const LinearGradient(colors:[Color(0xFFFFD700),Color(0xFFFF9500)]),borderRadius:BorderRadius.circular(14)),
            child:const Center(child:Text('📜',style:TextStyle(fontSize:26)))),
          const SizedBox(width:14),
          // text
          Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
            Row(children:[
              const Text('בגרות בהיסטוריה',style:TextStyle(color:_textP,fontSize:16,fontWeight:FontWeight.w800)),
              const SizedBox(width:8),
              Container(
                padding:const EdgeInsets.symmetric(horizontal:7,vertical:2),
                decoration:BoxDecoration(color:_gold,borderRadius:BorderRadius.circular(6)),
                child:const Text('חדש',style:TextStyle(color:Colors.black,fontSize:10,fontWeight:FontWeight.w900,letterSpacing:0.5))),
            ]),
            const SizedBox(height:3),
            const Text('תרגול חכם לפי חולשות וחוזקות',style:TextStyle(color:_textS,fontSize:13)),
          ])),
          const Icon(Icons.arrow_back_ios_new_rounded,color:_textS,size:15),
        ]),
      ),
    ),
  );
}

PageRoute _bagRoute(Widget w)=>MaterialPageRoute(builder:(_)=>w);

// ════════════════════════════════════════════════════════════════════════════
//  PAYWALL
// ════════════════════════════════════════════════════════════════════════════
class BagrutPaywallScreen extends StatefulWidget {
  const BagrutPaywallScreen({super.key});
  @override State<BagrutPaywallScreen> createState()=>_BagrutPWState();
}
class _BagrutPWState extends State<BagrutPaywallScreen> {
  bool _loading=false;
  String? _err;

  Future<void> _buy() async {
    final ps=PurchaseService.instance;
    setState((){_loading=true;_err=null;});
    if(ps.packages.isEmpty) await Future.delayed(const Duration(seconds:2));
    if(!mounted)return;
    if(ps.packages.isEmpty){
      setState((){_loading=false;_err='אין חיבור לחנות — נסה שוב';});return;
    }
    try{await ps.purchase(ps.packages.first);}catch(_){}
    if(!mounted)return;
    setState(()=>_loading=false);
    if(ps.isPremium)Navigator.pushReplacement(context,_bagRoute(const BagrutTrackSelectionScreen()));
  }

  Future<void> _restore() async {
    setState((){_loading=true;_err=null;});
    try{await PurchaseService.instance.restore();}catch(_){}
    if(!mounted)return;
    setState(()=>_loading=false);
    if(PurchaseService.instance.isPremium)Navigator.pushReplacement(context,_bagRoute(const BagrutTrackSelectionScreen()));
  }

  @override
  Widget build(BuildContext ctx){
    final bot=MediaQuery.of(ctx).padding.bottom;
    return Scaffold(
      backgroundColor:const Color(0xFF080F1E),
      body:Column(children:[
        Expanded(child:SingleChildScrollView(
          padding:const EdgeInsets.fromLTRB(24,0,24,0),
          child:Column(children:[
            // ── hero ──────────────────────────────────────────────────────
            const SizedBox(height:56),
            Container(width:80,height:80,
              decoration:BoxDecoration(shape:BoxShape.circle,
                gradient:const LinearGradient(colors:[_gold,Color(0xFFFF9F0A)],begin:Alignment.topLeft,end:Alignment.bottomRight),
                boxShadow:[BoxShadow(color:_gold.withAlpha(100),blurRadius:28,spreadRadius:2)]),
              child:const Center(child:Text('📜',style:TextStyle(fontSize:40)))),
            const SizedBox(height:18),
            const Text('ידען פרו',style:TextStyle(color:Colors.white,fontSize:30,fontWeight:FontWeight.w900,letterSpacing:1)),
            const SizedBox(height:6),
            ShaderMask(
              shaderCallback:(b)=>const LinearGradient(colors:[_gold,Color(0xFFFF9F0A)]).createShader(b),
              child:const Text('כולל בגרות בהיסטוריה',style:TextStyle(color:Colors.white,fontSize:16,fontWeight:FontWeight.w700))),
            const SizedBox(height:28),

            // ── benefits ──────────────────────────────────────────────────
            _PWRow('🔴','שלבים קשים — פתוחים','גישה לכל רמות הקושי'),
            const SizedBox(height:10),
            _PWRow('🧠','50 מוחות מיידית','במקום 15 — כמעט פי 4'),
            const SizedBox(height:10),
            _PWRow('⚡','טעינה מהירה פי 3','חזרה למשחק מהר יותר'),
            const SizedBox(height:10),
            _PWRow('🚫','ללא פרסומות','חוויה נקייה ורציפה'),
            const SizedBox(height:10),
            _PWRow('📜','בגרות בהיסטוריה','ממלכתי, ממלכתי דתי (חמ"ד) ואקסטרני — תרגול חכם 70/30'),
            const SizedBox(height:10),
            _PWRow('🔓','כל התכנים העתידיים','עדכונים, קטגוריות ותכנים מיוחדים'),
            const SizedBox(height:28),
          ])),
        ),

        // ── sticky bottom ────────────────────────────────────────────────
        Container(
          padding:EdgeInsets.fromLTRB(24,16,24,bot+16),
          decoration:BoxDecoration(
            color:const Color(0xFF080F1E),
            border:Border(top:BorderSide(color:Colors.white.withAlpha(15)))),
          child:Column(children:[
            if(_err!=null)Padding(padding:const EdgeInsets.only(bottom:10),
              child:Text(_err!,textAlign:TextAlign.center,style:const TextStyle(color:_red,fontSize:13))),
            if(_loading)
              const Padding(padding:EdgeInsets.symmetric(vertical:14),
                child:CircularProgressIndicator(color:_gold))
            else...[
              SizedBox(
                width:double.infinity,height:54,
                child:ElevatedButton(
                  onPressed:_buy,
                  style:ElevatedButton.styleFrom(
                    backgroundColor:_gold,foregroundColor:Colors.black,
                    elevation:8,shadowColor:_gold.withAlpha(80),
                    shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(16)),
                    textStyle:const TextStyle(fontSize:17,fontWeight:FontWeight.w900)),
                  child:const Text('התחל עכשיו — 12.90 ₪ לחודש'))),
              const SizedBox(height:10),
              GestureDetector(
                onTap:_restore,
                child:const Text('שחזר רכישות',textAlign:TextAlign.center,
                  style:TextStyle(color:_textS,fontSize:13,decoration:TextDecoration.underline))),
              const SizedBox(height:10),
              const Text('המנוי מתחדש אוטומטית ב-12.90 ₪ לחודש אלא אם כן בוטל לפחות 24 שעות לפני סוף התקופה.',
                textAlign:TextAlign.center,style:TextStyle(color:Color(0xFF4A5A7A),fontSize:11,height:1.5)),
            ],
          ]),
        ),
      ]),
      // close X
      floatingActionButtonLocation:FloatingActionButtonLocation.miniStartTop,
      floatingActionButton:SafeArea(child:IconButton(
        onPressed:()=>Navigator.pop(ctx),
        icon:const Icon(Icons.close_rounded,color:Colors.white54,size:22))),
    );
  }
}

class _PWRow extends StatelessWidget {
  final String emoji,title,sub;
  const _PWRow(this.emoji,this.title,this.sub);
  @override
  Widget build(BuildContext ctx)=>Container(
    padding:const EdgeInsets.symmetric(horizontal:16,vertical:14),
    decoration:BoxDecoration(color:const Color(0xFF0D1A30),borderRadius:BorderRadius.circular(14),
      border:Border.all(color:const Color(0xFF1A2E50))),
    child:Row(children:[
      Text(emoji,style:const TextStyle(fontSize:26)),
      const SizedBox(width:14),
      Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
        Text(title,textDirection:TextDirection.rtl,style:const TextStyle(color:Colors.white,fontWeight:FontWeight.w700,fontSize:15)),
        Text(sub,textDirection:TextDirection.rtl,style:const TextStyle(color:Color(0xFF7A90C0),fontSize:12)),
      ])),
      const Icon(Icons.check_circle_rounded,color:_green,size:22),
    ]));
}

// ════════════════════════════════════════════════════════════════════════════
//  TRACK SELECTION
// ════════════════════════════════════════════════════════════════════════════
class BagrutTrackSelectionScreen extends StatelessWidget {
  const BagrutTrackSelectionScreen({super.key});

  void _pick(BuildContext ctx,String track) async {
    await BagrutService.instance.setTrack(track);
    if(!ctx.mounted)return;
    Navigator.pushReplacement(ctx,_bagRoute(const BagrutOnboardingScreen()));
  }

  @override
  Widget build(BuildContext ctx)=>Directionality(
    textDirection:TextDirection.rtl,
    child:Scaffold(
      backgroundColor:_bg,
      appBar:AppBar(backgroundColor:Colors.transparent,elevation:0,
        title:const Text('בחר מסלול',style:TextStyle(color:_textP,fontWeight:FontWeight.w800,fontSize:18)),
        centerTitle:true,iconTheme:const IconThemeData(color:_textS)),
      body:Padding(
        padding:const EdgeInsets.fromLTRB(20,16,20,24),
        child:Column(children:[
          _TrackOption(ctx,'mamlachti','ממלכתי','🏫',const Color(0xFF4D96FF),_pick),
          const SizedBox(height:12),
          _TrackOption(ctx,'chmd','ממלכתי דתי (חמ"ד)','🕍',const Color(0xFF9B59B6),_pick),
          const SizedBox(height:12),
          _TrackOption(ctx,'external','אקסטרני','📋',const Color(0xFF2ECC71),_pick),
        ]),
      ),
    ),
  );
}

class _TrackOption extends StatelessWidget {
  final BuildContext ctx;
  final String track,name,emoji;
  final Color color;
  final void Function(BuildContext,String) onPick;
  const _TrackOption(this.ctx,this.track,this.name,this.emoji,this.color,this.onPick);
  @override
  Widget build(BuildContext context)=>GestureDetector(
    onTap:()=>onPick(ctx,track),
    child:Container(
      padding:const EdgeInsets.symmetric(horizontal:20,vertical:18),
      decoration:BoxDecoration(
        color:_card,borderRadius:BorderRadius.circular(14),
        border:Border.all(color:color.withAlpha(70))),
      child:Row(children:[
        Text(emoji,style:const TextStyle(fontSize:24)),
        const SizedBox(width:14),
        Expanded(child:Text(name,style:const TextStyle(color:_textP,fontSize:17,fontWeight:FontWeight.w800))),
        Icon(Icons.arrow_back_ios_new_rounded,color:color,size:16),
      ]),
    ),
  );
}

// ════════════════════════════════════════════════════════════════════════════
//  ONBOARDING — rate topics, can't skip
// ════════════════════════════════════════════════════════════════════════════
class BagrutOnboardingScreen extends StatefulWidget {
  const BagrutOnboardingScreen({super.key});
  @override State<BagrutOnboardingScreen> createState()=>_OnbState();
}
class _OnbState extends State<BagrutOnboardingScreen>{
  // selected = topics user wants to FOCUS on (weak)
  final Set<String> _weak={};
  bool _saving=false;
  List<String> get _topics=>BagrutService.instance.trackTopics;

  Future<void> _save() async {
    setState(()=>_saving=true);
    // weak selected → strength 1, rest → strength 3
    final Map<String,int> strengths={};
    for(final cat in _topics){
      strengths[cat]=_weak.contains(cat)?1:3;
    }
    await BagrutService.instance.saveOnboarding(strengths);
    if(!mounted)return;
    Navigator.pushReplacement(context,_bagRoute(const BagrutMainScreen()));
  }

  @override
  Widget build(BuildContext ctx)=>Directionality(
    textDirection:TextDirection.rtl,
    child:Scaffold(
      backgroundColor:_bg,
      body:SafeArea(child:Column(children:[
        // ── header ──────────────────────────────────────────────────────────
        Padding(padding:const EdgeInsets.fromLTRB(20,16,20,8),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
          Row(children:[
            IconButton(
              icon:const Icon(Icons.arrow_back_ios_new_rounded,color:_textS,size:18),
              onPressed:()=>Navigator.pop(ctx),
              padding:EdgeInsets.zero,constraints:const BoxConstraints()),
            const SizedBox(width:4),
            const Expanded(child:Text('במה אתה רוצה להתחזק?',
              style:TextStyle(color:_textP,fontSize:19,fontWeight:FontWeight.w900))),
          ]),
          const SizedBox(height:6),
          const Text('בחר את הנושאים שאתה רוצה לתרגל יותר — השאר ייחשבו כחזקים.',
            style:TextStyle(color:_textS,fontSize:13,height:1.4)),
          const SizedBox(height:4),
          if(_weak.isNotEmpty) Text('${_weak.length} נושאים נבחרו',
            style:const TextStyle(color:_gold,fontSize:12,fontWeight:FontWeight.w600)),
        ])),

        // ── chips ─────────────────────────────────────────────────────────
        Expanded(child:SingleChildScrollView(
          padding:const EdgeInsets.fromLTRB(20,4,20,12),
          child:Wrap(
            spacing:10,runSpacing:10,
            children:_topics.map((cat){
              final name=_kTopicName[cat]??cat;
              final sel=_weak.contains(cat);
              return GestureDetector(
                onTap:()=>setState(()=>sel?_weak.remove(cat):_weak.add(cat)),
                child:AnimatedContainer(
                  duration:const Duration(milliseconds:150),
                  padding:const EdgeInsets.symmetric(horizontal:16,vertical:10),
                  decoration:BoxDecoration(
                    color:sel?_red.withAlpha(30):_card,
                    borderRadius:BorderRadius.circular(24),
                    border:Border.all(color:sel?_red:_border,width:sel?1.8:1.2)),
                  child:Text(name,style:TextStyle(
                    color:sel?_red:_textS,
                    fontSize:14,fontWeight:sel?FontWeight.w800:FontWeight.w600)),
                ),
              );
            }).toList(),
          ))),

        // ── save button ───────────────────────────────────────────────────
        Padding(padding:const EdgeInsets.fromLTRB(20,0,20,20),
          child:SizedBox(
            width:double.infinity,height:52,
            child:ElevatedButton(
              onPressed:_saving?null:_save,
              style:ElevatedButton.styleFrom(
                backgroundColor:_gold,foregroundColor:Colors.black,
                elevation:6,shadowColor:_gold.withAlpha(60),
                shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(14)),
                textStyle:const TextStyle(fontSize:16,fontWeight:FontWeight.w900)),
              child:_saving
                ?const SizedBox(height:20,width:20,child:CircularProgressIndicator(strokeWidth:2.5,color:Colors.black))
                :Text(_weak.isEmpty?'✓  שמור — הכל חזק':'✓  שמור והתחל לתרגל'),
            ))),
      ])),
    ));
}

// ════════════════════════════════════════════════════════════════════════════
//  MAIN BAGRUT SCREEN
// ════════════════════════════════════════════════════════════════════════════
class BagrutMainScreen extends StatelessWidget {
  const BagrutMainScreen({super.key});
  @override
  Widget build(BuildContext ctx){
    final svc=BagrutService.instance;
    final topics=svc.trackTopics.where((t)=>!svc.isExcluded(t)).toList();
    final mastered=topics.where((c)=>svc.accuracy(c)>=0.7).length;
    final toImprove=topics.where((c)=>svc.strength(c)==1||svc.accuracy(c)<0.5&&svc.total(c)>0).length;

    return Directionality(
      textDirection:TextDirection.rtl,
      child:Scaffold(
        backgroundColor:_bg,
        appBar:AppBar(
          backgroundColor:Colors.transparent,elevation:0,
          title:Text('${_kTrackLabel[svc.track]??""}',style:const TextStyle(color:_textP,fontWeight:FontWeight.w800,fontSize:17)),
          centerTitle:true,
          iconTheme:const IconThemeData(color:_textS),
          actions:[
            IconButton(
              icon:const Icon(Icons.tune_rounded,color:_textS),
              onPressed:()=>Navigator.push(ctx,_bagRoute(const BagrutTrackSelectionScreen()))),
          ]),
        body:Column(children:[
          // ── stats strip ──────────────────────────────────────────────────
          Padding(padding:const EdgeInsets.fromLTRB(16,4,16,12),
            child:Row(children:[
              _BagStatBox('📚','${topics.length}','נושאים'),
              const SizedBox(width:8),
              _BagStatBox('✅','$mastered','שולט'),
              const SizedBox(width:8),
              _BagStatBox('⚠️','$toImprove','לחזק'),
            ])),
          // ── list ─────────────────────────────────────────────────────────
          Expanded(child:ListView.builder(
            padding:const EdgeInsets.fromLTRB(16,0,16,16),
            itemCount:topics.length,
            itemBuilder:(ctx,i){
              final cat=topics[i];
              final acc=svc.accuracy(cat);
              final tot=svc.total(cat);
              final str=svc.strength(cat);
              Color col=_blue;String badge='';
              if(acc>=0.7){col=_green;badge='שולט';}
              else if(acc>=0&&acc<0.5&&tot>0){col=_red;badge='לחזק';}
              else if(str==1)col=_red;
              else if(str==3)col=_green;
              return Container(
                margin:const EdgeInsets.only(bottom:8),
                padding:const EdgeInsets.symmetric(horizontal:14,vertical:13),
                decoration:BoxDecoration(color:_card,borderRadius:BorderRadius.circular(13),border:Border.all(color:_border)),
                child:Row(children:[
                  // strength indicator
                  Container(width:4,height:36,decoration:BoxDecoration(color:col,borderRadius:BorderRadius.circular(2))),
                  const SizedBox(width:12),
                  Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
                    Text(_kTopicName[cat]??cat,style:const TextStyle(color:_textP,fontSize:14,fontWeight:FontWeight.w700)),
                    if(tot>0)Padding(padding:const EdgeInsets.only(top:2),
                      child:Text('${svc.correct(cat)} מתוך $tot נכון',style:const TextStyle(color:_textS,fontSize:12))),
                  ])),
                  if(badge.isNotEmpty)Container(
                    padding:const EdgeInsets.symmetric(horizontal:9,vertical:3),
                    decoration:BoxDecoration(color:col.withAlpha(30),borderRadius:BorderRadius.circular(8),border:Border.all(color:col.withAlpha(80))),
                    child:Text(badge,style:TextStyle(color:col,fontSize:11,fontWeight:FontWeight.w700))),
                  if(tot>0)Padding(padding:const EdgeInsets.only(right:8,left:0),
                    child:Text('${(acc*100).round()}%',style:TextStyle(color:col,fontSize:13,fontWeight:FontWeight.w800))),
                ]),
              );
            })),
          // ── start button ─────────────────────────────────────────────────
          Padding(padding:const EdgeInsets.fromLTRB(16,0,16,20),
            child:SizedBox(
              width:double.infinity,height:54,
              child:ElevatedButton.icon(
                onPressed:(){
                  final pool=svc.buildPool();
                  if(pool.isEmpty){ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content:Text('אין שאלות — בדוק שלא סימנת הכל כ"לא לומד"')));return;}
                  Navigator.push(ctx,_bagRoute(BagrutQuizScreen(questions:pool)));
                },
                icon:const Icon(Icons.play_arrow_rounded,size:22),
                label:const Text('התחל תרגול',style:TextStyle(fontSize:17,fontWeight:FontWeight.w800)),
                style:ElevatedButton.styleFrom(
                  backgroundColor:_blue,foregroundColor:Colors.white,
                  elevation:6,shadowColor:_blue.withAlpha(80),
                  shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(14))),
              ))),
        ]),
      ),
    );
  }
}

class _BagStatBox extends StatelessWidget {
  final String icon,val,label;
  const _BagStatBox(this.icon,this.val,this.label);
  @override
  Widget build(BuildContext ctx)=>Expanded(
    child:Container(
      padding:const EdgeInsets.symmetric(vertical:12),
      decoration:BoxDecoration(color:_card,borderRadius:BorderRadius.circular(12),border:Border.all(color:_border)),
      child:Column(children:[
        Text('$icon  $val',style:const TextStyle(color:_textP,fontSize:15,fontWeight:FontWeight.w800)),
        const SizedBox(height:2),
        Text(label,style:const TextStyle(color:_textS,fontSize:11)),
      ]),
    ));
}

// ════════════════════════════════════════════════════════════════════════════
//  QUIZ SCREEN
// ════════════════════════════════════════════════════════════════════════════
class BagrutQuizScreen extends StatefulWidget {
  final List<BagrutQuestion> questions;
  const BagrutQuizScreen({super.key,required this.questions});
  @override State<BagrutQuizScreen> createState()=>_BQState();
}
class _BQState extends State<BagrutQuizScreen>{
  int _idx=0;int? _sel;bool _answered=false;
  final Map<String,int> _catC={},_catT={};
  int _totalC=0;

  BagrutQuestion get _q=>widget.questions[_idx];

  void _choose(int i){
    if(_answered)return;
    final ok=i==_q.c;
    setState((){_sel=i;_answered=true;});
    BagrutService.instance.recordAnswer(_q.id,_q.cat,ok);
    _catT[_q.cat]=(_catT[_q.cat]??0)+1;
    if(ok){_catC[_q.cat]=(_catC[_q.cat]??0)+1;_totalC++;Sfx.correct();}
    else{Sfx.wrong();Future.delayed(const Duration(milliseconds:900),()=>_next());}
  }

  void _next(){
    if(!mounted)return;
    if(_idx<widget.questions.length-1){setState((){_idx++;_sel=null;_answered=false;});}
    else{
      final lied=BagrutService.instance.detectLiedStrength();
      Navigator.pushReplacement(context,_bagRoute(BagrutResultScreen(
        questions:widget.questions,catCorrect:_catC,catTotal:_catT,totalCorrect:_totalC,weaknessDetected:lied)));
    }
  }

  @override
  Widget build(BuildContext ctx)=>Directionality(
    textDirection:TextDirection.rtl,
    child:PopScope(canPop:false,child:Scaffold(
      backgroundColor:_bg,
      body:SafeArea(child:Column(children:[
        // ── top bar ─────────────────────────────────────────────────────────
        Padding(padding:const EdgeInsets.fromLTRB(16,12,16,8),
          child:Row(children:[
            GestureDetector(
              onTap:()=>showDialog(context:ctx,builder:(_)=>Directionality(textDirection:TextDirection.rtl,child:AlertDialog(
                backgroundColor:_card,shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(16)),
                title:const Text('לצאת מהתרגול?',style:TextStyle(color:_textP)),
                content:const Text('ההתקדמות בשאלות שנענו תישמר.',style:TextStyle(color:_textS)),
                actions:[
                  TextButton(onPressed:()=>Navigator.pop(ctx),child:const Text('המשך',style:TextStyle(color:_blue))),
                  TextButton(onPressed:(){Navigator.pop(ctx);Navigator.pop(ctx);},child:const Text('צא',style:TextStyle(color:_red))),
                ]))),
              child:Container(padding:const EdgeInsets.all(8),
                decoration:BoxDecoration(color:_card,borderRadius:BorderRadius.circular(10)),
                child:const Icon(Icons.close_rounded,color:_textS,size:20))),
            const SizedBox(width:12),
            Expanded(child:Column(children:[
              ClipRRect(
                borderRadius:BorderRadius.circular(4),
                child:LinearProgressIndicator(
                  value:(_idx+1)/widget.questions.length,
                  backgroundColor:_border,color:_gold,minHeight:6)),
            ])),
            const SizedBox(width:12),
            Text('${_idx+1}/${widget.questions.length}',style:const TextStyle(color:_textS,fontSize:13,fontWeight:FontWeight.w700)),
          ])),
        // ── topic badge ──────────────────────────────────────────────────────
        Padding(padding:const EdgeInsets.fromLTRB(16,4,16,4),
          child:Align(alignment:Alignment.centerRight,
            child:Container(
              padding:const EdgeInsets.symmetric(horizontal:10,vertical:4),
              decoration:BoxDecoration(color:_card,borderRadius:BorderRadius.circular(8),border:Border.all(color:_border)),
              child:Text(_kTopicName[_q.cat]??_q.cat,style:const TextStyle(color:_textS,fontSize:12,fontWeight:FontWeight.w600))))),
        // ── question ─────────────────────────────────────────────────────────
        Expanded(child:SingleChildScrollView(
          padding:const EdgeInsets.fromLTRB(16,8,16,0),
          child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
            Text(_q.q,style:const TextStyle(color:_textP,fontSize:18,fontWeight:FontWeight.w800,height:1.5)),
            const SizedBox(height:20),
            ...List.generate(_q.a.length,(i)=>_BQTile(
              text:_q.a[i],index:i,selected:_sel==i,answered:_answered,isCorrect:i==_q.c,
              onTap:()=>_choose(i))),
            const SizedBox(height:16),
          ]))),
        // ── next button — only on correct answer ─────────────────────────────
        if(_answered&&_sel==_q.c)Padding(padding:const EdgeInsets.fromLTRB(16,4,16,16),
          child:GestureDetector(
            onTap:_next,
            child:Container(
              width:double.infinity,
              padding:const EdgeInsets.symmetric(vertical:16),
              decoration:BoxDecoration(
                gradient:LinearGradient(colors:_sel==_q.c?[_green,const Color(0xFF27AE60)]:[_blue,const Color(0xFF2A5298)]),
                borderRadius:BorderRadius.circular(14),
                boxShadow:[BoxShadow(color:(_sel==_q.c?_green:_blue).withAlpha(60),blurRadius:12,offset:const Offset(0,4))]),
              child:Row(mainAxisAlignment:MainAxisAlignment.center,children:[
                Text(_idx<widget.questions.length-1?'שאלה הבאה':'לתוצאות',
                  style:const TextStyle(color:Colors.white,fontSize:16,fontWeight:FontWeight.w800)),
                const SizedBox(width:6),
                const Icon(Icons.arrow_back_rounded,color:Colors.white,size:18),
              ]),
            ),
          )),
      ])),
    )),
  );
}

class _BQTile extends StatelessWidget {
  final String text;final int index;
  final bool selected,answered,isCorrect;
  final VoidCallback onTap;
  const _BQTile({required this.text,required this.index,required this.selected,required this.answered,required this.isCorrect,required this.onTap});
  @override
  Widget build(BuildContext ctx){
    Color bg=_card,border=_border,textCol=_textP;
    if(answered){
      if(isCorrect){bg=_green.withAlpha(30);border=_green;textCol=_green;}
      else if(selected){bg=_red.withAlpha(30);border=_red;textCol=_red;}
    } else if(selected){bg=_blue.withAlpha(30);border=_blue;}
    final labels=['א','ב','ג','ד'];
    return GestureDetector(
      onTap:onTap,
      child:AnimatedContainer(
        duration:const Duration(milliseconds:150),
        margin:const EdgeInsets.only(bottom:10),
        padding:const EdgeInsets.symmetric(horizontal:14,vertical:14),
        decoration:BoxDecoration(color:bg,borderRadius:BorderRadius.circular(13),border:Border.all(color:border,width:1.5)),
        child:Row(children:[
          // label circle
          Container(width:30,height:30,
            decoration:BoxDecoration(color:border.withAlpha(40),shape:BoxShape.circle,border:Border.all(color:border,width:1)),
            child:Center(child:Text(labels[index],style:TextStyle(color:border,fontWeight:FontWeight.w800,fontSize:13)))),
          const SizedBox(width:12),
          Expanded(child:Text(text,style:TextStyle(color:textCol,fontSize:15,height:1.4))),
          if(answered&&isCorrect)const Icon(Icons.check_rounded,color:_green,size:20),
          if(answered&&selected&&!isCorrect)const Icon(Icons.close_rounded,color:_red,size:20),
        ]),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
//  RESULT SCREEN
// ════════════════════════════════════════════════════════════════════════════
class BagrutResultScreen extends StatefulWidget {
  final List<BagrutQuestion> questions;
  final Map<String,int> catCorrect,catTotal;
  final int totalCorrect;
  final List<String> weaknessDetected;
  const BagrutResultScreen({super.key,required this.questions,required this.catCorrect,required this.catTotal,required this.totalCorrect,required this.weaknessDetected});
  @override State<BagrutResultScreen> createState()=>_BagrutResultScreenState();
}
class _BagrutResultScreenState extends State<BagrutResultScreen> with TickerProviderStateMixin {
  late final AnimationController _enter, _confettiCtrl;
  final List<_Confetti> _pieces=[];
  bool _showContent=false;

  @override void initState(){
    super.initState();
    _enter=AnimationController(vsync:this,duration:const Duration(milliseconds:750))..forward();
    _confettiCtrl=AnimationController(vsync:this,duration:const Duration(seconds:3));
    final total=widget.questions.length;
    final pct=total==0?0.0:widget.totalCorrect/total;
    if(pct>=0.7){
      final rnd=Random();
      for(int i=0;i<55;i++){
        _pieces.add(_Confetti(
          x:rnd.nextDouble(),delay:rnd.nextDouble()*0.5,
          color:[_gold,_green,_blue,const Color(0xFFFF6B9D),const Color(0xFF4D96FF),Colors.white][rnd.nextInt(6)],
          size:rnd.nextDouble()*9+4,
          rotSpeed:(rnd.nextDouble()-0.5)*3,
          swayAmp:rnd.nextDouble()*0.05+0.01));
      }
      _confettiCtrl.forward();
    }
    Future.delayed(const Duration(milliseconds:200),(){if(mounted)setState(()=>_showContent=true);});
  }
  @override void dispose(){_enter.dispose();_confettiCtrl.dispose();super.dispose();}

  @override
  Widget build(BuildContext ctx){
    final total=widget.questions.length;
    final pct=total==0?0.0:widget.totalCorrect/total;
    final emoji=pct>=0.9?'🏆':pct>=0.7?'⭐':pct>=0.5?'📘':'💪';
    final msg=pct>=0.9?'מצוין! שליטה מלאה!':pct>=0.7?'כל הכבוד, עבודה טובה':pct>=0.5?'טוב — יש עוד מה לשפר':'יש עבודה — המשך לתרגל!';
    final pctColor=pct>=0.7?_green:pct>=0.5?_blue:_red;

    return Directionality(
      textDirection:TextDirection.rtl,
      child:Scaffold(
        backgroundColor:_bg,
        body:Stack(children:[
          if(_pieces.isNotEmpty)AnimatedBuilder(animation:_confettiCtrl,
            builder:(_,__)=>CustomPaint(size:Size.infinite,
              painter:_ConfettiPainter(_pieces,_confettiCtrl.value))),
          SafeArea(child:SingleChildScrollView(
          padding:const EdgeInsets.fromLTRB(20,20,20,32),
          child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
            const SizedBox(height:12),
            // ── score ──────────────────────────────────────────────────────
            ScaleTransition(
              scale:CurvedAnimation(parent:_enter,curve:Curves.easeOutBack),
              child:FadeTransition(
              opacity:_enter,
              child:Container(
              padding:const EdgeInsets.all(24),
              decoration:BoxDecoration(
                gradient:LinearGradient(colors:[pctColor.withAlpha(40),_card],begin:Alignment.topCenter,end:Alignment.bottomCenter),
                borderRadius:BorderRadius.circular(20),
                border:Border.all(color:pctColor.withAlpha(80))),
              child:Column(children:[
                Text(emoji,style:const TextStyle(fontSize:56)),
                const SizedBox(height:10),
                Text('${widget.totalCorrect} מתוך $total',style:const TextStyle(color:_textP,fontSize:36,fontWeight:FontWeight.w900)),
                const SizedBox(height:4),
                Text('${(pct*100).round()}%',style:TextStyle(color:pctColor,fontSize:22,fontWeight:FontWeight.w900)),
                const SizedBox(height:8),
                Text(msg,style:const TextStyle(color:_textP,fontSize:16),textAlign:TextAlign.center),
              ])))),

            const SizedBox(height:20),

            // ── per topic ──────────────────────────────────────────────────
            if(widget.catTotal.isNotEmpty)...[
              const Text('ביצועים לפי נושא',style:TextStyle(color:_textP,fontSize:16,fontWeight:FontWeight.w800)),
              const SizedBox(height:10),
              ...widget.catTotal.entries.map((e){
                final cat=e.key;final tot=e.value;final cor=widget.catCorrect[cat]??0;
                final acc=tot==0?0.0:cor/tot;
                final col=acc>=0.7?_green:acc>=0.5?_blue:_red;
                return Container(
                  margin:const EdgeInsets.only(bottom:8),
                  padding:const EdgeInsets.symmetric(horizontal:14,vertical:12),
                  decoration:BoxDecoration(color:_card,borderRadius:BorderRadius.circular(12),border:Border.all(color:_border)),
                  child:Row(children:[
                    Container(width:4,height:32,decoration:BoxDecoration(color:col,borderRadius:BorderRadius.circular(2))),
                    const SizedBox(width:10),
                    Expanded(child:Text(_kTopicName[cat]??cat,style:const TextStyle(color:_textP,fontSize:14,fontWeight:FontWeight.w700))),
                    Text('$cor/$tot',style:TextStyle(color:col,fontWeight:FontWeight.w800,fontSize:14)),
                    const SizedBox(width:8),
                    Text('${(acc*100).round()}%',style:TextStyle(color:col,fontSize:13)),
                  ]),
                );
              }),
            ],

            // ── weakness detected ──────────────────────────────────────────
            if(widget.weaknessDetected.isNotEmpty)...[
              const SizedBox(height:12),
              _WeaknessCard(cats:widget.weaknessDetected),
            ],

            const SizedBox(height:20),

            // ── back ───────────────────────────────────────────────────────
            GestureDetector(
              onTap:()=>Navigator.pushReplacement(ctx,_bagRoute(const BagrutMainScreen())),
              child:Container(
                padding:const EdgeInsets.symmetric(vertical:16),
                decoration:BoxDecoration(
                  gradient:const LinearGradient(colors:[Color(0xFF1B3A6B),Color(0xFF2A5298)]),
                  borderRadius:BorderRadius.circular(14),
                  border:Border.all(color:_blue.withAlpha(80))),
                child:const Row(mainAxisAlignment:MainAxisAlignment.center,children:[
                  Icon(Icons.home_rounded,color:_textP,size:20),
                  SizedBox(width:8),
                  Text('חזרה לתפריט',style:TextStyle(color:_textP,fontSize:16,fontWeight:FontWeight.w800)),
                ]),
              )),
          ]),
        )),
        ])));
  }
}

// ════════════════════════════════════════════════════════════════════════════
//  WEAKNESS DETECTION
// ════════════════════════════════════════════════════════════════════════════
class _WeaknessCard extends StatefulWidget {
  final List<String> cats;
  const _WeaknessCard({required this.cats});
  @override State<_WeaknessCard> createState()=>_WCState();
}
class _WCState extends State<_WeaknessCard>{
  bool _done=false,_loading=false;
  @override
  Widget build(BuildContext ctx){
    final names=widget.cats.map((c)=>_kTopicName[c]??c).join('، ');
    if(_done)return Container(
      padding:const EdgeInsets.all(14),
      decoration:BoxDecoration(color:_green.withAlpha(20),borderRadius:BorderRadius.circular(14),border:Border.all(color:_green.withAlpha(60))),
      child:const Row(children:[Icon(Icons.check_circle_rounded,color:_green),SizedBox(width:10),Expanded(child:Text('עודכן — בתרגול הבא תקבל יותר שאלות מנושאים אלו',style:TextStyle(color:_green,fontSize:13)))]));
    return Container(
      padding:const EdgeInsets.all(16),
      decoration:BoxDecoration(
        color:_red.withAlpha(20),borderRadius:BorderRadius.circular(14),border:Border.all(color:_red.withAlpha(60))),
      child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
        Row(children:[
          Container(width:36,height:36,decoration:BoxDecoration(color:_red.withAlpha(40),shape:BoxShape.circle),child:const Center(child:Text('⚠️',style:TextStyle(fontSize:18)))),
          const SizedBox(width:10),
          const Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
            Text('זיהינו פערי ידע',style:TextStyle(color:_red,fontWeight:FontWeight.w800,fontSize:15)),
            Text('בנושאים שסימנת כחזק',style:TextStyle(color:_textS,fontSize:12)),
          ]),
        ]),
        const SizedBox(height:10),
        Text('נראה שחסר ידע ב: $names',style:const TextStyle(color:_textP,fontSize:13,height:1.5)),
        const SizedBox(height:4),
        const Text('רוצה לקבל יותר שאלות מנושאים אלו?',style:TextStyle(color:_textS,fontSize:13)),
        const SizedBox(height:14),
        Row(children:[
          Expanded(child:GestureDetector(
            onTap:_loading?null:() async {
              setState(()=>_loading=true);
              for(final cat in widget.cats) await BagrutService.instance.updateStrength(cat,1);
              if(!mounted)return;
              setState((){_loading=false;_done=true;});
            },
            child:Container(
              padding:const EdgeInsets.symmetric(vertical:12),
              decoration:BoxDecoration(color:_red,borderRadius:BorderRadius.circular(10)),
              child:_loading
                ?const Center(child:SizedBox(height:16,width:16,child:CircularProgressIndicator(strokeWidth:2,color:Colors.white)))
                :const Text('כן, תן לי יותר שאלות',textAlign:TextAlign.center,style:TextStyle(color:Colors.white,fontWeight:FontWeight.w700,fontSize:13))))),
          const SizedBox(width:10),
          TextButton(onPressed:(){},child:const Text('לא עכשיו',style:TextStyle(color:_textS,fontSize:13))),
        ]),
      ]),
    );
  }
}
