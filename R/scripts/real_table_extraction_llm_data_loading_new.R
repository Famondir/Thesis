library(jsonlite)
library(tidyverse)

#### Final ####

json_files_table_extraction_llm <- list.files(
  "../benchmark_results/table_extraction/llm/final/real_tables_more_examples/",
  pattern = "\\.json$",
  full.names = TRUE
) %>%
  .[!grepl("_test_", .)] %>% 
  .[!grepl("synth", .)]

meta_list_llm <- list()

error_list <- c()

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
  if (str_detect(name_split[1], "gpt-oss")) next
  method_index = which(str_starts((basename(file) %>% str_split("__"))[[1]], "loop"))-1
  # print(name_split)
  
  results <-  json_data$results %>% as_tibble()
  
  if (nrow(results) == 0) {
    error_list <-  c(error_list, file)
    next
  }
  
  results <-  results %>% rowwise() %>%  
    mutate(
      model = name_split[1], 
      method = name_split[method_index],
      n_examples = str_match(method, "\\d+")[[1]],
      out_of_company = if_else(str_detect(method, "rag"), str_detect(basename(file), "out_of_sample") == TRUE, NA),
      method_family = str_replace(str_replace(method, '\\d+', 'n'), '_out_of_sample', ''),
      loop = as.numeric((basename(file) %>% str_match("loop_(.)(_queued)?\\.json"))[2]),
      predictions = list(fromJSON(df_joined) %>% as_tibble()),
      request_tokens = list(json_data$request_tokens),
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
    NA_precision = if_else(NA_total_truth > 0, if_else((NA_true_positive + NA_false_positive)>0, NA_true_positive/(NA_true_positive + NA_false_positive), 0), NA),
    NA_recall = if_else(NA_total_truth > 0, NA_true_positive/(NA_true_positive + NA_false_negative), NA),
    NA_F1 = if_else((NA_precision + NA_recall) > 0, (2 * NA_precision * NA_recall)/(NA_precision + NA_recall), 0),
    percentage_correct_numeric = if_else((correct_numeric + incorrect_numeric)>0, correct_numeric/(correct_numeric + incorrect_numeric), 0),
    percentage_correct_total = (correct_numeric + NA_true_positive)/total_entries
  ) %>% mutate(
    model = str_replace(model, "_vllm", ""),
    model_family = sub("_.*", "", model),
    model_family = if_else(str_detect(model, "Qwen2"), "Qwen 2.5", model_family),
    model_family = if_else(str_detect(model, "Qwen3"), "Qwen 3", model_family),
    model_family = if_else(str_detect(model, "Llama-3"), "Llama-3", model_family),
    model_family = if_else(str_detect(model, "Llama-4"), "Llama-4", model_family)
  ) %>% mutate(
    n_examples = as.numeric(n_examples),
    n_examples = if_else(method_family == "zero_shot", 0, n_examples),
    n_examples = if_else(method_family == "static_example", 1, n_examples)
  ) %>% mutate(
    filepath = str_replace(filepath, "/pvc/benchmark_truth/real_tables_extended/Tempelhof Projekt GmbH __", "/pvc/benchmark_truth/real_tables_extended/Tempelhof Projekt GmbH__")
  )

df %>%
  saveRDS("data_storage/real_table_extraction_extended_llm.rds")

# # with NAs
# extract_wrong_values <- function(df) {
#   df %>% mutate(
#     mistake_year = (year_truth != year_result) | (is.na(year_truth) & !is.na(year_result)) | (is.na(year_result) & !is.na(year_truth)),
#     mistake_year = if_else(is.na(mistake_year), FALSE, mistake_year),
#     mistake_previous_year =(previous_year_truth != previous_year_result) | (is.na(previous_year_truth) & !is.na(previous_year_result)) | (is.na(previous_year_result) & !is.na(previous_year_truth)),
#     mistake_previous_year = if_else(is.na(mistake_previous_year), FALSE, mistake_previous_year)
#   ) %>% select(
#     year_truth, year_result, 
#     previous_year_truth, previous_year_result,
#     mistake_year, mistake_previous_year
#   ) %>% 
#     filter(mistake_year | mistake_previous_year)  
# }
# 
# # only floats
# extract_wrong_floats <- function(df) {
#   df %>% mutate(
#     mistake_year = (year_truth != year_result),
#     mistake_previous_year =(previous_year_truth != previous_year_result)
#   ) %>% select(
#     year_truth, year_result, 
#     previous_year_truth, previous_year_result,
#     mistake_year, mistake_previous_year
#   ) %>% 
#     filter(mistake_year | mistake_previous_year)
# }
# 
# relative_float_diff <- df %>% 
#   mutate(wrong_floats = map(predictions, extract_wrong_floats)) %>%
#   select(filepath, wrong_floats, model, method) %>% 
#   rowwise() %>% mutate(n_wrong_floats = nrow(wrong_floats)) %>% 
#   filter(n_wrong_floats>0) %>% 
#   unnest(wrong_floats) %>% 
#   mutate(
#     ratio_this_year = year_result/year_truth,
#     ratio_previous_year = previous_year_result/previous_year_truth
#   ) %>% pivot_longer(
#     cols = c(ratio_this_year, ratio_previous_year),
#     names_to = "year_type",
#     values_to = "ratio",
#     names_prefix = "ratio_"
#   ) %>% unique()
# 
# # relative_float_diff %>% saveRDS("data_storage/relative_float_diff_with_mistakes.rds")
# 
# # checked (log 10 ratio and differing truth log 10)
# integer_multiplier <- relative_float_diff %>% 
#   filter(log(ratio, base = 10) == as.integer(log(ratio, base = 10)), ratio != 1, 
#          as.integer(log(year_truth, base = 10)) != as.integer(log(previous_year_truth, base = 10))
#   ) %>% unique()
# 
# # checked (log 10 ratio)
# integer_multiplier <- relative_float_diff %>% 
#   filter(log(ratio, base = 10) == as.integer(log(ratio, base = 10)), ratio != 1
#   ) %>% unique()
# 
# # unchecked (random ratio)
# integer_multiplier <- relative_float_diff %>% 
#   filter(!(log(ratio, base = 10) == as.integer(log(ratio, base = 10)))
#   ) %>% unique()
# 
# 
# paths <- dir("../manual_download/", full.names=TRUE, recursive=TRUE)
# n_mistakes_identified <- tibble(change_date = file.info(paths)$ctime) %>% 
#   filter(change_date > as.POSIXct("2025-07-23")) %>% nrow()

#### Synth Context ####

json_files_table_extraction_llm <- list.files(
  "../benchmark_results/table_extraction/llm/final/real_tables_more_examples/",
  pattern = "\\.json$",
  full.names = TRUE
) %>%
  .[!grepl("_test_", .)] %>% 
  .[grepl("synth", .)]

meta_list_llm <- list()
error_list <- c()

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
  
  results <-  json_data$results %>% as_tibble()
  
  if (nrow(results) == 0) {
    error_list <-  c(error_list, file)
    next
  }
  
  results <-  results %>% rowwise() %>%  
    mutate(
      model = name_split[1], 
      method = name_split[method_index],
      n_examples = str_match(method, "\\d+")[[1]],
      ignore_units = if_else((name_split[method_index+1] %>% str_split('_') %>% .[[1]] %>% .[3]) == "True", TRUE, FALSE),
      out_of_company = if_else(str_detect(method, "rag"), str_detect(basename(file), "out_of_sample") == TRUE, NA),
      method_family = str_replace(str_replace(method, '\\d+', 'n'), '_out_of_sample', ''),
      loop = as.numeric((basename(file) %>% str_match("loop_(.)(_queued)?\\.json"))[2]),
      predictions = list(fromJSON(df_joined) %>% as_tibble()),
      runtime = json_data$runtime,
      request_tokens = list(json_data$request_tokens)
    ) %>% select(-df_joined)
  
  # results$predictions <- predictions
  meta_list_llm[[length(meta_list_llm) + 1]] <- results
}

df_synth <- bind_rows(meta_list_llm) %>% select(!starts_with("changed_values")) %>% 
  filter(grammar_error != TRUE || is.na(grammar_error)) %>%
  unnest_wider(`NA`, names_sep = "_") %>%
  unnest_wider(`relative_numeric_difference`, names_sep = "_") %>%
  unnest_wider(`levenstein_distance`, names_sep = "_") %>%
  # rename_with(~ gsub("^NA_", "NA_", .x)) %>%  # Ensures prefix is NA_
  mutate(
    NA_total_truth = NA_true_positive + NA_false_negative,
    NA_precision = if_else(NA_total_truth > 0, if_else((NA_true_positive + NA_false_positive)>0, NA_true_positive/(NA_true_positive + NA_false_positive), 0), NA),
    NA_recall = if_else(NA_total_truth > 0, NA_true_positive/(NA_true_positive + NA_false_negative), NA),
    NA_F1 = if_else((NA_precision + NA_recall) > 0, (2 * NA_precision * NA_recall)/(NA_precision + NA_recall), 0),
    percentage_correct_numeric = if_else((correct_numeric + incorrect_numeric)>0, correct_numeric/(correct_numeric + incorrect_numeric), 0),
    percentage_correct_total = (correct_numeric + NA_true_positive)/total_entries
  ) %>% mutate(
    model = str_replace(model, "_vllm", ""),
    model_family = sub("_.*", "", model),
    model_family = if_else(str_detect(model, "Qwen2"), "Qwen 2.5", model_family),
    model_family = if_else(str_detect(model, "Qwen3"), "Qwen 3", model_family),
    model_family = if_else(str_detect(model, "Llama-3"), "Llama-3", model_family),
    model_family = if_else(str_detect(model, "Llama-4"), "Llama-4", model_family)
  ) %>% mutate(
    n_examples = as.numeric(n_examples),
    n_examples = if_else(method_family == "zero_shot", 0, n_examples),
    n_examples = if_else(method_family == "static_example", 1, n_examples)
  ) %>% mutate(
    filepath = str_replace(filepath, "/pvc/benchmark_truth/real_tables_extended/Tempelhof Projekt GmbH __", "/pvc/benchmark_truth/real_tables_extended/Tempelhof Projekt GmbH__")
  )

df_synth %>% 
  saveRDS("data_storage/real_table_extraction_extended_synth.rds")

#### Azure ####

json_files_table_extraction_llm <- list.files(
  "../benchmark_results/table_extraction/llm/final/real_tables_more_examples/openai/",
  pattern = "\\.json$",
  full.names = TRUE
) %>%
  .[!grepl("_test_", .)]

meta_list_llm <- list()
error_list <- list()

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
  method_index = which(str_starts((basename(file) %>% str_split("__"))[[1]], "loop"))-1
  # print(name_split)
  
  results <- json_data$results %>% as_tibble() %>% filter(!json_error)
  errors <- json_data$results %>% as_tibble() %>% filter(json_error)
  
  if (nrow(results) > 0) {
    results <- results %>% rowwise() %>%  
      mutate(
        model = name_split[1], 
        method = name_split[method_index],
        n_examples = str_match(method, "\\d+")[[1]],
        out_of_company = if_else(str_detect(method, "rag"), str_detect(basename(file), "out_of_sample") == TRUE, NA),
        method_family = str_replace(str_replace(method, '\\d+', 'n'), '_out_of_sample', ''),
        loop = as.numeric((basename(file) %>% str_match("loop_(.)(_queued)?\\.json"))[2]),
        predictions = list(fromJSON(df_joined) %>% as_tibble()),
        runtime = json_data$runtime,
        request_tokens = list(json_data$request_tokens)
      ) %>% select(-df_joined)
    
    meta_list_llm[[length(meta_list_llm) + 1]] <- results
  }
  
  if (nrow(errors) > 0) {
    # browser()
    error_list[[length(meta_list_llm) + 1]] <- errors %>% rowwise() %>% 
      mutate(
        model = name_split[1], 
        method = name_split[method_index],
        n_examples = str_match(method, "\\d+")[[1]],
        out_of_company = if_else(str_detect(method, "rag"), str_detect(basename(file), "out_of_sample") == TRUE, NA),
        method_family = str_replace(str_replace(method, '\\d+', 'n'), '_out_of_sample', ''),
        loop = as.numeric((basename(file) %>% str_match("loop_(.)(_queued)?\\.json"))[2]),
        request_tokens = list(json_data$request_tokens)
      )
  }
  
  # results$predictions <- predictions
}

df_errors <- bind_rows(error_list)

df_azure <- bind_rows(meta_list_llm) %>% select(!starts_with("changed_values")) %>% 
  filter(grammar_error != TRUE || is.na(grammar_error)) %>%
  unnest_wider(`NA`, names_sep = "_") %>%
  unnest_wider(`relative_numeric_difference`, names_sep = "_") %>%
  unnest_wider(`levenstein_distance`, names_sep = "_") %>%
  # rename_with(~ gsub("^NA_", "NA_", .x)) %>%  # Ensures prefix is NA_
  mutate(
    NA_total_truth = NA_true_positive + NA_false_negative,
    NA_precision = if_else(NA_total_truth > 0, if_else((NA_true_positive + NA_false_positive)>0, NA_true_positive/(NA_true_positive + NA_false_positive), 0), NA),
    NA_recall = if_else(NA_total_truth > 0, NA_true_positive/(NA_true_positive + NA_false_negative), NA),
    NA_F1 = if_else((NA_precision + NA_recall) > 0, (2 * NA_precision * NA_recall)/(NA_precision + NA_recall), 0),
    percentage_correct_numeric = if_else((correct_numeric + incorrect_numeric)>0, correct_numeric/(correct_numeric + incorrect_numeric), 0),
    percentage_correct_total = (correct_numeric + NA_true_positive)/total_entries
  ) %>% mutate(
    model_family = "chat-gpt"
  ) %>% mutate(
    model = str_replace(model, "_vllm", "")
  ) %>% mutate(
    n_examples = as.numeric(n_examples),
    n_examples = if_else(method_family == "zero_shot", 0, n_examples),
    n_examples = if_else(method_family == "static_example", 1, n_examples)
  )

# calc_metrics_all <- function(df) {
#   # browser()
#   df %>% nest(year = c(year_truth, year_result), previous_year = c(previous_year_truth, previous_year_result)) %>% pivot_longer(
#     cols = c(year, previous_year)
#   ) %>% unnest_wider(value) %>% mutate(
#     truth = if_else(name == "year", year_truth, previous_year_truth),
#     result = if_else(name == "year", year_result, previous_year_result)
#   ) %>% select(-contains("year")) %>% transmute(
#     true_positive = is.na(truth) & is.na(result),
#     true_negative = !is.na(truth) & !is.na(result),
#     false_positive = !is.na(truth) & is.na(result),
#     false_negative = is.na(truth) & !is.na(result),
#     both = `_merge` == "both",
#     numeric = !is.na(truth),
#     numeric_correct = truth == result,
#     n_row = 1
#   ) %>% summarise_all(~sum(., na.rm=TRUE)) %>% mutate(
#     new_recall = if_else(true_positive+false_negative>0, (true_positive/(true_positive+false_negative)), 0),
#     new_precision = if_else(true_positive+false_positive>0, (true_positive/(true_positive+false_positive)), 0),
#     new_F1 = if_else((new_precision + new_recall) > 0, (2 * new_precision * new_recall)/(new_precision + new_recall), 0),
#     numeric_incorrect = numeric - numeric_correct,
#     new_percentage_correct_numeric = numeric_correct/(numeric_correct + numeric_incorrect),
#     new_percentage_correct_total = (numeric_correct + true_positive)/n_row
#   )
#   # df %>% filter(`_merge` == "both") %>% nrow()
# }
# 
# df_temp <- df_azure %>% filter(model == "gpt-4.1-nano_azure") %>% 
#   mutate(
#   new_values = map(predictions, calc_metrics_all),
#   .before = 1
# ) %>% unnest_wider(new_values) %>% select(method,
#   NA_recall, new_recall, NA_precision, new_precision, NA_F1, new_F1, both,
#   percentage_correct_numeric, new_percentage_correct_numeric,
#   percentage_correct_total, new_percentage_correct_total, numeric
#   )
# 
# df_temp %>% pull(both) %>% hist()
# 
# df_null <- df_azure %>% filter(model == "gpt-4.1-nano_azure") %>% pull(predictions) %>% .[[1]] %>% mutate(
#   year_truth = NA,
#   previous_year_truth = NA
# )
# 
# null_list <- list()
# 
# for (i in 1:29) {
#   df_dummy <- df_null
#   df_dummy$year_truth = c(rep(1, i), rep(NA, 29-i))
#   df_dummy$previous_year_truth = c(rep(1, i), rep(NA, 29-i))
#   null_list[[i]] <- df_dummy %>% calc_metrics_all()
# }
# 
# bind_rows(null_list) %>% saveRDS("data_storage/null_scores.rds")
# bind_rows(null_list) %>% pivot_longer(c(new_percentage_correct_total, new_percentage_correct_numeric, new_F1)) %>% 
#   ggplot() +
#   geom_line(aes(x = numeric, y = value, color = name))

df_azure %>% 
  # filter(model %in% c(
  #   "gpt-4.1-nano", "gpt-4.1-mini", "gpt-4.1", 
  #   "openai_gpt-oss-20b", "gpt-oss-120b_azure", "gpt-5-mini_azure"
  # )) %>% 
  mutate(
    model = str_remove(model, "_azure")
  ) %>% 
  saveRDS("data_storage/real_table_extraction_extended_azure.rds")

df_errors %>% 
  saveRDS("data_storage/real_table_extraction_extended_azure_errors.rds")
