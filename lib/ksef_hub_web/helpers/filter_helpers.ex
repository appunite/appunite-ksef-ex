defmodule KsefHubWeb.FilterHelpers do
  @moduledoc """
  Shared helper functions for parsing URL filter params and building query param maps.

  Used by invoice list, dashboard, and payment request LiveViews to avoid
  duplicating filter parsing, URL serialization, and form-building logic.
  """

  @doc "Puts `value` into `map` at `key` unless it is nil or empty string."
  @spec maybe_put(map(), String.t(), String.t() | nil) :: map()
  def maybe_put(map, _key, nil), do: map
  def maybe_put(map, _key, ""), do: map
  def maybe_put(map, key, value), do: Map.put(map, key, value)

  @doc "Parses an ISO8601 date string and puts it into the map."
  @spec maybe_put_date(map(), atom(), String.t() | nil) :: map()
  def maybe_put_date(map, _key, nil), do: map
  def maybe_put_date(map, _key, ""), do: map

  def maybe_put_date(map, key, value) do
    case Date.from_iso8601(value) do
      {:ok, date} -> Map.put(map, key, date)
      _ -> map
    end
  end

  @doc "Puts a non-empty search string into the map."
  @spec maybe_put_search(map(), atom(), String.t() | nil) :: map()
  def maybe_put_search(map, _key, nil), do: map
  def maybe_put_search(map, _key, ""), do: map
  def maybe_put_search(map, key, value), do: Map.put(map, key, value)

  @doc "Parses a positive integer string and puts it into the map."
  @spec maybe_put_page(map(), atom(), String.t() | nil) :: map()
  def maybe_put_page(map, _key, nil), do: map
  def maybe_put_page(map, _key, ""), do: map

  def maybe_put_page(map, key, value) do
    case Integer.parse(value) do
      {int, ""} when int > 0 -> Map.put(map, key, int)
      _ -> map
    end
  end

  @doc "Casts a string to an Ecto enum value and puts it into the map."
  @spec maybe_put_enum(map(), atom(), String.t() | nil, module(), atom()) :: map()
  def maybe_put_enum(map, _key, nil, _schema, _field), do: map
  def maybe_put_enum(map, _key, "", _schema, _field), do: map

  def maybe_put_enum(map, key, value, schema, field) do
    type = schema.__schema__(:type, field)

    case Ecto.Type.cast(type, value) do
      {:ok, atom} -> Map.put(map, key, atom)
      :error -> map
    end
  end

  @doc """
  Parses a comma-separated string into a list of validated values.

  Options:
  - `:valid` — list of valid string values (rejects others)
  - `:validate` — function `(String.t()) -> boolean()` for custom validation
  - `:transform` — function `(String.t()) -> term()` applied after validation

  ## Examples

      # With valid list + atom transform
      maybe_put_csv(map, :statuses, "pending,approved", valid: ~w(pending approved rejected), transform: &String.to_existing_atom/1)

      # With custom validation (UUID)
      maybe_put_csv(map, :category_ids, "uuid1,uuid2", validate: fn id -> match?({:ok, _}, Ecto.UUID.cast(id)) end)

      # No validation (free-form tags)
      maybe_put_csv(map, :tags, "monthly,recurring")
  """
  @spec maybe_put_csv(map(), atom(), String.t() | nil, keyword()) :: map()
  def maybe_put_csv(map, key, value, opts \\ [])
  def maybe_put_csv(map, _key, nil, _opts), do: map
  def maybe_put_csv(map, _key, "", _opts), do: map

  def maybe_put_csv(map, key, value, opts) do
    valid = Keyword.get(opts, :valid)
    validate = Keyword.get(opts, :validate)
    transform = Keyword.get(opts, :transform)

    items =
      value
      |> String.split(",", trim: true)
      |> then(fn items ->
        cond do
          valid -> Enum.filter(items, &(&1 in valid))
          validate -> Enum.filter(items, validate)
          true -> items
        end
      end)
      |> then(fn items ->
        if transform, do: Enum.map(items, transform), else: items
      end)

    if items == [], do: map, else: Map.put(map, key, items)
  end

  @doc """
  Toggles a value in a multi-select filter list.

  Returns the updated filters map with the value added or removed from the list at `key`.
  Normalizes existing values to strings for comparison.
  """
  @allowed_filter_fields ~w(statuses expense_category_ids tags payment_statuses)a

  @spec toggle_filter_value(map(), String.t(), String.t()) :: map()
  def toggle_filter_value(filters, field, value) do
    key = Enum.find(@allowed_filter_fields, fn k -> Atom.to_string(k) == field end)
    if is_nil(key), do: raise("Invalid filter field: #{inspect(field)}")
    current = Enum.map(Map.get(filters, key, []), &to_string/1)

    updated =
      if value in current,
        do: List.delete(current, value),
        else: current ++ [value]

    Map.put(filters, key, updated)
  end

  @doc "Clears all selections for the given filter field, returning updated filters."
  @spec clear_filter_field(map(), String.t()) :: map()
  def clear_filter_field(filters, field) do
    key = Enum.find(@allowed_filter_fields, fn k -> Atom.to_string(k) == field end)
    if is_nil(key), do: raise("Invalid filter field: #{inspect(field)}")
    Map.put(filters, key, [])
  end

  @doc "Converts an atom or string to a string, returning empty string for nil."
  @spec to_string_or_empty(atom() | String.t() | nil) :: String.t()
  def to_string_or_empty(nil), do: ""
  def to_string_or_empty(value) when is_atom(value), do: Atom.to_string(value)
  def to_string_or_empty(value) when is_binary(value), do: value

  @doc "Parses tags from a list param or CSV fallback into the map."
  @spec maybe_put_tags(map(), atom(), list() | String.t() | nil) :: map()
  def maybe_put_tags(map, _key, nil), do: map
  def maybe_put_tags(map, _key, []), do: map
  def maybe_put_tags(map, key, tags) when is_list(tags), do: Map.put(map, key, tags)
  def maybe_put_tags(map, _key, ""), do: map

  def maybe_put_tags(map, key, value) when is_binary(value) do
    tags = String.split(value, ",", trim: true)
    if tags == [], do: map, else: Map.put(map, key, tags)
  end

  @doc "Puts a list as repeated query params, returns map unchanged for nil or empty list."
  @spec maybe_put_list(map(), String.t(), list() | nil) :: map()
  def maybe_put_list(map, _key, nil), do: map
  def maybe_put_list(map, _key, []), do: map
  def maybe_put_list(map, key, list), do: Map.put(map, key, list)

  @doc "Joins a list into a comma-separated string, returns nil for nil or empty list."
  @spec join_list(list() | nil) :: String.t() | nil
  def join_list(nil), do: nil
  def join_list([]), do: nil
  def join_list(list), do: Enum.join(list, ",")

  @doc "Converts a Date to ISO8601 string, returns nil for nil."
  @spec date_to_string(Date.t() | nil) :: String.t() | nil
  def date_to_string(nil), do: nil
  def date_to_string(date), do: Date.to_iso8601(date)

  @doc "Builds a category label with optional emoji prefix."
  @spec category_label(map()) :: String.t()
  def category_label(cat) do
    prefix = if cat.emoji, do: "#{cat.emoji} ", else: ""
    "#{prefix}#{cat.name || cat.identifier}"
  end
end
