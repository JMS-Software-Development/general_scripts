
pg_dump -h localhost -U $POSTGRES_USER -F p $POSTGRES_DB > /home/$USER_NAME/database-backups/db_backup_$POSTGRES_DB_$(date +%Y-%m-%d)
find /home/$USER_NAME/database-backups/* -mtime +7