#!/bin/bash -e

NEXUS_DOWNLOAD_URL=https://download.sonatype.com/nexus/3/nexus-3.76.1-01-unix.tar.gz
NEXUS_DOWNLOAD_SHA256_HASH=e6a68b903a445fc6b923a2ea922accb336e659a838099f2efb08e382332ff8f1

JDK_DOWNLOAD_URL=https://github.com/adoptium/temurin17-binaries/releases/download/jdk-17.0.9%2B9/OpenJDK17U-jdk_x64_linux_hotspot_17.0.9_9.tar.gz
JDK_DOWNLOAD_SHA256_HASH=7b175dbe0d6e3c9c23b6ed96449b018308d8fc94a5ecd9c0df8b8bc376c3c18a

download_and_unpack() {
  DOWNLOAD_URL=$1
  DOWNLOADED_ARCHIVE=$2
  EXPECTED_HASH=$3
  UNPACK_LOCATION=$4

  echo "Downloading: $DOWNLOAD_URL..."
  if wget -q --show-progress -O "$DOWNLOADED_ARCHIVE" "$DOWNLOAD_URL"; then
      echo "Successfully downloaded $DOWNLOADED_ARCHIVE"
  else
      echo "Error: Failed to download from $DOWNLOAD_URL"
      exit 1
  fi

  echo "Checking the downloaded file..."

  DOWNLOADED_HASH=$(sha256sum "$DOWNLOADED_ARCHIVE" | awk '{print $1}')
  if [ "$DOWNLOADED_HASH" == "$EXPECTED_HASH" ]; then
      echo "Successfully verified the file hash"
  else
      echo "Error: Failed the hash verification. Expected: $EXPECTED_HASH but got $DOWNLOADED_HASH instead"
      exit 1
  fi

  mkdir -p "$UNPACK_LOCATION"
  if tar -xzf "$DOWNLOADED_ARCHIVE" -C "$UNPACK_LOCATION" --strip-components=1; then
      echo "Successfully extracted to $UNPACK_LOCATION"
      rm "$DOWNLOADED_ARCHIVE"
  else
      echo "Error: Failed to untar $DOWNLOADED_ARCHIVE."
      exit 1
  fi
}

export SONATYPE_DIR=$1
export NEXUS_HOME="$SONATYPE_DIR/nexus"
export NEXUS_DATA="$SONATYPE_DIR/nexus-data"
export SONATYPE_WORK="$SONATYPE_DIR/sonatype-work/nexus3"
export INSTALL4J_JAVA_HOME="$SONATYPE_DIR/jdk"

if [ -d "$NEXUS_HOME" ]; then
  echo "Nexus already installed. Skipping..."
else
  download_and_unpack "$NEXUS_DOWNLOAD_URL" "nexus.tar.gz" "$NEXUS_DOWNLOAD_SHA256_HASH" "$NEXUS_HOME"
  #  echo "run_as_user=\"fedora\"" > "$NEXUS_HOME/bin/nexus.rc"
  sed -i "s?^# INSTALL4J_JAVA_HOME_OVERRIDE=?INSTALL4J_JAVA_HOME_OVERRIDE=$INSTALL4J_JAVA_HOME?" "$NEXUS_HOME/bin/nexus"
  sed -i 's/^-Xms.*/-Xms4096m/;s/^-Xmx.*/-Xmx4096m/;s/^-XX:MaxDirectMemorySize.*/-XX:MaxDirectMemorySize=4096m/' "$NEXUS_HOME/bin/nexus.vmoptions"
fi

if [ -d "$INSTALL4J_JAVA_HOME" ]; then
  echo "JDK already installed. Skipping..."
else
  download_and_unpack "$JDK_DOWNLOAD_URL" "jdk.tar.gz" "$JDK_DOWNLOAD_SHA256_HASH" "$INSTALL4J_JAVA_HOME"
fi

#####################################################################

if [ -e ${SONATYPE_WORK}/instance.configured ]
then
  echo 'Nexus data already contains initial configuration, skipping initialisation.'
else
  echo "Nexus starting for the first time. No initial configuration applied yet."
  echo "Nexus will start, get preconfigured and then restart."

  $NEXUS_HOME/bin/nexus start

  until curl -s -f -o /dev/null "http://localhost:8081/"
    do
      echo 'Not ready yet'
      sleep 5
    done

  # initial password is stored in a /nexus-data/admin.password
  INIT_PASS=$(cat ${SONATYPE_WORK}/admin.password)
  NEW_PASS=${ADMIN_PASS:-${INIT_PASS}}

  # Initial login to Nexus requires resetting the admin password, and making the decision about anonymous access:
  curl -s -X PUT --location "http://localhost:8081/service/rest/v1/security/users/admin/change-password" \
          -H "Content-Type: text/plain" \
          -d ${NEW_PASS} \
          --basic --user admin:${INIT_PASS}

  curl -s -X PUT --location "http://localhost:8081/service/rest/v1/security/anonymous" \
      -H "Content-Type: application/json" \
      -d '{
            "enabled": true,
            "userId": "anonymous",
            "realmName": "NexusAuthorizingRealm"
          }' \
      --basic --user admin:${NEW_PASS}

  # using Docker registries may requires docker token, and this request adds a corresponding realm:
  curl -s -X PUT --location "http://localhost:8081/service/rest/v1/security/realms/active" \
      -H "Content-Type: application/json" \
      -d '[
            "NexusAuthenticatingRealm",
            "DockerToken"
          ]' \
      --basic --user admin:${NEW_PASS}

  # create a storage (so we do not rely on the default just in case we decide to switch to S3 or do some more configuration for it)
  curl -s -X POST --location "http://localhost:8081/service/rest/v1/blobstores/file" \
      -H "Content-Type: application/json" \
      -d "{
            \"name\": \"docker-store\",
            \"path\": \"$NEXUS_DATA/blobs/docker-store\"
          }" \
      --basic --user admin:${NEW_PASS}

  # start creating docker mirror-proxies:
  curl -s -X POST --location "http://localhost:8081/service/rest/v1/repositories/docker/proxy" \
      -H "Content-Type: application/json" \
      -d '{
            "name": "docker-mirror-elastic",
            "online": true,
            "storage": {
              "blobStoreName": "docker-store",
              "strictContentTypeValidation": true
            },
            "proxy": {
              "remoteUrl": "https://docker.elastic.co/",
              "contentMaxAge": 168,
              "metadataMaxAge": 168
            },
            "docker": {
              "v1Enabled": false,
              "forceBasicAuth": true,
              "httpPort": null,
              "httpsPort": null,
              "subdomain": null
            },
            "dockerProxy": {
              "indexType": "REGISTRY",
              "indexUrl": null,
              "cacheForeignLayers": false,
              "foreignLayerUrlWhitelist": [

              ]
            },
            "negativeCache": {
              "enabled": false,
              "timeToLive": 1440
            },
            "httpClient": {
              "blocked": false,
              "autoBlock": true,
              "connection": {
                "retries": null,
                "userAgentSuffix": null,
                "timeout": null,
                "enableCircularRedirects": false,
                "enableCookies": false,
                "useTrustStore": false
              },
              "authentication": null
            }
          }' \
      --basic --user admin:${NEW_PASS}

  curl -s -X POST --location "http://localhost:8081/service/rest/v1/repositories/docker/proxy" \
      -H "Content-Type: application/json" \
      -d '{
            "name": "docker-mirror-microsoft",
            "online": true,
            "storage": {
              "blobStoreName": "docker-store",
              "strictContentTypeValidation": true
            },
            "proxy": {
              "remoteUrl": "https://mcr.microsoft.com",
              "contentMaxAge": -1,
              "metadataMaxAge": -1
            },
            "docker": {
              "v1Enabled": false,
              "forceBasicAuth": true,
              "httpPort": null,
              "httpsPort": null,
              "subdomain": null
            },
            "dockerProxy": {
              "indexType": "REGISTRY",
              "indexUrl": null,
              "cacheForeignLayers": false,
              "foreignLayerUrlWhitelist": [

              ]
            },
            "negativeCache": {
              "enabled": false,
              "timeToLive": 1
            },
            "httpClient": {
              "blocked": false,
              "autoBlock": true,
              "connection": {
                "retries": null,
                "userAgentSuffix": null,
                "timeout": null,
                "enableCircularRedirects": false,
                "enableCookies": false,
                "useTrustStore": false
              },
              "authentication": null
            }
          }' \
      --basic --user admin:${NEW_PASS}

  curl -s -X POST --location "http://localhost:8081/service/rest/v1/repositories/docker/proxy" \
      -H "Content-Type: application/json" \
      -d '{
            "name": "docker-mirror-google",
            "online": true,
            "storage": {
              "blobStoreName": "docker-store",
              "strictContentTypeValidation": true
            },
            "proxy": {
              "remoteUrl": "https://mirror.gcr.io/",
              "contentMaxAge": -1,
              "metadataMaxAge": -1
            },
            "docker": {
              "v1Enabled": false,
              "forceBasicAuth": true,
              "httpPort": null,
              "httpsPort": null,
              "subdomain": null
            },
            "dockerProxy": {
              "indexType": "REGISTRY",
              "indexUrl": null,
              "cacheForeignLayers": false,
              "foreignLayerUrlWhitelist": [

              ]
            },
            "negativeCache": {
              "enabled": false,
              "timeToLive": 1
            },
            "httpClient": {
              "blocked": false,
              "autoBlock": true,
              "connection": {
                "retries": null,
                "userAgentSuffix": null,
                "timeout": null,
                "enableCircularRedirects": false,
                "enableCookies": false,
                "useTrustStore": false
              },
              "authentication": null
            }
          }' \
      --basic --user admin:${NEW_PASS}

  curl -s -X POST --location "http://localhost:8081/service/rest/v1/repositories/docker/proxy" \
      -H "Content-Type: application/json" \
      -d '{
            "name": "docker-mirror-ibm",
            "online": true,
            "storage": {
              "blobStoreName": "docker-store",
              "strictContentTypeValidation": true
            },
            "proxy": {
              "remoteUrl": "https://icr.io",
              "contentMaxAge": -1,
              "metadataMaxAge": -1
            },
            "docker": {
              "v1Enabled": false,
              "forceBasicAuth": true,
              "httpPort": null,
              "httpsPort": null,
              "subdomain": null
            },
            "dockerProxy": {
              "indexType": "REGISTRY",
              "indexUrl": null,
              "cacheForeignLayers": false,
              "foreignLayerUrlWhitelist": [

              ]
            },
            "negativeCache": {
              "enabled": false,
              "timeToLive": 1
            },
            "httpClient": {
              "blocked": false,
              "autoBlock": true,
              "connection": {
                "retries": null,
                "userAgentSuffix": null,
                "timeout": null,
                "enableCircularRedirects": false,
                "enableCookies": false,
                "useTrustStore": false
              },
              "authentication": null
            }
          }' \
      --basic --user admin:${NEW_PASS}

  # finally create a docker group repository combining all the proxies and enabling http access on port 8181:
  curl -s -X POST --location "http://localhost:8081/service/rest/v1/repositories/docker/group" \
      -H "Content-Type: application/json" \
      -d '{
            "name": "docker-mirror",
            "online": true,
            "storage": {
              "blobStoreName": "docker-store",
              "strictContentTypeValidation": true
            },
            "group": {
              "memberNames": [
                "docker-mirror-google",
                "docker-mirror-elastic",
                "docker-mirror-ibm",
                "docker-mirror-microsoft"
              ]
            },
            "docker": {
              "v1Enabled": false,
              "forceBasicAuth": false,
              "httpPort": 8181,
              "httpsPort": null,
              "subdomain": null
            }
          }' \
      --basic --user admin:${NEW_PASS}

  echo "$NEW_PASS" >> "${SONATYPE_WORK}/instance.configured"
  echo
  echo 'Finished configuring Nexus'
  echo 'About to stop the Nexus instance. It will get started as a service...'
  $NEXUS_HOME/bin/nexus stop
fi

exit $?
