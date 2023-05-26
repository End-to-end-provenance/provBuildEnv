prov.BuildEnv <- function(prov.dir, script.name, docker.image.name, from.prov.file = TRUE, r.version = NULL){
  if (!file.exists(prov.dir)) {  
    stop("Provenance directory not found")
  } 
  prov.file <- paste(prov.dir, "/prov.json", sep= "")
  
  if (!file.exists(prov.file)) {  
    stop("Provenance file not found")
  } 
  
  prov <- provParseR::prov.parse(prov.file)
  
  build.env.dir(prov, docker.image.name, prov.dir, script.name, from.prov.file, r.version)
}

build.env.dir <- function(prov, docker.image.name, prov.dir, script.name, from.prov.file, r.version){
  build.dir<- paste(prov.dir, "/", docker.image.name, sep="")
  if (!file.exists(build.dir)){
    dir.create(build.dir)
  }
  docker.file <- paste(build.dir, "/Dockerfile", sep="")
  if (!file.exists(docker.file)){
    file.create(docker.file)
  }
  entrypoint <- paste(build.dir, "/entrypoint.sh", sep="")
  if (!file.exists(entrypoint)){
    file.create(entrypoint)
  }
  docker.compose <- paste(build.dir, "/docker-compose.yml", sep="")
  if (!file.exists(docker.compose)){
    file.create(docker.compose)
  }
  volumes.dir <- paste(build.dir, "/volumes", sep="")
  if (!file.exists(volumes.dir)){
    dir.create(volumes.dir)
  }
  requirements <- paste(volumes.dir, "/requirements.txt", sep="")
  if (!file.exists(requirements)){
    file.create(requirements)
  }
  analysis.dir <- paste(volumes.dir, "/Analysis/", sep = "")
  if (!file.exists(analysis.dir)){
    dir.create(analysis.dir)
  }
  data.dir <- paste(volumes.dir, "/Data/", sep = "")
  if (!file.exists(data.dir)){
    dir.create(data.dir)
  }
  
  environment <- provParseR::get.environment(prov)
  if(is.null(r.version)){
    r.version <- environment[environment$label == "langVersion", ]$value
    r.version <- get.version.type(r.version)
  }
  
  
  script.path <- paste(prov.dir, "/scripts/", sep = "")
  data.path <- paste(prov.dir, "/data/", sep = "")
  
  script.files <- list.files(script.path)
  data.files <- list.files(data.path)
  
  file.copy(from = paste0(script.path, script.files), to = paste0(analysis.dir, script.files))
  file.copy(from = paste0(data.path, data.files), to = paste0(data.dir, data.files))
  
  #write dockerfile
  writeLines(c(paste("FROM rocker/r-ver:", r.version, sep=""),
               "LABEL Maintainer=\"sfabrega\"",
               "WORKDIR /home",
               "COPY entrypoint.sh /entrypoint.sh",
               "RUN chmod 755 /entrypoint.sh",
               "ENTRYPOINT [\"/entrypoint.sh\"]"
  ), docker.file)
  
  libs <- provParseR::get.libs(prov)
  script.libraries <- libs[libs$whereLoaded == "script", ] #loaded because script used them
  preloaded.libraries <- libs[libs$whereLoaded == "preloaded", ] #libs loaded when starts
  rdtLite.libraries <- libs[libs$whereLoaded == "rdtLite", ] #loaded because rdtLite uses them, possible that script uses them
  unknown.libraries <- libs[libs$whereLoaded == "unknown", ] #loading in a prov file if old
  
  script.vals <- data.frame(script.libraries$name, script.libraries$version)
  preloaded.vals <- data.frame(preloaded.libraries$name, preloaded.libraries$version)
  rdtLite.vals <- data.frame(rdtLite.libraries$name, rdtLite.libraries$version)
  unknown.vals <- data.frame(unknown.libraries$name, unknown.libraries$version)
  
  
  lines <- set.requirements.lines(script.vals, preloaded.vals, rdtLite.vals, unknown.vals)
  writeLines(as.character(lines), requirements)
  
  #TODO: write docker-compose
  
  writeLines(c("version: '1'",
               "services:",
               "  rscript:",
               paste("    image: ",docker.image.name, sep=""),
               "    volumes:",
               paste("      - ", volumes.dir, ":/home", sep=""),
               "    environment:",
               "      - TZ=America/New_York",
               paste("    command: Rscript -e \"rdtLite::prov.run(\'Analysis/", script.name,"\', prov.dir = \'Data\')\"",sep="")),
             docker.compose)
  
  if (from.prov.file){
    writeLines(c("#!/bin/bash",
                 "cd /home",
                 "apt update",
                 "DEBIAN_FRONTEND=noninteractive apt-get --yes install build-essential libcurl4-gnutls-dev libxml2-dev",
                 "FILE=./requirements.txt",
                 "if test -f \"$FILE\"; then",
                 " echo \"$FILE exists.\" ",
                 " Rscript -e \"install.packages('remotes')\"",
                 " while read -r package version; ",
                 " do ",
                 "  Rscript -e \"remotes::install_version('\"$package\"', version='\"$version\"', repos = 'https://cran.rstudio.com/')\"; ",
                 " done < \"$FILE\"",
                 "fi",
                 " Rscript -e \"install.packages('rdtLite')\"",
                 "exec \"$@\" # run whatever command is given for “command:” in docker-compose.yml"),
               entrypoint)
  }else {
    writeLines(c("#!/bin/bash",
                 "cd /home",
                 "apt update",
                 "DEBIAN_FRONTEND=noninteractive apt-get --yes install build-essential libcurl4-gnutls-dev libxml2-dev",
                 "FILE=./requirements.txt",
                 "PACKAGE_LS=\"c(\"",
                 "if test -f \"$FILE\"; then",
                 " echo \"$FILE exists.\" ",
                 " while read -r package version; ",
                 " do ",
                 "  PACKAGE_LS+=\"\'${package}\',\"",
                 " done < \"$FILE\"",
                 " PACKAGE_LS=${PACKAGE_LS::-1}",
                 " PACKAGE_LS+=\",'rdtLite')\"",
                 " echo ${PACKAGE_LS} ",
                 "fi",
                 " Rscript -e \"install.packages(${PACKAGE_LS})\"",
                 "exec \"$@\" # run whatever command is given for “command:” in docker-compose.yml"),
               entrypoint)
    
  }
  
  
  
  
}
set.requirements.lines <- function(script.df, preloaded.df, rdtLite.df, unknown.df){
  lines <- c("#package requirements")
  script.names <- script.df$script.libraries.name
  script.versions <- script.df$script.libraries.version
  for (i in seq_len(length(script.names))){
    if (!is.base.package(script.names[i])){
      lines <- c(lines, paste(script.names[i], script.versions[i], sep=" "))
    }
  }
  preloaded.names <- preloaded.df$preloaded.libraries.name
  preloaded.versions <- preloaded.df$preloaded.libraries.version
  for (i in seq_len(length(preloaded.names))){
    if (!is.base.package(preloaded.names[i])){
      lines <- c(lines, paste(preloaded.names[i], preloaded.versions[i], sep=" "))
    }  
  }
  rdtLite.names <- rdtLite.df$rdtLite.libraries.name
  rdtLite.versions <- rdtLite.df$rdtLite.libraries.version
  for (i in seq_len(length(rdtLite.names))){
    if (!is.base.package(rdtLite.names[i])){
      lines <- c(lines, paste(rdtLite.names[i], rdtLite.versions[i], sep=" "))
    }  
  }
  unknown.names <- unknown.df$unknown.libraries.name
  unknown.versions <- unknown.df$unknown.libraries.version
  for (i in seq_len(length(unknown.names))){
    if (!is.base.package(unknown.names[i])){
      lines <- c(lines, paste(unknown.names[i], unknown.versions[i], sep=" "))
    }    
  }
  return(lines)
  
}
get.version.type <- function(r.version){
  r.version <- unlist(strsplit(r.version, " "))[3]
  return(r.version)
}
is.base.package <- function(name){
  base.packages = c('base', 'compiler', 'datasets', 
                    'graphics', 'grDevices', 'grid', 
                    'methods', 'parallel', 'splines', 
                    'stats', 'stats4', 'tcltk',
                    'tools', 'utils')
  if(name %in% base.packages){
    return(TRUE)
  }
  return(FALSE)
}