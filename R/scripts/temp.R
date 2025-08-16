confidence_vs_truth <- df_binary %>% 
  filter(model %in% c("Ministral-8B-Instruct-2410", "Qwen3-8B")) %>% 
  group_by(method, model) %>% mutate(
    mean_f1 = mean(f1_score, na.rm=TRUE), .before = 1
  ) %>% group_by(model) %>% 
  arrange(desc(mean_f1)) %>% 
  slice_max(mean_f1, n = 1, with_ties = TRUE) %>% 
  select(-filepath) %>% 
  unnest(predictions) %>% mutate(
    match = factor(match, levels = c(F, T)),
    # truth_NA = factor(truth_NA, levels = c(F, T))
  )

confidence_vs_truth %>% ggplot() +
  geom_boxplot(
    aes(x = match, y = confidence_score, fill = classification_type), 
    position = position_dodge2(preserve = "single")) +
  scale_fill_discrete(drop = FALSE) +
  scale_x_discrete(drop = FALSE) +
  facet_grid(~ model)

confidence_vs_truth %>% rename(confidence = confidence_score) %>% 
  mutate(
    conf_interval = cut(confidence, breaks = seq(0, 1, by = 0.05), include.lowest = TRUE),
    conf_center = as.numeric(sub("\\((.+),(.+)\\]", "\\1", levels(conf_interval))[conf_interval]) + 0.025
  ) %>%
  group_by(conf_center, classification_type, model) %>%
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
  ggplot(aes(x = conf_center, y = chance_false, color = chance_low#, fill = chance_below_1
             )) +
  geom_col(alpha = 0.7) +
  # geom_hline(yintercept = 1, linetype = "dashed") +
  # geom_smooth(method = "lm", se = TRUE) +
  scale_color_manual(values = c("green", "yellow", "red")) +
  labs(x = "Confidence Interval Center", y = "Chance False (%)", color = "mistake rate") +
  coord_cartesian(
    # ylim = c(0, 100), 
    xlim = c(0,1)
    ) +
  facet_grid(classification_type ~ model)
