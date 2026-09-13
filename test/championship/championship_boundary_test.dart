import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _productDirectories = <String>[
  'lib/app',
  'lib/application',
  'lib/domain',
  'lib/export',
  'lib/persistence',
  'lib/presentation',
];

const _productEntrypoints = <String>[
  'lib/main_development.dart',
  'lib/main_staging.dart',
  'lib/main_production.dart',
];

const _championshipBannedSubstrings = <String>[
  'dart:io',
  'package:sqflite',
  'package:prep_book/bootstrap.dart',
  'package:prep_book/persistence/',
  'bootstrap(',
  'IngredientRepository',
  'RecipeRepository',
  'ProductionRunRepository',
  'OPENAI_API_KEY',
];

final _directiveStatement = RegExp(r'\b(?:import|export)\b[^;]*;');
final _quotedUri = RegExp("'([^']*)'|\"([^\"]*)\"");

List<File> _dartFilesUnder(String directoryPath) {
  final directory = Directory(directoryPath);
  if (!directory.existsSync()) {
    throw StateError('$directoryPath does not exist. No files were checked.');
  }
  return directory
      .listSync(recursive: true)
      .whereType<File>()
      .where((file) => file.path.endsWith('.dart'))
      .toList();
}

Iterable<String> _directiveUris(String source) sync* {
  for (final directive in _directiveStatement.allMatches(source)) {
    for (final match in _quotedUri.allMatches(directive.group(0)!)) {
      yield match.group(1) ?? match.group(2)!;
    }
  }
}

void main() {
  test('the shipping product does not import the championship variant', () {
    final productFiles = [
      for (final directory in _productDirectories)
        ..._dartFilesUnder(directory),
      for (final path in _productEntrypoints) File(path),
    ];
    final offenders = <String>[];

    for (final file in productFiles) {
      for (final uri in _directiveUris(file.readAsStringSync())) {
        if (uri.startsWith('package:prep_book/championship/')) {
          offenders.add('${file.path} imports $uri');
        }
      }
    }

    expect(offenders, isEmpty);
  });

  test('the championship production code stays inside its web boundary', () {
    final offenders = <String>[];
    final championshipFiles = [
      ..._dartFilesUnder('lib/championship'),
      File('lib/main_championship.dart'),
    ];

    for (final file in championshipFiles) {
      final source = file.readAsStringSync();
      for (final banned in _championshipBannedSubstrings) {
        if (source.contains(banned)) {
          offenders.add('${file.path} contains $banned');
        }
      }
    }

    expect(offenders, isEmpty);
  });
}
