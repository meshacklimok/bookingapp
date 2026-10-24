import 'package:bookingapp/core/utils/errors.dart';
import 'package:bookingapp/core/utils/validators.dart';
import 'package:bookingapp/features/org_dashboard/data/org_repository.dart';
import 'package:bookingapp/features/org_dashboard/domain/organization.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  group('slugify', () {
    test('lowercases and joins words with dashes', () {
      expect(slugify('Glow Beauty Studio'), 'glow-beauty-studio');
    });

    test('drops apostrophes and collapses punctuation', () {
      expect(slugify("Wanjiru's Salon & Spa!"), 'wanjirus-salon-spa');
    });

    test('trims leading and trailing separators', () {
      expect(slugify('  --Nairobi Yoga--  '), 'nairobi-yoga');
    });

    test('falls back when nothing usable is left', () {
      expect(slugify('★★★'), 'org');
      expect(slugify(''), 'org');
    });
  });

  group('OrgStatus.parse', () {
    test('reads each database value', () {
      expect(OrgStatus.parse('pending'), OrgStatus.pending);
      expect(OrgStatus.parse('approved'), OrgStatus.approved);
      expect(OrgStatus.parse('suspended'), OrgStatus.suspended);
    });

    test('treats unknown or missing values as pending, never approved', () {
      expect(OrgStatus.parse('archived'), OrgStatus.pending);
      expect(OrgStatus.parse(null), OrgStatus.pending);
    });
  });

  group('Organization.fromMap', () {
    test('reads every column', () {
      final o = Organization.fromMap({
        'id': 'o1',
        'name': 'Glow',
        'slug': 'glow',
        'status': 'approved',
        'description': 'Hair and nails',
        'category': 'Beauty',
      });
      expect(o.id, 'o1');
      expect(o.isApproved, isTrue);
      expect(o.description, 'Hair and nails');
      expect(o.category, 'Beauty');
    });

    test('optional columns may be null', () {
      final o = Organization.fromMap({'id': 'o2', 'name': 'Fit', 'slug': 'fit', 'status': 'pending'});
      expect(o.isApproved, isFalse);
      expect(o.description, isNull);
      expect(o.category, isNull);
    });
  });

  group('OrgMembership.fromMap', () {
    test('carries the organization status', () {
      final m = OrgMembership.fromMap({
        'org_id': 'o1',
        'role': 'owner',
        'organizations': {'name': 'Glow', 'status': 'pending'},
      });
      expect(m.status, OrgStatus.pending);
      expect(m.orgName, 'Glow');
    });
  });

  group('validateOrgName', () {
    test('rejects empty, one-letter and very long names', () {
      expect(validateOrgName(null), isNotNull);
      expect(validateOrgName('  '), isNotNull);
      expect(validateOrgName('A'), isNotNull);
      expect(validateOrgName('x' * 81), isNotNull);
    });

    test('accepts a normal name, ignoring surrounding spaces', () {
      expect(validateOrgName(' Glow Beauty '), isNull);
    });
  });

  test('a slug clash that survives the retries reads as a naming problem', () {
    const clash = PostgrestException(
      message: 'duplicate key value violates unique constraint "organizations_slug_key"',
      code: '23505',
    );
    expect(friendlyError(clash), contains('similar name'));
  });
}
