########################################################################################################################
#                                                       DEV                                                            #
########################################################################################################################
FROM maven:3.6.1-jdk-8 AS dev

##########################
#  install dependencies  #
##########################

RUN sed -i s/deb.debian.org/archive.debian.org/g /etc/apt/sources.list && \
    sed -i s/security.debian.org/archive.debian.org/g /etc/apt/sources.list && \
    sed -i '/stretch-updates/d' /etc/apt/sources.list && \
    echo 'Acquire::Check-Valid-Until "false";' > /etc/apt/apt.conf.d/99no-check-valid-until && \
    apt-get update \
    && apt-get install -y --no-install-recommends \
    curl=7.52.1-5+deb9u9 \
    g++=4:6.3.0-4 \
    make=4.1-9.1 \
    unzip=6.0-21+deb9u1 \
    zip=3.0-11+b1 \
    libjpeg-dev \
    zlib1g-dev \
    && rm -rf /var/lib/apt/lists/*

#######################
#  install new cmake  #
#######################
RUN curl -fsSL --insecure -o /tmp/cmake.tar.gz https://cmake.org/files/v3.13/cmake-3.13.4.tar.gz \
    && tar -xzf /tmp/cmake.tar.gz -C /tmp \
    && rm -rf /tmp/cmake.tar.gz  \
    && mv /tmp/cmake-* /tmp/cmake \
    && cd /tmp/cmake \
    && ./bootstrap \
    && make -j4 \
    && make install \
    && rm -rf /tmp/cmake

#######################
#  download libtorch  #
#######################
WORKDIR /opt
ENV LIBTORCH_URL=https://download.pytorch.org/libtorch/cpu/libtorch-cxx11-abi-shared-with-deps-1.5.0%2Bcpu.zip
RUN curl -fsSL --insecure -o libtorch.zip  $LIBTORCH_URL \
    && unzip -q libtorch.zip \
    && rm libtorch.zip

ENV TORCH_HOME=/opt/libtorch

#####################
#  Install PyTorch  #
#####################
WORKDIR /tmp
RUN curl -fsSL --insecure -o anaconda.sh https://repo.anaconda.com/miniconda/Miniconda3-4.7.10-Linux-x86_64.sh \
    && /bin/bash anaconda.sh -b -p /opt/conda \
    && rm anaconda.sh \
    && ln -s /opt/conda/etc/profile.d/conda.sh /etc/profile.d/conda.sh \
    && echo ". /opt/conda/etc/profile.d/conda.sh" >> "$HOME"/.bashrc \
    && echo "conda activate base" >> "$HOME"/.bashrc

ENV PATH=/opt/conda/bin/:$PATH

RUN pip install --no-cache-dir -f https://download.pytorch.org/whl/torch_stable.html \
    torch==1.5.0+cpu \
    torchvision==0.6.0+cpu \
    black==23.3.0 \
    isort==5.11.5 \
    typing-extensions==4.7.1 \
    numpy==1.21.6 \
    scikit-learn==1.0.2 \
    pandas==1.3.5 \
    matplotlib==3.5.3 \
    tqdm==4.67.3


########################################################################################################################
#                                                     JAVA BUILDER                                                     #
########################################################################################################################
RUN curl -fsSL --insecure -o /tmp/protobuf-2.5.0.tar.gz https://github.com/protocolbuffers/protobuf/releases/download/v2.5.0/protobuf-2.5.0.tar.gz \
    && tar -xzf /tmp/protobuf-2.5.0.tar.gz -C /tmp \
    && rm -rf /tmp/protobuf-2.5.0.tar.gz  \
    && mv /tmp/protobuf-* /tmp/protobuf \
    && cd /tmp/protobuf \
    && ./configure \
    && make -j$(nproc) \
    && make install \
    && rm -rf /tmp/protobuf
ENV PATH=/usr/local/bin/:$PATH
ENV LD_LIBRARY_PATH=/usr/local/lib:$LD_LIBRARY_PATH

WORKDIR /app
COPY ./angel /app/angel
RUN --mount=type=cache,target=/root/.m2 \
    curl -o /tmp/algs4.jar https://algs4.cs.princeton.edu/code/algs4.jar && \
    mvn install:install-file -Dfile=/tmp/algs4.jar -DgroupId=edu.princeton.cs -DartifactId=algs4 -Dversion=1.0.4 -Dpackaging=jar && \
    rm -f /tmp/algs4.jar && \
    mvn install -q -e -B -Dmaven.test.skip=true -f /app/angel/pom.xml

COPY ./pom.xml /app/pytorch-on-angel/pom.xml
COPY ./java /app/pytorch-on-angel/java
COPY ./examples /app/pytorch-on-angel/examples
RUN --mount=type=cache,target=/root/.m2 \
    mvn install -q -e -B -Dmaven.test.skip=true -f /app/pytorch-on-angel/pom.xml

########################################################################################################################
#                                                     CPP BUILDER                                                      #
########################################################################################################################

WORKDIR /app

COPY ./cpp ./

RUN ./build.sh \
    && cp ./out/*.so "$TORCH_HOME"/lib \
    && cp /usr/lib/x86_64-linux-gnu/libstdc++.so.6 "$TORCH_HOME"/lib \
    && ln -s "$TORCH_HOME"/lib torch-lib \
    && zip -qr /torch.zip torch-lib

########################################################################################################################
#                                                       Artifacts                                                      #
########################################################################################################################
FROM alpine:3.10 AS artifacts

WORKDIR /dist
COPY --from=dev /torch.zip ./
COPY --from=dev /app/target/*.jar ./

VOLUME /output

CMD [ "/bin/sh", "-c", "cp ./* /output" ]
