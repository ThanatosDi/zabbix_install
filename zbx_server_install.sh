#!/bin/bash

# 啟動腳本參數設定
function config_setting(){
    read -p "此系統是 docker 的 container 嗎? (y/n): (預設:n)" q_indocker
    q_indocker="${q_indocker:-"n"}"

    read -p "是否更新系統套件? (y/n): (預設:y)" q_upgrade
    q_upgrade="${q_upgrade:-"y"}"

    read -p "是否安裝資料庫? (y/n): (預設:y)" q_database
    q_database="${q_database:-"y"}"
    if [[ $q_database = "Y" || $q_database = "y" ]];
    then
        echo $'欲安裝何種資料庫 (1/2): '
        select database_type in MySQL MariaDB
        do
            if [[ $database_type = "MySQL" ]];
            then
                echo "即將安裝 MySQL"
                break;
            elif [[ $database_type = "MariaDB" ]];
            then
                echo "即將安裝 MariaDB"
                break;
            fi
        done
    fi
    read -p "資料庫名稱(留空為預設): (預設:zabbix)" zabbix_db_name
    zabbix_db_name="${zabbix_db_name:-"zabbix"}"
    read -p "資料庫使用者帳號(留空為預設): (預設zabbix)" zabbix_db_username
    zabbix_db_username="${zabbix_db_username:-"zabbix"}"
    read -p "資料庫 zabbix 使用者密碼: " zabbix_db_password
    read -p "設定 zabbix 的 nginx server name: (預設: 127.0.0.1)" server_name
    server_name="${server_name:-"127.0.0.1"}"
}

# 顯示所有參數設定值
function config_show(){
    echo "==================================="
    echo "此系統是 docker 的 container 嗎?: ${q_indocker}"
    echo "是否更新系統套件?: ${q_upgrade}"
    echo "是否安裝資料庫?: ${q_database}"
    if [[ $q_database == 'y' || $q_database == "Y" ]]
    then
        echo "即將安裝資料庫: ${database_type}"
    fi
    echo "資料庫名稱: ${zabbix_db_name}"
    echo "資料庫使用者帳號: ${zabbix_db_username}"
    echo "${database_type} 資料庫 zabbix 使用者密碼: ${zabbix_db_password}"
    echo "zabbix-server 的 server name: ${server_name}"
    echo "==================================="
    read -p "請確認上方有無輸入錯誤，如無錯誤請按 [ENTER] 進入安裝程序，如錯誤請 Ctrl+C 終止程序"
}

function docker(){
    # 當環境為 docker container 時執行下方指令
    if [[ $q_indocker == "y" || $q_indocker == "Y" ]] 
    then
        echo "更新套件索引"
        apt update
        echo "安裝 sudo 套件"
        apt install sudo -y
        echo "取消自動刪除 documentation"
        sed -i "s/path-exclude=\/usr\/share\/doc\/\*/\#path-exclude=\/usr\/share\/doc\/\*/g" /etc/dpkg/dpkg.cfg.d/excludes
    fi
}

function upgrade(){
    echo "執行系統套件升級作業"
    if [[ $q_upgrade == "y" || $q_upgrade == "Y" ]] 
    then
        sudo apt update
        sudo apt upgrade -y
    fi
}

function database_install(){
    # 安裝資料庫
    case $database_type in
        "MySQL")
            echo "安裝 mysql-server"
            sudo apt install mysql-server -y
        ;;
        "MariaDB")
            echo "安裝 mariadb-server"
            sudo apt install mariadb-server -y
        ;;
    esac
}

function mysql_status_check(){
    # 判斷資料庫服務是否有啟動
    if sudo ps ax | grep -v grep | grep mysql > /dev/null
    then
        echo "檢測到資料庫服務正在運作中"
        mysql_status=true
    else
        echo "檢測到資料庫服務停止中"
        mysql_status=false
    fi
}

function zabbix_install(){
    sudo apt install wget -y
    sudo wget https://repo.zabbix.com/zabbix/5.0/ubuntu/pool/main/z/zabbix-release/zabbix-release_5.0-1+focal_all.deb \
    -O /tmp/zabbix-release_5.0-1+focal_all.deb
    sudo dpkg -i /tmp/zabbix-release*
    sudo apt update
    export DEBIAN_FRONTEND=noninteractive
    ln -fs /usr/share/zoneinfo/Asia/Taipei /etc/localtime
    sudo apt install zabbix-server-mysql zabbix-frontend-php zabbix-nginx-conf nginx -y
}

function database_insert(){
    echo "建立 Zabbix 資料庫"
    mysql_status_check
    if [ $mysql_status == "false" ]
    then
        echo "嘗試啟動資料庫伺服器服務"
        sudo service mysql start
    fi
    sudo mysql -u root -e "CREATE DATABASE IF NOT EXISTS ${zabbix_db_name} \
                           CHARACTER SET utf8 \
                           COLLATE utf8_bin;"
    sudo mysql -u root -e "CREATE USER ${zabbix_db_username}@localhost identified by '${zabbix_db_password}';"
    sudo mysql -u root -e "grant all privileges on ${zabbix_db_name}.* to ${zabbix_db_username}@localhost;"

    zcat /usr/share/doc/zabbix-server-mysql*/create.sql.gz | mysql -u${zabbix_db_username} -p${zabbix_db_password} ${zabbix_db_name}
}

function zabbix_setting(){
    sudo sed -i "s@DBName=zabbix@DBName=${zabbix_db_name}@g" /etc/zabbix/zabbix_server.conf
    sudo sed -i "s@DBUser=zabbix@DBUser=${zabbix_db_username}@g" /etc/zabbix/zabbix_server.conf
    sudo sed -i "s@\# DBPassword=@DBPassword=${zabbix_db_password}@g" /etc/zabbix/zabbix_server.conf
    sudo sed -i "s@#        listen          80;@        listen          80;@g" /etc/zabbix/nginx.conf
    sudo sed -i "s@#        server_name     example.com;@        server_name     ${server_name};@g" /etc/zabbix/nginx.conf
    sudo sed -i "s@; php_value\[date.timezone\] = Europe\/Riga@php_value\[date.timezone\] = Asia\/Taipei@g" /etc/zabbix/php-fpm.conf
}

function start(){
    if [[ $q_indocker == "y" || $q_indocker == "Y" ]] 
    then
        sudo service php7.4-fpm restart
        sudo service zabbix-server start
        sudo service nginx restart
    else
        sudo systemctl restart php7.4-fpm.service
        sudo systemctl start zabbix-server
        sudo systemctl restart nginx
    fi
    echo "goto http://${server_name}/ setting Zabbix!"
}





installer(){
    docker
    upgrade
    database_install
    zabbix_install
    database_insert
    zabbix_setting
}

config_setting
config_show
installer
start
