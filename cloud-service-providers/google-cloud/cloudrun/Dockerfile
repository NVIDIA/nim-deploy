FROM nvcr.io/nim/meta/llama3-8b-instruct:1.0.0
ENV TZ US/Pacific
ENV DEBIAN_FRONTEND noninteractive
ENV NFSDATA_FILESTORE_IPV4 10.237.234.194
ENV LD_LIBRARY_PATH /usr/local/nvidia/lib64:${LD_LIBRARY_PATH}
USER root
RUN mkdir -p /home/nemo
COPY source/entrypoint_0.sh /home/nemo/entrypoint_0.sh
COPY source/http_respond_ready.py  /home/nemo/http_respond_ready.py
WORKDIR /
RUN mkdir -p /opt/nim/.cache
RUN chmod 777 /opt/nim/.cache
ENV NIM_CACHE_PATH=/opt/nim/.cache
WORKDIR /home/nemo
RUN apt-get update && apt-get install python3-pip -y
RUN pip install fastapi
RUN pip install "uvicorn[standard]"
ENTRYPOINT ["/home/nemo/entrypoint_0.sh"]



