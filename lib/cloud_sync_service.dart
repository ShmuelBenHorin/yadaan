import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ═══════════════════════════════════════════════
//  CLOUD SYNC SERVICE — Google Sign-In + Firestore
//  אנדרואיד בלבד (iOS משתמש ב-iCloud KV)
// ═══════════════════════════════════════════════
class CloudSyncService extends ChangeNotifier {
  static final CloudSyncService _i = CloudSyncService._();
  static CloudSyncService get instance => _i;
  CloudSyncService._();

  final _auth   = FirebaseAuth.instance;
  final _store  = FirebaseFirestore.instance;
  final _google = GoogleSignIn();

  User?   _user;
  bool    _syncing = false;

  User?   get user       => _user;
  bool    get isSignedIn => _user != null;
  bool    get syncing    => _syncing;
  String? get displayName => _user?.displayName;
  String? get photoUrl    => _user?.photoURL;

  static Future<void> init() async {
    _i._user = FirebaseAuth.instance.currentUser;
    FirebaseAuth.instance.authStateChanges().listen((u) {
      _i._user = u;
      _i.notifyListeners();
    });
  }

  // ── התחברות עם Google ─────────────────────────
  Future<bool> signIn() async {
    try {
      final googleUser = await _google.signIn();
      if (googleUser == null) return false;
      final googleAuth = await googleUser.authentication;
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );
      await _auth.signInWithCredential(credential);
      notifyListeners();
      return true;
    } catch (_) { return false; }
  }

  // ── התנתקות ───────────────────────────────────
  Future<void> signOut() async {
    await _google.signOut();
    await _auth.signOut();
    notifyListeners();
  }

  // ── שמור התקדמות ל-Firestore ──────────────────
  Future<void> saveProgress() async {
    if (!isSignedIn) return;
    try {
      _syncing = true; notifyListeners();
      final p = await SharedPreferences.getInstance();
      final Map<String, dynamic> data = {
        'updatedAt': FieldValue.serverTimestamp(),
      };

      // StringLists
      for (final key in ['seen_easy','seen_medium','seen_hard','mistakes_v2',
                          'interests_v1']) {
        final v = p.getStringList(key);
        if (v != null) data[key] = v;
      }
      // Level stars
      for (final d in ['easy','medium','hard']) {
        for (int i = 0; i < 500; i++) {
          final key = 'lvl_${d}_$i';
          final v = p.getInt(key);
          if (v == null) break;
          data[key] = v;
        }
      }
      // ints
      for (final key in ['energy','energy_ts','levels_completed']) {
        final v = p.getInt(key); if (v != null) data[key] = v;
      }
      // bools
      final ob = p.getBool('onboarding_done');
      if (ob != null) data['onboarding_done'] = ob;

      await _store.collection('users').doc(_user!.uid)
          .set(data, SetOptions(merge: true));
    } catch (_) {}
    _syncing = false; notifyListeners();
  }

  // ── שחזר התקדמות מ-Firestore ─────────────────
  Future<bool> restoreProgress() async {
    if (!isSignedIn) return false;
    try {
      _syncing = true; notifyListeners();
      final doc = await _store.collection('users').doc(_user!.uid).get();
      if (!doc.exists || doc.data() == null) {
        _syncing = false; notifyListeners();
        return false;
      }
      final data = doc.data()!;
      final p = await SharedPreferences.getInstance();

      for (final entry in data.entries) {
        final key = entry.key;
        final val = entry.value;
        if (key == 'updatedAt') continue;
        if (val is List) {
          await p.setStringList(key, List<String>.from(val));
        } else if (val is int) {
          await p.setInt(key, val);
        } else if (val is bool) {
          await p.setBool(key, val);
        } else if (val is String) {
          await p.setString(key, val);
        }
      }
      _syncing = false; notifyListeners();
      return true;
    } catch (_) {
      _syncing = false; notifyListeners();
      return false;
    }
  }

  // ── בדוק אם יש נתונים בענן ───────────────────
  Future<bool> hasCloudData() async {
    if (!isSignedIn) return false;
    try {
      final doc = await _store.collection('users').doc(_user!.uid).get();
      return doc.exists && (doc.data()?.containsKey('lvl_easy_0') ?? false);
    } catch (_) { return false; }
  }
}

// ═══════════════════════════════════════════════
//  UI — כפתור Sign-In קומפקטי (TopBar)
// ═══════════════════════════════════════════════
class CloudSyncChip extends StatelessWidget {
  const CloudSyncChip({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: CloudSyncService.instance,
      builder: (ctx, _) {
        final svc = CloudSyncService.instance;
        if (svc.syncing) {
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xFF1A2E6E),
              borderRadius: BorderRadius.circular(10)),
            child: const SizedBox(
              width: 14, height: 14,
              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white54)));
        }
        if (svc.isSignedIn) {
          return GestureDetector(
            onTap: () => _showSignedInMenu(ctx, svc),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFF1A3A1A),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFF2ECC71).withOpacity(0.5))),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                svc.photoUrl != null
                  ? ClipOval(child: Image.network(svc.photoUrl!, width: 18, height: 18, fit: BoxFit.cover))
                  : const Icon(Icons.check_circle, color: Color(0xFF2ECC71), size: 16),
                const SizedBox(width: 5),
                const Text('מסונכרן', style: TextStyle(color: Color(0xFF2ECC71), fontSize: 11, fontWeight: FontWeight.w700)),
              ])));
        }
        return GestureDetector(
          onTap: () => _signIn(ctx, svc),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xFF1A2E6E),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFF4D96FF).withOpacity(0.4))),
            child: const Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.sync, color: Color(0xFF4D96FF), size: 14),
              SizedBox(width: 5),
              Text('סנכרן', style: TextStyle(color: Color(0xFF4D96FF), fontSize: 11, fontWeight: FontWeight.w700)),
            ])));
      },
    );
  }

  Future<void> _signIn(BuildContext ctx, CloudSyncService svc) async {
    final ok = await svc.signIn();
    if (!ok || !ctx.mounted) return;

    // בדוק אם יש נתונים בענן
    final hasCloud = await svc.hasCloudData();
    if (!ctx.mounted) return;

    if (hasCloud) {
      final restore = await showDialog<bool>(
        context: ctx,
        builder: (_) => Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            backgroundColor: const Color(0xFF0F2044),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: const Text('נמצאה התקדמות שמורה', style: TextStyle(color: Colors.white, fontSize: 17)),
            content: const Text('נמצאה התקדמות שמורה בענן. האם לשחזר אותה?',
              style: TextStyle(color: Color(0xFF7A90C0), fontSize: 14)),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false),
                child: const Text('לא תודה', style: TextStyle(color: Color(0xFF7A90C0)))),
              ElevatedButton(onPressed: () => Navigator.pop(ctx, true),
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFFD700), foregroundColor: Colors.black),
                child: const Text('שחזר', style: TextStyle(fontWeight: FontWeight.w800))),
            ])));
      if (restore == true) {
        await svc.restoreProgress();
        if (ctx.mounted) {
          ScaffoldMessenger.of(ctx).showSnackBar(
            const SnackBar(content: Text('✅ ההתקדמות שוחזרה בהצלחה')));
        }
      }
    } else {
      // אין נתונים בענן — שמור את הנוכחי
      await svc.saveProgress();
      if (ctx.mounted) {
        ScaffoldMessenger.of(ctx).showSnackBar(
          const SnackBar(content: Text('✅ ההתקדמות שמורה בענן')));
      }
    }
  }

  void _showSignedInMenu(BuildContext ctx, CloudSyncService svc) {
    showModalBottomSheet(
      context: ctx,
      backgroundColor: const Color(0xFF0F2044),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => Directionality(
        textDirection: TextDirection.rtl,
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.white12, borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 16),
            Text('מחובר כ-${svc.displayName ?? ""}',
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16)),
            const SizedBox(height: 4),
            const Text('ההתקדמות שלך מסונכרנת אוטומטית',
              style: TextStyle(color: Color(0xFF7A90C0), fontSize: 13)),
            const SizedBox(height: 20),
            SizedBox(width: double.infinity,
              child: ElevatedButton(
                onPressed: () async { Navigator.pop(ctx); await svc.saveProgress();
                  if (ctx.mounted) ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text('✅ ההתקדמות עודכנה בענן'))); },
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1B3A6B), foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                child: const Text('סנכרן עכשיו'))),
            const SizedBox(height: 10),
            TextButton(
              onPressed: () async { Navigator.pop(ctx); await svc.signOut(); },
              child: const Text('התנתק', style: TextStyle(color: Color(0xFF7A90C0)))),
          ]))));
  }
}
