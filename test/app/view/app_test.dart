import 'package:flutter_test/flutter_test.dart';
import 'package:prep_book/app/app.dart';
import 'package:prep_book/application/application.dart';
import 'package:prep_book/presentation/presentation.dart';

import '../../application/fakes.dart';

void main() {
  group('App', () {
    testWidgets('opens on the recipe library', (tester) async {
      final recipes = FakeRecipeRepository()..seed(buildRecipe(id: 'r-a'));

      await tester.pumpWidget(
        App(
          listLibrary: ListLibrary(recipes),
          searchLibrary: SearchLibrary(recipes),
        ),
      );
      await tester.pump();

      expect(find.byType(RecipeLibraryPage), findsOneWidget);
      expect(find.text('Test recipe'), findsOneWidget);
    });
  });
}
