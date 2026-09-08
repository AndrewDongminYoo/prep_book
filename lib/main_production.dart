import 'package:prep_book/app/app.dart';
import 'package:prep_book/application/application.dart';
import 'package:prep_book/bootstrap.dart';

Future<void> main() async {
  await bootstrap(
    (recipes) => App(
      listLibrary: ListLibrary(recipes),
      searchLibrary: SearchLibrary(recipes),
    ),
  );
}
