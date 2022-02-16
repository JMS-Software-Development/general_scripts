sudo apt-get update
sudo apt-get install postgresql postgresql-contrib
sudo apt-get install libpq-dev python3-dev
pip install psycopg2

PASSWORD=$(< /dev/urandom tr -dc _A-Z-a-z-0-9 | head -c${1:-24};echo;)
sudo -u postgres createuser $POSTGRES_USER
sudo -u postgres createdb $POSTGRES_DB
sudo -u postgres psql -c "ALTER USER $POSTGRES_USER WITH ENCRYPTED PASSWORD $PASSWORD;"
sudo -u postgres psql -c "GRANT ALL privileges on database $POSTGRES_DB to $POSTGRES_USER;"

echo """
DATABASES = {
    'default': {
        'ENGINE': 'django.db.backends.postgresql_psycopg2',
        'NAME': "$POSTGRES_DB",
        'USER': "$POSTGRES_USER",
        'PASSWORD': "$PASSWORD",
        'HOST': 'localhost',
        'PORT': '',
    }
}
""" >> /home/$USER_NAME/$PROJECT_NAME/$PROJECT_NAME/production.py
