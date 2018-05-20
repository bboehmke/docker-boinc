#!/bin/bash
# inspired by https://github.com/sameersbn/docker-gitlab
set -e

[[ $DEBUG == true ]] && set -x

BOINC_URL=${BOINC_URL:-http://127.0.0.1}
BOINC_PROJECT_SHORT=${BOINC_PROJECT_SHORT:-boinc}
BOINC_PROJECT_LONG=${BOINC_PROJECT_LONG:-Boinc@Home}

finalize_database_parameters() {
  DB_HOST=${DB_HOST:-${MYSQL_PORT_3306_TCP_ADDR}}

  # support for linked sameersbn/mysql image
  DB_USER=${DB_USER:-${MYSQL_ENV_DB_USER}}
  DB_PASS=${DB_PASS:-${MYSQL_ENV_DB_PASS}}
  DB_NAME=${DB_NAME:-${MYSQL_ENV_DB_NAME}}

  # support for linked orchardup/mysql and enturylink/mysql image
  # also supports official mysql image
  DB_USER=${DB_USER:-${MYSQL_ENV_MYSQL_USER}}
  DB_PASS=${DB_PASS:-${MYSQL_ENV_MYSQL_PASSWORD}}
  DB_NAME=${DB_NAME:-${MYSQL_ENV_MYSQL_DATABASE}}

  if [[ -z ${DB_HOST} ]]; then
    echo
    echo "ERROR: "
    echo "  Please configure the database connection."
    echo "  Cannot continue without a database. Aborting..."
    echo
    return 1
  fi

  # set default user and database
  DB_USER=${DB_USER:-boinc}
  DB_NAME=${DB_NAME:-password}
}

check_database_connection() {
  prog="mysqladmin -h ${DB_HOST} -u ${DB_USER} ${DB_PASS:+-p$DB_PASS} status"
  
  timeout=60
  while ! ${prog} >/dev/null 2>&1
  do
    timeout=$(expr $timeout - 1)
    if [[ $timeout -eq 0 ]]; then
      echo
      echo "Could not connect to database server. Aborting..."
      return 1
    fi
    echo -n "."
    sleep 1
  done
  echo
}

initProject() {
  # initial project
  if [[ ! -f "${PROJECT_PATH}/config.xml" ]]; then
    # "improve" already installed detection
    sed 's;os.path.exists(options.project_root);os.path.exists(os.path.join(options.project_root, "config.xml"));g' -i ${ROOT_PATH}/tools/make_project
    sed 's;os.path.exists(self.dir());os.path.exists(os.path.join(self.dir(), "config.xml"));g' -i ${ROOT_PATH}/py/Boinc/setup_project.py
    sed 's;cursor.execute("create database %s"%config.db_name);;g' -i ${ROOT_PATH}/py/Boinc/database.py

    ${ROOT_PATH}/tools/make_project \
      --srcdir ${ROOT_PATH} \
      --url_base "${BOINC_URL}" \
      --project_host "${BOINC_PROJECT_SHORT}" \
      --db_host $DB_HOST \
      --db_user $DB_USER \
      --db_name $DB_NAME \
      --db_passwd $DB_PASS \
      --no_query \
      --project_root ${PROJECT_PATH} \
      "${BOINC_PROJECT_SHORT}" "${BOINC_PROJECT_LONG}"

    sed -i -e 's/Deny from all/Require all denied/g' \
              -e 's/Allow from all/Require all granted/g' \
              -e '/Order/d' ${PROJECT_PATH}/*.httpd.conf 

    sed 's;REPLACE WITH PROJECT NAME;'"${BOINC_PROJECT_LONG}"';g' -i ${PROJECT_PATH}/html/project/project.inc

  else
    # upgrade project
    yes | ${ROOT_PATH}/tools/upgrade \
      --srcdir ${ROOT_PATH} \
      ${PROJECT_PATH}
  fi

  chown -R boincadm:boincadm ${PROJECT_PATH}

  ln -sf ${PROJECT_PATH}/${BOINC_PROJECT_SHORT}.httpd.conf /etc/apache2/sites-enabled/

  echo "*/5 * * * *   boincadm   cd ${PROJECT_PATH}/ ; ${PROJECT_PATH}/bin/start --cron" > /etc/cron.d/boinc
}

appCheck () {
  # configure database and check connection
  finalize_database_parameters
  check_database_connection
}

appStart () {
  # prepare project
  initProject

  # start application
  su -c "${PROJECT_PATH}/bin/start" -s /bin/sh boincadm

  # start supervisord
  echo "Starting supervisord..."
  exec /usr/bin/supervisord -n -c /etc/supervisor/supervisord.conf
}


appHelp () {
  echo "Available options:"
  echo " app:start          - Starts postfix and dovecot (default)"
  echo " app:check          - Checks the MySQL connection"
  echo " [command]          - Execute the specified linux command eg. bash."
}

case ${1} in
  app:start|app:check)

    case ${1} in
      app:start)
        appCheck
        appStart
      ;;
      app:check)
        appInit
      ;;
    esac
    
    ;;
  app:help)
    appHelp
  ;;
  *)
    exec "$@"
  ;;
esac
