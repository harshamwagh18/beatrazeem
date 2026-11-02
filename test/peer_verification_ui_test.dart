import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:beatrazeem/core/transport.dart';
import 'package:beatrazeem/ui/peer_verification_dialog.dart';

void main() {
  Future<void> open(WidgetTester tester, ValueChanged<bool?> result) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async => result(
                await showDialog<bool>(
                  context: context,
                  builder: (_) => const PeerVerificationDialog(
                    verification: PeerVerification(
                      verificationCode: '123456',
                      isHost: true,
                    ),
                  ),
                ),
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
  }

  testWidgets('device approval requires an explicit code comparison', (
    tester,
  ) async {
    bool? result;
    await open(tester, (value) => result = value);
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Approve device'),
          )
          .onPressed,
      isNull,
    );
    await tester.tap(find.byType(CheckboxListTile));
    await tester.pump();
    await tester.tap(find.text('Approve device'));
    await tester.pumpAndSettle();
    expect(result, isTrue);
  });
  testWidgets('unanswered verification closes with rejection', (tester) async {
    bool? result;
    await open(tester, (value) => result = value);
    await tester.pump(const Duration(seconds: 76));
    await tester.pumpAndSettle();
    expect(result, isFalse);
    expect(find.text('Compare security codes'), findsNothing);
  });
}
