#!/usr/bin/Rscript

## Script name: functions.R
##
## Purpose of script: functions for the analysis of species 
## assessments and statistics
##
## Author: Savvas Paragkamian
##
## Date Created: 2022-12-22
create_dir <- function(dir_name){

    if (!dir.exists(dir_name)){
    dir.create(dir_name)
    print(paste0(dir_name, " directory created", sep=""))
    } else{
        print(paste0(dir_name, " directory exists", sep=""))
    }
}

area_overlap_combination <- function(master_sf, list_sf, clabels){

    # this function takes as input a master sf, a named list of sf objects
    # and a labels factor. It calculates the area of overlap of the master_sf 
    # with each of the other sf objects per label. The output is a list of lists
    # of dataframes. 
    # Complementary functions are spatial_area_summary and convert_nested_l_df
    results <- list()

    for (i in seq_along(list_sf)){
    
        intersected <- st_intersection(master_sf,list_sf[[i]] )
        name_sf <- names(list_sf)[i]
        results[[name_sf]] <- list()
        
        for (j in seq_along(clabels)){

            label <- clabels[j]
            df_results <- spatial_area_summary(intersected,label)
            colnames(df_results) <- c(label, name_sf)
            print(j,i)

            results[[name_sf]][[label]] <- df_results
        }
    }
    return(results)
}

spatial_area_summary <- function(spatial_area,attribute){

    #this function takes a sf object and a grouping variable
    #and returns a dataframe of the area per name of the variable
    attribute <- as.character(attribute)
    spatial_area$area <- units::set_units(st_area(st_make_valid(spatial_area)),km^2)

    spatial_area_s <- spatial_area %>%
        st_drop_geometry() %>%
        group_by(.data[[attribute]]) %>%
        summarise(total_area=sum(area))

    return(spatial_area_s)
}

heatmaps <- function(locations_grid){
    
    locations_grid_o <- locations_grid %>%
        distinct(CELLCOD, order) %>%
        arrange(order)
    
    order_cell_m <- locations_grid_o %>%
        st_drop_geometry() %>%
        mutate(exist=1) %>%
        pivot_wider(id_cols=order, 
                    names_from = CELLCOD, 
                    values_from= exist,
                    values_fill = 0) %>%
        column_to_rownames(var="order") %>%
        as.matrix()
    
    # create the heatmap matrix through matrix multiplication
    
    order_cell_over <- order_cell_m %*% t(order_cell_m)
    
    order_cell_over[lower.tri(order_cell_over)] <- 0
    
    order_cell_long <- order_cell_over %>% 
        as.data.frame() %>%
        rownames_to_column() %>% 
        pivot_longer(-rowname,names_to="colname",values_to="count" )
    
    colnames(order_cell_long) <- c("from","to","count")
    
    order_cell_long$from <- factor(order_cell_long$from, 
                                         levels = unique(order_cell_long$from))
    order_cell_long$to <- factor(order_cell_long$to, 
                                 levels = unique(order_cell_long$to))

    order_cell_heatmap <- ggplot()+
      geom_tile(data=order_cell_long,aes(x=from, y=to,fill=count),alpha=1, show.legend = T)+
      scale_fill_gradient(low="#999999", high="#E69F00", limits=c(1, max(order_cell_long$count)),na.value="white")+ 
      scale_x_discrete(position = "top")+
      scale_y_discrete(limits = rev)+
      labs(fill="# of locations")+
      xlab("") +
      ylab("")+
      theme_bw()+
      theme(
            panel.border=element_blank(),
            panel.grid.major = element_blank(),
            panel.grid.minor=element_blank(),
            text = element_text(size=17), 
            axis.text.x = element_text(angle = 90, hjust = 0),
            legend.position = c(.90, .83))

    results <- list(order_cell_long,order_cell_heatmap)
    return(results)
}

aoo_overlap <- function(aoo_shp, baseline_map, overlap_area, plots){

    aoo <- aoo_shp[[2]]
    species_aoo <- list()
#    overlap_area_c <- st_combine(overlap_area)
    if (plots){
    }

    for (a in seq_along(aoo)){
        
        species <- names(aoo[a])
        aoo_sf <- st_as_sf(aoo[[a]])
        # area units transform to km^2
        aoo_area <- sum(units::set_units(st_area(aoo_sf),km^2))
        print(aoo_area)
        # Calculate the overlap with protected area

        aoo_overlap <- st_intersection(aoo_sf,overlap_area)

        aoo_overlap_area <- sum(units::set_units(st_area(aoo_overlap), km^2))
        print(aoo_overlap_area)
        species_row <- cbind(species, aoo_area, aoo_overlap_area)

        species_aoo[[a]]<- species_row

        if (plots) {
            
            if (is(baseline_map, "sf")==TRUE){
        
                g <- g_species(aoo_sf, overlap_area, baseline_map)

                if (as.numeric(aoo_overlap_area) > 0){
                    g <- g + 
                        geom_sf(aoo_overlap, mapping=aes(fill="orange"),color="orange", alpha=0.2, size=0.2)
                }
                ggsave(paste0("../plots/aoo/","aoo_", as.character(species),".png"), plot=g, device="png")
            }
        }
    }

    species_aoo_df <- as_tibble(do.call(rbind, species_aoo)) %>%
        rename("aoo"="aoo_area", "aoo_overlap"="aoo_overlap_area")

    species_aoo_df$aoo <- as.numeric(species_aoo_df$aoo)
    species_aoo_df$aoo_overlap <- as.numeric(species_aoo_df$aoo_overlap)

    return(species_aoo_df)
}

eoo_calculation <- function(occurrences,baseline_map, overlap_area, plots, prefix) {
    
# eoo_calculation is a custom function that takes 3 inputs.
# the location shapefile, the polygon and a TRUE/FALSE value to 
# export or not to plot
    species <- occurrences %>% st_drop_geometry() %>%
        dplyr::select(scientificName) %>% 
        distinct() %>%
        pull()

    calculations <- list(list())

    for(s in seq_along(species)){

        n_occurrences <- occurrences %>%
            filter(scientificName==species[s])

        calculations[[s]] <- eoo_single(n_occurrences,baseline_map, overlap_area, plots, prefix)
        
    }

    eoo_overlap_name <- paste0("eoo_",prefix)
    calculations_df <- convert_ll_df(calculations) %>% as_tibble() 
    colnames(calculations_df) <- c("scientificName", "n_sites", "eoo", "eoo_overlap")

    calculations_df$n_sites <- as.numeric(calculations_df$n_sites)
    calculations_df$eoo <- as.numeric(calculations_df$eoo)
    calculations_df$eoo_overlap <- as.numeric(calculations_df$eoo_overlap)
    
    return(calculations_df)
}


eoo_single <- function(taxon_occurrences,baseline_map, overlap_area, plots, prefix) {
    
    prefix <- as.character(prefix)
    rows <- nrow(taxon_occurrences)
    species <- taxon_occurrences %>% st_drop_geometry() %>%
        dplyr::select(scientificName) %>% 
        distinct() %>%
        pull()

    calculations <- list()
    print(as.character(species))
    calculations[[1]] <- as.character(species)
    calculations[[2]] <- rows

    if (length(species) > 1){
        print(paste0(" has more than one taxon."))

    } else if (rows < 3){
        print(paste0(species, " has ", rows, 
                         " occurrences. Moving to the next taxon"))
        calculations[[3]] <- NA
        calculations[[4]] <- NA

    } else {
        # union the points of each species
        # and then calculate the convex hull of the points of 
        # each species
        species_convex <- st_convex_hull(st_union(taxon_occurrences))

        # here we check whether the EOO of a species forms a polygon.
        # There are some rare cases that it forms a line. When that
        # happens the overlap cannot be calculated.

        if (st_geometry_type(species_convex)!="POLYGON"){
            calculations[[3]] <- 0
            calculations[[4]] <- 0

        } else {
            
            #Use km^2 for area units
            calculations[[3]] <- units::set_units(st_area(species_convex), km^2)
            print(calculations[[3]])

            if (is(overlap_area, "sf")==TRUE){

                species_convex_overlap <- st_intersection(species_convex,overlap_area)
                # st_intersection with multiple polygons returns multiple polygons
                # so st_area returns the area of each polygon. Either we sum the area
                # of each polygon or before calculating the area we union the polygons
                calculations[[4]] <- units::set_units(st_area(st_union(species_convex_overlap)), km^2)

            } else {
                calculations[[4]] <- NA
            }
        }
        
        if (plots==TRUE){
            g <- g_species(taxon_occurrences,species_convex, baseline_map)
            
            if (is(baseline_map, "sf")==TRUE){
        
                g <- g + 
                    geom_sf(overlap_area, mapping=aes(),color="green", alpha=0.2, size=0.2)
        
            }

            ggsave(paste0("../plots/polygons/",prefix, "_", as.character(species),".png"), plot=g, device="png")

        }
    }

    return(calculations)
}

g_species <- function(occurrences,convex, baseline_map){
    
#    convex <- st_convex_hull(st_union(occurrences))
    name <- unique(as.character(occurrences$scientificName))
    name_ <- gsub(" ", "_", name)

    g <- ggplot() +
        geom_sf(baseline_map, mapping=aes()) +
        geom_sf(occurrences, mapping=aes(),color="blue", size=0.1, alpha=0.2) +
        geom_sf(convex, mapping=aes(),color="red", alpha=0.2, size=0.1) +
        coord_sf(crs="WGS84") +
        ggtitle(name)+
        theme_bw()+
        theme(plot.title = element_text(face = "italic"))
    
        return(g)

}

g_base <- function(){

    crete_shp <- sf::st_read("../data/crete/crete.shp")
    
    natura_crete <- sf::st_read("../data/natura2000/natura2000_crete.shp")

    natura_crete_land <- st_intersection(natura_crete, crete_shp)

    # split the SPA SCI

    natura_crete_land_sci <- natura_crete_land %>% filter(SITETYPE=="B")

    g_base <- ggplot() +
        geom_sf(crete_shp, mapping=aes()) +
        geom_sf(natura_crete_land_sci, mapping=aes(),color="#4BA591", alpha=0.2, size=0.1) +
        coord_sf(crs="WGS84") +
        theme_bw()

    return(g_base)
} 

convert_nested_l_df <- function(list_of_l_of_df){

    # transormation of nested list of lists to list of dataframes

    # this step merges lists of lists of dataframes to lists of dataframes.
    # The names of l1 are the concataned names of the original with . .
    # The next step is to create a new list with the right part of the name.
    # This way each element of the list contains dataframes of the same name.
    # In the last step the dataframes with the same name and subsequently the
    # same rows are merged. 
    # The final list is contains merged dataframes.
    l1 <- do.call('c', list_of_l_of_df)
    l2 <- split(l1,sub('.*\\.', '', names(l1)))
    results_df <- lapply(l2, function(x) Reduce(merge, x))
    return(results_df)


}

convert_ll_df <- function(list_of_l_of_l){
    
    list_of_l <- lapply(list_of_l_of_l, unlist)
    df <- data.frame(do.call(rbind, list_of_l))

    return(df)

}
