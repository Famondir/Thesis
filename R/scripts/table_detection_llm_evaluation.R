library(jsonlite)
library(tidyverse)

# Rename files ending with __no_think.json to -no-think in the model name and remove the suffix
files_to_rename <- list.files(
  "../benchmark_results/table_detection/llm/",
  pattern = "__no_think\\.json$",
  full.names = TRUE
)

for (old_path in files_to_rename) {
  # Extract filename
  old_name <- basename(old_path)
  # Replace "__no_think.json" with ".json" and insert "-no-think" after the model name
  new_name <- sub("([0-9]+B)__", "\\1-no-think__", sub("__no_think\\.json$", ".json", old_name))
  # print(new_name)
  new_path <- file.path(dirname(old_path), new_name)
  file.rename(old_path, new_path)
}

json_files_table_detection_llm <- list.files(
  "../benchmark_results/table_detection/llm/",
  pattern = "\\.json$",
  full.names = TRUE
) %>%
  .[!grepl("_test_", .)] %>% 
  # .[grepl("_binary_", .)] 
  .[grepl("_five_classes_", .)]

meta_list_llm <- list()

# Loop through each .json file
for (file in json_files_table_detection_llm) {
  # print(file)
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

results_df_llm$llm %>% unique()

results_df_llm <- results_df_llm %>% 
  # mutate(llm = factor(llm, levels = c(
  #   "Qwen_Qwen2.5-0.5B-Instruct",
  #   "Qwen_Qwen2.5-1.5B-Instruct",
  #   "Qwen_Qwen2.5-1.5B-Instruct_alt_prompts",
  #   "Qwen_Qwen2.5-3B-Instruct",
  #   "Qwen_Qwen2.5-7B-Instruct",
  #   "Qwen_Qwen2.5-7B-Instruct_alt_prompts",
  #   "Qwen_Qwen2.5-14B-Instruct",
  #   "Qwen_Qwen2.5-32B-Instruct",
  #   "Qwen_Qwen2.5-72B-Instruct",
  #   "Qwen_Qwen3-8B",
  #   "Qwen_Qwen3-8B-no-think",
  #   "Qwen_Qwen3-32B",
  #   "Qwen_Qwen3-32B-no-think"
  # ))) %>%
  mutate(llm = factor(llm, levels = c(
    "deepseek-ai_DeepSeek-R1-Distill-Qwen-32B",
    "google_gemma-3-4b-it",
    "google_gemma-3-27b-it",
    "microsoft_phi-4",
    "meta-llama_Llama-4-Scout-17B-16E",
    "meta-llama_Llama-3.3-70B-Instruct",
    "meta-llama_Llama-3.2-3B-Instruct",
    "meta-llama_Llama-3.1-8B-Instruct",
    "meta-llama_Llama-3.1-70B-Instruct",
    "mistralai_Mistral-7B-Instruct-v0.3",
    "tiiuae_Falcon3-10B-Instruct",
    "Qwen_Qwen2.5-7B-Instruct",
    "Qwen_Qwen2.5-72B-Instruct"
  ))) %>%
  filter(!str_detect(llm, "_alt_"))

selected_columns <- names(results_df_llm)[c(5:ncol(results_df_llm)-1)]

results_df_llm %>%
  group_by(llm, parameters, method) %>% 
  summarise(across(all_of(selected_columns), list(median = ~median(.x, na.rm = TRUE), MAD = ~mad(.x, na.rm = TRUE))))

results_df_llm %>% 
  pivot_longer(cols = contains("F1"), values_to = "value", names_to = "metric") %>% 
  ggplot() +
  geom_boxplot(aes(x=llm, y=value)) +
  facet_grid(metric~method) +
  ylim(c(0,1)) +
  scale_x_discrete(guide = guide_axis(angle = 30))

results_df_llm %>% 
  pivot_longer(cols = contains("recall"), values_to = "value", names_to = "metric") %>% 
  ggplot() +
  geom_boxplot(aes(x=llm, y=value)) +
  facet_grid(metric~method) +
  ylim(c(0,1)) +
  scale_x_discrete(guide = guide_axis(angle = 30))

results_df_llm %>% 
  pivot_longer(cols = contains("precision"), values_to = "value", names_to = "metric") %>% 
  ggplot() +
  geom_boxplot(aes(x=llm, y=value)) +
  facet_grid(metric~method) +
  ylim(c(0,1)) +
  scale_x_discrete(guide = guide_axis(angle = 30))
