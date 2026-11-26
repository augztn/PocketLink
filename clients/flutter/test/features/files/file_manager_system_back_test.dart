import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart' hide MaterialApp;
import 'package:material_ui/material_ui.dart'
    show MaterialApp, MaterialUiCompatibilityBridge;
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:pocketlink_client/core/network/server_api.dart';
import 'package:pocketlink_client/features/files/file_browser_state_store.dart';
import 'package:pocketlink_client/features/files/file_manager_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ServerApi api;
  late _DirectoryAdapter adapter;
  late FileBrowserStateStore browserState;

  setUp(() {
    adapter = _DirectoryAdapter();
    browserState = FileBrowserStateStore();
    api = ServerApi(
      baseUrl: 'http://pocketlink.test:8000',
      username: 'test',
      password: 'test',
      httpClientAdapter: adapter,
    );
  });

  tearDown(() => api.close(force: true));

  testWidgets('registered system Back handler steps up one folder at a time',
      (tester) async {
    VoidCallback? backHandler;

    await tester.pumpWidget(
      ChangeNotifierProvider<FileBrowserStateStore>.value(
        value: browserState,
        child: MaterialApp(
          builder: (context, child) => MaterialUiCompatibilityBridge(
            child: child ?? const SizedBox.shrink(),
          ),
          home: PopScope(
          canPop: false,
          onPopInvokedWithResult: (didPop, result) {
            if (!didPop) backHandler?.call();
          },
          child: FileManagerScreen(
            api: api,
            // Exercise the directory browser rather than the Files home
            // landing page; folder entries remain visible in every category.
            initialCategory: 'Documents',
            isActive: true,
            onBackAtRoot: () {},
            onBackHandlerChanged: (handler) {
              backHandler = handler;
            },
          ),
        ),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(adapter.directoryRequests, contains(''));
    expect(backHandler, isNull);

    await tester.tap(find.text('DCIM').first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(adapter.directoryRequests, contains('DCIM'));
    expect(backHandler, isNotNull);

    await tester.tap(find.text('Screenshots').first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(adapter.directoryRequests, contains('DCIM/Screenshots'));
    expect(backHandler, isNotNull);

    // Send a platform Back event through the same PopScope dispatch used
    // by HomeScreen, rather than invoking the folder callback directly.
    await tester.binding.handlePopRoute();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(browserState.stateFor(api.baseUrl).path, 'DCIM');
    expect(backHandler, isNotNull);

    await tester.binding.handlePopRoute();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(browserState.stateFor(api.baseUrl).path, isEmpty);
    expect(backHandler, isNull);
  });
}

class _DirectoryAdapter implements HttpClientAdapter {
  final List<String> directoryRequests = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (options.path.endsWith('/api/storage/volumes')) {
      return _json({'items': []});
    }

    if (options.path.endsWith('/api/files/')) {
      final path = options.queryParameters['path'] as String? ?? '';
      directoryRequests.add(path);
      final items = switch (path) {
        '' => [_folder('DCIM')],
        'DCIM' => [_folder('Screenshots')],
        _ => <Map<String, Object>>[],
      };
      return _json({'path': path, 'items': items});
    }

    return _json({});
  }

  ResponseBody _json(Map<String, Object?> value) => ResponseBody.fromString(
        jsonEncode(value),
        200,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      );

  Map<String, Object> _folder(String name) => {
        'name': name,
        'type': 'directory',
        'size': 0,
        'modified': '',
      };

  @override
  void close({bool force = false}) {}
}
