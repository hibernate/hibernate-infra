FROM sonatype/nexus3:3.76.0-ubi

COPY init_and_run.sh ${SONATYPE_DIR}/init_and_run.sh

EXPOSE 8081
EXPOSE 8181
USER nexus

CMD ["/opt/sonatype/init_and_run.sh"]
