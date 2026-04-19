// Login — matches lib/ksef_hub_web/live/user_live/login.ex and register.ex

const Login = ({ onSuccess }) => {
  const [email, setEmail] = React.useState("");
  const [password, setPassword] = React.useState("");
  const [submitting, setSubmitting] = React.useState(false);

  const submit = (e) => {
    e.preventDefault();
    setSubmitting(true);
    setTimeout(() => { setSubmitting(false); onSuccess(email || "ops@appunite.com"); }, 500);
  };

  return (
    <div className="min-h-screen bg-[var(--background)] text-[var(--foreground)] flex flex-col">
      <header className="px-6 py-5">
        <Logo />
      </header>
      <main className="flex-1 flex items-center justify-center px-4">
        <div className="w-full max-w-sm">
          <div className="text-center mb-8">
            <h1 className="text-2xl font-semibold tracking-tight">Log in to your account</h1>
            <p className="text-sm text-[var(--muted-foreground)] mt-1.5">Access the KSeF Hub admin.</p>
          </div>

          <Card padding="p-6">
            <form onSubmit={submit}>
              <Input label="Email" type="email" value={email} onChange={e => setEmail(e.target.value)}
                placeholder="you@company.pl" autoFocus required />
              <Input label="Password" type="password" value={password} onChange={e => setPassword(e.target.value)}
                placeholder="••••••••" required />
              <label className="flex items-center gap-2 text-sm mb-4 mt-1">
                <input type="checkbox" /> Keep me signed in
              </label>
              <Button variant="primary" className="w-full" disabled={submitting}>
                {submitting ? "Signing in…" : "Log in"}
              </Button>
            </form>
          </Card>

          <p className="text-center text-xs text-[var(--muted-foreground)] mt-6">
            Don't have an account? <a href="#" className="underline font-medium text-[var(--foreground)]">Register</a>
          </p>
          <p className="text-center text-xs text-[var(--muted-foreground)] mt-2">
            <a href="#" className="underline">Log in with magic link →</a>
          </p>
        </div>
      </main>
      <footer className="text-center text-xs text-[var(--muted-foreground)] py-6">
        KSeF Hub · by Appunite · <a href="#" className="underline">Status</a>
      </footer>
    </div>
  );
};

Object.assign(window, { Login });
