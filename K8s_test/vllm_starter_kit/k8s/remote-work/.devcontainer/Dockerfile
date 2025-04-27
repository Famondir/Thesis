FROM nvcr.io/nvidia/pytorch:25.03-py3

ENV TERM=xterm

RUN apt-get update

RUN apt-get install -y nano curl git

RUN apt-get -yq install openssh-server; \
  mkdir -p /var/run/sshd; \
  mkdir /root/.ssh && chmod 700 /root/.ssh; \
  touch /root/.ssh/authorized_keys

### Install code-server
RUN curl -fsSL https://code-server.dev/install.sh | sh

RUN mkdir -p /root/.vscode-server/extensions/
RUN code-server & sleep 5 && pkill code-server || true
RUN echo "extensions-dir: /root/.vscode-server/extensions/" >> /root/.config/code-server/config.yaml

### Preinstall extensions
RUN code-server --install-extension ms-python.python \
    && code-server --install-extension ms-toolsai.jupyter

### Install Python packages
RUN python -m pip install --upgrade pip
# RUN pip install vllm
RUN pip install pandas

### install docker client

# RUN apt-get install \
#     apt-transport-https \
#     ca-certificates \
#     curl \
#     gnupg-agent \
#     software-properties-common

# RUN curl -fsSL https://download.docker.com/linux/ubuntu/gpg | apt-key add -

# RUN add-apt-repository \
#    "deb [arch=amd64] https://download.docker.com/linux/ubuntu \
#    $(lsb_release -cs) \
#    stable"

# RUN apt update
# RUN apt install -y docker-ce docker-ce-cli containerd.io


COPY bin/* /usr/local/bin/
COPY sshd_config /etc/ssh/sshd_config

EXPOSE 22

ENTRYPOINT ["ssh-start"]
CMD ["ssh-server"]