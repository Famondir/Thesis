library(jsonlite)
library(tidyverse)

json_files_table_detection_llm <- list.files(
  "../benchmark_results/table_detection/llm/",
  pattern = "\\.json$",
  full.names = TRUE
) %>%
  # .[!grepl("_test_", .)] %>% 
  .[grepl("_binary_", .)]

meta_list_llm <- list()

# Loop through each .json file
for (file in json_files_table_detection_llm) {
  # Read the JSON file
  json_data <- fromJSON(file)
  
  # Extract the threshold and metrics from the "metrics" key
  metrics <- as.data.frame(json_data$metrics)
  
  lst <- list(
    metrics = metrics,
    model = basename(file),
    runtime = json_data$runtime
  )
  meta_list_llm[[length(meta_list_llm) + 1]] <- lst
}

results_df_llm <- data.frame(
  llm = character(),
  parameters = character(),
  method = character(),
  loop = numeric(),
  setNames(
    rep(list(numeric()), length(unique(unlist(lapply(meta_list_llm, function(x) names(x$metrics)))))),
    unique(unlist(lapply(meta_list_llm, function(x) names(x$metrics))))
  ),
  runtime_in_s = numeric(),
  stringsAsFactors = FALSE
)

for (result in meta_list_llm) {
  
  name_split = result$model %>% str_split("__")
  name_split = name_split[[1]]
  
  llm = name_split[1]
  parameters = str_extract(llm, "\\d*\\.?\\d+B")
  method = name_split[length(name_split)-1]
  loop = name_split[length(name_split)] %>% str_remove(".json") %>% str_remove("loop_") %>% as.integer()
  F1_Aktiva = result$metrics$Aktiva.f1_score
  F1_Passiva = result$metrics$Passiva.f1_score
  runtime = result$runtime
  
  results_df_llm <- results_df_llm %>%
    add_row(
      llm = llm,
      parameters = parameters,
      method = method,
      loop = loop,
      !!!setNames(
        lapply(result$metrics, function(x) round(as.numeric(x), 2)),
        names(result$metrics)
      ),
      runtime_in_s = round(runtime, 2)
    )
}

results_df_llm %>%
  group_by(llm, parameters, method) %>% 
  summarise(across(Aktiva.true_positive:runtime_in_s, list(median = ~median(.x, na.rm = TRUE), MAD = ~mad(.x, na.rm = TRUE))))

results_df_llm %>% 
  pivot_longer(cols = contains("precision"), values_to = "value", names_to = "metric") %>% 
  ggplot() +
  geom_boxplot(aes(x=llm, y=value)) +
  facet_grid(method~metric)

results_df_llm %>% 
  pivot_longer(cols = contains("F1"), values_to = "value", names_to = "metric") %>% 
  ggplot() +
  geom_boxplot(aes(x=llm, y=value)) +
  facet_grid(method~metric)
