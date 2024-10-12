FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

# Set the working directory
WORKDIR /app

# Install necessary system dependencies
RUN apt update
RUN apt install python3.11 python3.11-dev -y
RUN apt install curl git gcc libgirepository1.0-dev libcairo2-dev qemu-utils libvirt-dev python3-pip python3-venv -y

# Clone the latest release of LISA from the GitHub repository
RUN git clone --branch $(curl --silent "https://api.github.com/repos/microsoft/lisa/releases/latest" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/') https://github.com/microsoft/lisa.git /app/lisa

# Install Python dependencies for LISA
RUN python3 -m pip install --upgrade pip
WORKDIR /app/lisa
RUN python3 -m pip install --editable .[azure,libvirt] --config-settings editable_mode=compat
RUN ln -s /app/.local/bin/lisa /bin/lisa

CMD ["/bin/bash"]
