// Demo data — mirrors the Invoice / SyncJob / Certificate schemas

const COMPANIES = [
  { id: "c1", name: "Appunite sp. z o.o.", nip: "PL9721241997" },
  { id: "c2", name: "Bratnia Sp. j.", nip: "PL5252457316" },
  { id: "c3", name: "Kowalski Consulting", nip: "PL6762563217" },
];

const INVOICES = [
  { id: "i01", number: "FV/2026/04/0142", type: "expense", status: "pending", kind: "vat",
    seller: "Linear B.V.", nip: "NL858058747B01", netto: "89.00", brutto: "89.00", currency: "EUR",
    date: "2026-04-18", ksef: "5252457316-20260418-5A3F0B-142", category: { emoji: "💻", name: "Software" },
    predicted: true, confidence: 0.92, extraction: "complete", duplicateStatus: null },
  { id: "i02", number: "FV/2026/04/0141", type: "expense", status: "approved", kind: "vat",
    seller: "Google Ireland Ltd.", nip: "IE6388047V", netto: "1 240.00", brutto: "1 525.20", currency: "PLN",
    date: "2026-04-17", ksef: "5252457316-20260417-4B1D22-141", category: { emoji: "☁️", name: "Cloud" },
    predicted: true, confidence: 0.88, extraction: "complete", duplicateStatus: null },
  { id: "i03", number: "FV/2026/04/0140", type: "income", status: "approved", kind: "vat",
    seller: "Acme S.A.", nip: "PL1234567890", netto: "18 450.00", brutto: "22 693.50", currency: "PLN",
    date: "2026-04-16", ksef: "9721241997-20260416-91CEF0-140", category: { emoji: "💰", name: "Services" },
    predicted: false, confidence: null, extraction: "complete", duplicateStatus: null },
  { id: "i04", number: "FV/2026/04/0139", type: "expense", status: "pending", kind: "correction",
    seller: "Orange Polska", nip: "PL5260250995", netto: "-420.00", brutto: "-516.60", currency: "PLN",
    date: "2026-04-15", ksef: "5252457316-20260415-7FA8C3-139", category: { emoji: "📱", name: "Telecom" },
    predicted: true, confidence: 0.95, extraction: "complete", duplicateStatus: null },
  { id: "i05", number: "FV/2026/04/0138", type: "expense", status: "pending", kind: "vat",
    seller: "Orange Polska", nip: "PL5260250995", netto: "420.00", brutto: "516.60", currency: "PLN",
    date: "2026-04-15", ksef: null, category: { emoji: "📱", name: "Telecom" },
    predicted: true, confidence: 0.61, extraction: "partial", duplicateStatus: "suspected" },
  { id: "i06", number: "INV-8821", type: "expense", status: "approved", kind: "vat",
    seller: "Stripe Payments Europe", nip: "IE3206488LH", netto: "284.00", brutto: "284.00", currency: "EUR",
    date: "2026-04-14", ksef: null, category: { emoji: "💳", name: "Payments" },
    predicted: true, confidence: 0.94, extraction: "complete", duplicateStatus: null, source: "email" },
  { id: "i07", number: "FV/2026/04/0137", type: "income", status: "approved", kind: "vat",
    seller: "Softly sp. z o.o.", nip: "PL5213870274", netto: "8 200.00", brutto: "10 086.00", currency: "PLN",
    date: "2026-04-14", ksef: "9721241997-20260414-A8C1D2-137", category: { emoji: "💰", name: "Services" },
    predicted: false, confidence: null, extraction: "complete", duplicateStatus: null },
  { id: "i08", number: "FV/2026/04/0136", type: "expense", status: "approved", kind: "vat",
    seller: "Netia S.A.", nip: "PL7340009951", netto: "400.41", brutto: "492.50", currency: "PLN",
    date: "2026-04-13", ksef: "5252457316-20260413-33EE12-136", category: { emoji: "🌐", name: "Internet" },
    predicted: true, confidence: 0.91, extraction: "complete", duplicateStatus: null },
  { id: "i09", number: "2026-0014", type: "expense", status: "pending", kind: "vat",
    seller: "Notion Labs, Inc.", nip: "US82-1840463", netto: "120.00", brutto: "120.00", currency: "USD",
    date: "2026-04-12", ksef: null, category: { emoji: "🧠", name: "Software" },
    predicted: true, confidence: 0.89, extraction: "complete", duplicateStatus: null, source: "upload" },
  { id: "i10", number: "FV/2026/04/0135", type: "expense", status: "approved", kind: "vat",
    seller: "Allegro sp. z o.o.", nip: "PL5272525995", netto: "995.12", brutto: "1 224.00", currency: "PLN",
    date: "2026-04-12", ksef: "5252457316-20260412-1B2C3D-135", category: { emoji: "📦", name: "Marketplace" },
    predicted: true, confidence: 0.86, extraction: "complete", duplicateStatus: null },
  { id: "i11", number: "FV/2026/04/0134", type: "expense", status: "approved", kind: "vat",
    seller: "Uber BV", nip: "NL852071589B01", netto: "42.13", brutto: "51.82", currency: "PLN",
    date: "2026-04-11", ksef: "5252457316-20260411-2D11A9-134", category: { emoji: "🚖", name: "Transport" },
    predicted: true, confidence: 0.78, extraction: "complete", duplicateStatus: null },
  { id: "i12", number: "AR-2026-44", type: "expense", status: "pending", kind: "vat",
    seller: "Linear Orbit Inc.", nip: "US83-4419221", netto: "48.00", brutto: "48.00", currency: "USD",
    date: "2026-04-10", ksef: null, category: { emoji: "💻", name: "Software" },
    predicted: true, confidence: 0.71, extraction: "complete", duplicateStatus: null, source: "api" },
  { id: "i13", number: "FV/2026/04/0133", type: "income", status: "approved", kind: "vat",
    seller: "Bratnia Sp. j.", nip: "PL5252457316", netto: "4 500.00", brutto: "5 535.00", currency: "PLN",
    date: "2026-04-10", ksef: "9721241997-20260410-AB44CE-133", category: { emoji: "💰", name: "Services" },
    predicted: false, confidence: null, extraction: "complete", duplicateStatus: null },
  { id: "i14", number: "FV/2026/04/0132", type: "expense", status: "needs_review", kind: "vat",
    seller: "Unknown vendor", nip: null, netto: null, brutto: null, currency: "PLN",
    date: "2026-04-09", ksef: "5252457316-20260409-8E19B4-132", category: null,
    predicted: true, confidence: 0.41, extraction: "failed", duplicateStatus: null },
  { id: "i15", number: "FV/2026/04/0131", type: "expense", status: "approved", kind: "vat",
    seller: "Orange Polska", nip: "PL5260250995", netto: "72.28", brutto: "88.90", currency: "PLN",
    date: "2026-04-09", ksef: "5252457316-20260409-FE0011-131", category: { emoji: "📱", name: "Telecom" },
    predicted: true, confidence: 0.97, extraction: "complete", duplicateStatus: null },
  { id: "i16", number: "F/04/2026/KS", type: "expense", status: "approved", kind: "vat",
    seller: "PKP Intercity", nip: "PL5260250375", netto: "260.40", brutto: "320.00", currency: "PLN",
    date: "2026-04-08", ksef: "5252457316-20260408-92AC31-130", category: { emoji: "🚆", name: "Transport" },
    predicted: true, confidence: 0.84, extraction: "complete", duplicateStatus: null },
  { id: "i17", number: "FV/2026/04/0129", type: "expense", status: "rejected", kind: "vat",
    seller: "Restauracja Karmnik", nip: "PL7792456881", netto: "186.18", brutto: "200.00", currency: "PLN",
    date: "2026-04-07", ksef: "5252457316-20260407-43B2E0-129", category: { emoji: "🍽️", name: "Meals" },
    predicted: true, confidence: 0.66, extraction: "complete", duplicateStatus: null },
  { id: "i18", number: "INV-0077", type: "expense", status: "approved", kind: "vat",
    seller: "Vercel Inc.", nip: "US82-3739587", netto: "20.00", brutto: "20.00", currency: "USD",
    date: "2026-04-07", ksef: null, category: { emoji: "☁️", name: "Cloud" },
    predicted: true, confidence: 0.93, extraction: "complete", duplicateStatus: null, source: "email" },
  { id: "i19", number: "FV/2026/04/0128", type: "income", status: "approved", kind: "vat",
    seller: "Formax S.A.", nip: "PL9512498111", netto: "12 000.00", brutto: "14 760.00", currency: "PLN",
    date: "2026-04-06", ksef: "9721241997-20260406-C1D2E3-128", category: { emoji: "💰", name: "Services" },
    predicted: false, confidence: null, extraction: "complete", duplicateStatus: null },
  { id: "i20", number: "FV/2026/04/0127", type: "expense", status: "approved", kind: "vat",
    seller: "IKEA Retail sp. z o.o.", nip: "PL5272452233", netto: "487.80", brutto: "600.00", currency: "PLN",
    date: "2026-04-05", ksef: "5252457316-20260405-FA9988-127", category: { emoji: "🪑", name: "Office" },
    predicted: true, confidence: 0.82, extraction: "complete", duplicateStatus: null },
  { id: "i21", number: "2026/04/MANUAL-03", type: "expense", status: "approved", kind: "vat",
    seller: "Poczta Polska S.A.", nip: "PL5250007313", netto: "18.29", brutto: "22.50", currency: "PLN",
    date: "2026-04-04", ksef: null, category: { emoji: "📮", name: "Postage" },
    predicted: false, confidence: null, extraction: "complete", duplicateStatus: null, source: "manual" },
  { id: "i22", number: "FV/2026/04/0126", type: "expense", status: "approved", kind: "vat",
    seller: "Tauron Sprzedaż sp. z o.o.", nip: "PL6762327545", netto: "342.88", brutto: "421.74", currency: "PLN",
    date: "2026-04-03", ksef: "5252457316-20260403-112233-126", category: { emoji: "⚡", name: "Utilities" },
    predicted: true, confidence: 0.90, extraction: "complete", duplicateStatus: null },
  { id: "i23", number: "FV/2026/04/0125", type: "income", status: "approved", kind: "vat",
    seller: "Obrót.io sp. z o.o.", nip: "PL5842774918", netto: "6 800.00", brutto: "8 364.00", currency: "PLN",
    date: "2026-04-02", ksef: "9721241997-20260402-AA11BB-125", category: { emoji: "💰", name: "Services" },
    predicted: false, confidence: null, extraction: "complete", duplicateStatus: null },
  { id: "i24", number: "FV/2026/03/0898", type: "expense", status: "approved", kind: "vat",
    seller: "Benefit Systems S.A.", nip: "PL8361842318", netto: "2 100.00", brutto: "2 583.00", currency: "PLN",
    date: "2026-03-31", ksef: "5252457316-20260331-778899-898", category: { emoji: "🏋️", name: "Benefits" },
    predicted: true, confidence: 0.88, extraction: "complete", duplicateStatus: null },
  { id: "i25", number: "FV/2026/03/0897", type: "expense", status: "approved", kind: "vat",
    seller: "Google Ireland Ltd.", nip: "IE6388047V", netto: "1 240.00", brutto: "1 525.20", currency: "PLN",
    date: "2026-03-30", ksef: "5252457316-20260330-CCDDEE-897", category: { emoji: "☁️", name: "Cloud" },
    predicted: true, confidence: 0.85, extraction: "complete", duplicateStatus: null },
];

const SYNC_JOBS = [
  { id: "s1", inserted: "2026-01-14 09:02 UTC", duration: "2.4s", state: "completed", income: 0, expense: 3, error: null },
  { id: "s2", inserted: "2026-01-14 08:02 UTC", duration: "2.1s", state: "completed", income: 0, expense: 0, error: null },
  { id: "s3", inserted: "2026-01-14 07:02 UTC", duration: "2.2s", state: "completed", income: 1, expense: 0, error: null },
  { id: "s4", inserted: "2026-01-13 23:02 UTC", duration: "11.8s", state: "failed", income: null, expense: null, error: "KSeF upstream: 502 Bad Gateway" },
  { id: "s5", inserted: "2026-01-13 22:02 UTC", duration: "2.5s", state: "completed", income: 0, expense: 2, error: null },
  { id: "s6", inserted: "2026-01-13 21:02 UTC", duration: "2.3s", state: "completed", income: 0, expense: 1, error: null },
];

const CERT = {
  subject: "CN=Appunite sp. z o.o., O=Appunite, C=PL",
  serial: "03:9A:2B:F1:88:C4:0E:11",
  issued: "2025-01-14",
  expires: "2026-04-20",
  daysLeft: 96,
  status: "ok",
};

const CATEGORIES = [
  { id: "software", emoji: "💻", name: "Software" },
  { id: "cloud", emoji: "☁️", name: "Cloud" },
  { id: "telecom", emoji: "📱", name: "Telecom" },
  { id: "internet", emoji: "🌐", name: "Internet" },
  { id: "transport", emoji: "🚖", name: "Transport" },
  { id: "meals", emoji: "🍽️", name: "Meals" },
  { id: "office", emoji: "🪑", name: "Office" },
  { id: "utilities", emoji: "⚡", name: "Utilities" },
  { id: "postage", emoji: "📮", name: "Postage" },
  { id: "benefits", emoji: "🏋️", name: "Benefits" },
  { id: "marketplace", emoji: "📦", name: "Marketplace" },
  { id: "payments", emoji: "💳", name: "Payments" },
  { id: "services", emoji: "💰", name: "Services" },
];

const TAGS = [
  { id: "reimbursable", name: "reimbursable", color: "info" },
  { id: "recurring", name: "recurring", color: "muted" },
  { id: "travel-q2", name: "travel-q2", color: "purple" },
  { id: "project-acme", name: "project-acme", color: "success" },
  { id: "urgent", name: "urgent", color: "error" },
  { id: "personal-use", name: "personal-use", color: "warning" },
];

// Payment status attached to each invoice (deterministic by id)
INVOICES.forEach((inv, idx) => {
  const pm = ["paid", "paid", "pending", "none", "paid", "pending"];
  inv.paymentStatus = pm[idx % pm.length];
  if (inv.status === "rejected" || inv.status === "needs_review") inv.paymentStatus = "none";
  inv.tags = [];
  if (idx % 5 === 0) inv.tags.push("recurring");
  if (idx % 7 === 0) inv.tags.push("project-acme");
  if (idx % 11 === 0) inv.tags.push("travel-q2");
  if (inv.currency !== "PLN") inv.tags.push("reimbursable");
});

// Demo activity/notes/comments/access/payments for invoice detail tabs.
// Keyed by invoice id; we populate a few richly and a default fallback for the rest.

const DETAIL_ACTIVITY = {
  default: [
    { id: "a1", icon: "arrow-path", actor: "KSeF sync", verb: "fetched invoice from KSeF", ts: "2026-04-14 09:02 UTC" },
    { id: "a2", icon: "bolt", actor: "Classifier", verb: "predicted category Software (92%)", ts: "2026-04-14 09:02 UTC" },
    { id: "a3", icon: "check", actor: "Maciej K.", verb: "approved invoice", ts: "2026-04-14 10:11 UTC" },
  ],
  i05: [
    { id: "a1", icon: "arrow-path", actor: "KSeF sync", verb: "fetched invoice from KSeF", ts: "2026-04-15 07:02 UTC" },
    { id: "a2", icon: "duplicate", actor: "Dedup", verb: "flagged as possible duplicate of FV/2026/01/0014 (91.4%)", ts: "2026-04-15 07:02 UTC" },
    { id: "a3", icon: "warning", actor: "Classifier", verb: "low confidence on category (61%)", ts: "2026-04-15 07:02 UTC" },
    { id: "a4", icon: "cog", actor: "Ana S.", verb: "opened invoice for review", ts: "2026-04-15 09:34 UTC" },
    { id: "a5", icon: "cog", actor: "Ana S.", verb: "changed category from Software to Telecom", ts: "2026-04-15 09:35 UTC" },
  ],
  i14: [
    { id: "a1", icon: "arrow-path", actor: "KSeF sync", verb: "fetched invoice from KSeF", ts: "2026-04-09 12:05 UTC" },
    { id: "a2", icon: "error", actor: "Extractor", verb: "failed to extract line items (OCR timeout)", ts: "2026-04-09 12:05 UTC" },
    { id: "a3", icon: "info", actor: "System", verb: "status set to needs_review", ts: "2026-04-09 12:05 UTC" },
  ],
};

const DETAIL_NOTES = {
  default: [
    { id: "n1", author: "Maciej K.", initials: "MK", ts: "2026-04-14 10:14 UTC",
      body: "Matches Q2 SaaS budget line. Approved; paid via virtual card." },
  ],
  i01: [], // demo: empty notes state
  i05: [
    { id: "n1", author: "Ana S.", initials: "AS", ts: "2026-04-15 09:40 UTC",
      body: "This looks like a re-post of the January invoice. Same NIP, same brutto, reversed sign. Waiting for Orange to confirm before rejecting." },
    { id: "n2", author: "Maciej K.", initials: "MK", ts: "2026-04-15 14:22 UTC",
      body: "Called Orange support — it's a correction pair with the cancelled Jan line. We should keep both, mark this one as the correction, and approve." },
  ],
};

const DETAIL_COMMENTS = {
  default: [
    { id: "c1", author: "Maciej K.", initials: "MK", ts: "10:11",
      body: "Approving — this is the standard monthly charge.", ownMine: false },
  ],
  i01: [], // demo: empty comments state
  i05: [
    { id: "c1", author: "Ana S.", initials: "AS", ts: "09:34",
      body: "@Maciej K. can you check with Orange before I reject this?", ownMine: false },
    { id: "c2", author: "Maciej K.", initials: "MK", ts: "14:20",
      body: "On it.", ownMine: false },
    { id: "c3", author: "Maciej K.", initials: "MK", ts: "14:22",
      body: "Confirmed — it's a correction pair, keeping both.", ownMine: false },
    { id: "c4", author: "You", initials: "OP", ts: "14:31",
      body: "Thanks. Marking as correction and approving.", ownMine: true },
  ],
};

const DETAIL_ACCESS = {
  default: [
    { id: "u1", name: "Maciej Kowalski", email: "maciej@appunite.com", initials: "MK", role: "approver", grantedBy: "Owner", grantedOn: "2025-11-02" },
    { id: "u2", name: "Ana Sobczak", email: "ana@appunite.com", initials: "AS", role: "editor", grantedBy: "Maciej K.", grantedOn: "2026-01-08" },
    { id: "u3", name: "Piotr Nowak", email: "piotr@appunite.com", initials: "PN", role: "viewer", grantedBy: "Maciej K.", grantedOn: "2026-03-21" },
  ],
};

const DETAIL_PAYMENTS = {
  i01: [{ id: "p01", counterparty: "Google Ireland Ltd.", amount: "1 525.20", currency: "PLN", scheduledFor: "2026-04-22", status: "pending" }],
  i02: [{ id: "p02", counterparty: "Google Ireland Ltd.", amount: "1 525.20", currency: "PLN", scheduledFor: "2026-04-15", sentAt: "2026-04-15 09:12 UTC", status: "sent" }],
  i08: [{ id: "p06", counterparty: "Netia S.A.", amount: "492.50", currency: "PLN", scheduledFor: "2026-04-14", sentAt: "2026-04-14 11:03 UTC", status: "sent" }],
  i17: [{ id: "p11", counterparty: "Restauracja Karmnik", amount: "200.00", currency: "PLN", scheduledFor: "2026-04-08", status: "voided" }],
  default: [],
};

Object.assign(window, { COMPANIES, INVOICES, SYNC_JOBS, CERT, CATEGORIES, TAGS,
  DETAIL_ACTIVITY, DETAIL_NOTES, DETAIL_COMMENTS, DETAIL_ACCESS, DETAIL_PAYMENTS });
