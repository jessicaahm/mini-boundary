###########################################
##### INSTALLATION SCRIPT - RUN ONCE ######
###########################################
#!/bin/sh

sudo apt update
sudo apt install curl ca-certificates gnupg -y
sudo apt install docker.io -y
sudo apt install postgresql-client-common -y
sudo apt install postgresql-client -y
sudo apt install ldap-utils -y

# Add current user to docker group
sudo usermod -aG docker $USER

# Log out and log back in, or run:
newgrp docker

# Test docker without sudo
docker ps

# Install Boundary CLI
curl -fsSL https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list
sudo apt install boundary -y