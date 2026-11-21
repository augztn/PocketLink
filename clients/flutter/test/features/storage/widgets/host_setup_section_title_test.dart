import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'package:pocketlink_client/features/storage/widgets/host_setup_section_title.dart';

void main() {
  testWidgets('shows the supplied title and subtitle', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: HostSetupSectionTitle(
            title: 'USB / External Storage',
            subtitle: 'Connect and manage removable drives.',
          ),
        ),
      ),
    );

    expect(find.text('USB / External Storage'), findsOneWidget);
    expect(find.text('Connect and manage removable drives.'), findsOneWidget);
  });
}
