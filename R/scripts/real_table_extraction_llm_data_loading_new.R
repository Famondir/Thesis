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
  # if (str_detect(name_split[1], "gpt-oss")) next
  method_index = which(str_starts((basename(file) %>% str_split("__"))[[1]], "loop"))-1
  # print(name_split)
  
  results <-  json_data$results %>% as_tibble()
  
  if (nrow(results) == 0) {
    error_list <-  c(error_list, file)
    next
  }
  
  # for (idx in 1:nrow(results)) {
  #   print(idx)
  #   # try()
  #   fromJSON(results$df_joined[[idx]])
  # }
  # 
  # results$df_joined[[16]]
  
  results <-  results %>% rowwise() %>%  
    mutate(
      model = name_split[1], 
      method = name_split[method_index],
      n_examples = str_match(method, "\\d+")[[1]],
      out_of_company = if_else(str_detect(method, "rag"), str_detect(basename(file), "out_of_sample") == TRUE, NA),
      method_family = str_replace(str_replace(method, '\\d+', 'n'), '_out_of_sample', ''),
      loop = as.numeric((basename(file) %>% str_match("loop_(.)(_queued)?\\.json"))[2]),
      predictions = list(try(fromJSON(df_joined)) %>% as_tibble()),
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
    method = str_replace(method, '_out_of_sample', ''),
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
    method = str_replace(method, '_out_of_sample', ''),
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
    model = str_replace(model, "_vllm", ""),
    method = str_replace(method, '_out_of_sample', '')
  ) %>% mutate(
    n_examples = as.numeric(n_examples),
    n_examples = if_else(method_family == "zero_shot", 0, n_examples),
    n_examples = if_else(method_family == "static_example", 1, n_examples)
  )

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

#### new input formats ####

##### pymupdf markdown #####

json_files_table_extraction_llm <- list.files(
  "../benchmark_results/table_extraction/llm/final/real_tables_more_examples_pymupdf_markdown/",
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
  # if (str_detect(name_split[1], "gpt-oss")) next
  method_index = which(str_starts((basename(file) %>% str_split("__"))[[1]], "loop"))-1
  # print(name_split)
  
  results <-  json_data$results %>% as_tibble()
  
  if (nrow(results) == 0 | 'none_type_error' %in% colnames(json_data$results)) {
    error_list <-  c(error_list, file)
    next
  }
  
  # for (idx in 1:nrow(results)) {
  #   print(idx)
  #   # try()
  #   fromJSON(results$df_joined[[idx]])
  # }
  # 
  # results$df_joined[[16]]
  
  results <-  results %>% rowwise() %>%  
    mutate(
      extractor = "pymupdf",
      input_format = "markdown",
      model = name_split[1], 
      method = name_split[method_index],
      n_examples = str_match(method, "\\d+")[[1]],
      out_of_company = if_else(str_detect(method, "rag"), str_detect(basename(file), "out_of_sample") == TRUE, NA),
      method_family = str_replace(str_replace(method, '\\d+', 'n'), '_out_of_sample', ''),
      loop = as.numeric((basename(file) %>% str_match("loop_(.)(_queued)?\\.json"))[2]),
      predictions = list(try(fromJSON(df_joined)) %>% as_tibble()),
      request_tokens = list(json_data$request_tokens),
      runtime = json_data$runtime
    ) %>% select(-df_joined)
  
  # results$predictions <- predictions
  meta_list_llm[[length(meta_list_llm) + 1]] <- results
}

df_pymupdf_md <- bind_rows(meta_list_llm) %>% select(!starts_with("changed_values")) %>% 
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
    method = str_replace(method, '_out_of_sample', ''),
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

##### pymupdf text #####

json_files_table_extraction_llm <- list.files(
  "../benchmark_results/table_extraction/llm/final/real_tables_more_examples_pymupdf/",
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
  # if (str_detect(name_split[1], "gpt-oss")) next
  method_index = which(str_starts((basename(file) %>% str_split("__"))[[1]], "loop"))-1
  # print(name_split)
  
  results <-  json_data$results %>% as_tibble()
  
  if (nrow(results) == 0) {
    error_list <-  c(error_list, file)
    next
  }
  
  # for (idx in 1:nrow(results)) {
  #   print(idx)
  #   # try()
  #   fromJSON(results$df_joined[[idx]])
  # }
  # 
  # results$df_joined[[16]]
  
  results <-  results %>% rowwise() %>%  
    mutate(
      extractor = "pymupdf",
      input_format = "text",
      model = name_split[1], 
      method = name_split[method_index],
      n_examples = str_match(method, "\\d+")[[1]],
      out_of_company = if_else(str_detect(method, "rag"), str_detect(basename(file), "out_of_sample") == TRUE, NA),
      method_family = str_replace(str_replace(method, '\\d+', 'n'), '_out_of_sample', ''),
      loop = as.numeric((basename(file) %>% str_match("loop_(.)(_queued)?\\.json"))[2]),
      predictions = list(try(fromJSON(df_joined)) %>% as_tibble()),
      request_tokens = list(json_data$request_tokens),
      runtime = json_data$runtime
    ) %>% select(-df_joined)
  
  # results$predictions <- predictions
  meta_list_llm[[length(meta_list_llm) + 1]] <- results
}

df_pymupdf_txt <- bind_rows(meta_list_llm) %>% select(!starts_with("changed_values")) %>% 
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
    method = str_replace(method, '_out_of_sample', ''),
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

##### pdfium text #####

json_files_table_extraction_llm <- list.files(
  "../benchmark_results/table_extraction/llm/final/real_tables_more_examples/",
  pattern = "\\.json$",
  full.names = TRUE
) %>%
  .[!grepl("_test_", .)] %>% 
  .[grepl("235B", .)] %>% 
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
  # if (str_detect(name_split[1], "gpt-oss")) next
  method_index = which(str_starts((basename(file) %>% str_split("__"))[[1]], "loop"))-1
  # print(name_split)
  
  results <-  json_data$results %>% as_tibble()
  
  if (nrow(results) == 0) {
    error_list <-  c(error_list, file)
    next
  }
  
  # for (idx in 1:nrow(results)) {
  #   print(idx)
  #   # try()
  #   fromJSON(results$df_joined[[idx]])
  # }
  # 
  # results$df_joined[[16]]
  
  results <-  results %>% rowwise() %>%  
    mutate(
      extractor = "pdfium",
      input_format = "text",
      model = name_split[1], 
      method = name_split[method_index],
      n_examples = str_match(method, "\\d+")[[1]],
      out_of_company = if_else(str_detect(method, "rag"), str_detect(basename(file), "out_of_sample") == TRUE, NA),
      method_family = str_replace(str_replace(method, '\\d+', 'n'), '_out_of_sample', ''),
      loop = as.numeric((basename(file) %>% str_match("loop_(.)(_queued)?\\.json"))[2]),
      predictions = list(try(fromJSON(df_joined)) %>% as_tibble()),
      request_tokens = list(json_data$request_tokens),
      runtime = json_data$runtime
    ) %>% select(-df_joined)
  
  # results$predictions <- predictions
  meta_list_llm[[length(meta_list_llm) + 1]] <- results
}

df_pdfium_txt <- bind_rows(meta_list_llm) %>% select(!starts_with("changed_values")) %>% 
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
    method = str_replace(method, '_out_of_sample', ''),
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

##### docling markdown #####


json_files_table_extraction_llm <- list.files(
  "../benchmark_results/table_extraction/llm/final/real_tables_more_examples_docling_markdown/",
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
  # if (str_detect(name_split[1], "gpt-oss")) next
  method_index = which(str_starts((basename(file) %>% str_split("__"))[[1]], "loop"))-1
  # print(name_split)
  
  results <-  json_data$results %>% as_tibble()
  
  if (nrow(results) == 0) {
    error_list <-  c(error_list, file)
    next
  }
  
  # for (idx in 1:nrow(results)) {
  #   print(idx)
  #   # try()
  #   fromJSON(results$df_joined[[idx]])
  # }
  # 
  # results$df_joined[[16]]
  
  results <-  results %>% rowwise() %>%  
    mutate(
      extractor = "docling",
      input_format = "markdown",
      model = name_split[1], 
      method = name_split[method_index],
      n_examples = str_match(method, "\\d+")[[1]],
      out_of_company = if_else(str_detect(method, "rag"), str_detect(basename(file), "out_of_sample") == TRUE, NA),
      method_family = str_replace(str_replace(method, '\\d+', 'n'), '_out_of_sample', ''),
      loop = as.numeric((basename(file) %>% str_match("loop_(.)(_queued)?\\.json"))[2]),
      predictions = list(try(fromJSON(df_joined)) %>% as_tibble()),
      request_tokens = list(json_data$request_tokens),
      runtime = json_data$runtime
    ) %>% select(-df_joined)
  
  # results$predictions <- predictions
  meta_list_llm[[length(meta_list_llm) + 1]] <- results
}

df_docling_md <- bind_rows(meta_list_llm) %>% select(!starts_with("changed_values")) %>% 
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
    method = str_replace(method, '_out_of_sample', ''),
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

##### docling text #####

json_files_table_extraction_llm <- list.files(
  "../benchmark_results/table_extraction/llm/final/real_tables_more_examples_docling_parse/",
  pattern = "\\.json$",
  full.names = TRUE
) %>%
  .[!grepl("_test_", .)] %>% 
  .[grepl("235B", .)] %>% 
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
  # if (str_detect(name_split[1], "gpt-oss")) next
  method_index = which(str_starts((basename(file) %>% str_split("__"))[[1]], "loop"))-1
  # print(name_split)
  
  results <-  json_data$results %>% as_tibble()
  
  if (nrow(results) == 0) {
    error_list <-  c(error_list, file)
    next
  }
  
  # for (idx in 1:nrow(results)) {
  #   print(idx)
  #   # try()
  #   fromJSON(results$df_joined[[idx]])
  # }
  # 
  # results$df_joined[[16]]
  
  results <-  results %>% rowwise() %>%  
    mutate(
      extractor = "docling",
      input_format = "text",
      model = name_split[1], 
      method = name_split[method_index],
      n_examples = str_match(method, "\\d+")[[1]],
      out_of_company = if_else(str_detect(method, "rag"), str_detect(basename(file), "out_of_sample") == TRUE, NA),
      method_family = str_replace(str_replace(method, '\\d+', 'n'), '_out_of_sample', ''),
      loop = as.numeric((basename(file) %>% str_match("loop_(.)(_queued)?\\.json"))[2]),
      predictions = list(try(fromJSON(df_joined)) %>% as_tibble()),
      request_tokens = list(json_data$request_tokens),
      runtime = json_data$runtime
    ) %>% select(-df_joined)
  
  # results$predictions <- predictions
  meta_list_llm[[length(meta_list_llm) + 1]] <- results
}

df_docling_txt <- bind_rows(meta_list_llm) %>% select(!starts_with("changed_values")) %>% 
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
    method = str_replace(method, '_out_of_sample', ''),
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

##### tesseract text #####

json_files_table_extraction_llm <- list.files(
  "../benchmark_results/table_extraction/llm/final/real_tables_more_examples_tesseract/",
  pattern = "\\.json$",
  full.names = TRUE
) %>%
  .[!grepl("_test_", .)] %>% 
  .[grepl("235B", .)] %>% 
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
  # if (str_detect(name_split[1], "gpt-oss")) next
  method_index = which(str_starts((basename(file) %>% str_split("__"))[[1]], "loop"))-1
  # print(name_split)
  
  results <-  json_data$results %>% as_tibble()
  
  if (nrow(results) == 0) {
    error_list <-  c(error_list, file)
    next
  }
  
  # for (idx in 1:nrow(results)) {
  #   print(idx)
  #   # try()
  #   fromJSON(results$df_joined[[idx]])
  # }
  # 
  # results$df_joined[[16]]
  
  results <-  results %>% rowwise() %>%  
    mutate(
      extractor = "tesseract",
      input_format = "text",
      model = name_split[1], 
      method = name_split[method_index],
      n_examples = str_match(method, "\\d+")[[1]],
      out_of_company = if_else(str_detect(method, "rag"), str_detect(basename(file), "out_of_sample") == TRUE, NA),
      method_family = str_replace(str_replace(method, '\\d+', 'n'), '_out_of_sample', ''),
      loop = as.numeric((basename(file) %>% str_match("loop_(.)(_queued)?\\.json"))[2]),
      predictions = list(try(fromJSON(df_joined)) %>% as_tibble()),
      request_tokens = list(json_data$request_tokens),
      runtime = json_data$runtime
    ) %>% select(-df_joined)
  
  # results$predictions <- predictions
  meta_list_llm[[length(meta_list_llm) + 1]] <- results
}

df_tesseract_txt <- bind_rows(meta_list_llm) %>% select(!starts_with("changed_values")) %>% 
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
    method = str_replace(method, '_out_of_sample', ''),
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

##### azure document intelligence text #####

json_files_table_extraction_llm <- list.files(
  "../benchmark_results/table_extraction/llm/final/real_tables_more_examples_azure_doc_int/",
  pattern = "\\.json$",
  full.names = TRUE
) %>%
  .[!grepl("_test_", .)] %>% 
  .[grepl("235B", .)] %>% 
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
  # if (str_detect(name_split[1], "gpt-oss")) next
  method_index = which(str_starts((basename(file) %>% str_split("__"))[[1]], "loop"))-1
  # print(name_split)
  
  results <-  json_data$results %>% as_tibble()
  
  if (nrow(results) == 0) {
    error_list <-  c(error_list, file)
    next
  }
  
  # for (idx in 1:nrow(results)) {
  #   print(idx)
  #   # try()
  #   fromJSON(results$df_joined[[idx]])
  # }
  # 
  # results$df_joined[[16]]
  
  results <-  results %>% rowwise() %>%  
    mutate(
      extractor = "azure",
      input_format = "text",
      model = name_split[1], 
      method = name_split[method_index],
      n_examples = str_match(method, "\\d+")[[1]],
      out_of_company = if_else(str_detect(method, "rag"), str_detect(basename(file), "out_of_sample") == TRUE, NA),
      method_family = str_replace(str_replace(method, '\\d+', 'n'), '_out_of_sample', ''),
      loop = as.numeric((basename(file) %>% str_match("loop_(.)(_queued)?\\.json"))[2]),
      predictions = list(try(fromJSON(df_joined)) %>% as_tibble()),
      request_tokens = list(json_data$request_tokens),
      runtime = json_data$runtime
    ) %>% select(-df_joined)
  
  # results$predictions <- predictions
  meta_list_llm[[length(meta_list_llm) + 1]] <- results
}

df_azure_txt <- bind_rows(meta_list_llm) %>% select(!starts_with("changed_values")) %>% 
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
    method = str_replace(method, '_out_of_sample', ''),
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

##### combine #####

library(ggh4x)

df_qwen235 <- bind_rows(
  df_docling_md,
  df_docling_txt,
  df_pdfium_txt,
  df_pymupdf_md,
  df_pymupdf_txt,
  df_tesseract_txt,
  df_azure_txt
) %>% mutate(
  model = gsub("^[^_]+_", "", model),
  company = map_chr(filepath, ~str_split(str_split(., "/")[[1]][5], "__")[[1]][1])
) %>% filter(company != "MEAB GmbH")

df_qwen235 %>% saveRDS("data_storage/table_extraction_qwen3_235B_multiple_input_formats")

table_characteristics <- read.csv("../benchmark_truth/real_tables_extended/table_characteristics_more_examples.csv") %>% 
  mutate(
    filepath = paste0("/pvc/benchmark_truth/real_tables_extended/", company, "__", filename)
  ) %>% as_tibble()

df_qwen235 <- df_qwen235 %>% left_join(table_characteristics)

df_qwen235 %>% group_by(model, method, extractor, input_format) %>% 
  mutate(mean_total = mean(percentage_correct_total)) %>% 
  group_by(model, extractor, input_format, filepath) %>% 
  slice_max(n = 1, mean_total, with_ties = FALSE) %>% 
  # select(model, method, extractor, input_format, mean_total, filepath) %>% 
  ggplot() +
  geom_boxplot(aes(x = company, y = percentage_correct_total)) +
  facet_nested(extractor+input_format~.) +
  scale_x_discrete(guide = guide_axis(angle = 30))

df_qwen235 %>% group_by(model, method, extractor, input_format) %>% 
  mutate(mean_total = mean(percentage_correct_total)) %>% 
  group_by(model, extractor, input_format, filepath) %>% 
  slice_max(n = 1, mean_total, with_ties = FALSE) %>% 
  # select(model, method, extractor, input_format, mean_total, filepath) %>% 
  ggplot() +
  geom_boxplot(aes(x = company, y = percentage_correct_numeric)) +
  facet_nested(extractor+input_format~.) +
  scale_x_discrete(guide = guide_axis(angle = 30))
  
df_qwen235 %>% group_by(model, method, extractor, input_format) %>% 
  summarize(mean_total = mean(percentage_correct_total)) %>% 
  group_by(model, extractor, input_format) %>% 
  slice_max(n = 1, mean_total, with_ties = FALSE)

df_best <- df_qwen235 %>% filter(input_format == "text", extractor == "pdfium") %>% 
  group_by(method) %>% 
  mutate(mean_total = mean(percentage_correct_total), .before = 1) %>% 
  group_by(filepath) %>% 
  slice_max(n = 1, mean_total, with_ties = FALSE) %>% 
  ungroup()

df_best %>% mutate(across(T_in_year:multiple_this_years, ~as.character(.))) %>% 
  pivot_longer(T_in_year:multiple_this_years) %>% 
  group_by(name, value) %>% 
  mutate(mean_total = mean(percentage_correct_total)) %>% 
  ggplot() +
  geom_point(aes(x = name, y = mean_total, color = value)) +
  scale_x_discrete(guide = guide_axis(angle = 30))

df_temp <- df_best %>% 
  pivot_longer(NA_true_positive:NA_true_negative) %>% 
  mutate(
    predicted = !str_detect(name, "negative"),
    truth = !(name %in% c("NA_true_negative", "NA_false_positive"))
    ) %>% 
  filter(str_detect(name, "false"))
  
df_temp %>% 
  group_by(company) %>% 
  mutate(value = sum(value)/n()) %>% 
  ggplot() +
  geom_tile(aes(y = truth, x = predicted, fill = value)) +
  geom_text(
    data = . %>% select(name, truth, predicted) %>% unique(), 
    aes(label = name, y = truth, x = predicted), color = "white"
    ) +
  facet_wrap(~company)

df_temp %>% 
  ggplot() +
  geom_tile(aes(y = truth, x = predicted, fill = ordered(value))) +
  geom_text(
    data = . %>% select(name, truth, predicted) %>% unique(), 
    aes(label = name, y = truth, x = predicted), color = "white"
  ) +
  facet_wrap(~filepath)

df_best %>% group_by(company) %>% 
  reframe(
    mean_numeric = mean(percentage_correct_numeric),
    mean_F1 = mean(NA_F1)
    ) %>% 
  arrange(mean_numeric)

df_best %>% group_by(filepath) %>% 
  reframe(
    mean_numeric = mean(percentage_correct_numeric),
    mean_F1 = mean(NA_F1)
  ) %>% 
  arrange(mean_numeric)
