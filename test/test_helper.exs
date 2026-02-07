ExUnit.start(exclude: [:integration])
Ecto.Adapters.SQL.Sandbox.mode(KsefHub.Repo, :manual)

# Define Mox mocks for external dependencies
Mox.defmock(KsefHub.KsefClient.Mock, for: KsefHub.KsefClient.Behaviour)
Mox.defmock(KsefHub.XadesSigner.Mock, for: KsefHub.XadesSigner.Behaviour)
Mox.defmock(KsefHub.Pdf.Mock, for: KsefHub.Pdf.Behaviour)
