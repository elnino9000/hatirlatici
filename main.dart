import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:alarm/alarm.dart' as alm;
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

const kChAlarm = 'hatirlatici_alarm_v2';
const kChOnce = 'hatirlatici_onceden_v1';
const kPaket = 'com.hatirlatici.hatirlatici';

final FlutterLocalNotificationsPlugin plugin = FlutterLocalNotificationsPlugin();
final FlutterTts tts = FlutterTts();
final ValueNotifier<int> yenileSinyali = ValueNotifier<int>(0);

const kArka = Color(0xFF0A0E1F);
const kYuzey = Color(0xFF151A33);
const kYuzey2 = Color(0xFF1E2550);
const kMor = Color(0xFF7C5CFF);
const kMavi = Color(0xFF3D8BFF);
const kYesil = Color(0xFF2EE6A6);
const kSari = Color(0xFFFFB84D);
const kKirmizi = Color(0xFFFF5C6C);
const kGri = Color(0xFF6B7299);
const kSoluk = Color(0xFF8E96C7);
const kGradyan = LinearGradient(
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
  colors: [kMor, kMavi],
);
const _ayTam = [
  'Ocak',
  'Şubat',
  'Mart',
  'Nisan',
  'Mayıs',
  'Haziran',
  'Temmuz',
  'Ağustos',
  'Eylül',
  'Ekim',
  'Kasım',
  'Aralık'
];
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

const Map<String, int> _birler = {
  'sıfır': 0,
  'bir': 1,
  'iki': 2,
  'üç': 3,
  'dört': 4,
  'dörd': 4,
  'beş': 5,
  'altı': 6,
  'yedi': 7,
  'sekiz': 8,
  'dokuz': 9,
};
const Map<String, int> _onlar = {
  'on': 10,
  'yirmi': 20,
  'otuz': 30,
  'kırk': 40,
  'elli': 50,
};
const List<String> _ekListe = [
  'de', 'da', 'te', 'ta', 'ye', 'ya', 'yi', 'yı', 'yu', 'yü', //
  'e', 'a', 'i', 'ı', 'u', 'ü',
];
const Set<String> _uzunEk = {
  'gibi',
  'civarı',
  'civarında',
  'sularında',
  'itibaren'
};
final Set<String> _ekSet = {..._ekListe, ..._uzunEk};
const Set<String> _yerEk = {'de', 'da', 'te', 'ta'};
const List<MapEntry<String, int>> _gunler = [
  MapEntry('pazartesi', 1),
  MapEntry('salı', 2),
  MapEntry('çarşamba', 3),
  MapEntry('perşembe', 4),
  MapEntry('cumartesi', 6),
  MapEntry('cuma', 5),
  MapEntry('pazar', 7),
];
const Set<String> _gunEkleri = {
  '',
  'ya',
  'ye',
  'a',
  'e',
  'yı',
  'yi',
  'ı',
  'i',
  'da',
  'de',
  'dan',
  'den',
  'nın',
  'nin',
  'günü'
};
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
const Set<String> _dolgu = {
  'bana',
  'bize',
  'beni',
  'lütfen',
  'hatırlat',
  'hatırlatır',
  'hatırlatsana',
  'hatırlatıcı',
  'hatırlatma',
  'hatırla',
  'unutma',
  'diye',
  'kur',
  'ayarla',
  'alarm',
  'uyar',
  'uyarı',
};
const Set<String> _sayiDegil = {
  'tane',
  'adet',
  'kilo',
  'kg',
  'lira',
  'tl',
  'gün',
  'hafta',
  'ay',
  'dakika',
  'dk',
  'saat',
  'kişi',
  'metre',
  'litre',
  'paket',
  'kutu',
  'yıl',
  'sene'
};
const Map<String, String> _bolumler = {
  'sabah': 'sabah',
  'sabahleyin': 'sabah',
  'öğle': 'ogle',
  'öğlen': 'ogle',
  'öğleyin': 'ogle',
  'akşam': 'aksam',
  'akşamleyin': 'aksam',
  'akşamüstü': 'aksam',
  'gece': 'gece',
  'geceleyin': 'gece',
};
const Set<String> _zamanBirim = {'dakika', 'dk', 'saat', 'gün', 'hafta', 'ay'};
const Set<String> _sonraSozu = {'sonra', 'içinde', 'sonrasına'};
const Set<String> _ayGunEki = {'inde', 'ında', 'unda', 'ünde', 'sinde', 'sında'};
final RegExp _saatDk = RegExp(r'^(\d{1,2})[:.](\d{2})$');
final RegExp _sayiRe = RegExp(r'^\d{1,2}$');
final RegExp _rakamEk =
    RegExp(r'^(\d{1,2}(?:[:.]\d{2})?)([a-zA-ZçğıöşüÇĞİÖŞÜ]+)$');

class _Kok {
  final int v;
  final bool sx;
  _Kok(this.v, this.sx);
}

class _Say {
  final int v;
  final int c;
  final bool sx;
  final bool kelime;
  _Say(this.v, this.c, this.sx, this.kelime);
}

_Kok? _kokCoz(String t) {
  if (_birler.containsKey(t)) return _Kok(_birler[t]!, false);
  if (_onlar.containsKey(t)) return _Kok(_onlar[t]!, false);
  for (final sf in _ekListe) {
    if (t.length > sf.length && t.endsWith(sf)) {
      final b = t.substring(0, t.length - sf.length);
      if (_birler.containsKey(b)) return _Kok(_birler[b]!, true);
      if (_onlar.containsKey(b)) return _Kok(_onlar[b]!, true);
    }
  }
  return null;
}

_Say? _sayiOku(List<String> w, int i, List<bool> used) {
  final n = w.length;
  if (i >= n || used[i]) return null;
  final t = w[i];
  if (_sayiRe.hasMatch(t)) return _Say(int.parse(t), 1, false, false);
  final r = _kokCoz(t);
  if (r == null) return null;
  if (r.v >= 10 && r.v % 10 == 0 && !r.sx && i + 1 < n && !used[i + 1]) {
    final r2 = _kokCoz(w[i + 1]);
    if (r2 != null && r2.v >= 1 && r2.v <= 9) {
      return _Say(r.v + r2.v, 2, r2.sx, true);
    }
  }
  return _Say(r.v, 1, r.sx, true);
}

Parsed parseTr(String raw, DateTime now) {
  final temiz = raw.replaceAll('’', "'").replaceAll(',', ' ');
  final orig = <String>[];
  final glue = <bool>[];
  for (final p in temiz.split(RegExp(r'\s+'))) {
    if (p.isEmpty) continue;
    final parts = p.split("'");
    for (int k = 0; k < parts.length; k++) {
      final q = parts[k];
      if (q.isEmpty) continue;
      final m = k == 0 ? _rakamEk.firstMatch(q) : null;
      if (m != null) {
        orig.add(m.group(1)!);
        glue.add(false);
        orig.add(m.group(2)!);
        glue.add(true);
      } else {
        orig.add(q);
        glue.add(k > 0);
      }
    }
  }
  final w = orig.map(trLower).toList();
  final n = w.length;
  final used = List<bool>.filled(n, false);
  String nx(int i, [int k = 1]) => (i + k < n && !used[i + k]) ? w[i + k] : '';
  String pv(int i) => (i > 0 && !used[i - 1]) ? w[i - 1] : '';

  int? relMin;
  int? relDays;
  int? relMonths;
  int? dayD;
  int? dayM;
  int? dayoff;
  int? wday;
  bool haftaya = false;
  bool gelecek = false;
  bool aySonu = false;
  String? period;
  int? hour;
  int minute = 0;

  // 1) göreli süreler ve "20 Aralık" gibi tarihler
  for (int i = 0; i < n; i++) {
    if (used[i]) continue;
    final t = w[i];
    if (t == 'yarım' && nx(i) == 'saat' && _sonraSozu.contains(nx(i, 2))) {
      relMin = 30;
      used[i] = used[i + 1] = used[i + 2] = true;
      continue;
    }
    if (t == 'çeyrek' && nx(i) == 'saat' && _sonraSozu.contains(nx(i, 2))) {
      relMin = 15;
      used[i] = used[i + 1] = used[i + 2] = true;
      continue;
    }
    final r = _sayiOku(w, i, used);
    if (r != null) {
      int j = i + r.c;
      bool half = false;
      if (j + 1 < n &&
          !used[j] &&
          w[j] == 'buçuk' &&
          (w[j + 1] == 'saat' ||
              w[j + 1] == 'gün' ||
              w[j + 1] == 'hafta' ||
              w[j + 1] == 'ay')) {
        half = true;
        j++;
      }
      if (j + 1 < n && _zamanBirim.contains(w[j]) && _sonraSozu.contains(w[j + 1])) {
        final u = w[j];
        final val = r.v + (half ? 0.5 : 0.0);
        if (u == 'dakika' || u == 'dk') {
          relMin = val.toInt();
        } else if (u == 'saat') {
          relMin = (val * 60).toInt();
        } else if (u == 'gün') {
          relDays = val.toInt();
        } else if (u == 'hafta') {
          relDays = (val * 7).toInt();
        } else {
          relMonths = val.toInt();
        }
        for (int k = i; k <= j + 1; k++) {
          used[k] = true;
        }
        continue;
      }
      if (r.v >= 1 && r.v <= 31 && j < n && !used[j]) {
        for (final a in _aylar) {
          if (w[j].startsWith(a.key)) {
            dayD = r.v;
            dayM = a.value;
            for (int k = i; k <= j; k++) {
              used[k] = true;
            }
            if (j + 1 < n && _ekSet.contains(w[j + 1]) && glue[j + 1]) {
              used[j + 1] = true;
            }
            break;
          }
        }
      }
    }
  }

  // 2) ayın günü: "ayın 25'inde", "25'inde", "ayın sonunda"
  for (int i = 0; i < n; i++) {
    if (used[i] || dayD != null) continue;
    final t = w[i];
    if ((t == 'ayın' || t == 'ay') && (nx(i) == 'sonu' || nx(i) == 'sonunda')) {
      aySonu = true;
      used[i] = used[i + 1] = true;
      continue;
    }
    if (t == 'ayın') {
      final r = _sayiOku(w, i + 1, used);
      if (r != null && r.v >= 1 && r.v <= 31) {
        dayD = r.v;
        used[i] = true;
        for (int k = i + 1; k <= i + r.c; k++) {
          used[k] = true;
        }
        final e = i + 1 + r.c;
        if (e < n && glue[e]) used[e] = true;
        continue;
      }
    }
    if (_sayiRe.hasMatch(t) &&
        _ayGunEki.contains(nx(i)) &&
        int.parse(t) >= 1 &&
        int.parse(t) <= 31) {
      dayD = int.parse(t);
      used[i] = used[i + 1] = true;
    }
  }

  // 3) gün ve günün bölümü sözcükleri
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
    } else if ((t == 'gelecek' || t == 'önümüzdeki') && nx(i) == 'hafta') {
      haftaya = true;
      used[i] = used[i + 1] = true;
    } else if (t == 'gelecek' || t == 'önümüzdeki') {
      gelecek = true;
      used[i] = true;
    } else if (t == 'bu' &&
        (_bolumler.containsKey(nx(i)) ||
            nx(i) == 'hafta' ||
            _gunler.any((g) => nx(i).startsWith(g.key)))) {
      if (_bolumler.containsKey(nx(i))) dayoff = 0;
      if (nx(i) == 'hafta') used[i + 1] = true;
      used[i] = true;
    } else if (t == 'öğleden' && nx(i) == 'sonra') {
      period = 'ogleden';
      used[i] = used[i + 1] = true;
    } else if (t == 'öğleden' && nx(i) == 'önce') {
      period = 'sabah';
      used[i] = used[i + 1] = true;
    } else if (t == 'sabaha' && nx(i) == 'karşı') {
      period = 'sabaha';
      used[i] = used[i + 1] = true;
    } else if (_bolumler.containsKey(t)) {
      period = _bolumler[t];
      used[i] = true;
    } else if (t.startsWith('akşam') && t.length <= 8) {
      period = 'aksam';
      used[i] = true;
    } else {
      for (final g in _gunler) {
        if (t.startsWith(g.key) &&
            _gunEkleri.contains(t.substring(g.key.length)) &&
            !(g.key == 'pazar' && t != 'pazar' && t != 'pazarı')) {
          wday = g.value;
          used[i] = true;
          if (nx(i) == 'günü' || nx(i) == 'gün') used[i + 1] = true;
          break;
        }
      }
    }
  }

  // 4) saat
  for (int i = 0; i < n; i++) {
    if (hour != null) break;
    if (used[i]) continue;
    final t = w[i];
    final m = _saatDk.firstMatch(t);
    int hh;
    int mm = 0;
    int c = 1;
    bool sx = false;
    bool kelime = false;
    final saatMi = m != null && int.parse(m.group(1)!) < 24 && int.parse(m.group(2)!) < 60;
    if (saatMi) {
      hh = int.parse(m.group(1)!);
      mm = int.parse(m.group(2)!);
    } else {
      final r = _sayiOku(w, i, used);
      if (r == null) continue;
      if (r.v > 24) continue;
      c = r.c;
      sx = r.sx;
      kelime = r.kelime;
      final j0 = i + c;
      final nxt = (j0 < n && !used[j0]) ? w[j0] : '';
      final p = pv(i);
      final pw = i > 0 ? w[i - 1] : '';
      final oncekiKullanildi = i > 0 && used[i - 1];
      bool ctx = p == 'saat' ||
          sx ||
          (_ekSet.contains(nxt) && j0 < n && glue[j0]) ||
          nxt.startsWith('buçuk') ||
          nxt == 'çeyrek' ||
          (oncekiKullanildi &&
              !_sayiDegil.contains(nxt) &&
              nxt != 'gün' &&
              nxt != 'hafta');
      if (r.v == 10 && kelime && c == 1) {
        final saatOnce = pw == 'saat';
        final bolumOnce = _bolumler.containsKey(pw);
        if (sx && !(saatOnce || bolumOnce)) ctx = false;
        if (!sx &&
            !(saatOnce || bolumOnce || (_ekSet.contains(nxt) && j0 < n && glue[j0]))) {
          ctx = false;
        }
      }
      if (!ctx) continue;
      if (_sayiDegil.contains(nxt) && nxt != 'saat') continue;
      hh = r.v;
      mm = 0;
    }
    int j = i + c;
    used[i] = true;
    for (int k = 1; k < c; k++) {
      used[i + k] = true;
    }
    if (i > 0 && w[i - 1] == 'saat' && !used[i - 1]) used[i - 1] = true;
    while (j < n &&
        !used[j] &&
        ((glue[j] && _ekSet.contains(w[j])) ||
            (_yerEk.contains(w[j]) && _sayiRe.hasMatch(orig[j - 1])))) {
      used[j] = true;
      j++;
    }
    String nxj(int k) => (j + k < n && !used[j + k]) ? w[j + k] : '';
    if (mm == 0) {
      if (nxj(0).startsWith('buçuk')) {
        mm = 30;
        used[j] = true;
        j++;
      } else if (nxj(0) == 'çeyrek' && nxj(1) == 'var') {
        hh = (hh - 1 + 24) % 24;
        mm = 45;
        used[j] = used[j + 1] = true;
        j += 2;
      } else if (nxj(0) == 'çeyrek' && (nxj(1) == 'geçe' || nxj(1) == 'geçiyor')) {
        mm = 15;
        used[j] = used[j + 1] = true;
        j += 2;
      } else {
        final r2 = _sayiOku(w, j, used);
        if (r2 != null && r2.v >= 0 && r2.v <= 59) {
          final sonraki = j + r2.c < n ? w[j + r2.c] : '';
          if (sonraki == 'geçe') {
            mm = r2.v;
            for (int k = j; k <= j + r2.c; k++) {
              used[k] = true;
            }
            j += r2.c + 1;
          } else if (sonraki == 'var') {
            hh = (hh - 1 + 24) % 24;
            mm = 60 - r2.v;
            for (int k = j; k <= j + r2.c; k++) {
              used[k] = true;
            }
            j += r2.c + 1;
          } else {
            final saatli = i > 0 && w[i - 1] == 'saat';
            final ikiKelime = !saatMi && kelime && r2.kelime;
            if ((saatli || ikiKelime) &&
                r2.v % 5 == 0 &&
                !glue[j] &&
                !(j + r2.c < n && _sayiDegil.contains(w[j + r2.c]))) {
              mm = r2.v;
              for (int k = j; k < j + r2.c; k++) {
                used[k] = true;
              }
              j += r2.c;
            }
          }
        }
      }
    }
    while (j < n &&
        !used[j] &&
        _ekSet.contains(w[j]) &&
        (glue[j] || _uzunEk.contains(w[j]))) {
      used[j] = true;
      j++;
    }
    hour = hh;
    minute = mm;
  }

  for (int i = 1; i < n; i++) {
    if (w[i] == 'kadar' && !used[i] && used[i - 1]) used[i] = true;
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
  while (words.length > 1 &&
      (trLower(words[0]) == 'şunu' || trLower(words[0]) == 'şey')) {
    words.removeAt(0);
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
  if (relMonths != null) {
    final mo = today.month - 1 + relMonths;
    date = DateTime(today.year + mo ~/ 12, mo % 12 + 1, min(today.day, 28));
  } else if (relDays != null) {
    date = gunEkle(today, relDays);
  } else if (dayD != null && dayM != null) {
    final dd = DateTime(now.year, dayM, dayD);
    date = dd.month == dayM ? dd : null;
  } else if (dayD != null) {
    int y = today.year;
    int mo = today.month;
    if (dayD < today.day) mo++;
    final dd = DateTime(y, mo, dayD);
    date = dd.day == dayD ? dd : null;
  } else if (aySonu) {
    date = DateTime(today.year, today.month + 1, 0);
  } else if (wday != null) {
    if (haftaya) {
      date = gunEkle(today, -(today.weekday - 1) + 7 + wday - 1);
    } else {
      int d = (wday - today.weekday + 7) % 7;
      if (gelecek && d == 0) d = 7;
      date = gunEkle(today, d);
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
    mm = 0;
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
      case 'sabaha':
        hh = 6;
        break;
      default:
        hh = 22;
    }
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
    if (!cand.isAfter(now)) {
      cand = DateTime(cand.year, cand.month, cand.day + 1, hh, mm);
    }
    return Parsed(title, cand);
  }
  var cand = DateTime(date.year, date.month, date.day, hh, mm);
  if (!cand.isAfter(now)) {
    if (gunFarki(date, now) == 0 &&
        belirsiz &&
        wday == null &&
        cand.add(const Duration(hours: 12)).isAfter(now)) {
      cand = cand.add(const Duration(hours: 12));
    } else if (gunFarki(date, now) == 0 && period == 'gece' && hh < 6) {
      cand = DateTime(cand.year, cand.month, cand.day + 1, hh, mm);
    } else if (wday != null && !haftaya) {
      cand = DateTime(cand.year, cand.month, cand.day + 7, hh, mm);
    } else if (dayD != null && dayM == null) {
      final dd = DateTime(cand.year, cand.month + 1, cand.day, hh, mm);
      if (dd.day != cand.day) return Parsed(title, null);
      cand = dd;
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
      sound: const UriAndroidNotificationSound('content://settings/system/alarm_alert'),
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
    sound: UriAndroidNotificationSound('content://settings/system/alarm_alert'),
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

alm.AlarmSettings alarmAyari(int id, DateTime when, String baslik) {
  return alm.AlarmSettings(
    id: id,
    dateTime: when,
    assetAudioPath: 'assets/alarm.wav',
    loopAudio: true,
    vibrate: true,
    warningNotificationOnKill: false,
    androidFullScreenIntent: true,
    volumeSettings: alm.VolumeSettings.fade(
      volume: 0.9,
      fadeDuration: const Duration(seconds: 3),
      volumeEnforced: false,
    ),
    notificationSettings: alm.NotificationSettings(
      title: baslik,
      body: 'Hatırlatma zamanı',
      stopButton: 'Durdur',
    ),
  );
}

Future<void> alarmDurdur(int id) async {
  try {
    await alm.Alarm.stop(id);
  } catch (_) {}
}

Future<void> bildirimIptal(int id) async {
  try {
    await plugin.cancel(id);
  } catch (_) {}
}

Future<void> iptalHat(int id) async {
  await alarmDurdur(id);
  await bildirimIptal(id * 10 + 1);
  await bildirimIptal(id * 10 + 2);
  await bildirimIptal(id * 10 + 3);
}

Future<void> kurHat(Hat h) async {
  if (h.done) {
    await iptalHat(h.id);
    return;
  }
  await bildirimIptal(h.id * 10 + 2);
  if (h.when.isAfter(DateTime.now())) {
    await alarmDurdur(h.id);
    await alm.Alarm.set(alarmSettings: alarmAyari(h.id, h.when, h.title));
  }
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
  await alm.Alarm.init();
  await initTts();
  runApp(const HatApp());
}

ThemeData _tema() {
  final cs = ColorScheme.fromSeed(
    seedColor: kMor,
    brightness: Brightness.dark,
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: cs,
    scaffoldBackgroundColor: kArka,
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: kYuzey,
      showDragHandle: true,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: kYuzey2,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: BorderSide.none,
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: kMor,
        foregroundColor: Colors.white,
        minimumSize: const Size(0, 52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: Colors.white,
        minimumSize: const Size(0, 52),
        side: const BorderSide(color: Color(0xFF39407A)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
    ),
  );
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
      theme: _tema(),
      darkTheme: _tema(),
      themeMode: ThemeMode.dark,
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
    _timer = Timer.periodic(const Duration(seconds: 5), (_) => _nabiz());
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
      _nabiz();
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

  bool _dialogAcik = false;

  // Zamanı gelen hatırlatmayı sesli oku ve ekranda göster
  Future<void> _nabiz() async {
    await _yukle();
    if (_dialogAcik || !mounted) return;
    final now = DateTime.now();
    for (final h in items) {
      if (h.done) continue;
      final fark = now.difference(h.when);
      final anahtar = '${h.id}-${h.whenMs}';
      if (!fark.isNegative &&
          fark < const Duration(minutes: 3) &&
          !_okundu.contains(anahtar)) {
        _okundu.add(anahtar);
        await _calDialog(h);
        break;
      }
    }
  }

  Future<void> _calDialog(Hat h) async {
    _dialogAcik = true;
    if (!mounted) {
      _dialogAcik = false;
      return;
    }
    final secim = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (c) => AlertDialog(
        backgroundColor: kYuzey,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
        icon: const Icon(Icons.alarm, size: 44, color: kSari),
        title: Text(
          h.title,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w700),
        ),
        content: Text('Saat ${hhmm(h.when)}',
            textAlign: TextAlign.center, style: const TextStyle(fontSize: 18)),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          TextButton(
            onPressed: () => Navigator.of(c).pop('ertele'),
            child: const Text('10 dk ertele'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(c).pop('tamam'),
            child: const Text('Tamam'),
          ),
        ],
      ),
    );
    await alarmDurdur(h.id);
    if (secim == 'tamam') {
      await _bitti(h, true);
    } else if (secim == 'ertele') {
      final l = await Store.load();
      final k = l.indexWhere((e) => e.id == h.id);
      if (k >= 0) {
        l[k].whenMs =
            DateTime.now().add(const Duration(minutes: 10)).millisecondsSinceEpoch;
        l[k].done = false;
        await Store.save(l);
        try {
          await kurHat(l[k]);
        } catch (_) {}
        if (mounted) setState(() => items = l);
      }
    }
    _dialogAcik = false;
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

  String _kalanYazi(DateTime when, DateTime now) {
    final d = when.difference(now);
    if (d.isNegative) return 'Kaçırıldı';
    if (d.inMinutes < 1) return 'şimdi';
    if (d.inMinutes < 60) return '${d.inMinutes} dk sonra';
    if (d.inHours < 24) {
      final m = d.inMinutes % 60;
      return m == 0 ? '${d.inHours} sa sonra' : '${d.inHours} sa $m dk sonra';
    }
    return '${d.inDays} gün sonra';
  }

  Widget _satir(Hat h, DateTime now) {
    final gecmis = !h.done && h.when.isBefore(now);
    final f = gunFarki(h.when, now);
    final Color renk = h.done
        ? kGri
        : gecmis
            ? kKirmizi
            : f == 0
                ? kSari
                : f == 1
                    ? kMavi
                    : kMor;
    return Dismissible(
      key: ValueKey('h${h.id}'),
      direction: DismissDirection.endToStart,
      background: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        decoration: BoxDecoration(
          color: kKirmizi.withOpacity(0.25),
          borderRadius: BorderRadius.circular(22),
        ),
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 26),
        child: const Icon(Icons.delete_outline, color: kKirmizi),
      ),
      onDismissed: (_) => _sil(h),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        child: Material(
          color: kYuzey,
          borderRadius: BorderRadius.circular(22),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => _duzenle(baslik: h.title, zaman: h.when, mevcut: h),
            onLongPress: () => _sil(h),
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(width: 5, color: renk),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 14, 6, 14),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 64,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  hhmm(h.when),
                                  style: TextStyle(
                                    fontSize: 22,
                                    fontWeight: FontWeight.w800,
                                    color: renk,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  gunEtiketi(h.when, now),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      fontSize: 12, color: kSoluk),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  h.title,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 17,
                                    fontWeight: FontWeight.w600,
                                    color: h.done ? kSoluk : Colors.white,
                                    decoration: h.done
                                        ? TextDecoration.lineThrough
                                        : null,
                                  ),
                                ),
                                if (h.early && !h.done)
                                  const Padding(
                                    padding: EdgeInsets.only(top: 3),
                                    child: Text('Bir gün önce de haber verir',
                                        style: TextStyle(
                                            fontSize: 12, color: kSoluk)),
                                  ),
                                if (gecmis)
                                  const Padding(
                                    padding: EdgeInsets.only(top: 3),
                                    child: Text('Kaçırıldı',
                                        style: TextStyle(
                                            fontSize: 12, color: kKirmizi)),
                                  ),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: Icon(
                              h.done
                                  ? Icons.check_circle
                                  : Icons.radio_button_unchecked,
                              color: h.done ? kYesil : renk,
                              size: 28,
                            ),
                            onPressed: () => _bitti(h, !h.done),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _bolum(String ad, List<Hat> l, DateTime now, {Color? renk}) {
    if (l.isEmpty) return [];
    return [
      Padding(
        padding: const EdgeInsets.fromLTRB(26, 22, 24, 4),
        child: Row(
          children: [
            Text(
              ad,
              style: TextStyle(
                fontSize: 13,
                letterSpacing: 0.6,
                fontWeight: FontWeight.w700,
                color: renk ?? kSoluk,
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: (renk ?? kSoluk).withOpacity(0.18),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text('${l.length}',
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: renk ?? kSoluk)),
            ),
          ],
        ),
      ),
      ...l.map((h) => _satir(h, now)),
    ];
  }

  Widget _baslik(DateTime now, int bekleyen) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(26, 18, 16, 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${_gunTam[now.weekday - 1]}, ${now.day} ${_ayTam[now.month - 1]}',
                  style: const TextStyle(fontSize: 14, color: kSoluk),
                ),
                const SizedBox(height: 2),
                const Text(
                  'Hatırlatıcı',
                  style: TextStyle(
                      fontSize: 34,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                      height: 1.1),
                ),
                const SizedBox(height: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                  decoration: BoxDecoration(
                    color: kMor.withOpacity(0.18),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Text(
                    bekleyen == 0 ? 'Her şey yolunda' : '$bekleyen hatırlatma bekliyor',
                    style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFFB9A8FF)),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: GestureDetector(
              onTap: _kurulumAc,
              child: Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: kYuzey,
                  shape: BoxShape.circle,
                  border: Border.all(color: const Color(0xFF2A3160)),
                ),
                child: Badge(
                  isLabelVisible: _uyari,
                  child: const Icon(Icons.shield_outlined,
                      color: Colors.white, size: 22),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _hero(Hat h, DateTime now) {
    return Dismissible(
      key: ValueKey('hero${h.id}'),
      direction: DismissDirection.endToStart,
      background: Container(
        margin: const EdgeInsets.fromLTRB(16, 14, 16, 4),
        decoration: BoxDecoration(
          color: kKirmizi.withOpacity(0.25),
          borderRadius: BorderRadius.circular(30),
        ),
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 30),
        child: const Icon(Icons.delete_outline, color: kKirmizi, size: 30),
      ),
      onDismissed: (_) => _sil(h),
      child: GestureDetector(
      onTap: () => _duzenle(baslik: h.title, zaman: h.when, mevcut: h),
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 14, 16, 4),
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          gradient: kGradyan,
          borderRadius: BorderRadius.circular(30),
          boxShadow: [
            BoxShadow(
              color: kMor.withOpacity(0.35),
              blurRadius: 30,
              offset: const Offset(0, 14),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.alarm, color: Colors.white70, size: 18),
                const SizedBox(width: 6),
                Text(
                  'SIRADAKİ',
                  style: TextStyle(
                    fontSize: 12,
                    letterSpacing: 1.4,
                    fontWeight: FontWeight.w700,
                    color: Colors.white.withOpacity(0.8),
                  ),
                ),
                const Spacer(),
                GestureDetector(
                  onTap: () => _sil(h),
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.18),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.delete_outline,
                        color: Colors.white, size: 20),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              h.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.w800,
                color: Colors.white,
                height: 1.15,
              ),
            ),
            const SizedBox(height: 18),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  hhmm(h.when),
                  style: const TextStyle(
                    fontSize: 46,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                    height: 1,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(
                      '${gunEtiketi(h.when, now)} • ${_kalanYazi(h.when, now)}',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Colors.white.withOpacity(0.85),
                      ),
                    ),
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

  Widget _bos() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 56, 32, 0),
      child: Column(
        children: [
          Container(
            width: 120,
            height: 120,
            decoration: BoxDecoration(
              gradient: kGradyan,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: kMor.withOpacity(0.4),
                  blurRadius: 40,
                  spreadRadius: 4,
                ),
              ],
            ),
            child: const Icon(Icons.mic, size: 56, color: Colors.white),
          ),
          const SizedBox(height: 28),
          const Text(
            'Mikrofona bas ve söyle',
            style: TextStyle(
                fontSize: 24, fontWeight: FontWeight.w800, color: Colors.white),
          ),
          const SizedBox(height: 6),
          const Text(
            'Gün ve saati kendim anlarım',
            style: TextStyle(fontSize: 15, color: kSoluk),
          ),
          const SizedBox(height: 24),
          for (final s in const [
            'Yarın saat 9\'a toptancıyı ara',
            'Haftaya salı akşam 6\'da doktor',
            '2 saat sonra ütüyü kapat',
          ])
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
              decoration: BoxDecoration(
                color: kYuzey,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: const Color(0xFF2A3160)),
              ),
              child: Text('“$s”',
                  style: const TextStyle(fontSize: 15, color: Color(0xFFCBD1FF))),
            ),
        ],
      ),
    );
  }

  Widget _daire({
    required double boy,
    required Widget child,
    required VoidCallback onTap,
    Gradient? gradient,
    Color? renk,
    List<BoxShadow>? golge,
    Border? kenar,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: boy,
        height: boy,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: gradient,
          color: renk,
          boxShadow: golge,
          border: kenar,
        ),
        child: Center(child: child),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final aktif = items.where((e) => !e.done).toList()
      ..sort((a, b) => a.whenMs.compareTo(b.whenMs));
    final bitenler = items.where((e) => e.done).toList()
      ..sort((a, b) => b.whenMs.compareTo(a.whenMs));
    final kacan = aktif.where((e) => e.when.isBefore(now)).toList();
    final gelecek = aktif.where((e) => !e.when.isBefore(now)).toList();
    final sirada = gelecek.isEmpty ? null : gelecek.first;
    final kalan = sirada == null
        ? gelecek
        : gelecek.where((e) => e.id != sirada.id).toList();
    final bugun = kalan.where((e) => gunFarki(e.when, now) == 0).toList();
    final yarin = kalan.where((e) => gunFarki(e.when, now) == 1).toList();
    final hafta = kalan
        .where((e) => gunFarki(e.when, now) >= 2 && gunFarki(e.when, now) <= 7)
        .toList();
    final sonra = kalan.where((e) => gunFarki(e.when, now) > 7).toList();

    final govde = <Widget>[_baslik(now, aktif.length)];
    if (_uyari) {
      govde.add(GestureDetector(
        onTap: _kurulumAc,
        child: Container(
          margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: kKirmizi.withOpacity(0.15),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: kKirmizi.withOpacity(0.5)),
          ),
          child: const Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: kKirmizi),
              SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Alarmın çalması için bir izin eksik. Dokun ve düzelt.',
                  style: TextStyle(color: Colors.white, fontSize: 14),
                ),
              ),
              Icon(Icons.chevron_right, color: Colors.white54),
            ],
          ),
        ),
      ));
    }
    if (aktif.isEmpty && bitenler.isEmpty) {
      govde.add(_bos());
    } else {
      if (sirada != null) govde.add(_hero(sirada, now));
      govde.addAll(_bolum('KAÇIRILAN', kacan, now, renk: kKirmizi));
      govde.addAll(_bolum('BUGÜN', bugun, now));
      govde.addAll(_bolum('YARIN', yarin, now));
      govde.addAll(_bolum('BU HAFTA', hafta, now));
      govde.addAll(_bolum('DAHA SONRA', sonra, now));
      if (bitenler.isNotEmpty) {
        govde.add(Padding(
          padding: const EdgeInsets.only(top: 16),
          child: Theme(
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              tilePadding: const EdgeInsets.symmetric(horizontal: 26),
              iconColor: kSoluk,
              collapsedIconColor: kSoluk,
              title: Text('TAMAMLANANLAR (${bitenler.length})',
                  style: const TextStyle(
                      fontSize: 13,
                      letterSpacing: 0.6,
                      fontWeight: FontWeight.w700,
                      color: kSoluk)),
              children: bitenler.map((h) => _satir(h, now)).toList(),
            ),
          ),
        ));
      }
    }

    return Scaffold(
      backgroundColor: kArka,
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF1A2050), kArka],
            stops: [0.0, 0.5],
          ),
        ),
        child: SafeArea(
          bottom: false,
          child: ListView(
            padding: const EdgeInsets.only(bottom: 170),
            children: govde,
          ),
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _daire(
            boy: 58,
            renk: kYuzey2,
            kenar: Border.all(color: const Color(0xFF39407A)),
            onTap: _elleEkle,
            child: const Icon(Icons.edit_outlined, color: Colors.white, size: 24),
          ),
          const SizedBox(width: 22),
          _daire(
            boy: 86,
            gradient: kGradyan,
            golge: [
              BoxShadow(
                color: kMor.withOpacity(0.6),
                blurRadius: 32,
                spreadRadius: 2,
              ),
            ],
            onTap: _mikrofon,
            child: const Icon(Icons.mic, color: Colors.white, size: 42),
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
                    gradient: _hata ? null : kGradyan,
                    color: _hata ? cs.errorContainer : null,
                    boxShadow: [
                      BoxShadow(
                        color: (_hata ? kKirmizi : kMor).withOpacity(0.5),
                        blurRadius: 30 + _seviye.clamp(0.0, 10.0) * 3,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: Icon(
                    _hata ? Icons.mic_off : Icons.mic,
                    size: 48,
                    color: _hata ? cs.onErrorContainer : Colors.white,
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
                label: const Text('Dene: 6 saniye sonra alarm çalsın'),
                onPressed: () async {
                  final nav = ScaffoldMessenger.of(context);
                  try {
                    await alarmDurdur(999998);
                    await alm.Alarm.set(
                      alarmSettings: alarmAyari(
                        999998,
                        DateTime.now().add(const Duration(seconds: 6)),
                        'Deneme hatırlatması',
                      ),
                    );
                  } catch (e) {
                    nav.showSnackBar(SnackBar(content: Text('Hata: $e')));
                    return;
                  }
                  if (!mounted) return;
                  await showDialog<void>(
                    context: context,
                    barrierDismissible: false,
                    builder: (c) => AlertDialog(
                      title: const Text('Alarm 6 saniye sonra çalacak'),
                      content: const Text(
                          'Telefonu sessizde bırak. Çalınca aşağıdaki tuşla durdur.'),
                      actions: [
                        FilledButton(
                          onPressed: () async {
                            await alarmDurdur(999998);
                            if (c.mounted) Navigator.of(c).pop();
                          },
                          child: const Text('Durdur'),
                        ),
                      ],
                    ),
                  );
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
