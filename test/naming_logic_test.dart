import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sdu/services/storage_service.dart';

void main() {
  group('StorageService Naming Logic', () {
    late StorageService storageService;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      // We don't need a real SharedPreferences for the sanitize methods
      // but StorageService requires it in constructor.
    });

    test('sanitizeFileName preserves multiple underscores', () {
      final prefs = SharedPreferences.getInstance();
      return prefs.then((p) {
        storageService = StorageService(p);
        
        expect(storageService.sanitizeFileName('kashika__2023.tar.gz'), 
               equals('kashika__2023.tar.gz'));

        expect(storageService.sanitizeFileName('sa-IAST-kRdanta__2024-01-01.tar.gz'), 
               equals('sa-IAST-kRdanta__2024-01-01.tar.gz'));
        
        expect(storageService.sanitizeFileName('my - file.zip'), 
               equals('my_file.zip'));
               
        expect(storageService.sanitizeFileName('file name with spaces.tar.gz'), 
               equals('file_name_with_spaces.tar.gz'));

        expect(storageService.sanitizeFileName('___edge___'), 
               equals('edge'));
      });
    });

    test('sanitizeFolderName collapses multiple underscores correctly for nested paths', () {
      final prefs = SharedPreferences.getInstance();
      return prefs.then((p) {
        storageService = StorageService(p);
        
        expect(storageService.sanitizeFolderName('sa - संस्कृतम्'), 
               equals('sa_संस्कृतम्'));

        expect(storageService.sanitizeFolderName('sa - संस्कृतम् - vyAkaraNa'), 
               equals('sa_संस्कृतम्_vyAkaraNa'));
        
        expect(storageService.sanitizeFolderName('Group  With   Spaces'), 
               equals('Group_With_Spaces'));
               
        expect(storageService.sanitizeFolderName('Double__Underscore'), 
               equals('Double_Underscore'));
      });
    });
  });
}
