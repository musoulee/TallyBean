class AppConfig {
  const AppConfig({this.title = 'Tally Bean', this.useDemoData = false});

  final String title;
  final bool useDemoData;
}

const defaultAppConfig = AppConfig();
