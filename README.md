# provBuildEnv
Creates a Docker container based on provenance created by rdtLite and runs the script in that container to collect new provenance.

# To Use
Call provBuildEnv() with the following parameters:
- prov.dir -> the pathname to the provenance directory
- script.name -> the name of the main script in the prov directory
- docker.image.name -> what the user wants to name the docker image
- from.prov.file -> default TRUE if the user wants to use the package versions from the prov.JSON file. Use FALSE if the user wants to set their own R version to run the script(s).
- r.version -> default NULL, enter version of R as a string if you want to specify the R version. Make sure from.prov.file is set to FALSE. ex: r.version="4.2.0"

provBuildEnv() will create a docker folder in the provenance directory. To run the docker container, use the terminal to navigate into the docker folder, then execute the following commands. Make sure Docker is running on your machine before you do this:

docker build -t <docker.image.name> . \n
docker compose up


