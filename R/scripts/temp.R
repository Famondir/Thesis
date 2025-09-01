df_real_table_extraction %>% 
  filter(str_detect(model, "235B")) %>% 
  group_by(model, method) %>% 
  mutate(mean_perc_total = mean(percentage_correct_total)) %>% 
  ungroup() %>% 
  slice_max(n=1, mean_perc_total) %>% 
  select(method, filepath, percentage_correct_total, percentage_correct_numeric, NA_F1) %>% 
  arrange(percentage_correct_total) %>% View()

#####

df_real_table_extraction_synth <- readRDS("data_storage/real_table_extraction_extended_synth.rds") %>% 
  filter(!model %in% c("deepseek-ai_DeepSeek-R1-Distill-Qwen-32B", 'google_gemma-3n-E4B-it')) %>% 
  mutate(model = gsub("^[^_]+_", "", model))

df_real_table_extraction_extended <- readRDS("data_storage/real_table_extraction_extended_llm.rds") %>% 
  filter(!model %in% c("deepseek-ai_DeepSeek-R1-Distill-Qwen-32B", 'google_gemma-3n-E4B-it')) %>% 
  mutate(model = gsub("^[^_]+_", "", model))

units_real_tables <- read_csv("../benchmark_truth/real_tables/table_characteristics_more_examples.csv") %>% mutate(
  filepath = paste0('/pvc/benchmark_truth/real_tables/', company, '__', filename),
  T_EUR = (T_in_year + T_in_previous_year)>0,
  T_EUR_both = (T_in_year + T_in_previous_year)>1
) %>% select(filepath, T_EUR, T_EUR_both)

df_real_table_extraction_synth <- df_real_table_extraction_synth %>% left_join(units_real_tables)

df_overview <- bind_rows(df_real_table_extraction_extended) %>% 
  filter(out_of_company != TRUE | is.na(out_of_company), n_examples <= 3, n_examples != 2) %>% 
  filter(model %in% model_by_size) %>%
  mutate(
    model = factor(model, levels = model_by_size),
    method_family = factor(method_family, levels = method_order),
    n_examples = fct_rev(ordered(paste("n =", n_examples)))
  )

df_overview %>% 
  ggplot() +
  geom_hline(yintercept = real_table_extraction_regex_num_performance_mean, linetype = "dashed") +
  geom_boxplot(aes(x = model, y = percentage_correct_numeric, fill = model_family)) +
  scale_x_discrete(guide = guide_axis(angle = 30)) +
  facet_nested(method_family + n_examples ~ .) +
  theme(
    legend.position = "bottom"
  )

####

confidence_vs_truth_multi <- df_multi %>% 
  filter(model %in% c("Ministral-8B-Instruct-2410", "Llama-4-Scout-17B-16E-Instruct", "Qwen3-8B")) %>% 
  unnest(metrics) %>% 
  group_by(method, model, metric_type) %>% mutate(
    mean_f1 = mean(f1_score, na.rm=TRUE), .before = 1
  ) %>% group_by(model, metric_type) %>% 
  arrange(desc(mean_f1)) %>% 
  slice_max(mean_f1, n = 1, with_ties = FALSE) %>% 
  select(-filepath) %>% 
  unnest(predictions) %>% mutate(
    match = factor(match, levels = c(F, T)),
    # truth_NA = factor(truth_NA, levels = c(F, T))
  ) %>% filter(metric_type %in% c("Aktiva", "Passiva", "GuV"))

confidence_vs_truth_multi %>% ggplot() +
  geom_boxplot(
    aes(x = match, y = confidence_score, fill = metric_type), 
    position = position_dodge2(preserve = "single")) +
  scale_fill_discrete(drop = FALSE) +
  scale_x_discrete(drop = FALSE) +
  facet_grid(~ model)

confidence_vs_truth_multi %>% rename(confidence = confidence_score) %>% 
  mutate(
    conf_interval = cut(confidence, breaks = seq(0, 1, by = 0.05), include.lowest = TRUE),
    conf_center = as.numeric(sub("\\((.+),(.+)\\]", "\\1", levels(conf_interval))[conf_interval]) + 0.025
  ) %>%
  group_by(conf_center, metric_type, model) %>%
  summarize(
    n_true = sum(match == TRUE, na.rm = TRUE),
    n_false = sum(match == FALSE, na.rm = TRUE),
    total = n_true + n_false,
    chance_false = if_else(total > 0, n_false / total * 100, NA_real_),
    chance_zero = chance_false == 0,
    chance_below_1 = chance_false < 1,
    chance_low = if_else(chance_zero, 0, if_else(chance_below_1, 1, 2)),
    chance_low = factor(chance_low, levels = c(0,1,2), labels = c("equls 0 %", "below 1 %", "more")),
    .groups = "drop"
  ) %>%
  ggplot(aes(x = conf_center, y = chance_false, color = chance_low, fill = chance_false
             )) +
  geom_col(alpha = 0.7) +
  scale_fill_viridis_c() +
  # geom_hline(yintercept = 1, linetype = "dashed") +
  # geom_smooth(method = "lm", se = TRUE) +
  scale_color_manual(values = c("green", "yellow", "red")) +
  labs(x = "Confidence Interval Center", y = "Chance False (%)", color = "mistake rate") +
  coord_cartesian(
    ylim = c(0, 50), 
    xlim = c(0,1)
    ) +
  facet_grid(metric_type ~ model)

# how to show the number of data?

confidence_vs_truth_multi %>% rename(confidence = confidence_score) %>% 
  mutate(
    conf_interval = cut(confidence, breaks = seq(0, 1, by = 0.01), include.lowest = TRUE),
    conf_center = as.numeric(sub("\\((.+),(.+)\\]", "\\1", levels(conf_interval))[conf_interval]) + 0.005
  ) %>%
  group_by(conf_center, metric_type, model) %>%
  summarise(
    n_true = sum(match == TRUE, na.rm = TRUE),
    n_false = sum(match == FALSE, na.rm = TRUE),
    total = n_true + n_false,
    chance_false = if_else(total > 0, n_false / total * 100, NA_real_),
    chance_zero = chance_false == 0,
    chance_below_1 = chance_false < 1,
    chance_low = if_else(chance_zero, 0, if_else(chance_below_1, 1, 2)),
    chance_low = factor(chance_low, levels = c(0,1,2), labels = c("equls 0 %", "below 1 %", "more"))
  ) %>% group_by(metric_type, model) %>% mutate(
    perc = total/sum(total)*100
  ) %>% ungroup() %>% 
  mutate(
    chance_false_interval = cut(
      chance_false,
      breaks = c(0, 1, 2, 4, 8, 16, 32, 64, Inf),
      labels = c("[0,1)", "[1,2)", "[2,4)", "[4,8)", 
                 "[8,16)", "[16,32)", "[32,64)", "[64,Inf)"),
      right = FALSE,
      ordered_result = TRUE
    ),
  ) %>%
  ggplot() +
  geom_col(aes(x = conf_center, y = perc, color = chance_low, fill = chance_false_interval), alpha = 1) +
  geom_text(
    aes(x = conf_center, y = perc, label = round(perc, 0)), 
    position = position_stack(vjust = 1), vjust = -0.6, 
    size = 3, color = "black"
  ) +
  scale_color_manual(values = c("#00CC00", "orange", "#555555")) +
  scale_fill_manual(values = rev(c("#d53e4f", "#f46d43", "#fdae61", "#fee08b", "#e6f598", "#abdda4", "#66c2a5", "#3288bd"))) +
  labs(
    x = "Confidence Interval Center", 
    y = "Percentage of predictions", 
    color = "mistake rate") +
  coord_cartesian(
    # ylim = c(0, 50), 
    xlim = c(0,1)
  ) +
  facet_grid(metric_type ~ model)

######

df_multi %>% 
  filter(model %in% c("Ministral-8B-Instruct-2410", "Llama-4-Scout-17B-16E-Instruct", "Qwen3-8B")) %>% 
  unnest(metrics) %>% 
  group_by(method, model, metric_type) %>% mutate(
    mean_f1 = mean(f1_score, na.rm=TRUE), .before = 1
  ) %>% group_by(model, metric_type) %>% 
  arrange(desc(mean_f1)) %>% 
  slice_max(mean_f1, n = 1, with_ties = FALSE) %>% 
  select(-filepath) %>% 
  unnest(predictions) %>% mutate(
    match = factor(match, levels = c(F, T)),
    # truth_NA = factor(truth_NA, levels = c(F, T))
  ) %>% filter(metric_type %in% c("Aktiva", "Passiva", "GuV")) %>% 
  group_by(model, metric_type) %>% summarise(n())




# selected_type <- "Aktiva"
# model_name <- "Ministral-8B-Instruct-2410"
# method_name <- "3_rag_examples"
model_name <- "Llama-4-Scout-17B-16E-Instruct"
method_name <- "3_rag_examples"

df_temp_mistral_multi <- df_multi %>% 
  filter(
    model == model_name,
    method == method_name
  ) # %>% unnest(metrics) # %>% calc_micro_f1(model, method)
p_aktiva <- df_temp_mistral_multi %>% plot_pr_double_curve_multi("Aktiva", x_stuff = FALSE)
p_passiva <- df_temp_mistral_multi %>% plot_pr_double_curve_multi("Passiva", x_stuff = FALSE)
p_guv <- df_temp_mistral_multi %>% plot_pr_double_curve_multi("GuV", x_stuff = TRUE)

wrap_elements(p_aktiva) / wrap_elements(p_passiva) / wrap_elements(p_guv) +
  plot_layout(heights = c(2, 2, 3)) +
  plot_annotation(title = str_c(model, " with ", method))


#####

plot_pr_double_curve_tf <- function(df, selected_type, x_stuff = FALSE) {
  df_temp2 <- df %>% filter(
    n_predictors == 4, data_split == "test",
    type == selected_type
  ) %>% 
    rename(
      confidence_score = score
    ) %>% 
    mutate(
      type = factor(is_truth, levels = c(1, 0))
    )
  
  # Precision-Recall Curve with ggplot2
  
  pr_df <- df_temp2 %>% pr_curve(type, confidence_score) %>%
    rename(threshold = .threshold) %>% filter(threshold<=1) %>% 
    mutate(f1 = 2 * precision * recall / (precision + recall))
  
  pr_auc <- round(df_temp2 %>% pr_auc(type, confidence_score) %>% .$.estimate, 3)
  best_F1_row <- pr_df %>% slice_max(n = 1, f1)  
  best_F1_row_high_recall <- pr_df %>% 
    filter(recall > 0.999, precision > 0.1) %>% slice_max(n = 1, f1)  
  best_F1 <- best_F1_row  %>% pull(f1)
  best_F1_high_recall <- best_F1_row_high_recall %>% pull(f1)
  best_threshold <- best_F1_row  %>% pull(threshold)
  best_threshold_high_recall <- best_F1_row_high_recall  %>% pull(threshold)
  best_precision_high_recall <- best_F1_row_high_recall  %>% pull(precision)
  
  g1 <- pr_df %>%
    ggplot(aes(x = recall, y = precision)) +
    geom_line(aes(color = threshold), size = 1.2) +
    scale_color_viridis_c(option = "plasma", limits = c(0, 1)) +
    labs(
      subtitle = paste0("Precision-Recall Curve for ", selected_type, " (AUC = ", pr_auc, ")"),
      x = "Recall",
      y = "Precision"
    ) +
    coord_cartesian(ylim = c(0,1)) +
    theme(
      legend.position = "bottom"
    )
  
  g2 <- pr_df %>%
    ggplot(aes(x = recall, y = precision, color = f1)) +
    geom_line(size = 1.2) +
    scale_color_viridis_c(option = "viridis", limits = c(0, 1)) +
    labs(
      # title = "Precision-Recall Curve colored by F1 score",
      x = "Recall",
      y = NULL,
      color = "F1 score"
    ) +
    coord_cartesian(ylim = c(0,1))+
    theme(
      legend.position = "bottom"
    ) 
  
  if (x_stuff == FALSE) {
    g1 <- g1 + guides(color = FALSE) +
      labs(x = element_blank())
    
    g2 <- g2 + guides(color = FALSE) +
      labs(x = element_blank())
  }
  
  combined_plot <- g1 + g2
  combined_plot + plot_annotation(caption = paste0(
    'Best F1 score of ', round(best_F1,3) , ' gets reached with threshold of value ', round(best_threshold,3), '\n',
    'Best F1 score with recall > 0.999 of ', round(best_F1_high_recall,3) , ' gets reached with threshold of value ', round(best_threshold_high_recall,3), ' (corresp. precision value: ', round(best_precision_high_recall,3) , ')'))
}

df_temp <- df_rf_results

df_rf_results %>% filter(type == "Aktiva") %>% 
  filter(score > 0.999) %>% select(score, is_truth) %>% 
  group_by(is_truth) %>% summarise(n())

p_aktiva <- df_temp %>% plot_pr_double_curve_tf("Aktiva", x_stuff = FALSE)
p_passiva <- df_temp %>% plot_pr_double_curve_tf("Passiva", x_stuff = FALSE)
p_guv <- df_temp %>% plot_pr_double_curve_tf("GuV", x_stuff = TRUE)
# p_other <- df_temp_mistral_multi %>% plot_pr_double_curve_multi("other", x_stuff = TRUE)

wrap_elements(p_aktiva) / wrap_elements(p_passiva) / wrap_elements(p_guv) +
  plot_layout(heights = c(2, 2, 3)) +
  plot_annotation(title = str_c(model, " with ", method))
  
####

pr_df <- df_temp %>% pr_curve(type, confidence_score) %>%
  rename(threshold = .threshold) %>% filter(threshold<=1) %>% 
  mutate(f1 = 2 * precision * recall / (precision + recall))

pr_auc <- round(df_temp %>% pr_auc(type, confidence_score) %>% .$.estimate, 3)


# best_F1_row <- pr_df %>% slice_max(n = 1, f1)  
# best_F1_row_high_recall <- pr_df %>% 
#   filter(recall > 0.999, precision > 0.1) %>% slice_max(n = 1, f1)  
# best_F1 <- best_F1_row  %>% pull(f1)
# best_F1_high_recall <- best_F1_row_high_recall %>% pull(f1)
# best_threshold <- best_F1_row  %>% pull(threshold)
# best_threshold_high_recall <- best_F1_row_high_recall  %>% pull(threshold)
# best_precision_high_recall <- best_F1_row_high_recall  %>% pull(precision)

g1 <- pr_df %>%
  ggplot(aes(x = recall, y = precision)) +
  geom_line(aes(color = threshold), size = 1.2) +
  scale_color_viridis_c(option = "plasma", limits = c(0, 1)) +
  labs(
    subtitle = paste0("Precision-Recall Curve for ", selected_type, " (AUC = ", pr_auc, ")"),
    x = "Recall",
    y = "Precision"
  ) +
  coord_cartesian(ylim = c(0,1)) +
  theme(
    legend.position = "bottom"
  )

g2 <- pr_df %>%
  ggplot(aes(x = recall, y = precision, color = f1)) +
  geom_line(size = 1.2) +
  scale_color_viridis_c(option = "viridis", limits = c(0, 1)) +
  labs(
    # title = "Precision-Recall Curve colored by F1 score",
    x = "Recall",
    y = NULL,
    color = "F1 score"
  ) +
  coord_cartesian(ylim = c(0,1))+
  theme(
    legend.position = "bottom"
  ) 

g1 + g2 

# Precision-Recall Curve with ggplot2

pr_obj <- pr.curve(scores.class0 = df_temp$score[df_temp$is_truth == 1],
                   scores.class1 = df_temp$score[df_temp$is_truth == 0],
                   curve = TRUE)

pr_df <- tibble(
  recall = pr_obj$curve[, 1],
  precision = pr_obj$curve[, 2],
  threshold = pr_obj$curve[, 3]
) %>%
  mutate(f1 = 2 * precision * recall / (precision + recall))

pr_auc <- round(pr_obj$auc.integral, 3)

g1 <- pr_df %>%
  ggplot(aes(x = recall, y = precision)) +
  geom_line(aes(color = threshold), size = 1.2) +
  scale_color_viridis_c(option = "plasma") +
  labs(
    title = str_c("Precision-Recall Curve (AUC = ", pr_auc, ")"),
    x = "Recall",
    y = "Precision"
  ) +
  coord_cartesian(ylim = c(0,1)) +
  theme(
    legend.position = "bottom"
  )

g2 <- pr_df %>%
  ggplot(aes(x = recall, y = precision, color = f1)) +
  geom_line(size = 1.2) +
  scale_color_viridis_c(option = "viridis") +
  labs(
    # title = "Precision-Recall Curve colored by F1 score",
    x = "Recall",
    # y = "Precision",
    color = "F1 score"
  ) +
  coord_cartesian(ylim = c(0,1))+
  theme(
    legend.position = "bottom"
  )

g1 + g2

######

filepathes_toc_mr <- next_page_df_toc_benchmark %>% 
  filter(benchmark_type == "machine readable") %>% 
  pull(filepath) %>% unique()

next_page_df_toc_benchmark_combi <- next_page_df_toc_benchmark %>% 
  filter(benchmark_type == "machine readable") %>% 
  bind_rows(
    next_page_df_toc_benchmark %>% 
      filter(benchmark_type == "200 lines", 
             !filepath %in% filepathes_toc_mr
             ))

next_page_df_toc_benchmark %>% 
  filter(benchmark_type == "machine readable") %>% 
  group_by(type) %>% 
  reframe(
    n_correct = sum(in_range),
    n_tried = n()
    ) %>% 
  left_join(
      data_unnested %>% group_by(type) %>% summarise(n_total = n())    
    ) %>% mutate(
      precision_like = n_correct/n_tried,
      recall = n_correct/n_total
    )

next_page_df_toc_benchmark_combi %>% group_by(type) %>% 
  reframe(
    n_correct = sum(in_range),
    n_tried = n()
    ) %>% 
  left_join(
    data_unnested %>% group_by(type) %>% summarise(n_total = n())    
  ) %>% mutate(
    precision_like = n_correct/n_tried,
    recall = n_correct/n_total
  )

##### top k accuracy ####

library(dplyr)
library(tidyr)
library(purrr)

(top_k_results <- df_binary %>%
  filter(model == "Ministral-8B-Instruct-2410", method == "3_rag_examples") %>%
  group_by(classification_type) %>%
  slice_max(n = 1, f1_score, with_ties = FALSE) %>%
  select(-filepath) %>%
  unnest(predictions) %>%
  select(match, confidence_score, classification_type, filepath, predicted_type) %>%
    mutate(confidence_score = if_else(predicted_type == classification_type, confidence_score, 1-confidence_score)) %>% 
  # filter(predicted_type == classification_type) %>% 
  group_by(classification_type, filepath) %>%
  arrange(desc(confidence_score), .by_group = TRUE) %>%
  mutate(rank = row_number()) %>%
  ungroup() %>%
  group_by(classification_type, filepath) %>%
  arrange(rank, .by_group = TRUE) %>%
  mutate(
    cum_match = cumsum(match == TRUE)
  ) %>%
  ungroup() %>%
  group_by(classification_type, rank) %>%
  summarise(
    top_k_recall = mean(cum_match >= 1),
    .groups = "drop"
  ) %>%
  filter(rank <= 5, 
         #classification_type == "Passiva"
         )
  )

# If you want a wide format (k as columns):
top_k_wide <- top_k_results %>%
  pivot_wider(names_from = rank, values_from = top_k_recall, names_prefix = "top_")
top_k_wide




(top_k_results <- df_multi %>%
    unnest(metrics) %>% 
    filter(metric_type %in% c("Aktiva", "Passiva", "GuV")) %>% 
    filter(model == "Ministral-8B-Instruct-2410", method == "3_rag_examples") %>%
    mutate(classification_type = metric_type) %>% 
    group_by(classification_type) %>%
    slice_max(n = 1, f1_score, with_ties = FALSE) %>%
    select(-filepath) %>%
    unnest(predictions) %>%
    select(match, confidence_score, classification_type, filepath, predicted_type) %>%
    mutate(confidence_score = if_else(predicted_type == classification_type, confidence_score, 1-confidence_score)) %>% 
    # filter(predicted_type == classification_type) %>% 
    group_by(classification_type, filepath) %>%
    arrange(desc(confidence_score), .by_group = TRUE) %>%
    mutate(rank = row_number()) %>%
    ungroup() %>%
    group_by(classification_type, filepath) %>%
    arrange(rank, .by_group = TRUE) %>%
    mutate(
      cum_match = cumsum(match == TRUE)
    ) %>%
    ungroup() %>%
    group_by(classification_type, rank) %>%
    summarise(
      top_k_recall = mean(cum_match >= 1),
      .groups = "drop"
    ) %>%
    filter(rank <= 5, 
           #classification_type == "Passiva"
    )
)

#### llm usage table extraction csv ####

# df_empty <- readRDS("data_storage/table_extraction_regex.rds") %>% slice_head(n=1) %>% 
#   pull(predictions) %>% .[[1]]
# df_empty$year_result <- NA
# df_empty$previous_year_result <- NA
# df_empty

norm_factors <- read_csv("../benchmark_jobs/page_identification/gpu_benchmark/runtime_factors_real_table_extraction.csv") %>% 
  mutate(
    model_name = model_name %>% str_replace("/", "_")
  )
norm_factors_few_examples <- norm_factors %>% filter((str_ends(filename, "binary.yaml") | str_ends(filename, "multi.yaml") | str_ends(filename, "vllm_batched.yaml")))


df_real_table_extraction %>% select(model_family, model) %>% 
  mutate(task = "real tables") %>% 
  bind_rows(
    df_synth_table_extraction %>% select(model_family, model) %>% 
      mutate(task = "synth tables") 
  ) %>% 
  bind_rows(
    df_real_table_extraction_synth %>% select(model_family, model) %>% 
      mutate(task = "hybrid")
  ) %>% 
  bind_rows(
    df_real_table_extraction_azure %>% select(model_family, model) %>%
      mutate(task = "real tables")
  ) %>%
  bind_rows(
    df_binary %>% select(model_family, model) %>%
      mutate(task = "binary") %>% mutate(
        # model_family = sub("_.*", "", model),
        model_family = if_else(str_detect(model, "Qwen2"), "Qwen 2.5", model_family),
        model_family = if_else(str_detect(model, "Qwen3"), "Qwen 3", model_family),
        model_family = if_else(str_detect(model, "Llama-3"), "Llama-3", model_family),
        model_family = if_else(str_detect(model, "Llama-4"), "Llama-4", model_family),
        model = str_remove(model, "-0-9-1")
      )
  ) %>%
  bind_rows(
    df_multi %>% select(model_family, model) %>%
      mutate(task = "multi-class") %>% mutate(
        # model_family = sub("_.*", "", model),
        model_family = if_else(str_detect(model, "Qwen2"), "Qwen 2.5", model_family),
        model_family = if_else(str_detect(model, "Qwen3"), "Qwen 3", model_family),
        model_family = if_else(str_detect(model, "Llama-3"), "Llama-3", model_family),
        model_family = if_else(str_detect(model, "Llama-4"), "Llama-4", model_family),
        model = str_remove(model, "-0-9-1")
      )
  ) %>%
  unique() %>% 
  mutate(used = "X") %>% 
  left_join(
    norm_factors_few_examples %>% 
      mutate(model = gsub("^[^_]+_", "", model_name)) %>% 
      select(model, parameter_count),
  ) %>% 
  pivot_wider(names_from = task, values_from = used) %>% 
  write_csv("data_storage/model_usage_extraction.csv")


df <- read_csv("data_storage/model_usage_extraction.csv") %>% 
  arrange(tolower(model_family), parameter_count) %>% 
  mutate_if(is.character, ~if_else(is.na(.), "", .))

alignment="lrccccc"
caption="Overview of benchmarked LLMs for the extraction tasks."
col_idx = 1
row_group_col = 1
row_groups <- generate_row_groups(df, row_group_col = col_idx)
# df <- df %>% ungroup() %>% select(-col_idx)
kbl_out <- kbl(
  df, escape = FALSE, format = "latex", align = alignment, caption = caption, booktabs = T
) %>% kable_styling()

for (grp in row_groups) {
  kbl_out <- kbl_out %>% pack_rows(grp$name, grp$start, grp$end, label_row_css = grp$css)
}
kbl_out

colgroups = c(" " = 2, "information extraction" = 3, "page identification" = 2)
kbl_out %>% add_header_above(colgroups)

sketch = htmltools::withTags(table(
  class = 'display',
  thead(
    tr(
      th(rowspan = 2, 'Species'),
      th(colspan = 2, 'Sepal'),
      th(colspan = 2, 'Petal')
    ),
    tr(
      lapply(rep(c('Length', 'Width'), 2), th)
    )
  )
))
print(sketch)
datatable(iris[1:20, c(5, 1:4)], container = sketch, rownames = FALSE)

####

confidence_vs_truth_multi %>% ggplot() +
  geom_boxplot(
    aes(x = match, y = confidence_score, fill = metric_type), 
    position = position_dodge2(preserve = "single")) +
  scale_fill_discrete(drop = FALSE) +
  scale_x_discrete(drop = FALSE) +
  facet_grid(~ model) + 
  geom_point(
    data = .%>% group_by(model, metric_type, match) %>% mutate(n = n(), .before = 1) %>% filter(n<20),
    aes(x = match, y = confidence_score, alpha = metric_type), color = "green",
    shape = 4, position=position_jitterdodge(dodge.width=1, jitter.width = 0.05, jitter.height = 0.005)
  ) +
  scale_alpha_manual(values = c(1, 1, 1), guide = "none")

####

confidence_vs_truth_real <- df_real_table_extraction %>% 
  # filter(loop == 0) %>% 
  filter(model %in% c("Ministral-8B-Instruct-2410", "Qwen3-8B", "Qwen3-235B-A22B-Instruct-2507-FP8")) %>% 
  group_by(method, model, loop) %>% mutate(
    mean_percentage_correct_total = mean(percentage_correct_total, na.rm=TRUE), .before = 1
  ) %>% group_by(model) %>% 
  # arrange(desc(mean_percentage_correct_total)) %>% 
  slice_max(mean_percentage_correct_total, n = 1, with_ties = TRUE) %>% 
  mutate(predictions_processed = map(predictions, ~{
    .x %>% 
      select(-"_merge") %>% 
      mutate(
        match = (year_truth == year_result) | (is.na(year_truth) & is.na(year_result)),
        confidence = confidence_this_year,
        truth_NA = is.na(year_truth),
        predicted_NA = is.na(year_result),
        .before = 4
      ) %>% nest(
        tuple_year = c(match, confidence, truth_NA, predicted_NA)
      ) %>% 
      mutate(
        confidence = confidence_previous_year,
        match = (previous_year_truth == previous_year_result) | (is.na(previous_year_truth) & is.na(previous_year_result)),
        truth_NA = is.na(previous_year_truth),
        predicted_NA = is.na(previous_year_result),
        .before = 4
      ) %>% nest(
        tuple_previous_year = c(match, confidence, truth_NA, predicted_NA)
      ) %>% select(
        -c(year_truth, previous_year_truth, year_result, previous_year_result,
           confidence_this_year, confidence_previous_year)
      ) %>% 
      pivot_longer(-c("E1", "E2", "E3")) %>% 
      unnest(cols = value) %>% mutate(
        match = if_else(is.na(match), FALSE, match)
      )
  })) %>% 
  unnest(predictions_processed) %>% mutate(
    match = factor(match, levels = c(F, T)),
    truth_NA = factor(truth_NA, levels = c(F, T))
  )

confidence_intervals_real <- confidence_vs_truth_real %>% #rename(confidence = confidence_score) %>% 
  mutate(
    conf_interval = cut(confidence, breaks = seq(0, 1, by = 0.05), include.lowest = TRUE),
    conf_center = as.numeric(sub("\\((.+),(.+)\\]", "\\1", levels(conf_interval))[conf_interval]) + 0.025
  ) %>%
  group_by(conf_center, predicted_NA, model, company) %>%
  summarise(
    n_true = sum(match == TRUE, na.rm = TRUE),
    n_false = sum(match == FALSE, na.rm = TRUE),
    total = n_true + n_false,
    chance_false = if_else(total > 0, n_false / total * 100, NA_real_),
    chance_zero = chance_false == 0,
    chance_below_1 = chance_false < 1,
    chance_low = if_else(chance_zero, 0, if_else(chance_below_1, 1, 2)),
    chance_low = factor(chance_low, levels = c(0,1,2), labels = c("equls 0 %", "below 1 %", "more"))
  ) %>% group_by(predicted_NA, model, company) %>% mutate(
    perc = total/sum(total)*100
  ) %>% ungroup() %>% 
  mutate(
    chance_false_interval = cut(
      chance_false,
      breaks = c(0, 1, 2, 4, 8, 16, 32, 64, Inf),
      labels = c("[0,1)", "[1,2)", "[2,4)", "[4,8)", 
                 "[8,16)", "[16,32)", "[32,64)", "[64,Inf)"),
      right = FALSE,
      ordered_result = TRUE
    ),
  )

confidence_intervals_real %>%
  filter(str_detect(model, "235B")) %>% 
  ggplot() +
  geom_col(aes(
    x = conf_center, y = perc, 
    color = chance_low, 
    fill = chance_false_interval
  ), alpha = 1) +
  # geom_text(
  #   aes(x = conf_center, y = perc, label = round(perc, 0)), 
  #   position = position_stack(vjust = 1), vjust = -0.6, 
  #   size = 3, color = "black"
  # ) +
  scale_color_manual(values = c("equls 0 %" = "#00CC00", "below 1 %" = "orange", "more" = "#555555"), drop = FALSE) +
  scale_fill_manual(values = rev(c("#d53e4f", "#f46d43", "#fdae61", "#fee08b", "#e6f598", "#abdda4", "#66c2a5", "#3288bd")), drop=FALSE) +
  labs(
    x = "Confidence Interval Center", 
    y = "Percentage of predictions", 
    color = "mistake rate") +
  coord_cartesian(
    ylim = c(0, 100), 
    xlim = c(0,1)
  ) +
  facet_nested_wrap(
    vars(company, paste("predicted NA:", predicted_NA)),
    # dir = "v", strip.position = "left"
    )

df_real_table_extraction %>% filter(str_detect(model, "235B")) %>% 
  filter(n_examples == 5, method_family == "top_n_rag_examples") %>% 
  mutate(
    .before = 1, 
    company = map_chr(filepath, ~str_split(str_split(., "/")[[1]][5], "__")[[1]][1]),
    same_company = !out_of_company
    ) %>% 
  group_by(company) %>% 
  ggplot() +
  geom_boxplot(aes(y = company, x = percentage_correct_numeric)) + 
  geom_jitter(
    aes(y = company, x = percentage_correct_numeric, color = same_company), 
    alpha= .7, shape = 4
    ) +
  # scale_x_discrete(guide = guide_axis(angle = 30)) + 
  facet_grid(model_family ~ .)

#### binary classification results per company ####

df_t <- df_binary %>% select(-filepath) %>% 
  # filter(!str_detect(model, "oss")) %>% 
  # filter(n_examples == 3) %>% 
  unnest(predictions) %>%
  # head(10000) %>% 
  rowwise() %>% 
  mutate(
    true_pos = predicted_type != "no" && match,
    true_neg = predicted_type == "no" && match,
    false_pos = predicted_type == "no" && !match,
    false_neg = predicted_type != "no" && !match,
    .before = 1
  )
  
df_t2 <- df_t %>% 
  group_by(company, model_family, method_family, n_examples, classification_type) %>% 
  summarize(
    recall = sum(true_pos)/(sum(true_pos)+sum(false_neg)),
    precision = sum(true_pos)/(sum(true_pos)+sum(false_pos)),
    F1 = 2*recall*precision/(recall+precision)
  )

df_t2 %>% 
  filter(n_examples %in% c(0,1,3)) %>% 
  ggplot() +
  geom_col(
    aes(x = company, y = F1, fill = model_family),
    position = position_dodge2()) + 
  scale_x_discrete(guide = guide_axis(angle = 30)) +
  facet_nested(method_family+n_examples~classification_type)

df_t3 <- df_t %>% 
  group_by(model, method, loop) %>% 
  mutate(
    # match_rate = sum(match)/n(),
    recall2 = sum(true_pos)/(sum(true_pos)+sum(false_neg)),
    precision2 = sum(true_pos)/(sum(true_pos)+sum(false_pos)),
    F1 = 2*recall2*precision2/(recall2+precision2),
    .before = 1
    )

df_t3 %>% group_by(filepath, classification_type, page) %>% 
  slice_max(n = 1, F1, with_ties = FALSE) %>% 
  group_by(company) %>% 
  summarise(
    recall = sum(true_pos),
    precision = sum(true_pos)/(sum(true_pos)+sum(false_pos)),
    F1 = 2*recall*precision/(recall+precision)
  )

df_t3 %>% group_by(filepath, classification_type, page) %>% 
  slice_max(n = 1, F1, with_ties = FALSE) %>% 
  group_by(company, classification_type) %>% 
  summarise(
    recall = sum(true_pos)/(sum(true_pos)+sum(false_neg)),
    precision = sum(true_pos)/(sum(true_pos)+sum(false_pos)),
    F1 = 2*recall*precision/(recall+precision)
  ) %>% 
  pivot_longer(cols = c(precision, recall, F1)) %>% 
  ggplot() +
  geom_col(
    aes(x = company, y = value, fill = classification_type),
    position = position_dodge2()) + 
  scale_x_discrete(guide = guide_axis(angle = 30)) +
  facet_nested(name~.)
