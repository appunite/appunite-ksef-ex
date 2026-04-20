// Settings — cert management, API keys, sync schedule

const SettingsNav = ({ active, onNav }) => {
  const items = [
    { id: "certificates", label: "Certificates", icon: "lock" },
    { id: "api-keys", label: "API keys", icon: "bolt" },
    { id: "sync", label: "Sync schedule", icon: "arrow-path" },
    { id: "appearance", label: "Appearance", icon: "sun" },
    { id: "company", label: "Company", icon: "building" },
  ];
  return (
    <nav className="flex flex-col gap-0.5">
      {items.map(i => (
        <button key={i.id} onClick={() => onNav(i.id)}
          className={`flex items-center gap-2 px-3 py-2 text-sm rounded-md text-left cursor-pointer transition-colors ${active === i.id ? "bg-[var(--accent)] font-medium" : "text-[var(--muted-foreground)] hover:bg-[var(--accent)] hover:text-[var(--foreground)]"}`}>
          <Icon name={i.icon} size={14} />
          {i.label}
        </button>
      ))}
    </nav>
  );
};

const CertificatePanel = () => {
  const empty = window.KSH_EMPTY_DEMO;
  if (empty) {
    return (
      <div className="space-y-4">
        <Card padding="p-0">
          <EmptyState
            tone="warning"
            icon="lock"
            title="No certificate uploaded"
            sub="Upload a XAdES certificate to enable KSeF sync. Without it, the hub cannot sign outbound requests."
            action={<Button variant="primary"><Icon name="upload" size={13} /> Upload certificate</Button>} />
        </Card>
      </div>
    );
  }
  return (
  <div className="space-y-4">
    <Card>
      <div className="flex items-start justify-between">
        <div>
          <h2 className="text-sm font-semibold">Active certificate</h2>
          <p className="text-xs text-[var(--muted-foreground)] mt-0.5">Used to sign all KSeF requests with XAdES.</p>
        </div>
        <Badge variant="success"><Icon name="check" size={10} /> valid</Badge>
      </div>
      <dl className="mt-4">
        <DetailRow label="Subject" mono><span className="text-xs">{CERT.subject}</span></DetailRow>
        <DetailRow label="Serial" mono><span className="text-xs">{CERT.serial}</span></DetailRow>
        <DetailRow label="Issued" mono>{CERT.issued}</DetailRow>
        <DetailRow label="Expires">
          <span className="font-mono">{CERT.expires}</span>
          <span className="ml-2 text-xs text-[var(--muted-foreground)]">· {CERT.daysLeft} days left</span>
        </DetailRow>
      </dl>
      <div className="border-t border-[var(--border)] mt-4 pt-4 flex gap-2">
        <Button variant="primary">Upload new certificate</Button>
        <Button variant="outline">Download public cert</Button>
      </div>
    </Card>

    <Card>
      <h2 className="text-sm font-semibold">Certificate history</h2>
      <p className="text-xs text-[var(--muted-foreground)] mt-0.5 mb-3">Superseded and revoked certs stay in the audit log.</p>
      <ul className="space-y-2 text-sm">
        {[
          { serial: "02:1E:7A:CC:91:FF:B0:22", status: "superseded", on: "2025-01-14" },
          { serial: "01:8F:D2:3B:40:11:8C:A0", status: "revoked", on: "2024-07-02" },
        ].map(c => (
          <li key={c.serial} className="flex items-center justify-between px-3 py-2 rounded-md border border-[var(--border)] bg-[var(--muted)]/30">
            <div className="flex flex-col">
              <span className="font-mono text-xs">{c.serial}</span>
              <span className="text-xs text-[var(--muted-foreground)]">replaced on {c.on}</span>
            </div>
            <Badge variant={c.status === "revoked" ? "error" : "muted"}>{c.status}</Badge>
          </li>
        ))}
      </ul>
    </Card>
  </div>
  );
};

const ApiKeysPanel = () => {
  const keys = [
    { id: "k1", name: "Production", prefix: "ksef_live_7F3xA…", created: "2025-11-04", last: "2 min ago" },
    { id: "k2", name: "Staging", prefix: "ksef_test_K81d2…", created: "2025-08-20", last: "yesterday" },
    { id: "k3", name: "CI runner", prefix: "ksef_test_9aLwe…", created: "2025-03-15", last: "48 days ago" },
  ];
  return (
    <Card>
      <div className="flex items-center justify-between mb-4">
        <div>
          <h2 className="text-sm font-semibold">API keys</h2>
          <p className="text-xs text-[var(--muted-foreground)] mt-0.5">Authenticate requests to the REST API.</p>
        </div>
        <Button variant="primary" size="sm"><Icon name="plus" size={13} /> New key</Button>
      </div>
      <div className="rounded-lg border border-[var(--border)] overflow-hidden">
        <table className="w-full text-sm">
          <thead>
            <tr className="text-xs uppercase tracking-wide text-[var(--muted-foreground)] bg-[var(--muted)]/50 border-b border-[var(--border)]">
              <th className="text-left font-medium px-4 py-2">Name</th>
              <th className="text-left font-medium px-4 py-2">Token</th>
              <th className="text-left font-medium px-4 py-2">Created</th>
              <th className="text-left font-medium px-4 py-2">Last used</th>
              <th />
            </tr>
          </thead>
          <tbody>
            {keys.map(k => (
              <tr key={k.id} className="border-b border-[var(--border)] last:border-b-0">
                <td className="px-4 py-2.5">{k.name}</td>
                <td className="px-4 py-2.5 font-mono text-xs">{k.prefix}</td>
                <td className="px-4 py-2.5 font-mono text-xs text-[var(--muted-foreground)]">{k.created}</td>
                <td className="px-4 py-2.5 text-xs text-[var(--muted-foreground)]">{k.last}</td>
                <td className="px-4 py-2.5 text-right">
                  <Button variant="ghost" size="sm">Revoke</Button>
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </Card>
  );
};

const SyncSchedulePanel = () => {
  const [every, setEvery] = React.useState("1h");
  return (
    <Card>
      <h2 className="text-sm font-semibold">Sync schedule</h2>
      <p className="text-xs text-[var(--muted-foreground)] mt-0.5 mb-4">How often the hub polls KSeF for new invoices.</p>
      <div className="flex flex-wrap gap-1.5 mb-6">
        {["15m", "30m", "1h", "4h", "daily"].map(opt => (
          <button key={opt} onClick={() => setEvery(opt)}
            className={`h-8 px-3 rounded-md border text-xs cursor-pointer transition-colors ${every === opt ? "bg-[var(--foreground)] text-[var(--background)] border-[var(--foreground)]" : "border-[var(--input)] bg-[var(--background)] hover:bg-[var(--accent)]"}`}>
            {opt}
          </button>
        ))}
      </div>
      <div className="grid grid-cols-1 sm:grid-cols-2 gap-4 text-sm">
        <label className="flex items-start gap-3 p-3 rounded-md border border-[var(--border)] cursor-pointer hover:bg-[var(--accent)]/50">
          <input type="checkbox" defaultChecked className="mt-0.5" />
          <span>
            <span className="font-medium block">Auto-categorize new invoices</span>
            <span className="text-xs text-[var(--muted-foreground)]">ML classifier runs after each sync.</span>
          </span>
        </label>
        <label className="flex items-start gap-3 p-3 rounded-md border border-[var(--border)] cursor-pointer hover:bg-[var(--accent)]/50">
          <input type="checkbox" defaultChecked className="mt-0.5" />
          <span>
            <span className="font-medium block">Flag suspected duplicates</span>
            <span className="text-xs text-[var(--muted-foreground)]">Same NIP + brutto within 30 days.</span>
          </span>
        </label>
        <label className="flex items-start gap-3 p-3 rounded-md border border-[var(--border)] cursor-pointer hover:bg-[var(--accent)]/50">
          <input type="checkbox" className="mt-0.5" />
          <span>
            <span className="font-medium block">Webhook notifications</span>
            <span className="text-xs text-[var(--muted-foreground)]">POST to your endpoint on sync completion.</span>
          </span>
        </label>
        <label className="flex items-start gap-3 p-3 rounded-md border border-[var(--border)] cursor-pointer hover:bg-[var(--accent)]/50">
          <input type="checkbox" className="mt-0.5" />
          <span>
            <span className="font-medium block">Email digest</span>
            <span className="text-xs text-[var(--muted-foreground)]">Daily at 07:00 Europe/Warsaw.</span>
          </span>
        </label>
      </div>
    </Card>
  );
};

const AppearancePanel = () => {
  const [theme, setTheme] = React.useState(() => {
    try {
      const stored = localStorage.getItem("ksef-theme");
      if (stored) return stored;
    } catch (e) {}
    return document.documentElement.getAttribute("data-theme") || "light";
  });
  const set = (t) => {
    setTheme(t);
    if (t === "system") document.documentElement.removeAttribute("data-theme");
    else document.documentElement.setAttribute("data-theme", t);
    try { localStorage.setItem("ksef-theme", t); } catch (e) {}
  };
  const modes = [
    { id: "light", icon: "sun", label: "Light", desc: "Bright surfaces, high contrast." },
    { id: "dark", icon: "moon", label: "Dark", desc: "Low-light friendly, reduced glare." },
    { id: "system", icon: "cog", label: "System", desc: "Match your OS setting." },
  ];
  return (
    <Card>
      <h2 className="text-sm font-semibold">Theme</h2>
      <p className="text-xs text-[var(--muted-foreground)] mt-0.5 mb-4">Choose how KSeF Hub looks. Applies to every screen in this browser.</p>
      <div className="grid grid-cols-1 sm:grid-cols-3 gap-3">
        {modes.map(m => {
          const active = theme === m.id;
          return (
            <button key={m.id} onClick={() => set(m.id)}
              className={`group text-left p-3 rounded-lg border transition-all cursor-pointer ${active ? "border-[var(--foreground)] bg-[var(--accent)]" : "border-[var(--border)] hover:border-[var(--foreground)]/40 hover:bg-[var(--accent)]/50"}`}>
              <div className="flex items-center justify-between mb-3">
                <div className="flex items-center gap-2">
                  <span className="inline-flex items-center justify-center w-7 h-7 rounded-md border border-[var(--border)] bg-[var(--background)]">
                    <Icon name={m.icon} size={14} />
                  </span>
                  <span className="text-sm font-medium">{m.label}</span>
                </div>
                {active && <Badge variant="success"><Icon name="check" size={10} /> active</Badge>}
              </div>
              {/* Mini preview */}
              <div className={`rounded-md border border-[var(--border)] overflow-hidden ${m.id === "dark" ? "bg-[#0a0a0a]" : m.id === "light" ? "bg-white" : "bg-gradient-to-br from-white to-[#0a0a0a]"}`}>
                <div className={`h-6 border-b ${m.id === "dark" ? "border-white/10 bg-white/5" : "border-black/10 bg-black/5"} flex items-center gap-1 px-2`}>
                  <span className={`w-1.5 h-1.5 rounded-full ${m.id === "dark" ? "bg-white/30" : "bg-black/30"}`} />
                  <span className={`w-1.5 h-1.5 rounded-full ${m.id === "dark" ? "bg-white/30" : "bg-black/30"}`} />
                </div>
                <div className="p-2 space-y-1">
                  <div className={`h-1.5 w-3/5 rounded ${m.id === "dark" ? "bg-white/60" : "bg-black/70"}`} />
                  <div className={`h-1 w-4/5 rounded ${m.id === "dark" ? "bg-white/20" : "bg-black/20"}`} />
                  <div className={`h-1 w-2/5 rounded ${m.id === "dark" ? "bg-white/20" : "bg-black/20"}`} />
                </div>
              </div>
              <p className="text-xs text-[var(--muted-foreground)] mt-2">{m.desc}</p>
            </button>
          );
        })}
      </div>
    </Card>
  );
};

const Settings = () => {
  const [section, setSection] = React.useState("certificates");
  return (
    <div>
      <PageHeader title="Settings" subtitle="Company-level configuration" />
      <div className="grid grid-cols-1 lg:grid-cols-[200px_1fr] gap-6">
        <SettingsNav active={section} onNav={setSection} />
        <div>
          {section === "certificates" && <CertificatePanel />}
          {section === "api-keys" && <ApiKeysPanel />}
          {section === "sync" && <SyncSchedulePanel />}
          {section === "appearance" && <AppearancePanel />}
          {section === "company" && (
            <Card>
              <h2 className="text-sm font-semibold mb-3">Company details</h2>
              <Input label="Legal name" defaultValue="Appunite sp. z o.o." />
              <Input label="NIP" defaultValue="PL9721241997" />
              <Input label="KSeF reporting address" defaultValue="ksef@appunite.com" />
              <div className="pt-2 flex gap-2">
                <Button variant="primary">Save changes</Button>
                <Button variant="ghost">Cancel</Button>
              </div>
            </Card>
          )}
        </div>
      </div>
    </div>
  );
};

Object.assign(window, { Settings });
