part of 'main.dart';

// ═══════════════════════════════════════════════
//  SeasonalService — שאלות עונתיות מ-Firestore
//  ניהול מ-Firebase Console, ללא עדכון חנות
// ═══════════════════════════════════════════════

class SeasonalEvent {
  final String id, title, emoji, colorHex;
  final DateTime from, until;
  final int order;
  final List<Question> questions;

  const SeasonalEvent({
    required this.id,
    required this.title,
    required this.emoji,
    required this.colorHex,
    required this.from,
    required this.until,
    required this.order,
    required this.questions,
  });

  Color get color {
    final hex = colorHex.replaceAll('#', '').padLeft(6, '0');
    return Color(int.parse('FF$hex', radix: 16));
  }

  bool get isActive {
    final now = DateTime.now();
    return now.isAfter(from) && now.isBefore(until);
  }

  // ימים שנותרו
  int get daysLeft => until.difference(DateTime.now()).inDays.clamp(0, 9999);
}

class SeasonalService extends ChangeNotifier {
  static final SeasonalService _i = SeasonalService._();
  static SeasonalService get instance => _i;
  SeasonalService._();

  List<SeasonalEvent> _events = [];
  bool _loaded = false;
  bool get loaded => _loaded;

  List<SeasonalEvent> get activeEvents {
    final list = _events.where((e) => e.isActive && e.questions.isNotEmpty).toList();
    list.sort((a, b) => a.order.compareTo(b.order));
    return list;
  }

  static Future<void> init() async {
    await _i._loadCached();  // טעינה מיידית מ-cache (offline)
    _i._fetchFromFirestore(); // רענון ברקע מ-Firestore
  }

  // ─── Firestore ────────────────────────────────
  Future<void> _fetchFromFirestore() async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('seasonal_events')
          .where('active', isEqualTo: true)
          .get();

      final events = <SeasonalEvent>[];
      for (final doc in snap.docs) {
        final data = doc.data();
        final qSnap = await FirebaseFirestore.instance
            .collection('seasonal_events')
            .doc(doc.id)
            .collection('questions')
            .get();

        final questions = qSnap.docs
            .where((q) => q.data().containsKey('q'))
            .map((q) => Question.fromMap({...q.data(), 'id': q.id}))
            .toList();

        if (questions.isEmpty) continue;

        final from  = (data['from']  as Timestamp).toDate();
        final until = (data['until'] as Timestamp).toDate();

        events.add(SeasonalEvent(
          id:       doc.id,
          title:    data['title']    ?? '',
          emoji:    data['emoji']    ?? '🔥',
          colorHex: data['colorHex'] ?? 'FF6B35',
          from:     from,
          until:    until,
          order:    (data['order']   as int?) ?? 0,
          questions: questions,
        ));
      }

      _events = events;
      _loaded = true;
      await _saveCache(events);
      notifyListeners();
    } catch (e) {
      debugPrint('SeasonalService fetch error: $e');
      _loaded = true;
      notifyListeners();
    }
  }

  // ─── Cache (SharedPreferences) ───────────────
  static const _cacheKey = 'seasonal_events_v1';

  Future<void> _loadCached() async {
    try {
      final p = await SharedPreferences.getInstance();
      final json = p.getString(_cacheKey);
      if (json == null) { _loaded = false; return; }
      final list = jsonDecode(json) as List;
      _events = list.map((e) => _fromCacheMap(e as Map<String, dynamic>)).toList();
      _loaded = true;
    } catch (_) { _loaded = false; }
  }

  Future<void> _saveCache(List<SeasonalEvent> events) async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(_cacheKey, jsonEncode(events.map(_toCacheMap).toList()));
    } catch (_) {}
  }

  Map<String, dynamic> _toCacheMap(SeasonalEvent e) => {
    'id': e.id, 'title': e.title, 'emoji': e.emoji,
    'colorHex': e.colorHex,
    'from':  e.from.millisecondsSinceEpoch,
    'until': e.until.millisecondsSinceEpoch,
    'order': e.order,
    'questions': e.questions.map((q) => {
      'id': q.id, 'category': q.category, 'q': q.q,
      'a': q.a, 'c': q.c, 'd': q.diff.index + 1, 'f': q.f,
    }).toList(),
  };

  SeasonalEvent _fromCacheMap(Map<String, dynamic> m) => SeasonalEvent(
    id:       m['id'],
    title:    m['title'],
    emoji:    m['emoji'],
    colorHex: m['colorHex'],
    from:     DateTime.fromMillisecondsSinceEpoch(m['from'] as int),
    until:    DateTime.fromMillisecondsSinceEpoch(m['until'] as int),
    order:    m['order'] as int,
    questions: (m['questions'] as List)
        .map((q) => Question.fromMap(q as Map<String, dynamic>))
        .toList(),
  );
}
