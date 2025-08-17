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


