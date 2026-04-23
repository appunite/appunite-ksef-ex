defmodule KsefHub.ServiceConfigTest do
  use KsefHub.DataCase, async: false

  alias KsefHub.Credentials.Encryption
  alias KsefHub.ServiceConfig
  alias KsefHub.ServiceConfig.ClassifierConfig

  import KsefHub.Factory

  setup do
    company = insert(:company)
    %{company: company}
  end

  describe "get_or_create_classifier_config/1" do
    test "creates a disabled config on first access", %{company: company} do
      config = ServiceConfig.get_or_create_classifier_config(company.id)

      assert %ClassifierConfig{} = config
      assert config.company_id == company.id
      assert config.enabled == false
      assert config.url == nil
    end

    test "returns existing config on subsequent access", %{company: company} do
      first = ServiceConfig.get_or_create_classifier_config(company.id)
      second = ServiceConfig.get_or_create_classifier_config(company.id)

      assert first.id == second.id
    end
  end

  describe "update_classifier_config/2" do
    test "updates URL and thresholds", %{company: company} do
      config = ServiceConfig.get_or_create_classifier_config(company.id)

      {:ok, updated} =
        ServiceConfig.update_classifier_config(config, %{
          "url" => "http://custom:9000",
          "category_confidence_threshold" => "0.85",
          "tag_confidence_threshold" => "0.90"
        })

      assert updated.url == "http://custom:9000"
      assert updated.category_confidence_threshold == 0.85
      assert updated.tag_confidence_threshold == 0.9
    end

    test "encrypts and stores API token", %{company: company} do
      config = ServiceConfig.get_or_create_classifier_config(company.id)

      {:ok, updated} =
        ServiceConfig.update_classifier_config(config, %{"api_token" => "secret"})

      assert updated.api_token_encrypted != nil
      assert {:ok, "secret"} = Encryption.decrypt(updated.api_token_encrypted)
    end

    test "blank api_token clears existing token", %{company: company} do
      config = ServiceConfig.get_or_create_classifier_config(company.id)

      {:ok, with_token} =
        ServiceConfig.update_classifier_config(config, %{"api_token" => "secret"})

      assert with_token.api_token_encrypted != nil

      {:ok, cleared} = ServiceConfig.update_classifier_config(with_token, %{"api_token" => ""})
      assert cleared.api_token_encrypted == nil
    end

    test "omitted api_token preserves existing token", %{company: company} do
      config = ServiceConfig.get_or_create_classifier_config(company.id)

      {:ok, with_token} =
        ServiceConfig.update_classifier_config(config, %{"api_token" => "secret"})

      encrypted = with_token.api_token_encrypted

      {:ok, unchanged} =
        ServiceConfig.update_classifier_config(with_token, %{"url" => "http://x:3003"})

      assert unchanged.api_token_encrypted == encrypted
    end

    test "rejects invalid URL when enabled", %{company: company} do
      config = ServiceConfig.get_or_create_classifier_config(company.id)

      {:error, changeset} =
        ServiceConfig.update_classifier_config(config, %{"enabled" => true, "url" => "not-a-url"})

      assert errors_on(changeset).url != []
    end

    test "rejects out-of-range thresholds when enabled", %{company: company} do
      config = ServiceConfig.get_or_create_classifier_config(company.id)

      {:error, changeset} =
        ServiceConfig.update_classifier_config(config, %{
          "enabled" => true,
          "url" => "http://localhost:3003",
          "category_confidence_threshold" => "1.5",
          "tag_confidence_threshold" => "0.95"
        })

      assert errors_on(changeset).category_confidence_threshold != []
    end

    test "requires url and thresholds when enabled", %{company: company} do
      config = ServiceConfig.get_or_create_classifier_config(company.id)

      {:error, changeset} =
        ServiceConfig.update_classifier_config(config, %{"enabled" => true})

      assert errors_on(changeset).url != []
      assert errors_on(changeset).category_confidence_threshold != []
      assert errors_on(changeset).tag_confidence_threshold != []
    end

    test "skips validation when disabled", %{company: company} do
      config = ServiceConfig.get_or_create_classifier_config(company.id)

      {:ok, updated} =
        ServiceConfig.update_classifier_config(config, %{"enabled" => false})

      assert updated.enabled == false
    end
  end

  describe "company isolation" do
    test "different companies have independent configs" do
      company_a = insert(:company)
      company_b = insert(:company)

      config_a = ServiceConfig.get_or_create_classifier_config(company_a.id)
      config_b = ServiceConfig.get_or_create_classifier_config(company_b.id)

      ServiceConfig.update_classifier_config(config_a, %{
        "enabled" => true,
        "url" => "http://model-a:9000",
        "category_confidence_threshold" => "0.71",
        "tag_confidence_threshold" => "0.95"
      })

      ServiceConfig.update_classifier_config(config_b, %{
        "enabled" => true,
        "url" => "http://model-b:9001",
        "category_confidence_threshold" => "0.71",
        "tag_confidence_threshold" => "0.95"
      })

      a = ServiceConfig.get_classifier_config(company_a.id)
      b = ServiceConfig.get_classifier_config(company_b.id)

      assert a.url == "http://model-a:9000"
      assert b.url == "http://model-b:9001"
    end
  end
end
