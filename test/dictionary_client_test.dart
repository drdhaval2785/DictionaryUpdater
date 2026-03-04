import 'package:flutter_test/flutter_test.dart';
import 'package:dictionary_updater/services/dictionary_client.dart';

void main() {
  group('DictionaryClient.toRawUrl', () {
    test('converts GitHub blob URL to raw content URL', () {
      const input =
          'https://github.com/indic-dict/stardict-sanskrit/blob/gh-pages/sa-head/en-entries/tars/tars.MD';
      const expected =
          'https://raw.githubusercontent.com/indic-dict/stardict-sanskrit/gh-pages/sa-head/en-entries/tars/tars.MD';
      expect(DictionaryClient.toRawUrl(input), equals(expected));
    });

    test('leaves non-GitHub URLs unchanged', () {
      const url = 'https://example.com/dict.tar.gz';
      expect(DictionaryClient.toRawUrl(url), equals(url));
    });

    test('handles multi-segment branch paths', () {
      const input =
          'https://github.com/user/repo/blob/main/path/to/file.MD';
      const expected =
          'https://raw.githubusercontent.com/user/repo/main/path/to/file.MD';
      expect(DictionaryClient.toRawUrl(input), equals(expected));
    });
  });

  group('DictionaryClient._extractLinks', () {
    const baseUrl =
        'https://raw.githubusercontent.com/indic-dict/stardict-sanskrit/gh-pages/sa-head/en-entries/tars/';

    test('extracts absolute markdown links', () {
      const content =
          '[Dict](https://example.com/mydict.tar.gz)\n[Other](https://example.com/other.zip)\n[NewDict](https://example.com/new.7z)';
      final links = DictionaryClient.extractLinksForTest(content, '');
      expect(links, contains('https://example.com/mydict.tar.gz'));
      expect(links, contains('https://example.com/other.zip'));
      expect(links, contains('https://example.com/new.7z'));
    });

    test('extracts relative markdown links and resolves them', () {
      const content = '[Dict](./sa-IAST-kRdanta.tar.gz)';
      final links = DictionaryClient.extractLinksForTest(content, baseUrl);
      expect(links.first,
          contains('sa-IAST-kRdanta.tar.gz'));
    });

    test('extracts plain https URLs from pasted text', () {
      const content = '''
https://example.com/dict1.tar.gz
https://example.com/dict2.zip
Some other text
https://example.com/dict3.tar.bz2
https://example.com/dict4.rar
https://example.com/dict5.tar.xz
''';
      final links = DictionaryClient.extractLinksForTest(content, '');
      expect(links.length, equals(5));
      expect(links, contains('https://example.com/dict4.rar'));
      expect(links, contains('https://example.com/dict5.tar.xz'));
    });

    test('deduplicates links', () {
      const content =
          '[Dict](https://example.com/dict.tar.gz)\nhttps://example.com/dict.tar.gz';
      final links = DictionaryClient.extractLinksForTest(content, '');
      expect(links.where((l) => l.contains('dict.tar.gz')).length, equals(1));
    });

    test('returns empty list when no links found', () {
      const content = 'No links here, just plain text.';
      final links = DictionaryClient.extractLinksForTest(content, '');
      expect(links, isEmpty);
    });
  });
}
