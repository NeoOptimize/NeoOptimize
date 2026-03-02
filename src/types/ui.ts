export type UIMode = 'simple' | 'advanced';

export type SectionId =
  | 'dashboard'
  | 'cleaner'
  | 'optimizer'
  | 'system-tools'
  | 'security'
  | 'settings'
  | 'support';

export type NavItem = {
  id: SectionId;
  label: string;
  desc: string;
  simple: boolean;
};

export const NAV_ITEMS: NavItem[] = [
  { id: 'dashboard', label: 'dashboard', desc: 'Core Hub', simple: true },
  { id: 'cleaner', label: 'cleaner', desc: 'Adaptive Cleaner', simple: true },
  { id: 'optimizer', label: 'optimizer', desc: 'Smart Optimizer', simple: true },
  { id: 'system-tools', label: 'system_tools', desc: 'Repair + Backup', simple: false },
  { id: 'security', label: 'security', desc: 'Unified Security', simple: false },
  { id: 'settings', label: 'settings', desc: 'Mode + Theme + Scheduler', simple: true },
  { id: 'support', label: 'support', desc: 'Help + Contact', simple: true }
];

export function visibleNavItems(mode: UIMode): NavItem[] {
  if (mode === 'advanced') return NAV_ITEMS;
  return NAV_ITEMS.filter((item) => item.simple);
}
