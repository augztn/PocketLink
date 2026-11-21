import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pocketlink_client/features/media/widgets/video_transport_button.dart';

void main() {
  testWidgets('renders the supplied transport control and invokes callback', (tester) async {
    var pressed = false;

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: VideoTransportButton(
          tooltip: 'Forward 10 seconds',
          icon: Icons.forward_10_rounded,
          onPressed: () => pressed = true,
        ),
      ),
    ));

    expect(find.byTooltip('Forward 10 seconds'), findsOneWidget);
    expect(find.byIcon(Icons.forward_10_rounded), findsOneWidget);

    await tester.tap(find.byTooltip('Forward 10 seconds'));
    expect(pressed, isTrue);
  });

  testWidgets('keeps unavailable transport controls disabled', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: VideoTransportButton(
          tooltip: 'Previous video',
          icon: Icons.skip_previous_rounded,
          onPressed: null,
        ),
      ),
    ));

    final button = tester.widget<IconButton>(find.byType(IconButton));
    expect(button.onPressed, isNull);
  });
}
