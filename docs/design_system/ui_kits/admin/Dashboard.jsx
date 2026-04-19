// Dashboard — sync health, counters, recent sync jobs

const StatCard = ({ label, value, delta, deltaTone = "muted", mono = true, hint }) => (
  <Card padding="p-5">
    <div className="text-xs uppercase tracking-wide text-[var(--muted-foreground)] font-medium">{label}</div>
    <div className={`mt-2 text-3xl font-semibold ${mono ? "font-mono tabular-nums" : ""} tracking-tight`}>{value}</div>
    {delta && (
      <div className={`mt-1 text-xs ${deltaTone === "up" ? "text-[var(--success)]" : deltaTone === "down" ? "text-[var(--destructive)]" : "text-[var(--muted-foreground)]"}`}>
        {delta}
      </div>
    )}
    {hint && <div className="mt-1 text-xs text-[var(--muted-foreground)]">{hint}</div>}
  </Card>
);

const SyncHealthChart = () => {
  // Mini area-style chart built from SVG rects — no libs
  const data = [2, 4, 3, 5, 2, 3, 4, 6, 3, 3, 2, 4, 3, 2, 4, 5, 3, 4, 3, 2, 4, 3, 6, 3];
  const fails = [0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0];
  const max = Math.max(...data) + 1;
  return (
    <Card>
      <div className="flex items-center justify-between mb-4">
        <div>
          <h2 className="text-sm font-semibold">Sync health</h2>
          <p className="text-xs text-[var(--muted-foreground)]">Last 24 hours · hourly jobs</p>
        </div>
        <Badge variant="success"><Icon name="check" size={10} /> operational</Badge>
      </div>
      <svg viewBox="0 0 480 120" className="w-full h-32">
        {data.map((d, i) => {
          const h = (d / max) * 90;
          const x = i * 20 + 2;
          const failed = fails[i] > 0;
          return (
            <rect key={i} x={x} y={110 - h} width={16} height={h} rx={2}
              fill={failed ? "var(--destructive)" : "var(--brand)"}
              opacity={failed ? 1 : 0.85} />
          );
        })}
        <line x1="0" y1="110" x2="480" y2="110" stroke="var(--border)" />
      </svg>
      <div className="flex justify-between text-[10px] text-[var(--muted-foreground)] font-mono mt-1">
        <span>00:00</span><span>06:00</span><span>12:00</span><span>18:00</span><span>now</span>
      </div>
    </Card>
  );
};

const RecentSyncJobs = () => (
  <Card padding="p-0">
    <div className="flex items-center justify-between gap-3 px-5 py-3 border-b border-[var(--border)]">
      <h2 className="text-sm font-semibold whitespace-nowrap">Recent sync jobs</h2>
      <Button variant="ghost" size="sm" className="flex-none">View all</Button>
    </div>
    <table className="w-full text-sm">
      <thead>
        <tr className="text-xs uppercase tracking-wide text-[var(--muted-foreground)] border-b border-[var(--border)]">
          <th className="text-left font-medium px-5 py-2">Time</th>
          <th className="text-left font-medium px-5 py-2">State</th>
          <th className="text-right font-medium px-5 py-2">Income</th>
          <th className="text-right font-medium px-5 py-2">Expense</th>
          <th className="text-right font-medium px-5 py-2">Duration</th>
        </tr>
      </thead>
      <tbody>
        {(SYNC_JOBS ?? []).map(j => (
          <tr key={j.id} className="border-b border-[var(--border)] last:border-b-0 hover:bg-[var(--accent)]/50">
            <td className="px-5 py-2.5 font-mono text-xs text-[var(--muted-foreground)]">{j.inserted}</td>
            <td className="px-5 py-2.5">
              {j.state === "failed"
                ? <Badge variant="error">{j.state}</Badge>
                : <Badge variant="success">{j.state}</Badge>}
              {j.error && <div className="text-xs text-[var(--destructive)] mt-1">{j.error}</div>}
            </td>
            <td className="px-5 py-2.5 text-right font-mono">{j.income ?? "—"}</td>
            <td className="px-5 py-2.5 text-right font-mono">{j.expense ?? "—"}</td>
            <td className="px-5 py-2.5 text-right font-mono">{j.duration}</td>
          </tr>
        ))}
      </tbody>
    </table>
  </Card>
);

const Dashboard = () => (
  <div>
    <PageHeader
      title="Dashboard"
      subtitle="Sync status · last 30 days"
      actions={<Button variant="outline"><Icon name="arrow-path" size={14} /> Sync now</Button>} />

    <Banner variant="warning" icon="warning" title="Your KSeF certificate expires in 96 days."
      actions={<Button variant="outline" size="sm">Manage certificates</Button>}>
      Certificate for <span className="font-mono">CN=Appunite sp. z o.o.</span> will require renewal before
      <span className="font-mono"> 2026-04-20</span>. Schedule the replacement early to avoid sync interruption.
    </Banner>

    <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-4 mb-4">
      <StatCard label="Invoices synced" value="412" delta="+17 this week" deltaTone="up" />
      <StatCard label="Pending review" value="24" delta="3 over 7 days" deltaTone="down" />
      <StatCard label="Auto-categorized" value="87.3%" hint="vs 82.1% last month" />
      <StatCard label="Sync uptime" value="99.84%" hint="30-day rolling" />
    </div>

    <div className="grid grid-cols-1 lg:grid-cols-3 gap-4">
      <div className="lg:col-span-2"><SyncHealthChart /></div>
      <Card>
        <h2 className="text-sm font-semibold mb-3">Queue</h2>
        <dl className="space-y-2.5 text-sm">
          <div className="flex justify-between items-center gap-3">
            <dt className="text-[var(--muted-foreground)] truncate">Pending approval</dt>
            <dd className="flex-none"><Badge variant="warning">24</Badge></dd>
          </div>
          <div className="flex justify-between items-center gap-3">
            <dt className="text-[var(--muted-foreground)] truncate">Needs review</dt>
            <dd className="flex-none"><Badge variant="info">6</Badge></dd>
          </div>
          <div className="flex justify-between items-center gap-3">
            <dt className="text-[var(--muted-foreground)] truncate">Suspected duplicates</dt>
            <dd className="flex-none"><Badge variant="warning">2</Badge></dd>
          </div>
          <div className="flex justify-between items-center gap-3">
            <dt className="text-[var(--muted-foreground)] truncate">Failed extraction</dt>
            <dd className="flex-none"><Badge variant="error">1</Badge></dd>
          </div>
        </dl>
        <Button variant="outline" size="sm" className="w-full mt-4">Open queue</Button>
      </Card>
    </div>

    <div className="mt-4">
      <RecentSyncJobs />
    </div>
  </div>
);

Object.assign(window, { Dashboard });
