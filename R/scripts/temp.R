library(MLmetrics)

df_temp <- df_temp_qwen$df %>% filter(target == "Aktiva") %>% mutate(type = if_else(type == "Aktiva", type, "no"))

pr <- pr.curve(df_temp$confidence_score, curve = TRUE)
plot(pr);

F1_Score(df_temp$type, df_temp$predicted_type, positive = NULL)

df_binary %>% filter(model == "Qwen_Qwen2.5-1.5B-Instruct", method == "1_rag_examples", classification_type == "Aktiva") %>% .$f1_score


# create artificial scores as random numbers
x <- rnorm( 1000 );
y <- rnorm( 1000, -1 );
# compute area under PR curve for the hard-labeled case
pr <- pr.curve( x, y );
print( pr );

# compute PR curve and area under curve
pr <- pr.curve( x, y, curve = TRUE );
# plot curve
plot(pr);

library(yardstick)

data(two_class_example)

pr_curve(two_class_example, truth, Class1)

library(ggplot2)
library(dplyr)
pr_curve(two_class_example, truth, Class1) %>%
  ggplot(aes(x = recall, y = precision)) +
  geom_path() +
  coord_equal() +
  theme_bw()

df_temp <- df_temp_mistral$df %>% filter(target == "Passiva") %>% mutate(type = if_else(type == "Aktiva", type, "no"))

library(ggplot2)
library(dplyr)
df_temp %>% mutate(type = factor(type)) %>% 
pr_curve(type, confidence_score) %>%
  ggplot(aes(x = recall, y = precision)) +
  geom_path() +
  coord_equal() +
  theme_bw()

df_temp %>% mutate(type = factor(type)) %>% 
  pr_auc(type, confidence_score) %>% .$.estimate

######


library(yardstick)

calc_micro_f1 <- function(df, model_name, method_name) {
  l_temp <- list()
  # browser()
  
  for (target in c('Aktiva', 'GuV', 'Passiva')) {
    # t <- "Aktiva"
    # df_filtered <- df %>% filter(
    #   classification_type == t,
    #   n_examples <= 3,
    #   loop == 0) %>% 
    #   arrange(desc(f1_score))
    # model_name_best_f1_aktiva <- df_filtered[model_rank, "model"]
    # method_best_f1_aktiva <- df_filtered[model_rank, "method"]
    
    df_filtered <- df %>%
      filter(
        classification_type == target,
        model == model_name,
        method == method_name,
        loop == 0
      ) %>% 
      arrange(desc(f1_score))
    
    df_temp <- df_filtered[1,"predictions"][[1]][[1]] %>% as_tibble()
    
    df_flipped_score <- df_temp %>% 
      mutate(
        confidence_score = if_else(predicted_type == "no", 1-confidence_score, confidence_score),
        target = target
      )
    l_temp[target] <- list(df_flipped_score)
  }
  
  list(df = bind_rows(l_temp), model = model_name, method = method_name)
}

hpc_cv

plot_pr_double_curve <- function(l, selected_type, x_stuff = FALSE) {
  # browser()
  df_temp2 <- l$df %>% filter(target == selected_type) %>% 
    mutate(type = if_else(type == selected_type, type, "no")) %>% 
    mutate(type = factor(type))
  # pr_obj <- pr.curve(scores.class0 = df_temp2$confidence_score[df_temp2$match == 1],
  #                    scores.class1 = df_temp2$confidence_score[df_temp2$match == 0],
  #                    curve = TRUE)
  
  # Precision-Recall Curve with ggplot2
  
  pr_df <- df_temp2 %>% pr_curve(type, confidence_score) %>%
    rename(threshold = .threshold) %>% 
    mutate(f1 = 2 * precision * recall / (precision + recall))
  
  pr_auc <- round(df_temp2 %>% pr_auc(type, confidence_score) %>% .$.estimate, 3)
  best_F1_row <- pr_df %>% slice_max(n = 1, f1)  
  best_F1 <- best_F1_row  %>% pull(f1)
  best_threshold <- best_F1_row  %>% pull(threshold)
  
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
  
  g1 + g2 + plot_annotation(caption = paste0('Best F1 score ', round(best_F1,3) , ' gets reached with threshold of value ', round(best_threshold,3)))
}
