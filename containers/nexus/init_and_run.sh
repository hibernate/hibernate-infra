#!/bin/bash -e

if [ -e ${NEXUS_DATA}/instance.configured ]
then
  echo 'Nexus data already contains initial configuration, skipping initialisation.'
else
  echo "Nexus starting for the first time. No initial configuration applied yet."
  echo "Nexus will start, get preconfigured and then restart."

  /opt/sonatype/nexus/bin/nexus start

  until curl -s -f -o /dev/null "http://localhost:8081/"
    do
      echo 'Not ready yet'
      sleep 5
    done

  # initial password is stored in a /nexus-data/admin.password
  INIT_PASS=$(cat ${NEXUS_DATA}/admin.password)
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
      -d '{
            "name": "docker-store",
            "path": "/nexus-data/blobs/docker-store"
          }' \
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

  echo 'configured' >> ${NEXUS_DATA}/instance.configured
  echo 'Finished configuring Nexus'
  echo 'About to restart the Nexus instance'
  /opt/sonatype/nexus/bin/nexus stop
fi

exec /opt/sonatype/nexus/bin/nexus run

exit $?
