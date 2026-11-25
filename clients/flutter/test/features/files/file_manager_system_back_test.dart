import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:pocketlink_client/core/network/server_api.dart';
import 'package:pocketlink_client/features/files/file_browser_state_store.dart';
import 'package:pocketlink_client/features/files/file_manager_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ServerApi api;
  late _DirectoryAdapter adapter;

  setUp(() {
    adapter = _DirectoryAdapter();
    api = ServerApi(
      baseUrl: 'http://pocketlink.test:8000',
      username: 'test',
      password: 'test',
      httpClientAdapter: adapter,
    );
  });

  tearDown(() => api.close(force: true));

  testWidgets('system Back steps up one folder at a time at multiple depths',
      (tester) async {
    VoidCallback? backHandler;

    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => FileBrowserStateStore(),
        child: MaterialApp(
          home: StatefulBuilder(
            builder: (context, setState) => PopScope(
              canPop: false,
              onPopInvokedWithResult: (didPop, result) {
                if (!didPop) backHandler?.call();
              },
              child: FileManagerScreen(
                api: api,
                isActive: true,
                onBackAtRoot: () {},
                onBackHandlerChanged: (handler) {
                  backHandler = handler;
                },
              ),
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();
    expect(adapter.directoryRequests, contains(''));

    await tester.tap(find.text('DCIM').first);
    await tester.pumpAndSettle();
    expect(adapter.directoryRequests, contains('DCIM'));

    await tester.tap(find.text('Screenshots').first);
    await tester.pumpAndSettle();
    expect(adapter.directoryRequests, contains('DCIM/Screenshots'));

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(adapter.directoryRequests.last, 'DCIM');

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(adapter.directoryRequests.last, isEmpty);
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
