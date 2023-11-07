# pokemon_entry =
#   %{
#     abra: %{
#       "" => ["autumn", "dark"]
#     }
#   }

# spawn_data_entry =
#   %{
#     "autumn" => ["byg:aspen_forect_hills", "redwoods"]
#   }

# rarity = 0.5

Mix.install([
  {:csv, "~> 3.2"},
  {:jason, "~> 1.4"}
])

defmodule AddSpawningData do
  def import_pixelmon_data(file_path) do
    file_path
    |> Path.expand(__DIR__)
    |> File.stream!()
    |> CSV.decode!(headers: true)
    |> Enum.group_by(&(&1["pokemon"]))
    |>Map.new(
      fn {k,v} ->
        value = Enum.group_by(
          v,
          fn %{"form" => form} ->
            case form do
              "galar" -> "galarian"
              "alola" -> "alolan"
              f -> f
            end
          end,
          fn %{"set" => set} ->
            set
          end
        )
        {k, value}
      end
    )
  end

  def import_spawning_data(file_path) do
    file_path
    |> Path.expand(__DIR__)
    |> File.stream!()
    |> CSV.decode!()
    |>Map.new(
      fn [k | v] ->
        value = Enum.reject(v, fn x -> x == "" end)
        {k, value}
      end
    )
  end

  def map_json_file_paths(file_path) do
    Path.wildcard(file_path <> "*.json")
    |>Enum.map(
      fn file_path ->
        key =
        Regex.run(~r/(.*?)(?=\.)/, Path.basename(file_path))
        |> Enum.at(1)
        {String.to_atom(key), file_path}
      end
    )
  end

  def create_spawn_info(spawn_info_template, id, form, palette, biomes) do
    spawn_info_template
    |> set_spec(id, form, palette)
    |> set_biomes(biomes)
    |> put_in([:rarity], 0.5)
  end

  def set_spec(spawn_info, id, "", palette) do
    put_in(
      spawn_info,
      [:spec],
      "species:#{id} palette:#{palette}"
    )
  end

  def set_spec(spawn_info, id, form, palette) do
    put_in(
      spawn_info,
      [:spec],
      "species:#{id} form:#{form} palette:#{palette}"
    )
  end

  def set_biomes(spawn_info, ["clone"]) do
    spawn_info
  end

  def set_biomes(spawn_info, biomes) do
   put_in(
      spawn_info,
      [:condition, :stringBiomes],
      biomes
    )
  end
end


json_directory = "spawning/standard/"

IO.puts("Importing CSV data")
pixelmon_data = AddSpawningData.import_pixelmon_data("../pixelmon-parser/pixelmon_data.csv")

spawning_data = AddSpawningData.import_spawning_data("../pixelmon-parser/spawning_data.csv")

json_file_maping = AddSpawningData.map_json_file_paths(json_directory)

IO.inspect(json_file_maping)

pixelmon_data
|> Enum.reduce(
  [],
  fn {k,forms}, errors ->
    #IO.puts("..Started processing pokemon: #{k}")
    with {:ok, file_path} <- Keyword.fetch(json_file_maping, String.to_atom(k)),
         {:ok, json_file} <- File.read(file_path),
         {:ok, data} <- Jason.decode(json_file, keys: :atoms, objects: :ordered_objects) do
          spawn_info = data[:spawnInfos] |> List.first()
          id = data[:id]
          new_spawn_infos =
            Enum.reduce(
              forms,
              [],
              fn {form,palettes}, new_entries ->
                #IO.puts("....Processing form: #{form}")
                Enum.reduce(
                  palettes,
                  new_entries,
                  fn palette, new_entries ->
                    case Map.get(spawning_data, palette) do
                      nil -> new_entries
                      biomes -> info = AddSpawningData.create_spawn_info(spawn_info, id, form, palette, biomes)
                      [info | new_entries]
                    end
                  end
                )
              end
            )
          #IO.inspect(new_spawn_infos, pretty: true, syntax_colors: IO.ANSI.syntax_colors() )
          updated_json =
            update_in(data,[:spawnInfos],&(&1 ++ new_spawn_infos))
            |> Jason.encode!()

          File.write("output/standard/#{k}.set.json", updated_json)
          # IO.puts("..Successfuly processed pokemon: #{k}")
          errors
    else
      {:error, %{position: _, token: _, data: _}} ->
        error_entry = %{file: k, reason: "JSON parse error"}
        [error_entry | errors]
      {:error, error} ->
        error_entry = %{file: k, reason: error}
        [error_entry | errors]
      _ -> errors
    end
  end
)
|> IO.inspect(pretty: true, syntax_colors: IO.ANSI.syntax_colors())
