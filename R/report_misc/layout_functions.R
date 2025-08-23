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
    
    df <- df %>% mutate(across(where(is.character), ~str_replace_all(., "_", "_<wbr>"))) %>% 
      setNames(str_replace_all(colnames(.), "_", " "))
    
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

create_hypotheses_table <- function(html_path, caption, detect="\\*$") {
  pd <- import("pandas")
  df_two_header_lines <- pd$read_html(html_path, header = 1L)[[1]]

  library(xml2)
  library(rvest)
  library(dplyr)
  library(purrr)
  library(tibble)
  
  html_table <- xml2::read_html(html_path) %>%
    xml2::xml_find_first("//table")
  
  # Get all rows
  rows <- xml_find_all(html_table, ".//tr")
  
  # Skip first two rows (header)
  data_rows <- rows[-c(1,2)]
  
  # Helper to extract info from a cell
  extract_cell_info <- function(cell) {
    # Check for bold (either <b> or <strong> or style)
    is_bold <- length(xml_find_all(cell, ".//b | .//strong")) > 0 ||
      grepl("font-weight:\\s*bold", xml_attr(cell, "style") %||% "", ignore.case = TRUE)
    # Get text color from style attribute
    style <- xml_attr(cell, "style") %||% ""
    color <- NA_character_
    # Try to get color from <font> tag first
    font_tag <- xml_find_first(cell, ".//font[@color]")
    if (!is.na(font_tag) && length(font_tag) > 0) {
      color <- xml_attr(font_tag, "color")
    } else if (grepl("color:", style)) {
      color <- sub(".*color:\\s*([^;]+);?.*", "\\1", style)
    }
    color <- trimws(color)
    # Get text content
    text <- xml_text(cell, trim = TRUE)
    tibble(text = text, bold = is_bold, color = color)
  }
  
  # Build matrix/list of cell info
  cell_info_list <- map(data_rows, function(row) {
    cells <- xml_find_all(row, ".//td|.//th")
    map_dfr(cells, extract_cell_info)
  })
  
  # Find which cells are bold (excluding the first column)
  bold_matrix <- sapply(cell_info_list, function(row) row$bold) %>% t()
  # Set first column to FALSE (never bold)
  if (is.matrix(bold_matrix)) {
    bold_matrix[, 1] <- FALSE
  } else {
    # If only one row, ensure it's a matrix
    bold_matrix[1] <- FALSE
  }
  df_bold <- bold_matrix %>% as.data.frame()
  
  df_red <- sapply(cell_info_list, function(row) row$color) %>% t() %>% 
    as.data.frame()
  
  n_cols <- ncol(df_two_header_lines)
  df_to_display <- df_two_header_lines
  df_to_display <- pmap(
    list(df_to_display, df_bold, df_red), 
    function(text, bold, color) {
      if_else(
        !is.na(color), 
        cell_spec(if_else(is.na(text), "", text), bold = bold, color = "darkred"),
        cell_spec(if_else(is.na(text), "", text), bold = bold)
      )}) %>% 
    as_tibble() %>% setNames(colnames(.) %>% str_remove(".\\d"))
  
  # browser()
  
  header_span <- if_else(n_cols == 7, list(c(
    " " = 1, "F1" = 2, "% correct numeric" = 2, 
    "binomial" = 2
  )), list(c(
    " " = 1, "F1" = 2, "% correct numeric" = 2, 
    "binomial" = 2, "confidence" = 2
  )))
  
  df_to_display <- df_to_display %>% 
    kbl(escape = F, booktabs = T, caption = caption) %>%
    kable_paper() %>%
    add_header_above(header_span[[1]]) %>%
    column_spec(1, border_right=T) %>%
    column_spec(3, border_right=T) %>%
    column_spec(5, border_right=T) %>%
    row_spec(
      which(str_detect(df_two_header_lines[[1]], detect)),
      color = "gray"
    )  
  
  if (n_cols == 9) {
    df_to_display <- df_to_display %>% 
      column_spec(7, border_right=T)
  }
  
  df_to_display
}

