// Platform Faz 3b-A: yönetici "Belgeler" ekranı (DocumentAdminView / DocumentAdminList).
//
// AGENTS.md kural 6: 320x640 x2,0 ve 360x640 x1,5, açık + koyu tema; yükleniyor / boş / hata / dolu durumlar
// taşmaz. Yarış korumaları: art arda arama, süzgeç değişimi, site değişimi, çift dokunuş. Kurul üyesi SALT
// OKUNUR. Hata ASLA "belge yok" demez.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:site_kapi_kontrol/models/user_role.dart';
import 'package:site_kapi_kontrol/services/api_exception.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart' show InlineNotice;
import 'package:site_kapi_kontrol/ui/design/buttons.dart'
    show PrimaryActionButton;
import 'package:site_kapi_kontrol/ui/helpers/people_scope.dart';
import 'package:site_kapi_kontrol/ui/views/document_admin_view.dart';
import 'package:site_kapi_kontrol/ui/widgets/document_parts.dart';
import 'package:site_kapi_kontrol/ui/widgets/list_parts.dart';
import 'package:site_kapi_kontrol/ui/widgets/drive_storage_card.dart';

import 'dialog_layout_harness.dart' show settleFor;
import 'document_fixtures.dart';
import 'list_fixtures.dart';

const List<PeopleSite> _writeSite = <PeopleSite>[
  PeopleSite(code: 11, name: 'Gül Sitesi', canWrite: true),
];
const List<PeopleSite> _boardSite = <PeopleSite>[
  PeopleSite(code: 11, name: 'Gül Sitesi'),
];

Future<GlobalKey<DocumentAdminViewState>> _pump(
  WidgetTester t,
  DocumentFakeAuth auth,
  FakeDocumentService service, {
  double width = 400,
  double height = 1600,
  double scale = 1.0,
  bool dark = false,
  List<PeopleSite> sites = _writeSite,
  bool all = false,
  VoidCallback? onOpenModules,
}) async {
  final key = GlobalKey<DocumentAdminViewState>();
  await pumpList(
    t,
    DocumentAdminView(
      key: key,
      authService: auth,
      service: service,
      sites: sites,
      manageAllSites: all,
      onOpenModules: onOpenModules,
    ),
    width: width,
    height: height,
    scale: scale,
    dark: dark,
  );
  // Önce siteler gelir, liste sonra kurulur ve kendi verisini çeker: iki aşama.
  await settleFor(t, 100);
  await settleFor(t, 100);
  return key;
}

Finder _card(String title) => find.widgetWithText(DocumentAdminCard, title);

Future<void> _typeSearch(WidgetTester t, String text) async {
  final field = find.byKey(const ValueKey<String>('documents_search'));
  await t.ensureVisible(field);
  await t.pump();
  await t.enterText(field, text);
  await t.pump();
}

Future<void> _debounce(WidgetTester t) async {
  await t.pump(const Duration(milliseconds: 400));
  await t.pump();
}

void main() {
  // Belgeler ve Google Drive TEK modül (Dosya Deposu, drive_storage): yönetim ekranında Drive bölümü ÜSTTE, sunucu
  // belge listesi ALTTA görünür. D1: sunucu kotası yok, dosyalar sitenin Drive hesabındadır.
  group('Dosya Deposu: Google Drive bölümü', () {
    testWidgets(
      'Drive kartı üstte, belge listesi altta; eski sunucu kota çubuğu yok',
      (t) async {
        final auth = DocumentFakeAuth();
        final service = seededDocuments(auth);
        await _pump(t, auth, service);
        final drive = find.byKey(const ValueKey<String>('drive_storage_card'));
        final quota = find.byKey(const ValueKey<String>('document_usage_bar'));
        expect(drive, findsOneWidget);
        expect(quota, findsNothing);
        expect(find.byType(DocumentAdminCard), findsNWidgets(3));
        final driveBottom = t.getBottomLeft(drive).dy;
        expect(
          driveBottom,
          lessThanOrEqualTo(
            t.getTopLeft(find.byType(DocumentAdminCard).first).dy,
          ),
        );
        expect(t.takeException(), isNull);
      },
    );

    testWidgets(
      'yazma yetkisi olan yönetimde belge listesiyle birlikte görünür ("Yakında…" bağlı değilken)',
      (t) async {
        final auth = DocumentFakeAuth();
        final service = seededDocuments(auth);
        await _pump(t, auth, service);
        expect(find.byType(DocumentAdminCard), findsNWidgets(3));
        expect(
          find.byKey(const ValueKey<String>('drive_storage_card')),
          findsOneWidget,
        );
        expect(find.text('Google Drive'), findsOneWidget);
        expect(find.text('Google Drive bağlantısı Yakında…'), findsOneWidget);
        expect(t.takeException(), isNull);
      },
    );

    testWidgets('kurul üyesi (salt okunur) Drive bölümünü görmez', (t) async {
      final auth = DocumentFakeAuth();
      final service = seededDocuments(auth);
      await _pump(t, auth, service, sites: _boardSite);
      expect(find.byType(DocumentAdminCard), findsWidgets);
      expect(
        find.byKey(const ValueKey<String>('drive_storage_card')),
        findsNothing,
      );
    });
  });

  group('yatay telefon (640x360 x2,0)', () {
    for (final dark in const <bool>[false, true]) {
      testWidgets(
        'dolu liste, kota çubuğu ve süzgeçler taşmaz (${dark ? 'koyu' : 'açık'})',
        (t) async {
          final auth = DocumentFakeAuth();
          final service = seededDocuments(auth);
          await _pump(
            t,
            auth,
            service,
            width: 640,
            height: 360,
            scale: 2.0,
            dark: dark,
          );
          expect(find.byType(DocumentAdminCard), findsNWidgets(3));
          expect(t.takeException(), isNull);
        },
      );
    }
  });

  group('taşma matrisi', () {
    listMatrix(
      'liste: dolu görünüm (kategori, kitle, sürüm, indirme, kota çubuğu)',
      (t, w, h, s, dark) async {
        final auth = DocumentFakeAuth();
        final service = seededDocuments(auth);
        await _pump(
          t,
          auth,
          service,
          width: w,
          height: h,
          scale: s,
          dark: dark,
        );

        expect(find.byType(DocumentAdminCard), findsNWidgets(3));
        // Sıra: id DESC.
        final order = [
          for (final card in t.widgetList<DocumentAdminCard>(
            find.byType(DocumentAdminCard),
          ))
            card.document.id,
        ];
        expect(order, <int>[41, 40, 39]);
        expect(find.text('Site Yönetmeliği'), findsOneWidget);
        expect(
          find.text('Kitle: A Blok'),
          findsOneWidget,
          reason: 'blok hedefi kitle özetinde',
        );
        expect(find.text('Kitle: Yönetim'), findsOneWidget);
        expect(find.text('Kitle: Özel yönetici belgesi'), findsOneWidget);
        expect(
          find.text('v2'),
          findsOneWidget,
          reason: 'yalnız çok sürümlü belgede',
        );
        expect(find.text('12 indirme'), findsOneWidget);
        expect(find.text('Belge Yükle'), findsOneWidget);
        expect(
          find.byKey(const ValueKey<String>('document_usage_label')),
          findsNothing,
        );
        expect(find.text('42 MB / 200 MB'), findsNothing);
        expect(
          find.byKey(const ValueKey<String>('document_usage_bar')),
          findsNothing,
        );
        expect(
          find.byKey(const ValueKey<String>('documents_drive_required_note')),
          findsOneWidget,
        );
        expect(
          t
              .widget<PrimaryActionButton>(
                find.byKey(const ValueKey<String>('document_create')),
              )
              .onPressed,
          isNull,
        );
        for (final label in const [
          'Hepsi',
          'Yönetmelik',
          'Tutanak / Karar',
          'Sözleşme',
          'Bilgilendirme',
          'Diğer',
        ]) {
          expect(
            find.widgetWithText(ChoiceChip, label),
            findsOneWidget,
            reason: label,
          );
        }
        expect(find.widgetWithText(ChoiceChip, 'Yayında'), findsOneWidget);
        expect(find.widgetWithText(ChoiceChip, 'Silinenler'), findsOneWidget);
      },
    );

    listMatrix('liste: Silinenler görünümü (kalan gün çipi)', (
      t,
      w,
      h,
      s,
      dark,
    ) async {
      final auth = DocumentFakeAuth();
      final service = seededDocuments(auth);
      await _pump(t, auth, service, width: w, height: h, scale: s, dark: dark);
      await tapFinder(
        t,
        find.byKey(const ValueKey<String>('document_status_deleted')),
      );
      await settleFor(t);

      expect(find.byType(DocumentAdminCard), findsOneWidget);
      expect(
        find.text('Silindi · 12 gün sonra kalıcı silinir'),
        findsOneWidget,
      );
      expect(find.text('Silinen belgeler'), findsOneWidget);
      expect(
        find.textContaining('indirme'),
        findsNothing,
        reason: 'silinmişte indirme sayısı gösterilmez',
      );
    });

    listMatrix('boş durum: yazma yetkilisine yönlendirme', (
      t,
      w,
      h,
      s,
      dark,
    ) async {
      final auth = DocumentFakeAuth();
      final service = FakeDocumentService(authService: auth);
      await _pump(t, auth, service, width: w, height: h, scale: s, dark: dark);

      expect(find.text('Henüz belge yok.'), findsOneWidget);
      expect(find.textContaining('Belge Yükle ile'), findsOneWidget);
      expect(find.byType(DocumentAdminCard), findsNothing);
    });

    listMatrix('hata durumu: "belge yok" DENMEZ, Tekrar Dene görünür', (
      t,
      w,
      h,
      s,
      dark,
    ) async {
      final auth = DocumentFakeAuth();
      final service = seededDocuments(auth)
        ..listError = ApiException(
          'Sunucu şu anda yanıt veremiyor (502). Lütfen biraz sonra tekrar deneyin.',
        );
      await _pump(t, auth, service, width: w, height: h, scale: s, dark: dark);

      final errorNotice = find.byWidgetPredicate(
        (widget) =>
            widget is InlineNotice &&
            widget.message.contains('Sunucu şu anda yanıt veremiyor'),
      );
      expect(errorNotice, findsOneWidget);
      expect(t.widget<InlineNotice>(errorNotice).onRetry, isNotNull);
      expect(find.textContaining('yanıt veremiyor'), findsOneWidget);
      expect(find.text('Tekrar Dene'), findsOneWidget);
      expect(find.text('Henüz belge yok.'), findsNothing);
      expect(find.byType(EmptyCard), findsNothing);
    });

    listMatrix('modül kapalı: açıklayıcı kart + Modüller düğmesi', (
      t,
      w,
      h,
      s,
      dark,
    ) async {
      final auth = DocumentFakeAuth();
      final service = seededDocuments(auth)
        ..listError = ApiException(
          'Bu özellik şu an kapalı. Site yöneticisi Modüller ekranından açabilir.',
          statusCode: 403,
          code: 'MODULE_DISABLED',
        );
      var opened = 0;
      await _pump(
        t,
        auth,
        service,
        width: w,
        height: h,
        scale: s,
        dark: dark,
        onOpenModules: () => opened++,
      );

      expect(
        find.byKey(const ValueKey<String>('documents_module_off')),
        findsOneWidget,
      );
      expect(find.text('Dosya Deposu bu site için kapalı.'), findsOneWidget);
      expect(find.text('Henüz belge yok.'), findsNothing);
      await tapFinder(
        t,
        find.byKey(const ValueKey<String>('documents_open_modules')),
      );
      expect(opened, 1);
    });

    listMatrix(
      'kurul: salt okur (yükleme / kota / Silinenler yok, not görünür)',
      (t, w, h, s, dark) async {
        final auth = DocumentFakeAuth();
        final service = seededDocuments(auth, board: true);
        await _pump(
          t,
          auth,
          service,
          width: w,
          height: h,
          scale: s,
          dark: dark,
          sites: _boardSite,
        );

        expect(
          find.byKey(const ValueKey<String>('documents_read_only_note')),
          findsOneWidget,
        );
        expect(find.text('Belge Yükle'), findsNothing);
        expect(
          find.byKey(const ValueKey<String>('document_usage_bar')),
          findsNothing,
        );
        expect(find.widgetWithText(ChoiceChip, 'Silinenler'), findsNothing);
        // Yönetici belgesi sunucudan zaten gelmez; yükleyen adı yoktur.
        expect(find.text('Yönetici Sözleşmesi'), findsNothing);
        expect(find.byType(DocumentAdminCard), findsNWidgets(2));
        expect(find.textContaining('Yükleyen'), findsNothing);
      },
    );
  });

  group('süzgeç, arama ve yarışlar', () {
    testWidgets('kategori süzgeci sunucuya gider; "Hepsi" süzgeci kaldırır', (
      t,
    ) async {
      final auth = DocumentFakeAuth();
      final service = seededDocuments(auth);
      await _pump(t, auth, service);
      expect(service.listCalls.last.category, isNull);

      await tapFinder(
        t,
        find.byKey(const ValueKey<String>('document_category_contract')),
      );
      await settleFor(t);
      expect(service.listCalls.last.category, 'contract');
      expect(find.byType(DocumentAdminCard), findsOneWidget);
      expect(find.text('Yönetici Sözleşmesi'), findsOneWidget);

      await tapFinder(
        t,
        find.byKey(const ValueKey<String>('document_category_all')),
      );
      await settleFor(t);
      expect(service.listCalls.last.category, isNull);
      expect(find.byType(DocumentAdminCard), findsNWidgets(3));
    });

    testWidgets(
      'süzgeçle boş sonuç: "Bu arama ve süzgeç için belge bulunamadı."',
      (t) async {
        final auth = DocumentFakeAuth();
        final service = seededDocuments(auth);
        await _pump(t, auth, service);
        await tapFinder(
          t,
          find.byKey(const ValueKey<String>('document_category_other')),
        );
        await settleFor(t);
        expect(
          find.text('Bu arama ve süzgeç için belge bulunamadı.'),
          findsOneWidget,
        );
        expect(find.text('Henüz belge yok.'), findsNothing);
      },
    );

    testWidgets(
      'arama duraksayınca çalışır (350 ms); art arda yazılan tek istek yapar',
      (t) async {
        final auth = DocumentFakeAuth();
        final service = seededDocuments(auth);
        await _pump(t, auth, service);
        final before = service.listCalls.length;
        await _typeSearch(t, 'yön');
        await t.pump(const Duration(milliseconds: 100));
        await _typeSearch(t, 'yönet');
        expect(service.listCalls.length, before, reason: 'debounce');
        await _debounce(t);
        await settleFor(t);
        expect(service.listCalls.length, before + 1);
        expect(service.listCalls.last.query, 'yönet');
        expect(
          find.byType(DocumentAdminCard),
          findsNWidgets(2),
          reason: '"Site Yönetmeliği" ve "Yönetici Sözleşmesi"',
        );
      },
    );

    testWidgets('eski arama yanıtı yenisini EZMEZ', (t) async {
      final auth = DocumentFakeAuth();
      final service = seededDocuments(auth);
      await _pump(t, auth, service);
      final slow = Completer<void>();
      service.listGates.add(slow); // ilk arama yavaş
      await _typeSearch(t, 'tutanak');
      await _debounce(t);
      await _typeSearch(t, 'sözleşme');
      await _debounce(t);
      await settleFor(t);
      expect(find.text('Yönetici Sözleşmesi'), findsOneWidget);
      slow.complete(); // eski yanıt şimdi gelir
      await settleFor(t);
      expect(find.text('Yönetici Sözleşmesi'), findsOneWidget);
      expect(
        find.text('Kurul Toplantı Tutanağı'),
        findsNothing,
        reason: 'eski sonuç yeniyi ezmedi',
      );
    });

    testWidgets('sayfalama: 30 + "Daha fazla yükle"', (t) async {
      final auth = DocumentFakeAuth();
      final service = FakeDocumentService(authService: auth);
      for (var i = 1; i <= 35; i++) {
        service.docs[i] = FakeDoc(i, title: 'Belge $i');
      }
      await _pump(t, auth, service, height: 6000);
      expect(find.byType(DocumentAdminCard), findsNWidgets(30));
      expect(find.text('Daha fazla yükle'), findsOneWidget);
      await tapFinder(t, find.text('Daha fazla yükle'));
      await settleFor(t);
      expect(find.byType(DocumentAdminCard), findsNWidgets(35));
      expect(find.text('Daha fazla yükle'), findsNothing);
      expect(service.listCalls.last.offset, 30);
    });

    testWidgets('yenile düğmesi ve reload() listeyi yeniden çeker', (t) async {
      final auth = DocumentFakeAuth();
      final service = seededDocuments(auth);
      final key = await _pump(t, auth, service);
      final before = service.listCalls.length;
      await tapFinder(t, find.byTooltip('Yenile'));
      await settleFor(t);
      expect(service.listCalls.length, before + 1);
      await key.currentState!.reload();
      await settleFor(t);
      expect(service.listCalls.length, greaterThan(before + 1));
    });

    testWidgets('hata sonrası Tekrar Dene listeyi getirir', (t) async {
      final auth = DocumentFakeAuth();
      final service = seededDocuments(auth)
        ..listError = ApiException('Bağlantı kurulamadı.');
      await _pump(t, auth, service);
      expect(find.text('Tekrar Dene'), findsOneWidget);
      service.listError = null;
      await tapFinder(t, find.text('Tekrar Dene'));
      await settleFor(t);
      expect(find.byType(DocumentAdminCard), findsNWidgets(3));
      expect(find.text('Tekrar Dene'), findsNothing);
    });

    testWidgets('yükleme sürerken iskelet; boş durum çizilmez', (t) async {
      final auth = DocumentFakeAuth();
      final service = seededDocuments(auth);
      final gate = Completer<void>();
      service.listGates.add(gate);
      await _pump(t, auth, service);
      expect(find.byType(ListSkeleton), findsOneWidget);
      expect(find.text('Henüz belge yok.'), findsNothing);
      gate.complete();
      await settleFor(t);
      expect(find.byType(DocumentAdminCard), findsNWidgets(3));
    });
  });

  group('site seçici', () {
    testWidgets(
      'bağlı siteden başka siteye geçince Drive yanıtı gelene kadar yükleme kilitli kalır',
      (t) async {
        final auth = DocumentFakeAuth();
        final gate = Completer<http.Response>();
        addTearDown(() {
          if (!gate.isCompleted) {
            gate.complete(
              http.Response('{"configured":false,"connected":false}', 200),
            );
          }
        });
        DriveStorageCard.debugApi = DriveStorageApi(
          baseUrl: 'http://localhost',
          client: MockClient((request) async {
            if (request.url.path.contains('/12/')) return gate.future;
            return http.Response(
              '{"configured":true,"connected":true,"status":"connected"}',
              200,
              headers: {'content-type': 'application/json'},
            );
          }),
        );
        final service = seededDocuments(auth);
        await _pump(
          t,
          auth,
          service,
          sites: const [
            PeopleSite(code: 11, name: 'Gül Sitesi', canWrite: true),
            PeopleSite(code: 12, name: 'Mavi Park', canWrite: true),
          ],
        );
        final upload = find.byKey(const ValueKey<String>('document_create'));
        expect(t.widget<PrimaryActionButton>(upload).onPressed, isNotNull);
        await tapFinder(t, find.byType(DropdownButtonFormField<int>));
        await tapFinder(t, find.text('Mavi Park').last);
        await settleFor(t, 100);
        expect(
          t.widget<PrimaryActionButton>(upload).onPressed,
          isNull,
          reason: 'önceki sitenin bağlı Drive durumu yeni siteye taşınmamalı',
        );
        expect(
          find.textContaining('Google Drive bağlantısı doğrulanıyor'),
          findsOneWidget,
        );
        expect(service.listCalls.last.site, 12);
        gate.complete(
          http.Response(
            '{"configured":true,"connected":false,"status":"disconnected"}',
            200,
            headers: {'content-type': 'application/json'},
          ),
        );
        await settleFor(t, 100);
        expect(t.widget<PrimaryActionButton>(upload).onPressed, isNull);
        expect(
          find.byKey(const ValueKey<String>('documents_drive_required_note')),
          findsOneWidget,
        );
        expect(t.takeException(), isNull);
      },
    );

    testWidgets(
      'birden çok sitede seçici çıkar; site değişince eski liste atılır',
      (t) async {
        final auth = DocumentFakeAuth();
        final service = seededDocuments(auth);
        service.docs[70] = FakeDoc(
          70,
          title: 'Mavi Park Belgesi',
          siteCode: 12,
        );
        await _pump(
          t,
          auth,
          service,
          sites: const <PeopleSite>[
            PeopleSite(code: 11, name: 'Gül Sitesi', canWrite: true),
            PeopleSite(code: 12, name: 'Mavi Park', canWrite: true),
          ],
        );
        expect(find.byType(DropdownButtonFormField<int>), findsOneWidget);
        expect(find.text('Site Yönetmeliği'), findsOneWidget);
        await tapFinder(t, find.byType(DropdownButtonFormField<int>));
        await tapFinder(t, find.text('Mavi Park').last);
        await settleFor(t);
        expect(service.listCalls.last.site, 12);
        expect(find.text('Mavi Park Belgesi'), findsOneWidget);
        expect(find.text('Site Yönetmeliği'), findsNothing);
      },
    );

    testWidgets(
      'süper kullanıcı: tüm onaylı siteler çekilir ve yazma yetkisi verilir',
      (t) async {
        final auth = DocumentFakeAuth(role: UserRole.superUser);
        final service = seededDocuments(auth);
        await _pump(t, auth, service, sites: const <PeopleSite>[], all: true);
        expect(auth.listSitesCalls, greaterThan(0));
        expect(find.text('Belge Yükle'), findsOneWidget);
      },
    );

    testWidgets('site yokken açıklayıcı boş durum', (t) async {
      final auth = DocumentFakeAuth();
      final service = seededDocuments(auth);
      await _pump(t, auth, service, sites: const <PeopleSite>[]);
      expect(find.text('Kayıtlı site bulunamadı.'), findsOneWidget);
    });
  });

  group('erişilebilirlik', () {
    testWidgets(
      'kart tek birleşik ekran okuyucu etiketi taşır ("PDF, 2,4 MB")',
      (t) async {
        final handle = t.ensureSemantics();
        final auth = DocumentFakeAuth();
        final service = seededDocuments(auth);
        await _pump(t, auth, service);
        final label = t.getSemantics(_card('Site Yönetmeliği')).label;
        expect(label, contains('Belge: Site Yönetmeliği'));
        expect(label, contains('Yönetmelik'));
        expect(label, contains('Kitle: A Blok'));
        expect(label, contains('PDF, 2,4 MB'));
        expect(label, contains('12 indirme'));
        handle.dispose();
      },
    );

    testWidgets(
      'Drive gereksinimi ekran okuyucuya açıklanır; eski sunucu kotası gösterilmez',
      (t) async {
        final handle = t.ensureSemantics();
        final auth = DocumentFakeAuth();
        final service = seededDocuments(auth)..usedBytes = 200 * 1024 * 1024;
        await _pump(t, auth, service);
        final note = find.byKey(
          const ValueKey<String>('documents_drive_required_note'),
        );
        final noteText = find.descendant(
          of: note,
          matching: find.text(t.widget<InlineNotice>(note).message),
        );
        expect(t.getSemantics(noteText).label, contains('Google Drive'));
        expect(find.byType(DocumentUsageBar), findsNothing);
        expect(find.textContaining('MB / 200 MB'), findsNothing);
        expect(
          t
              .widget<PrimaryActionButton>(
                find.byKey(const ValueKey<String>('document_create')),
              )
              .onPressed,
          isNull,
        );
        handle.dispose();
      },
    );

    testWidgets('düğmeler en az 48 dp yükseklikte', (t) async {
      final auth = DocumentFakeAuth();
      final service = seededDocuments(auth);
      await _pump(t, auth, service, width: 320, height: 640, scale: 2.0);
      final button = t.getSize(find.byType(PrimaryActionButton).first);
      expect(button.height, greaterThanOrEqualTo(48));
    });
  });
}
