// סאונד במובייל (iOS / Android) — מנגן קבצי WAV מתוך assets/sounds/
// מזהה איזה סאונד לנגן לפי התדר הראשון שמגיע מ-main.dart:
//   1318 Hz → correct  (תשובה נכונה)
//    294 Hz → wrong    (תשובה שגויה)
//    784 Hz → perfect  (ניצחון מושלם)
//    392 Hz → fail     (נכשלת)
// על Web נטען אוטומטית sfx_web.dart במקומו (ראה conditional import ב-main.dart).

import 'package:audioplayers/audioplayers.dart';

// pool של נגנים — מאפשר השמעה חופפת בלי ניתוק הקודם באמצע
final List<AudioPlayer> _pool = List.generate(4, (_) => AudioPlayer());
int _poolIdx = 0;

AudioPlayer _nextPlayer() {
  final p = _pool[_poolIdx];
  _poolIdx = (_poolIdx + 1) % _pool.length;
  return p;
}

String? _pickSoundFile(List<Map<String, dynamic>> notes) {
  if (notes.isEmpty) return null;
  final firstFreq = (notes.first['freq'] as num?)?.toDouble() ?? 0;
  // התאמה לפי התדר הראשון שמוגדר בקריאות Sfx.* ב-main.dart
  if ((firstFreq - 1318).abs() < 1) return 'sounds/correct.wav';
  if ((firstFreq -  294).abs() < 1) return 'sounds/wrong.wav';
  if ((firstFreq -  784).abs() < 1) return 'sounds/perfect.wav';
  if ((firstFreq -  392).abs() < 1) return 'sounds/fail.wav';
  return null;
}

void playWebTone(List<Map<String, dynamic>> notes) {
  final file = _pickSoundFile(notes);
  if (file == null) return;
  final player = _nextPlayer();
  // fire-and-forget: לא מחכים – כך האפליקציה לא נתקעת אם הנגן איטי
  player.stop().then((_) {
    player.play(AssetSource(file));
  }).catchError((_) {
    // גם אם stop נכשל, ננסה לנגן בכל זאת
    player.play(AssetSource(file));
  });
}
