library(jsonlite)
library(tidyverse)

unit_list = tribble(
  ~unit, ~multiplier,
  'EUR', 1, 
  '€', 1, 
  'Tsd. EUR', 1000, 
  'Mio. EUR', 1000000, 
  'TEUR', 1000, 
  'T€', 1000, 
  'Tsd. €', 1000, 
  'Mio. €', 1000000
)

#### Final ####

json_files_table_extraction_llm <- list.files(
  "../benchmark_results/table_extraction/llm/final/synth_tables/",
  pattern = "\\.json$",
  full.names = TRUE
) %>%
  .[!grepl("_test_", .)] %>% 
  .[grepl("synth", .)]

meta_list_llm <- list()

# Loop through each .json file
for (file in json_files_table_extraction_llm) {
  # print(file)
  # Read the JSON file
  # Read the JSON file and replace NaN with NULL in the file content
  file_content <- readLines(file, warn = FALSE)
  file_content <- gsub("\\bNaN\\b", "null", file_content)
  file_content <- gsub("\\bInfinity\\b", "null", file_content)
  # Remove incomplete last JSON entry and close the list if file ends early
  # if (!grepl("\\]$", file_content[length(file_content)])) {
  #   # Find the last complete JSON object (ends with "},")
  #   last_complete <- max(grep('\\.pdf', file_content))
  #   file_content <- c(file_content[1:last_complete], "}]")
  # }
  json_data <- fromJSON(paste(file_content, collapse = "\n"))
  
  name_split = (basename(file) %>% str_split("__"))[[1]]
  method_index = which(str_starts((basename(file) %>% str_split("__"))[[1]], "ignore"))-1
  # print(name_split)
  
  results <-  json_data$results %>% as_tibble() %>% rowwise() %>%  
    mutate(
      model = name_split[1], 
      method = name_split[method_index],
      n_examples = str_match(method, "\\d+")[[1]],
      out_of_company = if_else(str_detect(method, "rag"), str_detect(method, "out_of_company"), NA),
      ignore_units = if_else((name_split[method_index+1] %>% str_split('_') %>% .[[1]] %>% .[3]) == "True", TRUE, FALSE),
      input_format = name_split[2] %>% str_split("_") %>% .[[1]] %>% .[length(.)],
      method_family = str_replace(str_replace(method, '\\d+', 'n'), '_out_of_company', ''),
      loop = as.numeric((basename(file) %>% str_match("loop_(.)(_queued)?\\.json"))[2]),
      predictions = list(fromJSON(df_joined) %>% as_tibble()),
      runtime = json_data$runtime
    ) %>% select(-df_joined)
  
  # results$predictions <- predictions
  meta_list_llm[[length(meta_list_llm) + 1]] <- results
}

df <- bind_rows(meta_list_llm) %>% select(!starts_with("changed_values")) %>% 
  filter(grammar_error != TRUE || is.na(grammar_error)) %>%
  unnest_wider(`NA`, names_sep = "_") %>%
  unnest_wider(`relative_numeric_difference`, names_sep = "_") %>%
  unnest_wider(`levenstein_distance`, names_sep = "_") %>%
  # rename_with(~ gsub("^NA_", "NA_", .x)) %>%  # Ensures prefix is NA_
  mutate(
    NA_total_truth = NA_true_positive + NA_false_negative,
    NA_precision = if_else(NA_total_truth > 0, NA_true_positive/(NA_true_positive + NA_false_positive), NA),
    NA_recall = if_else(NA_total_truth > 0, NA_true_positive/(NA_true_positive + NA_false_negative), NA),
    NA_F1 = if_else((NA_precision + NA_recall) > 0, (2 * NA_precision * NA_recall)/(NA_precision + NA_recall), 0),
    percentage_correct_numeric = correct_numeric/(correct_numeric + incorrect_numeric),
    percentage_correct_total = (correct_numeric + NA_true_positive)/total_entries
  ) %>% mutate(
    model = str_replace(model, "_vllm", ""),
    model_family = sub("_.*", "", model),
    model_family = if_else(str_detect(model, "Qwen2"), "Qwen 2.5", model_family),
    model_family = if_else(str_detect(model, "Qwen3"), "Qwen 3", model_family),
    model_family = if_else(str_detect(model, "Llama-3"), "Llama-3", model_family),
    model_family = if_else(str_detect(model, "Llama-4"), "Llama-4", model_family)
  )

# Vectorized version for efficiency (avoids rowwise)
df <- df %>%
  mutate(
    n_columns = str_match(filepath, "(\\d)_columns")[,2],
    header_span = str_match(filepath, "span_(False|True)")[,2] == "True",
    thin = str_match(filepath, "thin_(False|True)")[,2] == "True",
    year_as = str_match(filepath, "year_as_(.*)__unit")[,2],
    unit_in_first_cell = str_match(filepath, "unit_in_first_cell_(False|True)")[,2] == "True",
    unit_str = str_match(filepath, "unit_in_first_cell_(False|True)__(.*)__enumeration")[,3],
    enumeration = str_match(filepath, "enumeration_(False|True)")[,2] == "True",
    shuffle_rows = str_match(filepath, "shuffle_(False|True)")[,2] == "True",
    text_around = str_match(filepath, "text_around_(False|True)")[,2] == "True",
    max_line_length = str_match(filepath, "max_length_(\\d+)")[,2],
    sum_same_line = str_match(filepath, "sum_in_same_row_(False|True)")[,2] == "True"
  ) %>%
  left_join(unit_list, by = c("unit_str" = "unit")) %>%
  mutate(
    unit_multiplier = multiplier
  ) %>%
  select(-multiplier) %>% 
  mutate(
    n_columns = ordered(n_columns, c("3", "4", "5"))
  ) %>% mutate(
    n_examples = as.numeric(n_examples),
    n_examples = if_else(method_family == "zero_shot", 0, n_examples),
    n_examples = if_else(method_family == "static_example", 1, n_examples),
    many_line_breaks = if_else(max_line_length == 50, TRUE, FALSE)
  )

df %>% write_csv("data_storage/synth_table_extraction_llm.rds")
