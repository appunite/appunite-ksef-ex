// Payments - outgoing payment requests generated from approved expenses.
// All payments are bank transfers.

const PAYMENT_REQUESTS = [
  { id: "p01", status: "pending",
    counterparty: "Google Ireland Ltd.", iban: "IE29 AIBK 9311 5212 3456 78", amount: "1 525.20", currency: "PLN",
    invoiceNumber: "FV/2026/04/0141",
    scheduledFor: "2026-04-22", createdAt: "2026-04-18", reference: "FV/2026/04/0141" },
  { id: "p02", status: "pending",
    counterparty: "Orange Polska", iban: "PL61 1090 1014 0000 0712 1981 2874", amount: "492.50", currency: "PLN",
    invoiceNumber: "FV/2026/04/0136",
    scheduledFor: "2026-04-21", createdAt: "2026-04-17", reference: "FV/2026/04/0136" },
  { id: "p03", status: "pending",
    counterparty: "Benefit Systems S.A.", iban: "PL83 1140 1112 4000 0123 4567 8901", amount: "2 583.00", currency: "PLN",
    invoiceNumber: "FV/2026/03/0898",
    scheduledFor: "2026-04-30", createdAt: "2026-04-18", reference: "FV/2026/03/0898" },
  { id: "p04", status: "pending",
    counterparty: "Stripe Payments Europe", iban: "IE64 IRCE 9920 5500 0001 23", amount: "284.00", currency: "EUR",
    invoiceNumber: "INV-8821",
    scheduledFor: "2026-04-20", createdAt: "2026-04-17", reference: "INV-8821" },
  { id: "p05", status: "sent",
    counterparty: "Tauron Sprzedaz sp. z o.o.", iban: "PL27 1930 1089 0000 0123 1234 5678", amount: "421.74", currency: "PLN",
    invoiceNumber: "FV/2026/04/0126",
    scheduledFor: "2026-04-15", sentAt: "2026-04-15 09:12 UTC", createdAt: "2026-04-12", reference: "FV/2026/04/0126" },
  { id: "p06", status: "sent",
    counterparty: "Netia S.A.", iban: "PL44 1050 1025 1000 0022 1234 5678", amount: "492.50", currency: "PLN",
    invoiceNumber: "FV/2026/04/0136",
    scheduledFor: "2026-04-14", sentAt: "2026-04-14 11:03 UTC", createdAt: "2026-04-11", reference: "FV/2026/04/0136" },
  { id: "p07", status: "voided",
    counterparty: "Linear Orbit Inc.", iban: "US-INVALID-000000", amount: "48.00", currency: "USD",
    invoiceNumber: "AR-2026-44",
    scheduledFor: "2026-04-13", voidedAt: "2026-04-13 10:22 UTC", createdAt: "2026-04-11", reference: "AR-2026-44",
    voidReason: "Duplicate of p08" },
  { id: "p08", status: "pending",
    counterparty: "IKEA Retail sp. z o.o.", iban: "PL12 1240 1170 5000 0012 3456 7890", amount: "600.00", currency: "PLN",
    invoiceNumber: "FV/2026/04/0127",
    scheduledFor: "2026-04-25", createdAt: "2026-04-16", reference: "FV/2026/04/0127" },
  { id: "p09", status: "pending",
    counterparty: "Allegro sp. z o.o.", iban: "PL59 1090 2590 0000 0001 4321 1234", amount: "1 224.00", currency: "PLN",
    invoiceNumber: "FV/2026/04/0135",
    scheduledFor: "2026-04-24", createdAt: "2026-04-18", reference: "FV/2026/04/0135" },
  { id: "p10", status: "sent",
    counterparty: "Vercel Inc.", iban: "US11 VERC 1100 0000 5566 78", amount: "20.00", currency: "USD",
    invoiceNumber: "INV-0077",
    scheduledFor: "2026-04-08", sentAt: "2026-04-08 16:40 UTC", createdAt: "2026-04-07", reference: "INV-0077" },
  { id: "p11", status: "voided",
    counterparty: "Restauracja Karmnik", iban: "PL22 1020 1068 0000 1102 0123 4567", amount: "200.00", currency: "PLN",
    invoiceNumber: "FV/2026/04/0129",
    scheduledFor: "2026-04-08", voidedAt: "2026-04-09 08:15 UTC", createdAt: "2026-04-07", reference: "FV/2026/04/0129",
    voidReason: "Invoice rejected" },
];

const PaymentStatusBadge = ({ status }) => {
  const map = {
    pending: { v: "info", label: "pending" },
    sent: { v: "success", label: "sent" },
    voided: { v: "muted", label: "voided" },
  };
  const m = map[status] || { v: "muted", label: status };
  return <Badge variant={m.v}>{m.label}</Badge>;
};

// Tri-state checkbox: checked, unchecked, indeterminate
const RowCheckbox = ({ checked, indeterminate, onChange, ariaLabel }) => {
  const ref = React.useRef(null);
  React.useEffect(() => {
    if (ref.current) ref.current.indeterminate = !!indeterminate;
  }, [indeterminate]);
  return (
    <label className="inline-flex items-center justify-center cursor-pointer" onClick={(e) => e.stopPropagation()}>
      <input ref={ref} type="checkbox" checked={!!checked} onChange={e => onChange(e.target.checked)}
        aria-label={ariaLabel}
        className="w-4 h-4 rounded border-[var(--border)] text-[var(--foreground)] focus:ring-1 focus:ring-[var(--ring)] cursor-pointer accent-[var(--foreground)]" />
    </label>
  );
};

const StatusTabs = ({ value, onChange, data }) => {
  const counts = React.useMemo(() => ({
    all: data.length,
    pending: data.filter(p => p.status === "pending").length,
    sent: data.filter(p => p.status === "sent").length,
    voided: data.filter(p => p.status === "voided").length,
  }), [data]);
  const tabs = [
    { id: "all", label: "All" },
    { id: "pending", label: "Pending" },
    { id: "sent", label: "Sent" },
    { id: "voided", label: "Voided" },
  ];
  return (
    <div className="-mt-2 mb-5 border-b border-[var(--border)] flex items-center gap-0 overflow-x-auto">
      {tabs.map(t => {
        const active = value === t.id;
        return (
          <button key={t.id} onClick={() => onChange(t.id)}
            className={`relative -mb-px h-10 px-4 text-sm cursor-pointer transition-colors flex items-center gap-2 whitespace-nowrap ${active ? "text-[var(--foreground)] font-medium" : "text-[var(--muted-foreground)] hover:text-[var(--foreground)]"}`}>
            {t.label}
            <span className={`inline-flex items-center justify-center min-w-[20px] h-[18px] px-1 rounded text-[11px] font-mono tabular-nums ${active ? "bg-[var(--foreground)] text-[var(--background)]" : "bg-[var(--muted)] text-[var(--muted-foreground)]"}`}>{counts[t.id]}</span>
            {active && <span className="absolute left-0 right-0 bottom-0 h-[2px] bg-[var(--foreground)]"></span>}
          </button>
        );
      })}
    </div>
  );
};

const PaymentRow = ({ p, selected, onToggle }) => {
  const dateField = p.sentAt || p.voidedAt || p.scheduledFor;
  const dateLabel = p.sentAt ? "sent" : p.voidedAt ? "voided" : "scheduled";
  return (
    <tr className={`group border-b border-[var(--border)] hover:bg-[var(--accent)] transition-colors ${selected ? "bg-[var(--accent)]" : ""}`}>
      <td className="pl-4 pr-2 py-3 w-10">
        <RowCheckbox checked={selected} onChange={() => onToggle(p.id)} ariaLabel={`Select payment ${p.invoiceNumber}`} />
      </td>
      <td className="px-4 py-3 max-w-[240px]">
        <div className={`text-sm truncate ${p.status === "voided" ? "line-through text-[var(--muted-foreground)]" : ""}`} title={p.counterparty}>{p.counterparty}</div>
        {p.iban && <div className="font-mono text-[11px] text-[var(--muted-foreground)] truncate">{p.iban}</div>}
      </td>
      <td className="px-4 py-3">
        <span className="font-mono text-xs text-[var(--foreground)]">{p.invoiceNumber}</span>
      </td>
      <td className="px-4 py-3 max-w-[200px]">
        <div className="font-mono text-[11px] text-[var(--muted-foreground)] truncate" title={p.reference}>{p.reference}</div>
        {p.voidReason && <div className="text-[10px] text-[var(--muted-foreground)] truncate italic" title={p.voidReason}>{p.voidReason}</div>}
      </td>
      <td className={`px-4 py-3 text-right font-mono text-sm tabular-nums whitespace-nowrap ${p.status === "voided" ? "line-through text-[var(--muted-foreground)]" : ""}`}>
        {p.amount}
        <span className="text-[var(--muted-foreground)] text-xs ml-1">{p.currency}</span>
      </td>
      <td className="px-4 py-3 font-mono text-xs text-[var(--muted-foreground)] whitespace-nowrap">
        <span className="block">{dateField}</span>
        <span className="block text-[10px] uppercase tracking-wide mt-0.5 opacity-60">{dateLabel}</span>
      </td>
      <td className="px-4 py-3"><PaymentStatusBadge status={p.status} /></td>
      <td className="px-2 py-3 text-right">
        {p.status === "pending" && <Button variant="ghost" size="sm"><Icon name="x-mark" size={12} /> Void</Button>}
      </td>
    </tr>
  );
};

// Build CSV text for the selected rows
const paymentsToCsv = (rows) => {
  const header = ["ID", "Status", "Counterparty", "IBAN", "Invoice", "Reference", "Amount", "Currency", "Scheduled for", "Sent at"];
  const escape = (v) => {
    if (v == null) return "";
    const s = String(v);
    return /[",\n]/.test(s) ? `"${s.replace(/"/g, '""')}"` : s;
  };
  const lines = [header.join(",")];
  rows.forEach(p => {
    lines.push([p.id, p.status, p.counterparty, p.iban, p.invoiceNumber, p.reference,
      p.amount.replace(/\s/g, ""), p.currency, p.scheduledFor || "", p.sentAt || ""].map(escape).join(","));
  });
  return lines.join("\n");
};

const downloadCsv = (csv, filename) => {
  const blob = new Blob([csv], { type: "text/csv;charset=utf-8" });
  const url = URL.createObjectURL(blob);
  const a = document.createElement("a");
  a.href = url; a.download = filename;
  document.body.appendChild(a); a.click(); a.remove();
  setTimeout(() => URL.revokeObjectURL(url), 1000);
};

const Payments = () => {
  const [status, setStatus] = React.useState("all");
  const [data, setData] = React.useState(PAYMENT_REQUESTS);
  const [selected, setSelected] = React.useState(() => new Set());
  const [toast, setToast] = React.useState(null);

  const filtered = data.filter(p => {
    if (status !== "all" && p.status !== status) return false;
    return true;
  });

  // Drop selections that are no longer visible when tab changes
  React.useEffect(() => {
    setSelected(prev => {
      const visibleIds = new Set(filtered.map(p => p.id));
      const next = new Set();
      prev.forEach(id => { if (visibleIds.has(id)) next.add(id); });
      return next;
    });
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [status]);

  const toggleOne = (id) => setSelected(prev => {
    const next = new Set(prev);
    next.has(id) ? next.delete(id) : next.add(id);
    return next;
  });

  const visibleIds = filtered.map(p => p.id);
  const allVisibleSelected = visibleIds.length > 0 && visibleIds.every(id => selected.has(id));
  const someVisibleSelected = visibleIds.some(id => selected.has(id)) && !allVisibleSelected;

  const toggleAll = (checked) => {
    setSelected(prev => {
      const next = new Set(prev);
      if (checked) visibleIds.forEach(id => next.add(id));
      else visibleIds.forEach(id => next.delete(id));
      return next;
    });
  };

  const selectedRows = data.filter(p => selected.has(p.id));
  const selectedPending = selectedRows.filter(p => p.status === "pending");

  const handleExport = () => {
    const rows = selectedRows.length ? selectedRows : filtered;
    if (!rows.length) return;
    const csv = paymentsToCsv(rows);
    const stamp = new Date().toISOString().slice(0, 10);
    downloadCsv(csv, `payment-requests-${stamp}.csv`);
    setToast({ kind: "success", msg: `Exported ${rows.length} payment${rows.length === 1 ? "" : "s"} to CSV` });
  };

  const handleMarkPaid = () => {
    if (!selectedPending.length) return;
    const now = new Date();
    const stamp = now.toISOString().slice(0, 16).replace("T", " ") + " UTC";
    const ids = new Set(selectedPending.map(p => p.id));
    setData(prev => prev.map(p => ids.has(p.id) ? { ...p, status: "sent", sentAt: stamp } : p));
    setSelected(new Set());
    setToast({ kind: "success", msg: `Marked ${selectedPending.length} payment${selectedPending.length === 1 ? "" : "s"} as paid` });
  };

  React.useEffect(() => {
    if (!toast) return;
    const t = setTimeout(() => setToast(null), 3200);
    return () => clearTimeout(t);
  }, [toast]);

  const pendingTotal = data
    .filter(p => p.status === "pending" && p.currency === "PLN")
    .reduce((s, p) => s + parseFloat(p.amount.replace(/\s/g, "")), 0);
  const pendingCount = data.filter(p => p.status === "pending").length;
  const sentMTDTotal = data
    .filter(p => p.status === "sent" && p.currency === "PLN")
    .reduce((s, p) => s + parseFloat(p.amount.replace(/\s/g, "")), 0);

  const selectedCount = selected.size;
  const selectedTotalsByCurrency = selectedRows.reduce((acc, p) => {
    acc[p.currency] = (acc[p.currency] || 0) + parseFloat(p.amount.replace(/\s/g, ""));
    return acc;
  }, {});

  return (
    <div>
      <PageHeader title="Payments"
        subtitle="Transfer requests generated from approved expenses"
        actions={
          <>
            <Button variant="outline" onClick={handleExport}><Icon name="download" size={14} /> Export CSV</Button>
            <Button variant="primary"><Icon name="plus" size={14} /> New payment</Button>
          </>
        } />

      <div className="grid grid-cols-1 sm:grid-cols-3 gap-3 mb-5">
        <Card>
          <div className="text-xs text-[var(--muted-foreground)] uppercase tracking-wide">Pending outflow</div>
          <div className="mt-1 text-2xl font-semibold tabular-nums">
            {pendingTotal.toLocaleString("pl-PL", { minimumFractionDigits: 2, maximumFractionDigits: 2 })}
            <span className="text-sm font-mono text-[var(--muted-foreground)] ml-1.5">PLN</span>
          </div>
          <div className="text-xs text-[var(--muted-foreground)] mt-1">{pendingCount} pending payments, PLN only</div>
        </Card>
        <Card>
          <div className="text-xs text-[var(--muted-foreground)] uppercase tracking-wide">Pending count</div>
          <div className="mt-1 text-2xl font-semibold tabular-nums">{pendingCount}</div>
          <div className="text-xs text-[var(--muted-foreground)] mt-1">Awaiting bank transfer</div>
        </Card>
        <Card>
          <div className="text-xs text-[var(--muted-foreground)] uppercase tracking-wide">Sent this month</div>
          <div className="mt-1 text-2xl font-semibold tabular-nums">
            {sentMTDTotal.toLocaleString("pl-PL", { minimumFractionDigits: 2, maximumFractionDigits: 2 })}
            <span className="text-sm font-mono text-[var(--muted-foreground)] ml-1.5">PLN</span>
          </div>
          <div className="text-xs text-[var(--muted-foreground)] mt-1">April 2026</div>
        </Card>
      </div>

      <StatusTabs value={status} onChange={setStatus} data={data} />

      <div className="rounded-lg border border-[var(--border)] overflow-hidden bg-[var(--card)]">
        {/* Bulk action bar */}
        {selectedCount > 0 && (
          <div className="flex items-center justify-between px-4 py-2.5 bg-[var(--foreground)] text-[var(--background)] border-b border-[var(--border)]">
            <div className="flex items-center gap-3 text-sm">
              <span className="font-medium tabular-nums">{selectedCount} selected</span>
              <span className="opacity-60">·</span>
              <span className="font-mono text-xs tabular-nums opacity-80">
                {Object.entries(selectedTotalsByCurrency).map(([cur, total], i) => (
                  <span key={cur}>
                    {i > 0 && <span className="mx-1 opacity-50">·</span>}
                    {total.toLocaleString("pl-PL", { minimumFractionDigits: 2, maximumFractionDigits: 2 })} {cur}
                  </span>
                ))}
              </span>
              {selectedPending.length < selectedCount && (
                <span className="text-xs opacity-70">
                  · {selectedPending.length} of {selectedCount} can be marked paid
                </span>
              )}
            </div>
            <div className="flex items-center gap-2">
              <button onClick={handleExport}
                className="inline-flex items-center gap-1.5 h-7 px-2.5 text-xs rounded-md bg-[var(--background)]/10 hover:bg-[var(--background)]/20 text-[var(--background)] transition-colors cursor-pointer">
                <Icon name="download" size={12} /> Download CSV
              </button>
              <button onClick={handleMarkPaid}
                disabled={selectedPending.length === 0}
                className="inline-flex items-center gap-1.5 h-7 px-2.5 text-xs rounded-md bg-[var(--background)] text-[var(--foreground)] hover:opacity-90 transition-opacity cursor-pointer disabled:opacity-40 disabled:cursor-not-allowed">
                <Icon name="check" size={12} /> Mark as paid
              </button>
              <button onClick={() => setSelected(new Set())}
                className="inline-flex items-center h-7 px-2 text-xs rounded-md hover:bg-[var(--background)]/10 transition-colors cursor-pointer opacity-80">
                Clear
              </button>
            </div>
          </div>
        )}

        <div className="overflow-x-auto">
          <table className="w-full text-left">
            <thead className="bg-[var(--muted)]/50 border-b border-[var(--border)]">
              <tr className="text-xs uppercase tracking-wide text-[var(--muted-foreground)]">
                <th className="pl-4 pr-2 py-2.5 w-10">
                  <RowCheckbox checked={allVisibleSelected} indeterminate={someVisibleSelected}
                    onChange={toggleAll} ariaLabel="Select all visible payments" />
                </th>
                <th className="px-4 py-2.5 font-medium w-[240px]">Counterparty</th>
                <th className="px-4 py-2.5 font-medium">Invoice</th>
                <th className="px-4 py-2.5 font-medium">Reference</th>
                <th className="px-4 py-2.5 font-medium text-right">Amount</th>
                <th className="px-4 py-2.5 font-medium">Date</th>
                <th className="px-4 py-2.5 font-medium">Status</th>
                <th />
              </tr>
            </thead>
            <tbody>
              {filtered.length === 0 ? (
                <tr><td colSpan={8} className="px-4 py-12 text-center text-sm text-[var(--muted-foreground)]">No data for selected period</td></tr>
              ) : filtered.map(p => (
                <PaymentRow key={p.id} p={p} selected={selected.has(p.id)} onToggle={toggleOne} />
              ))}
            </tbody>
          </table>
        </div>
        <div className="flex items-center justify-between px-4 py-2.5 border-t border-[var(--border)] text-xs text-[var(--muted-foreground)]">
          <span>Showing 1-{filtered.length} of {filtered.length} payments</span>
          <div className="flex items-center gap-1">
            <Button variant="ghost" size="sm" disabled>Previous</Button>
            <span className="px-2">Page 1 of 1</span>
            <Button variant="ghost" size="sm" disabled>Next</Button>
          </div>
        </div>
      </div>

      {/* Toast */}
      {toast && (
        <div className="fixed bottom-6 right-6 z-50 flex items-center gap-2 px-3.5 py-2.5 rounded-lg shadow-lg border border-[var(--border)] bg-[var(--card)] text-sm">
          <Icon name={toast.kind === "success" ? "check-circle" : "info"} size={14} />
          <span>{toast.msg}</span>
        </div>
      )}
    </div>
  );
};

Object.assign(window, { Payments, PAYMENT_REQUESTS });
