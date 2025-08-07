`?` <- function(x, y) {
  xs <- as.list(substitute(x))
  if (xs[[1]] == as.name("<-")) x <- eval(xs[[3]])
  r <- eval(sapply(strsplit(deparse(substitute(y)), ":"), function(e) parse(text = e))[[2 - as.logical(x)]])
  if (xs[[1]] == as.name("<-")) {
    xs[[3]] <- r
    eval.parent(as.call(xs))
  } else {
    r
  }
}  

# Estimate direction of effect (sign) SHAP for each feature
plot_shap_importance_signed <- function(shp, n = 10, max_label_length = 30, show_values = TRUE, digits = 3) {
  library(stringr)
  shap_imp <- bind_cols(
    shp$S %>% as_tibble() %>%  mutate(type1 = "importance") %>% 
      pivot_longer(cols = -type1, names_to = "colname1", values_to = "importance"),
    shp$X %>% as_tibble() %>%  mutate(type2 = "value") %>%
      pivot_longer(cols = -type2, names_to = "colname2", values_to = "value")
  ) %>% group_by(colname1) %>% 
    summarise(slope = lm(importance ~ value)$coefficients["value"]) %>% 
    mutate(
      Sign = if_else(slope >= 0, "+", "-")
    ) %>% rename(Variable = colname1) %>% left_join(
      sv_importance(shp, kind = "no") %>% enframe(name = "Variable", value = "Importance")      
    ) %>% arrange(desc(Importance)) %>% head(n) %>%
    mutate(
      Variable_wrapped = str_wrap(str_replace_all(Variable, "_", " "), width = max_label_length)
    )
  
  p <- ggplot(shap_imp, aes(y = reorder(Variable_wrapped, Importance), x = Importance, fill = Sign)) +
    geom_col() +
    scale_fill_manual(values = c("+" = "#009E73", "-" = "#D55E00")) +
    labs(y = "mean(|SHAP value|)", x = "") +
    theme_light()
  
  if (show_values) {
    p <- p + geom_text(aes(label = round(Importance, digits)), 
                       hjust = -0.1, size = 5) 
  }
  
  p
}
