FROM scratch

COPY zig-out/bin/zippon /
COPY example.zipponschema /

ENV ZIPPONDB_PATH=data
ENV ZIPPONDB_SCHEMA=example.zipponschema

CMD ["/zippon"]

