FROM nvcr.io/nvidia/pytorch:25.03-py3
# FROM nvcr.io/nvidia/pytorch:24.04-py3

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
# RUN pip install https://vllm-wheels.s3.us-west-2.amazonaws.com/nightly/vllm-1.0.0.dev-cp38-abi3-manylinux1_x86_64.whl
RUN pip install pandas transformers hf-xet ipywidgets xgrammar
RUN pip install accelerate
RUN pip install pypdfium2
RUN pip install sentence_transformers
RUN pip install chromadb

# configuring git
RUN git config --global user.email "s92818@bht-berlin.de"
RUN git config --global user.name "Simon Schaefer"

# Setting up ssh
COPY bin/* /usr/local/bin/
COPY sshd_config /etc/ssh/sshd_config

RUN echo "export LANG='C.UTF-8'" >> /root/.profile \
    && echo "export HF_HOME='/pvc/hub_cache'" >> /root/.profile \
    && echo "export OMP_NUM_THREADS='1'" >> /root/.profile

EXPOSE 22

ENTRYPOINT ["ssh-start"]
CMD ["ssh-server"]