defmodule Lotus.Web.Test.LazyResolver do
  @moduledoc false
  # A resolver that lives in a compiled `.beam` file so a test can unload it
  # and check that the resolver fallback loads it on demand.

  @behaviour Lotus.Web.Resolver

  @impl true
  def resolve_user(_conn), do: %{id: 7}

  @impl true
  def resolve_access(_user), do: :read_only

  @impl true
  def resolve_context(user), do: %{user_id: user[:id]}

  @impl true
  def resolve_scope(_user), do: %{tenant_id: "acme"}
end
