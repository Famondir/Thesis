# Initialize a counter for the total page count
total_pages <- 0

# Get the list of PDF files in the specified directory
pdf_files <- list.files(path = "../Geschaeftsberichte", pattern = "\\.pdf$", full.names = TRUE, recursive = TRUE)

# Loop through each PDF file to count pages
for (pdf_file in pdf_files) {
  # Use the pdftools package to count pages
  total_pages <- total_pages + pdftools::pdf_info(pdf_file)$pages
}

# all tables that could have been found
data <- read.csv("../benchmark_truth/aktiva_passiva_guv_table_pages_no_ocr.csv")

# Split the "type" column by '&' and explode it into multiple rows
data_unnested <- data %>%
  mutate(type = strsplit(as.character(type), "&")) %>%
  unnest(type)

num_tables <- data_unnested %>% 
  nrow()

# Get a list of all .json files in the folder
json_files <- list.files("../benchmark_results/page_identification/", pattern = "\\.json$", full.names = TRUE)

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
    
    # Read the JSON file
    json_data <- fromJSON(file)
    
    # Extract the required values
    correct_df <- as.data.frame(fromJSON(json_data$correct)) %>% filter(type == classification_type)
    wrong_df <- as.data.frame(fromJSON(json_data$wrong)) %>% filter(type == classification_type)
    missing_df <- as.data.frame(fromJSON(json_data$missing)) %>% filter(type == classification_type)
    
    filename <- basename(file)
    package <- strsplit(filename, "_")[[1]][1]
    method <- gsub("\\.json$", "", paste(strsplit(filename, "_")[[1]][-1], collapse = " "))
    
    num_tables <- data_unnested %>% filter(type == classification_type) %>% nrow()
    
    num_true_pos <- num_correct <- nrow(correct_df)
    num_false_pos <- num_wrong <- nrow(wrong_df)
    num_false_neg <- num_tables-num_correct
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
