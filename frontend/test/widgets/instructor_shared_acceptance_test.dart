import 'dart:convert';

import 'package:defensys/services/api_http.dart';
import 'package:defensys/widgets/repository/shared_deliverables_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../helpers/auth_test_overrides.dart';
import '../helpers/pump_app.dart';

Map<String, dynamic> _group({bool accepted = false}) => {
  'team_id': 93,
  'section': 'BSIT-1B',
  'stage_label': 'IT Concept Defense',
  'scope': 'pit',
  'identity': 'current-shared-project',
  'review_token': 'current-review-token',
  'project_manager_name': 'Lance San Pedro',
  'pre_complete': accepted,
  'concept_selection_enabled': false,
  'systems': [{'key': 'assigned', 'title': 'UniConnect Shared System'}],
  'requirements': [{
    'deliverable_id': 'SHARED_D1', 'label': 'Concept Paper', 'required': true,
    'deliverable_type': 'pre', 'status': accepted ? 'accepted' : 'pending',
    'file_policy': {'mode': 'single'},
    'documents': [{
      'key': 'primary', 'label': 'Concept Paper', 'required': true,
      'file_format': 'pdf', 'can_review': true, 'can_upload': false,
      'file': {
        'id': 42, 'legacy': false, 'file_name': 'UniConnect_Concept_Paper.pdf',
        'revision': 1, 'status': accepted ? 'accepted' : 'pending',
        'file_url': '/api/protected/shared-paper/',
      },
    }],
  }],
};

void main() {
  tearDown(resetApiHttpClientForTesting);
  for (final width in [390.0, 1280.0]) {
    for (final success in [true, false]) {
      testWidgets('instructor shared acceptance $success at $width', (tester) async {
        tester.view.physicalSize = Size(width, 1000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        var posts = 0;
        Map<String, dynamic>? changed;
        setApiHttpClientForTesting(MockClient((request) async {
          posts++;
          expect(request.method, 'POST');
          expect(request.url.path, endsWith('/shared-deliverables/'));
          final body = jsonDecode(request.body) as Map;
          expect(body['team_id'], 93);
          expect(body['action'], 'review');
          expect(body['status'], 'accepted');
          expect(body['file_id'], 42);
          expect(body['review_token'], 'current-review-token');
          return success
              ? http.Response(jsonEncode({'shared_deliverables': _group(accepted: true)}), 200)
              : http.Response('{"detail":"The shared project or documents changed. Refresh and review the current checklist."}', 400);
        }));
        await pumpDefensysWidget(tester, SingleChildScrollView(
          child: SharedDeliverablesPanel(group: _group(), normalFlow: true,
            onChanged: (value) => changed = value),
        ), overrides: authTestOverrides());
        expect(find.text('Accept file'), findsOneWidget);
        await tester.ensureVisible(find.text('Accept file'));
        await tester.tap(find.text('Accept file'));
        await tester.pumpAndSettle();
        expect(posts, 1);
        if (success) {
          expect(changed?['pre_complete'], isTrue);
          expect(find.text('Accepted'), findsOneWidget);
          expect(find.text('Accept file'), findsNothing);
        } else {
          expect(changed, isNull);
          expect(find.textContaining('The shared project or documents changed'), findsOneWidget);
          expect(find.text('Accept file'), findsOneWidget);
          expect(find.text('Pending review'), findsOneWidget);
        }
        expect(tester.takeException(), isNull);
      });
    }
  }
}
