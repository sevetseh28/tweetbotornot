utils::globalVariables(c("account_created_at", "created_at", "favorite_count",
  "favourites_count", "followers_count", "friends_count", "is_quote",
  "is_retweet", "listed_count", "n", "n_tweets", "retweet_count",
  "statuses_count", "text", "user_id", "verified", "years_on_twitter",
  "description", "location", "name"))

sum_ <- function(x) sum(x, na.rm = TRUE)

max_ <- function(x) max(x, na.rm = TRUE)

mean_ <- function(x) mean(x, na.rm = TRUE)

grepl_ <- function(pat, x) grepl(pat, x)

#' @importFrom rlang .data
extract_features_ytweets <- function(x) {
  ## remove retweet text and counts
  x$text[x$is_retweet] <- NA_character_
  x$retweet_count[x$is_retweet] <- NA_integer_

  ## remove user level duplicates
  x_usr <- dplyr::filter(x, !duplicated(.data$user_id))

  ## tweet features
  txt_df <- textfeatures::textfeatures(x$text)
  names(txt_df) <- paste0("txt_", names(txt_df))

  ## base64 version
  b64_df <- textfeatures::textfeatures(textfeatures:::char_to_b64(x$text))
  names(b64_df) <- paste0("b64_", names(b64_df))

  dsc_df <- textfeatures::textfeatures(x$description)
  names(dsc_df) <- paste0("dsc_", names(dsc_df))

  loc_df <- textfeatures::textfeatures(x$location)
  names(loc_df) <- paste0("loc_", names(loc_df))

  nm_df <- textfeatures::textfeatures(x$name)
  names(nm_df) <- paste0("nm_", names(nm_df))

  x <- x %>%
    dplyr::group_by(user_id) %>%
    dplyr::summarise(
      n_sincelast = count_mean(since_last(.data$created_at)),
      n_timeofday = count_mean(hourofweekday(.data$created_at)),
      n = n(),
      n_retweets = sum_(.data$is_retweet),
      n_quotes = sum_(.data$is_quote),
      retweet_count = mean_(c(0, .data$retweet_count)),
      favorite_count = mean_(c(0, .data$favorite_count)),
      favourites_count = max_(c(0, .data$favourites_count)),
      n_tweets = sum_(!.data$is_retweet & !.data$is_quote),
      iphone = sum_(grepl_("iphone", .data$source)) / .data$n,
      webclient = sum_(grepl_("web client", .data$source)) / .data$n,
      android = sum_(grepl_("android", .data$source)) / .data$n,
      hootsuite = sum_(grepl_("hootsuite", .data$source)) / .data$n,
      lite = sum_(grepl_("twitter lite", .data$source)) / .data$n,
      ipad = sum_(grepl_("for iPad", .data$source)) / .data$n,
      google = sum_(grepl_("google", .data$source)) / .data$n,
      ifttt = sum_(grepl_("IFTTT", .data$source)) / .data$n,
      facebook = sum_(grepl_("facebook", .data$source)) / .data$n,
      verified = as.integer(.data$verified[1]),
      years_on_twitter = as.numeric(
        difftime(Sys.time(), .data$account_created_at[1], units = "days")) / 365,
      tweets_per_year = .data$n_tweets / (1 + .data$years_on_twitter),
      ## i added one here so it wouldn't return NaN or undefined values (0 / x)
      statuses_count = max_(c(0, .data$statuses_count)),
      followers_count = max_(c(0, .data$followers_count)),
      friends_count = max_(c(0, .data$friends_count)),
      listed_count = max_(c(0, .data$listed_count)),
      tweets_to_followers = (.data$statuses_count + 1) /
        (.data$followers_count + 1),
      statuses_rate = (.data$statuses_count + 1) /
        (.data$years_on_twitter + .001),
      ff_ratio = (.data$followers_count + 1) /
        (.data$friends_count + .data$followers_count + 1)
    )
  x <- x[names(x) != "n"]
  x <- cbind(x, txt_df[-1])
  x <- cbind(x, b64_df[-1])
  x <- cbind(x, dsc_df[-1])
  x <- cbind(x, nm_df[-1])
  cbind(x, loc_df[-1])
}

train_model <- function(data, n_trees = 1000) {
  data <- data[!purrr::map_lgl(data,
    ~ all(is.na(.x)) || any(lengths(.x) != 1L))]
  data <- data[purrr::map_lgl(data, ~ is.numeric(.x) | is.integer(.x))]
  data <- data[purrr::map_lgl(data, ~ var(.x) > 0)]
  ## set params and run model (~ . means use all other variables)
  gbm::gbm(bot ~ .,
    data = data,
    n.trees = n_trees,
    interaction.depth = 2,
    cv.folds = 3,
    train.fraction = 1.0,
    verbose = FALSE,
    distribution = "bernoulli",
    shrinkage = .1)
}


## write a function to print out the percent correct (overall; for bots, and
## for non-bots)
percent_correct <- function(data, m, n_trees = 500) {
  best.iter <- gbm::gbm.perf(m, method = "cv", plot.it = FALSE)
  data$pred <- gbm::predict.gbm(m, newdata = data,
    n.trees = best.iter, type = "response")
  x <- table(correct = data$pred > .5, bot = data$bot)
  pc <- round((x[2, 2]) / sum_(x[, 2]), 4)
  pc <- as.character(pc * 100)
  message(sprintf("The model was %s%% accurate when classifying bots.\n", pc))
  pc <- round((x[1, 1]) / sum_(x[, 1]), 4)
  pc <- as.character(pc * 100)
  message(sprintf("The model was %s%% accurate when classifying non-bots.\n",
    pc))
  pc <- round((x[1, 1] + x[2, 2]) / sum_(c(x[, 1], x[, 2])), 3)
  pc <- as.character(pc * 100)
  message(sprintf("Overall, the model was correct %s%% of the time.", pc))
}


#' classify data
#'
#' Generate predicted probabilities of observations being bots.
#'
#' @param x New data on which to apply botornot model.
#' @param model gbm model from which to predict.
#' @return Vector of predictions expressed as probabilities of accounts being
#'   bots.
classify_data <- function(x, model) {
  best.iter <- gbm::gbm.perf(model, method = "cv", plot.it = FALSE)
  gbm::predict.gbm(model, n.trees = best.iter, newdata = x,
    type = "response")
}











extract_features_ntweets <- function(x) {
  ## remove user level duplicates
  x <- dplyr::filter(x, !duplicated(user_id))
  x <- dplyr::group_by(x, user_id)
  description_df <- textfeatures::textfeatures(
    dplyr::select(x, user_id, text = description))
  names(description_df) <- paste0("description_", names(description_df))

  location_df <- textfeatures::textfeatures(
    dplyr::select(x, user_id, text = location))
  names(location_df) <- paste0("location_", names(location_df))

  name_df <- textfeatures::textfeatures(
    dplyr::select(x, user_id, text = name))
  names(name_df) <- paste0("name_", names(name_df))

  x <- dplyr::summarise(x,
    favourites_count = max_(c(0, favourites_count)),
    verified = as.integer(verified[1]),
    years_on_twitter = as.numeric(
      difftime(Sys.time(), account_created_at[1], units = "days")) / 365,
    ## i added one here so it wouldn't return NaN or undefined values (0 / x)
    statuses_count  = max_(c(0, statuses_count)),
    followers_count  = max_(c(0, followers_count)),
    friends_count  = max_(c(0, friends_count)),
    listed_count  = max_(c(0, listed_count)),
    tweets_to_followers  = (statuses_count + 1) / (followers_count + 1),
    statuses_rate  = (statuses_count + 1) / (years_on_twitter + .001),
    ff_ratio = (followers_count + 1) / (friends_count + followers_count + 1)
  )
  dplyr::bind_cols(x, description_df, name_df, location_df)
}

