#' Adds a new scale to a plot
#'
#' Creates a new scale "slot". Geoms added to a plot after this function will
#' use a new scale definition.
#'
#' @param new_aes A string with the name of the aesthetic for which a new scale
#' will be created.
#'
#' @details
#' `new_scale_color()`, `new_scale_colour()` and `new_scale_fill()` are just
#' aliases to `new_scale("color")`, etc...
#'
#' @examples
#' library(ggplot2)
#'
#' # Equivalent to melt(volcano), but we don't want to depend on reshape2
#' topography <- expand.grid(x = 1:nrow(volcano),
#'                           y = 1:ncol(volcano))
#' topography$z <- c(volcano)
#'
#' # point measurements of something at a few locations
#' measurements <- data.frame(x = runif(30, 1, 80),
#'                            y = runif(30, 1, 60),
#'                            thing = rnorm(30))
#'
#' ggplot(mapping = aes(x, y)) +
#'   geom_contour(data = topography, aes(z = z, color = stat(level))) +
#'   # Color scale for topography
#'   scale_color_viridis_c(option = "D") +
#'   # geoms below will use another color scale
#'   new_scale_color() +
#'   geom_point(data = measurements, size = 3, aes(color = thing)) +
#'   # Color scale applied to geoms added after new_scale_color()
#'   scale_color_viridis_c(option = "A")
#'
#' @export
new_scale <- function(new_aes) {
  structure(ggplot2::standardise_aes_names(new_aes), class = "new_aes")
}

#' @export
#' @rdname new_scale
new_scale_fill <- function() {
  new_scale("fill")
}

#' @export
#' @rdname new_scale
new_scale_color <- function() {
  new_scale("colour")
}

#' @export
#' @rdname new_scale
new_scale_colour <- function() {
  new_scale("colour")
}

#' @export
#' @importFrom ggplot2 ggplot_add
ggplot_add.new_aes <- function(object, plot, object_name) {
  # To add default scales (I need to build the whole plot because they might be computed aesthetics)
  if (is.null(plot$scales$get_scales(object))) {
    plot$scales <- ggplot2::ggplot_build(plot)$plot$scales
  }
  # Global aes
  old_aes <- names(plot$mapping)[remove_new(names(plot$mapping)) %in% object]
  new_aes <- paste0(old_aes, "_new")
  names(plot$mapping)[names(plot$mapping) == old_aes] <- new_aes

  plot$layers <- bump_aes_layers(plot$layers, new_aes = object)
  plot$scales$scales <- bump_aes_scales(plot$scales$scales, new_aes = object)
  plot$labels <- bump_aes_labels(plot$labels, new_aes = object)
  plot$guides <- bump_aes_guides(plot$guides, new_aes = object)

  plot
}


bump_aes_guides <- function(guides, new_aes) {
  original_aes <- new_aes

  if (inherits(guides, "Guides")) {
    to_change <- remove_new(names(guides$guides)) == original_aes

    if (any(to_change)) {
      names(guides$guides)[to_change] <- paste0(names(guides$guides), "_new")
    }
  } else {
    to_change <- remove_new(names(guides)) == original_aes

    if (any(to_change)) {
      names(guides)[to_change] <- paste0(names(guides), "_new")
    }
  }

  return(guides)
}

bump_aes_layers <- function(layers, new_aes) {
  lapply(layers, bump_aes_layer, new_aes = new_aes)

}

bump_aes_layer <- function(layer, new_aes) {
  original_aes <- new_aes

  new_layer <- ggplot2::ggproto(NULL, layer)

  # Get explicit mapping
  old_aes <- names(new_layer$mapping)[remove_new(names(new_layer$mapping)) %in% new_aes]

  # If not explicit, get the default
  if (length(old_aes) == 0) {
    old_aes <- names(new_layer$stat$default_aes)[remove_new(names(new_layer$stat$default_aes)) %in% new_aes]
    if (length(old_aes) == 0) {
      old_aes <- names(new_layer$geom$default_aes)[remove_new(names(new_layer$geom$default_aes)) %in% new_aes]
    }
  }
  # Return unchanged layer if it doens't use this aes
  if (length(old_aes) == 0) {
    return(new_layer)
  }

  new_aes <- paste0(old_aes, "_new")

  old_geom <- new_layer$geom

  old_handle_na <- old_geom$handle_na
  new_handle_na <- function(self, data, params) {
    colnames(data)[colnames(data) %in% new_aes] <- original_aes
    old_handle_na(data, params)
  }

  new_geom <- ggplot2::ggproto(paste0("New", class(old_geom)[1]), old_geom,
                               handle_na = new_handle_na)

  new_geom$default_aes <- change_name(new_geom$default_aes, old_aes, new_aes)
  new_geom$non_missing_aes <- change_name(new_geom$non_missing_aes, old_aes, new_aes)
  new_geom$required_aes <- change_name(new_geom$required_aes, old_aes, new_aes)
  new_geom$optional_aes <- change_name(new_geom$optional_aes, old_aes, new_aes)

  draw_key <- new_geom$draw_key
  new_draw_key <- function(data, params, size) {
    colnames(data)[colnames(data) == new_aes] <- original_aes
    draw_key(data, params, size)
  }
  new_geom$draw_key <- new_draw_key

  new_layer$geom <- new_geom

  old_stat <- new_layer$stat

  new_handle_na <- function(self, data, params) {
    colnames(data)[colnames(data) %in% new_aes] <- original_aes
    ggplot2::ggproto_parent(self$super(), self)$handle_na(data, params)
  }

  new_setup_data <- function(self, data, scales, ...) {
    # After setup data, I need to go back to the new aes names, otherwise
    # scales are not applied.
    colnames(data)[colnames(data) %in% new_aes] <- original_aes
    data <- ggplot2::ggproto_parent(self$super(), self)$setup_data(data, scales, ...)
    colnames(data)[colnames(data) %in% original_aes] <- new_aes
    data
  }

  if (!is.null(old_stat$is_new)) {
    parent <- old_stat$super()
  } else {
    parent <- ggplot2::ggproto(NULL, old_stat)
  }

  new_stat <- ggplot2::ggproto(paste0("New", class(old_stat)[1]), parent,
                               setup_data = new_setup_data,
                               handle_na = new_handle_na,
                               is_new = TRUE)

  new_stat$default_aes <- change_name(new_stat$default_aes, old_aes, new_aes)
  new_stat$non_missing_aes <- change_name(new_stat$non_missing_aes, old_aes, new_aes)
  new_stat$required_aes <- change_name(new_stat$required_aes, old_aes, new_aes)
  new_stat$optional_aes <- change_name(new_stat$optional_aes, old_aes, new_aes)

  new_layer$stat <- new_stat

  # Make implicit mapping explicit.
  # This fixes https://github.com/eliocamp/ggnewscale/issues/45 but it feels
  # wrong. I don't understand why implicit mapping breaks when adding more than
  # one extra scale.
  if (is.null(new_layer$mapping[[old_aes]])) {
    new_layer$mapping[[old_aes]] <- new_stat$default_aes[[new_aes]]
  }
  new_layer$mapping <- change_name(new_layer$mapping, old_aes, new_aes)
  new_layer$aes_params <- change_name(new_layer$aes_params, old_aes, new_aes)

  # Restore custom attributes
  attributes_old <- attributes(layer)
  attributes_new <- attributes(new_layer)
  attributes_replace <- attributes_old[setdiff(names(attributes_old), names(attributes_new))]

  attributes(new_layer)[names(attributes_replace)] <- attributes_replace
  new_layer
}

bump_aes_scales <- function(scales, new_aes) {
  lapply(scales, bump_aes_scale, new_aes = new_aes)
}

#' @importFrom ggplot2 guide_colourbar guide_colorbar guide_legend
bump_aes_scale <- function(scale, new_aes) {
  old_aes <- scale$aesthetics[remove_new(scale$aesthetics) %in% new_aes]
  if (length(old_aes) != 0) {
    new_aes <- paste0(old_aes, "_new")

    scale$aesthetics[scale$aesthetics %in% old_aes] <- new_aes

    if (is.character(scale$guide)) {
      no_guide <- isTRUE(scale$guide == "none")
    } else {
      no_guide <- isFALSE(scale$guide) ||
        isTRUE(inherits(scale$guide, c("guide_none", "GuideNone")))
    }
    if (!no_guide) {
      if (is.character(scale$guide)) {
        scale$guide <- get(paste0("guide_", scale$guide), mode = "function")()
      }
      if (inherits(scale$guide, "Guide")) {
        # Make clone of guie
        old <- scale$guide
        new <- ggplot2::ggproto(NULL, old)

        # Change available aesthetics
        new$available_aes <- change_name(new$available_aes, old_aes, new_aes)
        new$available_aes[new$available_aes %in% old_aes] <- new_aes

        # Update aesthetic override
        if (!is.null(new$params$override.aes)) {
          new$params$override.aes <- change_name(new$params$override.aes, old_aes, new_aes)
        }

        # Re-assign updated guide
        scale$guide <- new
      } else {
        scale$guide$available_aes[scale$guide$available_aes %in% old_aes] <- new_aes

        if (!is.null(scale$guide$override.aes)) {
          names(scale$guide$override.aes)[names(scale$guide$override.aes) == old_aes] <- new_aes
        }
      }

    }
  }

  scale
}

bump_aes_labels <- function(labels, new_aes) {
  old_aes <-  names(labels)[remove_new(names(labels)) %in% new_aes]
  new_aes <- paste0(old_aes, "_new")

  names(labels)[names(labels) %in% old_aes] <- new_aes
  labels
}


change_name <- function(list, old, new) {
  UseMethod("change_name")
}

change_name.character <- function(list, old, new) {
  list[list %in% old] <- new
  list
}

change_name.default <- function(list, old, new) {
  nam <- names(list)
  nam[nam %in% old] <- new
  names(list) <- nam
  list
}

change_name.NULL <- function(list, old, new) {
  NULL
}


remove_new <- function(aes) {
  gsub("(_new)*", "", aes, fixed = FALSE)
  # stringi::stri_replace_all(aes, "", regex = "(_new)*")
}


