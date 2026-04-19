// InvoicesList — mirrors lib/ksef_hub_web/live/invoice_live/index.ex
// Filters strip, table, status/kind/category badges, pagination, row click

const StatusBadge = ({ status }) => {
  if (!status) return null;
  const map = {
    pending: "warning",
    approved: "success",
    rejected: "error",
    duplicate: "error",
    needs_review: "info",
    manual: "muted",
  };
  return <Badge variant={map[status] || "muted"}>{status.replace("_", " ")}</Badge>;
};

const KindBadge = ({ kind }) => {
  if (!kind || kind === "vat") return <Badge variant="muted">vat</Badge>;
  if (kind === "correction") return <Badge variant="purple">correction</Badge>;
  if (kind === "advance") return <Badge variant="info">advance</Badge>;
  if (kind === "duplicate") return <Badge variant="warning">duplicate</Badge>;
  return <Badge variant="muted">{kind}</Badge>;
};

const ExtractionBadge = ({ state }) => {
  if (state === "complete") return null;
  const map = { partial: "warning", incomplete: "warning", failed: "error" };
  return <Badge variant={map[state] || "muted"}>{state}</Badge>;
};

const TypePill = ({ type }) => (
  <span className={`inline-flex items-center gap-1 text-xs font-medium ${type === "income" ? "text-[var(--success)]" : "text-[var(--muted-foreground)]"}`}>
    <span className={`inline-block w-1.5 h-1.5 rounded-full ${type === "income" ? "bg-[var(--success)]" : "bg-[var(--muted-foreground)]"}`} />
    {type}
  </span>
);

const CategoryBadge = ({ category, predicted, confidence }) => {
  if (!category) return <span className="text-xs text-[var(--muted-foreground)]">—</span>;
  return (
    <span className={`inline-flex items-center gap-1 px-1.5 py-0.5 rounded-md text-xs border ${predicted ? "border-dashed" : ""} border-[var(--border)] bg-[var(--muted)]`}>
      <span>{category.emoji}</span>
      <span>{category.name}</span>
      {predicted && confidence != null && (
        <span className="text-[10px] text-[var(--muted-foreground)]">· {Math.round(confidence * 100)}%</span>
      )}
    </span>
  );
};

const SourceDot = ({ source, type }) => {
  const src = source || "ksef";
  const colors = {
    ksef: "bg-[var(--primary)]",
    email: "bg-blue-500",
    upload: "bg-amber-500",
    api: "bg-purple-500",
    manual: "bg-[var(--muted-foreground)]",
  };
  const labels = {
    ksef: "KSeF",
    email: "Email ingest",
    upload: "PDF upload",
    api: "API",
    manual: "Manual entry",
  };
  const tooltip = `${labels[src]} * ${type}`;
  return (
    <span title={tooltip}
      className={`inline-block w-2 h-2 rounded-full ${colors[src] || colors.ksef}`} />
  );
};

const InvoiceRow = ({ inv, onClick }) => (
  <tr onClick={onClick} className="group cursor-pointer border-b border-[var(--border)] hover:bg-[var(--accent)] transition-colors">
    <td className="pl-4 pr-2 py-3 w-6">
      <SourceDot source={inv.source} type={inv.type} />
    </td>
    <td className="px-4 py-3 max-w-[200px]">
      <span className="font-mono text-xs truncate block" title={inv.number}>{inv.number}</span>
    </td>
    <td className="px-4 py-3 max-w-[220px]">
      <div className="text-sm truncate" title={inv.seller}>{inv.seller}</div>
      {inv.nip && <div className="font-mono text-[11px] text-[var(--muted-foreground)] truncate">{inv.nip}</div>}
    </td>
    <td className="px-4 py-3 font-mono text-xs text-[var(--muted-foreground)] whitespace-nowrap" title={inv.date}>
      {(() => {
        const [y, m, d] = inv.date.split("-").map(Number);
        const dt = new Date(y, m - 1, d);
        return dt.toLocaleDateString("en-GB", { day: "2-digit", month: "short" });
      })()}
    </td>
    <td className="px-4 py-3 text-right whitespace-nowrap">
      <div className="font-mono text-sm tabular-nums leading-tight">
        {inv.brutto ?? <span className="text-[var(--muted-foreground)]">—</span>}
        {inv.brutto && <span className="text-[var(--muted-foreground)] text-xs ml-1">{inv.currency}</span>}
      </div>
      {inv.netto && (
        <div className="font-mono text-[11px] tabular-nums leading-tight text-[var(--muted-foreground)] mt-0.5">
          {inv.netto} <span className="opacity-70">net</span>
        </div>
      )}
    </td>
    <td className="px-4 py-3">
      <div className="flex items-center gap-2">
        <KindBadge kind={inv.duplicateStatus === "suspected" ? "duplicate" : inv.kind} />
        <ExtractionBadge state={inv.extraction} />
      </div>
    </td>
    <td className="px-4 py-3">
      <CategoryBadge category={inv.category} predicted={inv.predicted} confidence={inv.confidence} />
    </td>
    <td className="px-4 py-3"><StatusBadge status={inv.status} /></td>
    <td className="px-4 py-3"><PaymentBadge status={inv.paymentStatus} /></td>
    <td className="px-2 py-3 text-right text-[var(--muted-foreground)] opacity-0 group-hover:opacity-100 transition-opacity">
      <Icon name="chevron-right" size={14} />
    </td>
  </tr>
);

const FilterChip = ({ active, children, onClick, onClear }) => (
  <button onClick={onClick}
    className={`inline-flex items-center gap-1.5 h-8 px-2.5 rounded-md border text-xs cursor-pointer transition-colors ${active ? "bg-[var(--foreground)] text-[var(--background)] border-[var(--foreground)]" : "bg-[var(--background)] border-[var(--input)] hover:bg-[var(--accent)]"}`}>
    {children}
    {active && onClear && (
      <span onClick={e => { e.stopPropagation(); onClear(); }} className="hover:bg-black/10 rounded p-0.5">
        <Icon name="x-mark" size={10} />
      </span>
    )}
  </button>
);

const MultiPicker = ({ label, icon, options, selected, onChange, formatOption }) => {
  const [open, setOpen] = React.useState(false);
  const count = selected.length;
  const toggle = (id) => onChange(selected.includes(id) ? selected.filter(x => x !== id) : [...selected, id]);
  return (
    <div className="relative">
      <button onClick={() => setOpen(o => !o)}
        className={`inline-flex items-center gap-1.5 h-8 px-2.5 rounded-md border text-xs cursor-pointer transition-colors ${count > 0 ? "border-[var(--foreground)] bg-[var(--accent)]" : "border-[var(--input)] bg-[var(--background)] hover:bg-[var(--accent)]"}`}>
        {icon && <Icon name={icon} size={11} />}
        <span>{label}</span>
        {count > 0 && <span className="inline-flex items-center justify-center min-w-[16px] h-4 px-1 rounded bg-[var(--foreground)] text-[var(--background)] text-[10px] font-mono">{count}</span>}
        <Icon name="chevron-down" size={10} className="opacity-50" />
      </button>
      {open && (
        <>
          <div className="fixed inset-0 z-40" onClick={() => setOpen(false)} />
          <div className="absolute left-0 top-full mt-1 z-50 p-1 border border-[var(--border)] bg-[var(--popover)] rounded-md shadow-md w-56 max-h-80 overflow-auto">
            {count > 0 && (
              <button onClick={() => onChange([])}
                className="w-full text-left px-2 py-1.5 rounded-sm text-xs text-[var(--muted-foreground)] hover:bg-[var(--accent)] border-b border-[var(--border)] mb-1 cursor-pointer">
                Clear selection
              </button>
            )}
            {options.map(o => (
              <label key={o.id} className="flex items-center gap-2 px-2 py-1.5 rounded-sm text-sm cursor-pointer hover:bg-[var(--accent)]">
                <input type="checkbox" checked={selected.includes(o.id)} onChange={() => toggle(o.id)}
                  className="rounded border-[var(--input)]" />
                <span className="flex-1">{formatOption ? formatOption(o) : o.name}</span>
              </label>
            ))}
          </div>
        </>
      )}
    </div>
  );
};

const DateRangePicker = () => {
  const [open, setOpen] = React.useState(false);
  const [preset, setPreset] = React.useState("this-month");
  const presets = [
    { id: "today", label: "Today", range: "Apr 19, 2026" },
    { id: "7d", label: "Last 7 days", range: "Apr 13 - Apr 19, 2026" },
    { id: "30d", label: "Last 30 days", range: "Mar 21 - Apr 19, 2026" },
    { id: "this-month", label: "This month", range: "Apr 1 - Apr 19, 2026" },
    { id: "last-month", label: "Last month", range: "Mar 1 - Mar 31, 2026" },
    { id: "q2", label: "Q2 2026", range: "Apr 1 - Jun 30, 2026" },
    { id: "ytd", label: "Year to date", range: "Jan 1 - Apr 19, 2026" },
    { id: "custom", label: "Custom range...", range: "" },
  ];
  const active = presets.find(p => p.id === preset);
  return (
    <div className="relative">
      <button onClick={() => setOpen(o => !o)}
        className="inline-flex items-center gap-1.5 h-8 px-2.5 rounded-md border border-[var(--input)] bg-[var(--background)] hover:bg-[var(--accent)] text-xs cursor-pointer transition-colors">
        <Icon name="calendar" size={11} />
        <span className="font-mono">{active.range || active.label}</span>
        <Icon name="chevron-down" size={10} className="opacity-50" />
      </button>
      {open && (
        <>
          <div className="fixed inset-0 z-40" onClick={() => setOpen(false)} />
          <div className="absolute left-0 top-full mt-1 z-50 p-1 border border-[var(--border)] bg-[var(--popover)] rounded-md shadow-md w-64">
            {presets.map(p => (
              <button key={p.id} onClick={() => { setPreset(p.id); setOpen(false); }}
                className={`w-full flex items-center justify-between px-2 py-1.5 rounded-sm text-sm cursor-pointer hover:bg-[var(--accent)] ${preset === p.id ? "bg-[var(--accent)] font-medium" : ""}`}>
                <span>{p.label}</span>
                <span className="text-[10px] font-mono text-[var(--muted-foreground)]">{p.range}</span>
              </button>
            ))}
          </div>
        </>
      )}
    </div>
  );
};

const PaymentBadge = ({ status }) => {
  if (!status || status === "none") return <span className="text-xs text-[var(--muted-foreground)]">-</span>;
  if (status === "paid") return <Badge variant="success">paid</Badge>;
  if (status === "pending") return <Badge variant="warning">pending</Badge>;
  return <Badge variant="muted">{status}</Badge>;
};

const TypeTabs = ({ value, onChange }) => {
  const counts = React.useMemo(() => ({
    all: INVOICES.length,
    income: INVOICES.filter(i => i.type === "income").length,
    expense: INVOICES.filter(i => i.type === "expense").length,
  }), []);
  const tabs = [
    { id: "all", label: "All" },
    { id: "income", label: "Income" },
    { id: "expense", label: "Expense" },
  ];
  return (
    <div className="-mt-2 mb-5 border-b border-[var(--border)] flex items-center gap-0">
      {tabs.map(t => {
        const active = value === t.id;
        return (
          <button key={t.id} onClick={() => onChange(t.id)}
            className={`relative -mb-px h-10 px-4 text-sm cursor-pointer transition-colors flex items-center gap-2 ${active ? "text-[var(--foreground)] font-medium" : "text-[var(--muted-foreground)] hover:text-[var(--foreground)]"}`}>
            {t.label}
            <span className={`inline-flex items-center justify-center min-w-[20px] h-[18px] px-1 rounded text-[11px] font-mono tabular-nums ${active ? "bg-[var(--foreground)] text-[var(--background)]" : "bg-[var(--muted)] text-[var(--muted-foreground)]"}`}>{counts[t.id]}</span>
            {active && <span className="absolute left-0 right-0 bottom-0 h-[2px] bg-[var(--foreground)]"></span>}
          </button>
        );
      })}
    </div>
  );
};

const STATUS_OPTIONS = [
  { id: "pending", name: "Pending" },
  { id: "approved", name: "Approved" },
  { id: "rejected", name: "Rejected" },
  { id: "duplicate", name: "Duplicate" },
  { id: "incomplete", name: "Incomplete" },
  { id: "excluded", name: "Excluded" },
];
const PAYMENT_OPTIONS = [
  { id: "paid", name: "Paid" },
  { id: "pending", name: "Pending" },
  { id: "none", name: "None" },
];

const InvoicesList = ({ onOpen }) => {
  const [type, setType] = React.useState("all");
  const [statuses, setStatuses] = React.useState([]);
  const [categories, setCategories] = React.useState([]);
  const [tags, setTags] = React.useState([]);
  const [payments, setPayments] = React.useState([]);
  const [query, setQuery] = React.useState("");

  const filtered = INVOICES.filter(i => {
    if (type !== "all" && i.type !== type) return false;
    if (statuses.length) {
      const s = i.status === "needs_review" ? "incomplete" : i.duplicateStatus === "suspected" ? "duplicate" : i.status;
      if (!statuses.includes(s)) return false;
    }
    if (categories.length) {
      const cid = i.category ? (CATEGORIES.find(c => c.name === i.category.name)?.id) : null;
      if (!cid || !categories.includes(cid)) return false;
    }
    if (tags.length && !i.tags.some(t => tags.includes(t))) return false;
    if (payments.length && !payments.includes(i.paymentStatus || "none")) return false;
    if (query && !(`${i.seller} ${i.number} ${i.nip || ""}`.toLowerCase().includes(query.toLowerCase()))) return false;
    return true;
  });

  const activeFilterCount = statuses.length + categories.length + tags.length + payments.length;
  const clearAll = () => { setStatuses([]); setCategories([]); setTags([]); setPayments([]); };

  const subtitlePrefix = type === "all" ? "All invoices" : type === "income" ? "Income invoices" : "Expense invoices";

  return (
    <div>
      <PageHeader title="Invoices"
        subtitle={`${subtitlePrefix} * ${filtered.length} of ${INVOICES.length}`}
        actions={
          <>
            <Button variant="outline" size="default">
              <Icon name="arrow-path" size={14} /> Sync now
            </Button>
            <Button variant="primary" size="default">
              <Icon name="plus" size={14} /> New invoice
            </Button>
          </>
        } />

      <TypeTabs value={type} onChange={setType} />

      {/* Filter strip */}
      <div className="flex flex-wrap items-center gap-2 mb-4">
        <div className="relative">
          <Icon name="search" size={14} className="absolute left-2.5 top-1/2 -translate-y-1/2 text-[var(--muted-foreground)]" />
          <input value={query} onChange={e => setQuery(e.target.value)}
            placeholder="Search by seller, number, NIP…"
            className="h-8 w-64 pl-8 pr-3 rounded-md border border-[var(--input)] bg-[var(--background)] text-xs focus:outline-none focus:ring-1 focus:ring-[var(--ring)]" />
        </div>
        <DateRangePicker />
        <MultiPicker label="Status" icon="warning" options={STATUS_OPTIONS} selected={statuses} onChange={setStatuses} />
        <MultiPicker label="Category" icon="tag" options={CATEGORIES} selected={categories} onChange={setCategories}
          formatOption={o => <span className="inline-flex items-center gap-1.5"><span>{o.emoji}</span>{o.name}</span>} />
        <MultiPicker label="Tags" icon="hashtag" options={TAGS} selected={tags} onChange={setTags}
          formatOption={o => <span className="font-mono text-xs">#{o.name}</span>} />
        <MultiPicker label="Payment" icon="cash" options={PAYMENT_OPTIONS} selected={payments} onChange={setPayments} />
        {activeFilterCount > 0 && (
          <button onClick={clearAll}
            className="inline-flex items-center gap-1 h-8 px-2 rounded-md text-xs text-[var(--muted-foreground)] hover:text-[var(--foreground)] hover:bg-[var(--accent)] cursor-pointer">
            <Icon name="x-mark" size={11} /> Clear filters
          </button>
        )}
        <div className="flex-1" />
        <Button variant="ghost" size="sm"><Icon name="download" size={13} /> Export</Button>
      </div>

      {/* Table */}
      <div className="rounded-lg border border-[var(--border)] overflow-hidden bg-[var(--card)]">
        <div className="overflow-x-auto">
          <table className="w-full text-left">
            <thead className="bg-[var(--muted)]/50 border-b border-[var(--border)]">
              <tr className="text-xs uppercase tracking-wide text-[var(--muted-foreground)]">
                <th className="pl-4 pr-2 py-2.5 font-medium w-6" title="Source"></th>
                <th className="px-4 py-2.5 font-medium w-[200px]">Number</th>
                <th className="px-4 py-2.5 font-medium w-[220px]">Seller</th>
                <th className="px-4 py-2.5 font-medium">Date</th>
                <th className="px-4 py-2.5 font-medium text-right">Amount</th>
                <th className="px-4 py-2.5 font-medium">Kind</th>
                <th className="px-4 py-2.5 font-medium">Category</th>
                <th className="px-4 py-2.5 font-medium">Status</th>
                <th className="px-4 py-2.5 font-medium">Payment</th>
                <th />
              </tr>
            </thead>
            <tbody>
              {filtered.length === 0 ? (
                <tr><td colSpan={10} className="px-4 py-12 text-center text-sm text-[var(--muted-foreground)]">No data for selected period</td></tr>
              ) : filtered.map(inv => <InvoiceRow key={inv.id} inv={inv} onClick={() => onOpen(inv)} />)}
            </tbody>
          </table>
        </div>

        {/* Pagination */}
        <div className="flex items-center justify-between px-4 py-2.5 border-t border-[var(--border)] text-xs text-[var(--muted-foreground)]">
          <span>Showing 1-{filtered.length} of {filtered.length} invoices</span>
          <div className="flex items-center gap-1">
            <Button variant="ghost" size="sm" disabled>Previous</Button>
            <span className="px-2">Page 1 of 1</span>
            <Button variant="ghost" size="sm" disabled>Next</Button>
          </div>
        </div>
      </div>
    </div>
  );
};

Object.assign(window, { InvoicesList });
