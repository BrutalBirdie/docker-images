#!/bin/bash
set -o nounset
set -o pipefail
set -o errexit

basedir=$(pwd)

. /tuf/functions.inc.sh

echo "=> Setup Github CLI"
L_github_login

echo "=> Configure git"
L_git_configure

# If we already are in a directory with a git repository we assume it's the
# update repository and fetch the latest commit. If we are not in a git
# repository we create a new one and pull the upstream repository
if [[ ! -d .git ]]; then
  echo "=> Initially checkout repository"
  L_git_init
fi

echo "=> Update repository version"
L_git_update

case "$1" in
  "bash")
      /bin/bash
      ;;
  "update-timestamp")
      echo "=> TUF Updation timestamp"
      $TUF timestamp
      $TUF commit
      L_git_add_and_commit "Update timestamp"
      ;;
  "prepare-release")
      sed "s/\$VERSION/${UPDATE_VERSION}/g" $basedir/templates/update-info-4.json | tee /tmp/update-info.json
      cat <<< $(jq '.["description"] = "'"${UPDATE_DESCRIPTION}"'"' /tmp/update-info.json) > /tmp/update-info.json
      cat <<< $(jq '.["infourl"]["url"] = "'"${UPDATE_INFO_URL}"'"' /tmp/update-info.json) > /tmp/update-info.json
      cat <<< $(jq '.["infourl"]["title"] = "'"${UPDATE_INFO_TITLE}"'"' /tmp/update-info.json) > /tmp/update-info.json
      cat <<< $(jq '.["name"] = "'"${UPDATE_NAME}"'"' /tmp/update-info.json) > /tmp/update-info.json
      cat <<< $(jq '.["version"] = "'"${UPDATE_VERSION}"'"' /tmp/update-info.json) > /tmp/update-info.json
      $TUF add --custom="$(jq -c '.' /tmp/update-info.json)"
      L_git_add_and_commit "Prepare ${UPDATE_VERSION}"
      ;;
  "sign-release")
      $TUF sign targets.json
      L_git_add_and_commit "Sign Release ${GIT_TARGET_BRANCH_NAME}"
      ;;
  "release")
      $TUF snapshot
      L_git_add_and_commit "Release: ${GIT_TARGET_BRANCH_NAME}"
      L_github_create_and_merge_pr "Release: ${GIT_TARGET_BRANCH_NAME}"
      ;;
  "create-key")
      tmpfile=$(mktemp)
      $TUF gen-key --expires=548 ${SIGNATURE_ROLE} | tee $tmpfile
      keyid=$(cat $tmpfile | awk '{print $6}')

      jq ". + {\"${keyid}\":\"${SIGNATURE_ROLE_NAME}\"}" < metadata/keys.json > $tmpfile
      mv $tmpfile metadata/keys.json

      jq ". + {\"${keyid}\":\"${SIGNATURE_ROLE_NAME}\"}" < metadata/keys.json > $tmpfile
      mv $tmpfile metadata/keys.json

      if [ "${SIGNATURE_ROLE}" == "root" ] || [ "${SIGNATURE_ROLE}" == "targets"  ]; then
        jq ".signed.roles.snapshot.keyids += [\"${keyid}\"]" < staged/root.json > $tmpfile
        mv $tmpfile staged/root.json
      fi

      $TUF payload root.json > staged/root.json.payload
      L_git_add_and_commit "Prepare key for Role ${SIGNATURE_ROLE} by ${SIGNATURE_ROLE_NAME}"
      ;;
  "sign-key")
      $TUF sign-payload --role=${SIGNATURE_ROLE} staged/${SIGNATURE_ROLE}.json.payload > staged/${SIGNATURE_ROLE}.json.sigs.$RANDOM
      L_git_add_and_commit "Signed signature key"
      ;;
  "commit-key")
      jq -s add staged/${SIGNATURE_ROLE}.json.sigs.* > staged/${SIGNATURE_ROLE}.json.sigs
      $TUF add-signatures --signatures staged/${SIGNATURE_ROLE}.json.sigs ${SIGNATURE_ROLE}.json
      rm staged/${SIGNATURE_ROLE}.json.*
      $TUF snapshot
      L_git_add_and_commit "Add signature key"
      L_github_create_and_merge_pr "Add signature key"
      ;;
  *)
      $TUF "$1"
      ;;
esac
