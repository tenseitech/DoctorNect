# syntax=docker/dockerfile:1.7
# PostgREST for production RDS with TLS certificate verification.
# The official image carries no AWS RDS CA, so libpq cannot use sslmode=verify-full without one.
# This image adds the AWS RDS global CA bundle (pinned by SHA-256) at a fixed path.
#
# Build:  docker build -t <ecr>/doctornect-postgrest:v16.5-rdsca services/postgrest
# Then set var.postgrest_image to that tag and store PGRST_DB_URI in Secrets Manager as:
#   postgres://authenticator:<pw>@<rds-endpoint>:5432/doctornect?sslmode=verify-full&sslrootcert=/etc/ssl/rds/global-bundle.pem
#
# If AWS rotates the bundle, re-download it, update the checksum below, and rebuild.

FROM postgrest/postgrest:v16.5

ADD --checksum=sha256:90a6f1a7978a1b1b096dca6c57511ca48d3b8cf052f8e704baf358f34ea2f21b \
    https://truststore.pki.rds.amazonaws.com/global/global-bundle.pem \
    /etc/ssl/rds/global-bundle.pem

ENV PGSSLMODE=verify-full
ENV PGSSLROOTCERT=/etc/ssl/rds/global-bundle.pem
