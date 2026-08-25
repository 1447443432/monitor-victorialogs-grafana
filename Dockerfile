ARG BASE_IMAGE=alpine:3.23
FROM ${BASE_IMAGE} AS builder

ARG TARGETARCH=amd64
ARG VL_PACKAGE=packages/victoria-logs-linux-${TARGETARCH}-v1.43.1.tar.gz
ARG GRAFANA_PACKAGE=packages/grafana_13.1.1_29761037902_linux_${TARGETARCH}.tar.gz
ARG VL_PLUGIN_PACKAGE=packages/victoriametrics-logs-datasource-v0.23.5.tar.gz

COPY ${VL_PACKAGE} /tmp/victoria-logs.tar.gz
COPY ${GRAFANA_PACKAGE} /tmp/grafana.tar.gz
COPY ${VL_PLUGIN_PACKAGE} /tmp/vl-plugin.tar.gz
COPY provisioning /tmp/provisioning

RUN mkdir -p /out/usr/local/victorialogs /out/usr/local/grafana /out/opt/grafana-plugins \
    && tar xzf /tmp/victoria-logs.tar.gz -C /out/usr/local/victorialogs \
    && tar xzf /tmp/grafana.tar.gz -C /out/usr/local/grafana --strip-components=1 \
    && mkdir -p /out/usr/local/grafana/conf/provisioning/datasources /out/usr/local/grafana/conf/provisioning/dashboards \
    && mkdir -p /tmp/vl-plugin \
    && tar xzf /tmp/vl-plugin.tar.gz -C /tmp/vl-plugin \
    && PLUGIN_DIR="$(find /tmp/vl-plugin -name plugin.json | head -n 1 | xargs dirname)" \
    && cp -r "${PLUGIN_DIR}" /out/opt/grafana-plugins/victoriametrics-logs-datasource \
    && find /out/opt/grafana-plugins/victoriametrics-logs-datasource -type f -name 'victoriametrics_logs_backend_plugin_*' ! -name "victoriametrics_logs_backend_plugin_linux_${TARGETARCH}" -delete \
    && find /out/opt/grafana-plugins/victoriametrics-logs-datasource -type f -name '*.map' -delete \
    && rm -f /out/opt/grafana-plugins/victoriametrics-logs-datasource/MANIFEST.txt \
    && cp -r /tmp/provisioning/datasources/* /out/usr/local/grafana/conf/provisioning/datasources/ \
    && cp -r /tmp/provisioning/dashboards/* /out/usr/local/grafana/conf/provisioning/dashboards/ \
    && sed -i 's#${DS_VICTORIAMETRICS-LOGS-DATASOURCE}#victorialogs#g' /out/usr/local/grafana/conf/provisioning/dashboards/*.json \
    && chmod +x /out/usr/local/victorialogs/victoria-logs-prod /out/usr/local/grafana/bin/grafana \
    && rm -rf /out/usr/local/grafana/docs /out/usr/local/grafana/tools /out/usr/local/grafana/storybook /out/usr/local/grafana/npm-artifacts /out/usr/local/grafana/packaging /out/usr/local/grafana/.github /out/usr/local/grafana/devenv /out/usr/local/grafana/e2e /out/usr/local/grafana/kinds /out/usr/local/grafana/scripts /out/usr/local/grafana/pkg /out/usr/local/grafana/emails /out/usr/local/grafana/Dockerfile /out/usr/local/grafana/README.md /out/usr/local/grafana/NOTICE.md /out/usr/local/grafana/LICENSE

FROM ${BASE_IMAGE}

COPY --from=builder /out/usr/local/victorialogs /usr/local/victorialogs
COPY --from=builder /out/usr/local/grafana /usr/local/grafana
COPY --from=builder /out/opt/grafana-plugins /opt/grafana-plugins
COPY scripts/entrypoint.sh /usr/local/bin/entrypoint.sh

RUN apk add --no-cache ca-certificates tzdata libc6-compat \
    && mkdir -p /data/victorialogs /usr/local/grafana/data \
    && chmod +x /usr/local/bin/entrypoint.sh \
    && chmod +x /usr/local/victorialogs/victoria-logs-prod \
    && chmod +x /usr/local/grafana/bin/grafana

WORKDIR /usr/local

EXPOSE 9428 3000

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
