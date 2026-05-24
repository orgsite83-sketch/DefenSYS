import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

files = [
    'lib/services/grade_center_provider.dart',
    'lib/services/pit_lead_cohort_provider.dart',
    'lib/services/defense_scheduler_provider.dart',
    'lib/services/defense_stages_provider.dart',
    'lib/services/rubric_engine_provider.dart',
    'lib/services/repository_audit_provider.dart',
    'lib/services/weekly_progress_provider.dart',
    'lib/services/user_management_provider.dart',
    'lib/services/capstone_deliverables_provider.dart',
    'lib/services/team_detail_provider.dart',
    'lib/services/pit_repository_assistant_provider.dart',
    'lib/services/student_teams_provider.dart',
    'lib/services/academic_period_provider.dart',
    'lib/services/curriculum_analytics_provider.dart',
    'lib/services/student_academic_records_provider.dart',
    'lib/services/digital_vault_provider.dart',
    'lib/services/defense_board_provider.dart',
]

headers_block = re.compile(
    r"  Future<Map<String, String>> _headers\(\) async \{.*?^  \}\r?\n",
    re.MULTILINE | re.DOTALL,
)

for rel in files:
    p = ROOT / rel
    if not p.exists():
        print('skip', rel)
        continue
    text = p.read_text(encoding='utf-8')
    if 'jwt_token' not in text:
        print('no jwt', rel)
        continue
    orig = text
    text = text.replace("import 'package:shared_preferences/shared_preferences.dart';\n", '')
    if "authenticated_client.dart" not in text:
        if "import 'api_http.dart';\n" in text:
            text = text.replace(
                "import 'api_http.dart';\n",
                "import 'api_http.dart';\nimport 'authenticated_client.dart';\nimport 'session_expired.dart';\n",
            )
        elif "import '../config/api_config.dart';\n" in text:
            text = text.replace(
                "import '../config/api_config.dart';\n",
                "import '../config/api_config.dart';\nimport 'authenticated_client.dart';\nimport 'session_expired.dart';\n",
            )
    text = headers_block.sub(
        '  AuthenticatedHttpClient get _client => ref.read(authenticatedHttpClientProvider);\n\n',
        text,
    )
    text = text.replace('headers: await _headers(),', '')
    text = re.sub(r'await http\.(get|post|put|patch|delete)\(', r'await _client.\1(', text)
    text = re.sub(r'await apiHttpClient\.(get|post|put|patch|delete)\(', r'await _client.\1(', text)
    if text != orig:
        p.write_text(text, encoding='utf-8')
        print('updated', rel)
    else:
        print('unchanged', rel)
