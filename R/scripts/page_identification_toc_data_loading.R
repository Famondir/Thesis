library(jsonlite)
library(tidyverse)

#### functions ####

distance_confidence_plot <- function(df) {
  df %>%
    mutate(
      min_confidence = log(min(min_confidence))
    ) %>%
    ggplot() +
    geom_point(aes(x = min_confidence, y = min_distance, color = in_range, shape = type)) +
    stat_smooth(aes(x = min_confidence, y = min_distance), method = 'lm', formula = y ~ x+0, se = TRUE, fullrange = TRUE) +
    xlim(-3, 0)
}

#### General TOC Data ####

file_content <- readLines("../benchmark_truth/toc_data.json", warn = FALSE)
toc_data <- fromJSON(paste(file_content, collapse = "\n"))

n_toc = nrow(toc_data$files_with_toc)
n_no_toc = length(toc_data$files_without_toc)

#### General page data ####

file_content <- readLines("../Python/pdf_texts.json", warn = FALSE)
text <- paste(file_content, collapse = "\n")
page_data <- fromJSON(text)

num_lines <- page_data %>% sapply(function(x) { length(str_split(paste(x[1:5], collapse = "\n"), "\n")[[1]]) })

#### TOC benchmarks ####

file_content <- readLines("../benchmark_results/page_identification/toc_results_mistral_8B.json", warn = FALSE)
toc_benchmark_data <- paste(file_content, collapse = "\n") %>% str_replace_all(., "NaN", "null") %>% fromJSON()
df_toc_benchmark_5_pages <- toc_benchmark_data$toc_extraction_results_5_pages %>% mutate(benchmark_type = "5 pages") %>% as_tibble()
df_toc_benchmark_200_lines <- toc_benchmark_data$toc_extraction_results_200_lines %>% mutate(benchmark_type = "200 lines") %>% as_tibble()
df_toc_benchmark_mr <- toc_benchmark_data$machine_readable_toc %>% mutate(benchmark_type = "machine readable") %>% as_tibble()

df_toc_benchmark <- bind_rows(
  df_toc_benchmark_5_pages,
  df_toc_benchmark_200_lines,
  df_toc_benchmark_mr
) %>% group_by(type, benchmark_type) %>% 
  mutate(
    perc_correct = sum(in_range)/n(),
  )

n_found_toc_5_pages <- df_toc_benchmark_5_pages$filepath %>% unique() %>% length()
n_found_toc_200_lines <- df_toc_benchmark_200_lines$filepath %>% unique() %>% length()
n_found_toc_mr <- df_toc_benchmark_mr$filepath %>% unique() %>% length()

##### 5 pages #####

df_toc_benchmark_5_pages_range <- df_toc_benchmark_5_pages %>% 
  rowwise() %>% 
  mutate(
  min_confidence = min(confidence_start_page, confidence_end_page),
  range = abs(end_page - start_page) + 1,
)

# df_toc_benchmark_5_pages_range %>% ggplot() +
#   geom_violin(aes(y = range, x = in_range)) +
#   facet_wrap(~type, ncol = 1)
# 
# df_toc_benchmark_5_pages_range %>% ggplot() +
#   geom_jitter(aes(x = min_confidence, y = range, color = in_range))
# 
# df_toc_benchmark_5_pages_range %>% group_by(filepath) %>%
#   distance_confidence_plot()

##### 200 lines #####

df_toc_benchmark_200_lines_range <- df_toc_benchmark_200_lines %>% 
  rowwise() %>% 
  mutate(
    min_confidence = min(confidence_start_page, confidence_end_page),
    range = abs(end_page - start_page) + 1,
  )

# df_toc_benchmark_200_lines_range %>% group_by(filepath) %>% 
#   distance_confidence_plot()

##### mr #####

df_toc_benchmark_mr_range <- df_toc_benchmark_mr %>% 
  rowwise() %>% 
  mutate(
    min_confidence = min(confidence_start_page, confidence_end_page),
    range = abs(end_page - start_page) + 1,
  )

# df_toc_benchmark_mr_range %>% group_by(filepath) %>% 
#   distance_confidence_plot()

df_toc_benchmark_mr_degration <- toc_data$files_with_toc %>% 
  as_tibble() %>%
  rename(filepath = path) %>%
  mutate(filepath = str_replace(filepath, "/home/simon/Documents/data_science/Thesis", "..")) %>%
  right_join(df_toc_benchmark_mr) %>%
  group_by(type, n_entries) %>%
  reframe(
    n_correct = sum(in_range == TRUE),
    n_incorrect = sum(in_range == FALSE),
  ) %>%
  arrange(type, desc(n_entries)) %>%
  group_by(type) %>%
  mutate(
    cum_n_correct = cumsum(n_correct),
    cum_n_incorrect = cumsum(n_incorrect)
  ) %>% select(type, n_entries, starts_with("cum")) %>% 
  mutate(
    perc_correct = cum_n_correct / (cum_n_correct + cum_n_incorrect),
  ) %>%
  pivot_longer(-c(type, n_entries, perc_correct), names_to = "correct") %>% 
  mutate(
    correct = correct == "cum_n_correct",
    n_entries = ordered(n_entries)
    )

min_n_entries_max_correct <- df_toc_benchmark_mr_degration %>%
  filter(correct) %>% group_by(n_entries) %>% 
  summarise(sum = sum(value)) %>% filter(sum == max(sum)) %>% 
  pull(n_entries) %>% max() %>% as.character() %>% as.integer()