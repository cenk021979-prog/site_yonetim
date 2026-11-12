import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/ui/design/license_plate.dart';

/// Plaka görseli il/harf/rakamı ayrı çizer; tam metin erişilebilir etikette kalır.
Finder findLicensePlate(String plate) => find.descendant(
  of: find.byType(LicensePlateBadge),
  matching: find.byWidgetPredicate(
    (widget) =>
        widget is Semantics && widget.properties.label == 'Plaka: $plate',
  ),
);
