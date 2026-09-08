import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prep_book/app/app.dart';

const _message = 'The recipe database could not be opened.';
const _retryLabel = 'Try again';

void main() {
  group('StartupFailureApp', () {
    testWidgets('says startup failed and offers a retry', (tester) async {
      await tester.pumpWidget(StartupFailureApp(onRetry: () {}));

      expect(find.text(_message), findsOneWidget);
      // By label as well as by type: a button rendered with the wrong
      // string is the failure a `findsOneWidget` on the type alone misses.
      expect(find.widgetWithText(FilledButton, _retryLabel), findsOneWidget);
    });

    testWidgets('the retry button runs startup again', (tester) async {
      var retries = 0;
      await tester.pumpWidget(
        StartupFailureApp(
          onRetry: () {
            retries++;
          },
        ),
      );

      // Fails against a button wired to `null`, which renders identically
      // and is what the recipe library's disabled action looks like.
      await tester.tap(find.widgetWithText(FilledButton, _retryLabel));
      await tester.pump();

      expect(retries, 1);
    });
  });
}
