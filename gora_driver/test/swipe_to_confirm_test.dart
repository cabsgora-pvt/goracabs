import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gora_driver/features/ride/widgets/swipe_to_confirm.dart';

// The swipe control guards ride state changes a driver must not trigger by
// accident. These pin down the behaviour that makes it safe: partial swipes do
// not commit, a full swipe commits exactly once, a disabled control is inert,
// and screen-reader users are not locked out.

Widget host(Widget child, {double width = 360}) => MaterialApp(
  home: Scaffold(
    body: Center(child: SizedBox(width: width, child: child)),
  ),
);

/// Drags the knob a [fraction] of the track to the right, then releases slowly
/// so the flick shortcut does not apply.
Future<void> swipe(WidgetTester tester, double fraction, {double trackWidth = 360}) async {
  final knob = find.byIcon(Icons.arrow_forward_rounded);
  final start = tester.getCenter(knob);
  // Track travel = width - knob(50) - 2*inset(4).
  final travel = (trackWidth - 58) * fraction;
  final gesture = await tester.startGesture(start);
  const steps = 12;
  for (var i = 0; i < steps; i++) {
    await gesture.moveBy(Offset(travel / steps, 0));
    await tester.pump(const Duration(milliseconds: 40));
  }
  await gesture.up();
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  testWidgets('a partial swipe does not confirm', (tester) async {
    var calls = 0;
    await tester.pumpWidget(host(SwipeToConfirm(
      label: 'Swipe to end ride',
      onConfirm: () async => calls++,
    )));
    await swipe(tester, 0.5);
    expect(calls, 0, reason: 'Half a swipe is exactly the accident this prevents');
  });

  testWidgets('a full swipe confirms exactly once', (tester) async {
    var calls = 0;
    await tester.pumpWidget(host(SwipeToConfirm(
      label: 'Swipe to end ride',
      onConfirm: () async => calls++,
    )));
    await swipe(tester, 1.0);
    expect(calls, 1);
  });

  testWidgets('it cannot be re-triggered while the action is in flight', (tester) async {
    var calls = 0;
    final pending = Completer<void>();
    await tester.pumpWidget(host(SwipeToConfirm(
      label: 'Swipe to end ride',
      onConfirm: () { calls++; return pending.future; },
    )));
    final handle = tester.ensureSemantics();
    await swipe(tester, 1.0);
    // While busy the knob shows progress and has no arrow to grab, so a second
    // attempt must go through semantics — which is also refused while busy.
    // Looked up by label: the button's OWN node, not whatever node encloses it.
    final node = tester.getSemantics(find.bySemanticsLabel('Swipe to end ride'));
    expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isFalse,
        reason: 'A second trigger while the first is in flight must be refused');
    expect(calls, 1);
    pending.complete();
    await tester.pump(const Duration(milliseconds: 400));
    handle.dispose();
  });

  testWidgets('a disabled control does nothing', (tester) async {
    var calls = 0;
    await tester.pumpWidget(host(SwipeToConfirm(
      label: 'Swipe to end ride',
      enabled: false,
      onConfirm: () async => calls++,
    )));
    await swipe(tester, 1.0);
    expect(calls, 0);
  });

  testWidgets('screen readers can activate it without dragging', (tester) async {
    final handle = tester.ensureSemantics();
    var calls = 0;
    await tester.pumpWidget(host(SwipeToConfirm(
      label: 'Swipe to end ride',
      onConfirm: () async => calls++,
    )));
    final node = tester.getSemantics(find.bySemanticsLabel('Swipe to end ride'));
    final data = node.getSemanticsData();
    expect(data.hasAction(SemanticsAction.tap), isTrue,
        reason: 'TalkBack cannot drag; without a tap action it is unusable');
    expect(data.label, 'Swipe to end ride');

    tester.binding.pipelineOwner.semanticsOwner!
        .performAction(node.id, SemanticsAction.tap);
    // One frame starts the knob's ticker, the next advances it past its 260ms
    // duration — only then does the commit reach onConfirm. A single pump
    // starts the animation but never lets it finish.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(calls, 1);
    handle.dispose();
  });

  testWidgets('long label does not overflow on a 320pt screen', (tester) async {
    await tester.pumpWidget(host(
      SwipeToConfirm(
        label: 'Swipe to collect ₹1,24,999 from Chandrashekhar Balasubramanian',
        onConfirm: () async {},
      ),
      width: 320 - 32,
    ));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
