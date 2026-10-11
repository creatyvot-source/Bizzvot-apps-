import 'package:bizzvot/core/config/app_config.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('compareVersions handles numeric ordering and build suffix', () {
    expect(compareVersions('1.10.0', '1.9.9'), 1);
    expect(compareVersions('1.2', '1.2.0'), 0);
    expect(compareVersions('0.1.0+5', '0.1.1'), -1);
  });

  test('updateRequirement', () {
    const cfg = AppConfig(minSupportedVersion: '1.2.0', latestVersion: '1.4.0');
    expect(updateRequirement(cfg, '1.1.9'), UpdateRequirement.required);
    expect(updateRequirement(cfg, '1.3.0'), UpdateRequirement.optional);
    expect(updateRequirement(cfg, '1.4.0'), UpdateRequirement.none);
    expect(updateRequirement(AppConfig.defaults, '0.0.1'), UpdateRequirement.none);
  });

  test('parses nested config and defaults unknown flags to enabled', () {
    final c = AppConfig.fromJson({
      'version': {'min': '1.0.0', 'latest': '1.1.0'},
      'maintenance': {'active': true, 'message': 'Back soon'},
      'links': {'privacyPolicy': 'https://bizzvot.com/privacy'},
      'support': {'email': 'help@bizzvot.com'},
      'features': {'shop': false},
    });
    expect(c.minSupportedVersion, '1.0.0');
    expect(c.maintenance, isTrue);
    expect(c.maintenanceMessage, 'Back soon');
    expect(c.privacyPolicyUrl, 'https://bizzvot.com/privacy');
    expect(c.isEnabled(Flags.shop), isFalse);
    expect(c.isEnabled(Flags.notifications), isTrue);
  });
}
