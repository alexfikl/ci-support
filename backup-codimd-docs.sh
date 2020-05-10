#! /bin/bash

git clone https://github.com/codimd/cli.git codimd-cli
CODIMD=$(pwd)/codimd-cli/bin/codimd

git clone "$CI_REPOSITORY_URL" codimd-backup-subrepo
cd codimd-backup-subrepo
git checkout master

export CODIMD_SERVER='https://codimd.tiker.net'
$CODIMD login --email inform+codibackup@tiker.net "$CODIMD_PASSWORD"
while read -r DOCID FILEPATH; do
    echo "Reading note $DOCID into $FILEPATH"
    echo "**DO NOT EDIT**" > "$FILEPATH"
    echo "This file will be automatically overwritten. " >> "$FILEPATH"
    echo "Instead, edit the file at ${CODIMD_SERVER}/${DOCID} " >> "$FILEPATH"
    echo "**DO NOT EDIT**" >> "$FILEPATH"
    echo "" > "$FILEPATH"
    $CODIMD export --md "$DOCID" "-" >> "$FILEPATH"
    git add "$FILEPATH"
done < .codimd-backup.txt

if [[ `git status --porcelain --untracked-files=no ` ]]; then
  # There are changes in the index
  eval $(ssh-agent)
  trap "kill $SSH_AGENT_PID" EXIT
  echo "${CODIMD_BACKUP_PUSH_KEY}" > id_codimd_backup_push
  chmod 600 id_codimd_backup_push
  ssh-add id_codimd_backup_push
  git config --global user.name "CodiMD backup service"
  git config --global user.email "inform@tiker.net"
  git commit -m "Automatic update from CodiMD: $(date)"
  mkdir -p ~/.ssh
  echo -e "Host gitlab.tiker.net\n\tStrictHostKeyChecking no\n" >> ~/.ssh/config
  git push git@gitlab.tiker.net:${CI_PROJECT_PATH}.git master
fi
