library(jsonlite)
library(tidyverse)

count_doublepage_mistakes <- function(df, type) {
  select_type <- ifelse(type == "Aktiva", "Passiva", ifelse(type == "Passiva", "Aktiva", ""))
  
  df_doublepages <- df %>% group_by(filepath, page) %>% 
    filter(n() > 1) %>% filter(type == select_type)
  n_mistakes <- df %>% 
    filter(type == select_type, match == FALSE) %>% 
    anti_join(df_doublepages, by = c("filepath", "page", "type")) %>% 
    nrow()
  n_doublepage_mistakes <- nrow(df_doublepages) - n_mistakes
  return(n_doublepage_mistakes)
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
  
  name_split = (basename(file) %>% str_split("__"))[[1]]
  method_index = which(str_starts(name_split, "loop"))-1
  
  # print(name_split)
  
  results <-  json_data$metrics[[1]] %>% as_tibble() %>% rowwise() %>%
    mutate(
      model = name_split[1],
      method = name_split[method_index],
      n_examples = str_match(method, "\\d+")[[1]],
      out_of_company = if_else(str_detect(method, "rag"), str_detect(method, "out_of_company"), NA),
      method_family = str_replace(str_replace(method, '\\d+', 'n'), '_out_of_company', ''),
      loop = as.numeric((basename(file) %>% str_match("loop_(.)(_queued)?\\.json"))[2]),
      classifier_type = str_split(name_split[2], '_')[[1]][2],
      classification_type = str_split(name_split[2], '_')[[1]][3],
      runtime = json_data$runtime,
      results = list(fromJSON(json_data$results)),
      .before = 1
    )
  meta_list_llm[[length(meta_list_llm) + 1]] <- results
}

df <- meta_list_llm %>% bind_rows() %>% 
  mutate(
    false_positive = as.numeric(false_positive),
    true_positive = as.numeric(true_positive),
    false_negative = as.numeric(false_negative),
    fp = if_else(classification_type == "GuV", false_positive, false_positive - count_doublepage_mistakes(results, classification_type)),
    prec = true_positive/(true_positive+fp),
    f1 = if_else(prec+recall != 0, 2*prec*recall/(prec+recall), 0)
  )
}

df %>% filter(model == "Qwen_Qwen2.5-7B-Instruct_vllm") %>% 
  ggplot(aes(x = runtime, y = f1)) +
  geom_point(aes(color = method_family, shape = out_of_company), size = 7, alpha = .6) +
  scale_shape(na.value = 15, guide = "legend") +
  geom_text(aes(label = n_examples)) +
  facet_grid(model~classification_type) +
  theme(legend.position = "bottom") +
  guides(
    color = guide_legend(ncol = 1, title.position = "top"),
    shape = guide_legend(ncol = 1, title.position = "top")
  )

df_temp <- df$results[[6]] %>% as_tibble()
classification_type = "Passiva"
# how to handle activa and passiva on same page
df_doublepages <- df_temp %>% group_by(filepath, page) %>% 
  filter(n() > 1) %>% filter(type == classification_type)
df_temp %>% 
  filter(type == classification_type, match == FALSE) %>% 
  anti_join(df_doublepages, by = c("filepath", "page", "type"))

# if confidence < 1 better say no
df_temp %>% ggplot() +
  geom_boxplot(aes(x = match, y = confidence_score)) +
  geom_jitter(aes(x = match, y = confidence_score), alpha = .2, color = "red") +
  facet_wrap(~type)

df_labels <- read.csv("/home/simon/Documents/data_science/Thesis/benchmark_truth/aktiva_passiva_guv_table_pages_no_ocr.csv") %>% 
  as_tibble() %>% 
  mutate(
    filepath = str_replace(filepath, "..", "/pvc")
  )
df_temp %>% select(-type) %>% group_by(filepath, page) %>% 
  #left_join(df_labels, relationship = )
