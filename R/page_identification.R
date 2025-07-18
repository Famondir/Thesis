library(jsonlite)
library(tidyverse)

df_labels <- read.csv("/home/simon/Documents/data_science/Thesis/benchmark_truth/aktiva_passiva_guv_table_pages_no_ocr.csv") %>% 
  as_tibble() %>% 
  mutate(
    filepath = str_replace(filepath, "..", "/pvc")
  )

recalc_mectrics <- function(df, classification_type) {
  df_reeval <- df %>%
    select(-type, -match) %>%
    group_by(across(-confidence_score)) %>%
    summarise(confidence_score = mean(confidence_score, na.rm = TRUE), .groups = "drop") %>% 
    left_join(df_labels, relationship = "many-to-many", by = join_by(filepath, page)) %>%
    mutate(
      type = if_else(is.na(type), "other", type),
      match = if_else(predicted_type == classification_type, str_detect(type, predicted_type), !str_detect(type, classification_type))
    )
  
  tp <- df_reeval %>% filter(predicted_type != "no", match == TRUE) %>% nrow()
  fp <- df_reeval %>% filter(predicted_type != "no", match == FALSE) %>% nrow()
  fn <- df_reeval %>% filter(predicted_type == "no", match == FALSE) %>% nrow()
  tn <- df_reeval %>% filter(predicted_type == "no", match == TRUE) %>% nrow()
  n <- df_reeval %>% nrow()
  accuracy <- (tp + tn)/(n)
  precision <- tp/(tp+fp)
  recall <- tp/(tp+fn)
  f1_score <- ifelse(precision+recall != 0, 2*precision*recall/(precision+recall), 0)
  
  metrics <- list()
  metrics$true_positive <- tp
  metrics$false_positive <- fp
  metrics$false_negative <- fn
  metrics$true_negative <- tn
  metrics$n_pages <- n
  metrics$accuracy <- accuracy
  metrics$precision <- precision
  metrics$recall <- recall
  metrics$f1_score <- f1_score
  metrics$predictions <- list(df_reeval)
  
  return(metrics)
}

#### Real ####
{
json_files_page_identification_llm <- list.files(
  "../benchmark_results/page_identification/final/llm/",
  pattern = "\\.json$",
  full.names = TRUE
) %>%
  .[!grepl("_test_", .)]

meta_list_llm <- list()

# Loop through each .json file
for (file in json_files_page_identification_llm) {
  # print(file)

  file_content <- readLines(file, warn = FALSE)
  json_data <- fromJSON(paste(file_content, collapse = "\n"))
  
  name_split = (basename(file) %>% str_replace('__no_think', '') %>% str_split("__"))[[1]]
  method_index = which(str_starts(name_split, "loop"))-1
  
  # print(name_split)
  
  predictions <- fromJSON(json_data$results)
  classification_type <- str_split(name_split[2], '_')[[1]][3]
  
  results <- recalc_mectrics(predictions, classification_type) %>% 
    as_tibble() %>% rowwise() %>%
    mutate(
      model = str_replace(name_split[1], "_vllm", ""),
      method = name_split[method_index],
      n_examples = str_match(method, "\\d+")[[1]],
      out_of_company = if_else(str_detect(method, "rag"), str_detect(method, "out_of_company"), NA),
      method_family = str_replace(str_replace(method, '\\d+', 'n'), '_out_of_company', ''),
      loop = as.numeric((basename(file) %>% str_match("loop_(.)(_queued)?\\.json"))[2]),
      classifier_type = str_split(name_split[2], '_')[[1]][2],
      classification_type = classification_type,
      runtime = json_data$runtime,
      # predictions = list(predictions),
      .before = 1
    )
  meta_list_llm[[length(meta_list_llm) + 1]] <- results
}

df <- meta_list_llm %>% bind_rows()
}

df %>% filter(model == "mistralai_Ministral-8B-Instruct-2410") %>% 
  ggplot(aes(x = runtime, y = f1_score)) +
  geom_point(aes(color = method_family, shape = out_of_company), size = 7, alpha = .6) +
  scale_shape(na.value = 15, guide = "legend") +
  geom_text(aes(label = n_examples)) +
  facet_grid(model~classification_type) +
  theme(legend.position = "bottom") +
  guides(
    color = guide_legend(ncol = 1, title.position = "top"),
    shape = guide_legend(ncol = 1, title.position = "top")
  )

df %>% filter(classification_type == "Aktiva") %>% 
  ggplot(aes(x = runtime, y = f1_score)) +
  geom_point(aes(color = method_family, shape = out_of_company), size = 7, alpha = .6) +
  scale_shape(na.value = 15, guide = "legend") +
  geom_text(aes(label = n_examples)) +
  facet_grid(classification_type~model) +
  theme(legend.position = "bottom") +
  guides(
    color = guide_legend(ncol = 1, title.position = "top"),
    shape = guide_legend(ncol = 1, title.position = "top")
  )

df_temp <- (df %>% arrange(desc(f1_score)))[1,"predictions"][[1]][[1]] %>% as_tibble()
df_flipped_score <- df_temp %>% 
  mutate(
    confidence_score = if_else(predicted_type == "no", 1-confidence_score, confidence_score),
    is_aktiva = str_detect(type, "Aktiva")
  )

df_flipped_score %>% 
  ggplot() +
  geom_boxplot(aes(x = predicted_type, y = confidence_score)) +
  geom_jitter(aes(x = predicted_type, y = confidence_score, color = match), alpha = .2) +
  facet_wrap(~type)

library(pROC)

# ROC curve
roc_obj <- roc(df_flipped_score$is_aktiva, df_flipped_score$confidence_score)

# Plot ROC curve
plot(roc_obj, main = "ROC Curve for Aktiva Classification")
auc_val <- auc(roc_obj)
legend("bottomright", legend = paste("AUC =", round(auc_val, 3)))
