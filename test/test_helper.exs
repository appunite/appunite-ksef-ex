ExUnit.start(exclude: [:integration])
Ecto.Adapters.SQL.Sandbox.mode(KsefHub.Repo, :manual)

# Define Mox mocks for external dependencies
Mox.defmock(KsefHub.KsefClient.Mock, for: KsefHub.KsefClient.Behaviour)
Mox.defmock(KsefHub.XadesSigner.Mock, for: KsefHub.XadesSigner.Behaviour)
Mox.defmock(KsefHub.PdfRenderer.Mock, for: KsefHub.PdfRenderer.Behaviour)

Mox.defmock(KsefHub.Credentials.Pkcs12Converter.Mock,
  for: KsefHub.Credentials.Pkcs12Converter.Behaviour
)

Mox.defmock(KsefHub.Credentials.CertificateInfo.Mock,
  for: KsefHub.Credentials.CertificateInfo.Behaviour
)

Mox.defmock(KsefHub.InvoiceClassifier.Mock, for: KsefHub.InvoiceClassifier.Behaviour)
Mox.defmock(KsefHub.InvoiceExtractor.Mock, for: KsefHub.InvoiceExtractor.Behaviour)
Mox.defmock(KsefHub.EmojiGenerator.Mock, for: KsefHub.EmojiGenerator.Behaviour)
