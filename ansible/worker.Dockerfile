FROM debian:stable-slim

RUN apt-get update && apt-get install -y openssh-server sudo && \
    mkdir -p /var/run/sshd && useradd -ms /bin/bash ansible && \
    usermod -aG sudo ansible && \
    echo 'ansible ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/ansible
    
# copy your authorized_keys
# COPY authorized_keys /home/ansible/.ssh/authorized_keys
# Create .ssh and set permissions before copy
RUN mkdir -p /home/ansible/.ssh && chmod 700 /home/ansible/.ssh

# RUN chown -R ansible:ansible /home/ansible/.ssh && chmod 600 /home/ansible/.ssh/authorized_keys

EXPOSE 22

CMD ["/usr/sbin/sshd","-D","-e"]
