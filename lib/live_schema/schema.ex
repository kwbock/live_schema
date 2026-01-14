defmodule LiveSchema.Schema do
  @moduledoc """
  DSL for defining LiveSchema state structures.

  The schema macro provides a clean, declarative way to define your LiveView
  state with type information, defaults, and nested structures.

  ## Basic Usage

      defmodule MyApp.PostsState do
        use LiveSchema

        schema do
          field :posts, {:list, {:struct, Post}}, default: []
          field :selected, {:struct, Post}, null: true
          field :loading, :boolean, default: false
        end
      end

  ## Field Options

  - `:default` - Default value for the field
  - `:null` - If true, field accepts nil values (default: false)
  - `:required` - If true, field must be non-nil after initialization
  - `:validate` - Custom validation function or list of validators
  - `:setter` - Custom setter name (use `false` to disable setter generation)
  - `:doc` - Documentation string for the field
  - `:redact` - If true, hides field value in inspect output

  ## Embeds

  Use `embeds_one` and `embeds_many` for nested state structures:

      schema do
        field :title, :string

        embeds_one :filter do
          field :status, {:enum, [:all, :active]}, default: :all
          field :query, :string, default: ""
        end

        embeds_many :tags do
          field :name, :string
          field :color, :string
        end
      end

  """

  @doc """
  Defines the schema for a LiveSchema state module.

  This macro collects field definitions and generates the struct,
  type specs, setters, and constructors.
  """
  defmacro schema(do: block) do
    quote do
      # Process the schema block to collect fields
      unquote(block)

      # Generate everything from collected attributes
      # (handled by @before_compile in LiveSchema.Compiler)
    end
  end

  @doc """
  Defines a field in the schema.

  ## Parameters

  - `name` - The field name (atom)
  - `type` - The type specification (see `LiveSchema.Types`)
  - `opts` - Options keyword list

  ## Options

  - `:default` - Default value for the field
  - `:null` - If true, field accepts nil values (default: false)
  - `:required` - If true, must be non-nil after initialization
  - `:validate` - Custom validator (function or list)
  - `:setter` - Custom setter name or `false` to disable
  - `:doc` - Documentation string
  - `:redact` - If true, hidden in inspect output

  ## Examples

      field :name, :string
      field :count, :integer, default: 0
      field :status, {:enum, [:pending, :done]}, default: :pending
      field :selected, {:struct, Post}, null: true
      field :email, :string, required: true, validate: &valid_email?/1
      field :password, :string, redact: true

  """
  defmacro field(name, type, opts \\ []) do
    quote do
      @live_schema_fields {unquote(name), unquote(type), unquote(opts)}
    end
  end

  @doc """
  Defines a single embedded struct.

  Can be defined inline with a do block or reference an existing module.

  ## Inline Definition

      embeds_one :filter do
        field :status, {:enum, [:all, :active]}, default: :all
        field :search, :string, default: ""
      end

  ## Module Reference

      embeds_one :filter, MyApp.FilterState

  """
  # 2-arg version: embeds_one :filter do ... end
  defmacro embeds_one(name, do: block) do
    quote bind_quoted: [name: name, block: Macro.escape(block, unquote: true)] do
      @live_schema_embeds {name, :one, {:inline, block}, []}
    end
  end

  # 2-arg version with module: embeds_one :filter, MyModule
  defmacro embeds_one(name, module) when is_atom(module) do
    quote do
      @live_schema_embeds {unquote(name), :one, {:module, unquote(module)}, []}
    end
  end

  # 3-arg version with opts: embeds_one :filter, [opt: val] do ... end
  defmacro embeds_one(name, opts, do: block) do
    quote bind_quoted: [name: name, opts: opts, block: Macro.escape(block, unquote: true)] do
      @live_schema_embeds {name, :one, {:inline, block}, opts}
    end
  end

  @doc """
  Defines a list of embedded structs.

  Can be defined inline with a do block or reference an existing module.

  ## Inline Definition

      embeds_many :tags do
        field :name, :string
        field :color, :string, default: "#000000"
      end

  ## Module Reference

      embeds_many :comments, MyApp.Comment

  """
  # 2-arg version: embeds_many :tags do ... end
  defmacro embeds_many(name, do: block) do
    quote bind_quoted: [name: name, block: Macro.escape(block, unquote: true)] do
      @live_schema_embeds {name, :many, {:inline, block}, []}
    end
  end

  # 2-arg version with module: embeds_many :tags, MyModule
  defmacro embeds_many(name, module) when is_atom(module) do
    quote do
      @live_schema_embeds {unquote(name), :many, {:module, unquote(module)}, []}
    end
  end

  # 3-arg version with opts: embeds_many :tags, [opt: val] do ... end
  defmacro embeds_many(name, opts, do: block) do
    quote bind_quoted: [name: name, opts: opts, block: Macro.escape(block, unquote: true)] do
      @live_schema_embeds {name, :many, {:inline, block}, opts}
    end
  end
end
