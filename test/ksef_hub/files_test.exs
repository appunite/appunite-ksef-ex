defmodule KsefHub.FilesTest do
  use KsefHub.DataCase, async: true

  alias KsefHub.Files
  alias KsefHub.Files.File
  alias KsefHub.Repo

  import KsefHub.Factory

  describe "create_file/1" do
    test "valid attrs returns {:ok, %File{}} with computed byte_size" do
      content = "hello world"

      assert {:ok, %File{} = file} =
               Files.create_file(%{
                 content: content,
                 content_type: "text/plain",
                 filename: "test.txt"
               })

      assert file.content == content
      assert file.content_type == "text/plain"
      assert file.filename == "test.txt"
      assert file.byte_size == byte_size(content)
      assert file.inserted_at
    end

    test "missing content returns error" do
      assert {:error, changeset} = Files.create_file(%{content_type: "text/plain"})
      assert %{content: ["can't be blank"]} = errors_on(changeset)
    end

    test "missing content_type returns error" do
      assert {:error, changeset} = Files.create_file(%{content: "data"})
      assert %{content_type: ["can't be blank"]} = errors_on(changeset)
    end

    test "content over 10MB returns error" do
      big_content = :binary.copy(<<0>>, 10_000_001)

      assert {:error, changeset} =
               Files.create_file(%{content: big_content, content_type: "application/pdf"})

      assert %{byte_size: ["must be at most 10MB"]} = errors_on(changeset)
    end
  end

  describe "get_file!/1" do
    test "returns file by ID" do
      file = insert(:file)
      assert Files.get_file!(file.id).id == file.id
    end

    test "raises on missing ID" do
      assert_raise Ecto.NoResultsError, fn ->
        Files.get_file!(Ecto.UUID.generate())
      end
    end
  end

  describe "get_file/1" do
    test "returns file by ID" do
      file = insert(:file)
      assert Files.get_file(file.id).id == file.id
    end

    test "returns nil on missing ID" do
      assert is_nil(Files.get_file(Ecto.UUID.generate()))
    end
  end

  describe "invoice file associations" do
    test "invoice with xml_file and pdf_file loads via preload" do
      xml_file = insert(:file, content: "<xml/>", content_type: "application/xml")
      pdf_file = insert(:file, content: "%PDF", content_type: "application/pdf")

      invoice =
        insert(:invoice, xml_file: xml_file, pdf_file: pdf_file)
        |> Repo.preload([:xml_file, :pdf_file])

      assert invoice.xml_file.id == xml_file.id
      assert invoice.xml_file.content == "<xml/>"
      assert invoice.pdf_file.id == pdf_file.id
      assert invoice.pdf_file.content == "%PDF"
    end
  end

  describe "inbound_email file associations" do
    test "inbound email with pdf_file loads via preload" do
      pdf_file = insert(:file, content: "%PDF", content_type: "application/pdf")

      email =
        insert(:inbound_email, pdf_file: pdf_file)
        |> Repo.preload(:pdf_file)

      assert email.pdf_file.id == pdf_file.id
      assert email.pdf_file.content == "%PDF"
    end
  end
end
