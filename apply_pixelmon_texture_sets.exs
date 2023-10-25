Mix.install([
  {:csv, "~> 3.2"},
  {:jason, "~> 1.4"}
])

IO.puts("Importing CSV data")
csv_data =
"../pixelmon-parser/pixelmon_data.csv"
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
      fn %{"form" => form, "set" => set, "pokemon" => name} ->
        folder_name = if form == "", do: name, else: "#{name}-#{form}"
        Jason.OrderedObject.new(
          [
            name: set,
            texture: "pixelmon:pokemon/#{set}/#{folder_name}/texture.png",
            sprite: "pixelmon:pokemon/#{set}/#{folder_name}/sprite.png",
            particle: ""
          ]
        )
      end
    )
    {k, value}
  end
)

Enum.count(Map.keys(csv_data))
|> IO.puts()

json_file_maping =
  Path.wildcard("*.json")
  |>Enum.map(
    fn file_path ->
      key =
      Regex.run(~r/_(.*?)\./, file_path)
      |> Enum.at(1)
      {String.to_atom(key), file_path}
    end
  )


IO.puts("Starting json file processing")
csv_data
|> Enum.each(
  fn {k,pixelmon_data} ->
    IO.puts("..Started processing pokemon: #{k}")
    with {:ok, file_path} <- Keyword.fetch(json_file_maping, String.to_atom(k)),
         {:ok, json_file} <- File.read(file_path),
         {:ok, data} <- Jason.decode(json_file, keys: :atoms, objects: :ordered_objects) do
          updated_json =
            Enum.reduce(
              pixelmon_data,
              data,
              fn {form,new_entries}, acc ->
                IO.puts("....Processing form: #{form}")
                # update the data
                filter = Access.filter(&(&1.values[:name] == form))
                update_in(
                  acc,
                  [:forms,filter,:genderProperties,Access.all(),:palettes],
                  &(&1 ++ new_entries)
                )
              end
            )
            |> Jason.encode!()

          File.write(file_path, updated_json)
          IO.puts("..Successfuly processed pokemon: #{k}")
    else
      {:error, error} ->
      IO.puts("..!Failed processing pokemon: #{k}!")
      IO.inspect(error)
      _ -> nil
    end
  end
)
