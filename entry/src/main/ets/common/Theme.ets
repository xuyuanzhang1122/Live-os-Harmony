export class Theme {
  static readonly BRAND_COLOR: string = '#1FDBC7';
  static readonly BRAND_FOREGROUND: string = '#063D38';
  static readonly BRAND_TINT: string = '#1A1FDBC7';
  static readonly BRAND_BORDER: string = '#401FDBC7';
  static readonly DANGER_COLOR: string = '#E84040';
  static readonly DANGER_TINT: string = '#16E84040';
  static readonly DANGER_BORDER: string = '#40E84040';
  static readonly CORNER_RADIUS_SMALL: number = 8;
  static readonly CORNER_RADIUS_MEDIUM: number = 14;
  static readonly CORNER_RADIUS_LARGE: number = 18;
  static readonly SPACING_SMALL: number = 8;
  static readonly SPACING_MEDIUM: number = 16;
  static readonly SPACING_LARGE: number = 24;
}

export enum AppButtonRole {
  Primary,
  Secondary,
  Destructive,
  Plain
}

export class AppButtonVisualStyle {
  readonly foregroundColor: string;
  readonly backgroundColor: string;
  readonly borderColor: string;
  readonly opacity: number;

  constructor(foregroundColor: string, backgroundColor: string, borderColor: string, opacity: number) {
    this.foregroundColor = foregroundColor;
    this.backgroundColor = backgroundColor;
    this.borderColor = borderColor;
    this.opacity = opacity;
  }
}

export function appButtonVisualStyle(role: AppButtonRole, enabled: boolean): AppButtonVisualStyle {
  const opacity: number = enabled ? 1 : 0.42;
  switch (role) {
    case AppButtonRole.Primary:
      return new AppButtonVisualStyle(Theme.BRAND_FOREGROUND, Theme.BRAND_COLOR, Theme.BRAND_COLOR, opacity);
    case AppButtonRole.Secondary:
      return new AppButtonVisualStyle('#0D8D81', Theme.BRAND_TINT, Theme.BRAND_BORDER, opacity);
    case AppButtonRole.Destructive:
      return new AppButtonVisualStyle(Theme.DANGER_COLOR, Theme.DANGER_TINT, Theme.DANGER_BORDER, opacity);
    default:
      return new AppButtonVisualStyle('#0D8D81', '#00000000', '#00000000', opacity);
  }
}

export enum ConnectionVisualState {
  Loading,
  Failure,
  LAN,
  Public,
  Idle
}

export function settingsConnectionVisualState(testing: boolean, failed: boolean,
  isOnLAN: boolean, hasServerInfo: boolean): ConnectionVisualState {
  if (testing) {
    return ConnectionVisualState.Loading;
  }
  if (failed) {
    return ConnectionVisualState.Failure;
  }
  if (!hasServerInfo) {
    return ConnectionVisualState.Idle;
  }
  return isOnLAN ? ConnectionVisualState.LAN : ConnectionVisualState.Public;
}
