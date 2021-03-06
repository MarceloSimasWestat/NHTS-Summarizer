#==================================================================================================#
#' @export

use_labels <- function(tbl, dataset, keep = NULL, drop = NULL) {
  
  values <- CB(dataset)$values

  if(!is.null(keep)) {
    
    vars <- colnames(tbl)[colnames(tbl) %in% keep]
    if(!is.null(drop)) warning('Ignoring "drop" paramater, because "keep" was specified.')
    
  } else if(!is.null(drop)) {
    
    vars <- colnames(tbl)[!colnames(tbl) %in% drop]
    
  } else vars <- colnames(tbl)
  
  varlabs <- values[ NAME %in% vars & !grepl('[0-9 ,]+-[0-9 ,]+',VALUE), ]
  varlabs <- varlabs[!(VALUE == '' | LABEL == ''), LABEL := gsub("'","",LABEL)]
  s <- split(varlabs, varlabs$NAME)
  
  #message('Overwriting values with labels in table ', dQuote(deparse(substitute(tbl))) ,' for variable: ')
  for(i in names(s)) {
    v <- s[[i]]
    var_class <- class(tbl[[i]])
    class(v$VALUE) <- var_class
    
    merged <- merge(tbl, v, by.x = i, by.y = 'VALUE', all.x = T, sort = F)
    
    tbl[[i]] <- merged[,ifelse(NAME != i | is.na(NAME), get(i), LABEL)]
    tbl[, (i) := factor(get(i), levels = unique(c(v$LABEL, tbl[[i]])))]
  }
  
  return(tbl)
  
}

#==================================================================================================#
#' @export
#crosstab_output
crosstab_output <- function(tbl = NULL, ...) {
  
  default_output <- list(W = 'Weighted', E = 'Error', S = 'Surveyed', N = 'N')
  default_names <- names(default_output)
  
  custom_output <- list(...)
  custom_names <- names(custom_output)
  
  if (!'E' %in% custom_names & !is.null(tbl)) {
    error_output <- attr(tbl, 'error')
    custom_output$E <- error_output
  }
  
  default_output[names(custom_output)] <- custom_output
  default_output <- default_output[default_names]
  return(unlist(default_output))
}
#==================================================================================================#
#' @export
#get_trip_weights
get_trip_weights <- function(data, dataset) {
  person_weights <- copy(data$weights$person)
  person_weight_names <- WT('person', dataset)
  trip_weight_names <- WT('trip', dataset)
  person_weights[, (person_weight_names) := lapply(.SD, function(x) x * getOption('HTS.annualized.days')), .SDcols = person_weight_names]
  setnames(person_weights, person_weight_names, trip_weight_names)
  setkeyv(person_weights, c(ID('household'), ID('person')))
  trip_weights <- merge(copy(data$weights$trip_keys), person_weights)
  setkeyv(trip_weights, c(ID('household'), ID('person'), ID('trip')))
  return(trip_weights)
}

#==================================================================================================#
#' @export
#select_all
select_all <- function(dataset) {
  variables <- CB(dataset)$variables
  all_variables <- variables$NAME
  ids <- sapply(c('household','person','vehicle','trip'), ID)
  wgts <- sapply(c('household','person','trip'), function(x) WT(x, dataset)[1])
  # Other exclusions specific to NHTS but should not clash with other projects
  other_exclusions <- c('WTHHFIN','WTPERFIN','WTTRDFIN','PLACENO','PLACEID')
  missing_2001_vars <- c('MILDRIVA', 'MINDRIVA', 'MINDRIVE', 'MININVEA', 'MININVEH', 'MINTRVL', 'MINTRVLA')
  exclude <- c(ids, wgts, other_exclusions, missing_2001_vars)
  return(all_variables[!all_variables %in% exclude])
}
#==================================================================================================#
#' @export
#trim_input_data
trim_input_data <- function(data, variables, agg_var, factors, subset) {
  # Scan subset string for variable names
  subset_vars <- names(which(sapply(variables$NAME, grepl, x = subset)))
  vars <- c(factors, agg_var, subset_vars)
  
  # Get variables by table name
  household_vars <- variables[NAME %in% vars & TABLE == 'household', NAME]
  person_vars <- variables[NAME %in% vars & TABLE == 'person', NAME]
  trip_vars <- variables[NAME %in% vars & TABLE == 'trip', NAME]
  vehicle_vars <- variables[NAME %in% vars & TABLE == 'vehicle', NAME]
  
  # Append appropritate table ids
  household_vars <- c(get_table_keys('household'), household_vars)
  person_vars <- c(get_table_keys('person'), person_vars)
  trip_vars <- c(get_table_keys('trip'), trip_vars)
  vehicle_vars <- c(get_table_keys('vehicle'), vehicle_vars)
  
  # Subset variable selecting by relevant columns
  data <- data$clone()
  data$data$household <- data$data$household[, ..household_vars]
  data$data$person <- data$data$person[, ..person_vars]
  data$data$trip <- data$data$trip[, ..trip_vars]
  data$data$vehicle <- data$data$vehicle[, ..vehicle_vars]
  return(data)
}
#==================================================================================================#
#' @export
#exclude_missing_values
exclude_missing_values <- function(subset, vars) {
  exclude_missing <- sprintf("(!%s %%in%% c('-9','-88','-8','-7','-77','-1'))", vars)
  if(length(exclude_missing) > 0) {
    exclude_missing <- paste0(exclude_missing, collapse = ' & ')
    exclude_missing <- paste(exclude_missing, paste0('(', subset, ')'), sep = ' & ')
  } else {
    exclude_missing <- subset
  }
  return(exclude_missing)
}
#==================================================================================================#
#' @export
#get_table_keys
get_table_keys <- function(level) {
  switch(
    EXPR = level,
    household = ID('household'),
    person = c(ID('household'), ID('person')),
    trip = c(ID('household'), ID('person'), ID('trip'), ID('vehicle')),
    vehicle = c(ID('household'), ID('vehicle'))
  )
}
#==================================================================================================#
#' @export
# use_moe
use_moe <- function(tbl, confidence = 0.95) {
  
  dataset <- attr(tbl, 'dataset')
  
  df <- switch(dataset,
    '2001' = 99,
    '2009' = 100,
    '2017' = 98
  )
  
  if (!is.null(confidence)) {
    
    if (confidence <= 0 | confidence >= 1) {
      stop('Confidence level must be between 0 and 1.')
    }
    
    standard_score <- qt((confidence / 2) + 0.5, df = df)
    out_tbl <- copy(tbl)
    out_tbl[, E := E * standard_score]
    setattr(out_tbl, 'error', sprintf('MOE (%s%%)', 100 * confidence))
    return(out_tbl[])
  } else {
    # Show standard error
    return(tbl[])
  }
  
}
#==================================================================================================#
#' @export
# trim_labels
trim_label <- function(x, wrap_width, trunc_width) {
  wrap_width <- ifelse(is.null(wrap_width), 35, wrap_width)
  trunc_width <- ifelse(is.null(trunc_width), 100, trunc_width)
  regex_pattern <- sprintf('([[:print:]]{%s}[[:alnum:]]+).*', trunc_width)
  x <- sub(regex_pattern, "\\1...", x)
  x <- paste(strwrap(x, width = wrap_width), collapse = "\n")
  return(x)
}