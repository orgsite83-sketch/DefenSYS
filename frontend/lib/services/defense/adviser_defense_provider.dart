import 'team_defense_provider.dart';

// Preserve the adviser API while sharing its permission-scoped schedule feed.
typedef AdviserDefenseState = TeamDefenseState;
typedef AdviserDefenseNotifier = TeamDefenseNotifier;
final adviserDefenseProvider = teamDefenseProvider;
