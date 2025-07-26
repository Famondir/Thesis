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
df_toc_benchmark_5_pages <- toc_benchmark_data$toc_extraction_results_5_pages %>% mutate(benchmark_type = "5 pages") %>% 
  as_tibble() %>% filter(!is.na(page))
df_toc_benchmark_200_lines <- toc_benchmark_data$toc_extraction_results_200_lines %>% mutate(benchmark_type = "200 lines") %>% 
  as_tibble() %>% filter(!is.na(page))
df_toc_benchmark_mr <- toc_benchmark_data$machine_readable_toc %>% mutate(benchmark_type = "machine readable") %>% 
  as_tibble() %>% filter(!is.na(page))

df_toc_benchmark <- bind_rows(
  df_toc_benchmark_5_pages,
  df_toc_benchmark_200_lines,
  df_toc_benchmark_mr
) %>% group_by(type, benchmark_type) %>% 
  mutate(
    perc_correct = sum(in_range)/n(),
  )  %>% 
  rowwise() %>% 
  mutate(
    min_confidence = min(confidence_start_page, confidence_end_page),
    range = abs(end_page - start_page) + 1,
  )

n_found_toc_5_pages <- df_toc_benchmark_5_pages$filepath %>% unique() %>% length()
n_found_toc_200_lines <- df_toc_benchmark_200_lines$filepath %>% unique() %>% length()
n_found_toc_mr <- df_toc_benchmark_mr$filepath %>% unique() %>% length()

mean_ranges <- df_toc_benchmark %>% group_by(benchmark_type) %>% 
  reframe(
    `mean range` = mean(range, na.rm = T),
    `SD range` = sd(range, na.rm = T),
    ) %>% 
  mutate_if(is.numeric, round, digits = 2)

# df_toc_benchmark %>% 
#   select(type, start_page, end_page, benchmark_type, filepath) %>% 
#   filter(type != "GuV") %>% 
#   pivot_wider(values_from = c(start_page, end_page), names_from = type) %>% 
#   unnest() %>% mutate(
#     diff_start_page = start_page_Aktiva - start_page_Passiva,
#     diff_end_page = end_page_Aktiva - end_page_Passiva,
#     range_aktiva = end_page_Aktiva - start_page_Aktiva + 1,
#     range_passiva = end_page_Passiva - start_page_Passiva + 1,
#     ) %>% select(
#       filepath, benchmark_type,
#       range_aktiva, range_passiva,
#       diff_start_page, diff_end_page
#     ) %>%
#   mutate(
#     same_range = diff_start_page == diff_end_page,
#   ) %>%
#   pivot_longer(cols = c(diff_start_page, diff_end_page)) %>% ggplot() +
#   geom_histogram(aes(x = value, fill = same_range, alpha = range_aktiva == 1), binwidth = 1) +
#   facet_wrap(name~benchmark_type)

gpu_time_per_document_page_range <- tribble(~`Benchmark Type`, ~`Page range predicting`, ~`TOC extracting`,
        "5 pages", 36.9/66, (2*60+55.5)/80,
        "200 lines", 40.3/71, (5*60+4.2)/80,
        "machine readable", 26.9/43, NaN
) %>% 
  mutate_if(is.numeric, round, digits = 2)


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
  ungroup() %>% 
  mutate(
    correct = correct == "cum_n_correct",
    n_entries = ordered(n_entries)
    )

min_n_entries_max_correct <- df_toc_benchmark_mr_degration %>%
  filter(correct) %>% group_by(n_entries) %>% 
  summarise(sum = sum(value)) %>% filter(sum == max(sum)) %>% 
  pull(n_entries) %>% max() %>% as.character() %>% as.integer()

#### second run (balanced) ####

file_content <- readLines("../benchmark_results/page_identification/toc_results_mistral_8B_balance_details.json", warn = FALSE)
balanced_toc_benchmark_data <- paste(file_content, collapse = "\n") %>% str_replace_all(., "NaN", "null") %>% fromJSON()
balanced_df_toc_benchmark_5_pages <- balanced_toc_benchmark_data$toc_extraction_results_5_pages %>% mutate(benchmark_type = "5 pages") %>% 
  as_tibble() %>% filter(!is.na(page))
balanced_df_toc_benchmark_200_lines <- balanced_toc_benchmark_data$toc_extraction_results_200_lines %>% mutate(benchmark_type = "200 lines") %>%
  as_tibble() %>% filter(!is.na(page))
balanced_df_toc_benchmark_mr <- balanced_toc_benchmark_data$machine_readable_toc %>% mutate(benchmark_type = "machine readable") %>%
  as_tibble() %>% filter(!is.na(page))

balanced_df_toc_benchmark <- bind_rows(
  balanced_df_toc_benchmark_5_pages,
  balanced_df_toc_benchmark_200_lines,
  balanced_df_toc_benchmark_mr
) %>% group_by(type, benchmark_type) %>% 
  mutate(
    perc_correct = sum(in_range)/n(),
  )  %>% 
  rowwise() %>% 
  mutate(
    min_confidence = min(confidence_start_page, confidence_end_page),
    range = abs(end_page - start_page) + 1,
  )

df_toc_benchmark %>% filter(is.na(min_distance)) %>% # group_by(benchmark_type, type, in_range) %>% 
  summarise(n = n())

# df_toc_benchmark %>% ggplot() +
#   geom_bar(aes(x = type, fill = forcats::fct_rev(ordered(min_distance)), color = in_range)) +
#   geom_text(
#     data = df_toc_benchmark %>% filter(in_range == TRUE),
#     aes(x = type, label = paste0(round(perc_correct, 2), "")),
#     stat = "count",
#     vjust = 1.2,
#     color = "white"
#   ) +
#   geom_text(
#     aes(x = type, label = paste0(round(1-perc_correct, 2), "")),
#     stat = "count",
#     vjust = 1.5,
#     color = "white"
#   ) +
#   facet_wrap(~benchmark_type, nrow = 1)
