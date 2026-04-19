// AppShell — top navbar, company selector, avatar menu
// Mirrors lib/ksef_hub_web/components/layouts.ex `app/1`

const NAV = [
  { label: "Invoices", path: "invoices", icon: "document-text" },
  { label: "Payments", path: "payments", icon: "banknotes" },
  { label: "Dashboard", path: "dashboard", icon: "home" },
  { label: "Companies", path: "companies", icon: "building" },
  { label: "Settings", path: "settings", icon: "cog" },
];

const ThemeToggle = () => {
  const [theme, setTheme] = React.useState(() => document.documentElement.getAttribute("data-theme") || "light");
  const set = (t) => {
    setTheme(t);
    if (t === "system") document.documentElement.removeAttribute("data-theme");
    else document.documentElement.setAttribute("data-theme", t);
  };
  const modes = [
    { id: "system", icon: "cog", label: "System" },
    { id: "light", icon: "sun", label: "Light" },
    { id: "dark", icon: "moon", label: "Dark" },
  ];
  return (
    <div className="relative inline-flex items-center border border-[var(--border)] bg-[var(--muted)] rounded-full p-0.5">
      {modes.map(m => (
        <button key={m.id} onClick={() => set(m.id)}
          className={`flex items-center justify-center w-8 h-7 rounded-full cursor-pointer transition-all ${theme === m.id ? "bg-[var(--background)] shadow-sm" : "opacity-60 hover:opacity-100"}`}
          aria-label={m.id}>
          <Icon name={m.icon} size={13} />
        </button>
      ))}
    </div>
  );
};

const CompanySelector = ({ current, companies, onPick }) => {
  const [open, setOpen] = React.useState(false);
  return (
    <div className="relative">
      <button onClick={() => setOpen(o => !o)}
        className="inline-flex items-center gap-1.5 h-9 px-3 text-sm rounded-md border border-[var(--border)] bg-[var(--background)] hover:bg-[var(--accent)] cursor-pointer transition-colors">
        <Icon name="building" size={13} />
        <span className="hidden sm:inline truncate max-w-32">{current.name}</span>
        <Icon name="chevron-down" size={12} className="opacity-50" />
      </button>
      {open && (
        <>
          <div className="fixed inset-0 z-40" onClick={() => setOpen(false)} />
          <div className="absolute right-0 top-full mt-1 z-50 p-1 border border-[var(--border)] bg-[var(--popover)] rounded-md shadow-md w-60">
            {companies.map(c => (
              <button key={c.id} onClick={() => { onPick(c); setOpen(false); }}
                className={`w-full text-left px-2 py-1.5 rounded-sm cursor-pointer transition-colors ${c.id === current.id ? "bg-[var(--accent)]" : "hover:bg-[var(--accent)]"}`}>
                <span className="block text-sm">{c.name}</span>
                <span className="block text-xs text-[var(--muted-foreground)] font-mono">{c.nip}</span>
              </button>
            ))}
          </div>
        </>
      )}
    </div>
  );
};

const AvatarMenu = ({ email, onLogout }) => {
  const [open, setOpen] = React.useState(false);
  return (
    <div className="relative">
      <button onClick={() => setOpen(o => !o)}
        className="flex items-center justify-center h-8 w-8 rounded-full bg-[var(--primary)] text-[var(--primary-foreground)] text-xs font-medium cursor-pointer hover:opacity-90">
        {email?.[0]?.toUpperCase() || "?"}
      </button>
      {open && (
        <>
          <div className="fixed inset-0 z-40" onClick={() => setOpen(false)} />
          <div className="absolute right-0 top-full mt-1 z-50 p-1 border border-[var(--border)] bg-[var(--popover)] rounded-md shadow-md w-56">
            <div className="px-2 py-1.5 text-xs text-[var(--muted-foreground)] truncate">{email}</div>
            <div className="border-t border-[var(--border)] my-1" />
            <button onClick={onLogout} className="flex w-full items-center gap-2 px-2 py-1.5 text-sm rounded-sm hover:bg-[var(--accent)] cursor-pointer">
              <Icon name="logout" size={14} /> Log out
            </button>
          </div>
        </>
      )}
    </div>
  );
};

const AppShell = ({ page, onNav, children, company, companies, onPickCompany, user }) => (
  <div className="min-h-screen flex flex-col bg-[var(--background)] text-[var(--foreground)]">
    <header className="sticky top-0 z-30 w-full border-b border-[var(--border)] bg-[color-mix(in_oklch,var(--background)_95%,transparent)] backdrop-blur">
      <div className="flex h-14 items-center px-4 lg:px-6 gap-4">
        <Logo />
        <nav className="hidden md:flex items-center gap-1 ml-4">
          {NAV.map(item => (
            <button key={item.path} onClick={() => onNav(item.path)}
              className={`flex items-center gap-1.5 px-2.5 py-1.5 text-sm rounded-md transition-colors cursor-pointer ${page === item.path ? "text-[var(--foreground)] bg-[var(--accent)] font-medium" : "text-[var(--muted-foreground)] hover:bg-[var(--accent)] hover:text-[var(--foreground)]"}`}>
              <Icon name={item.icon} size={14} />
              {item.label}
            </button>
          ))}
        </nav>
        <div className="flex-1" />
        <CompanySelector current={company} companies={companies} onPick={onPickCompany} />
        <AvatarMenu email={user.email} onLogout={() => {}} />
      </div>
    </header>
    <main className="flex-1 p-4 sm:p-6 lg:p-8">
      <div className="mx-auto max-w-7xl">{children}</div>
    </main>
  </div>
);

const PageHeader = ({ title, subtitle, actions }) => (
  <header className="pb-4 border-b border-[var(--border)] flex items-center justify-between gap-6 mb-6">
    <div className="min-w-0 flex-1">
      <h1 className="text-lg font-semibold leading-7 tracking-tight">{title}</h1>
      {subtitle && <p className="text-sm text-[var(--muted-foreground)] mt-0.5 truncate">{subtitle}</p>}
    </div>
    {actions && <div className="flex-none flex gap-2">{actions}</div>}
  </header>
);

Object.assign(window, { ThemeToggle,  AppShell, PageHeader });
