defmodule LiveSchema.Component do
  @moduledoc """
  Phoenix.Component integration for LiveSchema.

  Provides enhanced `attr` declarations that work with LiveSchema types.

  ## Usage

      defmodule MyAppWeb.Components.PostCard do
        use Phoenix.Component
        use LiveSchema.Component

        # Use schema types in attr declarations
        schema_attr :post, MyApp.Post, required: true
        schema_attr :on_select, :function

        def post_card(assigns) do
          ~H\"\"\"
          <div class="post-card" phx-click={@on_select}>
            <h3><%= @post.title %></h3>
          </div>
          \"\"\"
        end
      end

  ## schema_attr Options

  All standard `attr` options are supported:

  - `:required` - Whether the attribute is required
  - `:default` - Default value
  - `:doc` - Documentation string
  - `:examples` - Example values for documentation

  Additionally:

  - For struct types, validation can verify the struct module
  - For LiveSchema modules, full type validation is available

  """

  @doc false
  defmacro __using__(_opts) do
    quote do
      import LiveSchema.Component, only: [schema_attr: 2, schema_attr: 3]
    end
  end

  @doc """
  Declares a component attribute with LiveSchema type support.

  Works like Phoenix.Component's `attr/3` but supports LiveSchema
  type specifications for enhanced validation.

  ## Examples

      # Struct type
      schema_attr :post, MyApp.Post, required: true

      # List of structs
      schema_attr :posts, {:list, MyApp.Post}, default: []

      # Enum type
      schema_attr :status, {:enum, [:pending, :active, :done]}

      # Nullable type
      schema_attr :selected, {:nullable, MyApp.Post}

  """
  defmacro schema_attr(name, type, opts \\ []) do
    phoenix_type = to_phoenix_type(type)

    quote do
      Module.put_attribute(__MODULE__, :live_schema_attrs, {
        unquote(name),
        unquote(Macro.escape(type)),
        unquote(opts)
      })

      # Use standard attr for Phoenix Component
      attr(unquote(name), unquote(phoenix_type), unquote(opts))
    end
  end

  # Convert LiveSchema types to Phoenix Component types
  defp to_phoenix_type({:struct, _module}), do: :map
  defp to_phoenix_type({:list, _inner}), do: :list
  defp to_phoenix_type({:map, _, _}), do: :map
  defp to_phoenix_type({:nullable, inner}), do: to_phoenix_type(inner)
  defp to_phoenix_type({:enum, _values}), do: :atom
  defp to_phoenix_type({:tuple, _types}), do: :any
  defp to_phoenix_type(:string), do: :string
  defp to_phoenix_type(:integer), do: :integer
  defp to_phoenix_type(:float), do: :float
  defp to_phoenix_type(:boolean), do: :boolean
  defp to_phoenix_type(:atom), do: :atom
  defp to_phoenix_type(:map), do: :map
  defp to_phoenix_type(:list), do: :list
  defp to_phoenix_type(:any), do: :any
  defp to_phoenix_type(module) when is_atom(module), do: :map
  defp to_phoenix_type(_), do: :any
end
