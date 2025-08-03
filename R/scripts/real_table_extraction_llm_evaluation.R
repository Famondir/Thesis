library(jsonlite)
library(tidyverse)

#### Final ####

json_files_table_extraction_llm <- list.files(
  "../benchmark_results/table_extraction/llm/final/real_tables/",
  pattern = "\\.json$",
  full.names = TRUE
) %>%
  .[!grepl("_test_", .)] %>% 
  .[!grepl("synth", .)]

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
  if (!grepl("\\]$", file_content[length(file_content)])) {
    # Find the last complete JSON object (ends with "},")
    last_complete <- max(grep('\\.pdf', file_content))
    file_content <- c(file_content[1:last_complete], "}]")
  }
  json_data <- fromJSON(paste(file_content, collapse = "\n"))
  
  name_split = (basename(file) %>% str_split("__"))[[1]]
  method_index = which(str_starts((basename(file) %>% str_split("__"))[[1]], "loop"))-1
  # print(name_split)
  
  results <-  json_data %>% as_tibble() %>% rowwise() %>%  
    mutate(
      model = name_split[1], 
      method = name_split[method_index],
      n_examples = str_match(method, "\\d+")[[1]],
      out_of_company = if_else(str_detect(method, "rag"), str_detect(method, "out_of_company"), NA),
      method_family = str_replace(str_replace(method, '\\d+', 'n'), '_out_of_company', ''),
      loop = as.numeric((basename(file) %>% str_match("loop_(.)(_queued)?\\.json"))[2]),
      predictions = list(fromJSON(df_joined) %>% as_tibble())
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
  )

# with NAs
extract_wrong_values <- function(df) {
  df %>% mutate(
    mistake_year = (year_truth != year_result) | (is.na(year_truth) & !is.na(year_result)) | (is.na(year_result) & !is.na(year_truth)),
    mistake_year = if_else(is.na(mistake_year), FALSE, mistake_year),
    mistake_previous_year =(previous_year_truth != previous_year_result) | (is.na(previous_year_truth) & !is.na(previous_year_result)) | (is.na(previous_year_result) & !is.na(previous_year_truth)),
    mistake_previous_year = if_else(is.na(mistake_previous_year), FALSE, mistake_previous_year)
  ) %>% select(
    year_truth, year_result, 
    previous_year_truth, previous_year_result,
    mistake_year, mistake_previous_year
  ) %>% 
    filter(mistake_year | mistake_previous_year)  
}

# only floats
extract_wrong_floats <- function(df) {
  df %>% mutate(
    mistake_year = (year_truth != year_result),
    mistake_previous_year =(previous_year_truth != previous_year_result)
  ) %>% select(
    year_truth, year_result, 
    previous_year_truth, previous_year_result,
    mistake_year, mistake_previous_year
  ) %>% 
    filter(mistake_year | mistake_previous_year)
}

relative_float_diff <- df %>% 
  mutate(wrong_floats = map(predictions, extract_wrong_floats)) %>%
  select(filepath, wrong_floats, model, method) %>% 
  rowwise() %>% mutate(n_wrong_floats = nrow(wrong_floats)) %>% 
  filter(n_wrong_floats>0) %>% 
  unnest(wrong_floats) %>% 
  mutate(
    ratio_this_year = year_result/year_truth,
    ratio_previous_year = previous_year_result/previous_year_truth
  ) %>% pivot_longer(
    cols = c(ratio_this_year, ratio_previous_year),
    names_to = "year_type",
    values_to = "ratio",
    names_prefix = "ratio_"
  ) %>% unique()

# relative_float_diff %>% saveRDS("data_storage/relative_float_diff_with_mistakes.rds")

# checked (log 10 ratio and differing truth log 10)
integer_multiplier <- relative_float_diff %>% 
  filter(log(ratio, base = 10) == as.integer(log(ratio, base = 10)), ratio != 1, 
         as.integer(log(year_truth, base = 10)) != as.integer(log(previous_year_truth, base = 10))
         ) %>% unique()

# checked (log 10 ratio)
integer_multiplier <- relative_float_diff %>% 
  filter(log(ratio, base = 10) == as.integer(log(ratio, base = 10)), ratio != 1
  ) %>% unique()

# unchecked (random ratio)
integer_multiplier <- relative_float_diff %>% 
  filter(!(log(ratio, base = 10) == as.integer(log(ratio, base = 10)))
  ) %>% unique()
  

paths <- dir("../manual_download/", full.names=TRUE, recursive=TRUE)
n_mistakes_identified <- tibble(change_date = file.info(paths)$ctime) %>% 
  filter(change_date > as.POSIXct("2025-07-23")) %>% nrow()

table_characteristics <- read.csv("../benchmark_truth/real_tables/table_characteristics.csv") %>% 
  mutate(
    filepath = paste0("/pvc/benchmark_truth/real_tables/", company, "__", filename)
    ) %>% as_tibble()

df_characteristics <- df %>% 
  select(filepath, method, model, percentage_correct_total) %>% 
  left_join(table_characteristics, by = "filepath")

##### regression #####

lm1 <- lm(
  data = df_characteristics,
  formula = percentage_correct_total ~ 
    method +
    model +
    n_columns + 
    T_in_previous_year + 
    T_in_year + 
    sum_same_line + 
    passiva_same_page +
    spacer +
    vorjahr +
    header_span
)
summary(lm1)

df_characteristics %>% select(is.numeric) %>% colMeans(na.rm= TRUE)

##### plotting #####

df %>% select(c(model, method, percentage_correct_numeric, percentage_correct_total)) %>% 
  pivot_longer(cols = -c(model, method)) %>% 
  ggplot() +
  geom_boxplot(aes(x = model, y = value)) +
  # facet_wrap(~name, ncol = 1) +
  scale_x_discrete(guide = guide_axis(angle = 30)) +
  facet_grid(method~name)

df %>% select(c(model, method, NA_precision, NA_recall, NA_F1)) %>% 
  pivot_longer(cols = -c(model, method)) %>% 
  ggplot() +
  geom_boxplot(aes(x = model, y = value)) +
  # facet_wrap(~name, ncol = 1) +
  scale_x_discrete(guide = guide_axis(angle = 30)) +
  facet_grid(name~method)

df %>% ggplot() +
  geom_boxplot(aes(x = model, y = deep_distance)) +
  scale_x_discrete(guide = guide_axis(angle = 30)) +
  facet_grid(method~1)

df %>% ggplot() +
  geom_boxplot(aes(x = model, y = relative_numeric_difference_mean)) +
  scale_x_discrete(guide = guide_axis(angle = 30)) +
  coord_cartesian(ylim = c(0, 1500)) +
  facet_grid(method~1)

df %>% ggplot() +
  geom_boxplot(aes(x = model, y = relative_numeric_difference_mean)) +
  scale_x_discrete(guide = guide_axis(angle = 30)) +
  coord_cartesian(ylim = c(0, 1)) +
  facet_grid(method~1)

df %>% ggplot() +
  geom_boxplot(aes(x = model, y = levenstein_distance_mean)) +
  scale_x_discrete(guide = guide_axis(angle = 30)) + # also between number and null?
  facet_grid(method~1)

relative_float_diff %>%
  filter(ratio != 1) %>%
  mutate(
    log_ratio = log(ratio, base = 10),
    log_ratio_is_int = (log(ratio, base = 10) == as.integer(log(ratio, base = 10)))
  ) %>%
  ggplot() +
  geom_histogram(aes(x = log_ratio, fill = log_ratio_is_int), binwidth = 1) +
  facet_grid(paste0(year_type,"\n", model)~method)

#### Synth Context ####

json_files_table_extraction_llm <- list.files(
  "../benchmark_results/table_extraction/llm/final/real_tables/",
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
  )

# with NAs
extract_wrong_values <- function(df) {
  df %>% mutate(
    mistake_year = (year_truth != year_result) | (is.na(year_truth) & !is.na(year_result)) | (is.na(year_result) & !is.na(year_truth)),
    mistake_year = if_else(is.na(mistake_year), FALSE, mistake_year),
    mistake_previous_year =(previous_year_truth != previous_year_result) | (is.na(previous_year_truth) & !is.na(previous_year_result)) | (is.na(previous_year_result) & !is.na(previous_year_truth)),
    mistake_previous_year = if_else(is.na(mistake_previous_year), FALSE, mistake_previous_year)
  ) %>% select(
    year_truth, year_result, 
    previous_year_truth, previous_year_result,
    mistake_year, mistake_previous_year
  ) %>% 
    filter(mistake_year | mistake_previous_year)  
}

# only floats
extract_wrong_floats <- function(df) {
  df %>% mutate(
    mistake_year = (year_truth != year_result),
    mistake_previous_year =(previous_year_truth != previous_year_result)
  ) %>% select(
    year_truth, year_result, 
    previous_year_truth, previous_year_result,
    mistake_year, mistake_previous_year
  ) %>% 
    filter(mistake_year | mistake_previous_year)
}

relative_float_diff <- df %>% 
  mutate(wrong_floats = map(predictions, extract_wrong_floats)) %>%
  select(filepath, wrong_floats, model, method) %>% 
  rowwise() %>% mutate(n_wrong_floats = nrow(wrong_floats)) %>% 
  filter(n_wrong_floats>0) %>% 
  unnest(wrong_floats) %>% 
  mutate(
    ratio_this_year = year_result/year_truth,
    ratio_previous_year = previous_year_result/previous_year_truth
  ) %>% pivot_longer(
    cols = c(ratio_this_year, ratio_previous_year),
    names_to = "year_type",
    values_to = "ratio",
    names_prefix = "ratio_"
  ) %>% unique()

# relative_float_diff %>% saveRDS("data_storage/relative_float_diff_with_mistakes.rds")

# checked (log 10 ratio and differing truth log 10)
integer_multiplier <- relative_float_diff %>% 
  filter(log(ratio, base = 10) == as.integer(log(ratio, base = 10)), ratio != 1, 
         as.integer(log(year_truth, base = 10)) != as.integer(log(previous_year_truth, base = 10))
  ) %>% unique()

# checked (log 10 ratio)
integer_multiplier <- relative_float_diff %>% 
  filter(log(ratio, base = 10) == as.integer(log(ratio, base = 10)), ratio != 1
  ) %>% unique()

# unchecked (random ratio)
integer_multiplier <- relative_float_diff %>% 
  filter(!(log(ratio, base = 10) == as.integer(log(ratio, base = 10)))
  ) %>% unique()


paths <- dir("../manual_download/", full.names=TRUE, recursive=TRUE)
n_mistakes_identified <- tibble(change_date = file.info(paths)$ctime) %>% 
  filter(change_date > as.POSIXct("2025-07-23")) %>% nrow()

table_characteristics <- read.csv("../benchmark_truth/real_tables/table_characteristics.csv") %>% 
  mutate(
    filepath = paste0("/pvc/benchmark_truth/real_tables/", company, "__", filename)
  ) %>% as_tibble()

df_characteristics <- df %>% 
  select(filepath, method, model, percentage_correct_total) %>% 
  left_join(table_characteristics, by = "filepath")

##### plotting #####

df %>% select(c(model, method, percentage_correct_numeric, percentage_correct_total, ignore_units)) %>% 
  pivot_longer(cols = -c(model, method, ignore_units)) %>% 
  ggplot() +
  geom_boxplot(aes(x = model, fill=ignore_units, y = value)) +
  # facet_wrap(~name, ncol = 1) +
  scale_x_discrete(guide = guide_axis(angle = 30)) +
  facet_grid(method~name)

df %>% select(c(model, method, NA_precision, NA_recall, NA_F1, ignore_units)) %>% 
  pivot_longer(cols = -c(model, method, ignore_units)) %>% 
  ggplot() +
  geom_boxplot(aes(x = model, fill=ignore_units, y = value)) +
  # facet_wrap(~name, ncol = 1) +
  scale_x_discrete(guide = guide_axis(angle = 30)) +
  facet_grid(name~method)

df %>% ggplot() +
  geom_boxplot(aes(x = model, y = deep_distance)) +
  scale_x_discrete(guide = guide_axis(angle = 30)) +
  facet_grid(method~1)

df %>% ggplot() +
  geom_boxplot(aes(x = model, y = relative_numeric_difference_mean)) +
  scale_x_discrete(guide = guide_axis(angle = 30)) +
  coord_cartesian(ylim = c(0, 1500)) +
  facet_grid(method~1)

df %>% ggplot() +
  geom_boxplot(aes(x = model, y = relative_numeric_difference_mean)) +
  scale_x_discrete(guide = guide_axis(angle = 30)) +
  coord_cartesian(ylim = c(0, 1)) +
  facet_grid(method~1)

df %>% ggplot() +
  geom_boxplot(aes(x = model, y = levenstein_distance_mean)) +
  scale_x_discrete(guide = guide_axis(angle = 30)) + # also between number and null?
  facet_grid(method~1)

relative_float_diff %>%
  filter(ratio != 1) %>%
  mutate(
    log_ratio = log(ratio, base = 10),
    log_ratio_is_int = (log(ratio, base = 10) == as.integer(log(ratio, base = 10)))
  ) %>%
  ggplot() +
  geom_histogram(aes(x = log_ratio, fill = log_ratio_is_int), binwidth = 1) +
  facet_grid(paste0(year_type,"\n", model)~method)

##### regression #####

lm1 <- lm(
  data = df_characteristics,
  formula = percentage_correct_total ~ 
    method +
    model +
    n_columns + 
    T_in_previous_year + 
    T_in_year + 
    sum_same_line + 
    passiva_same_page +
    spacer +
    vorjahr +
    header_span
)
summary(lm1)

df_characteristics %>% select(is.numeric) %>% colMeans(na.rm= TRUE)

#### Azure ####

json_files_table_extraction_llm <- list.files(
  "../benchmark_results/table_extraction/llm/final/real_tables/openai/",
  pattern = "\\.json$",
  full.names = TRUE
) %>%
  .[!grepl("_test_", .)]

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
  if (!grepl("\\]$", file_content[length(file_content)])) {
    # Find the last complete JSON object (ends with "},")
    last_complete <- max(grep('\\.pdf', file_content))
    file_content <- c(file_content[1:last_complete], "}]")
  }
  json_data <- fromJSON(paste(file_content, collapse = "\n"))
  
  name_split = (basename(file) %>% str_split("__"))[[1]]
  method_index = which(str_starts((basename(file) %>% str_split("__"))[[1]], "loop"))-1
  # print(name_split)
  
  results <-  json_data %>% as_tibble() %>% rowwise() %>%  
    mutate(
      model = name_split[1], 
      method = name_split[method_index],
      n_examples = str_match(method, "\\d+")[[1]],
      out_of_company = if_else(str_detect(method, "rag"), str_detect(method, "out_of_company"), NA),
      method_family = str_replace(str_replace(method, '\\d+', 'n'), '_out_of_company', ''),
      loop = as.numeric((basename(file) %>% str_match("loop_(.)(_queued)?\\.json"))[2]),
      predictions = list(fromJSON(df_joined) %>% as_tibble())
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
  )

##### plotting #####

df %>% select(c(model, method, percentage_correct_numeric, percentage_correct_total)) %>% 
  pivot_longer(cols = -c(model, method)) %>% 
  ggplot() +
  geom_boxplot(aes(x = model, y = value)) +
  # facet_wrap(~name, ncol = 1) +
  scale_x_discrete(guide = guide_axis(angle = 30)) +
  facet_grid(method~name)

df %>% select(c(model, method, NA_precision, NA_recall, NA_F1)) %>% 
  pivot_longer(cols = -c(model, method)) %>% 
  ggplot() +
  geom_boxplot(aes(x = model, y = value)) +
  # facet_wrap(~name, ncol = 1) +
  scale_x_discrete(guide = guide_axis(angle = 30)) +
  facet_grid(name~method)

# df %>% ggplot() +
#   geom_boxplot(aes(x = model, y = deep_distance)) +
#   scale_x_discrete(guide = guide_axis(angle = 30)) +
#   facet_grid(method~1)

df %>% ggplot() +
  geom_boxplot(aes(x = model, y = relative_numeric_difference_mean)) +
  scale_x_discrete(guide = guide_axis(angle = 30)) +
  coord_cartesian(ylim = c(0, 1500)) +
  facet_grid(method~1)

df %>% ggplot() +
  geom_boxplot(aes(x = model, y = relative_numeric_difference_mean)) +
  scale_x_discrete(guide = guide_axis(angle = 30)) +
  coord_cartesian(ylim = c(0, 1)) +
  facet_grid(method~1)

df %>% ggplot() +
  geom_boxplot(aes(x = model, y = levenstein_distance_mean)) +
  scale_x_discrete(guide = guide_axis(angle = 30)) + # also between number and null?
  facet_grid(method~1)

#### Real ####

json_files_table_extraction_llm <- list.files(
  "../benchmark_results/table_extraction/llm/real_tables/",
  pattern = "\\.json$",
  full.names = TRUE
) %>%
  .[!grepl("_test_", .)]

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
  if (!grepl("\\]$", file_content[length(file_content)])) {
    # Find the last complete JSON object (ends with "},")
    last_complete <- max(grep('\\.pdf', file_content))
    file_content <- c(file_content[1:last_complete], "}]")
  }
  json_data <- fromJSON(paste(file_content, collapse = "\n"))
  
  name_split = (basename(file) %>% str_split("__"))[[1]]
  method_index = which(str_starts((basename(file) %>% str_split("__"))[[1]], "loop"))-1
  # print(name_split)
  
  results <-  json_data %>% as_tibble() %>% rowwise() %>%  
    mutate(
      model = name_split[1], 
      method = name_split[method_index],
      loop = as.numeric((basename(file) %>% str_match("loop_(.)(_queued)?\\.json"))[2]),
      .before = 1
    )
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
  )

df <- df %>% rowwise() %>% mutate(
  n_columns = str_match(filepath, "(.)_columns")[2],
  span = if_else("True" == str_match(filepath, "span_(False|True)")[2], TRUE, FALSE),
  thin = if_else("True" == str_match(filepath, "thin_(False|True)")[2], TRUE, FALSE),
  year_as = str_match(filepath, "year_as_(.*)_unit")[2],
  unit_in_first_cell = if_else("True" == str_match(filepath, "unit_in_first_cell_(False|True)")[2], TRUE, FALSE),
  unit_str = str_match(filepath, "unit_in_first_cell_(False|True)_(.*)_enumeration")[3],
  enumeration = if_else("True" == str_match(filepath, "enumeration_(False|True)")[2], TRUE, FALSE),
  number_of_table = str_match(filepath, "enumeration_(False|True)_(.*)(_queued)?\\.pdf")[3]
) %>% mutate(
  n_columns = ordered(n_columns, c("3", "4", "5"))
) # %>% filter(number_of_table %in% c("0", "1"))

##### plotting #####

df %>% select(c(model, method, percentage_correct_numeric, percentage_correct_total)) %>% 
  pivot_longer(cols = -c(model, method)) %>% 
  ggplot() +
  geom_boxplot(aes(x = model, y = value)) +
  # facet_wrap(~name, ncol = 1) +
  scale_x_discrete(guide = guide_axis(angle = 30)) +
  facet_grid(method~name)

df %>% select(c(model, method, NA_precision, NA_recall, NA_F1)) %>% 
  pivot_longer(cols = -c(model, method)) %>% 
  ggplot() +
  geom_boxplot(aes(x = model, y = value)) +
  # facet_wrap(~name, ncol = 1) +
  scale_x_discrete(guide = guide_axis(angle = 30)) +
  facet_grid(name~method)

df %>% ggplot() +
  geom_boxplot(aes(x = model, y = deep_distance)) +
  scale_x_discrete(guide = guide_axis(angle = 30)) +
  facet_grid(method~1)

df %>% ggplot() +
  geom_boxplot(aes(x = model, y = relative_numeric_difference_mean)) +
  scale_x_discrete(guide = guide_axis(angle = 30)) +
  coord_cartesian(ylim = c(0, 1500)) +
  facet_grid(method~1)

df %>% ggplot() +
  geom_boxplot(aes(x = model, y = relative_numeric_difference_mean)) +
  scale_x_discrete(guide = guide_axis(angle = 30)) +
  coord_cartesian(ylim = c(0, 1)) +
  facet_grid(method~1)

df %>% ggplot() +
  geom_boxplot(aes(x = model, y = levenstein_distance_mean)) +
  scale_x_discrete(guide = guide_axis(angle = 30)) + # also between number and null?
  facet_grid(method~1)

##### regression #####

# lm_1 <- lm(
#   data = df,
#   formula = percentage_correct_total ~ n_columns + span + thin + year_as + unit_str + unit_in_first_cell + enumeration + number_of_table + model
# )
# 
# summary(lm_1)

# df %>% filter(grammar_error == TRUE)
# df %>% group_by(filepath) %>% summarise(n = n()) %>% 

#### Test ####

json_files_table_extraction_llm <- list.files(
  "../benchmark_results/table_extraction/llm/real_tables/",
  pattern = "\\.json$",
  full.names = TRUE
) %>%
  .[grepl("_test_", .)]

meta_list_llm <- list()

# Loop through each .json file
for (file in json_files_table_extraction_llm) {
  # print(file)
  # Read the JSON file
  # Read the JSON file and replace NaN with NULL in the file content
  file_content <- readLines(file, warn = FALSE)
  file_content <- gsub("\\bNaN\\b", "null", file_content)
  file_content <- gsub("\\bInfinity\\b", "null", file_content)
  json_data <- fromJSON(paste(file_content, collapse = "\n"))
  
  model_name <- (basename(file) %>% str_split("__"))[[1]][1] %>% str_replace("_vllm", "")
  # if (grepl("_queued\\.json$", basename(file))) {
  #   model_name <- paste0(model_name, "_queued")
  # }
  results <-  json_data %>% as_tibble() %>% rowwise() %>%  
    mutate(model = model_name, .before = 1)
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
  )

df %>% select(c(model, percentage_correct_numeric, percentage_correct_total)) %>% 
  pivot_longer(cols = -model) %>% 
  ggplot() +
  geom_boxplot(aes(x = model, y = value)) +
  facet_wrap(~name, ncol = 1) +
  scale_x_discrete(guide = guide_axis(angle = 30))

df %>% select(c(model, NA_precision, NA_recall, NA_F1)) %>% 
  pivot_longer(cols = -model) %>% 
  ggplot() +
  geom_boxplot(aes(x = model, y = value)) +
  facet_wrap(~name, ncol = 1) +
  scale_x_discrete(guide = guide_axis(angle = 30))

df %>% ggplot() +
  geom_boxplot(aes(x = model, y = deep_distance)) +
  scale_x_discrete(guide = guide_axis(angle = 30))

df %>% ggplot() +
  geom_boxplot(aes(x = model, y = relative_numeric_difference_mean)) +
  scale_x_discrete(guide = guide_axis(angle = 30)) +
  coord_cartesian(ylim = c(0, 1500))

df %>% ggplot() +
  geom_boxplot(aes(x = model, y = relative_numeric_difference_mean)) +
  scale_x_discrete(guide = guide_axis(angle = 30)) +
  coord_cartesian(ylim = c(0, 1))

df %>% ggplot() +
  geom_boxplot(aes(x = model, y = levenstein_distance_mean)) +
  scale_x_discrete(guide = guide_axis(angle = 30)) # also between number and null?
