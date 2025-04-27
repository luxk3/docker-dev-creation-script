#/bin/sh


INFO="[+]"
WARN="[-]"
ERR="\t[!]"
OK="\t[✓]"
KO="\t[x]"
LOG="[*]"



# Prompt the user
read -p "$LOG Please provide the container name (remind to avoid conflicts with existing containers): " container_name

# Check if the container name is good
if [[ -z "$container_name" || "$container_name" =~ ^[0-9] ]]; then
    echo "$ERR Error: The container name is not valid."
    exit 1
else
    echo "$OK Using '$container_name' as container name."
fi

# Prompt the user
read -p "$LOG Please paste the folder path you want to create the docker-dev in: " folder_path

# Check if the folder already exists
if [ -d "$folder_path" ]; then
    echo "$ERR Error: The folder '$folder_path' already exists."
    exit 1
else
    # Create the folder
    mkdir -p "$folder_path"
    echo "$OK Folder '$folder_path' has been created."
fi

# SSH port
read -p "$LOG Enter the ssh port you want to use on localhost: " ssh_port

# Check if not empty and is a number
if [[ -n "$ssh_port" && "$ssh_port" =~ ^[0-9]+$ ]]; then
    echo "$OK Using port: $ssh_port"
else
    echo "$ERR Error: no port provided or is not a number"
    exit 1
fi

# Prompt the user for the long string
read -p "$LOG Paste your public ssh key (leave empty to skip): " ssh_key_pub

# # Check if the input is not empty
# if [ -n "$ssh_key_pub" ]; then
#     # Save the key to the .ssh/key file
#     mkdir $folder_path/.ssh
#     echo "" >> "$folder_path/.ssh/authorized_keys"
#     echo "$ssh_key_pub" >> "$folder_path/.ssh/authorized_keys"
#     echo "Content saved to "$folder_path/.ssh/authorized_keys"
# else
#     echo "No public key provided. Authentication by password only."
# fi

# generating random password for user dev

random_string=$(head -c 48 /dev/urandom | base64 | tr -dc 'A-Za-z0-9' | head -c 25)



docker_file=$(cat <<EOF
FROM ubuntu:latest

# Set environment variables
ENV DEBIAN_FRONTEND=noninteractive

# Install dependencies
RUN apt update && apt install -y \
    curl git vim sudo openssh-server \
    python3 python3-pip \
    make build-essential libssl-dev zlib1g-dev \
    libbz2-dev libreadline-dev libsqlite3-dev wget \
    llvm libncurses5-dev xz-utils tk-dev \
    libffi-dev liblzma-dev \
    software-properties-common \
    && rm -rf /var/lib/apt/lists/*

# Create a non-root user
RUN useradd -m -s /bin/bash dev && echo "dev:$random_string" | chpasswd && usermod -aG sudo dev

# Set up SSH
RUN mkdir /var/run/sshd
RUN mkdir /home/dev/.ssh
RUN echo 'PermitRootLogin no' >> /etc/ssh/sshd_config
RUN echo 'PasswordAuthentication yes' >> /etc/ssh/sshd_config
RUN echo '$ssh_key_pub' >> /home/dev/.ssh/authorized_keys

# Install pyenv for managing multiple Python versions
USER dev
RUN curl https://pyenv.run | bash

# Set up pyenv environment
ENV PATH="/home/dev/.pyenv/bin:\$PATH"
ENV PYENV_ROOT="/home/dev/.pyenv"
ENV PATH="\$PYENV_ROOT/shims:\$PATH"
RUN export PATH=\$PATH:/home/dev/.pyenv/bin/

# Install Terraform
USER root
RUN curl -fsSL https://apt.releases.hashicorp.com/gpg | apt-key add - \
    && apt-add-repository "deb [arch=amd64] https://apt.releases.hashicorp.com \$(lsb_release -cs) main" \
    && apt update && apt install -y terraform

# Expose SSH port
EXPOSE 22

# Start SSH service
CMD ["/usr/sbin/sshd", "-D"]
EOF
)

# write file in folder
echo "$LOG Writing the Dockerfile.."
echo "$docker_file" > "$folder_path/Dockerfile"
echo "$OK Dockerfile written"


docker_compose_file=$(cat <<EOF
version: '3.8'

services:
  $container_name:
    build: .
    container_name: $container_name
    restart: unless-stopped
    ports:
      - "127.0.0.1:$ssh_port:22"
    volumes:
      - ./projects:/home/dev/projects
      # - ~/.ssh:/home/dev/.ssh:ro
    environment:
      - TZ=Europe/Brussels
    networks:
      - dev-network

networks:
  dev-network:
    driver: bridge


EOF
)


# write file in folder
echo "$LOG Writing the docker-compose.yml file"
echo "$docker_compose_file" > "$folder_path/docker-compose.yml"
echo "$OK docker-compose.yml file written"

echo "$LOG Creating project folder"
mkdir  "$folder_path/projects"
echo "$OK Creating project folder"


ssh_quick_config=$(cat <<EOF

Host $container_name
	HostName 127.0.0.1
	User dev
	Port $ssh_port
	ForwardAgent yes

EOF
)

RED="\033[31m"
GREEN="\033[32m"
UND="\033[4m"
RED_ITA="\033[3;31m"
RESET_ST="\033[0m"


CONNECTION_MESSAGE_no="\
To use the container, do: 
  1. ${RED_ITA}cd${RESET_ST} into the directory ${UND}$folder_path${RESET_ST} 
  2. Execute the ${RED_ITA}docker compose${RESET_ST} command 
  3. Connect to the container: ${GREEN}ssh -o IdentitiesOnly=yes dev@127.0.0.1 -p $ssh_port ${RESET_ST}
NOTE: password for user ${RED}dev${RESET_ST} is  ${RED}$random_string${RESET_ST}
"

CONNECTION_MESSAGE_yes="\
To use the container, do: 
  1. ${RED_ITA}cd${RESET_ST} into the directory ${UND}$folder_path${RESET_ST} 
  2. Execute the ${RED_ITA}docker compose${RESET_ST} command 
  3. Connect to the container: 
    ${GREEN}ssh -o IdentitiesOnly=yes dev@127.0.0.1 -p $ssh_port ${RESET_ST} or
    ${GREEN}ssh $container_name ${RESET_ST}
NOTE: password for user ${RED}dev${RESET_ST} is  ${RED}$random_string${RESET_ST}
"



read -p "$WARN I can add a quick SSH config to your config. Do you want to append the following to your ~/.ssh/config (yes/NO)?\n $ssh_quick_config: " yes_no

# Normalize input to lowercase
yes_no_insensitive=$(echo "$yes_no" | tr '[:upper:]' '[:lower:]')

if [[ -z "$yes_no_insensitive" || "$yes_no_insensitive" == "no" ]]; then
    echo "$KO Local ~/.ssh/config NOT modified."
    echo "\n\n$CONNECTION_MESSAGE_no"
    exit 1
fi


# Appending the configuration for quick ssh connect
echo "$INF Appending the configuration for quick ssh connect to the file ~/.ssh/config."

echo "$ssh_quick_config" >> ~/.ssh/config

echo "$OK Local file ~/.ssh/config MODIFIED. Configuration added."
echo "\n\n$CONNECTION_MESSAGE_yes"
