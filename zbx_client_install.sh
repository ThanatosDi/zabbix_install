#!/bin/bash

# 啟動腳本參數設定
function config_setting(){
    read -p "此系統是 docker 的 container 嗎? (y/n): (預設:n)" q_indocker
    q_indocker="${q_indocker:-"n"}"

    read -p "是否更新系統套件? (y/n): (預設:y)" q_upgrade
    q_upgrade="${q_upgrade:-"y"}"

    read -p "Zabbix Server IP 位置 : (預設:127.0.0.1)" q_server_ip
    q_server_ip="${q_server_ip:-"127.0.0.1"}"

    read -p "Zabbix Client Hostname: " q_client_hostname
    read -p "TLS PSK Identity PSK唯一名稱設定: " q_psk_identity

}

function config_show(){
    echo "==================================="
    echo "此系統是 docker 的 container 嗎?: ${q_indocker}"
    echo "是否更新系統套件?: ${q_upgrade}"
    echo "Zabbix Server IP 位置: ${q_server_ip}"
    echo "Zabbix Client Hostname: ${q_client_hostname}"
    echo "PSK Identity: ${q_psk_identity}"
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

function zabbix_client_install(){
    sudo apt install wget -y
    sudo wget https://repo.zabbix.com/zabbix/5.0/ubuntu/pool/main/z/zabbix-release/zabbix-release_5.0-1+focal_all.deb \
    -O /tmp/zabbix-release_5.0-1+focal_all.deb
    sudo dpkg -i /tmp/zabbix-release*
    sudo apt update
    sudo apt install zabbix-agent -y
}

function zabbix_client_setting(){
    # 建立 PSK 金鑰
    sudo sh -c "openssl rand -hex 32 > /etc/zabbix/zabbix_agentd.psk"
    psk=`cat /etc/zabbix/zabbix_agentd.psk`
    # 修改 zabbix_agentd 設定檔
    sudo sed -i "s@Server=127.0.0.1@Server=${q_server_ip}@g" /etc/zabbix/zabbix_agentd.conf
    sudo sed -i "s@ServerActive=127.0.0.1@ServerActive=${q_server_ip}@g" /etc/zabbix/zabbix_agentd.conf
    sudo sed -i "s@Hostname=Zabbix server@Hostname=${q_client_hostname}@g" /etc/zabbix/zabbix_agentd.conf
    sudo sed -i "s@\# TLSConnect=unencrypted@TLSConnect=psk@g" /etc/zabbix/zabbix_agentd.conf
    sudo sed -i "s@\# TLSAccept=unencrypted@TLSAccept=psk@g" /etc/zabbix/zabbix_agentd.conf
    sudo sed -i "s@\# TLSPSKIdentity=@TLSPSKIdentity=${q_psk_identity}@g" /etc/zabbix/zabbix_agentd.conf
    sudo sed -i "s@\# TLSPSKFile=@TLSPSKFile=/etc/zabbix/zabbix_agentd.psk@g" /etc/zabbix/zabbix_agentd.conf
}

function ufw_setting(){
    if [[ $q_indocker=="n" || $q_indocker=='N' ]]
    then
        sudo ufw allow proto tcp from $q_server_ip to any port 10050
    fi
}

function start(){
    if [[ $q_indocker=="y" || $q_indocker=='Y' ]]
    then
        sudo service zabbix-agent start
    else
        sudo systemctl enable zabbix-agent
        sudo systemctl start zabbix-agent
    fi
    echo -e "Goto Zabbix server webui and add this host. \n
    ========================
    client hostname: ${q_client_hostname}
    PSK Identity: ${q_psk_identity}
    PSK key: ${psk}
    ========================"
}


installer(){
    docker
    upgrade
    zabbix_client_install
    zabbix_client_setting
}

config_setting
config_show
installer
start
