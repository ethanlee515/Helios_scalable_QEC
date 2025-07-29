FROM debian:bookworm

RUN apt-get update
RUN apt-get install -y git git-lfs
RUN apt-get install -y wget tar curl openjdk-17-jdk make g++

WORKDIR /opt
RUN wget https://github.com/YosysHQ/oss-cad-suite-build/releases/download/2025-07-05/oss-cad-suite-linux-x64-20250705.tgz
RUN tar xvf oss-cad-suite-*.tgz
RUN rm oss-cad-suite-*.tgz
ENV PATH="/opt/oss-cad-suite/bin:${PATH}"