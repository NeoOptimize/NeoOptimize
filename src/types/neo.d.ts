type NeoUpdaterSettingsInput = {
  autoCheck: boolean;
  autoDownload: boolean;
  checkIntervalMinutes: number;
};

type NeoUpdaterEventHandler = (payload: unknown) => void;

interface NeoBridge {
  version?: () => string;
  getUpdaterState?: () => Promise<unknown>;
  getUpdaterSettings?: () => Promise<unknown>;
  setUpdaterSettings?: (settings: NeoUpdaterSettingsInput) => Promise<unknown>;
  checkForUpdates?: () => Promise<unknown>;
  downloadUpdate?: () => Promise<unknown>;
  installUpdateNow?: () => Promise<unknown>;
  openReleasesPage?: () => Promise<unknown>;
  onUpdaterStatus?: (cb: NeoUpdaterEventHandler) => (() => void) | void;
}

declare global {
  interface Window {
    neo?: NeoBridge;
  }
}

export {};

