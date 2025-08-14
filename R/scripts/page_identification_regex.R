source("./scripts/page_identification_preparations.R")

# Get a list of all .json files in the folder
json_files <- list.files("../benchmark_results/page_identification/", pattern = "regex.*\\.json$", full.names = TRUE)

calc_metrics <- function(classification_type) {
  # Initialize an empty dataframe to store results
  results_df <- data.frame(
    package = character(),
    method = character(),
    classification_type = character(),
    true_pos = numeric(),
    false_pos = numeric(),
    false_neg = numeric(),
    true_neg = numeric(),
    missing = numeric(),
    acc = numeric(),
    precision = numeric(),
    recall = numeric(),
    F1 = numeric(),
    runtime_in_s = numeric(),
    stringsAsFactors = FALSE
  )
  
  # Loop through each .json file
  for (file in json_files) {
    # browser()
    # print(file)
    
    json_data <- fromJSON(file)
    
    # Extract the required values
    correct_df <- as.data.frame(fromJSON(json_data$correct)) %>% filter(type == classification_type) %>% 
      filter(file %in% filenames_no_ocr)
    wrong_df <- as.data.frame(fromJSON(json_data$wrong)) %>% filter(type == classification_type) %>% 
      filter(file %in% filenames_no_ocr)
    missing_df <- as.data.frame(fromJSON(json_data$missing)) %>% filter(type == classification_type) %>% 
      filter(file %in% filenames_no_ocr)
    
    filename <- basename(file)
    package <- strsplit(filename, "_")[[1]][1]
    method <- gsub("\\.json$", "", paste(strsplit(filename, "_")[[1]][-1], collapse = " "))
    
    num_tables <- data_unnested %>% anti_join(consecutive_pages) %>% 
      ungroup() %>% filter(type == classification_type) %>% nrow()
    
    num_true_pos <- num_correct <- nrow(correct_df)
    num_false_pos <- num_wrong <- nrow(wrong_df)
    num_false_neg <- max(0, num_tables-num_true_pos)
    num_true_neg <- total_pages-num_true_pos-num_false_pos-num_false_neg
    num_missing <- nrow(missing_df)
    runtime <- round(json_data$runtime, 2)
    acc = round((num_true_pos+num_true_neg)/(total_pages),2)
    precision = round(num_true_pos/(num_true_pos+num_false_pos),2)
    recall = round(num_true_pos/(num_true_pos+num_false_neg),2)
    F1 = round(2*precision*recall/(precision+recall),2)
    
    # Append the values to the results dataframe
    results_df <- results_df %>%
      add_row(
        package = package,
        method = method,
        classification_type = classification_type,
        true_pos = num_true_pos,
        false_pos = num_false_pos,
        false_neg = num_false_neg,
        true_neg = num_true_neg,
        missing = num_missing,
        acc = acc,
        precision = precision,
        recall = recall,
        F1 = F1,
        runtime_in_s = runtime
      )
  }
  
  return(results_df %>% as_tibble())
}

metrics <- list()

for (type in c('Aktiva', 'Passiva', 'GuV')) {
  metrics[type] <- list(calc_metrics(type))
}

# # Loop through each .json file
# for (file in json_files) {
#   # Read the JSON file
#   json_data <- fromJSON(file)
#   
#   # Extract the required values
#   correct_df <- as.data.frame(fromJSON(json_data$correct)) # %>% filter(type == 'Aktiva')
#   wrong_df <- as.data.frame(fromJSON(json_data$wrong)) # %>% filter(type == 'Aktiva')
#   missing_df <- as.data.frame(fromJSON(json_data$missing)) # %>% filter(type == 'Aktiva')
#   
#   filename <- basename(file)
#   package <- strsplit(filename, "_")[[1]][1]
#   method <- gsub("\\.json$", "", paste(strsplit(filename, "_")[[1]][-1], collapse = " "))
#   
#   num_true_pos <- num_correct <- nrow(correct_df)
#   num_false_pos <- num_wrong <- nrow(wrong_df)
#   num_false_neg <- num_tables-num_correct
#   num_true_neg <- 3*total_pages-num_true_pos-num_false_pos-num_false_neg
#   num_missing <- nrow(missing_df)
#   runtime <- round(json_data$runtime, 2)
#   acc = round((num_true_pos+num_true_neg)/(3*total_pages),2)
#   precision = round(num_true_pos/(num_true_pos+num_false_pos),2)
#   recall = round(num_true_pos/(num_true_pos+num_false_neg),2)
#   F1 = round(2*precision*recall/(precision+recall),2)
#   
#   # Append the values to the results dataframe
#   results_df <- results_df %>%
#     add_row(
#       package = package,
#       method = method,
#       # acc = acc,
#       precision = precision,
#       recall = recall,
#       F1 = F1#,
#       # runtime_in_s = runtime
#     )
# }

metric_summaries <- list()

for (df in metrics) {
  type <- df$classification_type[[1]]
  results_df <- df %>%
    group_by(method) %>%
    summarise(
      precision_mean = mean(precision, na.rm = TRUE),
      precision_sd = sd(precision, na.rm = TRUE),
      recall_mean = mean(recall, na.rm = TRUE),
      recall_sd = sd(recall, na.rm = TRUE),
      F1_mean = mean(F1, na.rm = TRUE),
      F1_sd = sd(F1, na.rm = TRUE)
    ) %>%
    pivot_longer(
      cols = c(precision_mean, precision_sd, recall_mean, recall_sd, F1_mean, F1_sd),
      names_to = c("metric", "stat"),
      names_pattern = "(.*)_(mean|sd)"
    ) %>%
    pivot_wider(
      names_from = metric,
      values_from = value
    ) %>% 
    mutate_if(is.numeric, ~round(., 3))
  
  metric_summaries[type] <- list(results_df)
}

calc_metrics_by_company_and_type <- function() {
  df_list <- list()
  
  # Loop through each .json file
  for (file in json_files) {
     # browser()
    
    json_data <- fromJSON(file)
    
    # Extract the required values
    correct_df <- as_tibble(fromJSON(json_data$correct)) %>% 
      filter(file %in% filenames_no_ocr) %>% 
      group_by(company, type) %>% summarise(n_correct = n())
    wrong_df <- as_tibble(fromJSON(json_data$wrong)) %>% filter(file %in% filenames_no_ocr) %>% group_by(company, type) %>% summarise(n_wrong = n())
    # missing_df <- as_tibble(fromJSON(json_data$missing)) 
    # if (nrow(missing_df>0)) {
    #     missing_df <- df_missing %>% group_by(company, type) %>% summarise(n_missing = n())
    #   }
    
    filename <- basename(file)
    package <- strsplit(filename, "_")[[1]][1]
    method <- gsub("\\.json$", "", paste(strsplit(filename, "_")[[1]][-1], collapse = " "))
    runtime <- round(json_data$runtime, 2)
    
    num_tables <- data_unnested %>% anti_join(consecutive_pages) %>% 
      rowwise() %>% mutate(
      company = str_split(filepath, "/")[[1]][3]
    ) %>% group_by(type, company) %>% summarise(n_total = n())
    
    file_count <- data_unnested %>% rowwise() %>% mutate(
      company = str_split(filepath, "/")[[1]][3]
    ) %>% select(filepath, company) %>% unique() %>% group_by(company) %>% summarise(n_files = n())
    
    df_results <- correct_df %>% full_join(wrong_df) %>% full_join(num_tables) %>% 
      full_join(file_count) %>% rowwise() %>% mutate(
      num_true_pos = n_correct,
      num_false_pos = n_wrong,
      num_false_neg = max(0, (n_total-n_correct)),
      # acc = round((num_true_pos+num_true_neg)/(total_pages),2)
      precision = round(num_true_pos/(num_true_pos+num_false_pos),2),
      recall = round(num_true_pos/(num_true_pos+num_false_neg),2),
      F1 = round(2*precision*recall/(precision+recall),2),
      package = package,
      method = method,
      runtime_in_s = runtime
    ) %>% rename(classification_type = type)
    
    df_list[filename] <- list(df_results)
    
  }
  
  return(bind_rows(df_list) %>% as_tibble())
}

metrics_by_company_and_type <- calc_metrics_by_company_and_type()

list(
  metrics = metrics,
  metric_summaries = metric_summaries, 
  metrics_by_company_and_type = metrics_by_company_and_type
  ) %>% saveRDS("data_storage/page_identification_regex.rds")
