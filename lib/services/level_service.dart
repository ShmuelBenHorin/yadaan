import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config.dart';
import '../models/question.dart';
import 'purchase_service.dart';

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
    return PurchaseService.instance.isPremium; // כוכבים לא נדרשים לפתיחת קשה
  }
  bool isLevelUnlocked(Diff d,int idx) {
    if (!isDiffUnlocked(d)) return false;
    if (idx == 0) return true;
    if (starsFor(d, idx-1) == 0) return false;
    final seg = idx ~/ Cfg.segmentSize;
    if (seg == 0 || idx % Cfg.segmentSize != 0) return true;
    final prevStart = (seg-1)*Cfg.segmentSize;
    int prevStars = 0;
    for(int i=prevStart;i<prevStart+Cfg.segmentSize;i++) prevStars+=starsFor(d,i);
    return prevStars >= Cfg.starsPerSegment;
  }
  String segmentProgress(Diff d, int idx) {
    final seg = idx ~/ Cfg.segmentSize;
    if (seg == 0) return "";
    final prevStart = (seg-1)*Cfg.segmentSize;
    int prevStars = 0;
    for(int i=prevStart;i<prevStart+Cfg.segmentSize;i++) prevStars+=starsFor(d,i);
    return "$prevStars/${Cfg.starsPerSegment} ⭐";
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
