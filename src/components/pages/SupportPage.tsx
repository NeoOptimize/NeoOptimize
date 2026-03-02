import { ExternalLink, HeartHandshake, LifeBuoy } from 'lucide-react';

type LinkItem = {
  label: string;
  href: string;
};

const supportLinks: LinkItem[] = [
  { label: 'BuyMeCoffee', href: 'https://buymeacoffee.com/nol.eight' },
  { label: 'Saweria', href: 'https://saweria.co/dtechtive' },
  { label: 'Dana', href: 'https://ik.imagekit.io/dtechtive/Dana' }
];

export function SupportPage() {
  return (
    <div className="space-y-4">
      <div className="text-xs flex items-center gap-2" style={{ color: 'var(--text-muted)' }}>
        <span style={{ color: 'var(--ansi-green)', fontWeight: 700 }}>$</span>
        <span>neooptimize support --help --contact</span>
      </div>

      <div className="border p-4 space-y-3" style={{ borderColor: 'var(--border-color)', backgroundColor: 'var(--bg-secondary)' }}>
        <div className="text-xs font-bold flex items-center gap-2" style={{ color: 'var(--ansi-cyan)' }}>
          <LifeBuoy size={14} /> Contact Developer
        </div>
        <div className="space-y-1 text-xs">
          <div style={{ color: 'var(--text-primary)' }}>Nama: Sigit profesional IT</div>
          <div style={{ color: 'var(--text-primary)' }}>WhatsApp: 087889911030</div>
          <div style={{ color: 'var(--text-primary)' }}>Email: neooptimizeofficial@gmail.com</div>
        </div>
      </div>

      <div className="border p-4 space-y-3" style={{ borderColor: 'var(--border-color)', backgroundColor: 'var(--bg-secondary)' }}>
        <div className="text-xs font-bold flex items-center gap-2" style={{ color: 'var(--ansi-green)' }}>
          <HeartHandshake size={14} /> Support Us
        </div>
        <div className="grid grid-cols-1 md:grid-cols-3 gap-2">
          {supportLinks.map((item) => (
            <a
              key={item.href}
              href={item.href}
              target="_blank"
              rel="noreferrer"
              className="px-3 py-2 text-xs border font-bold inline-flex items-center justify-between"
              style={{ borderColor: 'var(--ansi-green)', color: 'var(--ansi-green)' }}
            >
              {item.label}
              <ExternalLink size={12} />
            </a>
          ))}
        </div>
        <div className="text-xs" style={{ color: 'var(--text-muted)' }}>
          Dukungan dipakai untuk maintenance fitur Cleaner, Optimizer, Security, dan update release.
        </div>
      </div>
    </div>
  );
}
