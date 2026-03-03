defmodule KsefHubWeb.Api.InvoiceControllerTest do
  use KsefHubWeb.ConnCase, async: true

  import KsefHub.Factory
  import KsefHubWeb.ApiTestHelpers

  describe "index" do
    test "returns invoices for the token's company without company_id param", %{conn: conn} do
      %{company: company, token: token} = create_owner_with_token()
      insert(:invoice, company: company, seller_name: "My Seller")

      other_company = insert(:company)
      insert(:invoice, company: other_company, seller_name: "Other Seller")

      conn = conn |> api_conn(token) |> get("/api/invoices")

      assert conn.status == 200
      body = Jason.decode!(conn.resp_body)
      assert length(body["data"]) == 1
      assert hd(body["data"])["seller_name"] == "My Seller"
    end

    test "returns empty list when company has no invoices", %{conn: conn} do
      %{token: token} = create_owner_with_token()

      conn = conn |> api_conn(token) |> get("/api/invoices")

      assert conn.status == 200
      body = Jason.decode!(conn.resp_body)
      assert body["data"] == []
      assert body["meta"]["total_count"] == 0
    end

    test "returns paginated response with meta", %{conn: conn} do
      %{company: company, token: token} = create_owner_with_token()

      for i <- 1..5 do
        insert(:invoice, company: company, invoice_number: "FV/#{i}")
      end

      conn = conn |> api_conn(token) |> get("/api/invoices?page=1&per_page=2")

      assert conn.status == 200
      body = Jason.decode!(conn.resp_body)
      assert length(body["data"]) == 2
      assert body["meta"]["page"] == 1
      assert body["meta"]["per_page"] == 2
      assert body["meta"]["total_count"] == 5
      assert body["meta"]["total_pages"] == 3
    end

    test "defaults to page 1 per_page 25", %{conn: conn} do
      %{company: company, token: token} = create_owner_with_token()
      insert(:invoice, company: company)

      conn = conn |> api_conn(token) |> get("/api/invoices")

      body = Jason.decode!(conn.resp_body)
      assert body["meta"]["page"] == 1
      assert body["meta"]["per_page"] == 25
    end
  end

  describe "show" do
    test "returns invoice from token's company", %{conn: conn} do
      %{company: company, token: token} = create_owner_with_token()
      invoice = insert(:invoice, company: company)

      conn = conn |> api_conn(token) |> get("/api/invoices/#{invoice.id}")

      assert conn.status == 200
      assert Jason.decode!(conn.resp_body)["data"]["id"] == invoice.id
    end

    test "returns 404 for invoice from different company", %{conn: conn} do
      %{token: token} = create_owner_with_token()
      other_company = insert(:company)
      invoice = insert(:invoice, company: other_company)

      assert_error_sent 404, fn ->
        conn |> api_conn(token) |> get("/api/invoices/#{invoice.id}")
      end
    end
  end

  describe "approve" do
    test "approves expense invoice from token's company", %{conn: conn} do
      %{company: company, token: token} = create_owner_with_token()
      invoice = insert(:invoice, company: company, type: :expense, status: :pending)

      conn = conn |> api_conn(token) |> post("/api/invoices/#{invoice.id}/approve")

      assert conn.status == 200
      assert Jason.decode!(conn.resp_body)["data"]["status"] == "approved"
    end

    test "returns 404 when approving invoice from different company", %{conn: conn} do
      %{token: token} = create_owner_with_token()
      other_company = insert(:company)
      invoice = insert(:invoice, company: other_company, type: :expense, status: :pending)

      assert_error_sent 404, fn ->
        conn |> api_conn(token) |> post("/api/invoices/#{invoice.id}/approve")
      end
    end
  end

  describe "reject" do
    test "rejects expense invoice from token's company", %{conn: conn} do
      %{company: company, token: token} = create_owner_with_token()
      invoice = insert(:invoice, company: company, type: :expense, status: :pending)

      conn = conn |> api_conn(token) |> post("/api/invoices/#{invoice.id}/reject")

      assert conn.status == 200
      assert Jason.decode!(conn.resp_body)["data"]["status"] == "rejected"
    end

    test "returns 404 when rejecting invoice from different company", %{conn: conn} do
      %{token: token} = create_owner_with_token()
      other_company = insert(:company)
      invoice = insert(:invoice, company: other_company, type: :expense, status: :pending)

      assert_error_sent 404, fn ->
        conn |> api_conn(token) |> post("/api/invoices/#{invoice.id}/reject")
      end
    end
  end

  describe "xml" do
    test "returns XML content with correct headers", %{conn: conn} do
      %{company: company, token: token} = create_owner_with_token()
      xml = "<Faktura>test</Faktura>"
      xml_file = insert(:file, content: xml, content_type: "application/xml")

      invoice =
        insert(:invoice,
          company: company,
          xml_file: xml_file,
          invoice_number: "FV/2025/001"
        )

      conn = conn |> api_conn(token) |> get("/api/invoices/#{invoice.id}/xml")

      assert conn.status == 200
      assert get_resp_header(conn, "content-type") |> hd() =~ "application/xml"
      assert get_resp_header(conn, "content-disposition") |> hd() =~ "FV_2025_001.xml"
      assert conn.resp_body == xml
    end

    test "returns 404 for invoice from different company", %{conn: conn} do
      %{token: token} = create_owner_with_token()
      other_company = insert(:company)
      invoice = insert(:invoice, company: other_company)

      assert_error_sent 404, fn ->
        conn |> api_conn(token) |> get("/api/invoices/#{invoice.id}/xml")
      end
    end
  end

  describe "create" do
    test "creates a manual invoice and returns 201", %{conn: conn} do
      %{token: token} = create_owner_with_token()

      body =
        Jason.encode!(%{
          type: "expense",
          seller_nip: "1234567890",
          seller_name: "Seller Sp. z o.o.",
          buyer_nip: "0987654321",
          buyer_name: "Buyer S.A.",
          invoice_number: "FV/2026/001",
          issue_date: "2026-02-20",
          net_amount: "1000.00",
          gross_amount: "1230.00"
        })

      conn = conn |> api_conn(token) |> post("/api/invoices", body)

      assert conn.status == 201
      data = Jason.decode!(conn.resp_body)["data"]
      assert data["source"] == "manual"
      assert data["type"] == "expense"
      assert data["seller_nip"] == "1234567890"
      assert is_nil(data["duplicate_of_id"])
    end

    test "creates manual invoice and detects duplicate by ksef_number", %{conn: conn} do
      %{company: company, token: token} = create_owner_with_token()
      existing = insert(:invoice, ksef_number: "dup-ksef-123", company: company)

      body =
        Jason.encode!(%{
          type: "expense",
          ksef_number: "dup-ksef-123",
          seller_nip: "1234567890",
          seller_name: "Seller Sp. z o.o.",
          buyer_nip: "0987654321",
          buyer_name: "Buyer S.A.",
          invoice_number: "FV/2026/002",
          issue_date: "2026-02-20",
          net_amount: "1000.00",
          gross_amount: "1230.00"
        })

      conn = conn |> api_conn(token) |> post("/api/invoices", body)

      assert conn.status == 201
      data = Jason.decode!(conn.resp_body)["data"]
      assert data["duplicate_of_id"] == existing.id
      assert data["duplicate_status"] == "suspected"
    end

    test "does not detect duplicate from different company", %{conn: conn} do
      %{token: token} = create_owner_with_token()
      other_company = insert(:company)
      insert(:invoice, ksef_number: "cross-company-123", company: other_company)

      body =
        Jason.encode!(%{
          type: "expense",
          ksef_number: "cross-company-123",
          seller_nip: "1234567890",
          seller_name: "Seller Sp. z o.o.",
          buyer_nip: "0987654321",
          buyer_name: "Buyer S.A.",
          invoice_number: "FV/2026/003",
          issue_date: "2026-02-20",
          net_amount: "1000.00",
          gross_amount: "1230.00"
        })

      conn = conn |> api_conn(token) |> post("/api/invoices", body)

      assert conn.status == 201
      data = Jason.decode!(conn.resp_body)["data"]
      assert is_nil(data["duplicate_of_id"])
    end

    test "returns 422 with validation errors for invalid data", %{conn: conn} do
      %{token: token} = create_owner_with_token()

      body = Jason.encode!(%{type: "expense"})

      conn = conn |> api_conn(token) |> post("/api/invoices", body)

      assert conn.status == 422
      assert Jason.decode!(conn.resp_body)["error"]
    end
  end

  describe "confirm_duplicate" do
    test "confirms a suspected duplicate invoice", %{conn: conn} do
      %{company: company, token: token} = create_owner_with_token()
      original = insert(:invoice, ksef_number: "confirm-orig", company: company)

      duplicate =
        insert(:manual_invoice,
          ksef_number: "confirm-orig",
          company: company,
          duplicate_of_id: original.id,
          duplicate_status: :suspected
        )

      conn =
        conn |> api_conn(token) |> post("/api/invoices/#{duplicate.id}/confirm-duplicate")

      assert conn.status == 200
      assert Jason.decode!(conn.resp_body)["data"]["duplicate_status"] == "confirmed"
    end

    test "returns 422 for non-duplicate invoice", %{conn: conn} do
      %{company: company, token: token} = create_owner_with_token()
      invoice = insert(:invoice, company: company)

      conn =
        conn |> api_conn(token) |> post("/api/invoices/#{invoice.id}/confirm-duplicate")

      assert conn.status == 422
      assert Jason.decode!(conn.resp_body)["error"] == "Invoice is not a duplicate"
    end

    test "returns 404 for invoice from different company", %{conn: conn} do
      %{token: token} = create_owner_with_token()
      other_company = insert(:company)
      original = insert(:invoice, ksef_number: "cross-confirm", company: other_company)

      duplicate =
        insert(:manual_invoice,
          ksef_number: "cross-confirm",
          company: other_company,
          duplicate_of_id: original.id,
          duplicate_status: :suspected
        )

      assert_error_sent 404, fn ->
        conn |> api_conn(token) |> post("/api/invoices/#{duplicate.id}/confirm-duplicate")
      end
    end
  end

  describe "dismiss_duplicate" do
    test "dismisses a suspected duplicate invoice", %{conn: conn} do
      %{company: company, token: token} = create_owner_with_token()
      original = insert(:invoice, ksef_number: "dismiss-orig", company: company)

      duplicate =
        insert(:manual_invoice,
          ksef_number: "dismiss-orig",
          company: company,
          duplicate_of_id: original.id,
          duplicate_status: :suspected
        )

      conn =
        conn |> api_conn(token) |> post("/api/invoices/#{duplicate.id}/dismiss-duplicate")

      assert conn.status == 200
      assert Jason.decode!(conn.resp_body)["data"]["duplicate_status"] == "dismissed"
    end

    test "returns 422 for non-duplicate invoice", %{conn: conn} do
      %{company: company, token: token} = create_owner_with_token()
      invoice = insert(:invoice, company: company)

      conn =
        conn |> api_conn(token) |> post("/api/invoices/#{invoice.id}/dismiss-duplicate")

      assert conn.status == 422
      assert Jason.decode!(conn.resp_body)["error"] == "Invoice is not a duplicate"
    end

    test "returns 404 for invoice from different company", %{conn: conn} do
      %{token: token} = create_owner_with_token()
      other_company = insert(:company)
      original = insert(:invoice, ksef_number: "cross-dismiss", company: other_company)

      duplicate =
        insert(:manual_invoice,
          ksef_number: "cross-dismiss",
          company: other_company,
          duplicate_of_id: original.id,
          duplicate_status: :suspected
        )

      assert_error_sent 404, fn ->
        conn |> api_conn(token) |> post("/api/invoices/#{duplicate.id}/dismiss-duplicate")
      end
    end

    test "dismisses a confirmed duplicate invoice", %{conn: conn} do
      %{company: company, token: token} = create_owner_with_token()
      original = insert(:invoice, ksef_number: "dismiss-conf", company: company)

      duplicate =
        insert(:manual_invoice,
          ksef_number: "dismiss-conf",
          company: company,
          duplicate_of_id: original.id,
          duplicate_status: :confirmed
        )

      conn =
        conn |> api_conn(token) |> post("/api/invoices/#{duplicate.id}/dismiss-duplicate")

      assert conn.status == 200
      assert Jason.decode!(conn.resp_body)["data"]["duplicate_status"] == "dismissed"
    end
  end

  describe "content endpoints with no xml_file" do
    for endpoint <- ~w(xml html) do
      test "#{endpoint} returns 422 for invoice without xml_file", %{conn: conn} do
        %{company: company, token: token} = create_owner_with_token()
        invoice = insert(:manual_invoice, company: company)

        conn =
          conn
          |> api_conn(token)
          |> get("/api/invoices/#{invoice.id}/#{unquote(endpoint)}")

        assert conn.status == 422
        assert Jason.decode!(conn.resp_body)["error"] == "Invoice has no XML content"
      end
    end

    test "pdf returns 422 for invoice without xml_file or pdf_file", %{conn: conn} do
      %{company: company, token: token} = create_owner_with_token()
      invoice = insert(:manual_invoice, company: company)

      conn =
        conn
        |> api_conn(token)
        |> get("/api/invoices/#{invoice.id}/pdf")

      assert conn.status == 422
      assert Jason.decode!(conn.resp_body)["error"] == "Invoice has no downloadable content"
    end
  end

  describe "confirm_duplicate status transitions" do
    test "returns 422 when confirming already confirmed duplicate", %{conn: conn} do
      %{company: company, token: token} = create_owner_with_token()
      original = insert(:invoice, ksef_number: "confirm-trans", company: company)

      duplicate =
        insert(:manual_invoice,
          ksef_number: "confirm-trans",
          company: company,
          duplicate_of_id: original.id,
          duplicate_status: :confirmed
        )

      conn =
        conn |> api_conn(token) |> post("/api/invoices/#{duplicate.id}/confirm-duplicate")

      assert conn.status == 422

      assert Jason.decode!(conn.resp_body)["error"] ==
               "Duplicate can only be confirmed from suspected status"
    end

    test "returns 422 when confirming dismissed duplicate", %{conn: conn} do
      %{company: company, token: token} = create_owner_with_token()
      original = insert(:invoice, ksef_number: "confirm-dis", company: company)

      duplicate =
        insert(:manual_invoice,
          ksef_number: "confirm-dis",
          company: company,
          duplicate_of_id: original.id,
          duplicate_status: :dismissed
        )

      conn =
        conn |> api_conn(token) |> post("/api/invoices/#{duplicate.id}/confirm-duplicate")

      assert conn.status == 422

      assert Jason.decode!(conn.resp_body)["error"] ==
               "Duplicate can only be confirmed from suspected status"
    end
  end

  describe "dismiss_duplicate status transitions" do
    test "returns 422 when dismissing already dismissed duplicate", %{conn: conn} do
      %{company: company, token: token} = create_owner_with_token()
      original = insert(:invoice, ksef_number: "dismiss-trans", company: company)

      duplicate =
        insert(:manual_invoice,
          ksef_number: "dismiss-trans",
          company: company,
          duplicate_of_id: original.id,
          duplicate_status: :dismissed
        )

      conn =
        conn |> api_conn(token) |> post("/api/invoices/#{duplicate.id}/dismiss-duplicate")

      assert conn.status == 422
      assert Jason.decode!(conn.resp_body)["error"] == "Duplicate has already been dismissed"
    end
  end

  describe "upload" do
    test "returns 201 with extracted data", %{conn: conn} do
      %{token: token} = create_owner_with_token()

      Mox.expect(KsefHub.InvoiceExtractor.Mock, :extract, fn _pdf, _opts ->
        {:ok,
         %{
           "seller_nip" => "1234567890",
           "seller_name" => "Upload Seller Sp. z o.o.",
           "buyer_nip" => "0987654321",
           "buyer_name" => "Upload Buyer S.A.",
           "invoice_number" => "FV/UPLOAD/001",
           "issue_date" => "2026-02-20",
           "net_amount" => "1000.00",
           "vat_amount" => "230.00",
           "gross_amount" => "1230.00",
           "currency" => "PLN"
         }}
      end)

      upload = %Plug.Upload{
        path: create_temp_pdf(),
        content_type: "application/pdf",
        filename: "invoice.pdf"
      }

      conn =
        conn
        |> api_conn_multipart(token)
        |> post("/api/invoices/upload", %{"file" => upload, "type" => "expense"})

      assert conn.status == 201
      data = Jason.decode!(conn.resp_body)["data"]
      assert data["source"] == "pdf_upload"
      assert data["extraction_status"] == "complete"
      assert data["seller_name"] == "Upload Seller Sp. z o.o."
      assert data["original_filename"] == "invoice.pdf"
    end

    test "returns 201 with partial extraction", %{conn: conn} do
      %{token: token} = create_owner_with_token()

      Mox.expect(KsefHub.InvoiceExtractor.Mock, :extract, fn _pdf, _opts ->
        {:ok, %{"seller_name" => "Partial Seller"}}
      end)

      upload = %Plug.Upload{
        path: create_temp_pdf(),
        content_type: "application/pdf",
        filename: "partial.pdf"
      }

      conn =
        conn
        |> api_conn_multipart(token)
        |> post("/api/invoices/upload", %{"file" => upload, "type" => "expense"})

      assert conn.status == 201
      data = Jason.decode!(conn.resp_body)["data"]
      assert data["extraction_status"] == "partial"
      assert data["seller_name"] == "Partial Seller"
    end

    test "returns 422 when file missing", %{conn: conn} do
      %{token: token} = create_owner_with_token()

      conn =
        conn
        |> api_conn_multipart(token)
        |> post("/api/invoices/upload", %{"type" => "expense"})

      assert conn.status == 422
      assert Jason.decode!(conn.resp_body)["error"] =~ "Missing required file"
    end

    test "returns 422 when type missing", %{conn: conn} do
      %{token: token} = create_owner_with_token()

      upload = %Plug.Upload{
        path: create_temp_pdf(),
        content_type: "application/pdf",
        filename: "invoice.pdf"
      }

      conn =
        conn
        |> api_conn_multipart(token)
        |> post("/api/invoices/upload", %{"file" => upload})

      assert conn.status == 422
      assert Jason.decode!(conn.resp_body)["error"] =~ "Missing or invalid type"
    end

    test "returns 415 for non-PDF file", %{conn: conn} do
      %{token: token} = create_owner_with_token()

      path = create_temp_non_pdf()

      upload = %Plug.Upload{
        path: path,
        content_type: "text/plain",
        filename: "invoice.txt"
      }

      conn =
        conn
        |> api_conn_multipart(token)
        |> post("/api/invoices/upload", %{"file" => upload, "type" => "expense"})

      assert conn.status == 415
      assert Jason.decode!(conn.resp_body)["error"] =~ "PDF"
    end

    test "creates invoice with failed extraction status when extraction service fails", %{
      conn: conn
    } do
      %{token: token} = create_owner_with_token()

      Mox.expect(KsefHub.InvoiceExtractor.Mock, :extract, fn _pdf, _opts ->
        {:error, {:extractor_error, 500}}
      end)

      upload = %Plug.Upload{
        path: create_temp_pdf(),
        content_type: "application/pdf",
        filename: "fail.pdf"
      }

      conn =
        conn
        |> api_conn_multipart(token)
        |> post("/api/invoices/upload", %{"file" => upload, "type" => "expense"})

      # Extraction failure still creates an invoice (with failed status)
      assert conn.status == 201
      data = Jason.decode!(conn.resp_body)["data"]
      assert data["extraction_status"] == "failed"
    end

    test "returns 201 for income-type upload", %{conn: conn} do
      %{token: token} = create_owner_with_token()

      upload = %Plug.Upload{
        path: create_temp_pdf(),
        content_type: "application/pdf",
        filename: "income_invoice.pdf"
      }

      conn =
        conn
        |> api_conn_multipart(token)
        |> post("/api/invoices/upload", %{"file" => upload, "type" => "income"})

      assert conn.status == 201
      data = Jason.decode!(conn.resp_body)["data"]
      assert data["type"] == "income"
      assert data["source"] == "pdf_upload"
    end
  end

  describe "update (PATCH)" do
    test "updates fields on a pdf_upload invoice", %{conn: conn} do
      %{company: company, token: token} = create_owner_with_token()

      invoice =
        insert(:pdf_upload_invoice,
          company: company,
          extraction_status: :partial,
          seller_nip: nil,
          issue_date: nil,
          net_amount: nil,
          gross_amount: nil
        )

      body =
        Jason.encode!(%{
          seller_nip: "1111111111",
          issue_date: "2026-03-01",
          net_amount: "500.00",
          gross_amount: "615.00"
        })

      conn = conn |> api_conn(token) |> patch("/api/invoices/#{invoice.id}", body)

      assert conn.status == 200
      data = Jason.decode!(conn.resp_body)["data"]
      assert data["seller_nip"] == "1111111111"
      assert data["net_amount"] == "500.00"
    end

    test "recalculates extraction_status to complete", %{conn: conn} do
      %{company: company, token: token} = create_owner_with_token()

      invoice =
        insert(:pdf_upload_invoice,
          company: company,
          extraction_status: :partial,
          seller_nip: "1234567890",
          seller_name: "Seller",
          invoice_number: "FV/1",
          issue_date: ~D[2026-01-01],
          net_amount: nil,
          gross_amount: nil
        )

      body = Jason.encode!(%{net_amount: "500.00", gross_amount: "615.00"})

      conn = conn |> api_conn(token) |> patch("/api/invoices/#{invoice.id}", body)

      assert conn.status == 200
      data = Jason.decode!(conn.resp_body)["data"]
      assert data["extraction_status"] == "complete"
    end

    test "returns 422 for invalid update data", %{conn: conn} do
      %{company: company, token: token} = create_owner_with_token()

      invoice =
        insert(:pdf_upload_invoice, company: company, extraction_status: :partial)

      too_long_nip = String.duplicate("1", 51)
      body = Jason.encode!(%{seller_nip: too_long_nip})
      conn = conn |> api_conn(token) |> patch("/api/invoices/#{invoice.id}", body)

      assert conn.status == 422
    end

    test "returns 422 for non-pdf_upload invoice", %{conn: conn} do
      %{company: company, token: token} = create_owner_with_token()
      invoice = insert(:invoice, company: company)

      body = Jason.encode!(%{seller_name: "New Name"})
      conn = conn |> api_conn(token) |> patch("/api/invoices/#{invoice.id}", body)

      assert conn.status == 422
      assert Jason.decode!(conn.resp_body)["error"] =~ "Only pdf_upload"
    end
  end

  describe "pdf download for pdf_upload invoices" do
    test "returns original uploaded PDF", %{conn: conn} do
      %{company: company, token: token} = create_owner_with_token()
      pdf_file = insert(:file, content: "fake-pdf-bytes", content_type: "application/pdf")

      invoice =
        insert(:pdf_upload_invoice,
          company: company,
          pdf_file: pdf_file,
          original_filename: "my_invoice.pdf"
        )

      conn = conn |> api_conn(token) |> get("/api/invoices/#{invoice.id}/pdf")

      assert conn.status == 200
      assert get_resp_header(conn, "content-type") |> hd() =~ "application/pdf"
      assert get_resp_header(conn, "content-disposition") |> hd() =~ "my_invoice.pdf"
      assert conn.resp_body == "fake-pdf-bytes"
    end

    test "returns original uploaded PDF for email-source invoice", %{conn: conn} do
      %{company: company, token: token} = create_owner_with_token()
      pdf_file = insert(:file, content: "email-pdf-bytes", content_type: "application/pdf")

      invoice =
        insert(:pdf_upload_invoice,
          company: company,
          source: :email,
          pdf_file: pdf_file,
          original_filename: "email_invoice.pdf"
        )

      conn = conn |> api_conn(token) |> get("/api/invoices/#{invoice.id}/pdf")

      assert conn.status == 200
      assert get_resp_header(conn, "content-type") |> hd() =~ "application/pdf"
      assert get_resp_header(conn, "content-disposition") |> hd() =~ "email_invoice.pdf"
      assert conn.resp_body == "email-pdf-bytes"
    end

    test "xml returns 422 for pdf_upload invoice", %{conn: conn} do
      %{company: company, token: token} = create_owner_with_token()
      invoice = insert(:pdf_upload_invoice, company: company)

      conn = conn |> api_conn(token) |> get("/api/invoices/#{invoice.id}/xml")

      assert conn.status == 422
      assert Jason.decode!(conn.resp_body)["error"] == "Invoice has no XML content"
    end

    test "html returns 422 for pdf_upload invoice", %{conn: conn} do
      %{company: company, token: token} = create_owner_with_token()
      invoice = insert(:pdf_upload_invoice, company: company)

      conn = conn |> api_conn(token) |> get("/api/invoices/#{invoice.id}/html")

      assert conn.status == 422
      assert Jason.decode!(conn.resp_body)["error"] == "Invoice has no XML content"
    end
  end

  describe "source filter" do
    test "filters invoices by source=manual in index", %{conn: conn} do
      %{company: company, token: token} = create_owner_with_token()
      insert(:invoice, company: company, source: :ksef)
      insert(:manual_invoice, company: company, source: :manual)

      conn = conn |> api_conn(token) |> get("/api/invoices?source=manual")

      body = Jason.decode!(conn.resp_body)
      assert length(body["data"]) == 1
      assert hd(body["data"])["source"] == "manual"
    end

    test "filters invoices by source=ksef in index", %{conn: conn} do
      %{company: company, token: token} = create_owner_with_token()
      insert(:invoice, company: company, source: :ksef)
      insert(:manual_invoice, company: company, source: :manual)

      conn = conn |> api_conn(token) |> get("/api/invoices?source=ksef")

      body = Jason.decode!(conn.resp_body)
      assert length(body["data"]) == 1
      assert hd(body["data"])["source"] == "ksef"
    end
  end

  describe "reviewer role scoping" do
    test "reviewer token returns only expense invoices from index", %{conn: conn} do
      {:ok, %{company: company, token: token}} = create_reviewer_with_token()
      insert(:invoice, company: company, type: :income, seller_name: "Income Seller")
      insert(:invoice, company: company, type: :expense, seller_name: "Expense Seller")

      conn = conn |> api_conn(token) |> get("/api/invoices")

      body = Jason.decode!(conn.resp_body)
      assert length(body["data"]) == 1
      assert hd(body["data"])["type"] == "expense"
      assert body["meta"]["total_count"] == 1
    end

    test "reviewer token returns 404 for income invoice show", %{conn: conn} do
      {:ok, %{company: company, token: token}} = create_reviewer_with_token()
      income = insert(:invoice, company: company, type: :income)

      assert_error_sent 404, fn ->
        conn |> api_conn(token) |> get("/api/invoices/#{income.id}")
      end
    end

    test "reviewer token can access expense invoice show", %{conn: conn} do
      {:ok, %{company: company, token: token}} = create_reviewer_with_token()
      expense = insert(:invoice, company: company, type: :expense)

      conn = conn |> api_conn(token) |> get("/api/invoices/#{expense.id}")

      assert conn.status == 200
      assert Jason.decode!(conn.resp_body)["data"]["id"] == expense.id
    end

    test "reviewer token returns 404 for income invoice approve", %{conn: conn} do
      {:ok, %{company: company, token: token}} = create_reviewer_with_token()
      income = insert(:invoice, company: company, type: :income)

      assert_error_sent 404, fn ->
        conn |> api_conn(token) |> post("/api/invoices/#{income.id}/approve")
      end
    end

    test "reviewer token returns 404 for income invoice reject", %{conn: conn} do
      {:ok, %{company: company, token: token}} = create_reviewer_with_token()
      income = insert(:invoice, company: company, type: :income)

      assert_error_sent 404, fn ->
        conn |> api_conn(token) |> post("/api/invoices/#{income.id}/reject")
      end
    end

    test "reviewer token returns 404 for income invoice xml", %{conn: conn} do
      {:ok, %{company: company, token: token}} = create_reviewer_with_token()
      income = insert(:invoice, company: company, type: :income)

      assert_error_sent 404, fn ->
        conn |> api_conn(token) |> get("/api/invoices/#{income.id}/xml")
      end
    end
  end

  describe "show with category and tags" do
    test "includes category and tags in show response", %{conn: conn} do
      %{company: company, token: token} = create_owner_with_token()
      category = insert(:category, company: company, name: "ops:test")
      tag = insert(:tag, company: company, name: "urgent")
      invoice = insert(:invoice, company: company, category_id: category.id)
      insert(:invoice_tag, invoice: invoice, tag: tag)

      conn = conn |> api_conn(token) |> get("/api/invoices/#{invoice.id}")

      data = Jason.decode!(conn.resp_body)["data"]
      assert data["category_id"] == category.id
      assert data["category"]["name"] == "ops:test"
      assert length(data["tags"]) == 1
      assert hd(data["tags"])["name"] == "urgent"
    end

    test "includes category_id in list response", %{conn: conn} do
      %{company: company, token: token} = create_owner_with_token()
      category = insert(:category, company: company)
      insert(:invoice, company: company, category_id: category.id)

      conn = conn |> api_conn(token) |> get("/api/invoices")

      data = Jason.decode!(conn.resp_body)["data"]
      assert hd(data)["category_id"] == category.id
    end
  end

  describe "set_category" do
    test "assigns a category to an invoice", %{conn: conn} do
      %{company: company, token: token} = create_owner_with_token()
      category = insert(:category, company: company)
      invoice = insert(:invoice, company: company)

      body = Jason.encode!(%{category_id: category.id})
      conn = conn |> api_conn(token) |> put("/api/invoices/#{invoice.id}/category", body)

      assert conn.status == 200
      assert Jason.decode!(conn.resp_body)["data"]["category_id"] == category.id
    end

    test "clears category with null", %{conn: conn} do
      %{company: company, token: token} = create_owner_with_token()
      category = insert(:category, company: company)
      invoice = insert(:invoice, company: company, category_id: category.id)

      body = Jason.encode!(%{category_id: nil})
      conn = conn |> api_conn(token) |> put("/api/invoices/#{invoice.id}/category", body)

      assert conn.status == 200
      assert is_nil(Jason.decode!(conn.resp_body)["data"]["category_id"])
    end

    test "returns 422 for category from different company", %{conn: conn} do
      %{company: company, token: token} = create_owner_with_token()
      other_company = insert(:company)
      category = insert(:category, company: other_company)
      invoice = insert(:invoice, company: company)

      body = Jason.encode!(%{category_id: category.id})
      conn = conn |> api_conn(token) |> put("/api/invoices/#{invoice.id}/category", body)

      assert conn.status == 422
      assert Jason.decode!(conn.resp_body)["error"] == "Category not found in this company"
    end
  end

  describe "add_tags" do
    test "adds tags to an invoice", %{conn: conn} do
      %{company: company, token: token} = create_owner_with_token()
      tag = insert(:tag, company: company, name: "urgent")
      invoice = insert(:invoice, company: company)

      body = Jason.encode!(%{tag_ids: [tag.id]})
      conn = conn |> api_conn(token) |> post("/api/invoices/#{invoice.id}/tags", body)

      assert conn.status == 200
      data = Jason.decode!(conn.resp_body)["data"]
      assert length(data) == 1
      assert hd(data)["name"] == "urgent"
    end

    test "returns 422 for tags from different company", %{conn: conn} do
      %{company: company, token: token} = create_owner_with_token()
      other_company = insert(:company)
      tag = insert(:tag, company: other_company)
      invoice = insert(:invoice, company: company)

      body = Jason.encode!(%{tag_ids: [tag.id]})
      conn = conn |> api_conn(token) |> post("/api/invoices/#{invoice.id}/tags", body)

      assert conn.status == 422

      assert Jason.decode!(conn.resp_body)["error"] ==
               "One or more tags not found in this company"
    end
  end

  describe "set_tags" do
    test "replaces all tags on an invoice", %{conn: conn} do
      %{company: company, token: token} = create_owner_with_token()
      tag1 = insert(:tag, company: company, name: "alpha")
      tag2 = insert(:tag, company: company, name: "beta")
      invoice = insert(:invoice, company: company)
      insert(:invoice_tag, invoice: invoice, tag: tag1)

      body = Jason.encode!(%{tag_ids: [tag2.id]})
      conn = conn |> api_conn(token) |> put("/api/invoices/#{invoice.id}/tags", body)

      assert conn.status == 200
      data = Jason.decode!(conn.resp_body)["data"]
      assert length(data) == 1
      assert hd(data)["name"] == "beta"
    end

    test "clears all tags with empty list", %{conn: conn} do
      %{company: company, token: token} = create_owner_with_token()
      tag = insert(:tag, company: company)
      invoice = insert(:invoice, company: company)
      insert(:invoice_tag, invoice: invoice, tag: tag)

      body = Jason.encode!(%{tag_ids: []})
      conn = conn |> api_conn(token) |> put("/api/invoices/#{invoice.id}/tags", body)

      assert conn.status == 200
      assert Jason.decode!(conn.resp_body)["data"] == []
    end
  end

  describe "remove_tag" do
    test "removes a tag from an invoice", %{conn: conn} do
      %{company: company, token: token} = create_owner_with_token()
      tag = insert(:tag, company: company)
      invoice = insert(:invoice, company: company)
      insert(:invoice_tag, invoice: invoice, tag: tag)

      conn = conn |> api_conn(token) |> delete("/api/invoices/#{invoice.id}/tags/#{tag.id}")

      assert conn.status == 200
      assert Jason.decode!(conn.resp_body)["message"] == "Tag removed"
    end

    test "returns 404 when tag is not associated", %{conn: conn} do
      %{company: company, token: token} = create_owner_with_token()
      tag = insert(:tag, company: company)
      invoice = insert(:invoice, company: company)

      conn = conn |> api_conn(token) |> delete("/api/invoices/#{invoice.id}/tags/#{tag.id}")

      assert conn.status == 404
    end
  end

  describe "filtering by category_id" do
    test "filters invoices by category_id", %{conn: conn} do
      %{company: company, token: token} = create_owner_with_token()
      category = insert(:category, company: company)
      insert(:invoice, company: company, category_id: category.id, seller_name: "Cat Invoice")
      insert(:invoice, company: company, seller_name: "No Cat Invoice")

      conn = conn |> api_conn(token) |> get("/api/invoices?category_id=#{category.id}")

      body = Jason.decode!(conn.resp_body)
      assert length(body["data"]) == 1
      assert hd(body["data"])["seller_name"] == "Cat Invoice"
    end
  end

  describe "filtering by tag_ids" do
    test "filters invoices by tag_ids", %{conn: conn} do
      %{company: company, token: token} = create_owner_with_token()
      tag = insert(:tag, company: company)
      invoice = insert(:invoice, company: company, seller_name: "Tagged")
      insert(:invoice, company: company, seller_name: "Untagged")
      insert(:invoice_tag, invoice: invoice, tag: tag)

      conn =
        conn |> api_conn(token) |> get("/api/invoices?tag_ids[]=#{tag.id}")

      body = Jason.decode!(conn.resp_body)
      assert length(body["data"]) == 1
      assert hd(body["data"])["seller_name"] == "Tagged"
    end
  end

  describe "source filter with pdf_upload" do
    test "filters invoices by source=pdf_upload", %{conn: conn} do
      %{company: company, token: token} = create_owner_with_token()
      insert(:invoice, company: company, source: :ksef)
      insert(:pdf_upload_invoice, company: company, source: :pdf_upload)

      conn = conn |> api_conn(token) |> get("/api/invoices?source=pdf_upload")

      body = Jason.decode!(conn.resp_body)
      assert length(body["data"]) == 1
      assert hd(body["data"])["source"] == "pdf_upload"
    end
  end

  # --- Helpers ---

  @spec api_conn_multipart(Plug.Conn.t(), String.t()) :: Plug.Conn.t()
  defp api_conn_multipart(conn, token) do
    conn
    |> Plug.Conn.put_req_header("authorization", "Bearer #{token}")
    |> Plug.Conn.put_req_header("accept", "application/json")
  end

  @spec create_temp_pdf() :: String.t()
  defp create_temp_pdf do
    path = Path.join(System.tmp_dir!(), "test_invoice_#{System.unique_integer([:positive])}.pdf")
    File.write!(path, "%PDF-1.4 fake test content")
    on_exit(fn -> File.rm(path) end)
    path
  end

  @spec create_temp_non_pdf() :: String.t()
  defp create_temp_non_pdf do
    path = Path.join(System.tmp_dir!(), "test_file_#{System.unique_integer([:positive])}.txt")
    File.write!(path, "not a pdf file at all")
    on_exit(fn -> File.rm(path) end)
    path
  end
end
