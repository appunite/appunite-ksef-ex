// InvoiceDetail — mirrors lib/ksef_hub_web/live/invoice_live/show.ex
// Back link, banners (duplicate/correction), details table, approve/reject actions

const Banner = ({ variant = "info", icon = "info", title, children, actions }) => {
  const styles = {
    info: "bg-[color-mix(in_oklch,var(--info)_8%,transparent)] border-[color-mix(in_oklch,var(--info)_25%,transparent)] text-[var(--info)]",
    warning: "bg-[color-mix(in_oklch,var(--warning)_10%,transparent)] border-[color-mix(in_oklch,var(--warning)_30%,transparent)]",
    error: "bg-[color-mix(in_oklch,var(--destructive)_8%,transparent)] border-[color-mix(in_oklch,var(--destructive)_25%,transparent)] text-[var(--destructive)]",
    purple: "bg-[color-mix(in_oklch,var(--purple)_8%,transparent)] border-[color-mix(in_oklch,var(--purple)_25%,transparent)] text-[var(--purple)]",
  };
  return (
    <div className={`flex items-start gap-3 p-4 rounded-lg border ${styles[variant]} mb-4`}>
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
    <dt className="text-xs text-[var(--muted-foreground)] w-32 flex-none uppercase tracking-wide font-medium">{label}</dt>
    <dd className={`text-sm ${mono ? "font-mono" : ""} text-[var(--foreground)]`}>{children}</dd>
  </div>
);

const InvoiceDetail = ({ invoice, onBack }) => {
  const inv = invoice;

  return (
    <div className="space-y-6">
      <button onClick={onBack} className="inline-flex items-center gap-1.5 text-sm text-[var(--muted-foreground)] hover:text-[var(--foreground)] cursor-pointer">
        <Icon name="chevron-right" size={14} className="rotate-180" /> Back to invoices
      </button>

      <div className="flex items-center justify-between gap-6 pb-4 border-b border-[var(--border)]">
        <div className="flex items-center gap-3">
          <Icon name="document-text" size={28} className="text-[var(--muted-foreground)]" />
          <div>
            <h1 className="text-lg font-semibold leading-6 tracking-tight">{inv.number}</h1>
            <div className="mt-1 flex items-center gap-2">
              <TypePill type={inv.type} />
              <KindBadge kind={inv.kind} />
              <StatusBadge status={inv.status} />
            </div>
          </div>
        </div>
        <div className="flex gap-2">
          {inv.status === "pending" && (
            <>
              <Button variant="outline"><Icon name="error" size={14} /> Reject</Button>
              <Button variant="primary"><Icon name="check" size={14} /> Approve</Button>
            </>
          )}
          <Button variant="ghost" size="icon"><Icon name="download" size={14} /></Button>
        </div>
      </div>

      {inv.duplicateStatus === "suspected" && (
        <Banner variant="warning" icon="duplicate"
          title="This invoice may be a duplicate."
          actions={<>
            <Button variant="outline" size="sm">Not a duplicate</Button>
            <Button variant="destructive" size="sm">Confirm duplicate</Button>
          </>}>
          Predicted with <span className="font-mono">91.4%</span> probability of matching <a href="#" className="underline">FV/2026/01/0014</a>.
          Same NIP, same brutto, same date — reversed sign suggests a correction pair.
        </Banner>
      )}

      {inv.kind === "correction" && (
        <Banner variant="purple" icon="uturn" title="Correction invoice">
          Corrects <a href="#" className="underline">FV/2026/01/0013</a>. Original netto was
          <span className="font-mono"> 420.00 PLN</span>; this correction reverses the full amount.
        </Banner>
      )}

      <div className="grid grid-cols-1 lg:grid-cols-3 gap-4">
        <div className="lg:col-span-2 space-y-4">
          <Card>
            <h2 className="text-sm font-semibold mb-3">Invoice details</h2>
            <dl>
              <DetailRow label="Seller">
                <div>{inv.seller}</div>
                <div className="text-xs text-[var(--muted-foreground)] font-mono mt-0.5">{inv.nip || "—"}</div>
              </DetailRow>
              <DetailRow label="Buyer">
                <div>Appunite sp. z o.o.</div>
                <div className="text-xs text-[var(--muted-foreground)] font-mono mt-0.5">PL9721241997</div>
              </DetailRow>
              <DetailRow label="Date" mono>{inv.date}</DetailRow>
              <DetailRow label="KSeF number" mono><span className="text-xs">{inv.ksef || "— not in KSeF —"}</span></DetailRow>
              <DetailRow label="Netto" mono>{inv.netto} {inv.currency}</DetailRow>
              <DetailRow label="VAT" mono>0.00 {inv.currency}</DetailRow>
              <DetailRow label="Brutto"><span className="font-mono font-bold">{inv.brutto} {inv.currency}</span></DetailRow>
            </dl>
          </Card>

          <Card>
            <div className="flex items-center justify-between mb-3">
              <h2 className="text-sm font-semibold">Line items</h2>
              <Badge variant="muted">1 item</Badge>
            </div>
            <table className="w-full text-sm">
              <thead>
                <tr className="text-xs uppercase tracking-wide text-[var(--muted-foreground)] border-b border-[var(--border)]">
                  <th className="text-left font-medium py-2">Description</th>
                  <th className="text-right font-medium py-2">Qty</th>
                  <th className="text-right font-medium py-2">Netto</th>
                  <th className="text-right font-medium py-2">VAT</th>
                  <th className="text-right font-medium py-2">Brutto</th>
                </tr>
              </thead>
              <tbody className="font-mono text-xs">
                <tr>
                  <td className="py-2.5 font-sans text-sm">Monthly subscription · Pro plan</td>
                  <td className="text-right">1</td>
                  <td className="text-right">{inv.netto}</td>
                  <td className="text-right">0.00</td>
                  <td className="text-right font-semibold">{inv.brutto}</td>
                </tr>
              </tbody>
            </table>
          </Card>
        </div>

        <div className="space-y-4">
          <Card>
            <h2 className="text-sm font-semibold mb-3">Category</h2>
            {inv.category ? (
              <>
                <div className="flex items-center gap-2 text-sm">
                  <span className="text-xl">{inv.category.emoji}</span>
                  <span>{inv.category.name}</span>
                </div>
                {inv.predicted && (
                  <p className="text-xs text-[var(--muted-foreground)] mt-2">
                    Predicted with <span className="font-mono">{Math.round(inv.confidence * 100)}%</span> probability, feel free to adjust.
                  </p>
                )}
                <Button variant="outline" size="sm" className="mt-3">Change category</Button>
              </>
            ) : (
              <div>
                <p className="text-xs text-[var(--muted-foreground)] mb-2">No category assigned.</p>
                <Button variant="outline" size="sm">Assign</Button>
              </div>
            )}
          </Card>

          <Card>
            <h2 className="text-sm font-semibold mb-3">Sync</h2>
            <dl className="text-xs space-y-2">
              <div className="flex justify-between">
                <dt className="text-[var(--muted-foreground)]">Source</dt>
                <dd className="font-mono">KSeF (live)</dd>
              </div>
              <div className="flex justify-between">
                <dt className="text-[var(--muted-foreground)]">Fetched</dt>
                <dd className="font-mono">2026-01-14 09:02 UTC</dd>
              </div>
              <div className="flex justify-between">
                <dt className="text-[var(--muted-foreground)]">XAdES</dt>
                <dd className="inline-flex items-center gap-1 text-[var(--success)]">
                  <Icon name="check" size={12} /> verified
                </dd>
              </div>
              <div className="flex justify-between">
                <dt className="text-[var(--muted-foreground)]">Extraction</dt>
                <dd className="text-[var(--success)]">complete</dd>
              </div>
            </dl>
            <div className="border-t border-[var(--border)] mt-3 pt-3 flex gap-2">
              <Button variant="outline" size="sm" className="flex-1"><Icon name="download" size={12} /> XML</Button>
              <Button variant="outline" size="sm" className="flex-1"><Icon name="download" size={12} /> PDF</Button>
            </div>
          </Card>
        </div>
      </div>
    </div>
  );
};

Object.assign(window, { InvoiceDetail });
