import 'package:flutter_test/flutter_test.dart';
import 'package:dictionary_updater/services/dictionary_client.dart';

void main() {
  group('DictionaryClient Link Extraction', () {
    test('extracts full URLs with multiple extensions (greedy)', () {
      const content = 'Check out https://download.freedict.org/dictionaries/afr-deu/0.3.3/freedict-afr-deu-0.3.3.dictd.tar.xz and also [this](https://example.com/file.dict.dz).';
      final links = DictionaryClient.extractLinksForTest(content, '');
      
      expect(links, contains('https://download.freedict.org/dictionaries/afr-deu/0.3.3/freedict-afr-deu-0.3.3.dictd.tar.xz'));
      expect(links, contains('https://example.com/file.dict.dz'));
      expect(links.length, equals(2));
    });

    test('does not truncate URLs at partial extension matches', () {
      // .dictd contains .dict, so it shouldn't stop at .dict if it's not the end
      const content = 'Download freedict-afr-eng-0.2.2.dict.dz from https://example.com/freedict-afr-eng-0.2.2.dict.dz';
      final links = DictionaryClient.extractLinksForTest(content, '');
      
      expect(links, contains('https://example.com/freedict-afr-eng-0.2.2.dict.dz'));
      expect(links.any((l) => l.endsWith('.dict')), isFalse, reason: 'Should not truncate at .dict');
    });

    test(r'handles boundary checks with (?!\w)', () {
      // If a file ends in .dictd (and .dictd is NOT in the list), it should NOT match .dict because of (?!\w)
      const content = 'file.dictd\nfile.dict';
      final links = DictionaryClient.extractLinksForTest(content, 'https://base.com/');
      
      expect(links.any((l) => l.contains('file.dictd')), isFalse);
      expect(links, contains('https://base.com/file.dict'));
    });
  });
}
