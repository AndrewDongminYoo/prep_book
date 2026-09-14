@TestOn('browser')
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prep_book/main_championship.dart' as championship;
import 'package:web/web.dart' as web;

void main() {
  test('writes the resolved locale language code to the HTML element', () {
    final documentElement = web.document.documentElement!;
    final originalLanguage = documentElement.getAttribute('lang');
    addTearDown(() {
      if (originalLanguage == null) {
        documentElement.removeAttribute('lang');
      } else {
        documentElement.setAttribute('lang', originalLanguage);
      }
    });

    championship.updateChampionshipDocumentLanguage(const Locale('en'));
    expect(documentElement.getAttribute('lang'), 'en');

    championship.updateChampionshipDocumentLanguage(const Locale('ko'));
    expect(documentElement.getAttribute('lang'), 'ko');
  });
}
