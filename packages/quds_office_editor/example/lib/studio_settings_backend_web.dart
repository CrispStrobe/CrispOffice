import 'studio_settings.dart';
import 'studio_web_data_store.dart';

StudioSettingsBackend createDefaultStudioSettingsBackend(String name) =>
    WebDataStoreStudioSettingsBackend(
      createDefaultStudioWebDataStore(),
      key: 'settings/$name.json',
    );
