defmodule LiveSchema.Form do
  @moduledoc """
  Helpers for Phoenix form integration with LiveSchema.

  Provides utilities for converting between form params and state,
  and for building forms from LiveSchema changesets.

  ## Usage

      defmodule MyAppWeb.UserLive do
        use MyAppWeb, :live_view
        alias MyApp.UserState

        def mount(_params, _session, socket) do
          state = UserState.new()
          form = LiveSchema.Form.to_form(state)
          {:ok, assign(socket, state: state, form: form)}
        end

        def handle_event("validate", %{"user" => params}, socket) do
          changeset =
            socket.assigns.state
            |> LiveSchema.change()
            |> LiveSchema.Form.cast(params, [:name, :email])
            |> LiveSchema.validate()

          {:noreply, assign(socket, form: to_form(changeset, as: :user))}
        end

        def handle_event("save", %{"user" => params}, socket) do
          case socket.assigns.state
               |> LiveSchema.change()
               |> LiveSchema.Form.cast(params, [:name, :email])
               |> LiveSchema.validate()
               |> LiveSchema.apply() do
            {:ok, new_state} ->
              {:noreply, assign(socket, state: new_state)}

            {:error, changeset} ->
              {:noreply, assign(socket, form: to_form(changeset, as: :user))}
          end
        end
      end

  """

  alias LiveSchema.Changeset

  @doc """
  Converts a LiveSchema state struct to Phoenix.HTML.Form compatible data.

  ## Options

  - `:as` - The form name (default: derived from struct module)
  - `:id` - The form id (default: same as `:as`)

  ## Examples

      form = LiveSchema.Form.to_form(state)
      form = LiveSchema.Form.to_form(state, as: :user)

  """
  @spec to_form(struct(), keyword()) :: Phoenix.HTML.Form.t()
  def to_form(%{__struct__: module} = state, opts \\ []) do
    name = Keyword.get(opts, :as, default_form_name(module))
    id = Keyword.get(opts, :id, name)

    changeset = Changeset.new(state)

    Phoenix.HTML.FormData.to_form(changeset, [name: name, id: id] ++ opts)
  end

  @doc """
  Converts a LiveSchema changeset to Phoenix.HTML.Form.

  ## Examples

      changeset =
        state
        |> LiveSchema.change()
        |> LiveSchema.put(:name, "New Name")

      form = LiveSchema.Form.changeset_to_form(changeset, as: :user)

  """
  @spec changeset_to_form(Changeset.t(), keyword()) :: Phoenix.HTML.Form.t()
  def changeset_to_form(%Changeset{} = changeset, opts \\ []) do
    name = Keyword.get(opts, :as, default_form_name(changeset.module))
    id = Keyword.get(opts, :id, name)

    Phoenix.HTML.FormData.to_form(changeset, [name: name, id: id] ++ opts)
  end

  @doc """
  Casts form params into the changeset.

  Only casts the specified permitted fields.

  ## Examples

      changeset =
        state
        |> LiveSchema.change()
        |> LiveSchema.Form.cast(params, [:name, :email, :age])

  """
  @spec cast(Changeset.t(), map(), [atom()]) :: Changeset.t()
  def cast(%Changeset{} = changeset, params, permitted) when is_map(params) do
    changes =
      permitted
      |> Enum.reduce(%{}, fn field, acc ->
        string_key = to_string(field)

        case Map.fetch(params, string_key) do
          {:ok, value} ->
            cast_value = cast_field_value(changeset.module, field, value)
            Map.put(acc, field, cast_value)

          :error ->
            case Map.fetch(params, field) do
              {:ok, value} ->
                cast_value = cast_field_value(changeset.module, field, value)
                Map.put(acc, field, cast_value)

              :error ->
                acc
            end
        end
      end)

    Changeset.put_changes(changeset, changes)
  end

  @doc """
  Converts a state struct to form params.

  Useful when you need to pre-populate a form or send data to JavaScript.

  ## Examples

      params = LiveSchema.Form.state_to_params(state)
      # => %{"name" => "John", "email" => "john@example.com"}

  """
  @spec state_to_params(struct()) :: map()
  def state_to_params(%{__struct__: module} = state) do
    fields =
      if function_exported?(module, :__live_schema__, 1) do
        module.__live_schema__(:fields)
      else
        state |> Map.keys() |> Enum.reject(&(&1 == :__struct__))
      end

    Enum.reduce(fields, %{}, fn field, acc ->
      value = Map.get(state, field)
      Map.put(acc, to_string(field), value_to_param(value))
    end)
  end

  @doc """
  Converts form params to a state struct.

  ## Examples

      {:ok, state} = LiveSchema.Form.params_to_state(MyState, params)

  """
  @spec params_to_state(module(), map()) :: {:ok, struct()} | {:error, term()}
  def params_to_state(module, params) when is_atom(module) and is_map(params) do
    attrs =
      Enum.reduce(params, %{}, fn {key, value}, acc ->
        try do
          field = if is_atom(key), do: key, else: String.to_existing_atom(key)
          cast_value = cast_field_value(module, field, value)
          Map.put(acc, field, cast_value)
        rescue
          ArgumentError -> acc
        end
      end)

    module.new(attrs)
  end

  # Private helpers

  defp default_form_name(module) do
    module
    |> Module.split()
    |> List.last()
    |> Macro.underscore()
    |> String.to_atom()
  end

  defp cast_field_value(module, field, value) do
    field_info = get_field_info(module, field)

    if field_info do
      cast_to_type(value, field_info.type)
    else
      value
    end
  end

  defp get_field_info(module, field) do
    if function_exported?(module, :__live_schema__, 1) do
      module.__live_schema__({:field, field})
    else
      nil
    end
  end

  defp cast_to_type(value, :integer) when is_binary(value) do
    case Integer.parse(value) do
      {int, ""} -> int
      _ -> value
    end
  end

  defp cast_to_type(value, :float) when is_binary(value) do
    case Float.parse(value) do
      {float, ""} -> float
      _ -> value
    end
  end

  defp cast_to_type("true", :boolean), do: true
  defp cast_to_type("false", :boolean), do: false
  defp cast_to_type(value, :boolean) when is_binary(value), do: value != ""

  defp cast_to_type(value, {:enum, _values}) when is_binary(value) do
    String.to_existing_atom(value)
  rescue
    ArgumentError -> value
  end

  defp cast_to_type(value, {:nullable, _inner}) when value in ["", nil], do: nil
  defp cast_to_type(value, {:nullable, inner}), do: cast_to_type(value, inner)

  defp cast_to_type(value, _type), do: value

  defp value_to_param(nil), do: ""
  defp value_to_param(value) when is_atom(value), do: to_string(value)
  defp value_to_param(%{__struct__: _} = struct), do: state_to_params(struct)
  defp value_to_param(value) when is_list(value), do: Enum.map(value, &value_to_param/1)
  defp value_to_param(value), do: value
end

# Implement Phoenix.HTML.FormData for Changeset
if Code.ensure_loaded?(Phoenix.HTML.FormData) do
  defimpl Phoenix.HTML.FormData, for: LiveSchema.Changeset do
    def to_form(changeset, opts) do
      %Phoenix.HTML.Form{
        source: changeset,
        impl: __MODULE__,
        id: opts[:id] || opts[:name],
        name: opts[:name],
        data: changeset.data,
        params: stringify_keys(changeset.changes),
        errors: format_errors(changeset.errors),
        options: opts
      }
    end

    def to_form(changeset, form, field, opts) do
      value = LiveSchema.Changeset.get_field(changeset, field)

      case value do
        %{__struct__: _module} = nested ->
          nested_changeset = LiveSchema.Changeset.new(nested)
          to_form(nested_changeset, [name: "#{form.name}[#{field}]", id: "#{form.id}_#{field}"] ++ opts)

        _ ->
          raise "Cannot create nested form for non-struct field #{field}"
      end
    end

    def input_value(changeset, _form, field) do
      LiveSchema.Changeset.get_field(changeset, field)
    end

    def input_validations(_changeset, _form, _field) do
      []
    end

    defp stringify_keys(map) do
      Map.new(map, fn {k, v} -> {to_string(k), v} end)
    end

    defp format_errors(errors) do
      Enum.flat_map(errors, fn error ->
        [{error.field, {Enum.map_join(error.errors, ", ", fn {_, msg} -> msg end), []}}]
      end)
    end
  end
end
