sudo apt-get update
sudo apt-get install postgresql postgresql-contrib
sudo apt-get install libpq-dev python3-dev
pip install psycopg2

PASSWORD=$(< /dev/urandom tr -dc _A-Z-a-z-0-9 | head -c${1:-24};echo;)
sudo -u postgres createuser $POSTGRES_USER
sudo -u postgres createdb $POSTGRES_DB
sudo -u postgres psql -c "ALTER USER $POSTGRES_USER WITH ENCRYPTED PASSWORD '$PASSWORD';"
sudo -u postgres psql -c "GRANT ALL privileges on database $POSTGRES_DB to $POSTGRES_USER;"

# Setup production.py
echo """
DATABASES = {
    'default': {
        'ENGINE': 'django.db.backends.postgresql_psycopg2',
        'NAME': '$POSTGRES_DB',
        'USER': '$POSTGRES_USER',
        'PASSWORD': '$PASSWORD',
        'HOST': 'localhost',
        'PORT': '',
    }
}
""" >> /home/$USER_NAME/$PROJECT_NAME/$PROJECT_NAME/production.py

# Create pgpass file
echo "localhost:5432:$POSTGRES_DB:$POSTGRES_USER:$PASSWORD" > /home/$USER_NAME/.pgpass
chmod 600 /home/$USER_NAME/.pgpass

# Create database backup script
BACKUP_SCRIPT="/home/$USER_NAME/backup_database.sh"
echo '#!/bin/bash' > $BACKUP_SCRIPT
echo """
pg_dump -F p $POSTGRES_DB > "/home/$USER_NAME/database-backups/db_backup_${POSTGRES_DB}_$(date +%Y-%m-%d)"
find /home/$USER_NAME/database-backups/* -mtime +7 -delete
""" >> $BACKUP_SCRIPT
chmod +x $BACKUP_SCRIPT

# Schedule database backup script to run every day
crontab -l > mycron
echo "0 5 * * * $BACKUP_SCRIPT" >> mycron
crontab mycron
rm mycron
