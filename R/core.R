#' The engine to collect the Dota2 data.
#'

collect <- function(type = "collect_id") {
    m <- mongolite::mongo("config", "dota")
    config_info <- m$find('{"_id": "config"}')
    m$disconnect()

    key <- config_info$keyapi[[1]]
    game_mode <- config_info$game_mode[[1]]
    lobby_type <- config_info$lobby_type[[1]]
    skill <- config_info$skill[[1]]
    public_account_id <- config_info$public_account_id[[1]]
    duration <- config_info$duration[[1]]
    n_history_matches <- config_info$n_history_matches[[1]]

    if (type == "collect_id") {
        # script <- "/home/andryas/Documentos/github/RDota2Plus/inst/scripts/collect_id.R"
        script <- system.file(package = "RDota2Plus", "scripts", "collect_id.R")
        p <- processx::process$new(script, c(key[1], lobby_type, skill))

        ## Eval if the process is running in background
        while (TRUE) {
            if (!p$is_alive()) {
                p <- processx::process$new(script, c(key[1], lobby_type, skill))
            }
            Sys.sleep(900)
        }
    } else if (type == "collect_match_details") {
        m <- mongolite::mongo(paste0("match_id_", skill), "dota")
        query <- paste0('{"_id": { "$lt": ', as.integer(Sys.Date()), '}}')
        fields <- '{"_id": 1, "match_id": 1}'
        df <- dplyr::as_tibble(m$find(query, fields ,'{"_id": -1}', limit = 7))
        m$disconnect()
        
        if (nrow(df) == 0) stop("No matches to collect")

        document <- df[1, ]$`_id`[[1]]
        match_id <- df[1, ]$match_id[[1]]
        script <- system.file(package = "RDota2Plus", "scripts", "collect_match_details.R")
        # script <- "/home/andryas/Documentos/github/RDota2Plus/inst/scripts/collect_match_details.R"
        # m$remove(paste0('{"_id": ', document, '}'), just_one = TRUE)
        
        key <- key[-1] ## One key serves to collect match_id
        match_id <- match_id[1:((length(match_id) %/% (length(key))) * (length(key)))]
        if (length(match_id) == 0) stop("No matches to collect")

        match_id <- split(match_id, ceiling(1:length(match_id)/(length(match_id)/length(key))))
        
        lconfig <- list(game_mode = game_mode, lobby_type = lobby_type,
                        public_account_id = public_account_id, skill = skill,
                        duration = duration)
        
        lmatch_id <- lapply(match_id, function(x) list(match_id = x))
        lmatch_id <- lapply(lmatch_id, function(x) append(x, lconfig))
        lmatch_id <- lapply(lmatch_id, function(x) list("$set" = x))

        m <- mongolite::mongo("collect_match_id", "dota")

        ## Register match_id to collect
        for (i in 1:length(key)) {
            lmatch_id_json <- jsonlite::toJSON(lmatch_id[[i]], auto_unbox = TRUE)
            m$update(paste0('{"_id": "', key[i], '"}'), lmatch_id_json, upser = TRUE)
        }
        
        ## Start process
        for (j in 1:length(key)) {
            assign(paste0("p", j), processx::process$new(script, c(key[j], document)))
        }

        while (TRUE) {
            for (w in 1:length(key)) {
                n <- m$find(paste0('{"_id": "', key[w], '"}'))$match_id[[1]]

                if (length(n) == 0) {
                    key <- key[-w]
                    next
                } 

                condition <- eval(parse(text = paste0("p", w, "$is_alive()")))
                
                if (!isTRUE(condition)) {
                    assign(paste0("p", w), processx::process$new(script, c(key[w], document)))
                } 
            }
            
            if (length(key) == 0) break

            Sys.sleep(5)
            
        }
        
        m$disconnect()
        
    } else if (type == "collect_players_details") {
        key <- key[-1]

        if (n_history_matches == 0) stop("Done")
        
        m <- mongolite::mongo("match", "dota")
        if (!any(grepl("start_time_-1", m$index()$name))) {
            ## Index the field start_time
            m$index(add = '{"start_time": -1}')
        }
        df <- dplyr::as_tibble(m$find('{"_pi": 0}', sort = '{"start_time": -1}',
                                      limit = 20))
        m$disconnect()

        df$players <- lapply(df$players, function(x) {
            x <- dplyr::select(x, account_id, hero_id)
            dplyr::as_tibble(x)
        })

        df <- split(df, ceiling(1:nrow(df)/(nrow(df)/length(key))))
        df <- lapply(df, function(x) tidyr::unnest(x, players))
        df <- lapply(df, function(x) dplyr::filter(x, account_id != 4294967295))
        df <- lapply(df, function(x) dplyr::select(x, match_id, start_time, hero_id, account_id))

        lconfig <- list(game_mode = game_mode, lobby_type = lobby_type,
                        public_account_id = public_account_id, skill = skill,
                        duration = duration, n_history_matches = n_history_matches)
        
        lp <- lapply(df, function(x) list(account_id = x))
        lp <- lapply(lp, function(x) append(x, lconfig))
        lp <- lapply(lp, function(x) list("$set" = x))
        
        m <- mongolite::mongo("collect_account_id", "dota")
        
        ## Register match_id to collect
        for (i in 1:length(key)) {
            lp_json <- jsonlite::toJSON(lp[[i]], auto_unbox = TRUE)
            m$update(paste0('{"_id": "', key[i], '"}'), lp_json, upser = TRUE)
        }

        script <- system.file(package = "RDota2Plus", "scripts", "collect_players_details.R")
        # script <- "/home/andryas/Documentos/github/RDota2Plus/inst/scripts/collect_players_details.R"
        
        ## Start process
        for (j in 1:length(key)) {
            assign(paste0("p", j), processx::process$new(script, key[j]))
        }

        while (TRUE) {
            for (w in 1:length(key)) {
                n <- m$find(paste0('{"_id": "', key[w], '"}'))$account_id[[1]]

                if (length(n) == 0) {
                    key <- key[-w]
                    next
                } 

                condition <- eval(parse(text = paste0("p", w, "$is_alive()")))
                
                if (!isTRUE(condition)) {
                    assign(paste0("p", w), processx::process$new(script, key[w]))
                } 
            }
            
            if (length(key) == 0) break

            Sys.sleep(5)
            
        }
        
        m$disconnect()
        
    } else {
        stop("type must be one of the follows args: 'collect_id'
             'collect_match_details' 'collect_players_details'")
    }
}