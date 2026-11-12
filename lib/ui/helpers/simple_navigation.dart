import 'package:site_kapi_kontrol/ui/helpers/module_showcase.dart';
import 'package:site_kapi_kontrol/ui/widgets/yan_menu.dart';

enum SimpleTopic {
  today('Bugün'), home('Evim'), payments('Ödemeler'), site('Site'), finance('Finans'), apartments('Daireler'), management('Yönetim');
  const SimpleTopic(this.label);
  final String label;
}

List<SimpleTopic> simpleTopics(ShowcaseAudience audience) => audience == ShowcaseAudience.admin
    ? [SimpleTopic.today, SimpleTopic.finance, SimpleTopic.apartments, SimpleTopic.management]
    : [SimpleTopic.today, SimpleTopic.home, SimpleTopic.payments, SimpleTopic.site];

/// Categorizes the already-authorized list. It never grants access to a route.
SimpleTopic simpleTopicFor(SirketMenuItem item, ShowcaseAudience audience) {
  final admin = audience == ShowcaseAudience.admin;
  return switch (item) {
    SirketMenuItem.dashboard => SimpleTopic.today,
    SirketMenuItem.finans || SirketMenuItem.borcum || SirketMenuItem.sayaclar || SirketMenuItem.isletmeProjesi => admin ? SimpleTopic.finance : SimpleTopic.payments,
    SirketMenuItem.kisiler || SirketMenuItem.daireKullanicilariYonetimi => admin ? SimpleTopic.apartments : SimpleTopic.home,
    SirketMenuItem.dairem || SirketMenuItem.kapilar || SirketMenuItem.ellerSerbest || SirketMenuItem.katilimVeKurulum || SirketMenuItem.yeniSite || SirketMenuItem.acilDurum => admin ? SimpleTopic.management : SimpleTopic.home,
    _ => admin ? SimpleTopic.management : SimpleTopic.site,
  };
}

String simpleGroupFor(SirketMenuItem item) => switch (item) {
  SirketMenuItem.finans || SirketMenuItem.borcum || SirketMenuItem.sayaclar || SirketMenuItem.isletmeProjesi => 'Hesaplar ve ödemeler',
  SirketMenuItem.kisiler || SirketMenuItem.dairem || SirketMenuItem.daireKullanicilariYonetimi => 'Daireler ve kişiler',
  SirketMenuItem.duyurular || SirketMenuItem.anket || SirketMenuItem.anketler || SirketMenuItem.komsuPanosu || SirketMenuItem.rehber => 'İletişim ve komşular',
  SirketMenuItem.belgeler || SirketMenuItem.kararlar || SirketMenuItem.kararDefteri || SirketMenuItem.faaliyetRaporu => 'Belgeler ve kararlar',
  SirketMenuItem.talepler || SirketMenuItem.taleplerim || SirketMenuItem.ekipmanBakim || SirketMenuItem.sozlesmeler || SirketMenuItem.rezervasyon || SirketMenuItem.rezervasyonlar || SirketMenuItem.ziyaretciKayitlari || SirketMenuItem.ziyaretcilerim => 'İşler ve ortak alanlar',
  SirketMenuItem.kapilar || SirketMenuItem.ellerSerbest || SirketMenuItem.cihazEkle || SirketMenuItem.kayitliCihazlar || SirketMenuItem.bluetoothWifiKur || SirketMenuItem.plakaTanima || SirketMenuItem.odemeKamera => 'Geçiş ve cihazlar',
  SirketMenuItem.acilDurum => 'Acil yardım',
  SirketMenuItem.siteler || SirketMenuItem.katilimVeKurulum || SirketMenuItem.yeniSite || SirketMenuItem.siteBasvurulari || SirketMenuItem.siteOnayTalepleri => 'Site ve katılım',
  _ => 'Hesap, platform ve ayarlar',
};

Map<String, List<SirketMenuItem>> simpleGroups({required List<SirketMenuItem> visibleItems, required ShowcaseAudience audience, required SimpleTopic topic, Set<SirketMenuItem>? featuredItems}) {
  final groups = <String, List<SirketMenuItem>>{};
  if (topic == SimpleTopic.today) return groups;
  final available = visibleItems.toSet()..remove(SirketMenuItem.dashboard);
  for (final item in available) {
    if (item == SirketMenuItem.dashboard) continue;
    // Residents explicitly asked not to be invited to set up another site.
    if (audience != ShowcaseAudience.admin && item == SirketMenuItem.yeniSite) continue;
    if (simpleTopicFor(item, audience) != topic) continue;
    (groups[simpleGroupFor(item)] ??= []).add(item);
  }
  return groups;
}
