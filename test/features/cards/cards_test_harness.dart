import 'dart:convert';
import 'dart:typed_data';

import 'package:bizzvot/app/theme.dart';
import 'package:bizzvot/core/auth/auth_user.dart';
import 'package:bizzvot/core/auth/session_controller.dart';
import 'package:bizzvot/core/config/app_config.dart';
import 'package:bizzvot/core/utilities/json.dart';
import 'package:bizzvot/features/cards/data/cards_repository.dart';
import 'package:bizzvot/features/cards/data/media_picker.dart';
import 'package:bizzvot/features/cards/data/share_service.dart';
import 'package:bizzvot/features/cards/domain/qr_codes.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../helpers/fake_api.dart';

/// 1×1 transparent PNG.
final tinyPng = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII=',
);

String get tinyPngDataUrl => 'data:image/png;base64,${base64Encode(tinyPng)}';

/// Minimal PDF header bytes.
final tinyPdf = Uint8List.fromList(utf8.encode('%PDF-1.4\n%fake\n'));

/// [FakeApi] that can also serve raw binary bodies (QR PNG, vCard, ZIP).
class BinaryFakeApi extends FakeApi {
  final _binary = <String, Uint8List>{};

  void onBytes(String method, String path, Uint8List bytes) =>
      _binary['$method $path'] = bytes;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) {
    final bytes = _binary['${options.method} ${options.path}'];
    if (bytes == null) return super.fetch(options, requestStream, cancelFuture);
    requests.add(
      RecordedRequest(
        options.method,
        options.path,
        options.queryParameters,
        options.data,
      ),
    );
    return Future.value(
      ResponseBody.fromBytes(
        bytes,
        200,
        headers: {
          Headers.contentTypeHeader: ['application/octet-stream'],
        },
      ),
    );
  }
}

class FakeShareService implements ShareService {
  final sharedTexts = <String>[];
  final sharedFiles = <List<ShareableFile>>[];
  final copied = <String>[];

  @override
  Future<void> copyText(String text) async => copied.add(text);

  @override
  Future<void> shareFiles(
    List<ShareableFile> files, {
    String? text,
    Rect? origin,
  }) async => sharedFiles.add(files);

  @override
  Future<void> shareText(String text, {String? subject, Rect? origin}) async =>
      sharedTexts.add(text);
}

class FakeMediaPicker implements MediaPicker {
  FakeMediaPicker({this.image, this.images = const [], this.pdfs = const []});

  PickedFile? image;
  List<PickedFile> images;
  List<PickedFile> pdfs;
  int? lastLimit;

  @override
  Future<PickedFile?> pickImage() async => image;

  @override
  Future<List<PickedFile>> pickImages({required int limit}) async {
    lastLimit = limit;
    return images;
  }

  @override
  Future<List<PickedFile>> pickPdfs({required int limit}) async {
    lastLimit = limit;
    return pdfs;
  }
}

const ownerUser = AuthUser(
  id: 'u-owner',
  email: 'owner@example.com',
  role: UserRole.owner,
);

AuthUser staffUser({
  StaffPermissions permissions = const StaffPermissions(),
  String? cardId = 'c1',
}) => AuthUser(
  id: 'u-staff',
  email: 'staff@example.com',
  role: UserRole.staff,
  cardId: cardId,
  permissions: permissions,
);

Json cardJson({
  String id = 'c1',
  String slug = 'asha-rao',
  String status = 'active',
  String visibility = 'inherit',
  bool disabledByBilling = false,
  Map<String, dynamic> extra = const {},
}) => {
  '_id': id,
  'slug': slug,
  'title': 'Asha Rao',
  'designation': 'Sales Lead',
  'company': 'Acme',
  'email': 'asha@example.com',
  'phone': '+91 98765 43210',
  'status': status,
  'visibility': visibility,
  'disabledByBilling': disabledByBilling,
  'template': 'corporate',
  'brandColor': '#1F4FD8',
  'bloodGroup': 'O+',
  'fatherName': 'Ravi Rao',
  'motherName': 'Meena Rao',
  ...extra,
};

/// Paths pushed by screens; each renders a `route:<location>` marker.
const stubPaths = [
  '/o/cards/:id',
  '/o/cards/:id/edit',
  '/o/cards/:id/share',
  '/o/cards/:id/analytics',
  '/o/billing/seats',
  '/o/staff/new',
  '/o/visibility',
  '/card/:slug',
  '/directory/:orgSlug',
  '/s/card/edit',
  '/s/card/share',
];

Future<GoRouter> pumpScreen(
  WidgetTester tester,
  Widget screen, {
  required FakeApi api,
  AuthUser? user = ownerUser,
  FakeShareService? share,
  FakeMediaPicker? picker,
  List<Override> extra = const [],
  bool pushed = false,
  Size size = const Size(800, 2400),
  double textScale = 1,
}) async {
  tester.view
    ..physicalSize = size
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final router = GoRouter(
    initialLocation: pushed ? '/home' : '/screen',
    routes: [
      GoRoute(
        path: '/home',
        builder: (context, _) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () => context.push('/screen'),
              child: const Text('open'),
            ),
          ),
        ),
      ),
      GoRoute(path: '/screen', builder: (_, _) => screen),
      for (final p in stubPaths)
        GoRoute(
          path: p,
          builder: (_, s) => Scaffold(body: Text('route:${s.uri}')),
        ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      retry: (_, _) => null,
      overrides: [
        cardsRepositoryProvider.overrideWithValue(CardsRepository(api.client)),
        currentUserProvider.overrideWithValue(user),
        currentConfigProvider.overrideWithValue(AppConfig.defaults),
        shareServiceProvider.overrideWithValue(share ?? FakeShareService()),
        mediaPickerProvider.overrideWithValue(picker ?? FakeMediaPicker()),
        ...extra,
      ],
      child: MaterialApp.router(
        theme: AppTheme.light(),
        routerConfig: router,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
      ),
    ),
  );
  if (pushed) {
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
  }
  await tester.pumpAndSettle();
  return router;
}

final tinyVcard = Uint8List.fromList(
  utf8.encode('BEGIN:VCARD\r\nVERSION:3.0\r\nFN:Asha Rao\r\nEND:VCARD\r\n'),
);
