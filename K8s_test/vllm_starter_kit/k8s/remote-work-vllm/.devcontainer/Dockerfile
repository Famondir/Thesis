# FROM ubuntu:24.04
FROM vllm/vllm-openai:latest

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

RUN pip install pandas ipykernel ipywidgets


COPY bin/* /usr/local/bin/
COPY sshd_config /etc/ssh/sshd_config

EXPOSE 22

ENTRYPOINT ["ssh-start"]
CMD ["ssh-server"]