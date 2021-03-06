#!/usr/bin/env bash
PATH=/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin:~/bin
export PATH

#Get Current folder
cur_dir=`pwd`
#Set file and url
libsodium_file="libsodium-1.0.16"
libsodium_url="https://github.com/jedisct1/libsodium/releases/download/1.0.16/libsodium-1.0.16.tar.gz"
mbedtls_file="mbedtls-2.6.0"
mbedtls_url="https://tls.mbed.org/download/mbedtls-2.6.0-gpl.tgz"
#Set Stream Ciphers
ciphers=(
aes-256-gcm
aes-256-ctr
aes-256-cfb
chacha20-ietf-poly1305
chacha20-ietf
chacha20
rc4-md5
)
#Set Color
red='\033[0;31m'
green='\033[0;32m'
yellow='\033[0;33m'
plain='\033[0m'
#Make sure run as root
[[ $EUID -ne 0 ]] && echo -e "[${red}Error${plain}] This script must be run as root!" && exit 1

#Disable selinux
disable_selinux(){
    if [ -s /etc/selinux/config ] && grep 'SELINUX=enforcing' /etc/selinux/config; then
        sed -i 's/SELINUX=enforcing/SELINUX=disabled/g' /etc/selinux/config
        setenforce 0
    fi
}
#Get ipv4
get_ip(){
    local IP=$( ip addr | egrep -o '[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}' | egrep -v "^192\.168|^172\.1[6-9]\.|^172\.2[0-9]\.|^172\.3[0-2]\.|^10\.|^127\.|^255\.|^0\." | head -n 1 )
    [ -z ${IP} ] && IP=$( wget -qO- -t1 -T2 ipv4.icanhazip.com )
    [ -z ${IP} ] && IP=$( wget -qO- -t1 -T2 ipinfo.io/ip )
    [ ! -z ${IP} ] && echo ${IP} || echo
}
#Get ipv6
get_ipv6(){
    local ipv6=$(wget -qO- -t1 -T2 ipv6.icanhazip.com)
    if [ -z ${ipv6} ]; then
        return 1
    else
        return 0
    fi
}
#Get char
get_char(){
    SAVEDSTTY=`stty -g`
    stty -echo
    stty cbreak
    dd if=/dev/tty bs=1 count=1 2> /dev/null
    stty -raw
    stty echo
    stty $SAVEDSTTY
}
#Get shadowsocks-libev lastest version
get_latest_version(){
    ver=$(wget --no-check-certificate -qO- https://api.github.com/repos/shadowsocks/shadowsocks-libev/releases/latest | grep 'tag_name' | cut -d\" -f4)
    [ -z ${ver} ] && echo "[${red}Error${plain}] Get shadowsocks-libev latest version failed!" && exit 1
    shadowsocks_libev_ver="shadowsocks-libev-$(echo ${ver} | sed -e 's/^[a-zA-Z]//g')"
    download_link="https://github.com/shadowsocks/shadowsocks-libev/releases/download/${ver}/${shadowsocks_libev_ver}.tar.gz"
    init_script_link="https://raw.githubusercontent.com/uxh/research/master/shadowsocks-libev"
}
#Check installed
check_installed(){
    if [ "$(command -v "$1")" ]; then
        return 0
    else
        return 1
    fi
}
#Compare version
check_version(){
    check_installed "ss-server"
    if [ $? -eq 0 ]; then
        installed_ver=$(ss-server -h | grep shadowsocks-libev | cut -d' ' -f2)
        return 0
    else
        return 1
    fi
}
#Print info
print_info(){
    clear
    echo "##############################################################"
    echo "# Desc: Auto Install Shadowsocks-libev Server for CentOS 6/7 #"
    echo "# Author: https://github.com/teddysun/shadowsocks_install    #"
    echo "# Modify: https://www.vultrcn.com                            #"
    echo "##############################################################"
    echo
}
#Check system
check_sys(){
    local checkType=$1
    local value=$2

    local release=''
    local systemPackage=''

    if [[ -f /etc/redhat-release ]]; then
        release="centos"
        systemPackage="yum"
    elif cat /etc/issue | grep -Eqi "debian"; then
        release="debian"
        systemPackage="apt"
    elif cat /etc/issue | grep -Eqi "ubuntu"; then
        release="ubuntu"
        systemPackage="apt"
    elif cat /etc/issue | grep -Eqi "centos|red hat|redhat"; then
        release="centos"
        systemPackage="yum"
    elif cat /proc/version | grep -Eqi "debian"; then
        release="debian"
        systemPackage="apt"
    elif cat /proc/version | grep -Eqi "ubuntu"; then
        release="ubuntu"
        systemPackage="apt"
    elif cat /proc/version | grep -Eqi "centos|red hat|redhat"; then
        release="centos"
        systemPackage="yum"
    fi

    if [[ ${checkType} == "sysRelease" ]]; then
        if [ "$value" == "$release" ]; then
            return 0
        else
            return 1
        fi
    elif [[ ${checkType} == "packageManager" ]]; then
        if [ "$value" == "$systemPackage" ]; then
            return 0
        else
            return 1
        fi
    fi
}
#Get version
getversion(){
    if [[ -s /etc/redhat-release ]]; then
        grep -oE  "[0-9.]+" /etc/redhat-release
    else
        grep -oE  "[0-9.]+" /etc/issue
    fi
}
#Get centos version
centosversion(){
    if check_sys sysRelease centos; then
        local code=$1
        local version="$(getversion)"
        local main_ver=${version%%.*}
        if [ "$main_ver" == "$code" ]; then
            return 0
        else
            return 1
        fi
    else
        return 1
    fi
}

version_ge(){
    test "$(echo "$@" | tr " " "\n" | sort -rV | head -n 1)" == "$1"
}
#autoconf version
autoconfversion(){
    if [ "$(command -v "autoconf")" ]; then
        local version=$(autoconf --version | grep autoconf | awk '{print $4}')
        if version_ge ${version} 2.67; then
            return 0
        else
            return 1
        fi
    else
        return 1
    fi
}
#Pre-installation settings
pre_install(){
    #Check os
    if check_sys sysRelease centos; then
        #Not support CentOS 5
        if centosversion 5; then
            echo -e "[${red}Error${plain}] Not support CentOS 5, please change to CentOS 6 or 7 and try again!"
            exit 1
        fi
    else
        echo -e "[${red}Error${plain}] Your OS is not supported to run it, please change OS to CentOS and try again!"
        exit 1
    fi
    #Check version
    check_version
    status=$?
    if [ ${status} -eq 0 ]; then
        echo -e "[${green}Info${plain}] ${installed_ver} has already been installed"
        exit 0
    elif [ ${status} -eq 1 ]; then
        print_info
        get_latest_version
    fi
    #Set shadowsocks password
    echo "Please set shadowsocks password"
    read -p "(Default: vultrcn.com):" shadowsockspwd
    [ -z "${shadowsockspwd}" ] && shadowsockspwd="vultrcn.com"
    echo "---------------------------"
    echo "password = ${shadowsockspwd}"
    echo "---------------------------"
    #Set shadowsocks port
    while true
    do
    dport=$(shuf -i 2999-9999 -n 1)
    echo -e "Please set shadowsocks port"
    read -p "(Default: ${dport}):" shadowsocksport
    [ -z "$shadowsocksport" ] && shadowsocksport=${dport}
    expr ${shadowsocksport} + 1 &>/dev/null
    if [ $? -eq 0 ]; then
        if [ ${shadowsocksport} -ge 1 ] && [ ${shadowsocksport} -le 65535 ] && [ ${shadowsocksport:0:1} != 0 ]; then
            echo "---------------------------"
            echo "port = ${shadowsocksport}"
            echo "---------------------------"
            break
        fi
    fi
    echo -e "[${red}Error${plain}] Please enter a number between 1 and 65535!"
    done
    #Set shadowsocks stream ciphers
    while true
    do
    echo -e "Please set shadowsocks stream cipher"
    for ((i=1;i<=${#ciphers[@]};i++ )); do
        hint="${ciphers[$i-1]}"
        echo -e "${green}${i}${plain}) ${hint}"
    done
    read -p "(Default: ${ciphers[0]}):" pick
    [ -z "$pick" ] && pick=1
    expr ${pick} + 1 &>/dev/null
    if [ $? -ne 0 ]; then
        echo -e "[${red}Error${plain}] Please enter a number!"
        continue
    fi
    if [[ "$pick" -lt 1 || "$pick" -gt ${#ciphers[@]} ]]; then
        echo -e "[${red}Error${plain}] Please enter a number between 1 and ${#ciphers[@]}"
        continue
    fi
    shadowsockscipher=${ciphers[$pick-1]}
    echo "---------------------------"
    echo "cipher = ${shadowsockscipher}"
    echo "---------------------------"
    break
    done

    echo
    echo "Press any key to start...or press Ctrl+C to cancel"
    char=`get_char`
    #Install necessary dependencies
    echo -e "[${green}Info${plain}] Checking the EPEL repository..."
    if [ ! -f /etc/yum.repos.d/epel.repo ]; then
        yum install -y -q epel-release
    fi
    [ ! -f /etc/yum.repos.d/epel.repo ] && echo -e "[${red}Error${plain}] Install EPEL repository failed, please check it." && exit 1
    [ ! "$(command -v yum-config-manager)" ] && yum install -y -q yum-utils
    if [ x"`yum-config-manager epel | grep -w enabled | awk '{print $3}'`" != x"True" ]; then
        yum-config-manager --enable epel
    fi
    echo -e "[${green}Info${plain}] Checking the EPEL repository complete..."
    yum install -y -q unzip openssl openssl-devel gettext gcc autoconf libtool automake make asciidoc xmlto libev-devel pcre pcre-devel git c-ares-devel
}
#Download file
download() {
    local filename=${1}
    local cur_dir=`pwd`
    if [ -s ${filename} ]; then
        echo -e "[${green}Info${plain}] ${filename} [found]"
    else
        echo -e "[${green}Info${plain}] ${filename} not found, download now..."
        wget --no-check-certificate -cq -t3 -T3 -O ${1} ${2}
        if [ $? -eq 0 ]; then
            echo -e "[${green}Info${plain}] ${filename} download completed"
        else
            echo -e "[${red}Error${plain}] Failed to download ${filename}, please download it manually and try again!"
            exit 1
        fi
    fi
}
#Download latest shadowsocks-libev
download_files(){
    cd ${cur_dir}
    download "${shadowsocks_libev_ver}.tar.gz" "${download_link}"
    download "${libsodium_file}.tar.gz" "${libsodium_url}"
    download "${mbedtls_file}-gpl.tgz" "${mbedtls_url}"
    download "/etc/init.d/shadowsocks" "${init_script_link}"
}
#Install libsodium
install_libsodium() {
    if [ ! -f /usr/lib/libsodium.a ]; then
        cd ${cur_dir}
        tar zxf ${libsodium_file}.tar.gz
        cd ${libsodium_file}
        ./configure --prefix=/usr && make && make install
        if [ $? -ne 0 ]; then
            echo -e "[${red}Error${plain}] ${libsodium_file} install failed!"
            exit 1
        fi
    else
        echo -e "[${green}Info${plain}] ${libsodium_file} already installed"
    fi
}
#Install mbedtls
install_mbedtls() {
    if [ ! -f /usr/lib/libmbedtls.a ]; then
        cd ${cur_dir}
        tar xf ${mbedtls_file}-gpl.tgz
        cd ${mbedtls_file}
        make SHARED=1 CFLAGS=-fPIC
        make DESTDIR=/usr install
        if [ $? -ne 0 ]; then
            echo -e "[${red}Error${plain}] ${mbedtls_file} install failed!"
            exit 1
        fi
    else
        echo -e "[${green}Info${plain}] ${mbedtls_file} already installed"
    fi
}
#Config shadowsocks
config_shadowsocks(){
    local server_value="\"0.0.0.0\""
    if get_ipv6; then
        server_value="[\"[::0]\",\"0.0.0.0\"]"
    fi

    if [ ! -d /etc/shadowsocks-libev ]; then
        mkdir -p /etc/shadowsocks-libev
    fi
    cat > /etc/shadowsocks-libev/config.json<<-EOF
{
    "server":${server_value},
    "server_port":${shadowsocksport},
    "local_address":"127.0.0.1",
    "local_port":1080,
    "password":"${shadowsockspwd}",
    "timeout":600,
    "method":"${shadowsockscipher}"
}
EOF
}
#Firewall set
firewall_set(){
    echo -e "[${green}Info${plain}] firewall set start..."
    if centosversion 6; then
        /etc/init.d/iptables status > /dev/null 2>&1
        if [ $? -eq 0 ]; then
            iptables -L -n | grep -i ${shadowsocksport} > /dev/null 2>&1
            if [ $? -ne 0 ]; then
                iptables -I INPUT -m state --state NEW -m tcp -p tcp --dport ${shadowsocksport} -j ACCEPT
                iptables -I INPUT -m state --state NEW -m udp -p udp --dport ${shadowsocksport} -j ACCEPT
                /etc/init.d/iptables save
                /etc/init.d/iptables restart
            else
                echo -e "[${green}Info${plain}] port ${shadowsocksport} has been set up"
            fi
        else
            echo -e "[${yellow}Warning${plain}] Iptables looks like shutdown or not installed, please manually set it if necessary!"
        fi
    elif centosversion 7; then
        systemctl status firewalld > /dev/null 2>&1
        if [ $? -eq 0 ]; then
            firewall-cmd --permanent --zone=public --add-port=${shadowsocksport}/tcp
            firewall-cmd --permanent --zone=public --add-port=${shadowsocksport}/udp
            firewall-cmd --reload
        else
            echo -e "[${yellow}Warning${plain}] Firewalld looks like not running or not installed, please enable port ${shadowsocksport} manually if necessary!"
        fi
    fi
    echo -e "[${green}Info${plain}] firewall set completed"
}
#Install shadowsocks-libev
install_shadowsocks(){
    install_libsodium
    install_mbedtls

    ldconfig
    cd ${cur_dir}
    tar zxf ${shadowsocks_libev_ver}.tar.gz
    cd ${shadowsocks_libev_ver}
    ./configure --disable-documentation
    make && make install
    if [ $? -eq 0 ]; then
        chmod +x /etc/init.d/shadowsocks
        chkconfig --add shadowsocks
        chkconfig shadowsocks on
        # Start shadowsocks
        /etc/init.d/shadowsocks start
        if [ $? -eq 0 ]; then
            echo -e "[${green}Info${plain}] Shadowsocks-libev start success"
        else
            echo -e "[${yellow}Warning${plain}] Shadowsocks-libev start failed!"
        fi
    else
        echo
        echo -e "[${red}Error${plain}] Shadowsocks-libev install failed!"
        exit 1
    fi

    cd ${cur_dir}
    rm -rf ${shadowsocks_libev_ver} ${shadowsocks_libev_ver}.tar.gz
    rm -rf ${libsodium_file} ${libsodium_file}.tar.gz
    rm -rf ${mbedtls_file} ${mbedtls_file}-gpl.tgz

    clear
    echo
    echo -e "Congratulations, shadowsocks-libev server install completed!"
    echo -e "Server IP        : ${red}$(get_ip)${plain}"
    echo -e "Server Port      : ${red}${shadowsocksport}${plain}"
    echo -e "Password         : ${red}${shadowsockspwd}${plain}"
    echo -e "Encryption Method: ${red}${shadowsockscipher}${plain}"
    echo
    echo -e "Please use shadowsocks client to connect!"
}
#Install shadowsocks-libev
install_shadowsocks_libev(){
    disable_selinux
    pre_install
    download_files
    config_shadowsocks
    firewall_set
    install_shadowsocks
}
#Uninstall shadowsocks-libev
uninstall_shadowsocks_libev(){
    clear
    print_info
    printf "Are you sure uninstall Shadowsocks-libev? (y/n)"
    printf "\n"
    read -p "(Default: n):" answer
    [ -z ${answer} ] && answer="n"

    if [ "${answer}" == "y" ] || [ "${answer}" == "Y" ]; then
        ps -ef | grep -v grep | grep -i "ss-server" > /dev/null 2>&1
        if [ $? -eq 0 ]; then
            /etc/init.d/shadowsocks stop
        fi
        chkconfig --del shadowsocks
        rm -fr /etc/shadowsocks-libev
        rm -f /usr/local/bin/ss-local
        rm -f /usr/local/bin/ss-tunnel
        rm -f /usr/local/bin/ss-server
        rm -f /usr/local/bin/ss-manager
        rm -f /usr/local/bin/ss-redir
        rm -f /usr/local/bin/ss-nat
        rm -f /usr/local/lib/libshadowsocks-libev.a
        rm -f /usr/local/lib/libshadowsocks-libev.la
        rm -f /usr/local/include/shadowsocks.h
        rm -f /usr/local/lib/pkgconfig/shadowsocks-libev.pc
        rm -f /usr/local/share/man/man1/ss-local.1
        rm -f /usr/local/share/man/man1/ss-tunnel.1
        rm -f /usr/local/share/man/man1/ss-server.1
        rm -f /usr/local/share/man/man1/ss-manager.1
        rm -f /usr/local/share/man/man1/ss-redir.1
        rm -f /usr/local/share/man/man1/ss-nat.1
        rm -f /usr/local/share/man/man8/shadowsocks-libev.8
        rm -fr /usr/local/share/doc/shadowsocks-libev
        rm -f /etc/init.d/shadowsocks
        echo "Shadowsocks-libev uninstall success!"
    else
        echo
        echo "uninstall cancelled, nothing to do..."
        echo
    fi
}

# Initialization step
action=$1
[ -z $1 ] && action=install
case "$action" in
    install|uninstall)
        ${action}_shadowsocks_libev
        ;;
    *)
        echo "Arguments error! [${action}]"
        echo "Usage: `basename $0` [install|uninstall]"
        ;;
esac
