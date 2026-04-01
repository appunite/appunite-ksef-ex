defmodule KsefHubWeb.Api.InvoiceControllerTest do
  use KsefHubWeb.ConnCase, async: true

  import KsefHub.Factory
  import KsefHubWeb.ApiTestHelpers

  describe "index" do
    test "returns invoices for the token's company without company_id param", %{conn: conn} do
      %{company: company, token: token} = create_user_with_token(:owner)
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
      %{token: token} = create_user_with_token(:owner)

      conn = conn |> api_conn(token) |> get("/api/invoices")

      assert conn.status == 200
      body = Jason.decode!(conn.resp_body)
      assert body["data"] == []
      assert body["meta"]["total_count"] == 0
    end

    test "returns paginated response with meta", %{conn: conn} do
      %{company: company, token: token} = create_user_with_token(:owner)

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
      %{company: company, token: token} = create_user_with_token(:owner)
      insert(:invoice, company: company)

      conn = conn |> api_conn(token) |> get("/api/invoices")

      body = Jason.decode!(conn.resp_body)
      assert body["meta"]["page"] == 1
      assert body["meta"]["per_page"] == 25
    end
  end

  describe "show" do
    test "returns invoice from token's company", %{conn: conn} do
      %{company: company, token: token} = create_user_with_token(:owner)
      invoice = insert(:invoice, company: company)

      conn = conn |> api_conn(token) |> get("/api/invoices/#{invoice.id}")

      assert conn.status == 200
      assert Jason.decode!(conn.resp_body)["data"]["id"] == invoice.id
    end

    test "returns 404 for invoice from different company", %{conn: conn} do
      %{token: token} = create_user_with_token(:owner)
      other_company = insert(:company)
      invoice = insert(:invoice, company: other_company)

      assert_error_sent 404, fn ->
        conn |> api_conn(token) |> get("/api/invoices/#{invoice.id}")
      end
    end
  end

  describe "approve" do
    test "approves expense invoice from token's company", %{conn: conn} do
      %{company: company, token: token} = create_user_with_token(:owner)
      invoice = insert(:invoice, company: company, type: :expense, status: :pending)

      conn = conn |> api_conn(token) |> post("/api/invoices/#{invoice.id}/approve")

      assert conn.status == 200
      assert Jason.decode!(conn.resp_body)["data"]["status"] == "approved"
    end

    test "returns 404 when approving invoice from different company", %{conn: conn} do
      %{token: token} = create_user_with_token(:owner)
      other_company = insert(:company)
      invoice = insert(:invoice, company: other_company, type: :expense, status: :pending)

      assert_error_sent 404, fn ->
        conn |> api_conn(token) |> post("/api/invoices/#{invoice.id}/approve")
      end
    end
  end

  describe "reject" do
    test "rejects expense invoice from token's company", %{conn: conn} do
      %{company: company, token: token} = create_user_with_token(:owner)
      invoice = insert(:invoice, company: company, type: :expense, status: :pending)

      conn = conn |> api_conn(token) |> post("/api/invoices/#{invoice.id}/reject")

      assert conn.status == 200
      assert Jason.decode!(conn.resp_body)["data"]["status"] == "rejected"
    end

    test "returns 404 when rejecting invoice from different company", %{conn: conn} do
      %{token: token} = create_user_with_token(:owner)
      other_company = insert(:company)
      invoice = insert(:invoice, company: other_company, type: :expense, status: :pending)

      assert_error_sent 404, fn ->
        conn |> api_conn(token) |> post("/api/invoices/#{invoice.id}/reject")
      end
    end
  end

  describe "reset_status" do
    test "resets approved expense invoice to pending", %{conn: conn} do
      %{company: company, token: token} = create_user_with_token(:owner)
      invoice = insert(:invoice, company: company, type: :expense, status: :approved)

      conn = conn |> api_conn(token) |> post("/api/invoices/#{invoice.id}/reset_status")

      assert conn.status == 200
      assert Jason.decode!(conn.resp_body)["data"]["status"] == "pending"
    end

    test "resets rejected expense invoice to pending", %{conn: conn} do
      %{company: company, token: token} = create_user_with_token(:owner)
      invoice = insert(:invoice, company: company, type: :expense, status: :rejected)

      conn = conn |> api_conn(token) |> post("/api/invoices/#{invoice.id}/reset_status")

      assert conn.status == 200
      assert Jason.decode!(conn.resp_body)["data"]["status"] == "pending"
    end

    test "returns 422 for already pending invoice", %{conn: conn} do
      %{company: company, token: token} = create_user_with_token(:owner)
      invoice = insert(:invoice, company: company, type: :expense, status: :pending)

      conn = conn |> api_conn(token) |> post("/api/invoices/#{invoice.id}/reset_status")

      assert conn.status == 422
      assert Jason.decode!(conn.resp_body)["error"] =~ "already pending"
    end

    test "returns 422 for income invoice", %{conn: conn} do
      %{company: company, token: token} = create_user_with_token(:owner)
      invoice = insert(:invoice, company: company, type: :income)

      conn = conn |> api_conn(token) |> post("/api/invoices/#{invoice.id}/reset_status")

      assert conn.status == 422
      assert Jason.decode!(conn.resp_body)["error"] =~ "expense"
    end

    test "accountant gets 403", %{conn: conn} do
      {:ok, %{company: company, token: token}} = create_user_with_token(:accountant)
      invoice = insert(:invoice, company: company, type: :expense, status: :approved)

      conn = conn |> api_conn(token) |> post("/api/invoices/#{invoice.id}/reset_status")
      assert conn.status == 403
    end

    test "reviewer can reset", %{conn: conn} do
      {:ok, %{company: company, token: token}} = create_user_with_token(:reviewer)
      invoice = insert(:invoice, company: company, type: :expense, status: :approved)

      conn = conn |> api_conn(token) |> post("/api/invoices/#{invoice.id}/reset_status")

      assert conn.status == 200
      assert Jason.decode!(conn.resp_body)["data"]["status"] == "pending"
    end
  end

  describe "xml" do
    test "returns XML content with correct headers", %{conn: conn} do
      %{company: company, token: token} = create_user_with_token(:owner)
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
      %{token: token} = create_user_with_token(:owner)
      other_company = insert(:company)
      invoice = insert(:invoice, company: other_company)

      assert_error_sent 404, fn ->
        conn |> api_conn(token) |> get("/api/invoices/#{invoice.id}/xml")
      end
    end
  end

  describe "create" do
    test "creates a manual invoice and returns 201", %{conn: conn} do
      %{token: token} = create_user_with_token(:owner)

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
      %{company: company, token: token} = create_user_with_token(:owner)
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
      %{token: token} = create_user_with_token(:owner)
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
      %{token: token} = create_user_with_token(:owner)

      body = Jason.encode!(%{type: "expense"})

      conn = conn |> api_conn(token) |> post("/api/invoices", body)

      assert conn.status == 422
      assert Jason.decode!(conn.resp_body)["error"]
    end
  end

  describe "confirm_duplicate" do
    test "confirms a suspected duplicate invoice", %{conn: conn} do
      %{company: company, token: token} = create_user_with_token(:owner)
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
      %{company: company, token: token} = create_user_with_token(:owner)
      invoice = insert(:invoice, company: company)

      conn =
        conn |> api_conn(token) |> post("/api/invoices/#{invoice.id}/confirm-duplicate")

      assert conn.status == 422
      assert Jason.decode!(conn.resp_body)["error"] == "Invoice is not a duplicate"
    end

    test "returns 404 for invoice from different company", %{conn: conn} do
      %{token: token} = create_user_with_token(:owner)
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
      %{company: company, token: token} = create_user_with_token(:owner)
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
      %{company: company, token: token} = create_user_with_token(:owner)
      invoice = insert(:invoice, company: company)

      conn =
        conn |> api_conn(token) |> post("/api/invoices/#{invoice.id}/dismiss-duplicate")

      assert conn.status == 422
      assert Jason.decode!(conn.resp_body)["error"] == "Invoice is not a duplicate"
    end

    test "returns 404 for invoice from different company", %{conn: conn} do
      %{token: token} = create_user_with_token(:owner)
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
      %{company: company, token: token} = create_user_with_token(:owner)
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
        %{company: company, token: token} = create_user_with_token(:owner)
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
      %{company: company, token: token} = create_user_with_token(:owner)
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
      %{company: company, token: token} = create_user_with_token(:owner)
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
      %{company: company, token: token} = create_user_with_token(:owner)
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
      %{company: company, token: token} = create_user_with_token(:owner)
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
      %{token: token} = create_user_with_token(:owner)

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
      %{token: token} = create_user_with_token(:owner)

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
      %{token: token} = create_user_with_token(:owner)

      conn =
        conn
        |> api_conn_multipart(token)
        |> post("/api/invoices/upload", %{"type" => "expense"})

      assert conn.status == 422
      assert Jason.decode!(conn.resp_body)["error"] =~ "Missing required file"
    end

    test "returns 422 when type missing", %{conn: conn} do
      %{token: token} = create_user_with_token(:owner)

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
      %{token: token} = create_user_with_token(:owner)

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
      %{token: token} = create_user_with_token(:owner)

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
      %{token: token} = create_user_with_token(:owner)

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
      %{company: company, token: token} = create_user_with_token(:owner)

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
      %{company: company, token: token} = create_user_with_token(:owner)

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
      %{company: company, token: token} = create_user_with_token(:owner)

      invoice =
        insert(:pdf_upload_invoice, company: company, extraction_status: :partial)

      too_long_nip = String.duplicate("1", 51)
      body = Jason.encode!(%{seller_nip: too_long_nip})
      conn = conn |> api_conn(token) |> patch("/api/invoices/#{invoice.id}", body)

      assert conn.status == 422
    end

    test "returns 422 for KSeF invoice", %{conn: conn} do
      %{company: company, token: token} = create_user_with_token(:owner)
      invoice = insert(:invoice, company: company)

      body = Jason.encode!(%{seller_name: "New Name"})
      conn = conn |> api_conn(token) |> patch("/api/invoices/#{invoice.id}", body)

      assert conn.status == 422
      assert Jason.decode!(conn.resp_body)["error"] =~ "KSeF invoices cannot be updated"
    end

    test "updates fields on a manual invoice", %{conn: conn} do
      %{company: company, token: token} = create_user_with_token(:owner)
      invoice = insert(:manual_invoice, company: company)

      body = Jason.encode!(%{seller_name: "Updated Name"})
      conn = conn |> api_conn(token) |> patch("/api/invoices/#{invoice.id}", body)

      assert conn.status == 200
      data = Jason.decode!(conn.resp_body)["data"]
      assert data["seller_name"] == "Updated Name"
      # Manual invoices have no extraction_status — update should not introduce one
      assert data["extraction_status"] == nil
    end
  end

  describe "pdf download for pdf_upload invoices" do
    test "returns original uploaded PDF", %{conn: conn} do
      %{company: company, token: token} = create_user_with_token(:owner)
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
      %{company: company, token: token} = create_user_with_token(:owner)
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
      %{company: company, token: token} = create_user_with_token(:owner)
      invoice = insert(:pdf_upload_invoice, company: company)

      conn = conn |> api_conn(token) |> get("/api/invoices/#{invoice.id}/xml")

      assert conn.status == 422
      assert Jason.decode!(conn.resp_body)["error"] == "Invoice has no XML content"
    end

    test "html returns 422 for pdf_upload invoice", %{conn: conn} do
      %{company: company, token: token} = create_user_with_token(:owner)
      invoice = insert(:pdf_upload_invoice, company: company)

      conn = conn |> api_conn(token) |> get("/api/invoices/#{invoice.id}/html")

      assert conn.status == 422
      assert Jason.decode!(conn.resp_body)["error"] == "Invoice has no XML content"
    end
  end

  describe "source filter" do
    test "filters invoices by source=manual in index", %{conn: conn} do
      %{company: company, token: token} = create_user_with_token(:owner)
      insert(:invoice, company: company, source: :ksef)
      insert(:manual_invoice, company: company, source: :manual)

      conn = conn |> api_conn(token) |> get("/api/invoices?source=manual")

      body = Jason.decode!(conn.resp_body)
      assert length(body["data"]) == 1
      assert hd(body["data"])["source"] == "manual"
    end

    test "filters invoices by source=ksef in index", %{conn: conn} do
      %{company: company, token: token} = create_user_with_token(:owner)
      insert(:invoice, company: company, source: :ksef)
      insert(:manual_invoice, company: company, source: :manual)

      conn = conn |> api_conn(token) |> get("/api/invoices?source=ksef")

      body = Jason.decode!(conn.resp_body)
      assert length(body["data"]) == 1
      assert hd(body["data"])["source"] == "ksef"
    end
  end

  describe "reviewer role scoping via access control" do
    test "reviewer token returns only expense invoices (income is auto-restricted)", %{conn: conn} do
      {:ok, %{company: company, token: token}} = create_user_with_token(:reviewer)
      insert(:invoice, company: company, type: :income, access_restricted: true)
      insert(:invoice, company: company, type: :expense)

      conn = conn |> api_conn(token) |> get("/api/invoices")

      body = Jason.decode!(conn.resp_body)
      assert length(body["data"]) == 1
      assert hd(body["data"])["type"] == "expense"
      assert body["meta"]["total_count"] == 1
    end

    test "reviewer token returns 404 for restricted income invoice show", %{conn: conn} do
      {:ok, %{company: company, token: token}} = create_user_with_token(:reviewer)
      income = insert(:invoice, company: company, type: :income, access_restricted: true)

      assert_error_sent 404, fn ->
        conn |> api_conn(token) |> get("/api/invoices/#{income.id}")
      end
    end

    test "reviewer token can access expense invoice show", %{conn: conn} do
      {:ok, %{company: company, token: token}} = create_user_with_token(:reviewer)
      expense = insert(:invoice, company: company, type: :expense)

      conn = conn |> api_conn(token) |> get("/api/invoices/#{expense.id}")

      assert conn.status == 200
      assert Jason.decode!(conn.resp_body)["data"]["id"] == expense.id
    end

    test "reviewer token returns 404 for restricted income invoice approve", %{conn: conn} do
      {:ok, %{company: company, token: token}} = create_user_with_token(:reviewer)
      income = insert(:invoice, company: company, type: :income, access_restricted: true)

      assert_error_sent 404, fn ->
        conn |> api_conn(token) |> post("/api/invoices/#{income.id}/approve")
      end
    end

    test "reviewer token returns 404 for restricted income invoice reject", %{conn: conn} do
      {:ok, %{company: company, token: token}} = create_user_with_token(:reviewer)
      income = insert(:invoice, company: company, type: :income, access_restricted: true)

      assert_error_sent 404, fn ->
        conn |> api_conn(token) |> post("/api/invoices/#{income.id}/reject")
      end
    end

    test "reviewer token returns 404 for restricted income invoice xml", %{conn: conn} do
      {:ok, %{company: company, token: token}} = create_user_with_token(:reviewer)
      income = insert(:invoice, company: company, type: :income, access_restricted: true)

      assert_error_sent 404, fn ->
        conn |> api_conn(token) |> get("/api/invoices/#{income.id}/xml")
      end
    end
  end

  describe "response fields" do
    test "includes company_id, note, and is_excluded in show response", %{conn: conn} do
      %{company: company, token: token} = create_user_with_token(:owner)

      invoice =
        insert(:invoice,
          company: company,
          note: "test note",
          is_excluded: true
        )

      conn = conn |> api_conn(token) |> get("/api/invoices/#{invoice.id}")

      data = Jason.decode!(conn.resp_body)["data"]
      assert data["company_id"] == company.id
      assert data["note"] == "test note"
      assert data["is_excluded"] == true
    end

    test "includes company_id in list response", %{conn: conn} do
      %{company: company, token: token} = create_user_with_token(:owner)
      insert(:invoice, company: company)

      conn = conn |> api_conn(token) |> get("/api/invoices")

      data = Jason.decode!(conn.resp_body)["data"]
      assert hd(data)["company_id"] == company.id
    end
  end

  describe "show with category and tags" do
    test "includes category and tags in show response", %{conn: conn} do
      %{company: company, token: token} = create_user_with_token(:owner)
      category = insert(:category, company: company, identifier: "ops:test")
      invoice = insert(:invoice, company: company, category_id: category.id, tags: ["urgent"])

      conn = conn |> api_conn(token) |> get("/api/invoices/#{invoice.id}")

      data = Jason.decode!(conn.resp_body)["data"]
      assert data["category"]["id"] == category.id
      assert data["category"]["identifier"] == "ops:test"
      assert data["tags"] == ["urgent"]
    end

    test "includes category in list response", %{conn: conn} do
      %{company: company, token: token} = create_user_with_token(:owner)
      category = insert(:category, company: company)
      insert(:invoice, company: company, category_id: category.id)

      conn = conn |> api_conn(token) |> get("/api/invoices")

      data = Jason.decode!(conn.resp_body)["data"]
      assert hd(data)["category"]["id"] == category.id
    end
  end

  describe "set_category" do
    test "assigns a category to an invoice", %{conn: conn} do
      %{company: company, token: token} = create_user_with_token(:owner)
      category = insert(:category, company: company)
      invoice = insert(:invoice, type: :expense, company: company)

      body = Jason.encode!(%{category_id: category.id})
      conn = conn |> api_conn(token) |> put("/api/invoices/#{invoice.id}/category", body)

      assert conn.status == 200
      assert Jason.decode!(conn.resp_body)["data"]["category"]["id"] == category.id
    end

    test "clears category with null", %{conn: conn} do
      %{company: company, token: token} = create_user_with_token(:owner)
      category = insert(:category, company: company)
      invoice = insert(:invoice, type: :expense, company: company, category_id: category.id)

      body = Jason.encode!(%{category_id: nil})
      conn = conn |> api_conn(token) |> put("/api/invoices/#{invoice.id}/category", body)

      assert conn.status == 200
      assert is_nil(Jason.decode!(conn.resp_body)["data"]["category"])
    end

    test "returns 422 when assigning category to income invoice", %{conn: conn} do
      %{company: company, token: token} = create_user_with_token(:owner)
      category = insert(:category, company: company)
      invoice = insert(:invoice, type: :income, company: company)

      body = Jason.encode!(%{category_id: category.id})
      conn = conn |> api_conn(token) |> put("/api/invoices/#{invoice.id}/category", body)

      assert conn.status == 422
      assert Jason.decode!(conn.resp_body)["error"] =~ "expense"
    end

    test "returns 422 for category from different company", %{conn: conn} do
      %{company: company, token: token} = create_user_with_token(:owner)
      other_company = insert(:company)
      category = insert(:category, company: other_company)
      invoice = insert(:invoice, type: :expense, company: company)

      body = Jason.encode!(%{category_id: category.id})
      conn = conn |> api_conn(token) |> put("/api/invoices/#{invoice.id}/category", body)

      assert conn.status == 422
      assert Jason.decode!(conn.resp_body)["error"] == "Category not found in this company"
    end

    test "includes cost_line in invoice JSON response", %{conn: conn} do
      %{company: company, token: token} = create_user_with_token(:owner)
      invoice = insert(:invoice, type: :expense, company: company, cost_line: :growth)

      conn = conn |> api_conn(token) |> get("/api/invoices/#{invoice.id}")

      assert conn.status == 200
      assert Jason.decode!(conn.resp_body)["data"]["cost_line"] == "growth"
    end

    test "set_category with cost_line override", %{conn: conn} do
      %{company: company, token: token} = create_user_with_token(:owner)
      category = insert(:category, company: company, default_cost_line: :growth)
      invoice = insert(:invoice, type: :expense, company: company)

      body = Jason.encode!(%{category_id: category.id, cost_line: "heads"})
      conn = conn |> api_conn(token) |> put("/api/invoices/#{invoice.id}/category", body)

      assert conn.status == 200
      data = Jason.decode!(conn.resp_body)["data"]
      assert data["cost_line"] == "heads"
    end

    test "set_category returns 422 for invalid cost_line", %{conn: conn} do
      %{company: company, token: token} = create_user_with_token(:owner)
      category = insert(:category, company: company)
      invoice = insert(:invoice, type: :expense, company: company)

      body = Jason.encode!(%{category_id: category.id, cost_line: "bogus"})
      conn = conn |> api_conn(token) |> put("/api/invoices/#{invoice.id}/category", body)

      assert conn.status == 422
      assert Jason.decode!(conn.resp_body)["error"] =~ "Invalid cost_line"
    end

    test "set_category auto-sets cost_line from default when not provided", %{conn: conn} do
      %{company: company, token: token} = create_user_with_token(:owner)
      category = insert(:category, company: company, default_cost_line: :service_delivery)
      invoice = insert(:invoice, type: :expense, company: company)

      body = Jason.encode!(%{category_id: category.id})
      conn = conn |> api_conn(token) |> put("/api/invoices/#{invoice.id}/category", body)

      assert conn.status == 200
      data = Jason.decode!(conn.resp_body)["data"]
      assert data["cost_line"] == "service_delivery"
    end
  end

  describe "set_tags" do
    test "replaces all tags on an invoice", %{conn: conn} do
      %{company: company, token: token} = create_user_with_token(:owner)
      invoice = insert(:invoice, company: company, tags: ["alpha"])

      body = Jason.encode!(%{tags: ["beta"]})
      conn = conn |> api_conn(token) |> put("/api/invoices/#{invoice.id}/tags", body)

      assert conn.status == 200
      data = Jason.decode!(conn.resp_body)["data"]
      assert data["tags"] == ["beta"]
    end

    test "clears all tags with empty list", %{conn: conn} do
      %{company: company, token: token} = create_user_with_token(:owner)
      invoice = insert(:invoice, company: company, tags: ["alpha"])

      body = Jason.encode!(%{tags: []})
      conn = conn |> api_conn(token) |> put("/api/invoices/#{invoice.id}/tags", body)

      assert conn.status == 200
      data = Jason.decode!(conn.resp_body)["data"]
      assert data["tags"] == []
    end

    test "returns 422 for non-list tags", %{conn: conn} do
      %{company: company, token: token} = create_user_with_token(:owner)
      invoice = insert(:invoice, company: company)

      body = Jason.encode!(%{tags: "not-a-list"})
      conn = conn |> api_conn(token) |> put("/api/invoices/#{invoice.id}/tags", body)

      assert conn.status == 422
      assert Jason.decode!(conn.resp_body)["error"] == "tags must be a list of strings"
    end

    test "returns 422 for mixed-element tags list", %{conn: conn} do
      %{company: company, token: token} = create_user_with_token(:owner)
      invoice = insert(:invoice, company: company)

      body = Jason.encode!(%{tags: ["alpha", 123]})
      conn = conn |> api_conn(token) |> put("/api/invoices/#{invoice.id}/tags", body)

      assert conn.status == 422
      assert Jason.decode!(conn.resp_body)["error"] == "tags must be a list of strings"
    end

    test "returns 422 when tags key is missing", %{conn: conn} do
      %{company: company, token: token} = create_user_with_token(:owner)
      invoice = insert(:invoice, company: company, tags: ["existing"])

      body = Jason.encode!(%{})
      conn = conn |> api_conn(token) |> put("/api/invoices/#{invoice.id}/tags", body)

      assert conn.status == 422
      assert Jason.decode!(conn.resp_body)["error"] == "tags must be a list of strings"
    end
  end

  describe "filtering by category_id" do
    test "filters invoices by category_id", %{conn: conn} do
      %{company: company, token: token} = create_user_with_token(:owner)
      category = insert(:category, company: company)
      insert(:invoice, company: company, category_id: category.id, seller_name: "Cat Invoice")
      insert(:invoice, company: company, seller_name: "No Cat Invoice")

      conn = conn |> api_conn(token) |> get("/api/invoices?category_id=#{category.id}")

      body = Jason.decode!(conn.resp_body)
      assert length(body["data"]) == 1
      assert hd(body["data"])["seller_name"] == "Cat Invoice"
    end
  end

  describe "filtering by tags" do
    test "filters invoices by tags", %{conn: conn} do
      %{company: company, token: token} = create_user_with_token(:owner)
      insert(:invoice, company: company, seller_name: "Tagged", tags: ["monthly"])
      insert(:invoice, company: company, seller_name: "Untagged")

      conn =
        conn |> api_conn(token) |> get("/api/invoices?tags[]=monthly")

      body = Jason.decode!(conn.resp_body)
      assert length(body["data"]) == 1
      assert hd(body["data"])["seller_name"] == "Tagged"
    end
  end

  describe "source filter with pdf_upload" do
    test "filters invoices by source=pdf_upload", %{conn: conn} do
      %{company: company, token: token} = create_user_with_token(:owner)
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

  describe "purchase_order" do
    test "show returns purchase_order in response", %{conn: conn} do
      %{company: company, token: token} = create_user_with_token(:owner)
      invoice = insert(:invoice, company: company, purchase_order: "PO-SHOW-001")

      conn = conn |> api_conn(token) |> get("/api/invoices/#{invoice.id}")

      assert conn.status == 200
      data = Jason.decode!(conn.resp_body)["data"]
      assert data["purchase_order"] == "PO-SHOW-001"
    end

    test "show returns null purchase_order when absent", %{conn: conn} do
      %{company: company, token: token} = create_user_with_token(:owner)
      invoice = insert(:invoice, company: company, purchase_order: nil)

      conn = conn |> api_conn(token) |> get("/api/invoices/#{invoice.id}")

      assert conn.status == 200
      data = Jason.decode!(conn.resp_body)["data"]
      assert is_nil(data["purchase_order"])
    end

    test "create accepts purchase_order", %{conn: conn} do
      %{token: token} = create_user_with_token(:owner)

      body =
        Jason.encode!(%{
          type: "expense",
          seller_nip: "1234567890",
          seller_name: "Seller Sp. z o.o.",
          buyer_nip: "0987654321",
          buyer_name: "Buyer S.A.",
          invoice_number: "FV/2026/PO1",
          issue_date: "2026-02-20",
          net_amount: "1000.00",
          gross_amount: "1230.00",
          purchase_order: "PO-CREATE-001"
        })

      conn = conn |> api_conn(token) |> post("/api/invoices", body)

      assert conn.status == 201
      data = Jason.decode!(conn.resp_body)["data"]
      assert data["purchase_order"] == "PO-CREATE-001"
    end

    test "update accepts purchase_order on pdf_upload invoice", %{conn: conn} do
      %{company: company, token: token} = create_user_with_token(:owner)
      invoice = insert(:pdf_upload_invoice, company: company)

      body = Jason.encode!(%{purchase_order: "PO-UPDATE-001"})

      conn = conn |> api_conn(token) |> patch("/api/invoices/#{invoice.id}", body)

      assert conn.status == 200
      data = Jason.decode!(conn.resp_body)["data"]
      assert data["purchase_order"] == "PO-UPDATE-001"
    end
  end

  describe "extraction fields (sales_date, due_date, iban, addresses)" do
    test "show returns all 5 new fields", %{conn: conn} do
      %{company: company, token: token} = create_user_with_token(:owner)

      invoice =
        insert(:invoice,
          company: company,
          sales_date: ~D[2025-01-14],
          due_date: ~D[2025-02-14],
          iban: "PL61109010140000071219812874",
          seller_address: %{
            street: "ul. Testowa 1",
            city: "Warszawa",
            postal_code: nil,
            country: "PL"
          },
          buyer_address: %{street: "ul. Kupna 5", city: "Kraków", postal_code: nil, country: "PL"}
        )

      conn = conn |> api_conn(token) |> get("/api/invoices/#{invoice.id}")

      assert conn.status == 200
      data = Jason.decode!(conn.resp_body)["data"]
      assert data["sales_date"] == "2025-01-14"
      assert data["due_date"] == "2025-02-14"
      assert data["iban"] == "PL61109010140000071219812874"
      assert data["seller_address"]["street"] == "ul. Testowa 1"
      assert data["buyer_address"]["street"] == "ul. Kupna 5"
    end

    test "show returns null for absent extraction fields", %{conn: conn} do
      %{company: company, token: token} = create_user_with_token(:owner)
      invoice = insert(:invoice, company: company)

      conn = conn |> api_conn(token) |> get("/api/invoices/#{invoice.id}")

      assert conn.status == 200
      data = Jason.decode!(conn.resp_body)["data"]
      assert is_nil(data["sales_date"])
      assert is_nil(data["due_date"])
      assert is_nil(data["iban"])
      assert is_nil(data["seller_address"])
      assert is_nil(data["buyer_address"])
    end

    test "create accepts sales_date, due_date, iban", %{conn: conn} do
      %{token: token} = create_user_with_token(:owner)

      body =
        Jason.encode!(%{
          type: "expense",
          seller_nip: "1234567890",
          seller_name: "Seller Sp. z o.o.",
          buyer_nip: "0987654321",
          buyer_name: "Buyer S.A.",
          invoice_number: "FV/2026/EX1",
          issue_date: "2026-02-20",
          net_amount: "1000.00",
          gross_amount: "1230.00",
          sales_date: "2026-02-18",
          due_date: "2026-03-20",
          iban: "PL61109010140000071219812874"
        })

      conn = conn |> api_conn(token) |> post("/api/invoices", body)

      assert conn.status == 201
      data = Jason.decode!(conn.resp_body)["data"]
      assert data["sales_date"] == "2026-02-18"
      assert data["due_date"] == "2026-03-20"
      assert data["iban"] == "PL61109010140000071219812874"
    end

    test "update accepts sales_date, due_date, iban on pdf_upload invoice", %{conn: conn} do
      %{company: company, token: token} = create_user_with_token(:owner)
      invoice = insert(:pdf_upload_invoice, company: company)

      body =
        Jason.encode!(%{
          sales_date: "2026-02-18",
          due_date: "2026-03-20",
          iban: "PL61109010140000071219812874"
        })

      conn = conn |> api_conn(token) |> patch("/api/invoices/#{invoice.id}", body)

      assert conn.status == 200
      data = Jason.decode!(conn.resp_body)["data"]
      assert data["sales_date"] == "2026-02-18"
      assert data["due_date"] == "2026-03-20"
      assert data["iban"] == "PL61109010140000071219812874"
    end
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

  # --- Permission Tests ---

  describe "accountant permission enforcement" do
    test "accountant can read invoices (index)", %{conn: conn} do
      {:ok, %{company: company, token: token}} = create_user_with_token(:accountant)
      insert(:invoice, company: company)

      conn = conn |> api_conn(token) |> get("/api/invoices")
      assert conn.status == 200
    end

    test "accountant can read single invoice (show)", %{conn: conn} do
      {:ok, %{company: company, token: token}} = create_user_with_token(:accountant)
      invoice = insert(:invoice, company: company)

      conn = conn |> api_conn(token) |> get("/api/invoices/#{invoice.id}")
      assert conn.status == 200
    end

    test "accountant cannot create invoices", %{conn: conn} do
      {:ok, %{token: token}} = create_user_with_token(:accountant)

      conn =
        conn
        |> api_conn(token)
        |> post("/api/invoices", %{
          type: "expense",
          seller_nip: "1234567890",
          seller_name: "Test",
          buyer_nip: "0987654321",
          buyer_name: "Test Buyer",
          invoice_number: "FV/1",
          issue_date: "2026-01-01",
          net_amount: "100.00",
          gross_amount: "123.00",
          currency: "PLN"
        })

      assert conn.status == 403
    end

    test "accountant cannot update invoices", %{conn: conn} do
      {:ok, %{company: company, token: token}} = create_user_with_token(:accountant)
      invoice = insert(:invoice, company: company, source: :pdf_upload)

      conn =
        conn
        |> api_conn(token)
        |> patch("/api/invoices/#{invoice.id}", %{seller_name: "Updated"})

      assert conn.status == 403
    end

    test "accountant cannot approve invoices", %{conn: conn} do
      {:ok, %{company: company, token: token}} = create_user_with_token(:accountant)
      invoice = insert(:invoice, company: company, type: :expense)

      conn = conn |> api_conn(token) |> post("/api/invoices/#{invoice.id}/approve")
      assert conn.status == 403
    end

    test "accountant cannot reject invoices", %{conn: conn} do
      {:ok, %{company: company, token: token}} = create_user_with_token(:accountant)
      invoice = insert(:invoice, company: company, type: :expense)

      conn = conn |> api_conn(token) |> post("/api/invoices/#{invoice.id}/reject")
      assert conn.status == 403
    end

    test "accountant cannot set category", %{conn: conn} do
      {:ok, %{company: company, token: token}} = create_user_with_token(:accountant)
      invoice = insert(:invoice, company: company)

      conn =
        conn
        |> api_conn(token)
        |> put("/api/invoices/#{invoice.id}/category", %{category_id: nil})

      assert conn.status == 403
    end

    test "accountant cannot set tags", %{conn: conn} do
      {:ok, %{company: company, token: token}} = create_user_with_token(:accountant)
      invoice = insert(:invoice, company: company)

      conn =
        conn
        |> api_conn(token)
        |> put("/api/invoices/#{invoice.id}/tags", %{tags: []})

      assert conn.status == 403
    end
  end

  describe "admin permission enforcement" do
    test "admin can create invoices", %{conn: conn} do
      {:ok, %{token: token}} = create_user_with_token(:admin)

      conn =
        conn
        |> api_conn(token)
        |> post("/api/invoices", %{
          type: "expense",
          seller_nip: "1234567890",
          seller_name: "Test",
          buyer_nip: "0987654321",
          buyer_name: "Test Buyer",
          invoice_number: "FV/1",
          issue_date: "2026-01-01",
          net_amount: "100.00",
          gross_amount: "123.00",
          currency: "PLN"
        })

      assert conn.status == 201
    end

    test "admin can approve invoices", %{conn: conn} do
      {:ok, %{company: company, token: token}} = create_user_with_token(:admin)

      invoice =
        insert(:invoice,
          company: company,
          type: :expense,
          status: :pending,
          source: :ksef
        )

      conn = conn |> api_conn(token) |> post("/api/invoices/#{invoice.id}/approve")
      assert conn.status == 200
    end
  end

  describe "billing_date_range" do
    test "billing_date_from/to appear in show response", %{conn: conn} do
      %{company: company, token: token} = create_user_with_token(:owner)

      invoice =
        insert(:invoice,
          company: company,
          billing_date_from: ~D[2026-03-01],
          billing_date_to: ~D[2026-05-01]
        )

      conn = conn |> api_conn(token) |> get("/api/invoices/#{invoice.id}")

      assert conn.status == 200
      data = Jason.decode!(conn.resp_body)["data"]
      assert data["billing_date_from"] == "2026-03-01"
      assert data["billing_date_to"] == "2026-05-01"
    end

    test "create with explicit billing_date_from/to", %{conn: conn} do
      %{token: token} = create_user_with_token(:owner)

      body =
        Jason.encode!(%{
          type: "expense",
          seller_nip: "1234567890",
          seller_name: "Seller Sp. z o.o.",
          buyer_nip: "0987654321",
          buyer_name: "Buyer S.A.",
          invoice_number: "FV/2026/BD1",
          issue_date: "2026-02-20",
          net_amount: "1000.00",
          gross_amount: "1230.00",
          billing_date_from: "2026-04-01",
          billing_date_to: "2026-06-01"
        })

      conn = conn |> api_conn(token) |> post("/api/invoices", body)

      assert conn.status == 201
      data = Jason.decode!(conn.resp_body)["data"]
      assert data["billing_date_from"] == "2026-04-01"
      assert data["billing_date_to"] == "2026-06-01"
    end

    test "create auto-computes billing_date_from/to when not provided", %{conn: conn} do
      %{token: token} = create_user_with_token(:owner)

      body =
        Jason.encode!(%{
          type: "expense",
          seller_nip: "1234567890",
          seller_name: "Seller Sp. z o.o.",
          buyer_nip: "0987654321",
          buyer_name: "Buyer S.A.",
          invoice_number: "FV/2026/BD2",
          issue_date: "2026-02-20",
          net_amount: "1000.00",
          gross_amount: "1230.00"
        })

      conn = conn |> api_conn(token) |> post("/api/invoices", body)

      assert conn.status == 201
      data = Jason.decode!(conn.resp_body)["data"]
      assert data["billing_date_from"] == "2026-02-01"
      assert data["billing_date_to"] == "2026-02-01"
    end

    test "update billing_date_from/to via PATCH", %{conn: conn} do
      %{company: company, token: token} = create_user_with_token(:owner)

      invoice =
        insert(:manual_invoice,
          company: company,
          billing_date_from: ~D[2026-02-01],
          billing_date_to: ~D[2026-02-01]
        )

      body =
        Jason.encode!(%{billing_date_from: "2026-05-01", billing_date_to: "2026-07-01"})

      conn = conn |> api_conn(token) |> patch("/api/invoices/#{invoice.id}", body)

      assert conn.status == 200
      data = Jason.decode!(conn.resp_body)["data"]
      assert data["billing_date_from"] == "2026-05-01"
      assert data["billing_date_to"] == "2026-07-01"
    end
  end

  describe "access control API" do
    test "get_access returns access status and grants", %{conn: conn} do
      %{company: company, token: token} = create_user_with_token(:owner)
      invoice = insert(:invoice, company: company, access_restricted: false)

      conn = conn |> api_conn(token) |> get("/api/invoices/#{invoice.id}/access")

      assert conn.status == 200
      data = Jason.decode!(conn.resp_body)["data"]
      assert data["access_restricted"] == false
      assert data["grants"] == []
    end

    test "set_access toggles restriction", %{conn: conn} do
      %{company: company, token: token} = create_user_with_token(:owner)
      invoice = insert(:invoice, company: company)

      conn =
        conn
        |> api_conn(token)
        |> put("/api/invoices/#{invoice.id}/access", %{access_restricted: true})

      assert conn.status == 200
      data = Jason.decode!(conn.resp_body)["data"]
      assert data["access_restricted"] == true
    end

    test "grant_access and revoke_access work", %{conn: conn} do
      %{company: company, token: token} = create_user_with_token(:owner)
      invoice = insert(:invoice, company: company, access_restricted: true)
      reviewer = insert(:user)
      insert(:membership, user: reviewer, company: company, role: :reviewer)

      # Grant
      conn1 =
        conn
        |> api_conn(token)
        |> post("/api/invoices/#{invoice.id}/access/grants", %{user_id: reviewer.id})

      assert conn1.status == 200
      data = Jason.decode!(conn1.resp_body)["data"]
      assert length(data["grants"]) == 1
      assert hd(data["grants"])["user_id"] == reviewer.id

      # Revoke
      conn2 =
        conn
        |> api_conn(token)
        |> delete("/api/invoices/#{invoice.id}/access/grants/#{reviewer.id}")

      assert conn2.status == 200
      data = Jason.decode!(conn2.resp_body)["data"]
      assert data["grants"] == []
    end

    test "grant_access and revoke_access reject malformed user_id", %{conn: conn} do
      %{company: company, token: token} = create_user_with_token(:owner)
      invoice = insert(:invoice, company: company, access_restricted: true)

      conn1 =
        conn
        |> api_conn(token)
        |> post("/api/invoices/#{invoice.id}/access/grants", %{user_id: "not-a-uuid"})

      assert conn1.status == 422

      conn2 =
        conn
        |> api_conn(token)
        |> delete("/api/invoices/#{invoice.id}/access/grants/not-a-uuid")

      assert conn2.status == 422
    end

    test "cannot unrestrict income invoice", %{conn: conn} do
      %{company: company, token: token} = create_user_with_token(:owner)
      invoice = insert(:invoice, company: company, type: :income, access_restricted: true)

      conn =
        conn
        |> api_conn(token)
        |> put("/api/invoices/#{invoice.id}/access", %{access_restricted: false})

      assert conn.status == 422
      body = Jason.decode!(conn.resp_body)
      assert body["error"] =~ "Income invoices"
    end

    test "reviewer cannot access access control endpoints", %{conn: conn} do
      {:ok, %{company: company, token: token}} = create_user_with_token(:reviewer)
      invoice = insert(:invoice, company: company, type: :expense)

      conn = conn |> api_conn(token) |> get("/api/invoices/#{invoice.id}/access")
      assert conn.status == 403
    end

    test "reviewer cannot see restricted invoice via API", %{conn: conn} do
      {:ok, %{token: token, company: company}} = create_user_with_token(:reviewer)
      insert(:invoice, company: company, type: :expense, access_restricted: true)

      conn = conn |> api_conn(token) |> get("/api/invoices")

      assert conn.status == 200
      body = Jason.decode!(conn.resp_body)
      assert body["data"] == []
      assert body["meta"]["total_count"] == 0
    end

    test "reviewer with explicit grant can view restricted invoice", %{conn: conn} do
      %{company: company, token: owner_token} = create_user_with_token(:owner)

      # Create reviewer in the same company with their own API token
      reviewer = insert(:user, google_uid: "uid-#{System.unique_integer([:positive])}")
      reviewer_membership = insert(:membership, user: reviewer, company: company, role: :owner)

      {:ok, reviewer_token_result} =
        KsefHub.Accounts.create_api_token(reviewer.id, company.id, %{name: "Reviewer Token"})

      reviewer_membership
      |> Ecto.Changeset.change(role: :reviewer)
      |> KsefHub.Repo.update!()

      reviewer_token = reviewer_token_result.token

      invoice = insert(:invoice, company: company, type: :expense, access_restricted: true)

      # Grant access to reviewer (as owner)
      grant_conn =
        conn
        |> api_conn(owner_token)
        |> post("/api/invoices/#{invoice.id}/access/grants", %{user_id: reviewer.id})

      assert grant_conn.status == 200

      # Reviewer can now see the restricted invoice via show
      show_conn = conn |> api_conn(reviewer_token) |> get("/api/invoices/#{invoice.id}")
      assert show_conn.status == 200
      assert Jason.decode!(show_conn.resp_body)["data"]["id"] == invoice.id

      # Reviewer can also see it in the list
      list_conn = conn |> api_conn(reviewer_token) |> get("/api/invoices")
      assert list_conn.status == 200
      body = Jason.decode!(list_conn.resp_body)
      assert body["meta"]["total_count"] > 0
      assert Enum.any?(body["data"], &(&1["id"] == invoice.id))
    end

    test "index returns access_restricted field", %{conn: conn} do
      %{company: company, token: token} = create_user_with_token(:owner)
      insert(:invoice, company: company, access_restricted: true)

      conn = conn |> api_conn(token) |> get("/api/invoices")

      assert conn.status == 200
      data = Jason.decode!(conn.resp_body)["data"]
      assert hd(data)["access_restricted"] == true
    end
  end

  describe "set_project_tag" do
    test "sets project tag on expense invoice", %{conn: conn} do
      %{company: company, token: token} = create_user_with_token(:owner)
      invoice = insert(:invoice, type: :expense, company: company)

      body = Jason.encode!(%{project_tag: "Project Alpha"})
      conn = conn |> api_conn(token) |> put("/api/invoices/#{invoice.id}/project-tag", body)

      assert conn.status == 200
      assert Jason.decode!(conn.resp_body)["data"]["project_tag"] == "Project Alpha"
    end

    test "sets project tag on income invoice", %{conn: conn} do
      %{company: company, token: token} = create_user_with_token(:owner)
      invoice = insert(:invoice, type: :income, company: company)

      body = Jason.encode!(%{project_tag: "Revenue Stream"})
      conn = conn |> api_conn(token) |> put("/api/invoices/#{invoice.id}/project-tag", body)

      assert conn.status == 200
      assert Jason.decode!(conn.resp_body)["data"]["project_tag"] == "Revenue Stream"
    end

    test "clears project tag with null", %{conn: conn} do
      %{company: company, token: token} = create_user_with_token(:owner)
      invoice = insert(:invoice, type: :expense, company: company, project_tag: "Old Tag")

      body = Jason.encode!(%{project_tag: nil})
      conn = conn |> api_conn(token) |> put("/api/invoices/#{invoice.id}/project-tag", body)

      assert conn.status == 200
      assert is_nil(Jason.decode!(conn.resp_body)["data"]["project_tag"])
    end

    test "returns 403 for accountant", %{conn: conn} do
      {:ok, %{company: company, token: token}} = create_user_with_token(:accountant)
      invoice = insert(:invoice, type: :expense, company: company)

      body = Jason.encode!(%{project_tag: "Forbidden"})
      conn = conn |> api_conn(token) |> put("/api/invoices/#{invoice.id}/project-tag", body)

      assert conn.status == 403
    end

    test "returns 403 for accountant when clearing", %{conn: conn} do
      {:ok, %{company: company, token: token}} = create_user_with_token(:accountant)
      invoice = insert(:invoice, type: :expense, company: company, project_tag: "Existing")

      body = Jason.encode!(%{project_tag: nil})
      conn = conn |> api_conn(token) |> put("/api/invoices/#{invoice.id}/project-tag", body)

      assert conn.status == 403
    end

    test "includes project_tag in invoice JSON response", %{conn: conn} do
      %{company: company, token: token} = create_user_with_token(:owner)
      invoice = insert(:invoice, type: :expense, company: company, project_tag: "My Project")

      conn = conn |> api_conn(token) |> get("/api/invoices/#{invoice.id}")

      assert conn.status == 200
      assert Jason.decode!(conn.resp_body)["data"]["project_tag"] == "My Project"
    end
  end

  describe "list_project_tags" do
    test "returns distinct project tags", %{conn: conn} do
      %{company: company, token: token} = create_user_with_token(:owner)
      insert(:invoice, company: company, type: :expense, project_tag: "Alpha")
      insert(:invoice, company: company, type: :income, project_tag: "Beta")

      conn = conn |> api_conn(token) |> get("/api/project-tags")

      assert conn.status == 200
      data = Jason.decode!(conn.resp_body)["data"]
      assert is_list(data)
      assert "Alpha" in data
      assert "Beta" in data
    end

    test "returns empty list when no tags set", %{conn: conn} do
      %{company: _company, token: token} = create_user_with_token(:owner)

      conn = conn |> api_conn(token) |> get("/api/project-tags")

      assert conn.status == 200
      assert Jason.decode!(conn.resp_body)["data"] == []
    end
  end
end
