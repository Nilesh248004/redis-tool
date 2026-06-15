FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y \
    openssh-server \
    sudo \
    python3 \
    python3-apt \
    curl \
    ca-certificates \
    build-essential \
    tcl \
    wget \
    net-tools \
    iputils-ping \
    && rm -rf /var/lib/apt/lists/*

RUN useradd -m -s /bin/bash ansible \
    && passwd -d ansible \
    && usermod -U ansible \
    && chage -E -1 ansible \
    && echo "ansible ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/ansible \
    && chmod 0440 /etc/sudoers.d/ansible

RUN mkdir -p /var/run/sshd \
    && mkdir -p /home/ansible/.ssh \
    && touch /home/ansible/.ssh/authorized_keys \
    && chmod 755 /home/ansible \
    && chmod 700 /home/ansible/.ssh \
    && chmod 600 /home/ansible/.ssh/authorized_keys \
    && chown -R ansible:ansible /home/ansible

RUN sed -i 's/#PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config \
    && sed -i 's/#PubkeyAuthentication yes/PubkeyAuthentication yes/' /etc/ssh/sshd_config \
    && sed -i 's/UsePAM yes/UsePAM no/' /etc/ssh/sshd_config

EXPOSE 22

CMD ["/usr/sbin/sshd", "-D"]
