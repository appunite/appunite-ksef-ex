// InvoiceDetail — 3-pane layout: sticky preview (left), metadata stack (right),
// tabs strip below (Line items / Payments / Activity / Notes / Comments / Access).
// Mirrors lib/ksef_hub_web/live/invoice_live/show.ex but expanded to host the new
// tabbed feature set. Uses primitives + badges from Primitives.jsx / InvoicesList.jsx.

// --- shared helpers ---------------------------------------------------------

const Banner = ({ variant = "info", icon = "info", title, children, actions }) => {
  const styles = {
    info: "bg-[color-mix(in_oklch,var(--info)_8%,transparent)] border-[color-mix(in_oklch,var(--info)_25%,transparent)] text-[var(--info)]",
    warning: "bg-[color-mix(in_oklch,var(--warning)_10%,transparent)] border-[color-mix(in_oklch,var(--warning)_30%,transparent)]",
    error: "bg-[color-mix(in_oklch,var(--destructive)_8%,transparent)] border-[color-mix(in_oklch,var(--destructive)_25%,transparent)] text-[var(--destructive)]",
    purple: "bg-[color-mix(in_oklch,var(--purple)_8%,transparent)] border-[color-mix(in_oklch,var(--purple)_25%,transparent)] text-[var(--purple)]",
  };
  return (
    <div className={`flex items-start gap-3 p-4 rounded-lg border ${styles[variant]}`}>
      <Icon name={icon} size={18} className="mt-0.5 flex-none" />
      <div className="flex-1 min-w-0 text-[var(--foreground)]">
        {title && <div className="font-medium text-sm mb-0.5">{title}</div>}
        <div className="text-sm text-[var(--muted-foreground)]">{children}</div>
      </div>
      {actions && <div className="flex-none flex gap-2">{actions}</div>}
    </div>
  );
};

const DetailRow = ({ label, children, mono }) => (
  <div className="flex items-baseline gap-4 py-2.5 border-b border-[var(--border)] last:border-b-0">
    <dt className="text-xs text-[var(--muted-foreground)] w-28 flex-none uppercase tracking-wide font-medium">{label}</dt>
    <dd className={`text-sm min-w-0 flex-1 ${mono ? "font-mono" : ""} text-[var(--foreground)]`}>{children}</dd>
  </div>
);

const Avatar = ({ initials, size = 32, tone = "muted" }) => {
  const tones = {
    muted: "bg-[var(--muted)] text-[var(--muted-foreground)]",
    info: "bg-[color-mix(in_oklch,var(--info)_12%,transparent)] text-[var(--info)]",
    purple: "bg-[color-mix(in_oklch,var(--purple)_14%,transparent)] text-[var(--purple)]",
    success: "bg-[color-mix(in_oklch,var(--success)_12%,transparent)] text-[var(--success)]",
    warning: "bg-[color-mix(in_oklch,var(--warning)_14%,transparent)] text-[var(--warning)]",
  };
  return (
    <span
      className={`inline-flex items-center justify-center rounded-full font-medium shrink-0 ${tones[tone]}`}
      style={{ width: size, height: size, fontSize: Math.max(10, Math.floor(size * 0.38)) }}>
      {initials}
    </span>
  );
};

// deterministic tone from a string, so each person gets a stable color
const toneFor = (key) => {
  const tones = ["info", "purple", "success", "warning", "muted"];
  let h = 0;
  for (const c of key || "") h = (h * 31 + c.charCodeAt(0)) >>> 0;
  return tones[h % tones.length];
};

// --- preview pane -----------------------------------------------------------

const PreviewPane = ({ inv }) => (
  <div className="rounded-xl border border-[var(--border)] bg-[var(--card)] overflow-hidden sticky top-4 flex flex-col"
       style={{ height: "calc(100vh - 2rem)" }}>
    {/* preview toolbar */}
    <div className="flex items-center justify-between gap-2 px-3 h-11 border-b border-[var(--border)] bg-[var(--muted)]/30">
      <div className="flex items-center gap-2 min-w-0">
        <Icon name="document-text" size={14} className="text-[var(--muted-foreground)]" />
        <span className="text-xs font-mono truncate">{inv.number}.pdf</span>
        <span className="text-xs text-[var(--muted-foreground)] font-mono">· 1 of 1</span>
      </div>
      <div className="flex items-center gap-1">
        <button className="inline-flex items-center justify-center w-7 h-7 rounded hover:bg-[var(--accent)] text-[var(--muted-foreground)] cursor-pointer" aria-label="Zoom out"><Icon name="zoom-out" size={14} /></button>
        <span className="text-xs font-mono text-[var(--muted-foreground)] w-10 text-center">100%</span>
        <button className="inline-flex items-center justify-center w-7 h-7 rounded hover:bg-[var(--accent)] text-[var(--muted-foreground)] cursor-pointer" aria-label="Zoom in"><Icon name="zoom-in" size={14} /></button>
        <div className="w-px h-5 bg-[var(--border)] mx-1"></div>
        <button className="inline-flex items-center justify-center w-7 h-7 rounded hover:bg-[var(--accent)] text-[var(--muted-foreground)] cursor-pointer" aria-label="Open full screen"><Icon name="expand" size={14} /></button>
        <button className="inline-flex items-center justify-center w-7 h-7 rounded hover:bg-[var(--accent)] text-[var(--muted-foreground)] cursor-pointer" aria-label="Download PDF"><Icon name="download" size={14} /></button>
      </div>
    </div>
    {/* placeholder page */}
    <div className="flex-1 overflow-auto bg-[var(--muted)]/40 p-6 flex items-start justify-center">
      <div className="w-full max-w-md bg-white text-neutral-900 shadow-sm rounded-sm border border-neutral-200 aspect-[1/1.414] p-8 flex flex-col gap-5 text-[10px] leading-relaxed">
        <div className="flex items-start justify-between gap-4 pb-3 border-b border-neutral-300">
          <div>
            <div className="text-[9px] uppercase tracking-widest text-neutral-500">Invoice</div>
            <div className="font-mono text-[13px] font-semibold mt-1">{inv.number}</div>
          </div>
          <div className="text-right">
            <div className="font-semibold">{inv.seller}</div>
            <div className="font-mono text-neutral-500">{inv.nip || "—"}</div>
          </div>
        </div>
        <div className="grid grid-cols-2 gap-4">
          <div>
            <div className="text-[9px] uppercase tracking-widest text-neutral-500 mb-1">Bill to</div>
            <div className="font-medium">Appunite sp. z o.o.</div>
            <div className="font-mono text-neutral-500">PL9721241997</div>
            <div className="text-neutral-500 mt-0.5">ul. Wąska 1, Poznań</div>
          </div>
          <div>
            <div className="text-[9px] uppercase tracking-widest text-neutral-500 mb-1">Issued</div>
            <div className="font-mono">{inv.date}</div>
            <div className="text-[9px] uppercase tracking-widest text-neutral-500 mt-2 mb-1">Due</div>
            <div className="font-mono">{inv.date}</div>
          </div>
        </div>
        <table className="w-full text-[10px] mt-1">
          <thead>
            <tr className="border-y border-neutral-300 text-neutral-500">
              <th className="text-left font-medium py-1.5">Description</th>
              <th className="text-right font-medium">Qty</th>
              <th className="text-right font-medium">Netto</th>
              <th className="text-right font-medium">Brutto</th>
            </tr>
          </thead>
          <tbody className="font-mono">
            <tr className="border-b border-neutral-200">
              <td className="py-2 font-sans">Monthly subscription · Pro plan</td>
              <td className="text-right">1</td>
              <td className="text-right">{inv.netto}</td>
              <td className="text-right">{inv.brutto}</td>
            </tr>
          </tbody>
        </table>
        <div className="ml-auto w-44 text-right space-y-1 font-mono">
          <div className="flex justify-between text-neutral-500"><span>Netto</span><span>{inv.netto} {inv.currency}</span></div>
          <div className="flex justify-between text-neutral-500"><span>VAT</span><span>0.00 {inv.currency}</span></div>
          <div className="flex justify-between border-t border-neutral-300 pt-1 font-semibold text-[11px]"><span>Brutto</span><span>{inv.brutto} {inv.currency}</span></div>
        </div>
        <div className="mt-auto pt-4 text-[9px] text-neutral-400 border-t border-neutral-200">
          Thank you for your business · Powered by KSeF
        </div>
      </div>
    </div>
  </div>
);

// --- metadata pane ----------------------------------------------------------

const MetaPane = ({ inv }) => (
  <div className="space-y-4">
    <Card padding="p-5">
      <h2 className="text-xs font-semibold uppercase tracking-wide text-[var(--muted-foreground)] mb-3">Details</h2>
      <dl>
        <DetailRow label="Seller">
          <div className="truncate">{inv.seller}</div>
          <div className="text-xs text-[var(--muted-foreground)] font-mono mt-0.5">{inv.nip || "—"}</div>
        </DetailRow>
        <DetailRow label="Buyer">
          <div>Appunite sp. z o.o.</div>
          <div className="text-xs text-[var(--muted-foreground)] font-mono mt-0.5">PL9721241997</div>
        </DetailRow>
        <DetailRow label="Issued" mono>{inv.date}</DetailRow>
        <DetailRow label="KSeF #" mono>
          <span className="text-xs break-all">{inv.ksef || "— not in KSeF —"}</span>
        </DetailRow>
        <DetailRow label="Netto" mono>{inv.netto} {inv.currency}</DetailRow>
        <DetailRow label="VAT" mono>0.00 {inv.currency}</DetailRow>
        <DetailRow label="Brutto">
          <span className="font-mono font-bold">{inv.brutto} {inv.currency}</span>
        </DetailRow>
      </dl>
    </Card>

    <Card padding="p-5">
      <h2 className="text-xs font-semibold uppercase tracking-wide text-[var(--muted-foreground)] mb-3">Classification</h2>
      <div className="mb-4">
        <div className="text-[11px] text-[var(--muted-foreground)] mb-1.5">Category</div>
        {inv.category ? (
          <div className="flex items-center justify-between gap-2">
            <span className="inline-flex items-center gap-2 text-sm">
              <span className="text-lg leading-none">{inv.category.emoji}</span>
              <span>{inv.category.name}</span>
            </span>
            {inv.predicted && (
              <Badge variant="info" className="font-mono">
                predicted · {Math.round(inv.confidence * 100)}%
              </Badge>
            )}
          </div>
        ) : (
          <div className="text-sm text-[var(--muted-foreground)]">Not assigned</div>
        )}
      </div>
      <div>
        <div className="text-[11px] text-[var(--muted-foreground)] mb-1.5">Tags</div>
        <div className="flex flex-wrap gap-1.5">
          {(inv.tags || []).map(t => (
            <Badge key={t} variant="muted">{t}</Badge>
          ))}
          <button className="inline-flex items-center gap-1 h-6 px-2 rounded border border-dashed border-[var(--border)] text-[11px] text-[var(--muted-foreground)] hover:text-[var(--foreground)] hover:border-[var(--foreground)] cursor-pointer">
            <Icon name="plus" size={10} /> add
          </button>
        </div>
      </div>
    </Card>

    <Card padding="p-5">
      <h2 className="text-xs font-semibold uppercase tracking-wide text-[var(--muted-foreground)] mb-3">Sync</h2>
      <dl className="text-xs space-y-2">
        <div className="flex justify-between">
          <dt className="text-[var(--muted-foreground)]">Source</dt>
          <dd className="font-mono">{inv.source ? inv.source : "KSeF (live)"}</dd>
        </div>
        <div className="flex justify-between">
          <dt className="text-[var(--muted-foreground)]">Fetched</dt>
          <dd className="font-mono">2026-04-14 09:02 UTC</dd>
        </div>
        <div className="flex justify-between">
          <dt className="text-[var(--muted-foreground)]">XAdES</dt>
          <dd className="inline-flex items-center gap-1 text-[var(--success)]">
            <Icon name="check" size={12} /> verified
          </dd>
        </div>
        <div className="flex justify-between">
          <dt className="text-[var(--muted-foreground)]">Extraction</dt>
          <dd className={inv.extraction === "complete" ? "text-[var(--success)]" : inv.extraction === "failed" ? "text-[var(--destructive)]" : "text-[var(--warning)]"}>
            {inv.extraction}
          </dd>
        </div>
      </dl>
      <div className="border-t border-[var(--border)] mt-3 pt-3 flex gap-2">
        <Button variant="outline" size="sm" className="flex-1"><Icon name="download" size={12} /> XML</Button>
        <Button variant="outline" size="sm" className="flex-1"><Icon name="download" size={12} /> PDF</Button>
      </div>
    </Card>
  </div>
);

// --- tab strip --------------------------------------------------------------

const TabStrip = ({ value, onChange, tabs }) => (
  <div className="mb-5 border-b border-[var(--border)] flex items-center gap-0 overflow-x-auto">
    {tabs.map(t => {
      const active = value === t.id;
      return (
        <button key={t.id} onClick={() => onChange(t.id)}
          className={`relative -mb-px h-10 px-4 text-sm cursor-pointer transition-colors flex items-center gap-2 whitespace-nowrap ${active ? "text-[var(--foreground)] font-medium" : "text-[var(--muted-foreground)] hover:text-[var(--foreground)]"}`}>
          {t.label}
          <span className={`inline-flex items-center justify-center min-w-[20px] h-[18px] px-1 rounded text-[11px] font-mono tabular-nums ${active ? "bg-[var(--foreground)] text-[var(--background)]" : "bg-[var(--muted)] text-[var(--muted-foreground)]"}`}>{t.count}</span>
          {active && <span className="absolute left-0 right-0 bottom-0 h-[2px] bg-[var(--foreground)]"></span>}
        </button>
      );
    })}
  </div>
);

// --- tab: line items --------------------------------------------------------

const LineItemsTab = ({ inv }) => {
  if (inv.extraction === "failed") {
    return (
      <Card padding="p-0">
        <EmptyState
          tone="warning"
          icon="warning"
          title="Line items couldn’t be extracted"
          sub="The OCR run for this invoice failed. Retry extraction or enter items manually."
          action={<div className="flex gap-2">
            <Button variant="outline" size="sm"><Icon name="sync" size={12} /> Retry extraction</Button>
            <Button variant="primary" size="sm"><Icon name="plus" size={12} /> Enter manually</Button>
          </div>}
        />
      </Card>
    );
  }
  return (
  <Card padding="p-0">
    <table className="w-full text-sm">
      <thead>
        <tr className="text-xs uppercase tracking-wide text-[var(--muted-foreground)] border-b border-[var(--border)]">
          <th className="text-left font-medium py-3 pl-5">Description</th>
          <th className="text-right font-medium py-3 w-16">Qty</th>
          <th className="text-right font-medium py-3 w-28">Netto</th>
          <th className="text-right font-medium py-3 w-20">VAT %</th>
          <th className="text-right font-medium py-3 w-28 pr-5">Brutto</th>
        </tr>
      </thead>
      <tbody>
        <tr className="border-b border-[var(--border)]">
          <td className="py-3 pl-5">Monthly subscription · Pro plan</td>
          <td className="text-right font-mono">1</td>
          <td className="text-right font-mono">{inv.netto}</td>
          <td className="text-right font-mono text-[var(--muted-foreground)]">0%</td>
          <td className="text-right font-mono font-semibold pr-5">{inv.brutto}</td>
        </tr>
        <tr className="bg-[var(--muted)]/40">
          <td className="py-3 pl-5 text-xs uppercase tracking-wide text-[var(--muted-foreground)] font-medium">Total</td>
          <td></td>
          <td className="text-right font-mono">{inv.netto}</td>
          <td className="text-right font-mono text-[var(--muted-foreground)]">—</td>
          <td className="text-right font-mono font-bold pr-5">{inv.brutto} {inv.currency}</td>
        </tr>
      </tbody>
    </table>
  </Card>
  );
};

// --- tab: payments ----------------------------------------------------------

const PaymentsTab = ({ inv }) => {
  const rows = (window.DETAIL_PAYMENTS[inv.id] || window.DETAIL_PAYMENTS.default) || [];
  // Payments don’t apply to income invoices or rejected expenses.
  if (inv.type === "income" || inv.status === "rejected") {
    return (
      <Card padding="p-0">
        <EmptyState
          tone="locked"
          icon="lock"
          title="Payments don’t apply here"
          sub={inv.type === "income"
            ? "Income invoices don’t generate outgoing transfers."
            : "Rejected invoices don’t generate outgoing transfers."}
        />
      </Card>
    );
  }
  if (rows.length === 0) {
    return (
      <Card padding="p-0">
        <EmptyState
          icon="banknotes"
          title="No payment requests yet"
          sub="Create one to schedule an outgoing transfer for this invoice."
          action={<Button variant="primary" size="sm"><Icon name="plus" size={12} /> Create payment</Button>}
        />
      </Card>
    );
  }
  return (
    <Card padding="p-0">
      <table className="w-full text-sm">
        <thead>
          <tr className="text-xs uppercase tracking-wide text-[var(--muted-foreground)] border-b border-[var(--border)]">
            <th className="text-left font-medium py-3 pl-5">Counterparty</th>
            <th className="text-right font-medium py-3 w-32">Amount</th>
            <th className="text-left font-medium py-3 w-40">Date</th>
            <th className="text-left font-medium py-3 w-28">Status</th>
            <th className="py-3 pr-5 w-10"></th>
          </tr>
        </thead>
        <tbody>
          {rows.map(r => {
            const dateLabel = r.sentAt ? "sent" : r.voidedAt ? "voided" : "scheduled";
            const dateValue = r.sentAt || r.voidedAt || r.scheduledFor;
            return (
              <tr key={r.id} className="border-b border-[var(--border)] last:border-b-0 hover:bg-[var(--accent)]">
                <td className="py-3 pl-5">
                  <div className="text-sm">{r.counterparty}</div>
                  <div className="text-[11px] font-mono text-[var(--muted-foreground)]">{r.id}</div>
                </td>
                <td className="text-right font-mono">{r.amount} {r.currency}</td>
                <td className="py-3">
                  <div className="text-xs text-[var(--muted-foreground)] uppercase tracking-wide">{dateLabel}</div>
                  <div className="font-mono text-xs">{dateValue}</div>
                </td>
                <td>
                  {r.status === "sent" && <Badge variant="success">sent</Badge>}
                  {r.status === "pending" && <Badge variant="info">pending</Badge>}
                  {r.status === "voided" && <Badge variant="muted">voided</Badge>}
                </td>
                <td className="pr-5 text-right">
                  <button className="inline-flex items-center justify-center w-7 h-7 rounded hover:bg-[var(--muted)] text-[var(--muted-foreground)] cursor-pointer" aria-label="Open">
                    <Icon name="chevron-right" size={14} />
                  </button>
                </td>
              </tr>
            );
          })}
        </tbody>
      </table>
    </Card>
  );
};

// --- tab: activity ----------------------------------------------------------

const ACTIVITY_ICON = {
  "arrow-path": { icon: "sync", tone: "muted" },
  "bolt": { icon: "sparkles", tone: "info" },
  "check": { icon: "check", tone: "success" },
  "cog": { icon: "cog", tone: "muted" },
  "duplicate": { icon: "duplicate", tone: "warning" },
  "warning": { icon: "warning", tone: "warning" },
  "error": { icon: "error", tone: "error" },
  "info": { icon: "info", tone: "muted" },
};

const ActivityTab = ({ inv }) => {
  const entries = window.DETAIL_ACTIVITY[inv.id] || window.DETAIL_ACTIVITY.default;
  return (
    <Card padding="p-6">
      <ol className="relative">
        {entries.map((e, i) => {
          const meta = ACTIVITY_ICON[e.icon] || { icon: "info", tone: "muted" };
          const toneColor = {
            muted: "bg-[var(--muted)] text-[var(--muted-foreground)] border-[var(--border)]",
            info: "bg-[color-mix(in_oklch,var(--info)_10%,transparent)] text-[var(--info)] border-[color-mix(in_oklch,var(--info)_25%,transparent)]",
            success: "bg-[color-mix(in_oklch,var(--success)_10%,transparent)] text-[var(--success)] border-[color-mix(in_oklch,var(--success)_25%,transparent)]",
            warning: "bg-[color-mix(in_oklch,var(--warning)_12%,transparent)] text-[var(--warning)] border-[color-mix(in_oklch,var(--warning)_30%,transparent)]",
            error: "bg-[color-mix(in_oklch,var(--destructive)_8%,transparent)] text-[var(--destructive)] border-[color-mix(in_oklch,var(--destructive)_25%,transparent)]",
          }[meta.tone];
          const isLast = i === entries.length - 1;
          return (
            <li key={e.id} className="relative flex gap-4 pb-5 last:pb-0">
              {!isLast && <span aria-hidden className="absolute left-[14px] top-8 bottom-0 w-px bg-[var(--border)]"></span>}
              <span className={`relative z-10 inline-flex items-center justify-center w-7 h-7 rounded-full border ${toneColor} shrink-0`}>
                <Icon name={meta.icon} size={13} />
              </span>
              <div className="flex-1 min-w-0 pt-0.5">
                <div className="text-sm text-[var(--foreground)]">
                  <span className="font-medium">{e.actor}</span>
                  <span className="text-[var(--muted-foreground)]"> · {e.verb}</span>
                </div>
                <div className="text-[11px] font-mono text-[var(--muted-foreground)] mt-0.5">{e.ts}</div>
              </div>
            </li>
          );
        })}
      </ol>
    </Card>
  );
};

// --- tab: notes -------------------------------------------------------------

const NotesTab = ({ inv }) => {
  const notes = inv.id in window.DETAIL_NOTES ? window.DETAIL_NOTES[inv.id] : window.DETAIL_NOTES.default;
  const [drafting, setDrafting] = React.useState(false);
  const [draft, setDraft] = React.useState("");

  if (notes.length === 0 && !drafting) {
    return (
      <Card padding="p-0">
        <EmptyState
          icon="document-text"
          title="No notes yet"
          sub="Notes are private to your team. Use them to record decisions or context."
          action={<Button variant="primary" size="sm" onClick={() => setDrafting(true)}><Icon name="plus" size={12} /> Add note</Button>}
        />
      </Card>
    );
  }

  return (
    <div className="space-y-3">
      {notes.map(n => (
        <Card key={n.id} padding="p-4" className="group">
          <div className="flex items-start gap-3">
            <Avatar initials={n.initials} size={32} tone={toneFor(n.author)} />
            <div className="flex-1 min-w-0">
              <div className="flex items-center justify-between gap-3 mb-1.5">
                <div className="flex items-baseline gap-2">
                  <span className="text-sm font-medium">{n.author}</span>
                  <span className="text-[11px] font-mono text-[var(--muted-foreground)]">{n.ts}</span>
                </div>
                <div className="opacity-0 group-hover:opacity-100 transition-opacity flex items-center gap-1">
                  <button className="inline-flex items-center justify-center w-7 h-7 rounded hover:bg-[var(--muted)] text-[var(--muted-foreground)] cursor-pointer" aria-label="Edit note"><Icon name="edit" size={13} /></button>
                  <button className="inline-flex items-center justify-center w-7 h-7 rounded hover:bg-[var(--muted)] text-[var(--muted-foreground)] cursor-pointer" aria-label="Delete note"><Icon name="trash" size={13} /></button>
                </div>
              </div>
              <div className="text-sm text-[var(--foreground)] leading-relaxed whitespace-pre-wrap">{n.body}</div>
            </div>
          </div>
        </Card>
      ))}

      {drafting ? (
        <Card padding="p-4">
          <div className="flex items-start gap-3">
            <Avatar initials="OP" size={32} tone="info" />
            <div className="flex-1 min-w-0">
              <textarea
                autoFocus
                value={draft}
                onChange={e => setDraft(e.target.value)}
                placeholder="Write a note… markdown supported"
                className="w-full min-h-[100px] resize-y bg-transparent text-sm leading-relaxed placeholder:text-[var(--muted-foreground)] focus:outline-none"
              />
              <div className="flex items-center justify-end gap-2 mt-2 pt-2 border-t border-[var(--border)]">
                <Button variant="ghost" size="sm" onClick={() => { setDrafting(false); setDraft(""); }}>Cancel</Button>
                <Button variant="primary" size="sm" onClick={() => { setDrafting(false); setDraft(""); }}>Save note</Button>
              </div>
            </div>
          </div>
        </Card>
      ) : (
        <button onClick={() => setDrafting(true)} className="w-full flex items-center justify-center gap-2 h-10 rounded-lg border border-dashed border-[var(--border)] text-sm text-[var(--muted-foreground)] hover:text-[var(--foreground)] hover:border-[var(--foreground)] cursor-pointer transition-colors">
          <Icon name="plus" size={14} /> Add note
        </button>
      )}
    </div>
  );
};

// --- tab: comments ----------------------------------------------------------

const renderCommentBody = (body) =>
  body
    .split(/(@[\w\s.]+?(?=[,\s]|$))/g)
    .filter(part => part !== "")
    .map((part, i) =>
      part.startsWith("@")
        ? <span key={i} className="font-medium text-[var(--info)]">{part}</span>
        : <React.Fragment key={i}>{part}</React.Fragment>
    );

const CommentsTab = ({ inv }) => {
  const lookup = () => inv.id in window.DETAIL_COMMENTS ? window.DETAIL_COMMENTS[inv.id] : window.DETAIL_COMMENTS.default;
  const [comments, setComments] = React.useState(lookup);
  const [text, setText] = React.useState("");
  const composerRef = React.useRef(null);

  React.useEffect(() => {
    setComments(lookup());
  }, [inv.id]);

  const submit = () => {
    if (!text.trim()) return;
    setComments(c => [...c, {
      id: `c${Date.now()}`,
      author: "You",
      initials: "OP",
      ts: new Date().toLocaleTimeString([], { hour: "2-digit", minute: "2-digit" }),
      body: text.trim(),
      ownMine: true,
    }]);
    setText("");
  };

  return (
    <Card padding="p-0" className="flex flex-col" >
      {comments.length === 0 ? (
        <EmptyState
          icon="chat"
          title="Start the conversation"
          sub="@mention a teammate to pull them into this invoice."
          action={<Button variant="outline" size="sm" onClick={() => composerRef.current?.focus()}>Write a comment</Button>}
        />
      ) : (
        <div className="px-5 py-4 space-y-4 max-h-[520px] overflow-y-auto">
        {comments.map(c => {
          const mine = c.ownMine;
          return (
            <div key={c.id} className={`flex items-start gap-3 ${mine ? "flex-row-reverse" : ""}`}>
              <Avatar initials={c.initials} size={28} tone={mine ? "info" : toneFor(c.author)} />
              <div className={`min-w-0 max-w-[75%] ${mine ? "items-end text-right" : ""} flex flex-col`}>
                <div className={`flex items-baseline gap-2 mb-1 ${mine ? "flex-row-reverse" : ""}`}>
                  <span className="text-xs font-medium">{c.author}</span>
                  <span className="text-[10px] font-mono text-[var(--muted-foreground)]">{c.ts}</span>
                </div>
                <div className={`inline-block text-sm leading-relaxed rounded-2xl px-3.5 py-2 ${mine
                  ? "bg-[var(--foreground)] text-[var(--background)] rounded-tr-sm"
                  : "bg-[var(--muted)] text-[var(--foreground)] rounded-tl-sm"}`}
                >
                  {renderCommentBody(c.body)}
                </div>
              </div>
            </div>
          );
        })}
        </div>
      )}
      <div className="border-t border-[var(--border)] bg-[var(--card)] px-3 py-3 flex items-end gap-2 sticky bottom-0">
        <Avatar initials="OP" size={28} tone="info" />
        <textarea
          ref={composerRef}
          value={text}
          onChange={e => setText(e.target.value)}
          onKeyDown={e => { if ((e.metaKey || e.ctrlKey) && e.key === "Enter") submit(); }}
          placeholder="Write a comment… @mention to notify"
          rows={1}
          className="flex-1 resize-none bg-[var(--background)] border border-[var(--border)] rounded-lg px-3 py-2 text-sm focus:outline-none focus:ring-1 focus:ring-[var(--ring)] min-h-[38px] max-h-32"
        />
        <Button variant="primary" size="sm" onClick={submit}>Send</Button>
      </div>
    </Card>
  );
};

// --- tab: access ------------------------------------------------------------

const RoleBadge = ({ role }) => {
  const map = {
    approver: { v: "purple", label: "Approver" },
    editor: { v: "info", label: "Editor" },
    viewer: { v: "muted", label: "Viewer" },
  };
  const m = map[role] || map.viewer;
  return <Badge variant={m.v}>{m.label}</Badge>;
};

const AccessTab = ({ inv }) => {
  const users = window.DETAIL_ACCESS.default;
  // When only the owner has access, we consider it a zero-data state.
  if (users.length <= 1) {
    return (
      <Card padding="p-0">
        <EmptyState
          icon="user-plus"
          title="Only you have access"
          sub="Share this invoice with teammates to collaborate on review and approval."
          action={<Button variant="primary" size="sm"><Icon name="user-plus" size={12} /> Grant access</Button>}
        />
      </Card>
    );
  }
  return (
    <div className="space-y-3">
      <Banner variant="info" icon="link" title="Share link disabled"
        actions={<Button variant="outline" size="sm">Create link</Button>}>
        Anyone with access to the link will be able to view this invoice. Links expire after 7 days.
      </Banner>
      <Card padding="p-0">
        <div className="flex items-center justify-between gap-2 px-5 py-3 border-b border-[var(--border)]">
          <div className="text-xs uppercase tracking-wide text-[var(--muted-foreground)] font-medium">{users.length} people have access</div>
          <Button variant="outline" size="sm"><Icon name="user-plus" size={12} /> Grant access</Button>
        </div>
        <table className="w-full text-sm">
          <thead>
            <tr className="text-xs uppercase tracking-wide text-[var(--muted-foreground)] border-b border-[var(--border)]">
              <th className="text-left font-medium py-3 pl-5">User</th>
              <th className="text-left font-medium py-3 w-32">Role</th>
              <th className="text-left font-medium py-3 w-40">Granted by</th>
              <th className="text-left font-medium py-3 w-32">On</th>
              <th className="py-3 pr-5 w-10"></th>
            </tr>
          </thead>
          <tbody>
            {users.map(u => (
              <tr key={u.id} className="border-b border-[var(--border)] last:border-b-0 hover:bg-[var(--accent)] group">
                <td className="py-3 pl-5">
                  <div className="flex items-center gap-3">
                    <Avatar initials={u.initials} size={30} tone={toneFor(u.name)} />
                    <div className="min-w-0">
                      <div className="text-sm truncate">{u.name}</div>
                      <div className="text-[11px] font-mono text-[var(--muted-foreground)] truncate">{u.email}</div>
                    </div>
                  </div>
                </td>
                <td><RoleBadge role={u.role} /></td>
                <td className="text-sm text-[var(--muted-foreground)]">{u.grantedBy}</td>
                <td className="font-mono text-xs text-[var(--muted-foreground)]">{u.grantedOn}</td>
                <td className="pr-5 text-right">
                  <button className="opacity-0 group-hover:opacity-100 inline-flex items-center justify-center w-7 h-7 rounded hover:bg-[var(--muted)] text-[var(--muted-foreground)] hover:text-[var(--destructive)] cursor-pointer transition-opacity" aria-label="Revoke access">
                    <Icon name="trash" size={13} />
                  </button>
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </Card>
    </div>
  );
};

// --- main -------------------------------------------------------------------

const InvoiceDetail = ({ invoice, onBack }) => {
  const inv = invoice;
  const [tab, setTab] = React.useState("activity");

  // Counts feed the tab pills. Respect the Notes/Comments per-invoice override
  // (an empty array is a valid zero-count, not "missing" — so we fall back only
  // on `undefined`).
  const notes = inv.id in window.DETAIL_NOTES ? window.DETAIL_NOTES[inv.id] : window.DETAIL_NOTES.default;
  const comments = inv.id in window.DETAIL_COMMENTS ? window.DETAIL_COMMENTS[inv.id] : window.DETAIL_COMMENTS.default;
  const payments = window.DETAIL_PAYMENTS[inv.id] || [];
  const activity = window.DETAIL_ACTIVITY[inv.id] || window.DETAIL_ACTIVITY.default;
  const access = window.DETAIL_ACCESS.default;

  const counts = {
    "line-items": inv.extraction === "failed" ? 0 : 1,
    payments: payments.length,
    activity: activity.length,
    notes: notes.length,
    comments: comments.length,
    access: access.length,
  };

  const tabs = [
    { id: "line-items", label: "Line items", count: counts["line-items"] },
    { id: "payments", label: "Payments", count: counts.payments },
    { id: "activity", label: "Activity", count: counts.activity },
    { id: "notes", label: "Notes", count: counts.notes },
    { id: "comments", label: "Comments", count: counts.comments },
    { id: "access", label: "Access", count: counts.access },
  ];

  return (
    <div className="space-y-5">
      {/* header */}
      <button onClick={onBack} className="inline-flex items-center gap-1.5 text-sm text-[var(--muted-foreground)] hover:text-[var(--foreground)] cursor-pointer">
        <Icon name="chevron-right" size={14} className="rotate-180" /> Back to invoices
      </button>

      <div className="flex items-start justify-between gap-6 pb-4 border-b border-[var(--border)]">
        <div className="flex items-start gap-3 min-w-0">
          <Icon name="document-text" size={26} className="text-[var(--muted-foreground)] mt-0.5" />
          <div className="min-w-0">
            <h1 className="text-lg font-semibold leading-6 tracking-tight truncate">{inv.number}</h1>
            <div className="mt-1.5 flex items-center gap-2 flex-wrap">
              <TypePill type={inv.type} />
              <KindBadge kind={inv.kind} />
              <StatusBadge status={inv.status} />
              <PaymentBadge status={inv.paymentStatus} />
            </div>
          </div>
        </div>
        <div className="flex gap-2 flex-none">
          {inv.status === "pending" && (
            <>
              <Button variant="outline"><Icon name="error" size={14} /> Reject</Button>
              <Button variant="primary"><Icon name="check" size={14} /> Approve</Button>
            </>
          )}
          {inv.status !== "pending" && (
            <Button variant="outline" size="sm"><Icon name="download" size={12} /> Export</Button>
          )}
        </div>
      </div>

      {/* banners */}
      {(inv.duplicateStatus === "suspected" || inv.kind === "correction") && (
        <div className="space-y-3">
          {inv.duplicateStatus === "suspected" && (
            <Banner variant="warning" icon="duplicate"
              title="This invoice may be a duplicate."
              actions={<>
                <Button variant="outline" size="sm">Not a duplicate</Button>
                <Button variant="destructive" size="sm">Confirm duplicate</Button>
              </>}>
              Predicted with <span className="font-mono">91.4%</span> probability of matching{" "}
              <a href="#" className="underline">FV/2026/01/0014</a>. Same NIP, same brutto, same date —
              reversed sign suggests a correction pair.
            </Banner>
          )}
          {inv.kind === "correction" && (
            <Banner variant="purple" icon="uturn" title="Correction invoice">
              Corrects <a href="#" className="underline">FV/2026/01/0013</a>. Original netto was{" "}
              <span className="font-mono">420.00 PLN</span>; this correction reverses the full amount.
            </Banner>
          )}
        </div>
      )}

      {/* top row: preview (left) + metadata (right) */}
      <div className="grid grid-cols-1 lg:grid-cols-5 gap-5">
        <div className="lg:col-span-3">
          <PreviewPane inv={inv} />
        </div>
        <div className="lg:col-span-2">
          <MetaPane inv={inv} />
        </div>
      </div>

      {/* tab strip + content */}
      <div className="pt-2">
        <TabStrip value={tab} onChange={setTab} tabs={tabs} />
        <div>
          {tab === "line-items" && <LineItemsTab inv={inv} />}
          {tab === "payments" && <PaymentsTab inv={inv} />}
          {tab === "activity" && <ActivityTab inv={inv} />}
          {tab === "notes" && <NotesTab inv={inv} />}
          {tab === "comments" && <CommentsTab inv={inv} />}
          {tab === "access" && <AccessTab inv={inv} />}
        </div>
      </div>
    </div>
  );
};

Object.assign(window, { InvoiceDetail });
