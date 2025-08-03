#### preparations ####

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

calculate_micro_macro_metrics <- function(metrics, suffix = "") {
  # browser()
  # Calculate micro and macro metrics
  # Micro: sum over all classes
  tp_micro <- sum(sapply(metrics, function(x) x$true_positive))
  fp_micro <- sum(sapply(metrics, function(x) x$false_positive))
  fn_micro <- sum(sapply(metrics, function(x) x$false_negative))
  tn_micro <- sum(sapply(metrics, function(x) x$true_negative))
  n_micro <- sum(sapply(metrics, function(x) x$n_pages))
  
  micro_precision <- tp_micro / (tp_micro + fp_micro)
  micro_recall <- tp_micro / (tp_micro + fn_micro)
  micro_f1 <- ifelse(micro_precision + micro_recall != 0, 2 * micro_precision * micro_recall / (micro_precision + micro_recall), 0)
  micro_accuracy <- (tp_micro + tn_micro) / n_micro
  
  # Macro: mean over all classes
  macro_precision <- mean(sapply(metrics, function(x) x$precision), na.rm = TRUE)
  macro_recall <- mean(sapply(metrics, function(x) x$recall), na.rm = TRUE)
  macro_f1 <- mean(sapply(metrics, function(x) x$f1_score), na.rm = TRUE)
  macro_accuracy <- mean(sapply(metrics, function(x) x$accuracy), na.rm = TRUE)
  
  new_metrics <- list()
  
  micro_name <- str_c("micro", suffix)
  new_metrics[[micro_name]] <- list(
    metric_type = micro_name,
    true_positive = tp_micro,
    false_positive = fp_micro,
    false_negative = fn_micro,
    true_negative = tn_micro,
    n_pages = n_micro,
    precision = micro_precision,
    recall = micro_recall,
    f1_score = micro_f1,
    accuracy = micro_accuracy
  )
  macro_name <- str_c("macro", suffix)
  new_metrics[[macro_name]] <- list(
    metric_type = macro_name,
    true_positive = NA,
    false_positive = NA,
    false_negative = NA,
    true_negative = NA,
    n_pages = NA,
    precision = macro_precision,
    recall = macro_recall,
    f1_score = macro_f1,
    accuracy = macro_accuracy
  )
  
  return(new_metrics)
}

recalc_mectrics_multiclass <- function(df) {
  recalc_mectrics_singleclass <- function(df_reeval, classification_type) {
    tp <- df_reeval %>% filter(predicted_type == classification_type, match == TRUE) %>% nrow()
    fp <- df_reeval %>% filter(predicted_type == classification_type, match == FALSE) %>% nrow()
    fn <- df_reeval %>% filter(type == classification_type, match == FALSE) %>% nrow()
    tn <- df_reeval %>% filter(type != classification_type, match == TRUE) %>% nrow()
    n <- df_reeval %>% nrow()
    accuracy <- (tp + tn)/(n)
    precision <- tp/(tp+fp)
    recall <- tp/(tp+fn)
    f1_score <- ifelse(precision+recall != 0, 2*precision*recall/(precision+recall), 0)
    
    metrics <- list()
    metrics$metric_type <- classification_type
    metrics$true_positive <- tp
    metrics$false_positive <- fp
    metrics$false_negative <- fn
    metrics$true_negative <- tn
    metrics$n_pages <- n
    metrics$accuracy <- accuracy
    metrics$precision <- precision
    metrics$recall <- recall
    metrics$f1_score <- f1_score
    
    return(metrics %>% as_tibble())
  }
  
  df_reeval <- df %>%
    select(-type, -match) %>%
    group_by(across(-confidence_score)) %>%
    summarise(confidence_score = mean(confidence_score, na.rm = TRUE), .groups = "drop") %>% 
    left_join(df_labels, relationship = "many-to-many", by = join_by(filepath, page)) %>%
    mutate(
      type = if_else(is.na(type), "other", type),
      # match = if_else(predicted_type == classification_type, str_detect(type, predicted_type), !str_detect(type, classification_type))
      match = str_detect(type, predicted_type)
    )
  
  metrics <- list()
  
  for (class in c('Aktiva', 'GuV', 'Passiva', 'other')) {
    metrics[class] <- list(recalc_mectrics_singleclass(df_reeval, class))
  }
  
  metrics_minorities <- metrics[names(metrics) %in% c('Aktiva', 'GuV', 'Passiva')]
  new_metrics <- calculate_micro_macro_metrics(metrics_minorities, "_minorities")
  # browser()
  new_metrics2 <- calculate_micro_macro_metrics(metrics, "")
  metrics <- c(metrics, new_metrics, new_metrics2)
  
  metrics <- metrics %>% bind_rows()
  results <- list(predictions = list(df_reeval), metrics = list(metrics))
  return(results)
}

#### Binary ####
{
  json_files_page_identification_llm <- list.files(
    "../benchmark_results/page_identification/final/llm/",
    pattern = "\\.json$",
    full.names = TRUE
  ) %>%
    .[!grepl("_test_", .)] %>%
    .[grepl("_binary_", .)]
  
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
        loop = as.numeric((basename(file) %>% str_replace('__no_think', '') %>% str_match("loop_(.)(_queued)?\\.json"))[2]),
        classifier_type = str_split(name_split[2], '_')[[1]][2],
        classification_type = classification_type,
        runtime = json_data$runtime,
        # predictions = list(predictions),
        .before = 1
      )
    meta_list_llm[[length(meta_list_llm) + 1]] <- results
  }
  
  df_binary <- meta_list_llm %>% bind_rows() %>% mutate(
    n_examples = as.integer(n_examples)
    ) %>% rowwise() %>% 
      mutate(
        model_family = str_split(model, "_")[[1]][1]
      )
}

# df_binary %>% filter(loop > 0) %>% pull(model) %>% unique()

##### Nomalizing runtime #####

norm_factors <- read_csv("../benchmark_jobs/page_identification/gpu_benchmark/runtime_factors.csv") %>% 
  mutate(
    model_name = model_name %>% str_replace("/", "_")
  ) %>% filter(str_detect(filename, "binary"))
norm_factors_few_examples <- norm_factors %>% filter((str_ends(filename, "binary.yaml") | str_ends(filename, "multi.yaml")))
norm_factors_many_examples <- norm_factors %>% filter(!(str_ends(filename, "binary.yaml") | str_ends(filename, "multi.yaml"))) %>% 
  add_column(n_examples = list(c(5,7), c(5), c(7,9), c(11,13))) %>% unnest(n_examples)

df_binary_few_examples <- df_binary %>% filter(n_examples <= 3 | is.na(n_examples)) %>% 
  left_join(norm_factors_few_examples, by = c("model" = "model_name")) %>% mutate(
    norm_runtime = runtime*normalization_factor
  )
df_binary_many_examples <- df_binary %>% filter(n_examples > 3) %>% 
  left_join(norm_factors_many_examples, by = c("model" = "model_name", "n_examples" = "n_examples")) %>% mutate(
    norm_runtime = runtime*normalization_factor
  )

df_binary <- bind_rows(
  df_binary_few_examples,
  df_binary_many_examples
)

#### Multiclass ####

{
  json_files_page_identification_llm <- list.files(
    "../benchmark_results/page_identification/final/llm/",
    pattern = "\\.json$",
    full.names = TRUE
  ) %>%
    .[!grepl("_test_", .)] %>%
    .[grepl("_four_", .)]
  
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
    # classification_type <- str_split(name_split[2], '_')[[1]][3]
    
    results <- recalc_mectrics_multiclass(predictions) %>% as_tibble() %>% 
      as_tibble() %>% rowwise() %>%
      mutate(
        model = str_replace(name_split[1], "_vllm", ""),
        method = name_split[method_index],
        n_examples = str_match(method, "\\d+")[[1]],
        out_of_company = if_else(str_detect(method, "rag"), str_detect(method, "out_of_company"), NA),
        method_family = str_replace(str_replace(method, '\\d+', 'n'), '_out_of_company', ''),
        loop = as.numeric((basename(file) %>% str_replace('__no_think', '') %>% str_match("loop_(.)(_queued)?\\.json"))[2]),
        classifier_type = paste(str_split(name_split[2], '_')[[1]][c(2,3)], collapse = "_"),
        classification_type = NA,
        runtime = json_data$runtime,
        # predictions = list(predictions),
        .before = 1
      )
    meta_list_llm[[length(meta_list_llm) + 1]] <- results
  }
  
  df_multi <- meta_list_llm %>% bind_rows() %>% mutate(
    n_examples = as.integer(n_examples)
  ) %>% rowwise() %>% 
    mutate(
      model_family = str_split(model, "_")[[1]][1],
      )
}

# df_multi %>% filter(loop > 0) %>% pull(model) %>% unique()

##### Nomalizing runtime #####

norm_factors <- read_csv("../benchmark_jobs/page_identification/gpu_benchmark/runtime_factors.csv") %>% 
  mutate(
    model_name = model_name %>% str_replace("/", "_")
  ) %>% filter(str_detect(filename, "multi"))
norm_factors_few_examples <- norm_factors %>% filter((str_ends(filename, "binary.yaml") | str_ends(filename, "multi.yaml")))
norm_factors_many_examples <- norm_factors %>% filter(!(str_ends(filename, "binary.yaml") | str_ends(filename, "multi.yaml"))) %>% 
  add_column(n_examples = list(c(7,9,11,13), c(5))) %>% unnest(n_examples)

df_multi_few_examples <- df_multi %>% filter(n_examples <= 3 | is.na(n_examples)) %>% 
  left_join(norm_factors_few_examples, by = c("model" = "model_name")) %>% mutate(
    norm_runtime = runtime*normalization_factor
  )
df_multi_many_examples <- df_multi %>% filter(n_examples > 3) %>% 
  left_join(norm_factors_many_examples, by = c("model" = "model_name", "n_examples" = "n_examples")) %>% mutate(
    norm_runtime = runtime*normalization_factor
  )

df_multi <- bind_rows(
  df_multi_few_examples,
  df_multi_many_examples
)

list(df_binary = df_binary, df_multi = df_multi) %>% 
  saveRDS("data_storage/page_identification_llm.rds")
