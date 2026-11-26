import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_engine/quds_productivity_automation.dart';
import 'package:quds_office_studio/studio_mail_draft.dart';
import 'package:quds_office_studio/studio_mcp_mail_actions.dart';

void main() {
  test(
    'send review freezes the exact plain-text envelope and content',
    () async {
      final calls = <StudioMailDraft>[];
      final send = studioMcpSendAction(
        sender: 'approved@example.test',
        send: (draft, current) async {
          expect(current(), isTrue);
          calls.add(draft);
          return null;
        },
      );
      final fields = <String, Object?>{
        'to': 'recipient@example.test',
        'title': 'Approved subject',
        'text': 'Approved body',
      };
      expect(
        () => send.plan({...fields, 'cc': 'extra@example.test'}),
        throwsFormatException,
      );
      expect(
        () =>
            send.plan({...fields, 'to': 'one@example.test, two@example.test'}),
        throwsFormatException,
      );
      final planned = send.plan(fields);
      expect(
        planned.destination,
        'From approved@example.test to recipient@example.test',
      );
      expect(planned.subject, 'Approved subject');
      expect(planned.details, 'Approved body');
      fields['to'] = 'other@example.test';
      fields['text'] = 'Different body';
      expect(calls, isEmpty);
      expect(
        await planned.execute(() => false),
        ProductivityApprovalOutcome.rejected,
      );
      expect(calls, isEmpty);
      expect(
        await planned.execute(() => true),
        ProductivityApprovalOutcome.unconfirmed,
      );
      expect(calls.single.to, 'recipient@example.test');
      expect(calls.single.subject, 'Approved subject');
      expect(calls.single.body, 'Approved body');
    },
  );
}
