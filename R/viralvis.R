#' Competing models plot
#'
#' Plots the rankings of a series of regression models for viral load or CD4 
#' counts
#'
#' @param traindata A data frame
#' @param semilla A numeric value
#' @param target A character value
#' @param viralvars Vector of variable names related to viral data.
#' @param logbase The base for logarithmic transformations.
#' @param pliegues A numeric value
#' @param repeticiones A numeric value
#' @param rejilla A numeric value 
#'
#' @return A plot of ranking models
#' @export
#'
#' @examples
#' \donttest{
#' library(tidyverse)
#' library(baguette)
#' library(kernlab)
#' library(kknn)
#' library(ranger)
#' library(rules)
#' library(glmnet)
#' # Define the function to impute values in the undetectable range
#' set.seed(123)
#' impute_undetectable <- function(column) {
#' ifelse(column <= 40,
#'       rexp(sum(column <= 40), rate = 1/13) + 1,
#'             column)
#'             }
#' # Apply the function to all vl columns using purrr's map_dfc
#' library(viraldomain)
#' data("viral", package = "viraldomain")
#' viral_imputed <- viral %>%
#' mutate(across(starts_with("vl"), ~impute_undetectable(.x)))
#' traindata <- viral_imputed
#' semilla <- 1501
#' target <- "cd_2022"
#' viralvars <- c("vl_2019", "vl_2021", "vl_2022")
#' logbase <- 10
#' pliegues <- 2
#' repeticiones <- 1
#' rejilla <- 1
#' set.seed(123)
#' viralvis(traindata, semilla, target, viralvars, logbase, pliegues, repeticiones, rejilla)
#' }
viralvis <- function(traindata, semilla, target, viralvars, logbase, pliegues, repeticiones, rejilla) {
  dplyr::bind_rows(
    workflowsets::workflow_set(
      preproc = list(simple = workflows::workflow_variables(outcomes = tidyselect::all_of(target), predictors = tidyselect::everything())),
      models = list(rf = parsnip::rand_forest(mtry = hardhat::tune(), min_n = hardhat::tune(), trees = hardhat::tune()) %>%
                      parsnip::set_engine("ranger") %>%
                      parsnip::set_mode("regression"),
                    CART_bagged = parsnip::bag_tree() %>%
                      parsnip::set_engine("rpart", times = 50L) %>%
                      parsnip::set_mode("regression"),
                    Cubist = parsnip::cubist_rules(committees = hardhat::tune(), neighbors = hardhat::tune()) %>%
                      parsnip::set_engine("Cubist")
      )
    ),
    workflowsets::workflow_set(
      preproc = list(normalized = recipes::recipe(stats::as.formula(paste(target, "~ .")), data = traindata) %>%
                       recipes::step_log(tidyselect::all_of(viralvars), base = logbase) %>%
                       recipes::step_normalize(recipes::all_predictors())),
      models = list(SVM_radial = parsnip::svm_rbf(cost = hardhat::tune(), rbf_sigma = hardhat::tune()) %>%
                      parsnip::set_engine("kernlab") %>%
                      parsnip::set_mode("regression"),
                    SVM_poly = parsnip::svm_poly(cost = hardhat::tune(), degree = hardhat::tune()) %>%
                      parsnip::set_engine("kernlab") %>%
                      parsnip::set_mode("regression"),
                    KNN = parsnip::nearest_neighbor(neighbors = hardhat::tune(), dist_power = hardhat::tune(), weight_func = hardhat::tune()) %>%
                      parsnip::set_engine("kknn") %>%
                      parsnip::set_mode("regression"),
                    neural_network = parsnip::mlp(hidden_units = hardhat::tune(), penalty = hardhat::tune(), epochs = hardhat::tune()) %>%
                      parsnip::set_engine("nnet", MaxNWts = 2600) %>%
                      parsnip::set_mode("regression")
      )
    ) %>%
      workflowsets::option_add(param_info = parsnip::mlp(hidden_units = hardhat::tune(), penalty = hardhat::tune(), epochs = hardhat::tune()) %>%
                                 parsnip::set_engine("nnet", MaxNWts = 2600) %>%
                                 parsnip::set_mode("regression") %>%
                                 tune::extract_parameter_set_dials() %>%
                                 recipes::update(hidden_units = dials::hidden_units(c(1, 27))),
                               id = "normalized_neural_network"),
    workflowsets::workflow_set(
      preproc = list(full_quad = recipes::recipe(stats::as.formula(paste(target, "~ .")), data = traindata) %>%
                       recipes::step_log(tidyselect::all_of(viralvars), base = logbase) %>%
                       recipes::step_normalize(recipes::all_predictors())  %>%
                       recipes::step_poly(recipes::all_predictors()) %>%
                       recipes::step_interact(~ recipes::all_predictors():recipes::all_predictors())
      ),
      models = list(linear_reg = parsnip::linear_reg(penalty = hardhat::tune(), mixture = hardhat::tune()) %>%
                      parsnip::set_engine("glmnet"),
                    KNN = parsnip::nearest_neighbor(neighbors = hardhat::tune(), dist_power = hardhat::tune(), weight_func = hardhat::tune()) %>%
                      parsnip::set_engine("kknn") %>%
                      parsnip::set_mode("regression")
      )
    )
  ) %>%
    workflowsets::workflow_map(
      seed = semilla,
      resamples = rsample::vfold_cv(traindata, v = pliegues, repeats = repeticiones),
      grid = rejilla,
      control = tune::control_grid(
        save_pred = TRUE,
        parallel_over = "everything",
        save_workflow = TRUE
      )
    ) %>%
    tune::autoplot(
      rank_metric = "rmse",  # <- how to order models
      metric = "rmse",       # <- which metric to visualize
      select_best = TRUE     # <- one point per workflow
    )
}