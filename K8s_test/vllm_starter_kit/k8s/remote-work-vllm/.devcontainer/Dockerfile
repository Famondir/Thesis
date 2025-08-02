# FROM ubuntu:24.04
# FROM vllm/vllm-openai:latest
# FROM vllm/vllm-openai:v0.9.1
FROM vllm/vllm-openai:v0.10.0

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
# RUN code-server --install-extension ms-toolsai.datawrangler 
# does not work :(

RUN pip install pandas ipykernel ipywidgets
# RUN pip install transformers
RUN pip install hf-xet xgrammar
RUN pip install accelerate
RUN pip install pypdfium2
RUN pip install sentence_transformers
RUN pip install chromadb
RUN pip install deepdiff
RUN pip install outlines
RUN pip install datasets
RUN pip install nltk
RUN pip install openpyxl
RUN pip install tabulate
RUN pip install matplotlib
# RUN pip install --upgrade transformers
# for kimi k2
# RUN pip install blobfile

# configuring git
RUN git config --global user.email "s92818@bht-berlin.de"
RUN git config --global user.name "Simon Schaefer"


COPY bin/* /usr/local/bin/
COPY sshd_config /etc/ssh/sshd_config

EXPOSE 22

ENTRYPOINT ["ssh-start"]
CMD ["ssh-server"]