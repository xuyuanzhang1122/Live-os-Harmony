@ObservedV2
export class AppConfig {
  private static readonly INSTANCE: AppConfig = new AppConfig();

  @Trace activeURL: string = '';

  private constructor() {
  }

  static getInstance(): AppConfig {
    return AppConfig.INSTANCE;
  }
}
