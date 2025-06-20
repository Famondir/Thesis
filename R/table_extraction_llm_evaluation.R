library(jsonlite)
library(tidyverse)

#### Test ####

json_files_table_extraction_llm <- list.files(
  "../benchmark_results/table_extraction/llm/",
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
  json_data <- fromJSON(paste(file_content, collapse = "\n"))
  
  results <-  json_data %>% as_tibble() %>% rowwise() %>%  
    mutate(model = (basename(file) %>% str_split("__"))[[1]][1], .before = 1)
  meta_list_llm[[length(meta_list_llm) + 1]] <- results
}

results_long <- bind_rows(meta_list_llm) %>% select(!starts_with("changed_values")) %>% 
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

results_long %>% select(c(model, percentage_correct_numeric, percentage_correct_total)) %>% 
  pivot_longer(cols = -model) %>% 
  ggplot() +
  geom_boxplot(aes(x = model, y = value)) +
  facet_wrap(~name, ncol = 1) +
  scale_x_discrete(guide = guide_axis(angle = 30))

results_long %>% select(c(model, NA_precision, NA_recall, NA_F1)) %>% 
  pivot_longer(cols = -model) %>% 
  ggplot() +
  geom_boxplot(aes(x = model, y = value)) +
  facet_wrap(~name, ncol = 1) +
  scale_x_discrete(guide = guide_axis(angle = 30))

results_long %>% ggplot() +
  geom_boxplot(aes(x = model, y = deep_distance)) +
  scale_x_discrete(guide = guide_axis(angle = 30))

results_long %>% ggplot() +
  geom_boxplot(aes(x = model, y = relative_numeric_difference_mean)) +
  scale_x_discrete(guide = guide_axis(angle = 30)) +
  coord_cartesian(ylim = c(0, 1500))

results_long %>% ggplot() +
  geom_boxplot(aes(x = model, y = relative_numeric_difference_mean)) +
  scale_x_discrete(guide = guide_axis(angle = 30)) +
  coord_cartesian(ylim = c(0, 1))

results_long %>% ggplot() +
  geom_boxplot(aes(x = model, y = levenstein_distance_mean)) +
  scale_x_discrete(guide = guide_axis(angle = 30)) # also between number and null?

#### Real ####

json_files_table_extraction_llm <- list.files(
  "../benchmark_results/table_extraction/llm/",
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
  json_data <- fromJSON(paste(file_content, collapse = "\n"))
  
  results <-  json_data %>% as_tibble() %>% rowwise() %>%  
    mutate(
      model = (basename(file) %>% str_split("__"))[[1]][1], 
      loop = as.numeric((basename(file) %>% str_match("loop_(.)\\.json"))[2]),
      .before = 1
      )
  meta_list_llm[[length(meta_list_llm) + 1]] <- results
}

results_long <- bind_rows(meta_list_llm) %>% select(!starts_with("changed_values")) %>% 
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

results_long %>% select(c(model, loop, percentage_correct_numeric, percentage_correct_total)) %>% 
  pivot_longer(cols = -c(model, loop)) %>% 
  ggplot() +
  geom_boxplot(aes(x = str_c(model, loop), y = value, fill = factor(loop))) +
  labs(fill = "loop") +
  facet_wrap(~name, ncol = 1) +
  scale_x_discrete(guide = guide_axis(angle = 30))

results_long %>% select(c(model, loop, NA_precision, NA_recall, NA_F1)) %>% 
  pivot_longer(cols = -c(model, loop)) %>% 
  ggplot() +
  geom_boxplot(aes(x = str_c(model, loop), y = value, fill = factor(loop))) +
  labs(fill = "loop") +
  facet_wrap(~name, ncol = 1) +
  scale_x_discrete(guide = guide_axis(angle = 30))

results_long %>% ggplot() +
  geom_boxplot(aes(x = str_c(model, loop), y = deep_distance, fill = factor(loop))) +
  labs(fill = "loop") +
  scale_x_discrete(guide = guide_axis(angle = 30))

results_long %>% ggplot() +
  geom_boxplot(aes(x = str_c(model, loop), y = relative_numeric_difference_mean, fill = factor(loop))) +
  labs(fill = "loop") +
  scale_x_discrete(guide = guide_axis(angle = 30)) +
  coord_cartesian(ylim = c(0, 1500))

results_long %>% ggplot() +
  geom_boxplot(aes(x = str_c(model, loop), y = relative_numeric_difference_mean, fill = factor(loop))) +
  labs(fill = "loop") +
  scale_x_discrete(guide = guide_axis(angle = 30)) +
  coord_cartesian(ylim = c(0, 1))

results_long %>% ggplot() +
  geom_boxplot(aes(x = str_c(model, loop), y = levenstein_distance_mean, fill = factor(loop))) +
  labs(fill = "loop") +
  scale_x_discrete(guide = guide_axis(angle = 30)) # also between number and null?
