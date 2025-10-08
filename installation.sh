###########################################
##### INSTALLATION SCRIPT - RUN ONCE ######
###########################################
#!/bin/sh

sudo apt update
sudo apt install curl ca-certificates gnupg -y
sudo apt install docker.io -y
sudo apt install postgresql-client-common -y
sudo apt install postgresql-client -y

# Add current user to docker group
sudo usermod -aG docker $USER

# Log out and log back in, or run:
newgrp docker

# Test docker without sudo
docker ps