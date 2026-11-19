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
    ["yarın saat 9'da bankaya git alarm kur", 'ALARM[11-20 09:00] "Bankaya git"'],
    ['yarın saat 10 a alarm ayarla toptancıyı ara', 'ALARM[11-20 10:00] "Toptancıyı ara" kat=Arama'],
    ['Çerezci 13.00019 TL', 'NOT[] "Çerezci 13.019 ₺" kat=Gider tutar=13019.0'],
    ['Çerezci 13000 19 TL', ''],
    ['Konfetici 23.256 TL', ''],
    ["akşam 8'de ilaç içmemi hatırlat", ''],
    ["bana yarın sabah 7'de uyar", ''],
    ["cuma günü saat 14.30'da randevu hatırlat", ''],
    ['20 dakika sonra çamaşırı çıkar hatırlat', ''],
    ['yarın akşam altıda annemi ara alarm kur', ''],
    ['haftaya salı sabah dokuzda toplantı', ''],
    ['öğleden sonra üçte kargo gelecek hatırlatır mısın', ''],
    ['bir saat sonra ocağı kapat diye alarm koy', ''],
    ['saat 21.15 e alarm kur', 'ALARM[11-19 21:15] "Alarm"'],
    ['yarına alarm kur ekmek al', 'ALARM[11-20 09:00] "Ekmek al" kat=Alışveriş'],
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
    ["iki gün sonra saat 4'te doktor", 'ALARM[11-21 16:00] "Doktor" kat=Sağlık'],
    ["bu akşam 9'a toptancı hatırlat", ''],
    ['yarın saat dokuz buçuğa alarm kur', 'ALARM[11-20 09:30] "Alarm"'],
    ["bugün 19.30'da maç hatırlat", ''],
    ['21:30 da alarm kur', 'ALARM[11-19 21:30] "Alarm"'],
    ['akşam sekizde alarm kur', ''],
    ['sabah altıda kalkmam için alarm kur', ''],
    ['yarın saat 3 e alarm ayarla', 'ALARM[11-20 15:00] "Alarm"'],
    ['bir saat sonraya alarm kur', 'ALARM[11-19 18:00] "Alarm"'],
    ['yarım saat sonra beni uyar', ''],
    ["perşembe günü 11'de toplantı var hatırlat", ''],
    ["15 Aralık'ta sigorta yenile hatırlat", ''],
    ['hatırlat', ''],
    ['alarm kur', ''],
    ["yarından sonra saat 2'de toplantı hatırlat", 'ALARM[11-21 14:00] "Toplantı" kat=Randevu'],
    ['saat on ikiye çeyrek var alarm kur', ''],
    ['dokuza on kala alarm kur', ''],
    ['öğlene doğru alarm kur', ''],
    ['akşama alarm kur toptancı', ''],
    ['yarın sabah beşte kalkmam lazım alarm kur', ''],
    ['saat 4 gibi hatırlat', ''],
    ['kırk beş dakika sonra hatırlat', ''],
    ['cumaya hatırlat toptancıyı ara', ''],
    ['haftaya cuma saat 3 te ödeme hatırlat', ''],
    ['saat 2 ye alarm kur', ''],
    ['yarın not ekle toptancı gelecek', ''],
    ['sabah 9 da alarm kur', ''],
    ['bu akşam kasa açılışı hatırlat', ''],
    ['çarşamba günü hatırlat doktor randevusu', ''],
    ['alarm ayarla', ''],
    ['bunu hatırlat', ''],
    ['bir saat sonra beni uyandır', ''],
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
