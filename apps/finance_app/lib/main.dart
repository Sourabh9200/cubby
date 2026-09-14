import 'package:finance_db/finance_db.dart';
import 'package:flutter/material.dart';

import 'app.dart';
import 'data/drift_finance_repository.dart';

/// Entry point.
///
/// The database is opened before the first frame so that a failure to decrypt
/// is reported as a failure, rather than surfacing later as mysteriously empty
/// screens. Encryption is only real if the native library supports it, so the
/// open path verifies the file header rather than assuming.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    final open = await DatabaseOpener.open();
    runApp(FinanceApp(repository: DriftFinanceRepository(db: open.database)));
  } on Object catch (error, stackTrace) {
    // Showing the error beats a crash-on-launch with no explanation: this is
    // the one path where a user could otherwise lose access to their own data
    // and have no idea why.
    debugPrint('Database open failed: $error');
    debugPrintStack(stackTrace: stackTrace);
    runApp(_StartupFailure(error: error));
  }
}

/// Shown when the database cannot be opened.
class _StartupFailure extends StatelessWidget {
  const _StartupFailure({required this.error});

  final Object error;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                const Icon(Icons.lock_outline_rounded, size: 48),
                const SizedBox(height: 20),
                Text(
                  'Could not open your data',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 12),
                Text(
                  'The local database could not be decrypted. Your data has not '
                  'been changed or deleted.\n\n$error',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
