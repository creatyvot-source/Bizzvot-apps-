import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/idempotency.dart';
import '../domain/polling.dart';

/// Source of idempotency keys (UUID v4 from `Random.secure`). Overridden in
/// tests for deterministic keys.
final idempotencyKeyFactoryProvider = Provider<KeyFactory>((ref) => uuidV4);

/// Delay used between payment-status polls. Overridden in tests.
final pollSleepProvider = Provider<Sleep>((ref) => realSleep);

/// Bounded polling schedule (≈2 minutes) for payment confirmation.
final pollScheduleProvider = Provider<PollSchedule>((ref) => const PollSchedule());
