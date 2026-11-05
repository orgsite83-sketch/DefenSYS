import 'package:flutter_test/flutter_test.dart';
import 'package:defensys/models/repository_library.dart';

VaultEntry entry(
  String id, {
  String project = '',
  String teamId = '',
  String kind = 'concept',
  String preview = '',
  String overviewLabel = '',
}) => VaultEntry(
  id: id,
  fileName: 'Approved_Concept_Paper.pdf',
  teamName: 'Team MedWards',
  uploadedBy: 'Faculty',
  academicYear: '2026–2027',
  status: 'Approved',
  timestamp: '',
  yearLevel: '4th Year',
  stage: 'Concept Proposal',
  type: 'capstone',
  projectTitle: 'Hospital Management System — Wards Module',
  projectKey: project,
  teamId: teamId,
  documentKind: kind,
  overviewText: preview,
  overviewLabel: overviewLabel,
);

void main() {
  test(
    'deliverables retain real keys across formats and separate repeated labels',
    () {
      VaultEntry material(String id, String key, String stage, String name) =>
          VaultEntry.fromJson({
            'id': id,
            'project_key': 'one',
            'file_name': name,
            'stage': stage,
            'deliverable_key': key,
            'deliverable_group_label': 'Prototype package',
          });
      final groups = LibraryDeliverable.group([
        material('pdf', 'proposal:D1', 'Proposal', 'design.pdf'),
        material('video', 'proposal:D1', 'Proposal', 'demo.mp4'),
        material('final', 'final:D1', 'Final', 'prototype.zip'),
        VaultEntry.fromJson({
          'id': 'legacy',
          'file_name': 'manuscript.pdf',
          'document_kind': 'final',
        }),
      ]);
      expect(groups, hasLength(3));
      expect(
        groups.firstWhere((item) => item.key == 'proposal:D1').entries,
        hasLength(2),
      );
      expect(
        groups
            .firstWhere((item) => item.key == 'final:D1')
            .displayLabel(groups),
        'Prototype package · Final',
      );
      expect(groups.last.label, 'Other materials');
    },
  );

  test(
    'catalog summary preserves all available deliverables without loading files',
    () {
      final summary = VaultEntry.fromJson({
        'id': 'one',
        'catalog_summary': true,
        'project_output_count': 17,
        'available_deliverables': [
          {'key': 'a', 'label': 'Custom demonstration'},
          {'key': 'b', 'label': 'Research package'},
        ],
      }).copyWith(userRating: 4);
      expect(summary.projectOutputCount, 17);
      expect(summary.hasDeliverable('b'), isTrue);
      expect(
        LibraryDeliverable.group([summary]).map((item) => item.label),
        containsAll(['Custom demonstration', 'Research package']),
      );
    },
  );
  test(
    'project title remains the identity while document stage is separate',
    () {
      final paper = entry('one');
      expect(paper.displayTitle, 'Hospital Management System — Wards Module');
      expect(paper.outputLabel, 'Concept Paper');
      expect(LibraryBrowse.concept.matches(paper), isTrue);
      expect(
        LibraryBrowse.concept.matches(entry('poster', kind: 'poster')),
        isFalse,
      );
    },
  );
  test('unlinked files with matching team names remain separate', () {
    expect(LibraryProject.group([entry('one'), entry('two')]), hasLength(2));
  });
  test('grouping respects explicit project version identity', () {
    final groups = LibraryProject.group([
      entry('one', project: 'team:1:version:1'),
      entry('two', project: 'team:1:version:2'),
    ]);
    expect(groups, hasLength(2));
  });
  test('overview comes from the latest available public manuscript stage', () {
    final project = LibraryProject('team', [
      entry('one', kind: 'concept', preview: 'Concept background'),
      entry('two', kind: 'final', preview: 'Final abstract'),
    ]);
    expect(project.overview?.previewText, 'Final abstract');
  });
  test('an identified section takes priority over a later cover excerpt', () {
    final project = LibraryProject('team', [
      entry(
        'one',
        preview: 'Existing background',
        overviewLabel: 'Background of the Study',
      ),
      entry(
        'two',
        kind: 'final',
        preview: 'Title page and authors',
        overviewLabel: 'Document excerpt',
      ),
    ]);
    expect(project.overview?.previewText, 'Existing background');
  });
}
