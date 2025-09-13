#!/bin/bash
#set -e


# --- Configuration ---
ENV_FILE="${PODMAN_DATA_DIR}/.env"
POD_NAME="overleaf-pod"
PODMAN_DATA_DIR="${HOME}/podman_data"
POD_DIR="${PODMAN_DATA_DIR}/overleaf-pod"

POD_OVERLEAF_DIR="${POD_DIR}/overleaf"
POD_REDIS_DIR="${POD_DIR}/redis"
POD_MONGO_DIR="${POD_DIR}/mongo"

CONTAINER_OVERLEAF_NAME="overleaf-app"
CONTAINER_REDIS_NAME="redis-overleaf"
CONTAINER_MONGO_NAME="mongo-overleaf"

mkdir -p ${POD_MONGO_DIR}/db
mkdir -p ${POD_MONGO_DIR}/configdb
mkdir -p ${POD_MONGO_DIR}/init
mkdir -p ${POD_REDIS_DIR}/data
mkdir -p ${POD_OVERLEAF_DIR}/data

# --- Mongo Init Script ---
cat > "${POD_MONGO_DIR}/init/mongo-init.js" << EOF
try {
  rs.status();
  console.log("Replica set already exists, skipping initialization.");
} catch (e) {
  console.log("Initializing new replica set...");
  rs.initiate({ _id: "overleaf", members: [{ _id: 0, host: "127.0.0.1:27017" }] });
}
EOF

# ---> Create the healthcheck.js file <---
cat > "${POD_MONGO_DIR}/init/healthcheck.js" <<EOF
const result = db.adminCommand({ ping: 1 });
if (result.ok === 1) {
  // Exit with 0 for success
  quit(0);
} else {
  // Exit with 1 for failure
  quit(1);
}
EOF

# --- Deploy ---
echo "Stopping and removing existing pod..."
systemctl --user stop pod-overleaf-pod.service
podman pod stop "${POD_NAME}" || true
podman pod rm "${POD_NAME}" || true

echo "Creating new pod: ${POD_NAME}"
podman pod create --name "${POD_NAME}" -p "8080:80"

echo "Starting MongoDB container..."
podman run -d --pod "${POD_NAME}" --name "${CONTAINER_MONGO_NAME}" \
  --restart=always \
  --memory=128m \
  --cpu-shares=256 \
  --volume="${POD_MONGO_DIR}/db:/data/db:Z" \
  --volume="${POD_MONGO_DIR}/configdb:/data/configdb:Z" \
  --volume="${POD_MONGO_DIR}/init/mongo-init.js:/docker-entrypoint-initdb.d/init.js:Z" \
  --volume="${POD_MONGO_DIR}/init/healthcheck.js:/healthcheck.js:ro,Z" \
  --env MONGO_INITDB_DATABASE=overleaf \
  --health-cmd='["CMD-SHELL", "mongosh --norc --quiet --file /healthcheck.js"]' \
  --health-interval=30s \
  --health-start-period=10s \
  mongo:6.0 --replSet overleaf

echo "Starting Redis container..."
podman run -d --pod "${POD_NAME}" --name "${CONTAINER_REDIS_NAME}" \
  --restart=always \
  --memory=128m \
  --cpu-shares=256 \
  --health-cmd='["CMD-SHELL", "redis-cli ping | grep PONG"]' \
  --health-interval=30s \
  --health-start-period=10s \
  --volume="${POD_REDIS_DIR}/data:/data:Z" \
  docker.io/library/redis:8-alpine redis-server --save 60 1 --loglevel warning

echo "Starting Overleaf container..."
# Required for Overleaf to write to the volume
podman run -d --pod "${POD_NAME}" --name "${CONTAINER_OVERLEAF_NAME}" \
  --restart=unless-stopped \
  --memory=2048m \
  --cpu-shares=1024 \
  --env OVERLEAF_MONGO_URL="mongodb://localhost:27017/overleaf?replicaSet=overleaf" \
  --env OVERLEAF_REDIS_HOST="localhost" \
  --env OVERLEAF_APP_NAME="Overleaf" \
  --env ENABLED_LINKED_FILE_TYPES="project_file,project_output_file" \
  --env ENABLE_CONVERSIONS="true" \
  --env EMAIL_CONFIRMATION_DISABLED="true" \
  --env OVERLEAF_SITE_URL="http://overleaf.bluewave.work" \
  --env OVERLEAF_ADMIN_EMAIL="medzarka@gmail.com" \
  --env OVERLEAF_DISABLE_SIGNUPS="true" \
  --volume="${POD_OVERLEAF_DIR}/data:/var/lib/overleaf:Z" \
  --label homepage.group="Production" \
  --label homepage.name="Overleaf" \
  --label homepage.icon="overleaf" \
  --label homepage.href="http://overleaf.bluewave.work" \
  --label homepage.description="Collaborative LaTeX Editor" \
  --health-cmd='["CMD-SHELL", "curl -f http://localhost:80 || exit 1"]' \
  --health-interval=1m \
  --health-start-period=30s \
  --health-retries=3 \
  --health-timeout=10s \
  sharelatex/sharelatex:latest

echo "Deployment complete."



# Since public sign-ups are disabled in the Overleaf container's configuration (`OVERLEAF_DISABLE_SIGNUPS="true"`), new users must be created manually by an administrator. There are two ways to do this.
#
#  1. Get a shell inside the container**: 
#    ```bash
#    podman exec -it overleaf-app /bin/bash
#    ```
#  2. Find the User Creation Script: The location of the administrative script can change with new versions of Overleaf. To ensure the command is always correct, first find the script's exact path. Thus, we can run the `find` command to locate the script: 
#    ```bash
#    find / -name "create-user.js". 
#    ```
#
#  As of this writing, it is:
#
#    ```bash
#    /overleaf/services/web/modules/server-ce-scripts/scripts/create-user.js
#    ``` 
#
#  3. Create the User: Run the `node` command using the path you just found. Note that this script only requires the email address:
#
#  ```bash
#  cd /overleaf/services/web && node modules/server-ce-scripts/scripts/create-user --admin --email=medzarka@gmail.com --password='YourStrongPassword'
#  ```
#
#  4. Exit the container: After the command runs successfully, you can leave the container shell: `exit`


# To overcome the WARNING Memory overcommit, we run:  
# ```bash
# echo 'vm.overcommit_memory = 1' | sudo tee /etc/sysctl.d/99-redis.conf
# ```
# or the following to get immediate effect:
# ```bash
# sudo sysctl -w vm.overcommit_memory=1
#



# Generate the files for the pod and its containers
podman generate systemd --new --name overleaf-pod --files
# Move all generated service files
mv 
mv pod-${POD_NAME}.service ~/.config/systemd/user/
mv container-${CONTAINER_MONGO_NAME}.service ~/.config/systemd/user/
mv container-${CONTAINER_REDIS_NAME}.service ~/.config/systemd/user/
mv container-${CONTAINER_OVERLEAF_NAME}.service ~/.config/systemd/user/

systemctl --user daemon-reload
systemctl --user enable --now pod-overleaf-pod.service