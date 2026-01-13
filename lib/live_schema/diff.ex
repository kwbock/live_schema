defmodule LiveSchema.Diff do
  @moduledoc """
  Utilities for computing differences between state structs.

  Useful for testing, debugging, and tracking state changes.

  ## Usage

      {:changed, diff} = LiveSchema.diff(old_state, new_state)

      diff.changed   # List of changed field names
      diff.added     # Map of fields that went from nil to value
      diff.removed   # Map of fields that went from value to nil
      diff.nested    # Map of nested struct diffs

  """

  @type diff :: %{
          changed: [atom()],
          added: map(),
          removed: map(),
          modified: map(),
          nested: map()
        }

  @doc """
  Computes the difference between two state structs.

  Returns `:unchanged` if the structs are equal, or
  `{:changed, diff}` with details about what changed.

  ## Examples

      iex> old = %MyState{count: 0, name: "foo"}
      iex> new = %MyState{count: 1, name: "foo"}
      iex> LiveSchema.Diff.diff(old, new)
      {:changed, %{changed: [:count], added: %{}, removed: %{}, modified: %{count: {0, 1}}, nested: %{}}}

  """
  @spec diff(struct(), struct()) :: :unchanged | {:changed, diff()}
  def diff(%{__struct__: module} = old, %{__struct__: module} = new) do
    fields = get_fields(module)

    {changed, added, removed, modified, nested} =
      Enum.reduce(fields, {[], %{}, %{}, %{}, %{}}, fn field, acc ->
        old_val = Map.get(old, field)
        new_val = Map.get(new, field)

        compare_field(field, old_val, new_val, acc)
      end)

    if Enum.empty?(changed) do
      :unchanged
    else
      {:changed,
       %{
         changed: Enum.reverse(changed),
         added: added,
         removed: removed,
         modified: modified,
         nested: nested
       }}
    end
  end

  def diff(%{__struct__: old_mod}, %{__struct__: new_mod}) do
    {:changed,
     %{
       changed: [:__struct__],
       added: %{},
       removed: %{},
       modified: %{__struct__: {old_mod, new_mod}},
       nested: %{}
     }}
  end

  defp compare_field(_field, old_val, new_val, {changed, added, removed, modified, nested})
       when old_val == new_val do
    {changed, added, removed, modified, nested}
  end

  defp compare_field(field, nil, new_val, {changed, added, removed, modified, nested}) do
    {[field | changed], Map.put(added, field, new_val), removed, modified, nested}
  end

  defp compare_field(field, old_val, nil, {changed, added, removed, modified, nested}) do
    {[field | changed], added, Map.put(removed, field, old_val), modified, nested}
  end

  defp compare_field(field, %{__struct__: _} = old_val, %{__struct__: _} = new_val, acc) do
    {changed, added, removed, modified, nested} = acc

    case diff(old_val, new_val) do
      :unchanged ->
        {changed, added, removed, modified, nested}

      {:changed, inner_diff} ->
        {[field | changed], added, removed, modified, Map.put(nested, field, inner_diff)}
    end
  end

  defp compare_field(field, old_val, new_val, {changed, added, removed, modified, nested}) do
    {[field | changed], added, removed, Map.put(modified, field, {old_val, new_val}), nested}
  end

  defp get_fields(module) do
    if function_exported?(module, :__live_schema__, 1) do
      module.__live_schema__(:fields)
    else
      module.__struct__()
      |> Map.keys()
      |> Enum.reject(&(&1 == :__struct__))
    end
  end

  @doc """
  Returns a human-readable summary of the diff.
  """
  @spec format(diff()) :: String.t()
  def format(%{changed: changed, added: added, removed: removed, modified: modified}) do
    parts = []

    parts =
      if map_size(added) > 0 do
        added_str =
          added
          |> Enum.map(fn {k, v} -> "  + #{k}: #{inspect(v)}" end)
          |> Enum.join("\n")

        [["Added:", added_str] | parts]
      else
        parts
      end

    parts =
      if map_size(removed) > 0 do
        removed_str =
          removed
          |> Enum.map(fn {k, v} -> "  - #{k}: #{inspect(v)}" end)
          |> Enum.join("\n")

        [["Removed:", removed_str] | parts]
      else
        parts
      end

    parts =
      if map_size(modified) > 0 do
        modified_str =
          modified
          |> Enum.map(fn {k, {old, new}} -> "  ~ #{k}: #{inspect(old)} -> #{inspect(new)}" end)
          |> Enum.join("\n")

        [["Modified:", modified_str] | parts]
      else
        parts
      end

    case parts do
      [] ->
        "No changes to fields: #{inspect(changed)}"

      _ ->
        parts
        |> Enum.reverse()
        |> Enum.map(&Enum.join(&1, "\n"))
        |> Enum.join("\n\n")
    end
  end

  @doc """
  Asserts that specific fields changed between states.

  Useful in tests.

  ## Examples

      assert_changed(old, new, [:count, :name])

  """
  @spec assert_changed(struct(), struct(), [atom()]) :: :ok | no_return()
  def assert_changed(old, new, expected_fields) do
    case diff(old, new) do
      :unchanged ->
        raise ExUnit.AssertionError,
          message: "Expected fields #{inspect(expected_fields)} to change, but nothing changed"

      {:changed, %{changed: changed}} ->
        missing = expected_fields -- changed
        extra = changed -- expected_fields

        if Enum.empty?(missing) and Enum.empty?(extra) do
          :ok
        else
          message =
            []
            |> maybe_add("Missing expected changes", missing)
            |> maybe_add("Unexpected changes", extra)
            |> Enum.join("\n")

          raise ExUnit.AssertionError, message: message
        end
    end
  end

  defp maybe_add(parts, _label, []), do: parts
  defp maybe_add(parts, label, items), do: ["#{label}: #{inspect(items)}" | parts]
end
