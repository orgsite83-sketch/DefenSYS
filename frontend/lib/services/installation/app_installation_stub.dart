import 'app_installation.dart';

AppInstallation createAppInstallation() => _NativeInstallation();

class _NativeInstallation extends AppInstallation {
  @override
  InstallationState get state => const InstallationState();
  @override
  Future<String> install() async => 'unavailable';
}
