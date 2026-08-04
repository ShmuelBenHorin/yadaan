import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import '../config.dart';
import 'analytics.dart';

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

  // Note: EnergyService is accessed via a late reference to avoid circular import.
  // EnergyService imports PurchaseService, so we call it via a callback set from main.dart.
  static void Function()? _onProActivated;
  static void setOnProActivated(void Function() cb) { _onProActivated = cb; }

  bool tryDev(String c){
    if(c!=Cfg.devCode)return false;
    _dev=true;
    _onProActivated?.call();
    notifyListeners();
    return true;
  }

  static Future<void> init() async {
    if(Cfg.mockPremium){_i._pro=true;return;}
    try{
      await Purchases.setLogLevel(LogLevel.debug);
      await Purchases.configure(PurchasesConfiguration(
        defaultTargetPlatform==TargetPlatform.iOS?Cfg.rciOS:Cfg.rcAndroid));
      final appUserId=await Purchases.appUserID;
      debugPrint('RC init — APP USER ID: $appUserId');
      final ci=await Purchases.getCustomerInfo();
      debugPrint('RC init — looking for entitlement: "${Cfg.entitlement}"');
      debugPrint('RC init — all entitlements returned: ${ci.entitlements.all.keys}');
      debugPrint('RC init — active entitlements: ${ci.entitlements.active.keys}');
      _i._pro=ci.entitlements.all[Cfg.entitlement]?.isActive??false;
      // fallback: אם השם המדויק לא נמצא — בדוק אם יש בכלל entitlement פעיל
      if(!_i._pro && ci.entitlements.active.isNotEmpty) _i._pro=true;
      debugPrint('RC init — isPremium result: ${_i._pro}');
      if(_i._pro){ _onProActivated?.call(); }
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
      // fallback: אם entitlement 'premium' לא נמצא — בדוק כל entitlement פעיל
      if(!_pro && ci.entitlements.active.isNotEmpty) _pro=true;
      // fallback 2: sync ו-refetch אחרי השהייה קצרה (עיכוב שרת RevenueCat)
      if(!_pro){
        await Future.delayed(const Duration(milliseconds:800));
        try{
          await Purchases.syncPurchases();
          final ci2=await Purchases.getCustomerInfo();
          _pro=ci2.entitlements.all[Cfg.entitlement]?.isActive??false;
          if(!_pro && ci2.entitlements.active.isNotEmpty) _pro=true;
          debugPrint('RC fallback entitlements: ${ci2.entitlements.all.keys}');
        }catch(e2){debugPrint('RC sync fallback error: $e2');}
      }
      if(_pro){
        _onProActivated?.call();
        Analytics.proPurchased(source:'purchase');
      }
      _loading=false;notifyListeners();return _pro;
    }on PurchasesError catch(e){
      debugPrint('RC purchase error: ${e.code} — ${e.message}');
      _loading=false;notifyListeners();
      if(e.code==PurchasesErrorCode.purchaseCancelledError)return false;
      rethrow;
    }catch(e){
      debugPrint('RC purchase unknown error: $e');
      _loading=false;notifyListeners();return false;
    }
  }
  Future<bool> restore() async {
    _loading=true;notifyListeners();
    try{
      final ci=await Purchases.restorePurchases();
      _pro=ci.entitlements.all[Cfg.entitlement]?.isActive??false;
      // fallback: כל entitlement פעיל
      if(!_pro && ci.entitlements.active.isNotEmpty) _pro=true;
      if(_pro){
        _onProActivated?.call();
        Analytics.proPurchased(source:'restore');
      }
      _loading=false;notifyListeners();return _pro;
    }catch(_){_loading=false;notifyListeners();return false;}
  }
}