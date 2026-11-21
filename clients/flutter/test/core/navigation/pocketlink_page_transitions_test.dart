import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pocketlink_client/core/navigation/pocketlink_page_transitions.dart';

void main() {
  group('PocketLinkPageTransitionsBuilder', () {
    const builder = PocketLinkPageTransitionsBuilder();
    const child = SizedBox(key: ValueKey<String>('route-content'));

    testWidgets('uses the subtle transition when motion is enabled', (
      tester,
    ) async {
      final route = MaterialPageRoute<void>(
        builder: (_) => child,
      );
      Widget? transition;

      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(disableAnimations: false),
          child: Builder(
            builder: (context) {
              transition = builder.buildTransitions<void>(
                route,
                context,
                const AlwaysStoppedAnimation<double>(0.5),
                const AlwaysStoppedAnimation<double>(0),
                child,
              );
              return transition!;
            },
          ),
        ),
      );

      expect(find.byType(FadeTransition), findsOneWidget);
      expect(find.byType(SlideTransition), findsOneWidget);
      expect(find.byType(ScaleTransition), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('route-content')), findsOneWidget);
    });

    testWidgets('respects the system reduced-motion setting', (tester) async {
      final route = MaterialPageRoute<void>(
        builder: (_) => child,
      );
      Widget? transition;

      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: Builder(
            builder: (context) {
              transition = builder.buildTransitions<void>(
                route,
                context,
                const AlwaysStoppedAnimation<double>(0.5),
                const AlwaysStoppedAnimation<double>(0),
                child,
              );
              return transition!;
            },
          ),
        ),
      );

      expect(identical(transition, child), isTrue);
      expect(find.byType(FadeTransition), findsNothing);
      expect(find.byType(SlideTransition), findsNothing);
      expect(find.byType(ScaleTransition), findsNothing);
    });
  });
}
