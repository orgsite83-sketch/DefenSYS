# Directives (Layer 1)

Markdown SOPs: goals, inputs, which scripts in `execution/` to run, outputs, and edge cases.

See [docs/AGENTS.md](../docs/AGENTS.md). Add new directive `.md` files here when agreed with the project owner.

flutter run --dart-define=DEFENSYS_API_HOST=192.168.1.5 
flutter run -d web-server --web-hostname 0.0.0.0 --web-port 57583 --dart-define=DEFENSYS_API_HOST=192.168.1.5
python manage.py runserver 0.0.0.0:8000