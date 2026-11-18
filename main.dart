import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:android_intent_plus/android_intent.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

// ---------------------------------------------------------------- sabitler

const kChAlarm = 'hatirlatici_alarm_v1';
const kChOnce = 'hatirlatici_onceden_v1';
const kPaket = 'com.hatirlatici.hatirlatici';

final FlutterLocalNotificationsPlugin plugin = FlutterLocalNotificationsPlugin();
final FlutterTts tts = FlutterTts();
final ValueNotifier<int> yenileSinyali = ValueNotifier<int>(0);

const _gunKisa = ['Pzt', 'Sal', 'Çar', 'Per', 'Cum', 'Cmt', 'Paz'];
const _gunTam = [
  'Pazartesi',
  'Salı',
  'Çarşamba',
  'Perşembe',
  'Cuma',
  'Cumartesi',
  'Pazar'
];
const _ayKisa = [
  'Oca',
  'Şub',
  'Mar',
  'Nis',
  'May',
  'Haz',
  'Tem',
  'Ağu',
  'Eyl',
  'Eki',
  'Kas',
  'Ara'
];

// ---------------------------------------------------------------- model

class Hat {
  int id;
  String title;
  int whenMs;
  bool done;
  bool early;
  Hat({
    required this.id,
    required this.title,
    required this.whenMs,
    this.done = false,
    this.early = false,
  });

  DateTime get when => DateTime.fromMillisecondsSinceEpoch(whenMs);

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'whenMs': whenMs,
        'done': done,
        'early': early,
      };

  factory Hat.fromJson(Map<String, dynamic> j) => Hat(
        id: j['id'] as int,
        title: j['title'] as String,
        whenMs: j['whenMs'] as int,
        done: (j['done'] as bool?) ?? false,
        early: (j['early'] as bool?) ?? false,
      );
}

class Store {
  static const _k = 'hatirlaticilar_v1';
  static const _kc = 'sayac_v1';

  static Future<List<Hat>> load() async {
    final p = await SharedPreferences.getInstance();
    await p.reload();
    final raw = p.getString(_k);
    if (raw == null) return [];
    try {
      final l = jsonDecode(raw) as List;
      return l
          .map((e) => Hat.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> save(List<Hat> l) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_k, jsonEncode(l.map((e) => e.toJson()).toList()));
  }

  static Future<int> nextId() async {
    final p = await SharedPreferences.getInstance();
    await p.reload();
    final n = (p.getInt(_kc) ?? 0) + 1;
    await p.setInt(_kc, n);
    return n;
  }
}

// ---------------------------------------------------------------- yardımcılar

String hhmm(DateTime d) =>
    '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

int gunFarki(DateTime a, DateTime now) =>
    DateTime.utc(a.year, a.month, a.day)
        .difference(DateTime.utc(now.year, now.month, now.day))
        .inDays;

String gunEtiketi(DateTime d, DateTime now) {
  final f = gunFarki(d, now);
  if (f == 0) return 'Bugün';
  if (f == 1) return 'Yarın';
  if (f == -1) return 'Dün';
  if (f > 1 && f < 7) return _gunTam[d.weekday - 1];
  return '${d.day} ${_ayKisa[d.month - 1]} ${_gunKisa[d.weekday - 1]}';
}

String zamanYazisi(DateTime d, DateTime now) =>
    '${gunEtiketi(d, now)} ${hhmm(d)}';

DateTime gunEkle(DateTime d, int k) => DateTime(d.year, d.month, d.day + k);

// ---------------------------------------------------------------- Türkçe cümle çözümleme

class Parsed {
  final String title;
  final DateTime? when;
  Parsed(this.title, this.when);
}

String trLower(String s) {
  final b = StringBuffer();
  for (final r in s.runes) {
    final c = String.fromCharCode(r);
    if (c == 'İ') {
      b.write('i');
    } else if (c == 'I') {
      b.write('ı');
    } else {
      b.write(c.toLowerCase());
    }
  }
  return b.toString();
}

String trBuyuk(String s) {
  if (s.isEmpty) return s;
  final c = s[0];
  String u;
  if (c == 'i') {
    u = 'İ';
  } else if (c == 'ı') {
    u = 'I';
  } else {
    u = c.toUpperCase();
  }
  return u + s.substring(1);
}

const Map<String, int> _sayiKelime = {
  'bir': 1,
  'iki': 2,
  'üç': 3,
  'dört': 4,
  'beş': 5,
  'altı': 6,
  'yedi': 7,
  'sekiz': 8,
  'dokuz': 9,
  'on': 10,
  'onbir': 11,
  'oniki': 12,
};
const List<MapEntry<String, int>> _gunler = [
  MapEntry('pazartesi', 1),
  MapEntry('salı', 2),
  MapEntry('çarşamba', 3),
  MapEntry('perşembe', 4),
  MapEntry('cumartesi', 6),
  MapEntry('cuma', 5),
  MapEntry('pazar', 7),
];
const List<MapEntry<String, int>> _aylar = [
  MapEntry('ocak', 1),
  MapEntry('şubat', 2),
  MapEntry('mart', 3),
  MapEntry('nisan', 4),
  MapEntry('mayıs', 5),
  MapEntry('haziran', 6),
  MapEntry('temmuz', 7),
  MapEntry('ağustos', 8),
  MapEntry('eylül', 9),
  MapEntry('ekim', 10),
  MapEntry('kasım', 11),
  MapEntry('aralık', 12),
];
const Set<String> _ekler = {'de', 'da', 'te', 'ta', 'gibi', 'civarı', 'civarında'};
const Set<String> _dolgu = {
  'bana',
  'lütfen',
  'hatırlat',
  'hatırlatır',
  'hatırlatsana',
  'hatırlatıcı',
  'hatırla'
};
final RegExp _bitisikSaat = RegExp(
    r'^(onbir|oniki|bir|iki|üç|dört|beş|altı|yedi|sekiz|dokuz|on)(de|da|te|ta)$');
final RegExp _saatDk = RegExp(r'^(\d{1,2})[:.](\d{2})$');
final RegExp _sayiRe = RegExp(r'^\d{1,2}$');

int? _sayi(String t) {
  if (_sayiRe.hasMatch(t)) return int.parse(t);
  return _sayiKelime[t];
}

Parsed parseTr(String raw, DateTime now) {
  final temiz = raw.replaceAll('’', "'").replaceAll(',', ' ');
  final orig = <String>[];
  final glue = <bool>[];
  for (final p in temiz.split(RegExp(r'\s+'))) {
    if (p.isEmpty) continue;
    final k = p.indexOf("'");
    if (k > 0) {
      orig.add(p.substring(0, k));
      glue.add(false);
      if (p.length > k + 1) {
        orig.add(p.substring(k + 1));
        glue.add(true);
      }
    } else if (k == 0) {
      if (p.length > 1) {
        orig.add(p.substring(1));
        glue.add(false);
      }
    } else {
      orig.add(p);
      glue.add(false);
    }
  }
  final w = orig.map(trLower).toList();
  final n = w.length;
  final used = List<bool>.filled(n, false);
  String nx(int i) => (i + 1 < n && !used[i + 1]) ? w[i + 1] : '';

  int? relMin;
  int? relDays;
  int? dayD;
  int? dayM;
  int? dayoff;
  int? wday;
  bool haftaya = false;
  String? period;
  int? hour;
  int minute = 0;

  // 1) göreli süreler ve "20 Aralık" gibi tarihler
  for (int i = 0; i < n; i++) {
    if (used[i]) continue;
    final t = w[i];
    if (t == 'yarım' && i + 2 < n && w[i + 1] == 'saat' && w[i + 2] == 'sonra') {
      relMin = 30;
      used[i] = used[i + 1] = used[i + 2] = true;
      continue;
    }
    final k = _sayi(t);
    if (k != null &&
        i + 2 < n &&
        (w[i + 1] == 'dakika' ||
            w[i + 1] == 'dk' ||
            w[i + 1] == 'saat' ||
            w[i + 1] == 'gün' ||
            w[i + 1] == 'hafta') &&
        w[i + 2] == 'sonra') {
      final u = w[i + 1];
      if (u == 'dakika' || u == 'dk') {
        relMin = k;
      } else if (u == 'saat') {
        relMin = k * 60;
      } else if (u == 'gün') {
        relDays = k;
      } else {
        relDays = k * 7;
      }
      used[i] = used[i + 1] = used[i + 2] = true;
      continue;
    }
    if (k != null && k >= 1 && k <= 31 && i + 1 < n) {
      for (final a in _aylar) {
        if (w[i + 1].startsWith(a.key)) {
          dayD = k;
          dayM = a.value;
          used[i] = used[i + 1] = true;
          if (i + 2 < n && _ekler.contains(w[i + 2])) used[i + 2] = true;
          break;
        }
      }
    }
  }

  // 2) gün ve günün bölümü sözcükleri
  for (int i = 0; i < n; i++) {
    if (used[i]) continue;
    final t = w[i];
    if (t == 'bugün' || t == 'bugun') {
      dayoff = 0;
      used[i] = true;
    } else if (t == 'yarın') {
      dayoff = 1;
      used[i] = true;
    } else if (t == 'öbür' && nx(i) == 'gün') {
      dayoff = 2;
      used[i] = used[i + 1] = true;
    } else if (t == 'ertesi' && nx(i) == 'gün') {
      dayoff = 1;
      used[i] = used[i + 1] = true;
    } else if (t == 'haftaya') {
      haftaya = true;
      used[i] = true;
    } else if (t == 'bu' &&
        (nx(i) == 'akşam' || nx(i) == 'gece' || nx(i) == 'sabah')) {
      dayoff = 0;
      used[i] = true;
    } else if (t == 'öğleden' && nx(i) == 'sonra') {
      period = 'ogleden';
      used[i] = used[i + 1] = true;
    } else if (t == 'öğle' || t == 'öğlen') {
      period = 'ogle';
      used[i] = true;
    } else if (t == 'akşam' || t == 'akşamüstü') {
      period = 'aksam';
      used[i] = true;
    } else if (t == 'sabah') {
      period = 'sabah';
      used[i] = true;
    } else if (t == 'gece') {
      period = 'gece';
      used[i] = true;
    } else {
      for (final g in _gunler) {
        if (t == g.key) {
          wday = g.value;
          used[i] = true;
          if (nx(i) == 'günü' || nx(i) == 'gün') used[i + 1] = true;
          break;
        }
      }
    }
  }

  // 3) saat
  for (int i = 0; i < n; i++) {
    if (used[i] || hour != null) continue;
    final t = w[i];
    final m = _saatDk.firstMatch(t);
    final g = _bitisikSaat.firstMatch(t);
    final k = _sayi(t);
    if (m != null && int.parse(m.group(1)!) < 24 && int.parse(m.group(2)!) < 60) {
      hour = int.parse(m.group(1)!);
      minute = int.parse(m.group(2)!);
      used[i] = true;
    } else if (g != null) {
      hour = _sayiKelime[g.group(1)!];
      used[i] = true;
    } else if (k != null &&
        k <= 24 &&
        ((i > 0 && w[i - 1] == 'saat') ||
            _ekler.contains(nx(i)) ||
            nx(i).startsWith('buçuk'))) {
      hour = k;
      used[i] = true;
      if (nx(i).startsWith('buçuk')) {
        minute = 30;
        used[i + 1] = true;
      }
    } else {
      continue;
    }
    if (i > 0 && w[i - 1] == 'saat') used[i - 1] = true;
    int j = i;
    while (j + 1 < n && !used[j + 1] && _ekler.contains(w[j + 1])) {
      used[j + 1] = true;
      j++;
    }
  }

  // başlık
  final words = <String>[];
  bool oncekiKaldi = false;
  for (int i = 0; i < n; i++) {
    final keep = !used[i] && !_dolgu.contains(w[i]);
    if (keep && glue[i]) {
      if (oncekiKaldi && words.isNotEmpty) {
        words[words.length - 1] = "${words.last}'${orig[i]}";
      }
    } else if (keep) {
      words.add(orig[i]);
    }
    oncekiKaldi = keep;
  }
  if (words.length > 1 && trLower(words.last) == 'için') words.removeLast();
  final title = words.isEmpty ? 'Hatırlatıcı' : trBuyuk(words.join(' '));

  // zaman
  final today = DateTime(now.year, now.month, now.day);
  if (relMin != null) {
    final t = now.add(Duration(minutes: relMin));
    return Parsed(title, DateTime(t.year, t.month, t.day, t.hour, t.minute));
  }
  DateTime? date;
  if (relDays != null) {
    date = gunEkle(today, relDays);
  } else if (dayD != null && dayM != null) {
    date = DateTime(now.year, dayM, dayD);
  } else if (wday != null) {
    if (haftaya) {
      date = gunEkle(today, -(today.weekday - 1) + 7 + wday - 1);
    } else {
      date = gunEkle(today, (wday - today.weekday + 7) % 7);
    }
  } else if (dayoff != null) {
    date = gunEkle(today, dayoff);
  } else if (haftaya) {
    date = gunEkle(today, 7);
  }

  int hh;
  int mm;
  if (hour == null && period == null) {
    if (date == null) return Parsed(title, null);
    hh = 9;
    mm = 0;
  } else if (hour == null) {
    switch (period) {
      case 'sabah':
        hh = 9;
        break;
      case 'ogle':
        hh = 12;
        break;
      case 'ogleden':
        hh = 14;
        break;
      case 'aksam':
        hh = 19;
        break;
      default:
        hh = 22;
    }
    mm = 0;
  } else {
    hh = hour;
    mm = minute;
    if (period == 'aksam' && hh < 12) {
      hh += 12;
    } else if (period == 'gece') {
      if (hh == 12) {
        hh = 0;
      } else if (hh >= 6 && hh < 12) {
        hh += 12;
      }
    } else if (period == 'ogleden' && hh < 12) {
      hh += 12;
    } else if (period == 'ogle' && hh >= 1 && hh <= 6) {
      hh += 12;
    }
  }
  if (hh > 23) hh = 23;
  final belirsiz = hour != null && period == null && hh >= 1 && hh <= 11;

  if (date == null) {
    var cand = DateTime(today.year, today.month, today.day, hh, mm);
    if (!cand.isAfter(now) &&
        belirsiz &&
        cand.add(const Duration(hours: 12)).isAfter(now)) {
      cand = cand.add(const Duration(hours: 12));
    }
    if (!cand.isAfter(now)) cand = DateTime(cand.year, cand.month, cand.day + 1, hh, mm);
    return Parsed(title, cand);
  }
  var cand = DateTime(date.year, date.month, date.day, hh, mm);
  if (!cand.isAfter(now)) {
    if (gunFarki(date, now) == 0 &&
        belirsiz &&
        wday == null &&
        cand.add(const Duration(hours: 12)).isAfter(now)) {
      cand = cand.add(const Duration(hours: 12));
    } else if (wday != null && !haftaya) {
      cand = DateTime(cand.year, cand.month, cand.day + 7, hh, mm);
    } else if (dayD != null) {
      cand = DateTime(cand.year + 1, cand.month, cand.day, hh, mm);
    } else {
      return Parsed(title, null);
    }
  }
  return Parsed(title, cand);
}

// ---------------------------------------------------------------- bildirimler ve ses

NotificationDetails alarmDetails() {
  return NotificationDetails(
    android: AndroidNotificationDetails(
      kChAlarm,
      'Hatırlatmalar',
      channelDescription: 'Zamanı gelen hatırlatmalar (alarm sesiyle)',
      importance: Importance.max,
      priority: Priority.max,
      category: AndroidNotificationCategory.alarm,
      fullScreenIntent: true,
      audioAttributesUsage: AudioAttributesUsage.alarm,
      playSound: true,
      enableVibration: true,
      vibrationPattern: Int64List.fromList(<int>[0, 700, 300, 700, 300, 700]),
      additionalFlags: Int32List.fromList(<int>[4]),
      timeoutAfter: 180000,
      ticker: 'Hatırlatma',
      actions: const <AndroidNotificationAction>[
        AndroidNotificationAction('tamam', 'Tamam'),
        AndroidNotificationAction('ertele', '10 dk ertele'),
      ],
    ),
  );
}

NotificationDetails onceDetails() {
  return const NotificationDetails(
    android: AndroidNotificationDetails(
      kChOnce,
      'Önceden haber',
      channelDescription: 'Bir gün önceden hatırlatma',
      importance: Importance.high,
      priority: Priority.high,
    ),
  );
}

Future<void> initNotifications() async {
  tzdata.initializeTimeZones();
  tz.setLocalLocation(tz.getLocation('Europe/Istanbul'));
  const init = InitializationSettings(
    android: AndroidInitializationSettings('@mipmap/ic_launcher'),
  );
  await plugin.initialize(
    init,
    onDidReceiveNotificationResponse: onResponseFg,
    onDidReceiveBackgroundNotificationResponse: onResponseBg,
  );
  final a = plugin.resolvePlatformSpecificImplementation<
      AndroidFlutterLocalNotificationsPlugin>();
  await a?.createNotificationChannel(const AndroidNotificationChannel(
    kChAlarm,
    'Hatırlatmalar',
    description: 'Zamanı gelen hatırlatmalar (alarm sesiyle)',
    importance: Importance.max,
    playSound: true,
    enableVibration: true,
    audioAttributesUsage: AudioAttributesUsage.alarm,
  ));
  await a?.createNotificationChannel(const AndroidNotificationChannel(
    kChOnce,
    'Önceden haber',
    description: 'Bir gün önceden hatırlatma',
    importance: Importance.high,
  ));
}

Future<void> initTts() async {
  try {
    await tts.setLanguage('tr-TR');
    await tts.setSpeechRate(0.45);
    await tts.setVolume(1.0);
  } catch (_) {}
}

Future<void> konus(String metin) async {
  try {
    await tts.stop();
    await tts.speak(metin);
  } catch (_) {}
}

Future<void> zamanla(
  int bildirimId,
  int hatId,
  String baslik,
  DateTime when, {
  required bool alarm,
  String? govde,
}) async {
  if (!when.isAfter(DateTime.now())) return;
  final d = tz.TZDateTime.from(when, tz.local);
  final det = alarm ? alarmDetails() : onceDetails();
  final body = govde ?? 'Hatırlatma zamanı';
  final payload = '$hatId|$baslik';
  try {
    await plugin.zonedSchedule(
      bildirimId,
      baslik,
      body,
      d,
      det,
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      payload: payload,
    );
  } catch (_) {
    await plugin.zonedSchedule(
      bildirimId,
      baslik,
      body,
      d,
      det,
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      payload: payload,
    );
  }
}

Future<void> iptalHat(int id) async {
  await plugin.cancel(id * 10 + 1);
  await plugin.cancel(id * 10 + 2);
  await plugin.cancel(id * 10 + 3);
}

Future<void> kurHat(Hat h) async {
  await iptalHat(h.id);
  if (h.done) return;
  await zamanla(h.id * 10 + 1, h.id, h.title, h.when, alarm: true);
  if (h.early) {
    final w = h.when;
    final e = DateTime(w.year, w.month, w.day - 1, 20, 0);
    await zamanla(h.id * 10 + 2, h.id, 'Yarın: ${h.title}', e,
        alarm: false, govde: 'Yarın saat ${hhmm(w)}');
  }
}

Future<void> hepsiniYenidenKur(List<Hat> l) async {
  for (final h in l) {
    if (!h.done) {
      try {
        await kurHat(h);
      } catch (_) {}
    }
  }
}

void onResponseFg(NotificationResponse r) {
  yanitIsle(r, fg: true);
}

@pragma('vm:entry-point')
void onResponseBg(NotificationResponse r) {
  yanitIsle(r, fg: false);
}

Future<void> yanitIsle(NotificationResponse r, {required bool fg}) async {
  final payload = r.payload ?? '';
  final i = payload.indexOf('|');
  final id = int.tryParse(i > 0 ? payload.substring(0, i) : payload) ?? 0;
  final baslik = i >= 0 ? payload.substring(i + 1) : 'Hatırlatma';
  try {
    if (r.actionId == 'ertele') {
      if (!fg) await initNotifications();
      final yeni = DateTime.now().add(const Duration(minutes: 10));
      await zamanla(id * 10 + 3, id, baslik, yeni, alarm: true);
      final l = await Store.load();
      final k = l.indexWhere((e) => e.id == id);
      if (k >= 0) {
        l[k].whenMs = yeni.millisecondsSinceEpoch;
        l[k].done = false;
        await Store.save(l);
      }
    } else if (r.actionId == 'tamam') {
      final l = await Store.load();
      final k = l.indexWhere((e) => e.id == id);
      if (k >= 0) {
        l[k].done = true;
        await Store.save(l);
      }
      await plugin.cancel(id * 10 + 2);
      await plugin.cancel(id * 10 + 3);
    } else if (fg) {
      await plugin.cancel(id * 10 + 1);
      await plugin.cancel(id * 10 + 3);
      await konus('Hatırlatma. $baslik');
    }
    yenileSinyali.value++;
  } catch (_) {}
}

// ---------------------------------------------------------------- uygulama

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initNotifications();
  await initTts();
  runApp(const HatApp());
}

class HatApp extends StatelessWidget {
  const HatApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Hatırlatıcı',
      debugShowCheckedModeBanner: false,
      locale: const Locale('tr', 'TR'),
      supportedLocales: const [Locale('tr', 'TR')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: const Color(0xFF3F51B5),
        brightness: Brightness.light,
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: const Color(0xFF3F51B5),
        brightness: Brightness.dark,
      ),
      themeMode: ThemeMode.system,
      home: const AnaSayfa(),
    );
  }
}

class AnaSayfa extends StatefulWidget {
  const AnaSayfa({super.key});

  @override
  State<AnaSayfa> createState() => _AnaSayfaState();
}

class _AnaSayfaState extends State<AnaSayfa> with WidgetsBindingObserver {
  List<Hat> items = [];
  Timer? _timer;
  final Set<String> _okundu = {};
  bool _uyari = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    yenileSinyali.addListener(_yukle);
    _baslat();
    _timer = Timer.periodic(const Duration(seconds: 15), (_) => _nabiz());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    yenileSinyali.removeListener(_yukle);
    _timer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _yukle();
      _saglikKontrol();
    }
  }

  Future<void> _baslat() async {
    final l = await Store.load();
    if (!mounted) return;
    setState(() => items = l);
    await hepsiniYenidenKur(l);
    await _saglikKontrol();
    // Bildirime dokunarak açıldıysa başlığı sesli oku
    try {
      final d = await plugin.getNotificationAppLaunchDetails();
      final resp = d?.notificationResponse;
      if (d != null && d.didNotificationLaunchApp && resp != null) {
        final p = resp.payload ?? '';
        final i = p.indexOf('|');
        if (i > 0 && (resp.actionId == null || resp.actionId!.isEmpty)) {
          final hid = int.tryParse(p.substring(0, i)) ?? 0;
          await plugin.cancel(hid * 10 + 1);
          await plugin.cancel(hid * 10 + 3);
          await konus('Hatırlatma. ${p.substring(i + 1)}');
        }
      }
    } catch (_) {}
    final sp = await SharedPreferences.getInstance();
    if (!(sp.getBool('kurulum_gosterildi') ?? false)) {
      await sp.setBool('kurulum_gosterildi', true);
      if (mounted) _kurulumAc();
    }
  }

  Future<void> _yukle() async {
    final l = await Store.load();
    if (!mounted) return;
    setState(() => items = l);
  }

  Future<void> _saglikKontrol() async {
    try {
      final a = plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      final n = await a?.areNotificationsEnabled() ?? true;
      final e = await a?.canScheduleExactNotifications() ?? true;
      if (mounted) setState(() => _uyari = !(n && e));
    } catch (_) {}
  }

  // Uygulama açıkken zamanı gelen hatırlatmayı sesli oku
  Future<void> _nabiz() async {
    await _yukle();
    final now = DateTime.now();
    for (final h in items) {
      if (h.done) continue;
      final fark = now.difference(h.when);
      final anahtar = '${h.id}-${h.whenMs}';
      if (!fark.isNegative &&
          fark < const Duration(minutes: 2) &&
          !_okundu.contains(anahtar)) {
        _okundu.add(anahtar);
        await konus('Hatırlatma. ${h.title}');
      }
    }
  }

  Future<void> _mikrofon() async {
    final metin = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const SesPenceresi(),
    );
    if (metin == null || metin.trim().isEmpty || !mounted) return;
    final p = parseTr(metin, DateTime.now());
    await _duzenle(
      baslik: p.title,
      zaman: p.when,
      duyulan: metin,
    );
  }

  Future<void> _elleEkle() async {
    await _duzenle(baslik: '', zaman: null, duyulan: null);
  }

  Future<void> _duzenle({
    required String baslik,
    required DateTime? zaman,
    String? duyulan,
    Hat? mevcut,
  }) async {
    final d = await showModalBottomSheet<Taslak>(
      context: context,
      isScrollControlled: true,
      builder: (_) => DuzenlePenceresi(
        baslik: baslik,
        zaman: zaman,
        erken: mevcut?.early,
        duyulan: duyulan,
      ),
    );
    if (d == null) return;
    final l = await Store.load();
    Hat h;
    if (mevcut != null) {
      final i = l.indexWhere((e) => e.id == mevcut.id);
      if (i >= 0) {
        h = l[i];
      } else {
        h = Hat(id: mevcut.id, title: d.baslik, whenMs: 0);
        l.add(h);
      }
      h.title = d.baslik;
      h.whenMs = d.zaman.millisecondsSinceEpoch;
      h.early = d.erken;
      h.done = false;
    } else {
      h = Hat(
        id: await Store.nextId(),
        title: d.baslik,
        whenMs: d.zaman.millisecondsSinceEpoch,
        early: d.erken,
      );
      l.add(h);
    }
    await Store.save(l);
    String? hata;
    try {
      await kurHat(h);
    } catch (e) {
      hata = 'Alarm kurulamadı: $e';
    }
    if (!mounted) return;
    setState(() => items = l);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(hata ?? 'Kuruldu: ${zamanYazisi(h.when, DateTime.now())}'),
    ));
  }

  Future<void> _bitti(Hat h, bool deger) async {
    final l = await Store.load();
    final i = l.indexWhere((e) => e.id == h.id);
    if (i < 0) return;
    l[i].done = deger;
    await Store.save(l);
    try {
      if (deger) {
        await iptalHat(h.id);
      } else {
        await kurHat(l[i]);
      }
    } catch (_) {}
    if (mounted) setState(() => items = l);
  }

  Future<void> _sil(Hat h) async {
    setState(() => items = items.where((e) => e.id != h.id).toList());
    final l = await Store.load();
    l.removeWhere((e) => e.id == h.id);
    await Store.save(l);
    try {
      await iptalHat(h.id);
    } catch (_) {}
    if (!mounted) return;
    setState(() => items = l);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('Silindi: ${h.title}'),
      action: SnackBarAction(
        label: 'Geri al',
        onPressed: () async {
          final l2 = await Store.load();
          l2.add(h);
          await Store.save(l2);
          try {
            await kurHat(h);
          } catch (_) {}
          if (mounted) setState(() => items = l2);
        },
      ),
    ));
  }

  void _kurulumAc() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const KurulumPenceresi(),
    ).then((_) => _saglikKontrol());
  }

  Widget _satir(Hat h, DateTime now, {Color? renk}) {
    final gecmis = !h.done && h.when.isBefore(now);
    final cs = Theme.of(context).colorScheme;
    return Dismissible(
      key: ValueKey('h${h.id}'),
      direction: DismissDirection.endToStart,
      background: Container(
        color: cs.errorContainer,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 24),
        child: Icon(Icons.delete_outline, color: cs.onErrorContainer),
      ),
      onDismissed: (_) => _sil(h),
      child: ListTile(
        leading: IconButton(
          icon: Icon(h.done ? Icons.check_circle : Icons.radio_button_unchecked),
          color: h.done ? cs.primary : (renk ?? cs.outline),
          tooltip: h.done ? 'Geri al' : 'Tamamlandı',
          onPressed: () => _bitti(h, !h.done),
        ),
        title: Text(
          h.title,
          style: TextStyle(
            fontSize: 17,
            decoration: h.done ? TextDecoration.lineThrough : null,
            color: h.done ? cs.outline : null,
          ),
        ),
        subtitle: Text(
          '${zamanYazisi(h.when, now)}${h.early && !h.done ? '  •  bir gün önce de haber' : ''}',
          style: TextStyle(color: gecmis ? cs.error : null),
        ),
        onTap: () => _duzenle(
          baslik: h.title,
          zaman: h.when,
          mevcut: h,
        ),
      ),
    );
  }

  List<Widget> _bolum(String ad, List<Hat> l, DateTime now, {Color? renk}) {
    if (l.isEmpty) return [];
    return [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 4),
        child: Text(
          ad,
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                color: renk ?? Theme.of(context).colorScheme.primary,
                fontWeight: FontWeight.w700,
              ),
        ),
      ),
      ...l.map((h) => _satir(h, now, renk: renk)),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final cs = Theme.of(context).colorScheme;
    final aktif = items.where((e) => !e.done).toList()
      ..sort((a, b) => a.whenMs.compareTo(b.whenMs));
    final bitenler = items.where((e) => e.done).toList()
      ..sort((a, b) => b.whenMs.compareTo(a.whenMs));
    final kacan = aktif.where((e) => e.when.isBefore(now)).toList();
    final gelecek = aktif.where((e) => !e.when.isBefore(now)).toList();
    final bugun = gelecek.where((e) => gunFarki(e.when, now) == 0).toList();
    final yarin = gelecek.where((e) => gunFarki(e.when, now) == 1).toList();
    final hafta = gelecek
        .where((e) => gunFarki(e.when, now) >= 2 && gunFarki(e.when, now) <= 7)
        .toList();
    final sonra = gelecek.where((e) => gunFarki(e.when, now) > 7).toList();

    final govde = <Widget>[];
    if (_uyari) {
      govde.add(Card(
        color: cs.errorContainer,
        margin: const EdgeInsets.all(12),
        child: ListTile(
          leading: Icon(Icons.warning_amber_rounded, color: cs.onErrorContainer),
          title: Text('Bildirim izni eksik',
              style: TextStyle(color: cs.onErrorContainer)),
          subtitle: Text('Alarmın çalması için ayarı düzelt',
              style: TextStyle(color: cs.onErrorContainer)),
          trailing: FilledButton(onPressed: _kurulumAc, child: const Text('Düzelt')),
        ),
      ));
    }
    govde.addAll(_bolum('Kaçırılan', kacan, now, renk: cs.error));
    govde.addAll(_bolum('Bugün', bugun, now));
    govde.addAll(_bolum('Yarın', yarin, now));
    govde.addAll(_bolum('Bu hafta', hafta, now));
    govde.addAll(_bolum('Daha sonra', sonra, now));
    if (bitenler.isNotEmpty) {
      govde.add(Padding(
        padding: const EdgeInsets.only(top: 12),
        child: ExpansionTile(
          title: Text('Tamamlananlar (${bitenler.length})'),
          children: bitenler.map((h) => _satir(h, now)).toList(),
        ),
      ));
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Hatırlatıcı'),
        actions: [
          IconButton(
            tooltip: 'Telefon ayarları',
            icon: Badge(
              isLabelVisible: _uyari,
              child: const Icon(Icons.shield_outlined),
            ),
            onPressed: _kurulumAc,
          ),
        ],
      ),
      body: aktif.isEmpty && bitenler.isEmpty && !_uyari
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.mic_none, size: 72, color: cs.primary),
                    const SizedBox(height: 16),
                    const Text(
                      'Mikrofona bas ve söyle',
                      style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      '“Yarın akşam 8\'de toptancıyı ara”\n'
                      '“Haftaya salı saat 10\'da doktor”\n'
                      '“2 saat sonra ütüyü kapat”',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: cs.outline, height: 1.6),
                    ),
                  ],
                ),
              ),
            )
          : ListView(
              padding: const EdgeInsets.only(bottom: 150),
              children: govde,
            ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          FloatingActionButton.small(
            heroTag: 'ekle',
            tooltip: 'Yazarak ekle',
            onPressed: _elleEkle,
            child: const Icon(Icons.edit_outlined),
          ),
          const SizedBox(width: 20),
          FloatingActionButton.large(
            heroTag: 'mik',
            tooltip: 'Konuş',
            onPressed: _mikrofon,
            child: const Icon(Icons.mic, size: 40),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- ses penceresi

class SesPenceresi extends StatefulWidget {
  const SesPenceresi({super.key});

  @override
  State<SesPenceresi> createState() => _SesPenceresiState();
}

class _SesPenceresiState extends State<SesPenceresi> {
  final stt.SpeechToText _sp = stt.SpeechToText();
  String _metin = '';
  String _mesaj = 'Hazırlanıyor…';
  double _seviye = 0;
  bool _kapandi = false;
  bool _hata = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _basla());
  }

  @override
  void dispose() {
    _kapandi = true;
    try {
      _sp.cancel();
    } catch (_) {}
    super.dispose();
  }

  void _bitir() {
    if (_kapandi) return;
    _kapandi = true;
    try {
      _sp.stop();
    } catch (_) {}
    if (mounted) Navigator.of(context).pop(_metin.trim());
  }

  void _basarisiz(String m) {
    if (!mounted || _kapandi) return;
    if (_metin.trim().isNotEmpty) {
      _bitir();
      return;
    }
    setState(() {
      _hata = true;
      _mesaj = m;
    });
  }

  Future<void> _basla() async {
    if (!mounted) return;
    setState(() {
      _hata = false;
      _metin = '';
      _mesaj = 'Hazırlanıyor…';
    });
    bool ok = false;
    try {
      ok = await _sp.initialize(
        onStatus: (s) {
          if (s == 'done' || s == 'notListening') {
            if (_metin.trim().isNotEmpty) {
              _bitir();
            } else if (!_hata && mounted && !_kapandi) {
              _basarisiz('Ses duyamadım. Tekrar dene.');
            }
          }
        },
        onError: (e) => _basarisiz('Anlayamadım. Tekrar dene.'),
      );
    } catch (_) {
      ok = false;
    }
    if (!ok) {
      _basarisiz(
          'Mikrofon izni verilmedi ya da ses tanıma kapalı. Telefon ayarlarından izin ver.');
      return;
    }
    String? loc;
    try {
      final l = await _sp.locales();
      for (final x in l) {
        if (x.localeId.toLowerCase().replaceAll('-', '_') == 'tr_tr') {
          loc = x.localeId;
        }
      }
    } catch (_) {}
    if (!mounted || _kapandi) return;
    setState(() => _mesaj = 'Dinliyorum… konuş');
    await _sp.listen(
      onResult: (SpeechRecognitionResult r) {
        if (!mounted || _kapandi) return;
        setState(() => _metin = r.recognizedWords);
        if (r.finalResult && _metin.trim().isNotEmpty) _bitir();
      },
      localeId: loc,
      listenFor: const Duration(seconds: 40),
      pauseFor: const Duration(seconds: 3),
      onSoundLevelChange: (double v) {
        if (mounted && !_kapandi) setState(() => _seviye = v);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final boy = 96.0 + max(0.0, min(10.0, _seviye)) * 6.0;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              height: 170,
              child: Center(
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 120),
                  width: boy,
                  height: boy,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _hata ? cs.errorContainer : cs.primaryContainer,
                  ),
                  child: Icon(
                    _hata ? Icons.mic_off : Icons.mic,
                    size: 48,
                    color: _hata ? cs.onErrorContainer : cs.onPrimaryContainer,
                  ),
                ),
              ),
            ),
            Text(_mesaj, style: TextStyle(color: cs.outline, fontSize: 15)),
            const SizedBox(height: 12),
            ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 60),
              child: Text(
                _metin,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () {
                      _kapandi = true;
                      Navigator.of(context).pop();
                    },
                    child: const Text('Vazgeç'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: _hata
                        ? () {
                            _kapandi = false;
                            _basla();
                          }
                        : _bitir,
                    child: Text(_hata ? 'Tekrar dene' : 'Bitti'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- düzenleme penceresi

class Taslak {
  final String baslik;
  final DateTime zaman;
  final bool erken;
  Taslak(this.baslik, this.zaman, this.erken);
}

class DuzenlePenceresi extends StatefulWidget {
  final String baslik;
  final DateTime? zaman;
  final bool? erken;
  final String? duyulan;
  const DuzenlePenceresi({
    super.key,
    required this.baslik,
    required this.zaman,
    this.erken,
    this.duyulan,
  });

  @override
  State<DuzenlePenceresi> createState() => _DuzenlePenceresiState();
}

class _DuzenlePenceresiState extends State<DuzenlePenceresi> {
  late final TextEditingController _c;
  late DateTime _zaman;
  late bool _zamanBelli;
  late bool _erken;
  bool _erkenElle = false;

  @override
  void initState() {
    super.initState();
    _c = TextEditingController(text: widget.baslik);
    final now = DateTime.now();
    _zamanBelli = widget.zaman != null;
    _zaman = widget.zaman ??
        DateTime(now.year, now.month, now.day, now.hour + 1, 0);
    _erkenElle = widget.erken != null;
    _erken = widget.erken ?? _otoErken();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  bool _otoErken() =>
      _zamanBelli && _zaman.difference(DateTime.now()) >= const Duration(hours: 36);

  void _zamanDegisti(DateTime z) {
    setState(() {
      _zaman = z;
      _zamanBelli = true;
      if (!_erkenElle) _erken = _otoErken();
    });
  }

  Future<void> _tarihSec() async {
    final bugun = DateTime.now();
    final ilk = DateTime(bugun.year, bugun.month, bugun.day);
    var baslangic = DateTime(_zaman.year, _zaman.month, _zaman.day);
    if (baslangic.isBefore(ilk)) baslangic = ilk;
    final d = await showDatePicker(
      context: context,
      initialDate: baslangic,
      firstDate: ilk,
      lastDate: DateTime(bugun.year + 3, 12, 31),
      helpText: 'Hangi gün?',
      cancelText: 'Vazgeç',
      confirmText: 'Tamam',
    );
    if (d == null) return;
    _zamanDegisti(DateTime(d.year, d.month, d.day, _zaman.hour, _zaman.minute));
  }

  Future<void> _saatSec() async {
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: _zaman.hour, minute: _zaman.minute),
      helpText: 'Saat kaç?',
      cancelText: 'Vazgeç',
      confirmText: 'Tamam',
      builder: (c, child) => MediaQuery(
        data: MediaQuery.of(c).copyWith(alwaysUse24HourFormat: true),
        child: child!,
      ),
    );
    if (t == null) return;
    _zamanDegisti(DateTime(_zaman.year, _zaman.month, _zaman.day, t.hour, t.minute));
  }

  Widget _hizli(String ad, DateTime Function(DateTime) f) {
    return ActionChip(
      label: Text(ad),
      onPressed: () => _zamanDegisti(f(DateTime.now())),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final now = DateTime.now();
    final gecmis = !_zaman.isAfter(now);
    final gecerli = _c.text.trim().isNotEmpty && _zamanBelli && !gecmis;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
            20, 20, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (widget.duyulan != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Text('Duydum: “${widget.duyulan}”',
                      style: TextStyle(color: cs.outline)),
                ),
              TextField(
                controller: _c,
                autofocus: widget.baslik.isEmpty,
                textCapitalization: TextCapitalization.sentences,
                style: const TextStyle(fontSize: 20),
                decoration: const InputDecoration(
                  labelText: 'Ne yapılacak?',
                  border: OutlineInputBorder(),
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 14),
              if (!_zamanBelli)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text('Zamanı anlayamadım, aşağıdan seç.',
                      style: TextStyle(color: cs.error)),
                ),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.calendar_today, size: 18),
                      onPressed: _tarihSec,
                      label: Text(_zamanBelli ? gunEtiketi(_zaman, now) : 'Gün seç'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.access_time, size: 18),
                      onPressed: _saatSec,
                      label: Text(_zamanBelli ? hhmm(_zaman) : 'Saat seç'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                children: [
                  _hizli('10 dk', (n) => n.add(const Duration(minutes: 10))),
                  _hizli('1 saat', (n) => n.add(const Duration(hours: 1))),
                  _hizli('Bu akşam',
                      (n) => DateTime(n.year, n.month, n.day, 20, 0)),
                  _hizli('Yarın sabah',
                      (n) => DateTime(n.year, n.month, n.day + 1, 9, 0)),
                  _hizli('Haftaya',
                      (n) => DateTime(n.year, n.month, n.day + 7, 9, 0)),
                ],
              ),
              if (gecmis && _zamanBelli)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text('Bu zaman geçmişte, başka bir zaman seç.',
                      style: TextStyle(color: cs.error)),
                ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Bir gün önce de haber ver'),
                subtitle: const Text('Önceki akşam saat 20:00'),
                value: _erken,
                onChanged: (v) => setState(() {
                  _erken = v;
                  _erkenElle = true;
                }),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Vazgeç'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: FilledButton(
                      onPressed: gecerli
                          ? () => Navigator.of(context).pop(
                                Taslak(_c.text.trim(), _zaman, _erken),
                              )
                          : null,
                      child: const Text('Kaydet'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- telefon ayarları

class KurulumPenceresi extends StatefulWidget {
  const KurulumPenceresi({super.key});

  @override
  State<KurulumPenceresi> createState() => _KurulumPenceresiState();
}

class _KurulumPenceresiState extends State<KurulumPenceresi>
    with WidgetsBindingObserver {
  bool? _bildirim;
  bool? _alarm;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _kontrol();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _kontrol();
  }

  AndroidFlutterLocalNotificationsPlugin? get _a => plugin
      .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();

  Future<void> _kontrol() async {
    try {
      final n = await _a?.areNotificationsEnabled();
      final e = await _a?.canScheduleExactNotifications();
      if (mounted) {
        setState(() {
          _bildirim = n;
          _alarm = e;
        });
      }
    } catch (_) {}
  }

  Future<void> _intent(String action, {String? data}) async {
    try {
      await AndroidIntent(action: action, data: data).launch();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Bu ayar sayfası telefonunda açılmadı. '
                'Ayarlar > Uygulamalar > Hatırlatıcı yolunu dene.')));
      }
    }
  }

  Widget _madde({
    required String baslik,
    required String aciklama,
    required String buton,
    required VoidCallback onPressed,
    bool? tamam,
  }) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(
            tamam == null
                ? Icons.info_outline
                : (tamam ? Icons.check_circle : Icons.error_outline),
            color: tamam == null ? cs.outline : (tamam ? Colors.green : cs.error),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(baslik,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                Text(aciklama, style: TextStyle(color: cs.outline, fontSize: 13)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (tamam != true)
            FilledButton.tonal(onPressed: onPressed, child: Text(buton)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Alarmın unutulmaması için',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            const Text('Bu dört ayarı bir kez yap, sonra hiç dokunma.'),
            const SizedBox(height: 8),
            _madde(
              baslik: '1. Bildirim izni',
              aciklama: 'Hatırlatma görünsün ve çalsın',
              buton: 'İzin ver',
              tamam: _bildirim,
              onPressed: () async {
                await _a?.requestNotificationsPermission();
                _kontrol();
              },
            ),
            _madde(
              baslik: '2. Tam zamanında alarm',
              aciklama: 'Saati dakikası dakikasına tutsun',
              buton: 'İzin ver',
              tamam: _alarm,
              onPressed: () async {
                await _a?.requestExactAlarmsPermission();
                _kontrol();
              },
            ),
            _madde(
              baslik: '3. Pil kısıtlaması yok',
              aciklama:
                  'Açılan listede Hatırlatıcı’yı bul, “Kısıtlama yok / Optimize etme” seç',
              buton: 'Aç',
              onPressed: () =>
                  _intent('android.settings.IGNORE_BATTERY_OPTIMIZATION_SETTINGS'),
            ),
            _madde(
              baslik: '4. Kilit ekranında aç',
              aciklama: 'Ekran kilitliyken alarm ekranı açılsın (Android 14)',
              buton: 'Aç',
              onPressed: () => _intent(
                'android.settings.MANAGE_APP_USE_FULL_SCREEN_INTENT',
                data: 'package:$kPaket',
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                icon: const Icon(Icons.volume_up),
                label: const Text('Şimdi çal (hemen dene)'),
                onPressed: () async {
                  final nav = ScaffoldMessenger.of(context);
                  try {
                    await plugin.show(999998, 'Deneme', 'Hemen gösterilen bildirim',
                        alarmDetails(), payload: '0|Deneme');
                  } catch (e) {
                    nav.showSnackBar(SnackBar(content: Text('Hata: $e')));
                  }
                },
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                icon: const Icon(Icons.notifications_active_outlined),
                label: const Text('Dene: 15 saniye sonra çalsın'),
                onPressed: () async {
                  final nav = ScaffoldMessenger.of(context);
                  try {
                    await zamanla(
                      999999,
                      0,
                      'Deneme hatırlatması',
                      DateTime.now().add(const Duration(seconds: 15)),
                      alarm: true,
                    );
                    nav.showSnackBar(const SnackBar(
                        content: Text(
                            'Kuruldu. Ekranı kilitleyip bekle, çalıyor mu bak.')));
                  } catch (e) {
                    nav.showSnackBar(SnackBar(content: Text('Kurulamadı: $e')));
                  }
                },
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Samsung, Xiaomi, Huawei gibi telefonlarda ayrıca “uyku moduna alınan '
              'uygulamalar” listesinden Hatırlatıcı’yı çıkar.',
              style: TextStyle(color: Theme.of(context).colorScheme.outline, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}
