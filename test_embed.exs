defmodule TestEmbed do
  use LiveSchema

  schema do
    field :title, :string, default: ""

    embeds_one :filter do
      field :status, :atom, default: :all
    end
  end
end

# Check what was generated
IO.puts("Filter module exists: #{Code.ensure_loaded?(TestEmbed.Filter)}")
IO.puts("TestEmbed fields: #{inspect(TestEmbed.__live_schema__(:fields))}")
IO.puts("TestEmbed embeds: #{inspect(TestEmbed.__live_schema__(:embeds))}")
