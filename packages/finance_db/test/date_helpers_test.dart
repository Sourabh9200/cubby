import 'dart:io';

import 'package:finance_db/finance_db.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('date helpers', () {
    test('month boundaries handle February, not a fixed thirty days', () {
      expect(monthStartIso(DateTime(2026, 2, 15)), '2026-02-01');
      // The exclusive end must roll into March.
      expect(monthEndIso(DateTime(2026, 2, 15)), '2026-03-01');
      expect(monthStartIso(DateTime(2026, 12, 31)), '2026-12-01');
      expect(monthEndIso(DateTime(2026, 12, 31)), '2027-01-01');
    });

    test('a leap day is preserved', () {
      expect(isoDate(DateTime(2028, 2, 29)), '2028-02-29');
    });

    test('single-digit months and days are zero padded', () {
      expect(isoDate(DateTime(2026, 1, 5)), '2026-01-05');
      expect(isoMonth(DateTime(2026, 1, 5)), '2026-01');
    });

    test('ISO date strings sort chronologically as plain strings', () {
      // This is what lets the range filters use ordinary comparison and stay
      // index-friendly, instead of needing a date function that would prevent
      // index use.
      final dates = <String>['2026-10-01', '2026-09-30', '2026-01-05']..sort();
      expect(dates, <String>['2026-01-05', '2026-09-30', '2026-10-01']);
    });

    test('isoDate and DateTime.parse round-trip', () {
      for (final date in <DateTime>[
        DateTime(2026, 1, 1),
        DateTime(2026, 6, 15),
        DateTime(2026, 12, 31),
      ]) {
        expect(DateTime.parse(isoDate(date)), date);
      }
    });
  });

  group('encryption header detection', () {
    test('reports false for a plaintext SQLite file', () async {
      // Builds a real, unencrypted SQLite file and confirms the detector
      // recognizes the magic header. This is the check that catches the
      // dangerous case where `PRAGMA key` is silently a no-op.
      final directory = await Directory.systemTemp.createTemp(
        'finance_db_test',
      );
      final file = File('${directory.path}/plain.sqlite');
      try {
        final db = AppDatabase.forFile(file);
        await db.customStatement('CREATE TABLE probe (id INTEGER);');
        await db.close();

        expect(await file.exists(), isTrue);
        expect(
          await isFileEncrypted(file),
          isFalse,
          reason: 'a plaintext database must be detected as unencrypted',
        );
      } finally {
        await directory.delete(recursive: true);
      }
    });

    test('reports false for a file that does not exist', () async {
      expect(
        await isFileEncrypted(File('/nonexistent/path/db.sqlite')),
        isFalse,
      );
    });

    test('reports false for a file too short to be a database', () async {
      final directory = await Directory.systemTemp.createTemp(
        'finance_db_test',
      );
      final file = File('${directory.path}/tiny.sqlite')
        ..writeAsStringSync('abc');
      try {
        expect(await isFileEncrypted(file), isFalse);
      } finally {
        await directory.delete(recursive: true);
      }
    });
  });
}
