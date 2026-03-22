defmodule Mix.Tasks.Openings.PartitionSkew do
  use Mix.Task

  alias Bookmoves.GamesRepo

  @shortdoc "Reports positions storage skew"

  @switches [limit: :integer, include_empty: :boolean, order_by: :string]
  @requirements ["app.start"]

  @default_limit 20
  @default_order_by :rows
  @order_by_values [:rows, :bytes, :name]

  @usage "usage: mix openings.partition_skew [--limit N] [--include-empty] [--order-by rows|bytes|name]"

  @type partition_stat :: %{
          partition_name: String.t(),
          row_count: non_neg_integer(),
          total_bytes: non_neg_integer()
        }

  @impl Mix.Task
  @spec run([String.t()]) :: :ok
  def run(args) when is_list(args) do
    {opts, positional, invalid} = OptionParser.parse(args, strict: @switches)

    if invalid != [] do
      raise "invalid option(s): #{format_invalid_options(invalid)}"
    end

    if positional != [] do
      raise @usage
    end

    limit =
      opts
      |> Keyword.get(:limit, @default_limit)
      |> normalize_positive_integer(@default_limit)

    include_empty? = Keyword.get(opts, :include_empty, false)
    order_by = normalize_order_by(Keyword.get(opts, :order_by, @default_order_by))

    started_ms = System.monotonic_time(:millisecond)
    stats = fetch_partition_stats(order_by)
    filtered_stats = maybe_filter_empty(stats, include_empty?)
    summary = summarize(stats)
    shown_stats = Enum.take(filtered_stats, limit)

    print_report(shown_stats, summary, filtered_stats, include_empty?, order_by)

    elapsed_ms = System.monotonic_time(:millisecond) - started_ms
    IO.puts("elapsed: #{elapsed_ms} ms")
    :ok
  end

  @spec maybe_filter_empty([partition_stat()], boolean()) :: [partition_stat()]
  defp maybe_filter_empty(stats, true), do: stats

  defp maybe_filter_empty(stats, false) do
    Enum.reject(stats, fn stat -> stat.row_count == 0 end)
  end

  @spec normalize_order_by(String.t() | atom()) :: :rows | :bytes | :name
  defp normalize_order_by(value) when is_atom(value) and value in @order_by_values, do: value

  defp normalize_order_by(value) when is_binary(value) do
    case String.downcase(value) do
      "rows" -> :rows
      "bytes" -> :bytes
      "name" -> :name
      _ -> raise "invalid --order-by value: #{value}. expected rows, bytes, or name"
    end
  end

  defp normalize_order_by(value) do
    raise "invalid --order-by value: #{inspect(value)}. expected rows, bytes, or name"
  end

  @spec normalize_positive_integer(term(), pos_integer()) :: pos_integer()
  defp normalize_positive_integer(value, _fallback) when is_integer(value) and value > 0,
    do: value

  defp normalize_positive_integer(_value, fallback), do: fallback

  @spec fetch_partition_stats(:rows | :bytes | :name) :: [partition_stat()]
  defp fetch_partition_stats(order_by) do
    if positions_partitioned?() do
      fetch_partition_stats_partitioned(order_by)
    else
      fetch_partition_stats_unpartitioned()
    end
  end

  @spec positions_partitioned?() :: boolean()
  defp positions_partitioned? do
    query = """
    SELECT EXISTS (
      SELECT 1
      FROM pg_inherits
      WHERE inhparent = 'positions'::regclass
    )
    """

    GamesRepo
    |> Ecto.Adapters.SQL.query!(query, [], timeout: :infinity)
    |> Map.fetch!(:rows)
    |> case do
      [[true]] -> true
      _ -> false
    end
  rescue
    _error in Postgrex.Error -> false
  end

  @spec fetch_partition_stats_partitioned(:rows | :bytes | :name) :: [partition_stat()]
  defp fetch_partition_stats_partitioned(order_by) do
    query = """
    WITH partition_list AS (
      SELECT
        i.inhrelid AS partition_oid,
        i.inhrelid::regclass::text AS partition_name
      FROM pg_inherits i
      WHERE i.inhparent = 'positions'::regclass
    ),
    partition_rows AS (
      SELECT tableoid AS partition_oid, count(*)::bigint AS row_count
      FROM positions
      GROUP BY tableoid
    )
    SELECT
      p.partition_name,
      COALESCE(r.row_count, 0)::bigint AS row_count,
      pg_total_relation_size(p.partition_oid)::bigint AS total_bytes
    FROM partition_list p
    LEFT JOIN partition_rows r ON r.partition_oid = p.partition_oid
    ORDER BY #{order_by_sql(order_by)}
    """

    GamesRepo
    |> Ecto.Adapters.SQL.query!(query, [], timeout: :infinity)
    |> Map.fetch!(:rows)
    |> Enum.map(&to_partition_stat/1)
  rescue
    error in Postgrex.Error ->
      case error do
        %Postgrex.Error{postgres: %{code: :undefined_table}} ->
          raise "positions table is missing in GamesRepo. run migrations first"

        _other ->
          reraise error, __STACKTRACE__
      end
  end

  @spec fetch_partition_stats_unpartitioned() :: [partition_stat()]
  defp fetch_partition_stats_unpartitioned do
    query = """
    SELECT
      'positions'::text AS partition_name,
      count(*)::bigint AS row_count,
      pg_total_relation_size('positions'::regclass)::bigint AS total_bytes
    FROM positions
    """

    GamesRepo
    |> Ecto.Adapters.SQL.query!(query, [], timeout: :infinity)
    |> Map.fetch!(:rows)
    |> Enum.map(&to_partition_stat/1)
  rescue
    error in Postgrex.Error ->
      case error do
        %Postgrex.Error{postgres: %{code: :undefined_table}} ->
          raise "positions table is missing in GamesRepo. run migrations first"

        _other ->
          reraise error, __STACKTRACE__
      end
  end

  @spec order_by_sql(:rows | :bytes | :name) :: String.t()
  defp order_by_sql(:rows), do: "row_count DESC, partition_name ASC"
  defp order_by_sql(:bytes), do: "total_bytes DESC, partition_name ASC"
  defp order_by_sql(:name), do: "partition_name ASC"

  @spec to_partition_stat([term()]) :: partition_stat()
  defp to_partition_stat([partition_name, row_count, total_bytes])
       when is_binary(partition_name) do
    %{
      partition_name: partition_name,
      row_count: to_non_negative_integer(row_count),
      total_bytes: to_non_negative_integer(total_bytes)
    }
  end

  @spec to_non_negative_integer(term()) :: non_neg_integer()
  defp to_non_negative_integer(value) when is_integer(value) and value >= 0, do: value
  defp to_non_negative_integer(_value), do: 0

  @spec summarize([partition_stat()]) ::
          %{
            total_partitions: non_neg_integer(),
            non_empty_partitions: non_neg_integer(),
            total_rows: non_neg_integer(),
            total_bytes: non_neg_integer(),
            max_rows: non_neg_integer(),
            min_non_empty_rows: non_neg_integer(),
            avg_rows: float()
          }
  defp summarize(stats) do
    non_empty = Enum.reject(stats, fn stat -> stat.row_count == 0 end)
    total_rows = Enum.reduce(stats, 0, fn stat, acc -> acc + stat.row_count end)
    total_bytes = Enum.reduce(stats, 0, fn stat, acc -> acc + stat.total_bytes end)
    max_rows = stats |> Enum.map(& &1.row_count) |> Enum.max(fn -> 0 end)
    min_non_empty_rows = non_empty |> Enum.map(& &1.row_count) |> Enum.min(fn -> 0 end)

    avg_rows =
      if stats == [] do
        0.0
      else
        total_rows / length(stats)
      end

    %{
      total_partitions: length(stats),
      non_empty_partitions: length(non_empty),
      total_rows: total_rows,
      total_bytes: total_bytes,
      max_rows: max_rows,
      min_non_empty_rows: min_non_empty_rows,
      avg_rows: avg_rows
    }
  end

  @spec print_report(
          [partition_stat()],
          map(),
          [partition_stat()],
          boolean(),
          :rows | :bytes | :name
        ) :: :ok
  defp print_report(shown_stats, summary, filtered_stats, include_empty?, order_by) do
    IO.puts("positions storage skew")

    IO.puts(
      "order_by=#{order_by} include_empty=#{include_empty?} shown=#{length(shown_stats)}/#{length(filtered_stats)}"
    )

    IO.puts("partition         rows      rows%        size    size%")
    IO.puts("--------------------------------------------------------")

    Enum.each(shown_stats, fn stat ->
      IO.puts(format_partition_row(stat, summary.total_rows, summary.total_bytes))
    end)

    IO.puts("")
    IO.puts("total partitions: #{summary.total_partitions}")
    IO.puts("non-empty partitions: #{summary.non_empty_partitions}")
    IO.puts("total rows: #{format_int(summary.total_rows)}")
    IO.puts("total size: #{format_bytes(summary.total_bytes)}")
    IO.puts("max rows in one partition: #{format_int(summary.max_rows)}")

    IO.puts("max/avg rows ratio: #{format_ratio(summary.max_rows, summary.avg_rows)}")

    IO.puts(
      "max/min(non-empty) rows ratio: #{format_ratio(summary.max_rows, summary.min_non_empty_rows)}"
    )

    :ok
  end

  @spec format_partition_row(partition_stat(), non_neg_integer(), non_neg_integer()) :: String.t()
  defp format_partition_row(stat, total_rows, total_bytes) do
    rows_pct = percent(stat.row_count, total_rows)
    bytes_pct = percent(stat.total_bytes, total_bytes)

    [
      String.pad_trailing(stat.partition_name, 16),
      String.pad_leading(format_int(stat.row_count), 10),
      String.pad_leading(format_percent(rows_pct), 10),
      String.pad_leading(format_bytes(stat.total_bytes), 12),
      String.pad_leading(format_percent(bytes_pct), 8)
    ]
    |> Enum.join(" ")
  end

  @spec percent(non_neg_integer(), non_neg_integer()) :: float()
  defp percent(_value, 0), do: 0.0
  defp percent(value, total), do: value * 100 / total

  @spec format_percent(float()) :: String.t()
  defp format_percent(value) when is_number(value) do
    value
    |> Kernel.*(1.0)
    |> :erlang.float_to_binary(decimals: 2)
    |> then(&"#{&1}%")
  end

  @spec format_ratio(non_neg_integer(), number()) :: String.t()
  defp format_ratio(_numerator, denominator) when denominator in [0, 0.0], do: "n/a"

  defp format_ratio(numerator, denominator) do
    numerator
    |> Kernel./(denominator)
    |> :erlang.float_to_binary(decimals: 2)
  end

  @spec format_bytes(non_neg_integer()) :: String.t()
  defp format_bytes(bytes) when bytes < 1024, do: "#{bytes} B"

  defp format_bytes(bytes) when bytes < 1_048_576 do
    format_scaled(bytes, 1024, "KB")
  end

  defp format_bytes(bytes) when bytes < 1_073_741_824 do
    format_scaled(bytes, 1_048_576, "MB")
  end

  defp format_bytes(bytes) do
    format_scaled(bytes, 1_073_741_824, "GB")
  end

  @spec format_scaled(non_neg_integer(), pos_integer(), String.t()) :: String.t()
  defp format_scaled(bytes, scale, unit) do
    scaled = bytes / scale
    "#{:erlang.float_to_binary(scaled, decimals: 2)} #{unit}"
  end

  @spec format_int(non_neg_integer()) :: String.t()
  defp format_int(value) when is_integer(value) and value >= 0 do
    value
    |> Integer.to_string()
    |> String.reverse()
    |> String.to_charlist()
    |> Enum.chunk_every(3)
    |> Enum.map(&List.to_string/1)
    |> Enum.join(",")
    |> String.reverse()
  end

  @spec format_invalid_options([{atom() | String.t(), term()}]) :: String.t()
  defp format_invalid_options(invalid) do
    invalid
    |> Enum.map(fn {option, _value} ->
      option
      |> to_string()
      |> String.trim_leading("-")
      |> then(&"--#{&1}")
    end)
    |> Enum.join(", ")
  end
end
