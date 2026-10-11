import 'package:bizzvot/features/organization_profile/data/organization_profile_repository.dart';
import 'package:bizzvot/features/organization_profile/domain/profile_form_values.dart';
import 'package:bizzvot/shared/models/organization.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fake_api.dart';

const _doc = {
  '_id': 'org1',
  'ownerUserId': 'u1',
  'name': 'Acme',
  'industry': 'Real estate',
  'address': '1 Main St',
  'gstNumber': '29ABCDE1234F1Z5',
  'status': 'active',
  'maxCards': 3,
};

void main() {
  late FakeApi fake;
  late OrganizationProfileRepository repo;

  setUp(() {
    fake = FakeApi();
    repo = OrganizationProfileRepository(fake.client);
  });

  test('parses the Organization document', () async {
    fake.on('GET', '/organization/profile', FakeResponse.ok(_doc));
    final p = await repo.fetch();
    expect(p.id, 'org1');
    expect(p.name, 'Acme');
    expect(p.industry, 'Real estate');
    expect(p.status, 'active');
    expect(ProfileFormValues.fromProfile(p).gstNumber, '29ABCDE1234F1Z5');
  });

  test('PATCH sends only the given changes and parses the result', () async {
    fake.on('PATCH', '/organization/profile',
        FakeResponse.ok({..._doc, 'name': 'Acme Group'}));
    final p = await repo.update({'name': 'Acme Group'});
    expect(fake.requests.single.body, {'name': 'Acme Group'});
    expect(p.name, 'Acme Group');
  });

  test('re-fetches when the PATCH response has no profile', () async {
    fake
      ..on('PATCH', '/organization/profile', FakeResponse.ok({'updated': true}))
      ..on('GET', '/organization/profile', FakeResponse.ok(_doc));
    final p = await repo.update({'industry': 'Retail'});
    expect(p.name, 'Acme');
    expect(fake.requests.map((r) => r.method), ['PATCH', 'GET']);
  });

  group('ProfileFormValues.changesFrom', () {
    final original = OrganizationProfile.fromJson(_doc);

    test('only changed allow-listed fields, never null', () {
      const v = ProfileFormValues(
        name: 'Acme',
        industry: '',
        address: '1 Main St',
        gstNumber: '29abcde1234f1z5',
      );
      final changes = v.changesFrom(original);
      expect(changes, {'industry': ''});
      expect(changes.values.contains(null), isFalse);
    });

    test('an empty name is never sent', () {
      const v = ProfileFormValues(
        name: '',
        industry: 'Real estate',
        address: '1 Main St',
        gstNumber: '29ABCDE1234F1Z5',
      );
      expect(v.changesFrom(original), isEmpty);
    });

    test('directory visibility (PROPOSED) and drop detection', () {
      const v = ProfileFormValues(
        name: 'Acme',
        industry: 'Real estate',
        address: '1 Main St',
        gstNumber: '29ABCDE1234F1Z5',
        directoryVisibility: DirectoryVisibility.private,
      );
      final changes = v.changesFrom(original);
      expect(changes, {'directoryVisibility': 'private'});
      // Backend ignored the field.
      expect(directoryChangeDropped(changes, original), isTrue);
      // Backend persisted it.
      final saved = OrganizationProfile.fromJson({..._doc, 'directoryVisibility': 'private'});
      expect(directoryChangeDropped(changes, saved), isFalse);
    });
  });
}
