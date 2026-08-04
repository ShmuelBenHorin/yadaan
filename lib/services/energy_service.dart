import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config.dart';
import 'analytics.dart';
import 'notification_service.dart';
import 'purchase_service.dart';

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
  /// קרא בכל חזרה לפוקוס (AppLifecycleState.resumed)
  void checkRecharge() => _check();
  void _check() {
    final elapsed=DateTime.now().difference(_last);
    final cycles=elapsed.inMinutes~/Cfg.energyRechargeMins;
    if(cycles>0&&_e<maxE){
      _e=(_e+cycles*rechargeAmt).clamp(0,maxE);
      _last=_last.add(Duration(minutes:cycles*Cfg.energyRechargeMins));
      _save(); notifyListeners();
    }
  }
  Future<void> spend(int n) async {
    final wasPositive = _e > 0;
    _e=(_e-n).clamp(0,maxE);
    await _save();
    if (wasPositive && _e == 0) {
      Analytics.energyDepleted();
      final minsUntilFull = (maxE / rechargeAmt).ceil() * Cfg.energyRechargeMins;
      NotificationService.scheduleEnergyFull(minsUntilFull);
    }
    notifyListeners();
  }
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
  int get secondsUntilNext {
    if (_e >= maxE) return 0;
    final diff = _last.add(Duration(minutes: Cfg.energyRechargeMins)).difference(DateTime.now());
    return diff.inSeconds.clamp(0, Cfg.energyRechargeMins * 60);
  }
  /// Called when Pro is activated — fills energy to max and persists it
  void fillToMax() {
    _e = maxE;
    _save();
    notifyListeners();
  }

  bool get canWatchAd => _e < maxE && !PurchaseService.instance.isPremium;
  // אנרגיה מפרסומת — amount לפי סוג הפרסומת
  Future<void> rewardFromAd({int amount = Cfg.adRewardedEnergy}) async {
    _e = (_e + amount).clamp(0, maxE);
    await _save(); notifyListeners();
  }
  @override void dispose(){_t?.cancel();super.dispose();}
}