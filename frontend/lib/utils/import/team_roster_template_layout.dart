/// Coordinates shared by the generated workbook and its on-screen blueprint.
class TeamRosterTemplateLayout {
  const TeamRosterTemplateLayout({this.instructorWorkspace = false});

  final bool instructorWorkspace;
  bool contains(int column) =>
      !instructorWorkspace || (column != 4 && column != 10);
  int column(int original) =>
      original -
      (instructorWorkspace && original > 4 ? 1 : 0) -
      (instructorWorkspace && original > 10 ? 1 : 0);

  List<double> get previewWidths => [
    for (final entry in const [
      24.0,
      114.0,
      160.0,
      70.0,
      120.0,
      125.0,
      24.0,
      114.0,
      146.0,
      70.0,
      120.0,
      125.0,
    ].indexed)
      if (contains(entry.$1)) entry.$2,
  ];
}
