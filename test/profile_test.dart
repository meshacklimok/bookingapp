import 'package:bookingapp/features/profile/domain/profile.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Profile.fromMap', () {
    test('reads every column', () {
      final p = Profile.fromMap({
        'id': 'u1',
        'full_name': 'Wanjiru Kamau',
        'phone': '254712345678',
        'avatar_url': 'https://example.com/a.png',
        'is_platform_admin': true,
      });
      expect(p.id, 'u1');
      expect(p.fullName, 'Wanjiru Kamau');
      expect(p.phone, '254712345678');
      expect(p.avatarUrl, 'https://example.com/a.png');
      expect(p.isPlatformAdmin, isTrue);
    });

    test('allows missing optional columns and defaults admin to false', () {
      final p = Profile.fromMap({'id': 'u2'});
      expect(p.fullName, isNull);
      expect(p.phone, isNull);
      expect(p.avatarUrl, isNull);
      expect(p.isPlatformAdmin, isFalse);
    });
  });
}
