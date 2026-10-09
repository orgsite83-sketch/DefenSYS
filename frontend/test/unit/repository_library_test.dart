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
