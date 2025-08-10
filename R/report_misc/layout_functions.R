render_table <- function(df, alignment = NULL, caption = NULL, ref = NULL, dom = "tiprfl") {
  # Replace **x** with <b>x</b> for HTML and \textbf{x} for LaTeX
  df <- df %>% bold_value_in_table()
  
  # Helper to convert knitr alignment to DT alignment
  get_dt_align <- function(align) {
    sapply(strsplit(paste0("l", align), "")[[1]], function(x) {
      switch(x, l = 'left', c = 'center', r = 'right', 'left')
    })
  }
  
  if (!knitr::is_html_output()) {
    latex_sub <- "([%&_#{}-])"
    
    # Escape special characters in the caption for LaTeX
    if (!is.null(caption) && knitr::is_latex_output()) {
      caption <- gsub(latex_sub, "\\\\\\1", caption) # Escape LaTeX special characters
    }
  
    df <- df %>%
      mutate(across(everything(), ~gsub(latex_sub, "\\\\\\1", .))) %>%
      setNames(gsub(latex_sub, "\\\\\\1", colnames(.))
    ) # Escape LaTeX special characters in column names
  }

  if (knitr::is_html_output()) {
    # Set caption
    if (!is.null(caption) & !is.null(ref)) {
      cat("<table>",paste0("<caption>", "(#tab:", ref, ")", caption, "</caption>"),"</table>", sep ="\n")
    }
    
    # Set column alignment for DT
    if (!is.null(alignment)) {
      dt_align <- get_dt_align(alignment)
      col_defs <- lapply(seq_along(dt_align), function(i) {
        list(targets = i - 1, className = paste0('dt-', dt_align[i]))
      })
      datatable(df, escape = FALSE, options = list(pageLength = 10, columnDefs = col_defs, scrollX = TRUE, dom = dom))
    } else {
      datatable(df, escape = FALSE, options = list(pageLength = 10, scrollX = TRUE, dom = dom))
    }
  } else if (knitr::is_latex_output()) {
    kbl(
      df, escape = FALSE, format = "latex", align = alignment, caption = caption
      ) %>%
      kable_styling()
  } else {
    knitr::kable(
      df, align = alignment#, caption = caption
      )
  }
}

bold_value_in_table <- function(df) {
  # Replace **x** with <b>x</b> for HTML and \textbf{x} for LaTeX
  df <- df %>%
    mutate_all(~ if (knitr::is_html_output()) {
      gsub("\\*\\*(.*?)\\*\\*", "<b>\\1</b>", .)
    } else if (knitr::is_latex_output()) {
      gsub("\\*\\*(.*?)\\*\\*", "\\\\textbf{\\1}", .)
    } else {
      .
    })
}