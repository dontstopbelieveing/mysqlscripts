#Data archival using pt-archiver for non partitioned tables

#!/usr/bin/bash

#declaring a associative array
declare -A tables
host=host
database=air_prod_110
slave="10.146.84.154"
repl_password="password"
master_password="password"
SSL_DSN=";mysql_ssl=1;ssl_mode=VERIFY_CA;mysql_ssl_ca_file=/tmp/hrz-mysql-client-ca.pem"
slave_SSL_DSN=";mysql_ssl=1;ssl_mode=VERIFY_CA"
log_dir=/home/mysql/scripts/logs

#put table-column name into array
#tables['celery_taskmeta']='date_done'
tables['dag_run']='execution_date'
tables['job']='end_date'
#tables['log']='execution_date'
#tables['task_fail']='end_date'
tables['task_instance']='end_date'
#tables['xcom']='execution_date'
#tables['iris_history']='execution_date'

#save today's date
today_date=`date +%s`

for k in "${!tables[@]}"; do
        archive="${k}_archive"
        mysql -u archiver -p$master_password  air_prod_110 -h $host --ssl-ca=/tmp/hrz-mysql-client-ca.pem -vv -e "CREATE TABLE IF NOT EXISTS $archive like $k"
done


for k in "${!tables[@]}"; do
        archive="${k}_archive"
        pt-archiver \
        --source h=$host$SSL_DSN,D=$database,t=$k,u=archiver \
        --dest h=$host$SSL_DSN,D=$database,t="$archive",u=archiver \
        --password=$master_password \
        --bulk-delete \
        --limit=1000 \
        --bulk-insert \
        --check-interval 60 \
        --port 3115 \
        --progress=10000 \
        --check-slave-lag h=$slave,u=archiver,p=$master_password \
        --max-lag=300 \
        --sentinel="/tmp/pause-pt-archiver" \
        --charset=utf8 \
        --sleep 1 \
        --statistics \
        --where "${tables[$k]} < date_sub(from_unixtime($today_date), interval 30 day)" | while IFS= read -r line; do printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$line"; done | tee -a $log_dir/airflow_archive.log
done
