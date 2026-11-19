import 'package:flutter_test/flutter_test.dart';
import 'package:hatirlatici/main.dart';

String _f(DateTime? d) => d == null
    ? '-'
    : '${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')} '
        '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

String _sonuc(List<Girdi> gs) {
  return gs.map((g) {
    String tur;
    if (g.niyet == 1 || (g.zaman == null && g.niyet == 0)) {
      tur = 'NOT';
    } else if (g.zaman == null) {
      tur = 'SAAT-SOR';
    } else {
      tur = 'ALARM';
    }
    final k = katBul(g.ham);
    final t = tutarBul(g.ham);
    return '$tur[${_f(g.zaman)}] "${g.baslik}"'
        '${k != null ? ' kat=${k.ad}' : ''}${t != null ? ' tutar=${tlYaz(t)}' : ''}';
  }).join('  ;;  ');
}

void main() {
  // Perşembe 19 Kasım 2026, 17:00
  final now = DateTime(2026, 11, 19, 17, 0);

  // [cümle, beklenen (boşsa sadece yazdırılır)]
  final cases = <List<String>>[
    // ---- NOT niyeti
    ['ekmek al not ekle', 'NOT[-] "Ekmek al" kat=Alışveriş'],
    ['not ekle ekmek al', 'NOT[-] "Ekmek al" kat=Alışveriş'],
    ['toptancıya borç var not yaz', ''],
    ["Ahmet'e 3200 lira borç kayıt et", ''],
    ["yarın 9'da bankaya git not al", ''],
    ['not al yarın toptancı gelecek', ''],
    ['defterime yaz süt ve ekmek', ''],
    ['kaydet kasa sayımı yapılacak', ''],
    ['bunu not düş fatura ödenecek', ''],
    ['panjurcuyu ara not et', ''],
    ['yarın sabah toptancıyı ara diye not al', ''],
    ['not olarak kaydet 5 bin lira kira öde', ''],
    ['kayıt et elektrik faturası 1.250 TL', ''],
    ['listeye ekle bebek bezi', ''],
    // ---- HATIRLATMA
    ["saat 5'e bunu hatırlat", ''],
    ["yarın saat 9'da bankaya git alarm kur", 'ALARM[11-20 09:00] "Bankaya git" kat=Araç'],
    ['yarın saat 10 a alarm ayarla toptancıyı ara', ''],
    ["akşam 8'de ilaç içmemi hatırlat", ''],
    ["bana yarın sabah 7'de uyar", ''],
    ["cuma günü saat 14.30'da randevu hatırlat", ''],
    ['20 dakika sonra çamaşırı çıkar hatırlat', ''],
    ['yarın akşam altıda annemi ara alarm kur', ''],
    ['haftaya salı sabah dokuzda toplantı', ''],
    ['öğleden sonra üçte kargo gelecek hatırlatır mısın', ''],
    ['bir saat sonra ocağı kapat diye alarm koy', ''],
    ['saat 21.15 e alarm kur', ''],
    ['yarına alarm kur ekmek al', ''],
    ["gece 12'de ilaç hatırlat", ''],
    ["ayın 25'inde kira ödemesini hatırlat", ''],
    ['pazartesi 8 buçukta servise git', ''],
    ['sabah yedi buçukta uyandır', ''],
    ["hatırlat yarın 9'da panjurcuyu ara", ''],
    ["alarm kur yarın 6'da", ''],
    ['5 dakika sonra alarm kur', ''],
    ['saat beşe alarm kur', ''],
    ['saat on yediye hatırlat toptancı', ''],
    ['yarın öğlen on ikide yemek hatırlat', ''],
    ['pazar günü saat 10 da kahvaltı hazırla hatırlat', ''],
    ["iki gün sonra saat 4'te doktor", ''],
    ["bu akşam 9'a toptancı hatırlat", ''],
    ['yarın saat dokuz buçuğa alarm kur', ''],
    ["bugün 19.30'da maç hatırlat", ''],
    ['21:30 da alarm kur', ''],
    ['akşam sekizde alarm kur', ''],
    ['sabah altıda kalkmam için alarm kur', ''],
    ['yarın saat 3 e alarm ayarla', ''],
    ['bir saat sonraya alarm kur', ''],
    ['yarım saat sonra beni uyar', ''],
    ["perşembe günü 11'de toplantı var hatırlat", ''],
    ["15 Aralık'ta sigorta yenile hatırlat", ''],
    ['hatırlat', ''],
    ['alarm kur', ''],
    // ---- çok işli
    ["yarın 9'da bankaya git ve akşam 6'da markete uğra", ''],
    ['süt ve ekmek al', 'NOT[-] "Süt ve ekmek al" kat=Alışveriş'],
    ["yarın sabah 8'de annemi ara, akşam 7'de ilaç al", ''],
    ['ekmek al bir de süt al', ''],
    // ---- sade not (saat yok)
    ['toptancı Ahmet 3200 lira borç', 'NOT[-] "Toptancı Ahmet 3200 lira borç" kat=Gider tutar=3.200 ₺'],
    ['beş bin lira kira öde', ''],
    ['iki yüz elli lira fatura', ''],
    ['arabayı servise götür', ''],
    ['yarın toptancı mal getirecek', ''],
  ];

  test('dil çözümleme', () {
    int hata = 0;
    for (final c in cases) {
      final gs = girdiCoz(c[0], now);
      final r = _sonuc(gs);
      final bek = c[1];
      final ok = bek.isEmpty || r == bek;
      if (!ok) hata++;
      // ignore: avoid_print
      print('${bek.isEmpty ? 'INFO' : (ok ? 'OK  ' : 'FAIL')} | ${c[0]}  =>  $r'
          '${(!ok) ? '   (beklenen: $bek)' : ''}');
    }
    // ignore: avoid_print
    print('TOPLAM_HATA=$hata');
    expect(hata, 0);
  });
}
