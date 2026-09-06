import 'package:prep_book/app/app.dart';
import 'package:prep_book/bootstrap.dart';

Future<void> main() async {
  await bootstrap(() => const App());
}
