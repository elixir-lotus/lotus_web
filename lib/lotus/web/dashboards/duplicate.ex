defmodule Lotus.Web.Dashboards.Duplicate do
  @moduledoc """
  A copy of a saved dashboard: its name (as a copy), description and
  refresh, its filters (with what each depends on), its cards (with their
  place and charts) and what each filter sets in each card. Not its public
  link: a copy is shared on its own.
  """

  use Gettext, backend: Lotus.Web.Gettext

  @doc """
  Copies the dashboard `id` in one transaction. `opts` are the actor's, for
  each write.
  """
  @spec copy(integer(), keyword()) :: {:ok, struct()} | {:error, term()}
  def copy(id, opts \\ []) do
    Lotus.repo().transaction(fn ->
      with %{} = dashboard <- Lotus.get_dashboard(id) || {:error, :not_found},
           {:ok, copy} <- Lotus.create_dashboard(dashboard_attrs(dashboard), opts),
           {:ok, filters} <- copy_filters(dashboard.id, copy, opts),
           :ok <- copy_cards(dashboard.id, copy, filters, opts) do
        copy
      else
        {:error, reason} -> Lotus.repo().rollback(reason)
      end
    end)
  end

  defp dashboard_attrs(dashboard) do
    %{
      name: gettext("%{name} (copy)", name: dashboard.name),
      description: dashboard.description,
      auto_refresh_seconds: dashboard.auto_refresh_seconds
    }
  end

  # The filters, then what each depends on: its parent may come after it.
  # Returns the new filter of each filter, by its id.
  defp copy_filters(dashboard_id, copy, opts) do
    filters = Lotus.list_dashboard_filters(dashboard_id)

    with {:ok, copies} <-
           create_each(filters, &Lotus.create_dashboard_filter(copy, filter_attrs(&1), opts)),
         :ok <- link_parents(filters, copies, opts) do
      {:ok, copies}
    end
  end

  defp link_parents(filters, copies, opts) do
    filters
    |> Enum.filter(& &1.depends_on_filter_id)
    |> each(fn filter ->
      Lotus.update_dashboard_filter(
        copies[filter.id],
        %{depends_on_filter_id: copies[filter.depends_on_filter_id].id},
        opts
      )
    end)
  end

  defp copy_cards(dashboard_id, copy, filters, opts) do
    cards = Lotus.list_dashboard_cards(dashboard_id, preload: [:filter_mappings])

    each(cards, fn card ->
      with {:ok, new_card} <- Lotus.create_dashboard_card(copy.id, card_attrs(card), opts) do
        each(card.filter_mappings, &copy_mapping(&1, new_card, filters, opts))
      end
    end)
  end

  defp copy_mapping(mapping, card, filters, opts) do
    Lotus.create_filter_mapping(
      card.id,
      filters[mapping.filter_id].id,
      mapping.variable_name,
      Keyword.put(opts, :transform, mapping.transform)
    )
  end

  defp filter_attrs(filter) do
    %{
      name: filter.name,
      label: filter.label,
      filter_type: filter.filter_type,
      widget: filter.widget,
      default_value: filter.default_value,
      position: filter.position,
      config: filter.config,
      source_query_id: filter.source_query_id
    }
  end

  defp card_attrs(card) do
    %{
      card_type: card.card_type,
      title: card.title,
      position: card.position,
      layout: layout(card.layout),
      query_id: card.query_id,
      visualization_config: card.visualization_config || %{},
      content: card.content || %{}
    }
  end

  defp layout(nil), do: nil

  defp layout(layout),
    do: %{
      x: layout.x,
      y: layout.y,
      w: layout.w,
      h: layout.h,
      folded: Map.get(layout, :folded, false)
    }

  # Creates each item, and returns what each became, by its id.
  defp create_each(items, create) do
    Enum.reduce_while(items, {:ok, %{}}, fn item, {:ok, ids} ->
      case create.(item) do
        {:ok, created} -> {:cont, {:ok, Map.put(ids, item.id, created)}}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
  end

  defp each(items, write) do
    Enum.reduce_while(items, :ok, fn item, :ok ->
      case write.(item) do
        {:error, _reason} = error -> {:halt, error}
        _written -> {:cont, :ok}
      end
    end)
  end
end
