FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        openssh-server \
        sudo \
        python3 \
        python3-apt \
        python3-distutils \
    && rm -rf /var/lib/apt/lists/*

RUN useradd -m -s /bin/bash ansible \
    && mkdir -p /var/run/sshd \
    && install -d -m 700 -o ansible -g ansible /home/ansible/.ssh \
    && echo 'ansible ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/ansible \
    && chmod 440 /etc/sudoers.d/ansible \
    && sed -i 's/#PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config \
    && sed -i 's|#PermitRootLogin prohibit-password|PermitRootLogin no|' /etc/ssh/sshd_config \
    && sed -i 's|AuthorizedKeysFile.*|AuthorizedKeysFile /home/ansible/.ssh/authorized_keys|' /etc/ssh/sshd_config

COPY ssh/id_rsa.pub /home/ansible/.ssh/authorized_keys

RUN chown -R ansible:ansible /home/ansible/.ssh \
    && chmod 600 /home/ansible/.ssh/authorized_keys \
    && ssh-keygen -A

EXPOSE 22

CMD ["/usr/sbin/sshd", "-D", "-e"]
