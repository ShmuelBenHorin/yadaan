import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;

// ═══════════════════════════════════════════════
//  NOTIFICATIONS
// ═══════════════════════════════════════════════
class NotificationService {
  static final _plugin = FlutterLocalNotificationsPlugin();
  static const _channelId      = 'yadaan_energy';
  static const _channelName    = 'אנרגיה';
  static const _streakChannelId   = 'yadaan_streak';
  static const _streakChannelName = 'רצף יומי';
  static const _energyId    = 1;
  static const _dailyId     = 2;
  static const _streakId    = 3;

  static Future<void> init() async {
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iOS     = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    await _plugin.initialize(
      const InitializationSettings(android: android, iOS: iOS),
    );
    // צור channels לאנדרואיד
    final ap = _plugin.resolvePlatformSpecificImplementation<
      AndroidFlutterLocalNotificationsPlugin>();
    await ap?.createNotificationChannel(const AndroidNotificationChannel(
      _channelId, _channelName, importance: Importance.high,
    ));
    await ap?.createNotificationChannel(const AndroidNotificationChannel(
      _streakChannelId, _streakChannelName, importance: Importance.high,
    ));
  }

  // בקש הרשאה (iOS בלבד — אנדרואיד אוטומטי מ-13+)
  static Future<void> requestPermission() async {
    await _plugin.resolvePlatformSpecificImplementation<
      IOSFlutterLocalNotificationsPlugin>()
      ?.requestPermissions(alert: true, badge: true, sound: true);
    await _plugin.resolvePlatformSpecificImplementation<
      AndroidFlutterLocalNotificationsPlugin>()
      ?.requestNotificationsPermission();
  }

  // שלח notification כשהאנרגיה מלאה
  static Future<void> scheduleEnergyFull(int minutesUntilFull) async {
    await _plugin.cancel(_energyId);
    if (minutesUntilFull <= 0) return;
    final when = DateTime.now().add(Duration(minutes: minutesUntilFull));
    await _plugin.zonedSchedule(
      _energyId,
      '🧠 האנרגיה שלך התמלאה!',
      'בוא לשחק ידען — הכל מחכה לך',
      _toTZDateTime(when),
      NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId, _channelName,
          importance: Importance.high, priority: Priority.high,
          icon: '@mipmap/ic_launcher',
        ),
        iOS: const DarwinNotificationDetails(),
      ),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
    );
  }

  // ביטול notification אנרגיה (כשנכנסים לאפליקציה)
  static Future<void> cancelEnergyNotification() async {
    await _plugin.cancel(_energyId);
  }

  // תזמן נוטיפיקציה לרצף ב-20:00 היום (אם עוד לא שיחקו)
  static Future<void> scheduleStreakReminder(int streakDays) async {
    await _plugin.cancel(_streakId);
    final now = DateTime.now();
    final when = DateTime(now.year, now.month, now.day, 20, 0);
    if (!when.isAfter(now)) return; // עבר 20:00 — לא מתזמנים
    final title = streakDays >= 7
        ? '🔥 $streakDays ימים ברצף — אל תשבור אותו!'
        : streakDays >= 3
        ? '🔥 $streakDays ימים ברצף — עוד יום אחד!'
        : streakDays == 1
        ? '🔥 יום ראשון ברצף — המשך הלאה!'
        : '🧠 יש לך שאלות שמחכות לך!';
    const body = 'פתח את ידען ושחק לפני חצות';
    await _plugin.zonedSchedule(
      _streakId, title, body,
      _toTZDateTime(when),
      NotificationDetails(
        android: AndroidNotificationDetails(
          _streakChannelId, _streakChannelName,
          importance: Importance.high, priority: Priority.high,
          icon: '@mipmap/ic_launcher',
        ),
        iOS: const DarwinNotificationDetails(),
      ),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
    );
  }

  // ביטול נוטיפיקציה רצף (כשמשחקים היום)
  static Future<void> cancelStreakNotification() async {
    await _plugin.cancel(_streakId);
  }

  static tz.TZDateTime _toTZDateTime(DateTime dt) {
    return tz.TZDateTime.from(dt, tz.local);
  }
}
