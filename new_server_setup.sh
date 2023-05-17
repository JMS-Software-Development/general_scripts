# exit when any command fails
set -e

# keep track of the last executed command
trap 'last_command=$current_command; current_command=$BASH_COMMAND' DEBUG
# echo an error message before exiting
trap 'echo "\"${last_command}\" command filed with exit code $?."' EXIT

if [ "${SERVER_NAME}" ]; then
    echo "Found existing server, updating..."
else
    echo "Setting up new server..."
fi

if ! [ "${SERVER_NAME}" ]; then
    read -p "Enter server name (eg anansiwebdevelopment.nl): " SERVER_NAME
    SERVER_NAME=${SERVER_NAME:-anansiwebdevelopment.nl}
fi

if ! [ "${PROJECT_NAME}" ]; then
    read -p "Enter project name: " PROJECT_NAME
    PROJECT_NAME=${PROJECT_NAME:-anansi}
fi

if ! [ "${USER_NAME}" ]; then
    read -p "Enter username: " USER_NAME
    USER_NAME=${USER_NAME:-anansi}
fi

if ! [ "${BRANCH}" ]; then
    read -p "Enter deploy branch: " BRANCH
    BRANCH=${BRANCH:-main}
fi

if ! [ "${SETUP_POSTGRES}" ]; then
    read -p "Should this be a postgres server? (y/N): " SETUP_POSTGRES
    SETUP_POSTGRES=${SETUP_POSTGRES:-n}
fi

read -p "Setup cerbot for HTTPS? (y/N): " SETUP_CERTBOT
SETUP_CERTBOT=${SETUP_CERTBOT:-n}

read -p "Setup cerbot nodejs+npm? (y/N): " SETUP_NODE
SETUP_NODE=${SETUP_NODE:-n}

# add project + required settings name to environment
echo PROJECT_NAME=$PROJECT_NAME >> /etc/environment
echo USE_NODE=$SETUP_NODE >> /etc/environment
echo SETUP_POSTGRES=$SETUP_POSTGRES >> /etc/environment
echo USER_NAME=$USER_NAME >> /etc/environment
echo SERVER_NAME=$SERVER_NAME >> /etc/environment
echo BRANCH=$BRANCH >> /etc/environment

apt update
apt install -y nginx python3-venv python3-wheel gcc python3-dev redis-server pipenv libpq-dev git

if [ $SETUP_NODE = "y" ]
then
    apt install -y nodejs npm
fi

# Setup new user
adduser --disabled-password --gecos "" $USER_NAME
echo "$USER_NAME ALL=(ALL) NOPASSWD: ALL" | sudo EDITOR='tee -a' visudo
usermod -aG sudo $USER_NAME

mkdir /home/$USER_NAME/.ssh
cp /root/.ssh/authorized_keys /home/$USER_NAME/.ssh/authorized_keys
chown -R $USER_NAME:$USER_NAME /home/$USER_NAME/.ssh
systemctl restart sshd

# Setup project dirs and config 
mkdir -p /home/$USER_NAME/$PROJECT_NAME/$PROJECT_NAME
mkdir -p /home/$USER_NAME/$PROJECT_NAME-logs/
mkdir -p /home/$USER_NAME/database-backups/

# Setup Firewall
apt install -y ufw
ufw default deny
ufw allow 443
ufw allow 80
ufw allow 22
ufw enable


# Setup production.py
PROD_FILE="/home/$USER_NAME/$PROJECT_NAME/$PROJECT_NAME/production.py"
if ! test -f "$PROD_FILE"
then
    # If the prod file does not yet exist 
    echo "
import os

ALLOWED_HOSTS = ['$SERVER_NAME']
DEBUG = False
SECRET_KEY = os.environ.get('DJANGO_SECRET_KEY', '!@3m(1&m_y++@@-vl%eu*ai-vgh14!m1=jsn(o*xhhbbml-&5o')

STATIC_ROOT = \"/var/www/$PROJECT_NAME/static\"
#STATICFILES_DIRS = [
#    os.path.join(BASE_DIR, \"static\"),
#]

LOG_BASE_PATH = \"/home/$USER_NAME/$PROJECT_NAME-logs/\"
LOGGING = {
    'version': 1,
    'disable_existing_loggers': False,
    'formatters': {
        'verbose': {
            'format': '{asctime} [{levelname}] {filename}:{lineno}:{funcName} {message}',
            'style': '{',
        },
        'simple': {
            'format': '{message}',
            'style': '{',
        },
    },
    'handlers': {
        'file': {
            'level': 'DEBUG',
            'class': 'logging.FileHandler',
            'filename': LOG_BASE_PATH + './debug.log',
            'formatter': 'verbose',
        },
        'console': {
            'level': 'INFO',
            'class': 'logging.StreamHandler',
            'formatter': 'simple',
        },
    },
    'loggers': {
        '': {
            'handlers': ['console', 'file'],
            'level': 'DEBUG',
        },
    },
}

    " > /home/$USER_NAME/$PROJECT_NAME/$PROJECT_NAME/production.py
fi

cd /home/$USER_NAME/$PROJECT_NAME/
# pipenv 
# python3 -m venv /home/$USER_NAME/venv

# source /home/$USER_NAME/venv/bin/activate
pipenv install wheel daphne django

# Create repository
mkdir -p /home/$USER_NAME/$PROJECT_NAME.git
cd /home/$USER_NAME/$PROJECT_NAME.git
git init --bare

# Create django secret key
cd /home/$USER_NAME/$PROJECT_NAME
DJANGO_KEY=$(pipenv run python -c 'from django.core.management.utils import get_random_secret_key; print(get_random_secret_key())')

# Create hook
echo "Creating deployment hook"
cd /home/$USER_NAME/$PROJECT_NAME.git/hooks
wget https://raw.githubusercontent.com/JMS-Software-Development/general_scripts/master/post-receive -O /home/$USER_NAME/$PROJECT_NAME.git/hooks/post-receive
sed -i "s/\$USER_NAME/$USER_NAME/g" /home/$USER_NAME/$PROJECT_NAME.git/hooks/post-receive
chmod +x post-receive
chown -R $USER_NAME:$USER_NAME /home/$USER_NAME/

# Create services
echo "Creating daphne service"
wget https://raw.githubusercontent.com/JMS-Software-Development/general_scripts/master/django-daphne.service -O /etc/systemd/system/django-daphne.service
sed -i "s/\$DJANGO_SECRET/$DJANGO_KEY/g" /etc/systemd/system/django-daphne.service
sed -i "s/\$PROJECT_NAME/$PROJECT_NAME/g" /etc/systemd/system/django-daphne.service
sed -i "s/\$SERVER_NAME/$SERVER_NAME/g" /etc/systemd/system/django-daphne.service
sed -i "s/\$USER_NAME/$USER_NAME/g" /etc/systemd/system/django-daphne.service
echo "Created daphne service"
echo 

# Celery and celerybeat
# mkdir -p /etc/conf.d/
# mkdir -p /var/log/celery
# mkdir -p /var/log/celerybeat
# chown $USER_NAME:$USER_NAME /var/log/celery
# chown $USER_NAME:$USER_NAME /var/log/celerybeat
# echo "Creating celery service"
# wget https://raw.githubusercontent.com/MedianaSoftware/general_scripts/master/celery.service -O /etc/systemd/system/celery.service
# wget https://raw.githubusercontent.com/MedianaSoftware/general_scripts/master/celery -O /etc/conf.d/celery
# echo 

# echo "Creating celerybeat service"
# wget https://raw.githubusercontent.com/MedianaSoftware/general_scripts/master/celerybeat.service -O /etc/systemd/system/celerybeat.service
# wget https://raw.githubusercontent.com/MedianaSoftware/general_scripts/master/celerybeat -O /etc/conf.d/celerybeat
# echo 

# Set up nginx
echo "Setting up nginx"
rm /etc/nginx/sites-enabled/default
wget https://raw.githubusercontent.com/JMS-Software-Development/general_scripts/master/nginx-config -O /etc/nginx/sites-available/$PROJECT_NAME
sed -i "s/\$PROJECT_NAME/$PROJECT_NAME/g" /etc/nginx/sites-available/$PROJECT_NAME
sed -i "s/\$SERVER_NAME/$SERVER_NAME/g" /etc/nginx/sites-available/$PROJECT_NAME

ln -s /etc/nginx/sites-available/$PROJECT_NAME /etc/nginx/sites-enabled/

nginx -t
systemctl restart nginx

mkdir -p "/var/www/$PROJECT_NAME/media/"
mkdir -p "/var/www/$PROJECT_NAME/static/"
chown -R $USER_NAME:$USER_NAME "/var/www/$PROJECT_NAME/static/"
chown -R $USER_NAME:$USER_NAME "/var/www/$PROJECT_NAME/static/"

if [ $SETUP_POSTGRES = "y" ]
then
    echo "Installing postgres..."
    wget https://raw.githubusercontent.com/JMS-Software-Development/general_scripts/master/setup_postgres.sh -O /home/$USER_NAME/setup_postgres.sh
    chmod +x /home/$USER_NAME/setup_postgres.sh
    POSTGRES_USER="$PROJECT_NAME"_user POSTGRES_DB="$PROJECT_NAME" . /home/$USER_NAME/setup_postgres.sh
fi

if [ $SETUP_CERTBOT = "y" ]
then
    echo "Setting up certbot..."
    wget https://raw.githubusercontent.com/JMS-Software-Development/general_scripts/master/setup_certbot.sh -O /home/$USER_NAME/setup_certbot.sh
    bash /home/$USER_NAME/setup_certbot.sh
fi

systemctl daemon-reload
systemctl enable django-daphne
# systemctl enable celery
# systemctl enable celerybeat
systemctl enable redis-server

chown -R $USER_NAME:$USER_NAME /home/$USER_NAME/$PROJECT_NAME

echo "Dont forget to add the following to settings.py:"
echo """
try:
    from .local import * 
except ImportError:
    try:
        from .staging import *
    except ImportError:
        try:
            from .production import *
        except ImportError:
            pass
"""

# Receive code
echo ""
echo "Then, please run the following command:"
echo "git remote add deploy ssh://$USER_NAME@$SERVER_NAME/home/$USER_NAME/$PROJECT_NAME.git/ && git push deploy"
echo "in your local repository."
