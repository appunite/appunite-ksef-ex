// Shared primitives — buttons, badges, inputs, cards.
// Expose to window at end for cross-file usage.

const Icon = ({ name, size = 16, className = "" }) => {
  const icons = {
    "document-text": <path d="M9 12h6m-6 4h6m-6-8h6M6 4h12a2 2 0 012 2v14a2 2 0 01-2 2H6a2 2 0 01-2-2V6a2 2 0 012-2z" />,
    "banknotes": <><rect x="3" y="6" width="18" height="12" rx="2" /><circle cx="12" cy="12" r="2" /></>,
    "home": <path d="M3 12l9-9 9 9M5 10v10h14V10" />,
    "building": <path d="M4 21V5a2 2 0 012-2h12a2 2 0 012 2v16M9 8h6M9 12h6M9 16h6" />,
    "cog": <><circle cx="12" cy="12" r="3" /><path d="M19 12a7 7 0 01-14 0 7 7 0 0114 0zM12 2v2M12 20v2M2 12h2M20 12h2" /></>,
    "arrow-path": <path d="M4 12a8 8 0 0115-3m1 3a8 8 0 01-15 3M20 4v5h-5M4 20v-5h5" />,
    "search": <><circle cx="11" cy="11" r="6" /><path d="M20 20l-4-4" /></>,
    "calendar": <><rect x="3" y="5" width="18" height="16" rx="2" /><path d="M3 9h18M8 3v4M16 3v4" /></>,
    "chevron-down": <path d="M6 9l6 6 6-6" />,
    "chevron-right": <path d="M9 6l6 6-6 6" />,
    "x-mark": <path d="M6 6l12 12M18 6L6 18" />,
    "info": <><circle cx="12" cy="12" r="9" /><path d="M12 8v4M12 16h.01" /></>,
    "warning": <path d="M12 3l10 18H2L12 3zM12 10v4M12 18h.01" />,
    "error": <><circle cx="12" cy="12" r="9" /><path d="M15 9l-6 6M9 9l6 6" /></>,
    "uturn": <path d="M9 14l-5-5 5-5M4 9h11a5 5 0 015 5v6" />,
    "duplicate": <><rect x="5" y="3" width="12" height="16" rx="2" /><rect x="8" y="6" width="12" height="16" rx="2" /></>,
    "logout": <path d="M10 17l5-5-5-5M15 12H4M12 3h7a2 2 0 012 2v14a2 2 0 01-2 2h-7" />,
    "plus": <path d="M12 5v14M5 12h14" />,
    "check": <path d="M5 12l5 5L20 7" />,
    "bars": <path d="M4 7h16M4 12h16M4 17h16" />,
    "bolt": <path d="M13 3L4 14h7l-1 7 9-11h-7l1-7z" />,
    "sun": <><circle cx="12" cy="12" r="4" /><path d="M12 2v2M12 20v2M4 12H2M22 12h-2M5 5l1.5 1.5M17.5 17.5L19 19M5 19l1.5-1.5M17.5 6.5L19 5" /></>,
    "moon": <path d="M21 12.8A9 9 0 1111.2 3a7 7 0 009.8 9.8z" />,
    "download": <path d="M12 4v12m-5-5l5 5 5-5M4 20h16" />,
    "upload": <path d="M12 20V8m-5 5l5-5 5 5M4 4h16" />,
    "lock": <><rect x="5" y="11" width="14" height="10" rx="2" /><path d="M8 11V7a4 4 0 018 0v4" /></>,
    "edit": <path d="M16 3l5 5-11 11H5v-5L16 3zM14 5l5 5" />,
    "trash": <path d="M5 7h14M10 7V4h4v3M6 7l1 13h10l1-13M10 11v6M14 11v6" />,
    "chat": <path d="M21 12a8 8 0 01-11.3 7.3L4 21l1.7-5.7A8 8 0 1121 12z" />,
    "user-plus": <><circle cx="9" cy="8" r="4" /><path d="M2 21a7 7 0 0114 0M18 9v6M15 12h6" /></>,
    "expand": <path d="M4 10V4h6M20 14v6h-6M4 4l7 7M20 20l-7-7" />,
    "zoom-in": <><circle cx="11" cy="11" r="6" /><path d="M20 20l-4-4M11 8v6M8 11h6" /></>,
    "zoom-out": <><circle cx="11" cy="11" r="6" /><path d="M20 20l-4-4M8 11h6" /></>,
    "sync": <path d="M4 12a8 8 0 0115-3m1 3a8 8 0 01-15 3M20 4v5h-5M4 20v-5h5" />,
    "sparkles": <path d="M12 3l2 5 5 2-5 2-2 5-2-5-5-2 5-2z" />,
    "link": <path d="M10 14a4 4 0 015.66 0l3 3a4 4 0 01-5.66 5.66l-1-1M14 10a4 4 0 00-5.66 0l-3 3a4 4 0 005.66 5.66l1-1" />,
  };
  return (
    <svg width={size} height={size} viewBox="0 0 24 24" fill="none" stroke="currentColor"
      strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round" className={className}
      style={{ display: "inline-block", verticalAlign: "-2px", flexShrink: 0 }}>
      {icons[name] || null}
    </svg>
  );
};

const Button = ({ variant = "primary", size = "default", children, onClick, className = "", ...rest }) => {
  const sizes = {
    default: "h-9 px-4 text-sm",
    sm: "h-7 px-2.5 text-xs",
    icon: "h-9 w-9 p-0",
  };
  const variants = {
    primary: "bg-[var(--primary)] text-[var(--primary-foreground)] hover:opacity-90",
    outline: "border border-[var(--input)] bg-[var(--background)] hover:bg-[var(--accent)]",
    ghost: "hover:bg-[var(--accent)] hover:text-[var(--accent-foreground)]",
    destructive: "bg-[var(--destructive)] text-[var(--destructive-foreground)] hover:opacity-90",
    brand: "bg-[var(--brand)] text-[var(--brand-foreground)] hover:opacity-90",
  };
  return (
    <button onClick={onClick}
      className={`inline-flex items-center justify-center gap-2 whitespace-nowrap rounded-md font-medium transition-all focus:outline-none focus-visible:ring-1 focus-visible:ring-[var(--ring)] disabled:opacity-50 disabled:pointer-events-none cursor-pointer ${sizes[size]} ${variants[variant]} ${className}`}
      {...rest}>
      {children}
    </button>
  );
};

const Badge = ({ variant = "default", children, className = "" }) => {
  const v = {
    success: "bg-[color-mix(in_oklch,var(--success)_10%,transparent)] text-[var(--success)] border-[color-mix(in_oklch,var(--success)_20%,transparent)]",
    warning: "bg-[color-mix(in_oklch,var(--warning)_10%,transparent)] border-[color-mix(in_oklch,var(--warning)_30%,transparent)]",
    error: "bg-[color-mix(in_oklch,var(--destructive)_10%,transparent)] text-[var(--destructive)] border-[color-mix(in_oklch,var(--destructive)_20%,transparent)]",
    info: "bg-[color-mix(in_oklch,var(--info)_10%,transparent)] text-[var(--info)] border-[color-mix(in_oklch,var(--info)_20%,transparent)]",
    muted: "bg-[var(--muted)] text-[var(--muted-foreground)] border-[var(--border)]",
    default: "bg-[var(--muted)] text-[var(--muted-foreground)] border-[var(--border)]",
    purple: "bg-[color-mix(in_oklch,var(--purple)_10%,transparent)] text-[var(--purple)] border-[color-mix(in_oklch,var(--purple)_20%,transparent)]",
    brand: "bg-[var(--brand-muted)] text-[var(--brand)] border-[color-mix(in_oklch,var(--brand)_25%,transparent)]",
  };
  const warnColor = variant === "warning" ? { color: "color-mix(in oklch,var(--warning) 60%,var(--foreground))" } : {};
  return (
    <span className={`inline-flex items-center px-2 py-0.5 rounded-md text-xs font-medium border whitespace-nowrap ${v[variant]} ${className}`} style={warnColor}>
      {children}
    </span>
  );
};

const Card = ({ children, className = "", padding = "p-6" }) => (
  <div className={`rounded-xl border border-[var(--border)] bg-[var(--card)] text-[var(--card-foreground)] ${className}`}>
    <div className={padding}>{children}</div>
  </div>
);

const Input = ({ label, error, className = "", ...rest }) => (
  <label className="block space-y-1.5 mb-3">
    {label && <span className="text-sm font-medium block">{label}</span>}
    <input {...rest}
      className={`w-full h-9 rounded-md border ${error ? "border-[var(--destructive)]" : "border-[var(--input)]"} bg-[var(--background)] px-3 text-sm focus:outline-none focus:ring-1 focus:ring-[var(--ring)] text-[var(--foreground)] ${className}`} />
    {error && <span className="text-xs text-[var(--destructive)] flex items-center gap-1"><Icon name="error" size={14} />{error}</span>}
  </label>
);

const Logo = ({ size = 28 }) => (
  <a href="#" onClick={e => e.preventDefault()} className="flex items-center gap-2 no-underline text-[var(--foreground)]">
    <svg width={size} height={size} viewBox="0 0 48 48" fill="none" aria-hidden="true">
      <g fill="currentColor" opacity="0.25">
        <circle cx="10" cy="10" r="2.5"/><circle cx="24" cy="10" r="2.5"/><circle cx="38" cy="10" r="2.5"/>
        <circle cx="10" cy="24" r="2.5"/>                                   <circle cx="38" cy="24" r="2.5"/>
        <circle cx="10" cy="38" r="2.5"/><circle cx="24" cy="38" r="2.5"/><circle cx="38" cy="38" r="2.5"/>
      </g>
      <circle cx="24" cy="24" r="4.5" fill="var(--brand)"/>
      <g stroke="var(--brand)" strokeWidth="2" strokeLinecap="round">
        <line x1="24" y1="19.5" x2="24" y2="12"/>
        <line x1="28.5" y1="24" x2="36" y2="24"/>
        <line x1="24" y1="28.5" x2="24" y2="36"/>
        <line x1="19.5" y1="24" x2="12" y2="24"/>
      </g>
    </svg>
    <span className="flex flex-col leading-tight whitespace-nowrap">
      <span className="text-sm font-bold tracking-tight whitespace-nowrap">KSeF<span className="font-normal"> Hub</span></span>
    </span>
  </a>
);

// EmptyState — canonical empty surface for tabs, tiles, and lists where
// "zero data" is a real state (not a filter result). See DESIGN_SYSTEM.md §7.
//
// tones:
//   default — normal zero-data (muted circle + optional CTA)
//   locked  — feature doesn't apply to this record (no CTA)
//   warning — something failed and needs attention (warning-tinted icon)
const EmptyState = ({ icon = "info", title, sub, action, tone = "default", className = "" }) => {
  const tones = {
    default: "bg-[var(--muted)] text-[var(--muted-foreground)] border-[var(--border)]",
    locked: "bg-[var(--muted)] text-[var(--muted-foreground)] border-[var(--border)] opacity-80",
    warning: "bg-[color-mix(in_oklch,var(--warning)_12%,transparent)] text-[var(--warning)] border-[color-mix(in_oklch,var(--warning)_30%,transparent)]",
  };
  return (
    <div className={`flex flex-col items-center text-center gap-3 py-14 px-6 ${className}`}>
      <span className={`inline-flex items-center justify-center w-10 h-10 rounded-full border ${tones[tone]}`}>
        <Icon name={icon} size={18} />
      </span>
      <div className="space-y-1 max-w-sm">
        <div className="text-sm font-medium text-[var(--foreground)]">{title}</div>
        {sub && <div className="text-xs text-[var(--muted-foreground)] leading-relaxed">{sub}</div>}
      </div>
      {action && tone !== "locked" && <div className="mt-1">{action}</div>}
    </div>
  );
};

Object.assign(window, { Icon, Button, Badge, Card, Input, Logo, EmptyState });
